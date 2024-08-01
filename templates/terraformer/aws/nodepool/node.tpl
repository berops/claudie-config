{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $_, $nodepool := .Data.NodePools }}

{{- $region         := $nodepool.Details.Region }}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

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

    {{- range $node := $nodepool.Nodes }}

        {{- $instanceResourceName         := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $subnetResourceName           := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
        {{- $securityGroupResourceName    := printf "claudie_sg_%s"   $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $volumeResourceName           := printf "%s_%s_volume" $node.Name $resourceSuffix }}
        {{- $volumeAttachmentResourceName := printf "%s_%s_volume_att" $node.Name $resourceSuffix }}

        resource "aws_instance" "{{ $instanceResourceName }}" {
          provider          = aws.nodepool_{{ $resourceSuffix }}
          availability_zone = "{{ $nodepool.Details.Zone }}"
          instance_type     = "{{ $nodepool.Details.ServerType }}"
          ami               = "{{ $nodepool.Details.Image }}"

          associate_public_ip_address = true
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
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config && service sshd restart
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
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config && service sshd restart
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
          availability_zone = "{{ $nodepool.Details.Zone }}"
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

output  "{{ $nodepool.Name }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $_, $node := $nodepool.Nodes }}
        {{- $instanceResourceName         := printf "%s_%s" $node.Name $resourceSuffix }}
        "${aws_instance.{{ $instanceResourceName }}.tags_all.Name}" =  aws_instance.{{ $instanceResourceName}}.public_ip
    {{- end }}
  }
}
{{- end }}
