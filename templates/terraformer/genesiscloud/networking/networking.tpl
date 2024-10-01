{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

data "genesiscloud_images" "base_os_{{ $resourceSuffix }}" {
  provider   = genesiscloud.nodepool_{{ $resourceSuffix }}
  filter = {
    type   = "base-os"
    region = "{{ $region }}"
  }
}

{{- $securityGroupResourceName := printf "claudie_security_group_%s" $resourceSuffix }}
{{- $securityGroupName         := printf "sg%s-%s-%s-%s" $clusterHash $region $specName $uniqueFingerPrint }}

resource "genesiscloud_security_group" "{{ $securityGroupResourceName }}" {
  provider = genesiscloud.nodepool_{{ $resourceSuffix }}
  name   = "{{ $securityGroupName }}"
  region = "{{ $region }}"
  rules = [
    {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 22
      port_range_max = 22
    },
    {
      direction      = "ingress"
      protocol       = "tcp"
      port_range_min = 51820
      port_range_max = 51820
    },
{{- if $isLoadbalancerCluster }}
    {{- range $role := $LoadBalancerRoles }}
    {
      direction      = "ingress"
      protocol       = "{{ $role.Protocol }}"
      port_range_min = {{ $role.Port }}
      port_range_max = {{ $role.Port }}
    },
    {{- end }}
{{- end }}

{{- if $isKubernetesCluster }}
    {{- if $K8sHasAPIServer }}
     {
       direction      = "ingress"
       protocol       = "tcp"
       port_range_min = 6443
       port_range_max = 6443
     },
    {{- end }}
{{- end }}

    {
      direction      = "ingress"
      protocol       = "icmp"
    }
  ]
}
{{- end }}
