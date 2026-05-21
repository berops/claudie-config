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

    data "ovh_cloud_project_image" "image_{{ $resourceSuffix }}_{{ $nodepool.Name }}" {
      provider     = ovh.nodepool_{{ $resourceSuffix }}
      service_name = "{{ $serviceName }}"
      region       = "{{ $nodepool.Details.Region }}"
      name         = "{{ $nodepool.Details.Image }}"
    }

    data "ovh_cloud_project_flavor" "flavor_{{ $resourceSuffix }}_{{ $nodepool.Name }}" {
      provider     = ovh.nodepool_{{ $resourceSuffix }}
      service_name = "{{ $serviceName }}"
      region       = "{{ $nodepool.Details.Region }}"
      name         = "{{ $nodepool.Details.ServerType }}"
    }

    resource "ovh_cloud_project_sshkey" "{{ $sshKeyResourceName }}" {
      provider     = ovh.nodepool_{{ $resourceSuffix }}
      service_name = "{{ $serviceName }}"
      name         = "{{ $sshKeyName }}"
      public_key   = file("./{{ $nodepool.Name }}")
    }

    {{- range $node := $nodepool.Nodes }}

        {{- $serverResourceName           := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $volumeResourceName           := printf "%s_%s_volume" $node.Name $resourceSuffix }}
        {{- $volumeAttachResourceName     := printf "%s_att" $volumeResourceName }}

        resource "ovh_cloud_project_instance" "{{ $serverResourceName }}" {
          provider       = ovh.nodepool_{{ $resourceSuffix }}
          service_name   = "{{ $serviceName }}"
          region         = "{{ $nodepool.Details.Region }}"
          billing_period = "hourly"
          name           = "{{ $node.Name }}"

          boot_from {
            image_id = data.ovh_cloud_project_image.image_{{ $resourceSuffix }}_{{ $nodepool.Name }}.id
          }

          flavor {
            flavor_id = data.ovh_cloud_project_flavor.flavor_{{ $resourceSuffix }}_{{ $nodepool.Name }}.id
          }

          ssh_key {
            name = ovh_cloud_project_sshkey.{{ $sshKeyResourceName }}.name
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
# Create longhorn volume directory
mkdir -p /opt/claudie/data

    {{- if $isWorkerNodeWithDiskAttached }}

# Mount the Cinder volume.
# OVH Public Cloud volumes appear under /dev/disk/by-id/ with a virtio- prefix
# whose serial matches the first 20 characters of the volume UUID (no dashes).
VOL_ID="${ovh_cloud_project_volume.{{ $volumeResourceName }}.id}"
SERIAL=$(echo "$VOL_ID" | tr -d '-' | cut -c1-20)
for i in $(seq 1 60); do
    if [ -e "/dev/disk/by-id/virtio-$SERIAL" ]; then
        break
    fi
    sleep 1
done
disk=$(readlink -f "/dev/disk/by-id/virtio-$SERIAL" 2>/dev/null || true)
if [ -n "$disk" ] && [ -b "$disk" ]; then
    if ! blkid "$disk" | grep -q 'TYPE="xfs"'; then
        mkfs.xfs "$disk"
    fi
    if ! grep -qs "$disk" /proc/mounts; then
        mount "$disk" /opt/claudie/data
        echo "$disk /opt/claudie/data xfs defaults 0 0" >> /etc/fstab
    fi
fi
    {{- end }}
{{- end }}
EOF
        }

        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}

            {{- $volumeName := printf "%sd" $node.Name }}

            resource "ovh_cloud_project_volume" "{{ $volumeResourceName }}" {
              provider     = ovh.nodepool_{{ $resourceSuffix }}
              service_name = "{{ $serviceName }}"
              region_name  = "{{ $nodepool.Details.Region }}"
              name         = "{{ $volumeName }}"
              size         = {{ $nodepool.Details.StorageDiskSize }}
              type         = "classic"
            }

            resource "ovh_cloud_project_volume_attached" "{{ $volumeAttachResourceName }}" {
              provider     = ovh.nodepool_{{ $resourceSuffix }}
              service_name = "{{ $serviceName }}"
              region_name  = "{{ $nodepool.Details.Region }}"
              volume_id    = ovh_cloud_project_volume.{{ $volumeResourceName }}.id
              instance_id  = ovh_cloud_project_instance.{{ $serverResourceName }}.id
            }

            {{- end }}
        {{- end }}

    {{- end }}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        "{{ $node.Name }}" = [
          [for addr in ovh_cloud_project_instance.{{ $serverResourceName }}.addresses : addr.ip if addr.version == 4 && addr.type == "public"][0],
          tostring(local.claudie_ssh_port_{{ $resourceSuffix }})
        ]
    {{- end }}
  }
}
{{- end }}
