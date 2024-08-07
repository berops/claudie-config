{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- range $_, $nodepool := .Data.NodePools }}

{{- $region                     := $nodepool.Details.Region }}
{{- $specName                   := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix             := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- $computeSubnetResourceName  := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $computeSubnetName          := printf "snt-%s-%s-%s" $clusterHash $region $nodepool.Name }}
{{- $computeSubnetCIDR          := $nodepool.Details.Cidr }}

resource "google_compute_subnetwork" "{{ $computeSubnetResourceName }}" {
  provider      = google.nodepool_{{ $resourceSuffix }}
  name          = "{{ $computeSubnetName }}"
  network       = google_compute_network.network_{{ $resourceSuffix }}.self_link
  ip_cidr_range = "{{ $computeSubnetCIDR }}"
  description   = "Managed by Claudie for cluster {{ $clusterName }}-{{ $clusterHash }}"
}

{{- end }}
