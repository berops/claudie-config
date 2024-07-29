{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $_, $nodepool := .Data.NodePools }}

{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

    {{- range $node := $nodepool.Nodes }}

        {{- $computeInstanceResourceName  := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $computeSubnetResourceName    := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
        {{- $varStorageDiskName           := printf "gcp_storage_disk_name_%s" $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}

        resource "google_compute_instance" "{{ $computeInstanceResourceName}}" {
          provider                  = google.nodepool_{{ $resourceSuffix }}
          zone                      = "{{ $nodepool.Details.Zone }}"
          name                      = "{{ $node.Name }}"
          machine_type              = "{{ $nodepool.Details.ServerType }}"
          description   = "Managed by Claudie for cluster {{ $clusterName }}-{{ $clusterHash }}"
          allow_stopping_for_update = true

          network_interface {
            subnetwork = google_compute_subnetwork.{{ $computeSubnetResourceName }}.self_link
            access_config {}
          }

          metadata = {
            ssh-keys = "root:${file("./{{ $nodepool.Name }}")}"
          }

          labels = {
            managed-by = "claudie"
            claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }

        {{- if $isLoadbalancerCluster }}
            boot_disk {
              initialize_params {
                size = "50"
                image = "{{ $nodepool.Details.Image }}"
              }
            }
            metadata_startup_script = "echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && service sshd restart"
        {{- end }}

        {{- if $isKubernetesCluster }}
            boot_disk {
              initialize_params {
                size = "100"
                image = "{{ $nodepool.Details.Image }}"
              }
            }

            metadata_startup_script = <<EOF
#!/bin/bash
set -euxo pipefail
# Allow ssh as root
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && service sshd restart
# Create longhorn volume directory
mkdir -p /opt/claudie/data

            {{- /* Only Mount disk for Worker nodes that have a non-zero requested disk size */}}
            {{- if $isWorkerNodeWithDiskAttached }}

# Mount managed disk only when not mounted yet
sleep 50
disk=$(ls -l /dev/disk/by-id | grep "google-${var.{{ $varStorageDiskName }}}" | awk '{print $NF}')
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

           {{- if $isWorkerNodeWithDiskAttached }}
               # As the storage disk is attached via google_compute_attached_disk,
               # we must ignore attached_disk property.
               lifecycle {
                 ignore_changes = [attached_disk]
               }
           {{- end }}
        {{- end }}
        }

        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}

            {{- $computeDiskResourceName          := printf "%s_%s_disk" $node.Name $resourceSuffix }}
            {{- $computeDiskName                  := printf "%sd" $node.Name }}
            {{- $computeAttachedDiskResourceName  := printf "%s_%s_disk_att" $node.Name $resourceSuffix }}

            resource "google_compute_disk" "{{ $computeDiskResourceName }}" {
              provider = google.nodepool_{{ $resourceSuffix }}
              # suffix 'd' as otherwise the creation of the VM instance and attachment of the disk will fail, if having the same name as the node.
              name     = "{{ $computeDiskName }}"
              type     = "pd-ssd"
              zone     = "{{ $nodepool.Details.Zone }}"
              size     = {{ $nodepool.Details.StorageDiskSize }}

              labels = {
                managed-by = "claudie"
                claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
              }
            }

            resource "google_compute_attached_disk" "{{ $computeAttachedDiskResourceName }}" {
              provider    = google.nodepool_{{ $resourceSuffix }}
              disk        = google_compute_disk.{{ $computeDiskResourceName }}.id
              instance    = google_compute_instance.{{ $computeInstanceResourceName }}.id
              zone        = "{{ $nodepool.Details.Zone }}"
              device_name = var.{{ $varStorageDiskName }}
            }
            {{- end }}
        {{- end }}
    {{- end }}

    output "{{ $nodepool.Name }}_{{ $uniqueFingerPrint }}" {
      value = {
      {{- range $node := $nodepool.Nodes }}
        {{- $computeInstanceResourceName  := printf "%s_%s" $node.Name $resourceSuffix }}

        "${google_compute_instance.{{ $computeInstanceResourceName }}.name}" = google_compute_instance.{{ $computeInstanceResourceName }}.network_interface.0.access_config.0.nat_ip

      {{- end }}
      }
    }
{{- end }}
