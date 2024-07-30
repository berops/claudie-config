{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- range $_, $nodepool := .Data.NodePools }}

{{- $region                     := $nodepool.Details.Region }}
{{- $specName                   := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix             := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}


{{- $coreSubnetResourceName  := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $coreSubnetName          := printf "snt-%s-%s-%s" $clusterHash $region $nodepool.Name }}
{{- $coreSubnetCIDR          := $nodepool.Details.Cidr }}
{{- $coreVCNResourceName     := printf "claudie_vcn_%s"   $resourceSuffix }}
{{- $varCompartmentID        := printf "default_compartment_id_%s" $resourceSuffix }}

resource "oci_core_subnet" "{{ $coreSubnetResourceName }}" {
  provider            = oci.nodepool_{{ $resourceSuffix }}
  vcn_id              = oci_core_vcn.{{ $coreVCNResourceName }}.id
  cidr_block          = "{{ $coreSubnetCIDR }}"
  compartment_id      = var.{{ $varCompartmentID }}
  display_name        = "{{ $coreSubnetName }}"
  security_list_ids   = [oci_core_vcn.{{ $coreVCNResourceName }}.default_security_list_id]
  route_table_id      = oci_core_vcn.{{ $coreVCNResourceName }}.default_route_table_id
  dhcp_options_id     = oci_core_vcn.{{ $coreVCNResourceName }}.default_dhcp_options_id
  availability_domain = "{{ $nodepool.Details.Zone }}"

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- end }}
