{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}
{{- $resourceSuffix        := printf "%s_%s" $specName $uniqueFingerPrint }}

locals {
  claudie_ssh_port_{{ $resourceSuffix }} = 22522
}

{{- $sgResourceName := printf "sg_%s" $resourceSuffix }}
{{- $sgName         := printf "sg%s%s" $clusterHash $uniqueFingerPrint }}

resource "exoscale_security_group" "{{ $sgResourceName }}" {
  provider = exoscale.networking_{{ $resourceSuffix }}
  name     = "{{ $sgName }}"
}

resource "exoscale_security_group_rule" "icmp_{{ $resourceSuffix }}" {
  provider          = exoscale.networking_{{ $resourceSuffix }}
  security_group_id = exoscale_security_group.{{ $sgResourceName }}.id
  type              = "INGRESS"
  protocol          = "ICMP"
  icmp_type         = 8
  icmp_code         = 0
  cidr              = "0.0.0.0/0"
}

resource "exoscale_security_group_rule" "ssh_{{ $resourceSuffix }}" {
  provider          = exoscale.networking_{{ $resourceSuffix }}
  security_group_id = exoscale_security_group.{{ $sgResourceName }}.id
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = local.claudie_ssh_port_{{ $resourceSuffix }}
  end_port          = local.claudie_ssh_port_{{ $resourceSuffix }}
  cidr              = "0.0.0.0/0"
}

resource "exoscale_security_group_rule" "wireguard_{{ $resourceSuffix }}" {
  provider          = exoscale.networking_{{ $resourceSuffix }}
  security_group_id = exoscale_security_group.{{ $sgResourceName }}.id
  type              = "INGRESS"
  protocol          = "UDP"
  start_port        = 51820
  end_port          = 51820
  cidr              = "0.0.0.0/0"
}

{{- if $isKubernetesCluster }}
{{-   if $K8sHasAPIServer }}

resource "exoscale_security_group_rule" "kube_api_{{ $resourceSuffix }}" {
  provider          = exoscale.networking_{{ $resourceSuffix }}
  security_group_id = exoscale_security_group.{{ $sgResourceName }}.id
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 6443
  end_port          = 6443
  cidr              = "0.0.0.0/0"
}

{{-   end }}{{/* if $K8sHasAPIServer */}}
{{- end }}{{/* if $isKubernetesCluster */}}

{{- if $isLoadbalancerCluster }}
{{-   range $role := $LoadBalancerRoles }}

resource "exoscale_security_group_rule" "lb_{{ $role.Port }}_{{ $resourceSuffix }}" {
  provider          = exoscale.networking_{{ $resourceSuffix }}
  security_group_id = exoscale_security_group.{{ $sgResourceName }}.id
  type              = "INGRESS"
  protocol          = "{{ upper $role.Protocol }}"
  start_port        = {{ $role.Port }}
  end_port          = {{ $role.Port }}
  cidr              = "0.0.0.0/0"
}

{{-   end }}{{/* range $LoadBalancerRoles */}}
{{- end }}{{/* if $isLoadbalancerCluster */}}

output "{{ $sgResourceName }}" {
  value = exoscale_security_group.{{ $sgResourceName }}.id
}

output "claudie_ssh_port_{{ $resourceSuffix }}" {
  value = tostring(local.claudie_ssh_port_{{ $resourceSuffix }})
}
