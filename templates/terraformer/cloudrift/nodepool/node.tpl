{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $nodepool := .Data.NodePools }}

{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix := printf "%s_%s" $specName $uniqueFingerPrint }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName         := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

    resource "cloudrift_ssh_key" "{{ $sshKeyResourceName }}" {
      provider   = cloudrift.nodepool_{{ $resourceSuffix }}
      name       = "{{ $sshKeyName }}"
      public_key = file("./{{ $nodepool.Name }}")
    }

    {{- range $node := $nodepool.Nodes }}

        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}

        resource "cloudrift_virtual_machine" "{{ $serverResourceName }}" {
          provider      = cloudrift.nodepool_{{ $resourceSuffix }}
          name          = "{{ $node.Name }}"
          recipe        = "{{ $nodepool.Details.Image }}"
          datacenter    = "{{ $nodepool.Details.Region }}"
          instance_type = "{{ $nodepool.Details.ServerType }}"
          ssh_key_id    = cloudrift_ssh_key.{{ $sshKeyResourceName }}.id

          metadata = {
            startup_commands = base64encode(<<-SCRIPT
#!/bin/bash
# Enable root SSH access
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/riftuser/.ssh/authorized_keys ]; then
    sed -n 's/^.*ssh-rsa/ssh-rsa/p' /home/riftuser/.ssh/authorized_keys > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'PubkeyAcceptedKeyTypes=+ssh-rsa' >> /etc/ssh/sshd_config
# Configure SSH port
echo "Port ${local.claudie_ssh_port_{{ $resourceSuffix }}}" >> /etc/ssh/sshd_config
mkdir -p /etc/systemd/system/ssh.socket.d
cat <<SSHEOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:${local.claudie_ssh_port_{{ $resourceSuffix }}}
SSHEOF
systemctl daemon-reload
systemctl restart ssh.socket
sshd_active=$(systemctl is-active sshd 2>/dev/null || true)
ssh_active=$(systemctl is-active ssh 2>/dev/null || true)
if [ "$sshd_active" = "active" ]; then
    systemctl restart sshd
fi
if [ "$ssh_active" = "active" ]; then
    systemctl restart ssh
fi

# Fix NAT hairpinning - allow node to reach its own public IP
PUBLIC_IP=$(curl -4 -s --connect-timeout 5 ifconfig.me)
PRIVATE_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
if [ -n "$PUBLIC_IP" ] && [ -n "$PRIVATE_IP" ]; then
    iptables -t nat -A OUTPUT -d "$PUBLIC_IP" -j DNAT --to-destination "$PRIVATE_IP"
fi

# Configure iptables firewall (not UFW — KubeOne disables UFW)
${local.cloudrift_firewall_script_{{ $resourceSuffix }}}

{{- if $isKubernetesCluster }}

# Create longhorn volume directory
mkdir -p /opt/claudie/data
{{- end }}
SCRIPT
            )
          }
        }

    {{- end }}

# Output: [public_ip, ssh_port, wireguard_port] per node.
#
# CloudRift's port_mappings entries are {host_port, guest_port} where, despite the
# names, host_port is the IN-VM service port (22, 80, 443, ...) and guest_port is
# the externally reachable port on the SHARED public IP (e.g. 60002). So to reach
# the VM's SSH (in-VM port = claudie_ssh_port) we connect to the public IP on the
# matching guest_port. CloudRift forwards a fixed set of in-VM ports (22/80/443/
# 8080/8443); WireGuard's 51820 is NOT forwarded, so it falls back to 51820 and the
# node relies on initiating the tunnel outbound (PersistentKeepalive).
#
# Dedicated-IP instances have empty port_mappings, so both ports fall back to the
# in-VM listen ports reached directly on the public IP.
output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        {{- $portMappings := printf "cloudrift_virtual_machine.%s.port_mappings" $serverResourceName }}
        "{{ $node.Name }}" = [
          cloudrift_virtual_machine.{{ $serverResourceName }}.public_ip,
          tostring(coalesce(one([for m in ({{ $portMappings }} == null ? [] : {{ $portMappings }}) : m.guest_port if m.host_port == local.claudie_ssh_port_{{ $resourceSuffix }}]), local.claudie_ssh_port_{{ $resourceSuffix }})),
          tostring(coalesce(one([for m in ({{ $portMappings }} == null ? [] : {{ $portMappings }}) : m.guest_port if m.host_port == 51820]), 51820)),
        ]
    {{- end }}
  }
}
{{- end }}
