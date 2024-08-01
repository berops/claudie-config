{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}

{{- range $i, $nodepool := .Data.NodePools }}

{{- $sanitisedRegion := replaceAll $nodepool.Details.Region " " "_"}}
{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}

    {{- range $node := $nodepool.Nodes }}

        {{- $virtualMachineResourceName   := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $resourceGroupResourceName    := printf "rg_%s"   $resourceSuffix }}
        {{- $networkInterfaceResourceName := printf "%s_%s_ni" $node.Name $resourceSuffix }}
        {{- $isWorkerNodeWithDiskAttached := and (not $nodepool.IsControl) (gt $nodepool.Details.StorageDiskSize 0) }}
        {{- $vmDiskAttachmentResourceName := printf "%s_%s_disk_att" $node.Name $resourceSuffix }}
        {{- $vmDiskResourceName           := printf "%s_%s_disk" $node.Name $resourceSuffix }}
        {{- $vmDiskName                   := printf "%sd" $node.Name }}


        resource "azurerm_linux_virtual_machine" "{{ $virtualMachineResourceName }}" {
          provider              = azurerm.nodepool_{{ $resourceSuffix }}
          name                  = "{{ $node.Name }}"
          location              = "{{ $nodepool.Details.Region }}"
          resource_group_name   = azurerm_resource_group.{{ $resourceGroupResourceName }}.name
          network_interface_ids = [azurerm_network_interface.{{ $networkInterfaceResourceName }}.id]
          size                  = "{{$nodepool.Details.ServerType}}"
          zone                  = "{{$nodepool.Details.Zone}}"

          source_image_reference {
            publisher = split(":", "{{ $nodepool.Details.Image }}")[0]
            offer     = split(":", "{{ $nodepool.Details.Image }}")[1]
            sku       = split(":", "{{ $nodepool.Details.Image }}")[2]
            version   = split(":", "{{ $nodepool.Details.Image }}")[3]
          }

          disable_password_authentication = true
          admin_ssh_key {
            public_key = file("./{{ $nodepool.Name }}")
            username   = "claudie"
          }

          computer_name  = "{{ $node.Name }}"
          admin_username = "claudie"

          tags = {
            managed-by      = "Claudie"
            claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }

        {{- if $isLoadbalancerCluster }}
          os_disk {
            name                 = "{{ $node.Name }}-osdisk"
            caching              = "ReadWrite"
            storage_account_type = "StandardSSD_LRS"
            disk_size_gb         = "50"
          }
        {{- end }}

        {{- if $isKubernetesCluster }}
          os_disk {
            name                 = "{{ $node.Name }}-osdisk"
            caching              = "ReadWrite"
            storage_account_type = "StandardSSD_LRS"
            disk_size_gb         = "100"
          }
        {{- end }}
        }

        {{- $virtualMachineExtensionResourceName   := printf "%s_%s_postcreation_script" $node.Name $resourceSuffix }}
        {{- $virtualMachineExtensionName           := printf "vm-ext-%s" $node.Name }}

        resource "azurerm_virtual_machine_extension" "{{ $virtualMachineExtensionResourceName }}" {
          provider             = azurerm.nodepool_{{ $resourceSuffix }}
          name                 = "{{ $virtualMachineExtensionName }}"
          virtual_machine_id   = azurerm_linux_virtual_machine.{{ $virtualMachineResourceName }}.id
          publisher            = "Microsoft.Azure.Extensions"
          type                 = "CustomScript"
          type_handler_version = "2.0"

          tags = {
            managed-by      = "Claudie"
            claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }

        {{- if $isLoadbalancerCluster }}
          protected_settings = <<PROT
          {
                "script": "${base64encode(<<EOF
#!/bin/bash
# Allow ssh as root
sudo sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
sudo cat /root/.ssh/temp > /root/.ssh/authorized_keys
sudo rm /root/.ssh/temp
sudo echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config
sshd_active=$(systemctl is-active sshd 2>/dev/null)
if [ $sshd_active = 'active' ]; then
    sudo service sshd restart
else
    # Ubuntu 24.04 doesn't have sshd service...
    sudo service ssh restart
fi
EOF
)}"
        }
PROT
        {{- end }}

        {{- if $isKubernetesCluster }}

          protected_settings = <<PROT
          {
          "script": "${base64encode(<<EOF
#!/bin/bash
set -euxo pipefail

# Allow ssh as root
sudo sed -n 's/^.*ssh-rsa/ssh-rsa/p' /root/.ssh/authorized_keys > /root/.ssh/temp
sudo cat /root/.ssh/temp > /root/.ssh/authorized_keys
sudo rm /root/.ssh/temp
sudo echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> sshd_config
# The '|| true' part in the following cmd makes sure that this script doesn't fail when there is no sshd service.
sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
if [ $sshd_active = 'active' ]; then
    sudo service sshd restart
else
    # Ubuntu 24.04 doesn't have sshd service...
    sudo service ssh restart
fi
# Create longhorn volume directory
mkdir -p /opt/claudie/data

            {{- if $isWorkerNodeWithDiskAttached }}

# Mount managed disk only when not mounted yet
sleep 50
disk=$(ls -l /dev/disk/by-path | grep "lun-${azurerm_virtual_machine_data_disk_attachment.{{ $vmDiskAttachmentResourceName }}.lun}" | awk '{print $NF}')
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
        )}"
          }
PROT

        {{- end }}
        }

        {{- if $isKubernetesCluster }}
            {{- if $isWorkerNodeWithDiskAttached }}
        resource "azurerm_managed_disk" "{{ $vmDiskResourceName }}" {
          provider             = azurerm.nodepool_{{ $resourceSuffix }}
          name                 = "{{ $vmDiskName }}"
          location             = "{{ $nodepool.Details.Region }}"
          zone                 = {{ $nodepool.Details.Zone }}
          resource_group_name  = azurerm_resource_group.{{ $resourceGroupResourceName }}.name
          storage_account_type = "StandardSSD_LRS"
          create_option        = "Empty"
          disk_size_gb         = {{ $nodepool.Details.StorageDiskSize }}

          tags = {
            managed-by      = "Claudie"
            claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }
        }



        resource "azurerm_virtual_machine_data_disk_attachment" "{{ $vmDiskAttachmentResourceName }}" {
          provider           = azurerm.nodepool_{{ $resourceSuffix }}
          managed_disk_id    = azurerm_managed_disk.{{ $vmDiskResourceName }}.id
          virtual_machine_id = azurerm_linux_virtual_machine.{{ $virtualMachineResourceName }}.id
          lun                = "1"
          caching            = "ReadWrite"
        }
            {{- end }}
        {{- end }}

    {{- end }}

output "{{ $nodepool.Name }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $virtualMachineResourceName   := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $publicIPResourceName         := printf "%s_%s_public_ip" $node.Name $resourceSuffix }}
        "${azurerm_linux_virtual_machine.{{ $virtualMachineResourceName }}.name}" = azurerm_public_ip.{{ $publicIPResourceName }}.ip_address
    {{- end }}
  }
}
{{- end }}
