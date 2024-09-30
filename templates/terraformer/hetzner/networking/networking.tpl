{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}
{{- $resourceSuffix        := printf "%s_%s" $specName $uniqueFingerPrint }}

{{- $firewallResourceName  := printf "firewall_%s" $resourceSuffix }}
{{- $firewallName  := printf "fwl-%s-%s-%s" $clusterHash $specName $uniqueFingerPrint }}

resource "hcloud_firewall" "{{ $firewallResourceName }}" {
  provider = hcloud.nodepool_{{ $resourceSuffix }}
  name     = "{{ $firewallName }}"
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

{{- if $isLoadbalancerCluster }}
  {{- range $role := $LoadBalancerRoles }}
  rule {
    direction  = "in"
    protocol   = "{{ $role.Protocol }}"
    port       = "{{ $role.Port }}"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  {{- end }}
{{- end }}

{{- if $isKubernetesCluster }}
  {{- if $K8sHasAPIServer }}
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  {{- end }}
{{- end }}

  labels = {
    "managed-by"      : "Claudie"
    "claudie-cluster" : "{{ $clusterName }}-{{ $clusterHash }}"
  }
}
