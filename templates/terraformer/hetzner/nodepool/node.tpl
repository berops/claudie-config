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

    resource "hcloud_ssh_key" "{{ $sshKeyResourceName }}" {
      provider   = hcloud.nodepool_{{ $resourceSuffix }}
      name       = "{{ $sshKeyName }}"
      public_key = file("./{{ $nodepool.Name }}")

      labels = {
        "managed-by"      : "Claudie"
        "claudie-cluster" : "{{ $clusterName }}-{{ $clusterHash }}"
      }
    }

    {{- range $node := $nodepool.Nodes }}

        {{- $serverResourceName           := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $firewallResourceName         := printf "firewall_%s" $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $volumeResourceName           := printf "%s_%s_volume" $node.Name $resourceSuffix }}

        resource "hcloud_server" "{{ $serverResourceName }}" {
          provider      = hcloud.nodepool_{{ $resourceSuffix }}
          name          = "{{ $node.Name }}"
          server_type   = "{{ $nodepool.Details.ServerType }}"
          image         = "{{ $nodepool.Details.Image }}"
          firewall_ids  = [ hcloud_firewall.{{ $firewallResourceName }}.id ]
          location      = "{{ $nodepool.Details.Region }}"
          public_net {
             ipv6_enabled = false
          }
          ssh_keys = [
            hcloud_ssh_key.{{ $sshKeyResourceName }}.id,
          ]
          labels = {
            "managed-by"      : "Claudie"
            "claudie-cluster" : "{{ $clusterName }}-{{ $clusterHash }}"
          }

          user_data = <<EOF
#!/bin/bash
# Configure SSH port
echo "Port ${local.claudie_ssh_port_{{ $resourceSuffix }}}" >> /etc/ssh/sshd_config
mkdir -p /etc/systemd/system/ssh.socket.d
cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:${local.claudie_ssh_port_{{ $resourceSuffix }}}
SSHEOF
systemctl daemon-reload
systemctl restart ssh.socket
        {{- if $isKubernetesCluster }}
# Create longhorn volume directory
mkdir -p /opt/claudie/data

            {{- /* Only Mount disk for Worker nodes that have a non-zero requested disk size */}}
            {{- if $isWorkerNodeWithDiskAttached }}

# Mount volume only when not mounted yet
sleep 50
disk=$(ls -l /dev/disk/by-id | grep "${hcloud_volume.{{ $volumeResourceName }}.id}" | awk '{print $NF}')
disk=$(basename "$disk")
if ! grep -qs "/dev/$disk" /proc/mounts; then

  if ! blkid /dev/$disk | grep -q "TYPE=\"xfs\""; then
    mkfs.xfs /dev/$disk
  fi
  mount /dev/$disk /opt/claudie/data
  echo "/dev/$disk /opt/claudie/data xfs defaults 0 0" >> /etc/fstab
fi

            {{- end }}
        {{- end }}
EOF
        }

        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}

            {{- $volumeName                   := printf "%sd" $node.Name }}
            {{- $volumeAttachmentResourceName := printf "%s_att" $volumeResourceName }}

            resource "hcloud_volume" "{{ $volumeResourceName }}" {
              provider  = hcloud.nodepool_{{ $resourceSuffix }}
              name      = "{{ $volumeName }}"
              size      = {{ $nodepool.Details.StorageDiskSize }}
              format    = "xfs"
              location = "{{ $nodepool.Details.Region }}"
            }

            resource "hcloud_volume_attachment" "{{ $volumeResourceName }}_att" {
              provider  = hcloud.nodepool_{{ $resourceSuffix }}
              volume_id = hcloud_volume.{{ $volumeResourceName }}.id
              server_id = hcloud_server.{{ $serverResourceName }}.id
              automount = false
            }

            {{- end }}
        {{- end }}

    {{- end }}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        "${hcloud_server.{{ $serverResourceName }}.name}" = [hcloud_server.{{ $serverResourceName }}.ipv4_address, tostring(local.claudie_ssh_port_{{ $resourceSuffix }})]
    {{- end }}
  }
}
{{- end }}
