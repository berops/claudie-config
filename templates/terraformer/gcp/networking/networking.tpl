{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}

{{- range $_, $region := .Data.Regions}}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- if $isKubernetesCluster }}
    {{- $varStorageDiskName  := printf "gcp_storage_disk_name_%s" $resourceSuffix }}
    variable "{{ $varStorageDiskName}}" {
      default = "storage-disk"
      type    = string
    }
{{- end }}

{{- $computeNetworkResourceName  := printf "network_%s"   $resourceSuffix }}
{{- $computeNetworkName          := printf "net%s%s-%s"   $clusterHash $uniqueFingerPrint $region }}

resource "google_compute_network" "{{ $computeNetworkResourceName }}" {
  provider                = google.nodepool_{{ $resourceSuffix }}
  name                    = "{{ $computeNetworkName }}"
  auto_create_subnetworks = false
  description             = "Managed by Claudie for cluster {{ $clusterName }}-{{ $clusterHash }}"
}

{{- $computeFirewallResourceName     := printf "firewall_%s"  $resourceSuffix }}
{{- $computeFirewallName             := printf "fwl%s%s-%s"   $clusterHash $uniqueFingerPrint $region }}


resource "google_compute_firewall" "{{ $computeFirewallResourceName }}" {
  provider     = google.nodepool_{{ $resourceSuffix }}
  name         = "{{ $computeFirewallName }}"
  network      = google_compute_network.{{ $computeNetworkResourceName }}.self_link
  description  = "Managed by Claudie for cluster {{ $clusterName }}-{{ $clusterHash }}"

{{- if $isLoadbalancerCluster }}
    {{- range $role :=  $LoadBalancerRoles }}
    allow {
        protocol = "{{ $role.Protocol }}"
        ports = ["{{ $role.Port }}"]
    }
  {{- end }}
{{- end }}

{{- if $isKubernetesCluster }}
  {{- if $K8sHasAPIServer }}
  allow {
      protocol = "TCP"
      ports    = ["6443"]
  }
  {{- end }}
{{- end }}

  allow {
    protocol = "UDP"
    ports    = ["51820"]
  }

  allow {
      protocol = "TCP"
      ports    = ["22"]
  }

  allow {
      protocol = "icmp"
   }

  source_ranges = [
      "0.0.0.0/0",
   ]
}
{{- end }}

