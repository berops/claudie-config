{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $i, $nodepool := .NodePools }}

{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

    {{- range $node := $nodepool.Nodes }}

        {{- $coreInstanceResourceName     := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $coreSubnetResourceName       := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
        {{- $varCompartmentID             := printf "default_compartment_id_%s" $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $varStorageDiskName           := printf "oci_storage_disk_name_%s" $resourceSuffix }}

        resource "oci_core_instance" "{{ $coreInstanceResourceName }}" {
          provider            = oci.nodepool_{{ $resourceSuffix }}
          compartment_id      = var.{{ $varCompartmentID }}
          availability_domain = "{{ $nodepool.Details.Zone }}"
          shape               = "{{ $nodepool.Details.ServerType }}"
          display_name        = "{{ $node.Name }}"

        {{if $nodepool.Details.MachineSpec}}
           shape_config {
               memory_in_gbs = {{ $nodepool.Details.MachineSpec.Memory }}
               ocpus = {{ $nodepool.Details.MachineSpec.CpuCount }}
           }
        {{end}}

          create_vnic_details {
            assign_public_ip  = true
            subnet_id         = oci_core_subnet.{{ $coreSubnetResourceName }}_subnet.id
          }

          freeform_tags = {
            "Managed-by"      = "Claudie"
            "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
          }

        {{- if $isLoadbalancerCluster }}
          source_details {
            source_id               = "{{ $nodepool.NodePool.Image }}"
            source_type             = "image"
            boot_volume_size_in_gbs = "50"
          }

          metadata = {
              ssh_authorized_keys = file("./{{ $nodepool.Name }}")
              user_data = base64encode(<<EOF
#cloud-config
runcmd:
  # Allow Claudie to ssh as root
  - sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
  - cat /root/.ssh/temp > /root/.ssh/authorized_keys
  - rm /root/.ssh/temp
  - echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config && service sshd restart
  # Disable iptables
  # Accept all traffic to avoid ssh lockdown via iptables firewall rules
  - iptables -P INPUT ACCEPT
  - iptables -P FORWARD ACCEPT
  - iptables -P OUTPUT ACCEPT
  # Flush and cleanup
  - iptables -F
  - iptables -X
  - iptables -Z
  # Make changes persistent
  - netfilter-persistent save
EOF
              )
          }
        {{- end }}

        {{- if $isKubernetesCluster }}
          source_details {
            source_id               = "{{ $nodepool.Details.Image }}"
            source_type             = "image"
            boot_volume_size_in_gbs = "100"
          }

          metadata = {
              ssh_authorized_keys = file("./{{ $nodepool.Name }}")
              user_data = base64encode(<<EOF
loud-config
ncmd:
# Allow Claudie to ssh as root
- sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
- cat /root/.ssh/temp > /root/.ssh/authorized_keys
- rm /root/.ssh/temp
- echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config && service sshd restart
# Disable iptables
# Accept all traffic to avoid ssh lockdown via iptables firewall rules
- iptables -P INPUT ACCEPT
- iptables -P FORWARD ACCEPT
- iptables -P OUTPUT ACCEPT
# Flush and cleanup
- iptables -F
- iptables -X
- iptables -Z
# Make changes persistent
- netfilter-persistent save
# Create longhorn volume directory
- mkdir -p /opt/claudie/data

                {{- if $isWorkerNodeWithDiskAttached }}

# Mount volume
- |
  sleep 50
  disk=$(ls -l /dev/oracleoci | grep "${var.{{ $varStorageDiskName }}}" | awk '{print $NF}')
  disk=$(basename "$disk")
  if ! grep -qs "/dev/$disk" /proc/mounts; then
    if ! blkid /dev/$disk | grep -q "TYPE=\"xfs\""; then
      mkfs.xfs /dev/$disk
    fi
    mount /dev/$disk /opt/claudie/data
    echo "/dev/$disk /opt/claudie/data xfs defaults 0 0" >> /etc/fstab
  fi

                {{- end }}

EOF

              )
          }
        {{- end }}
        }

        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}


            {{- $coreVolumeResourceName          := printf "%s_%s_volume" $node.Name $resourceSuffix }}
            {{- $coreVolumeName                  := printf "%sd" $node.Name }}
            {{- $coreAttachedDiskResourceName    := printf "%s_%s_volume_att" $node.Name $resourceSuffix }}
            {{- $coreAttachedDiskName            := printf "att-%s" $node.Name }}

            resource "oci_core_volume" "{{ $coreVolumeResourceName }}" {
              provider            = oci.nodepool_{{ $resourceSuffix }}
              compartment_id      = var.{{ $varCompartmentID }}
              availability_domain = "{{ $nodepool.Details.Zone }}"
              size_in_gbs         = "{{ $nodepool.Details.StorageDiskSize }}"
              display_name        = "{{ $coreVolumeName }}"
              vpus_per_gb         = 10

              freeform_tags = {
                "Managed-by"      = "Claudie"
                "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
              }
            }

            resource "oci_core_volume_attachment" "{{ $coreAttachedDiskResourceName }}" {
              provider        = oci.nodepool_{{ $resourceSuffix }}
              attachment_type = "paravirtualized"
              instance_id     = oci_core_instance.{{ $coreInstanceResourceName }}.id
              volume_id       = oci_core_volume.{{ $coreVolumeResourceName }}.id
              display_name    = "{{ $coreAttachedDiskName }}"
              device          = "/dev/oracleoci/${var.{{ $varStorageDiskName }}}"
            }

            {{- end }}
        {{- end }}

{{- end }}

output "{{ $nodepool.Name }}_{{ $uniqueFingerPrint }}" {
  value = {
  {{- range $node := $nodepool.Nodes }}
        {{- $coreInstanceResourceName     := printf "%s_%s" $node.Name $resourceSuffix }}
        "${oci_core_instance.{{ $coreInstanceResourceName }}.display_name}" = oci_core_instance.{{ $coreInstanceResourceName }}.public_ip
  {{- end }}
  }
}
{{- end }}
