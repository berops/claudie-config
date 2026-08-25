{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- $nodepool       := .Data.NodePool }}
{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}
{{- $networking     := .Data.Networking.All }}
{{- $claudieSshPort := index $networking (printf "claudie_ssh_port_%s_%s" $specName $uniqueFingerPrint) }}

{{- if not $claudieSshPort }}{{ template "node.tpl: missing output 'claudie_ssh_port_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

# Fetch available availability domains for the region
# Note: Availability domains must be queried using the tenancy OCID (root compartment),
# not a sub-compartment OCID, as ADs are tenancy-level resources.
data "oci_identity_availability_domains" "available_{{ $resourceSuffix }}" {
  provider       = oci.nodepool_{{ $resourceSuffix }}
  compartment_id = "{{ $nodepool.Details.Provider.GetOci.TenancyOCID }}"
}

{{- $varCompartmentID := printf "default_compartment_id_%s" $resourceSuffix }}

variable "{{ $varCompartmentID }}" {
  type    = string
  default = "{{ $nodepool.Details.Provider.GetOci.CompartmentOCID }}"
}

{{- if $isKubernetesCluster }}

{{- $varStorageDiskName := printf "oci_storage_disk_name_%s" $resourceSuffix }}

variable "{{ $varStorageDiskName }}" {
  default = "oraclevdb"
  type    = string
}
{{- end }}{{/* if $isKubernetesCluster */}}

{{- range $_, $node := $nodepool.Nodes }}

{{- $coreInstanceResourceName     := printf "%s_%s" $node.Name $resourceSuffix }}
{{- $coreSubnetResourceName       := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $varCompartmentID             := printf "default_compartment_id_%s" $resourceSuffix }}
{{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
{{- $varStorageDiskName           := printf "oci_storage_disk_name_%s" $resourceSuffix }}

resource "oci_core_instance" "{{ $coreInstanceResourceName }}" {
  provider            = oci.nodepool_{{ $resourceSuffix }}
  compartment_id      = var.{{ $varCompartmentID }}
  {{- if $nodepool.Details.Zone }}
  availability_domain = "{{ $nodepool.Details.Zone }}"
  {{- else }}
  availability_domain = element(data.oci_identity_availability_domains.available_{{ $resourceSuffix }}.availability_domains, parseint(regex("[0-9a-f]+$", "{{ $node.Name }}"), 16)).name
  {{- end }}
  shape               = "{{ $nodepool.Details.ServerType }}"
  display_name        = "{{ $node.Name }}"

  {{- if $nodepool.Details.MachineSpec }}
  shape_config {
    memory_in_gbs = {{ $nodepool.Details.MachineSpec.Memory }}
    ocpus         = {{ $nodepool.Details.MachineSpec.CpuCount }}
  }
  {{- end }}

  {{- if $nodepool.Details.Spot }}
  preemptible_instance_config {
    preemption_action {
      type                 = "TERMINATE"
      preserve_boot_volume = false
    }
  }
  {{- end }}

  create_vnic_details {
    assign_public_ip  = true
    subnet_id         = oci_core_subnet.{{ $coreSubnetResourceName }}.id
  }

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }

  {{- if $isLoadbalancerCluster }}
  source_details {
    source_id               = "{{ $nodepool.Details.Image }}"
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
                - echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> /etc/ssh/sshd_config
                # Configure SSH port
                - echo "Port {{ $claudieSshPort }}" >> /etc/ssh/sshd_config
                - mkdir -p /etc/systemd/system/ssh.socket.d
                - |
                  cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
                  [Socket]
                  ListenStream=
                  ListenStream=0.0.0.0:{{ $claudieSshPort }}
                  SSHEOF
                - systemctl daemon-reload
                - systemctl restart ssh.socket
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
                - |
                  # The '|| true' part in the following cmd makes sure that this script doesn't fail when there is no sshd service.
                  sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
                  ssh_active=$(systemctl is-active ssh 2>/dev/null || true)

                  if [ $sshd_active = 'active' ]; then
                      systemctl restart sshd
                  fi
                  if [ $ssh_active = 'active' ]; then
                      systemctl restart ssh
                  fi
              EOF
    )
  }
  {{- end }}{{/* if $isLoadbalancerCluster */}}

  {{- if $isKubernetesCluster }}
  source_details {
    source_id               = "{{ $nodepool.Details.Image }}"
    source_type             = "image"
    boot_volume_size_in_gbs = "100"
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
                - echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> /etc/ssh/sshd_config
                # Configure SSH port
                - echo "Port {{ $claudieSshPort }}" >> /etc/ssh/sshd_config
                - mkdir -p /etc/systemd/system/ssh.socket.d
                - |
                  cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
                  [Socket]
                  ListenStream=
                  ListenStream=0.0.0.0:{{ $claudieSshPort }}
                  SSHEOF
                - systemctl daemon-reload
                - systemctl restart ssh.socket
                - |
                  # The '|| true' part in the following cmd makes sure that this script doesn't fail when there is no sshd service.
                  sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
                  ssh_active=$(systemctl is-active ssh 2>/dev/null || true)

                  if [ $sshd_active = 'active' ]; then
                      systemctl restart sshd
                  fi
                  if [ $ssh_active = 'active' ]; then
                      systemctl restart ssh
                  fi
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
                {{- end }}{{/* if $isWorkerNodeWithDiskAttached */}}
              EOF
    )
  }
  {{- end }}{{/* if $isKubernetesCluster */}}
}

{{- if $isKubernetesCluster }}
{{-   if $isWorkerNodeWithDiskAttached }}

{{- $coreVolumeResourceName       := printf "%s_%s_volume" $node.Name $resourceSuffix }}
{{- $coreVolumeName               := printf "%sd" $node.Name }}
{{- $coreAttachedDiskResourceName := printf "%s_%s_volume_att" $node.Name $resourceSuffix }}
{{- $coreAttachedDiskName         := printf "att-%s" $node.Name }}

resource "oci_core_volume" "{{ $coreVolumeResourceName }}" {
  provider            = oci.nodepool_{{ $resourceSuffix }}
  compartment_id      = var.{{ $varCompartmentID }}
  {{- if $nodepool.Details.Zone }}
  availability_domain = "{{ $nodepool.Details.Zone }}"
  {{- else }}
  availability_domain = element(data.oci_identity_availability_domains.available_{{ $resourceSuffix }}.availability_domains, parseint(regex("[0-9a-f]+$", "{{ $node.Name }}"), 16)).name
  {{- end }}
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

{{-   end }}{{/* if $isWorkerNodeWithDiskAttached */}}
{{- end }}{{/* if $isKubernetesCluster */}}

{{- end }}{{/* range $nodepool.Nodes */}}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
    {{- $coreInstanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
    "${oci_core_instance.{{ $coreInstanceResourceName }}.display_name}" = [oci_core_instance.{{ $coreInstanceResourceName }}.public_ip, "{{ $claudieSshPort }}"]
    {{- end }}
  }
}
