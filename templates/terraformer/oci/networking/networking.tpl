{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}

locals {
  protocol_to_number_{{ $specName }}_{{ $uniqueFingerPrint }} = {
    "tcp"    = 6
    "udp"    = 17
    "icmp"   = 1
    "icmpv6" = 58
  }
}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- if $isKubernetesCluster }}
    {{- $varStorageDiskName  := printf "oci_storage_disk_name_%s" $resourceSuffix }}
    variable "{{ $varStorageDiskName }}" {
      default = "oraclevdb"
      type    = string
    }
{{- end }}

{{- $varCompartmentID  := printf "default_compartment_id_%s" $resourceSuffix }}
variable "{{ $varCompartmentID }}" {
  type    = string
  default = "{{ $.Data.Provider.GetOci.CompartmentOCID }}"
}

{{- $coreVCNResourceName  := printf "claudie_vcn_%s"   $resourceSuffix }}
{{- $coreVCNName          := printf "vcn%s-%s-%s-%s" $clusterHash $region $specName $uniqueFingerPrint }}

resource "oci_core_vcn" "{{ $coreVCNResourceName }}" {
  provider        = oci.nodepool_{{ $resourceSuffix }}
  compartment_id  = var.{{ $varCompartmentID }}
  display_name    = "{{ $coreVCNName }}"
  cidr_blocks     = ["10.0.0.0/16"]

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $coreGatewayResourceName  := printf "claudie_gateway_%s"   $resourceSuffix }}
{{- $coreGatewayName          := printf "gtw%s-%s-%s-%s" $clusterHash $region $specName $uniqueFingerPrint }}

resource "oci_core_internet_gateway" "{{ $coreGatewayResourceName }}" {
  provider        = oci.nodepool_{{ $resourceSuffix }}
  compartment_id  = var.{{ $varCompartmentID }}
  display_name    = "{{ $coreGatewayName }}"
  vcn_id          = oci_core_vcn.{{ $coreVCNResourceName }}.id
  enabled         = true

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $coreSecurityListResourceName  := printf "claudie_security_rules_%s"   $resourceSuffix }}
{{- $coreSecurityListName          := printf "sl%s-%s-%s" $clusterHash $region $specName $uniqueFingerPrint }}

resource "oci_core_default_security_list" "{{ $coreSecurityListResourceName }}" {
  provider                    = oci.nodepool_{{ $resourceSuffix }}
  manage_default_resource_id  = oci_core_vcn.{{ $coreVCNResourceName }}.default_security_list_id
  display_name                = "{{ $coreSecurityListName }}"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    description = "Allow all egress"
  }

  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    description = "Allow all ICMP"
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options {
      min = "22"
      max = "22"
    }
    description = "Allow SSH connections"
  }

{{- if $isKubernetesCluster }}
  {{- if $K8sHasAPIServer }}
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options {
      max = "6443"
      min = "6443"
    }
    description = "Allow kube API port"
  }
  {{- end }}
{{- end }}

{{- if $isLoadbalancerCluster }}
  {{- range $role := $LoadBalancerRoles }}
  ingress_security_rules {
    protocol  = lookup(local.protocol_to_number_{{ $specName }}_{{ $uniqueFingerPrint }}, lower("{{ $role.Protocol }}"), -1)
    source    = "0.0.0.0/0"
    tcp_options {
      max = "{{ $role.Port }}"
      min = "{{ $role.Port }}"
    }
    description = "LoadBalancer port defined in the manifest"
  }
  {{- end }}
{{- end }}

  ingress_security_rules {
    protocol    = "17"
    source      = "0.0.0.0/0"
    udp_options {
      max = "51820"
      min = "51820"
    }
    description = "Allow Wireguard VPN port"
  }

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $coreRouteTableResourceName  := printf "claudie_routes_%s"   $resourceSuffix }}

resource "oci_core_default_route_table" "{{ $coreRouteTableResourceName }}" {
  provider                    = oci.nodepool_{{ $resourceSuffix }}
  manage_default_resource_id  = oci_core_vcn.{{ $coreVCNResourceName }}.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.{{ $coreGatewayResourceName }}.id
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}
{{- end }}

