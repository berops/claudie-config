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
  claudie_ssh_port_{{ $specName }}_{{ $uniqueFingerPrint }} = 22522
}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- $varCompartmentID := printf "default_compartment_id_%s" $resourceSuffix }}

variable "{{ $varCompartmentID }}" {
  type    = string
  default = "{{ $.Data.Provider.GetOci.CompartmentOCID }}"
}

{{- $coreVCNResourceName  := printf "claudie_vcn_%s"   $resourceSuffix }}
{{- $coreVCNName          := printf "vcn%s%s-%s"       $clusterHash $uniqueFingerPrint $region }}

resource "oci_core_vcn" "{{ $coreVCNResourceName }}" {
  provider        = oci.networking_{{ $resourceSuffix }}
  compartment_id  = var.{{ $varCompartmentID }}
  display_name    = "{{ $coreVCNName }}"
  cidr_blocks     = ["10.0.0.0/16"]

  freeform_tags = {
    "Managed-by"      = "Claudie"
    "Claudie-cluster" = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $coreGatewayResourceName  := printf "claudie_gateway_%s"   $resourceSuffix }}
{{- $coreGatewayName          := printf "gtw%s%s-%s"           $clusterHash $uniqueFingerPrint $region }}

resource "oci_core_internet_gateway" "{{ $coreGatewayResourceName }}" {
  provider        = oci.networking_{{ $resourceSuffix }}
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
{{- $coreSecurityListName          := printf "sl%s%s-%s"                   $clusterHash $uniqueFingerPrint $region }}

resource "oci_core_default_security_list" "{{ $coreSecurityListResourceName }}" {
  provider                    = oci.networking_{{ $resourceSuffix }}
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
      min = local.claudie_ssh_port_{{ $specName }}_{{ $uniqueFingerPrint }}
      max = local.claudie_ssh_port_{{ $specName }}_{{ $uniqueFingerPrint }}
    }
    description = "Allow SSH connections"
  }

  {{- if $isKubernetesCluster }}
  {{-   if $K8sHasAPIServer }}
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options {
      max = "6443"
      min = "6443"
    }
    description = "Allow kube API port"
  }
  {{-   end }}{{/* if $K8sHasAPIServer */}}
  {{- end }}{{/* if $isKubernetesCluster */}}

  {{- if $isLoadbalancerCluster }}
  {{-   range $role := $LoadBalancerRoles }}
  ingress_security_rules {
    protocol  = lookup(local.protocol_to_number_{{ $specName }}_{{ $uniqueFingerPrint }}, lower("{{ $role.Protocol }}"), -1)
    source    = "0.0.0.0/0"
    {{- /* OCI rejects tcp_options on non-TCP rules, so pick the options block
           matching the role protocol. */}}
    {{- if eq (lower $role.Protocol) "udp" }}
    udp_options {
      max = "{{ $role.Port }}"
      min = "{{ $role.Port }}"
    }
    {{- else }}
    tcp_options {
      max = "{{ $role.Port }}"
      min = "{{ $role.Port }}"
    }
    {{- end }}
    description = "LoadBalancer port defined in the manifest"
  }
  {{-   end }}{{/* range $LoadBalancerRoles */}}
  {{- end }}{{/* if $isLoadbalancerCluster */}}

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

{{- $coreRouteTableResourceName := printf "claudie_routes_%s" $resourceSuffix }}

resource "oci_core_default_route_table" "{{ $coreRouteTableResourceName }}" {
  provider                    = oci.networking_{{ $resourceSuffix }}
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

output "{{ $coreVCNResourceName }}" {
  value = oci_core_vcn.{{ $coreVCNResourceName }}.id
}

output "claudie_security_list_{{ $resourceSuffix }}" {
  value = oci_core_vcn.{{ $coreVCNResourceName }}.default_security_list_id
}

output "claudie_route_table_{{ $resourceSuffix }}" {
  value = oci_core_vcn.{{ $coreVCNResourceName }}.default_route_table_id
}

output "claudie_dhcp_options_{{ $resourceSuffix }}" {
  value = oci_core_vcn.{{ $coreVCNResourceName }}.default_dhcp_options_id
}

{{- end }}{{/* range .Data.Regions */}}

output "claudie_ssh_port_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = tostring(local.claudie_ssh_port_{{ $specName }}_{{ $uniqueFingerPrint }})
}
