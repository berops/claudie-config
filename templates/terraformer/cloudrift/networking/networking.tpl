{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}
{{- $resourceSuffix        := printf "%s_%s" $specName $uniqueFingerPrint }}

# CloudRift does not provide cloud-level firewall or networking resources.
# UFW firewall rules are applied on each VM via startup commands.
# This template generates the UFW script as a Terraform local
# so that nodepool/node.tpl can reference it in startup_commands.

locals {
  cloudrift_ufw_script_{{ $resourceSuffix }} = <<-UFWSCRIPT
apt-get update -qq > /dev/null 2>&1 || true
apt-get install -y -qq ufw > /dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
{{- if $isKubernetesCluster }}
ufw allow 6443/tcp
{{- end }}
{{- if $isLoadbalancerCluster }}
  {{- range $role := $LoadBalancerRoles }}
ufw allow {{ $role.Port }}/{{ lower $role.Protocol }}
  {{- end }}
{{- end }}
ufw --force enable
systemctl enable ufw
UFWSCRIPT
}
