{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- $nodepool       := .Data.NodePool }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $networking     := .Data.Networking.All }}
{{- $claudieSshPort := index $networking (printf "claudie_ssh_port_%s" $resourceSuffix) }}
{{- $firewallScript := index $networking (printf "verda_firewall_script_%s" $resourceSuffix) }}

{{- if not $claudieSshPort }}{{ template "node.tpl: missing output 'claudie_ssh_port_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $firewallScript }}{{ template "node.tpl: missing output 'verda_firewall_script_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName         := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

{{- /* Size in GB of the OS volume Verda creates when none is requested. */}}
{{- $defaultOsVolumeSize := 50 }}

resource "verda_ssh_key" "{{ $sshKeyResourceName }}" {
  provider   = verda.nodepool_{{ $resourceSuffix }}
  name       = "{{ $sshKeyName }}"
  public_key = file("./{{ $nodepool.Name }}")
}

{{- range $node := $nodepool.Nodes }}

{{- $instanceResourceName      := printf "%s_%s" $node.Name $resourceSuffix }}
{{- $startupScriptResourceName := printf "startup_%s_%s" $node.Name $resourceSuffix }}
{{- $startupScriptName         := printf "startup-%s-%s" $node.Name $clusterHash }}
{{- $osVolumeName              := printf "os-%s-%s" $node.Name $clusterHash }}
{{- $osVolumeSize              := add $defaultOsVolumeSize $nodepool.Details.StorageDiskSize }}

resource "verda_startup_script" "{{ $startupScriptResourceName }}" {
  provider = verda.nodepool_{{ $resourceSuffix }}
  name     = "{{ $startupScriptName }}"
  script   = <<-SCRIPT
#!/bin/bash
# Enable root SSH access
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'PubkeyAcceptedKeyTypes=+ssh-rsa' >> /etc/ssh/sshd_config
# Configure custom SSH port (Claudie convention)
echo "Port {{ $claudieSshPort }}" >> /etc/ssh/sshd_config
mkdir -p /etc/systemd/system/ssh.socket.d
cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:{{ $claudieSshPort }}
SSHEOF
systemctl daemon-reload
systemctl restart ssh.socket
sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
ssh_active=$(systemctl is-active ssh 2>/dev/null || true)
if [ "$sshd_active" = "active" ]; then
    systemctl restart sshd
fi
if [ "$ssh_active" = "active" ]; then
    systemctl restart ssh
fi

# Configure iptables firewall (not UFW, KubeOne disables UFW)
{{ $firewallScript }}
{{- if $isKubernetesCluster }}

# Create longhorn volume directory
mkdir -p /opt/claudie/data
{{- end }}{{/* if $isKubernetesCluster */}}
SCRIPT
}

resource "verda_instance" "{{ $instanceResourceName }}" {
  provider          = verda.nodepool_{{ $resourceSuffix }}
  instance_type     = "{{ $nodepool.Details.ServerType }}"
  image             = "{{ $nodepool.Details.Image }}"
  hostname          = "{{ $node.Name }}"
  description       = "Claudie {{ $clusterName }}-{{ $clusterHash }}"
  location          = "{{ $nodepool.Details.Region }}"
  ssh_key_ids       = [verda_ssh_key.{{ $sshKeyResourceName }}.id]
  startup_script_id = verda_startup_script.{{ $startupScriptResourceName }}.id

  {{- if $nodepool.Details.Spot }}
  is_spot = true
  {{- end }}

  # Longhorn data lives on the OS volume (default size + storageDiskSize), because a
  # standalone verda_volume stays in Verda's trash and quota for 96 hours once deleted.
  # Ref: https://github.com/berops/claudie-config/issues/56
  os_volume = {
    name                = "{{ $osVolumeName }}"
    size                = {{ $osVolumeSize }}
    type                = "NVMe"
    on_destroy          = "delete_permanently"
    on_spot_discontinue = "delete_permanently"
  }
}

{{- end }}{{/* range $nodepool.Nodes */}}

# WORKAROUND: verda-cloud/terraform-provider-verda returns from verda_instance.Create
# before Verda assigns the public IP, leaving verda_instance.<n>.ip null in stored
# state for the rest of the apply. We re-fetch the IP via data.http after a wall-clock
# wait. Remove this block once the upstream provider patches Create to call
# waitForInstanceIP.
#
# Security note: data.http stores request_body and response_body in Terraform state,
# so the client_secret read via file() and the access_token returned by Verda end
# up in the cluster state file. Acceptable for now because Claudie stores state in
# MinIO with encryption-at-rest, and the workaround is temporary.
{{- $verdaBaseUrl := default "https://api.verda.com/v1" $nodepool.Details.Provider.GetVerda.GetBaseUrl }}

resource "time_sleep" "wait_for_ips_{{ $nodepool.Name }}_{{ $resourceSuffix }}" {
  depends_on = [
    {{- range $node := $nodepool.Nodes }}
    {{- $instanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
    verda_instance.{{ $instanceResourceName }},
    {{- end }}
  ]
  create_duration = "120s"
}

data "http" "verda_token_{{ $nodepool.Name }}_{{ $resourceSuffix }}" {
  depends_on = [time_sleep.wait_for_ips_{{ $nodepool.Name }}_{{ $resourceSuffix }}]
  url        = "{{ $verdaBaseUrl }}/oauth2/token"
  method     = "POST"
  request_headers = {
    "Content-Type" = "application/x-www-form-urlencoded"
    "user-agent"   = ""
  }
  request_body = "grant_type=client_credentials&client_id={{ $nodepool.Details.Provider.GetVerda.ClientId }}&client_secret=${file("./{{ $specName }}")}&scope=cloud-api-v1"
}

{{- range $node := $nodepool.Nodes }}
{{- $instanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}

data "http" "ip_{{ $instanceResourceName }}" {
  url    = "{{ $verdaBaseUrl }}/instances/${verda_instance.{{ $instanceResourceName }}.id}"
  method = "GET"
  request_headers = {
    "Authorization" = "Bearer ${jsondecode(data.http.verda_token_{{ $nodepool.Name }}_{{ $resourceSuffix }}.response_body).access_token}"
    "user-agent"    = ""
  }
  lifecycle {
    postcondition {
      condition     = jsondecode(self.response_body).ip != null && jsondecode(self.response_body).ip != ""
      error_message = "Verda did not assign IP within wait window for instance ${verda_instance.{{ $instanceResourceName }}.id}"
    }
  }
}

{{- end }}{{/* range $nodepool.Nodes */}}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
    {{- $instanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
    "{{ $node.Name }}" = [
      jsondecode(data.http.ip_{{ $instanceResourceName }}.response_body).ip,
      "{{ $claudieSshPort }}",
    ]
    {{- end }}
  }
}
