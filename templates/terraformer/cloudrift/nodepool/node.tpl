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

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        "{{ $node.Name }}" = cloudrift_virtual_machine.{{ $serverResourceName }}.public_ip
    {{- end }}
  }
}
{{- end }}
