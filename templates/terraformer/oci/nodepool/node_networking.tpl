{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- $nodepool        := .Data.NodePool }}
{{- $region          := $nodepool.Details.Region }}
{{- $specName        := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix  := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}
{{- $networking      := .Data.Networking.All }}
{{- $vcnId           := index $networking (printf "claudie_vcn_%s" $resourceSuffix) }}
{{- $securityListId  := index $networking (printf "claudie_security_list_%s" $resourceSuffix) }}
{{- $routeTableId    := index $networking (printf "claudie_route_table_%s" $resourceSuffix) }}
{{- $dhcpOptionsId   := index $networking (printf "claudie_dhcp_options_%s" $resourceSuffix) }}

{{- if not $vcnId }}{{ template "node_networking.tpl: missing output 'claudie_vcn_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $securityListId }}{{ template "node_networking.tpl: missing output 'claudie_security_list_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $routeTableId }}{{ template "node_networking.tpl: missing output 'claudie_route_table_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $dhcpOptionsId }}{{ template "node_networking.tpl: missing output 'claudie_dhcp_options_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

{{- $coreSubnetResourceName := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $coreSubnetName         := printf "snt-%s-%s-%s" $clusterHash $region $nodepool.Name }}
{{- $coreSubnetCIDR         := $nodepool.Details.Cidr }}
{{- $varCompartmentID       := printf "default_compartment_id_%s" $resourceSuffix }}

resource "oci_core_subnet" "{{ $coreSubnetResourceName }}" {
  provider            = oci.nodepool_{{ $resourceSuffix }}
  vcn_id              = "{{ $vcnId }}"
  cidr_block          = "{{ $coreSubnetCIDR }}"
  compartment_id      = var.{{ $varCompartmentID }}
  display_name        = "{{ $coreSubnetName }}"
  security_list_ids   = ["{{ $securityListId }}"]
  route_table_id      = "{{ $routeTableId }}"
  dhcp_options_id     = "{{ $dhcpOptionsId }}"
  availability_domain = "{{ $nodepool.Details.Zone }}"

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}
