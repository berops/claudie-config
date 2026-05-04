{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $nodepool := .Data.NodePools }}

{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s" $specName $uniqueFingerPrint }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName         := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

    resource "verda_ssh_key" "{{ $sshKeyResourceName }}" {
      provider   = verda.nodepool_{{ $resourceSuffix }}
      name       = "{{ $sshKeyName }}"
      public_key = file("./{{ $nodepool.Name }}")
    }

    {{- range $node := $nodepool.Nodes }}

        {{- $instanceResourceName        := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $startupScriptResourceName   := printf "startup_%s_%s" $node.Name $resourceSuffix }}
        {{- $startupScriptName           := printf "startup-%s-%s" $node.Name $clusterHash }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $volumeResourceName          := printf "%s_%s_volume" $node.Name $resourceSuffix }}
        {{- $volumeName                  := printf "vol-%s-%s" $node.Name $clusterHash }}

        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}

            resource "verda_volume" "{{ $volumeResourceName }}" {
              provider = verda.nodepool_{{ $resourceSuffix }}
              name     = "{{ $volumeName }}"
              size     = {{ $nodepool.Details.StorageDiskSize }}
              type     = "NVMe"
              location = "{{ $nodepool.Details.Region }}"
            }

            {{- end }}
        {{- end }}

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
echo "Port ${local.claudie_ssh_port_{{ $resourceSuffix }}}" >> /etc/ssh/sshd_config
mkdir -p /etc/systemd/system/ssh.socket.d
cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:${local.claudie_ssh_port_{{ $resourceSuffix }}}
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
${local.verda_firewall_script_{{ $resourceSuffix }}}

{{- if $isKubernetesCluster }}

# Create longhorn volume directory
mkdir -p /opt/claudie/data

  {{- if $isWorkerNodeWithDiskAttached }}

# Mount attached volume only when not mounted yet
sleep 50
disk=$(ls -l /dev/disk/by-id | grep "${verda_volume.{{ $volumeResourceName }}.id}" | awk '{print $NF}')
disk=$(basename "$disk")
if [ -n "$disk" ] && ! grep -qs "/dev/$disk" /proc/mounts; then
  if ! blkid /dev/$disk | grep -q 'TYPE="xfs"'; then
    mkfs.xfs /dev/$disk
  fi
  mount /dev/$disk /opt/claudie/data
  echo "/dev/$disk /opt/claudie/data xfs defaults 0 0" >> /etc/fstab
fi

  {{- end }}
{{- end }}
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

        {{- if and $isKubernetesCluster $isWorkerNodeWithDiskAttached }}
          existing_volumes = [verda_volume.{{ $volumeResourceName }}.id]
        {{- end }}
        }

    {{- end }}

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
  create_duration = "30s"
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

    {{- end }}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $instanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        "{{ $node.Name }}" = [
          jsondecode(data.http.ip_{{ $instanceResourceName }}.response_body).ip,
          tostring(local.claudie_ssh_port_{{ $resourceSuffix }}),
        ]
    {{- end }}
  }
}
{{- end }}
