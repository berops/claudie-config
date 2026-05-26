{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}
{{- $resourceSuffix        := printf "%s_%s" $specName $uniqueFingerPrint }}

# The OVH OpenTofu provider has no cloud-level security group or firewall resources.
# OVH Public Cloud security groups live in the OpenStack layer; to keep this provider
# self-contained we configure host-level iptables instead (same approach as CloudRift).
# KubeOne disables UFW during node provisioning but leaves iptables INPUT rules intact.
# This template emits the firewall script as a Terraform local so that
# nodepool/node.tpl can reference it inside the instance's user_data.

locals {
  claudie_ssh_port_{{ $resourceSuffix }} = 22522

  # Cloud-init bootstrap shared by every OVH instance in this cluster: enable
  # root SSH from the ubuntu/debian default user and move sshd to the Claudie
  # port via a systemd socket override.
  ovh_bootstrap_script_{{ $resourceSuffix }} = <<-BOOTSCRIPT
# Enable root SSH access
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
if [ -f /home/debian/.ssh/authorized_keys ]; then
    cp /home/debian/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Configure SSH port
echo "Port ${local.claudie_ssh_port_{{ $resourceSuffix }}}" >> /etc/ssh/sshd_config
mkdir -p /etc/systemd/system/ssh.socket.d
cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:${local.claudie_ssh_port_{{ $resourceSuffix }}}
SSHEOF
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
BOOTSCRIPT

  ovh_firewall_script_{{ $resourceSuffix }} = <<-FWSCRIPT
# Allow established connections and loopback
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# Allow SSH
iptables -A INPUT -p tcp --dport ${local.claudie_ssh_port_{{ $resourceSuffix }}} -j ACCEPT
# Allow WireGuard
iptables -A INPUT -p udp --dport 51820 -j ACCEPT
{{- if $isKubernetesCluster }}
{{- if $K8sHasAPIServer }}
# Allow K8s API server
iptables -A INPUT -p tcp --dport 6443 -j ACCEPT
{{- end }}
# Allow kubelet API
iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
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
