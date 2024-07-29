{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $nodepool := .Data.NodePools }}

{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}


{{- $sshKeyResourceName  := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName          := printf "key-%s-%s-%s-%s" $nodepool.Name $clusterHash $region $specName }}

resource "genesiscloud_ssh_key" "{{ $sshKeyResourceName }}" {
  provider   = genesiscloud.nodepool_{{ $resourceSuffix }}
  name       = "{{ $sshKeyName }}"
  public_key = file("./{{ $nodepool.Name }}")
}

    {{- range $node := $nodepool.Nodes }}

        {{- $volumeResourceName           := printf "%s_%s_volume" $node.Name $resourceSuffix }}
        {{- $volumeName                   := printf "%sd" $node.Name }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $instanceResourceName         := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $securityGroupResourceName    := printf "claudie_security_group_%s" $resourceSuffix }}

        {{- if and ($isKubernetesCluster) ($isWorkerNodeWithDiskAttached) }}
            resource "genesiscloud_volume" "{{ $volumeResourceName }}" {
              provider = genesiscloud.nodepool_{{ $resourceSuffix }}
              name   = "{{ $volumeName }}"
              region = "{{ $region }}"
              size   = {{ $nodepool.NodePool.StorageDiskSize}}
              type   = "hdd"
            }
        {{- end }}

        resource "genesiscloud_instance" "{{ $instanceResourceName }}" {
          provider = genesiscloud.nodepool_{{ $resourceSuffix }}
          name   = "{{ $node.Name }}"
          region = "{{ $region }}"

          image_id = data.genesiscloud_images.base_os_{{ $resourceSuffix }}.images[index(data.genesiscloud_images.base_os_{{ $resourceSuffix }}.images.*.name, "{{ $nodepool.NodePool.Image}}")].id
          type     = "{{ $nodepool.NodePool.ServerType }}"

          public_ip_type = "static"

        {{- if and ($isKubernetesCluster) ($isWorkerNodeWithDiskAttached) }}
          volume_ids = [
            genesiscloud_volume.{{ $volumeResourceName }}.id
          ]
        {{- end }}

          ssh_key_ids = [
            genesiscloud_ssh_key.{{ $sshKeyResourceName }}.id,
          ]

          security_group_ids = [
            genesiscloud_security_group.{{ $securityGroupResourceName }}.id
          ]

          {{- if $isLoadbalancerCluster }}
              metadata = {
                startup_script = <<EOF
#!/bin/bash
set -eo pipefail
sudo sed -i -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && service sshd restart
EOF
              }
          {{- end }}

          {{- if $isKubernetesCluster }}
              metadata = {
                startup_script = <<EOF
#!/bin/bash
set -eo pipefail

# Allow ssh as root
sudo sed -i -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && service sshd restart

# startup script
mkdir -p /opt/claudie/data
            {{- if $isWorkerNodeWithDiskAttached }}
sleep 30
# The IDs listed by `/dev/disk/by-id` are different then the volume ids assigned by genesis cloud.
# This is a hacky way assuming that only the longhorn volume will be mounted at startup and no other volume
longhorn_diskuuid=$(blkid | grep genesis_cloud | grep -oP 'UUID="\K[^"]+')
disk=$(ls -l /dev/disk/by-uuid/ | grep $longhorn_diskuuid | awk '{print $NF}')
disk=$(basename "$disk")

# The volume is automatically mounted, since we want it for longhorn specifically we have to re-mount the volume under /opt/claudie/data.
umount -l /dev/$disk

if ! grep -qs "/dev/$disk" /proc/mounts; then
  if ! blkid /dev/$disk | grep -q "TYPE=\"xfs\""; then
    mkfs.xfs -f /dev/$disk
  fi
  mount /dev/$disk /opt/claudie/data
  echo "/dev/$disk /opt/claudie/data xfs defaults 0 0" >> /etc/fstab
fi
            {{- end }}
EOF
          }
          {{- end }}
        }
    {{- end }}

output "{{ $nodepool.Name }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
    "${genesiscloud_instance.{{ $instanceResourceName }}.name}" = genesiscloud_instance.{{ $instanceResourceName }}.public_ip
    {{- end }}
  }
}
{{- end }}
