{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}


{{- range $nodepool := .Data.NodePools }}

{{- $specName       := $nodepool.Details.Provider.SpecName }}
{{- $serviceName    := $nodepool.Details.Provider.GetOvh.ServiceName }}
{{- $resourceSuffix := printf "%s_%s" $specName $uniqueFingerPrint }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
{{- $sshKeyName         := printf "key-%s-%s-%s" $nodepool.Name $clusterHash $specName }}

    resource "ovh_cloud_project_ssh_key" "{{ $sshKeyResourceName }}" {
      provider     = ovh.nodepool_{{ $resourceSuffix }}
      service_name = "{{ $serviceName }}"
      name         = "{{ $sshKeyName }}"
      public_key   = file("./{{ $nodepool.Name }}")
    }

    {{- range $node := $nodepool.Nodes }}

        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}

        resource "ovh_cloud_project_instance" "{{ $serverResourceName }}" {
          provider       = ovh.nodepool_{{ $resourceSuffix }}
          service_name   = "{{ $serviceName }}"
          region         = "{{ $nodepool.Details.Region }}"
{{- if $nodepool.Details.Zone }}
          availability_zone = "{{ $nodepool.Details.Zone }}"
{{- end }}
          billing_period = "hourly"
          name           = "{{ $node.Name }}"

          boot_from {
            image_id = "{{ $nodepool.Details.Image }}"
          }

          flavor {
            flavor_id = "{{ $nodepool.Details.ServerType }}"
          }

          ssh_key {
            name = ovh_cloud_project_ssh_key.{{ $sshKeyResourceName }}.name
          }

          network {
            public = true
          }

          user_data = <<-EOF
#!/bin/bash
${local.ovh_bootstrap_script_{{ $resourceSuffix }}}

# Configure iptables firewall (not UFW, KubeOne disables UFW)
${local.ovh_firewall_script_{{ $resourceSuffix }}}

{{- if $isKubernetesCluster }}
# Longhorn data directory on the OS disk. storageDiskSize is currently
# ignored on OVH: the upstream Terraform provider exposes no resource to
# attach a separate volume to an instance, so data shares the OS disk.
mkdir -p /opt/claudie/data
{{- end }}
EOF
        }

    {{- end }}

output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
        {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
        "{{ $node.Name }}" = [
          [for addr in ovh_cloud_project_instance.{{ $serverResourceName }}.addresses : addr.ip if addr.version == 4][0],
          tostring(local.claudie_ssh_port_{{ $resourceSuffix }})
        ]
    {{- end }}
  }
}
{{- end }}
