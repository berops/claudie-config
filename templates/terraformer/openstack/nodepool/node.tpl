{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}

{{- range $nodepool := .Data.NodePools }}

{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- $keypairResourceName  := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $keypairName          := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

  resource "openstack_compute_keypair_v2" "{{ $keypairResourceName }}" {
    provider   = openstack.nodepool_{{ $resourceSuffix }}
    name   = "{{ $keypairName }}"
    public_key = file("./{{ $nodepool.Name }}")
  }

  {{- range $node := $nodepool.Nodes }}

    {{- $instanceResourceName         := printf "%s_%s" $node.Name $resourceSuffix }}
    {{- $privateNetResourceName       := printf "network_%s_%s" $resourceSuffix $.Data.ClusterData.ClusterType}}
    {{- $volumeResourceName           := printf "volume_%s_%s" $node.Name $resourceSuffix }}
    {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
    {{- $securityGroupResourceName    := printf "claudie_sg_%s"   $resourceSuffix }}

    resource "openstack_compute_instance_v2" "{{ $instanceResourceName }}"  {
      provider          = openstack.nodepool_{{ $resourceSuffix }}
      name              = "{{ $node.Name }}"
      image_name        = "{{ $nodepool.Details.Image }}"
      flavor_name       = "{{ $nodepool.Details.ServerType }}"
      availability_zone = "{{ $nodepool.Details.Zone }}"
      key_pair          = openstack_compute_keypair_v2.{{ $keypairResourceName }}.id
      
      security_groups = [openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.name]

      network {
        uuid = openstack_networking_network_v2.{{ $privateNetResourceName }}.id
      }

      tags = [
        "managed-by:Claudie",
        "claudie-cluster:{{ $clusterName }}-{{ $clusterHash }}"
      ]

      user_data = <<-EOF
      #cloud-config

      runcmd:
        - sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
        - cat /root/.ssh/temp > /root/.ssh/authorized_keys
        - rm /root/.ssh/temp

        # Modify SSH configuration
        - echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
        - echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
        - echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
        - echo 'PubkeyAcceptedKeyTypes=+ssh-rsa' >> /etc/ssh/sshd_config

        # Configure SSH port
        - echo "Port ${local.claudie_ssh_port_{{ $resourceSuffix }}}" >> /etc/ssh/sshd_config
        - mkdir -p /etc/systemd/system/ssh.socket.d
        - |
          cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
          [Socket]
          ListenStream=
          ListenStream=0.0.0.0:${local.claudie_ssh_port_{{ $resourceSuffix }}}
          SSHEOF
        - systemctl daemon-reload
        - systemctl restart ssh.socket

        # Restart SSH service if it's running
        - |
          sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
          ssh_active=$(systemctl is-active ssh 2>/dev/null || true)
          if [ "$sshd_active" = "active" ]; then
            systemctl restart sshd
          fi
          if [ "$ssh_active" = "active" ]; then
            systemctl restart ssh
          fi

      {{- if $isKubernetesCluster }}
          # Create longhorn volume directory
          mkdir -p /opt/claudie/data
        {{- /* Only Mount disk for Worker nodes that have a non-zero requested disk size */}}
        {{- if $isWorkerNodeWithDiskAttached }}

          # Mount volume only when not mounted yet
          sleep 50
          disk=$(lsblk -o NAME,ID | grep "${ openstack_blockstorage_volume_v3.{{ $volumeResourceName }}.id }" | awk '{print $1}')
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

    {{- $fipResourceName  := printf "fip_%s_%s" $node.Name $resourceSuffix }}

    resource "openstack_networking_floatingip_v2" "{{ $fipResourceName }}" {
      provider   = openstack.nodepool_{{ $resourceSuffix }}
      pool = "{{ $nodepool.Details.ExternalNetworkName }}"

      tags = [
        "managed-by:Claudie",
        "claudie-cluster:{{ $clusterName }}-{{ $clusterHash }}"
      ]
    }

    {{- $vmNetworkPort           := printf "vm_port_%s_%s" $node.Name $resourceSuffix }}
    {{- $vmNetworkPortName       := printf "vm-port-%s-%s" $node.Name $resourceSuffix }}

    data "openstack_networking_port_v2" "{{ $vmNetworkPort }}" {
      provider   = openstack.nodepool_{{ $resourceSuffix }}
      device_id  = openstack_compute_instance_v2.{{ $instanceResourceName }}.id
      network_id = openstack_compute_instance_v2.{{ $instanceResourceName }}.network.0.uuid
    }

    {{- $fipAssociateName  := printf "fip_associate_%s_%s" $node.Name $resourceSuffix }}

    resource "openstack_networking_floatingip_associate_v2" "{{ $fipAssociateName }}" {
      provider   = openstack.nodepool_{{ $resourceSuffix }}
      floating_ip = openstack_networking_floatingip_v2.{{ $fipResourceName }}.address
      port_id     = data.openstack_networking_port_v2.{{ $vmNetworkPort }}.id
    }

    {{- if $isKubernetesCluster }}
      {{- /* Only Mount disk for Worker nodes that have a non-zero requested disk size */}}
      {{- if $isWorkerNodeWithDiskAttached }}
        {{- $volumeName                   := printf "%sd" $node.Name }}
        {{- $volumeAttachmentResourceName := printf "%s_att" $volumeResourceName }}

        resource "openstack_blockstorage_volume_v3" "{{ $volumeResourceName }}" {
          provider   = openstack.nodepool_{{ $resourceSuffix }}
          name       = "{{ $volumeName }}"
          size       = "{{ $nodepool.Details.StorageDiskSize }}"
          region     = "{{ $nodepool.Details.Region }}"
        }

        resource "openstack_compute_volume_attach_v2" "{{ $volumeAttachmentResourceName }}" {
          provider    = openstack.nodepool_{{ $resourceSuffix }}
          instance_id = openstack_compute_instance_v2.{{ $instanceResourceName }}.id
          volume_id   = openstack_blockstorage_volume_v3.{{ $volumeResourceName }}.id
        }
      {{- end }}
    {{- end }}
  {{- end }}

  output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
    value = {
      {{- range $node := $nodepool.Nodes }}
        {{- $instanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $fipResourceName      := printf "fip_%s_%s" $node.Name $resourceSuffix }}
        {{- $fipAssociateName     := printf "fip_associate_%s_%s" $node.Name $resourceSuffix }}
        "${openstack_compute_instance_v2.{{ $instanceResourceName }}.name}" = [openstack_networking_floatingip_associate_v2.{{ $fipAssociateName }}.floating_ip, tostring(local.claudie_ssh_port_{{ $resourceSuffix }})]
      {{- end }}
    }
}
{{- end }}
