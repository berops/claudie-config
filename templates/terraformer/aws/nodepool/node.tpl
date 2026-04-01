{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $_, $nodepool := .Data.NodePools }}

{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}
{{- $internetGatewayResourceName := printf "claudie_gateway_%s" $resourceSuffix }}
{{- $keypairResourceName  := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $keypairName          := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

resource "aws_key_pair" "{{ $keypairResourceName }}" {
  provider   = aws.nodepool_{{ $resourceSuffix }}
  key_name   = "{{ $keypairName }}"
  public_key = file("./{{ $nodepool.Name }}")
  tags = {
    Name            = "{{ $keypairName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

    {{- range $_, $node := $nodepool.Nodes }}

        {{- $instanceResourceName         := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- /* Subnet name depends on whether zone is specified */}}
        {{- $subnetResourceName           := "" }}
        {{- if $nodepool.Details.Zone }}
            {{- $subnetResourceName = printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
        {{- else }}
            {{- $subnetResourceName = printf "%s_%s_%s_subnet" $nodepool.Name $node.Name $resourceSuffix }}
        {{- end }}
        {{- $securityGroupResourceName    := printf "claudie_sg_%s"   $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $volumeResourceName           := printf "%s_%s_volume" $node.Name $resourceSuffix }}
        {{- $volumeAttachmentResourceName := printf "%s_%s_volume_att" $node.Name $resourceSuffix }}
        {{- $eipResourceName              := printf "%s_%s_eip" $node.Name $resourceSuffix }}
        {{- $eipAssocResourceName         := printf "%s_%s_eip_assoc" $node.Name $resourceSuffix }}

        resource "aws_eip" "{{ $eipResourceName }}" {
          provider   = aws.nodepool_{{ $resourceSuffix }}
          depends_on = [aws_internet_gateway.{{ $internetGatewayResourceName }}]
          domain     = "vpc"

          tags = {
            Name            = "{{ $node.Name }}-eip"
            Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }
        }

        resource "aws_eip_association" "{{ $eipAssocResourceName }}" {
          provider      = aws.nodepool_{{ $resourceSuffix }}
          instance_id   = aws_instance.{{ $instanceResourceName }}.id
          allocation_id = aws_eip.{{ $eipResourceName }}.id
        }

        resource "aws_instance" "{{ $instanceResourceName }}" {
          provider          = aws.nodepool_{{ $resourceSuffix }}
        {{- if $nodepool.Details.Zone }}
          availability_zone = "{{ $nodepool.Details.Zone }}"
        {{- else }}
          availability_zone = element(data.aws_availability_zones.available_{{ $resourceSuffix }}.names, parseint(regex("[0-9a-f]+$", "{{ $node.Name }}"), 16))
        {{- end }}
          instance_type     = "{{ $nodepool.Details.ServerType }}"
          ami               = "{{ $nodepool.Details.Image }}"

          key_name               = aws_key_pair.{{ $keypairResourceName }}.key_name
          subnet_id              = aws_subnet.{{ $subnetResourceName }}.id
          vpc_security_group_ids = [aws_security_group.{{ $securityGroupResourceName }}.id]

          tags = {
            Name            = "{{ $node.Name }}"
            Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }

        {{- if $isLoadbalancerCluster }}
          root_block_device {
            volume_size           = 50
            delete_on_termination = true
            volume_type           = "gp2"
          }

          user_data = <<EOF
#!/bin/bash
# Allow ssh connection for root
sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
cat /root/.ssh/temp > /root/.ssh/authorized_keys
rm /root/.ssh/temp
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config
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

        {{- end }}

        {{- if $isKubernetesCluster }}
          root_block_device {
            volume_size           = 100
            delete_on_termination = true
            volume_type           = "gp2"
          }
          user_data = <<EOF
#!/bin/bash
set -euxo pipefail
# Allow ssh connection for root
sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
cat /root/.ssh/temp > /root/.ssh/authorized_keys
rm /root/.ssh/temp
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config
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
# The '|| true' part in the following cmd makes sure that this script doesn't fail when there is no sshd service.
sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
ssh_active=$(systemctl is-active ssh 2>/dev/null || true)

if [ $sshd_active = 'active' ]; then
    systemctl restart sshd
fi

if [ $ssh_active = 'active' ]; then
    systemctl restart ssh
fi
# Create longhorn volume directory
mkdir -p /opt/claudie/data

            {{- if $isWorkerNodeWithDiskAttached }}

# Mount EBS volume only when not mounted yet
sleep 50
disk=$(ls -l /dev/disk/by-id | grep "${replace("${aws_ebs_volume.{{ $volumeResourceName }}.id}", "-", "")}" | awk '{print $NF}')
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

        {{- end }}
        }
        
        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}

        resource "aws_ebs_volume" "{{ $volumeResourceName }}" {
          provider          = aws.nodepool_{{ $resourceSuffix }}
        {{- if $nodepool.Details.Zone }}
          availability_zone = "{{ $nodepool.Details.Zone }}"
        {{- else }}
          availability_zone = element(data.aws_availability_zones.available_{{ $resourceSuffix }}.names, parseint(regex("[0-9a-f]+$", "{{ $node.Name }}"), 16))
        {{- end }}
          size              = {{ $nodepool.Details.StorageDiskSize }}
          type              = "gp2"

          tags = {
            Name            = "{{ $node.Name }}d"
            Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }
        }

        resource "aws_volume_attachment" "{{ $volumeAttachmentResourceName }}" {
          provider    = aws.nodepool_{{ $resourceSuffix }}
          device_name = "/dev/sdh"
          volume_id   = aws_ebs_volume.{{ $volumeResourceName }}.id
          instance_id = aws_instance.{{ $instanceResourceName }}.id
        }
            {{- end }}
        {{- end }}

    {{- end }}

output  "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $_, $node := $nodepool.Nodes }}
        {{- $instanceResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $eipResourceName := printf "%s_%s_eip" $node.Name $resourceSuffix }}
        "${aws_instance.{{ $instanceResourceName }}.tags_all.Name}" = [aws_eip.{{ $eipResourceName }}.public_ip, tostring(local.claudie_ssh_port_{{ $resourceSuffix }})]
    {{- end }}
  }
}
{{- end }}
