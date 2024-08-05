{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- range $_, $nodepool := .Data.NodePools }}

{{- $sanitisedRegion            := replaceAll $nodepool.Details.Region " " "_"}}
{{- $specName                   := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix             := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}


{{- $subnetResourceName          := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $subnetName                  := printf "snt-%s-%s-%s" $clusterHash $sanitisedRegion $nodepool.Name }}
{{- $subnetCIDR                  := $nodepool.Details.Cidr }}
{{- $resourceGroupResourceName   := printf "rg_%s"   $resourceSuffix }}
{{- $virtualNetworkResourceName  := printf "claudie_vn_%s"   $resourceSuffix }}

resource "azurerm_subnet" "{{ $subnetResourceName }}" {
  provider             = azurerm.nodepool_{{ $resourceSuffix }}
  name                 = "{{ $subnetName }}"
  resource_group_name  = azurerm_resource_group.{{ $resourceGroupResourceName }}.name
  virtual_network_name = azurerm_virtual_network.{{ $virtualNetworkResourceName }}.name
  address_prefixes     = ["{{ $subnetCIDR }}"]
}

{{- $subnetNetworkSecurityGroupAssociationResourceName := printf "%s_%s_associate_nsg" $nodepool.Name $resourceSuffix }}
{{- $networkSecurityGroupResourceName                  := printf "claudie_nsg_%s"   $resourceSuffix }}

resource "azurerm_subnet_network_security_group_association" "{{ $subnetNetworkSecurityGroupAssociationResourceName }}" {
  provider                  = azurerm.nodepool_{{ $resourceSuffix }}
  subnet_id                 = azurerm_subnet.{{ $subnetResourceName }}.id
  network_security_group_id = azurerm_network_security_group.{{ $networkSecurityGroupResourceName }}.id
}

    {{- range $node := $nodepool.Nodes }}

        {{- $publicIPResourceName := printf "%s_%s_public_ip" $node.Name $resourceSuffix }}
        {{- $publicIPName         := printf "ip-%s" $node.Name }}

        resource "azurerm_public_ip" "{{ $publicIPResourceName }}" {
          provider            = azurerm.nodepool_{{ $resourceSuffix }}
          name                = "{{ $publicIPName }}"
          location            = "{{ $nodepool.Details.Region }}"
          resource_group_name = azurerm_resource_group.{{ $resourceGroupResourceName }}.name
          allocation_method   = "Static"
          sku                 = "Standard"

          tags = {
            managed-by      = "Claudie"
            claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }
        }

        {{- $networkInterfaceResourceName := printf "%s_%s_ni" $node.Name $resourceSuffix }}
        {{- $networkInterfaceName         := printf "ni-%s" $node.Name }}

        resource "azurerm_network_interface" "{{ $networkInterfaceResourceName }}" {
          provider            = azurerm.nodepool_{{ $resourceSuffix }}
          name                = "{{ $networkInterfaceName }}"
          location            = "{{ $nodepool.Details.Region }}"
          resource_group_name = azurerm_resource_group.{{ $resourceGroupResourceName }}.name
          enable_accelerated_networking = length(regexall(local.combined_pattern_{{ $specName }}_{{ $uniqueFingerPrint }}, "{{ $nodepool.Details.ServerType }}")) > 0 ? "true" : "false"

          ip_configuration {
            name                          = "ip-cfg-{{ $node.Name }}"
            subnet_id                     = azurerm_subnet.{{ $subnetResourceName }}.id
            private_ip_address_allocation = "Dynamic"
            public_ip_address_id          = azurerm_public_ip.{{ $publicIPResourceName }}.id
            primary                       = true
          }

          tags = {
            managed-by      = "Claudie"
            claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
          }
        }
    {{- end }}
{{- end }}
