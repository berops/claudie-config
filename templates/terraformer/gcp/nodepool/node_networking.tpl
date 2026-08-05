{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- $nodepool                   := .Data.NodePool }}
{{- $region                     := $nodepool.Details.Region }}
{{- $specName                   := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix             := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}
{{- $networking                 := .Data.Networking.All }}
{{- $networkSelfLink            := index $networking (printf "network_%s" $resourceSuffix) }}

{{- if not $networkSelfLink }}{{ template "node_networking.tpl: missing output 'network_<region>_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

{{- $computeSubnetResourceName  := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $computeSubnetName          := printf "snt-%s-%s-%s" $clusterHash $region $nodepool.Name }}
{{- $computeSubnetCIDR          := $nodepool.Details.Cidr }}

resource "google_compute_subnetwork" "{{ $computeSubnetResourceName }}" {
  provider      = google.nodepool_{{ $resourceSuffix }}
  name          = "{{ $computeSubnetName }}"
  network       = "{{ $networkSelfLink }}"
  ip_cidr_range = "{{ $computeSubnetCIDR }}"
  description   = "Managed by Claudie for cluster {{ $clusterName }}-{{ $clusterHash }}"
}
