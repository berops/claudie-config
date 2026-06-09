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
# Direct iptables rules are used instead of UFW because KubeOne disables UFW
# during node provisioning. KubeOne does not flush iptables INPUT rules.
# This template generates the firewall script as a Terraform local
# so that nodepool/node.tpl can reference it in startup_commands.

locals {
  # CloudRift's shared-IP NAT forwards the standard guest SSH port (22) to a
  # random host port (exposed via port_mappings), so the in-VM sshd must listen
  # on 22 for the forward to land. node.tpl keys the SSH-port output, the sshd
  # config, and the firewall rule off this local.
  claudie_ssh_port_{{ $resourceSuffix }} = 22
  cloudrift_firewall_script_{{ $resourceSuffix }} = <<-FWSCRIPT
# Allow established connections and loopback
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# Allow SSH
iptables -A INPUT -p tcp --dport ${local.claudie_ssh_port_{{ $resourceSuffix }}} -j ACCEPT
# Allow WireGuard
iptables -A INPUT -p udp --dport 51820 -j ACCEPT
{{- if $isKubernetesCluster }}
# Allow K8s API server
iptables -A INPUT -p tcp --dport 6443 -j ACCEPT
# Kubelet API (10250) is intentionally NOT opened here: control-plane and
# metrics-server reach the kubelet over the WireGuard mesh (node InternalIP is
# the wg IP), which the "-i wg0 -j ACCEPT" rule below already permits.
{{- end }}
{{- if $isLoadbalancerCluster }}
  {{- range $role := $LoadBalancerRoles }}
iptables -A INPUT -p {{ lower $role.Protocol }} --dport {{ $role.Port }} -j ACCEPT
  {{- end }}
{{- end }}
# Allow ICMP
iptables -A INPUT -p icmp -j ACCEPT
# Allow all traffic on WireGuard tunnel interface
iptables -A INPUT -i wg0 -j ACCEPT
# Set default policy to drop everything else
iptables -P INPUT DROP
# Block IPv6 traffic but allow loopback (kube-apiserver uses [::1]:6443 internally)
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
# Persist rules across reboots
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent > /dev/null 2>&1 || true
iptables-save > /etc/iptables/rules.v4
FWSCRIPT
}
