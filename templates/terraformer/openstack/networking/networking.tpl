{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}

{{- range $_, $rn := .Data.RegionNetwork }}

{{- $resourceSuffix := printf "%s_%s_%s" $rn.Region $specName $uniqueFingerPrint }}

locals {
  claudie_ssh_port_{{ $resourceSuffix }} = 22522
}

{{- $privateNetResourceName := printf "network_%s_%s" $resourceSuffix $.Data.ClusterData.ClusterType }}

resource "openstack_networking_network_v2" "{{ $privateNetResourceName }}" {
  provider = openstack.networking_{{ $resourceSuffix }}
  name     = "{{ $privateNetResourceName }}"

  tags = [
    "managed-by:Claudie",
    "claudie-cluster:{{ $clusterName }}-{{ $clusterHash }}"
  ]
}

{{- $privateSubResourceName := printf "subnet_%s_%s" $resourceSuffix $.Data.ClusterData.ClusterType }}

resource "openstack_networking_subnet_v2" "{{ $privateSubResourceName }}" {
  provider        = openstack.networking_{{ $resourceSuffix }}
  name            = "{{ $privateSubResourceName }}"
  network_id      = openstack_networking_network_v2.{{ $privateNetResourceName }}.id
  cidr            = "10.0.0.0/16"
  ip_version      = 4
  gateway_ip      = "10.0.1.1"
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]

  tags = [
    "managed-by:Claudie",
    "claudie-cluster:{{ $clusterName }}-{{ $clusterHash }}"
  ]
}

{{- $extNetworkResourceName := printf "ext_net_%s" $resourceSuffix }}

data "openstack_networking_network_v2" "{{ $extNetworkResourceName }}" {
  provider = openstack.networking_{{ $resourceSuffix }}
  region   = "{{ $rn.Region }}"
  name     = "{{ $rn.ExternalNetwork }}"
  external = true
}

{{- $routerResourceName := printf "router_%s_%s" $resourceSuffix $.Data.ClusterData.ClusterType }}

resource "openstack_networking_router_v2" "{{ $routerResourceName }}" {
  provider            = openstack.networking_{{ $resourceSuffix }}
  name                = "{{ $routerResourceName }}"
  external_network_id = data.openstack_networking_network_v2.{{ $extNetworkResourceName }}.id

  tags = [
    "managed-by:Claudie",
    "claudie-cluster:{{ $clusterName }}-{{ $clusterHash }}"
  ]
}

{{- $routerIfaecResourceName := printf "router_iface_%s_%s" $resourceSuffix $.Data.ClusterData.ClusterType }}

resource "openstack_networking_router_interface_v2" "{{ $routerIfaecResourceName }}" {
  provider  = openstack.networking_{{ $resourceSuffix }}
  router_id = openstack_networking_router_v2.{{ $routerResourceName }}.id
  subnet_id = openstack_networking_subnet_v2.{{ $privateSubResourceName }}.id
}

{{- $securityGroupResourceName  := printf "claudie_sg_%s"   $resourceSuffix }}
{{- $securityGroupName          := printf "sg%s%s-%s"       $clusterHash $uniqueFingerPrint $rn.Region }}

resource "openstack_networking_secgroup_v2" "{{ $securityGroupResourceName }}" {
  provider    = openstack.networking_{{ $resourceSuffix }}
  region      = "{{ $rn.Region }}"
  name        = "{{ $securityGroupName }}"
  description = "Claudie security group"

  tags = [
    "managed-by:Claudie",
    "claudie-cluster:{{ $clusterName }}-{{ $clusterHash }}"
  ]
}

resource "openstack_networking_secgroup_rule_v2" "allow_ssh_{{ $resourceSuffix }}" {
  provider          = openstack.networking_{{ $resourceSuffix }}
  region            = "{{ $rn.Region }}"
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = local.claudie_ssh_port_{{ $resourceSuffix }}
  port_range_max    = local.claudie_ssh_port_{{ $resourceSuffix }}
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_wireguard_{{ $resourceSuffix }}" {
  provider          = openstack.networking_{{ $resourceSuffix }}
  region            = "{{ $rn.Region }}"
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = 51820
  port_range_max    = 51820
  protocol          = "udp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_icmp_{{ $resourceSuffix }}" {
  provider          = openstack.networking_{{ $resourceSuffix }}
  region            = "{{ $rn.Region }}"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.id
}

{{- if $isKubernetesCluster }}
{{-   if $K8sHasAPIServer }}

resource "openstack_networking_secgroup_rule_v2" "allow_kube_api_{{ $resourceSuffix }}" {
  provider          = openstack.networking_{{ $resourceSuffix }}
  region            = "{{ $rn.Region }}"
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = 6443
  port_range_max    = 6443
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.id
}

{{-   end }}{{/* if $K8sHasAPIServer */}}
{{- end }}{{/* if $isKubernetesCluster */}}

{{- if $isLoadbalancerCluster }}
{{-   range $role := $LoadBalancerRoles }}

resource "openstack_networking_secgroup_rule_v2" "allow_{{ $role.Port }}_{{ $resourceSuffix }}" {
  provider          = openstack.networking_{{ $resourceSuffix }}
  region            = "{{ $rn.Region }}"
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = {{ $role.Port }}
  port_range_max    = {{ $role.Port }}
  protocol          = "{{ $role.Protocol }}"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.id
}

{{-   end }}{{/* range $LoadBalancerRoles */}}
{{- end }}{{/* if $isLoadbalancerCluster */}}

output "{{ $privateNetResourceName }}" {
  value = openstack_networking_network_v2.{{ $privateNetResourceName }}.id
}

output "{{ $securityGroupResourceName }}" {
  value = openstack_networking_secgroup_v2.{{ $securityGroupResourceName }}.name
}

output "claudie_ssh_port_{{ $resourceSuffix }}" {
  value = tostring(local.claudie_ssh_port_{{ $resourceSuffix }})
}

{{- end }}{{/* range .Data.RegionNetwork */}}
