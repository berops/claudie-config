{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}


locals {
  protocol_to_azure_protocol_{{ $specName }}_{{ $uniqueFingerPrint }} = {
    "tcp"    = "Tcp"
    "udp"    = "Udp"
    "icmp"   = "Icmp"
  }
}

{{- $basePriority  := printf "base_priority_%s_%s" $specName $uniqueFingerPrint }}
variable "{{ $basePriority }}" {
  type    = number
  default = 200
}

{{- range $_, $region := .Data.Regions }}

{{- $sanitisedRegion := replaceAll $region " " "_"}}
{{- $resourceSuffix := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}


{{- $resourceGroupResourceName  := printf "rg_%s"     $resourceSuffix }}
{{- $resourceGroupName          := printf "rg%s%s-%s" $clusterHash $uniqueFingerPrint $sanitisedRegion }}

resource "azurerm_resource_group" "{{ $resourceGroupResourceName }}" {
  provider = azurerm.nodepool_{{ $resourceSuffix }}
  name     = "{{ $resourceGroupName }}"
  location = "{{ $region }}"

  tags = {
    managed-by      = "Claudie"
    claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $virtualNetworkResourceName  := printf "claudie_vn_%s"   $resourceSuffix }}
{{- $virtualNetworkName          := printf "vn%s%s-%s"      $clusterHash $uniqueFingerPrint $sanitisedRegion }}

resource "azurerm_virtual_network" "{{ $virtualNetworkResourceName }}" {
  provider            = azurerm.nodepool_{{ $resourceSuffix }}
  name                = "{{ $virtualNetworkName }}"
  address_space       = ["10.0.0.0/16"]
  location            = "{{ $region }}"
  resource_group_name = azurerm_resource_group.{{ $resourceGroupResourceName }}.name

  tags = {
    managed-by      = "Claudie"
    claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $networkSecurityGroupResourceName  := printf "claudie_nsg_%s"   $resourceSuffix }}
{{- $networkSecurityGroupName          := printf "nsg%s%s-%s"       $clusterHash $uniqueFingerPrint $sanitisedRegion  }}

resource "azurerm_network_security_group" "{{ $networkSecurityGroupResourceName }}" {
  provider            = azurerm.nodepool_{{ $resourceSuffix }}
  name                = "{{ $networkSecurityGroupName }}"
  location            = "{{ $region }}"
  resource_group_name = azurerm_resource_group.{{ $resourceGroupResourceName }}.name

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Wireguard"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "51820"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ICMP"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

{{- if $isLoadbalancerCluster }}
  {{- range $i, $role := $LoadBalancerRoles }}
  security_rule {
    name                       = "Allow-{{ $role.Name }}"
    priority                   = var.{{ $basePriority }} + {{ $i }}
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = lookup(local.protocol_to_azure_protocol_{{ $specName }}_{{ $uniqueFingerPrint }}, "{{ $role.Protocol }}", "undefined")
    source_port_range          = "*"
    destination_port_range     = "{{ $role.Port }}"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  {{- end }}
{{- end }}

{{- if $isKubernetesCluster }}
  {{- if $K8sHasAPIServer }}
  security_rule {
    name                       = "KubeApi"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  {{- end }}
{{- end }}

  tags = {
    managed-by      = "Claudie"
    claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}
{{- end }}
