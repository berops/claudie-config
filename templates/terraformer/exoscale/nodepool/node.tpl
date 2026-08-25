{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- $nodepool       := .Data.NodePool }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $networking     := .Data.Networking.All }}
{{- $sgId           := index $networking (printf "sg_%s" $resourceSuffix) }}
{{- $claudieSshPort := index $networking (printf "claudie_ssh_port_%s" $resourceSuffix) }}

{{- if not $sgId }}{{ template "node.tpl: missing output 'sg_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $claudieSshPort }}{{ template "node.tpl: missing output 'claudie_ssh_port_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName         := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}
{{- $templateDataName   := printf "template_%s_%s" $nodepool.Name $resourceSuffix }}

resource "exoscale_ssh_key" "{{ $sshKeyResourceName }}" {
  provider   = exoscale.nodepool_{{ $resourceSuffix }}
  name       = "{{ $sshKeyName }}"
  public_key = file("./{{ $nodepool.Name }}")
}

data "exoscale_template" "{{ $templateDataName }}" {
  provider = exoscale.nodepool_{{ $resourceSuffix }}
  zone     = "{{ $nodepool.Details.Region }}"
  name     = "{{ $nodepool.Details.Image }}"
}

{{- range $node := $nodepool.Nodes }}

{{- $serverResourceName           := printf "%s_%s" $node.Name $resourceSuffix }}
{{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
{{- $volumeResourceName           := printf "%s_%s_volume" $node.Name $resourceSuffix }}

{{- if $isKubernetesCluster }}
{{-   if $isWorkerNodeWithDiskAttached }}

{{- $volumeName := printf "%sd" $node.Name }}

resource "exoscale_block_storage_volume" "{{ $volumeResourceName }}" {
  provider = exoscale.nodepool_{{ $resourceSuffix }}
  zone     = "{{ $nodepool.Details.Region }}"
  name     = "{{ $volumeName }}"
  size     = {{ $nodepool.Details.StorageDiskSize }}

  labels = {
    "managed-by"      = "Claudie"
    "claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{-   end }}{{/* if $isWorkerNodeWithDiskAttached */}}
{{- end }}{{/* if $isKubernetesCluster */}}

resource "exoscale_compute_instance" "{{ $serverResourceName }}" {
  provider           = exoscale.nodepool_{{ $resourceSuffix }}
  zone               = "{{ $nodepool.Details.Region }}"
  name               = "{{ $node.Name }}"
  template_id        = data.exoscale_template.{{ $templateDataName }}.id
  type               = "{{ $nodepool.Details.ServerType }}"
  ssh_keys           = [exoscale_ssh_key.{{ $sshKeyResourceName }}.name]
  security_group_ids = ["{{ $sgId }}"]

  {{- if $isLoadbalancerCluster }}
  disk_size = 50
  {{- end }}

  {{- if $isKubernetesCluster }}
  disk_size = 100

  {{-   if $isWorkerNodeWithDiskAttached }}
  block_storage_volume_ids = [exoscale_block_storage_volume.{{ $volumeResourceName }}.id]
  {{-   end }}{{/* if $isWorkerNodeWithDiskAttached */}}
  {{- end }}{{/* if $isKubernetesCluster */}}

  labels = {
    "managed-by"      = "Claudie"
    "claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }

  {{- if $isLoadbalancerCluster }}
  user_data = <<EOF
#!/bin/bash
# Enable root SSH access
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    sed -n 's/^.*ssh-rsa/ssh-rsa/p' /home/ubuntu/.ssh/authorized_keys > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'PubkeyAcceptedKeyTypes=+ssh-rsa' >> /etc/ssh/sshd_config
# Configure SSH port
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
EOF
  {{- end }}{{/* if $isLoadbalancerCluster */}}

  {{- if $isKubernetesCluster }}
  user_data = <<EOF
#!/bin/bash
# Enable root SSH access
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    sed -n 's/^.*ssh-rsa/ssh-rsa/p' /home/ubuntu/.ssh/authorized_keys > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'PubkeyAcceptedKeyTypes=+ssh-rsa' >> /etc/ssh/sshd_config
# Configure SSH port
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

# Create longhorn volume directory
mkdir -p /opt/claudie/data

{{- if $isWorkerNodeWithDiskAttached }}

# Mount block storage volume only when not mounted yet
sleep 50
# Linux virtio driver truncates serial numbers to 20 chars, so we match on a prefix of the volume UUID
volume_id="${exoscale_block_storage_volume.{{ $volumeResourceName }}.id}"
short_id=$(echo "$volume_id" | cut -c1-20)
disk=$(ls -l /dev/disk/by-id | grep "$short_id" | awk '{print $NF}')
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
  {{- end }}{{/* if $isKubernetesCluster */}}
}

{{- end }}{{/* range $nodepool.Nodes */}}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
    {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
    "${exoscale_compute_instance.{{ $serverResourceName }}.name}" = [exoscale_compute_instance.{{ $serverResourceName }}.public_ip_address, "{{ $claudieSshPort }}"]
    {{- end }}
  }
}
