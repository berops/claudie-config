{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $nodepool := .Data.NodePools }}

{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $serviceName    := $nodepool.Details.Provider.GetOvh.ServiceName }}
{{- $resourceSuffix := printf "%s_%s" $specName $uniqueFingerPrint }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName         := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

    # The OVH provider v2.x has no by-name data source for images or flavors.
    # The InputManifest's `image` and `serverType` fields therefore must be
    # OVH UUIDs (image_id and flavor_id), not human-readable names. Look them
    # up once via the OVH CLI or API for your project and region:
    #   ovhcloud cloud project flavor list --service-name <project-id> --region <region>
    #   ovhcloud cloud project image list  --service-name <project-id> --region <region>
    resource "ovh_cloud_project_ssh_key" "{{ $sshKeyResourceName }}" {
      provider     = ovh.nodepool_{{ $resourceSuffix }}
      service_name = "{{ $serviceName }}"
      name         = "{{ $sshKeyName }}"
      public_key   = file("./{{ $nodepool.Name }}")
    }

    {{- range $node := $nodepool.Nodes }}

        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}

        resource "ovh_cloud_project_instance" "{{ $serverResourceName }}" {
          provider       = ovh.nodepool_{{ $resourceSuffix }}
          service_name   = "{{ $serviceName }}"
          region         = "{{ $nodepool.Details.Region }}"
{{- if $nodepool.Details.Zone }}
          availability_zone = "{{ $nodepool.Details.Zone }}"
{{- end }}
          billing_period = "hourly"
          name           = "{{ $node.Name }}"

          boot_from {
            image_id = "{{ $nodepool.Details.Image }}"
          }

          flavor {
            flavor_id = "{{ $nodepool.Details.ServerType }}"
          }

          ssh_key {
            name = ovh_cloud_project_ssh_key.{{ $sshKeyResourceName }}.name
          }

          network {
            public = true
          }

          user_data = <<-EOF
#!/bin/bash
# Enable root SSH access
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
if [ -f /home/debian/.ssh/authorized_keys ]; then
    cp /home/debian/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Configure SSH port
echo "Port ${local.claudie_ssh_port_{{ $resourceSuffix }}}" >> /etc/ssh/sshd_config
mkdir -p /etc/systemd/system/ssh.socket.d
cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:${local.claudie_ssh_port_{{ $resourceSuffix }}}
SSHEOF
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

# Configure iptables firewall (not UFW, KubeOne disables UFW)
${local.ovh_firewall_script_{{ $resourceSuffix }}}

{{- if $isKubernetesCluster }}
# Create longhorn volume directory on the OS disk.
# Note: v1 of the OVH provider integration does not attach a separate Cinder
# volume (the OVH provider exposes no Terraform resource to attach an existing
# volume to a running instance). Storage lives on the OS disk for now.
mkdir -p /opt/claudie/data
{{- end }}
EOF
        }

    {{- end }}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        "{{ $node.Name }}" = [
          [for addr in ovh_cloud_project_instance.{{ $serverResourceName }}.addresses : addr.ip if addr.version == 4][0],
          tostring(local.claudie_ssh_port_{{ $resourceSuffix }})
        ]
    {{- end }}
  }
}
{{- end }}
