{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- $nodepool        := .Data.NodePool }}
{{- $sanitisedRegion := replaceAll $nodepool.Details.Region " " "_"}}
{{- $specName        := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix  := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}
{{- $networking      := .Data.Networking.All }}
{{- $rgName          := index $networking (printf "rg_%s" $resourceSuffix) }}
{{- $vnName          := index $networking (printf "claudie_vn_%s" $resourceSuffix) }}
{{- $nsgId           := index $networking (printf "claudie_nsg_%s" $resourceSuffix) }}

{{- if not $rgName }}{{ template "node_networking.tpl: missing output 'rg_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $vnName }}{{ template "node_networking.tpl: missing output 'claudie_vn_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $nsgId }}{{ template "node_networking.tpl: missing output 'claudie_nsg_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

{{- $subnetResourceName := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $subnetName         := printf "snt-%s-%s-%s" $clusterHash $sanitisedRegion $nodepool.Name }}
{{- $subnetCIDR         := $nodepool.Details.Cidr }}

resource "azurerm_subnet" "{{ $subnetResourceName }}" {
  provider             = azurerm.nodepool_{{ $resourceSuffix }}
  name                 = "{{ $subnetName }}"
  resource_group_name  = "{{ $rgName }}"
  virtual_network_name = "{{ $vnName }}"
  address_prefixes     = ["{{ $subnetCIDR }}"]
}

{{- $subnetNetworkSecurityGroupAssociationResourceName := printf "%s_%s_associate_nsg" $nodepool.Name $resourceSuffix }}

resource "azurerm_subnet_network_security_group_association" "{{ $subnetNetworkSecurityGroupAssociationResourceName }}" {
  provider                  = azurerm.nodepool_{{ $resourceSuffix }}
  subnet_id                 = azurerm_subnet.{{ $subnetResourceName }}.id
  network_security_group_id = "{{ $nsgId }}"
}

{{- range $node := $nodepool.Nodes }}

{{- $publicIPResourceName := printf "%s_%s_public_ip" $node.Name $resourceSuffix }}
{{- $publicIPName         := printf "ip-%s" $node.Name }}

resource "azurerm_public_ip" "{{ $publicIPResourceName }}" {
  provider            = azurerm.nodepool_{{ $resourceSuffix }}
  name                = "{{ $publicIPName }}"
  location            = "{{ $nodepool.Details.Region }}"
  resource_group_name = "{{ $rgName }}"
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
  provider                       = azurerm.nodepool_{{ $resourceSuffix }}
  name                           = "{{ $networkInterfaceName }}"
  location                       = "{{ $nodepool.Details.Region }}"
  resource_group_name            = "{{ $rgName }}"
  accelerated_networking_enabled = length(regexall(local.combined_pattern_{{ $specName }}_{{ $uniqueFingerPrint }}, "{{ $nodepool.Details.ServerType }}")) > 0

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

{{- end }}{{/* range $nodepool.Nodes */}}
