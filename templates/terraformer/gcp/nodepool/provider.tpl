{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $gcpProject        := $nodepool.Details.Provider.GetGcp.Project }}
{{- $region            := $nodepool.Details.Region }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "google" {
  credentials = "${file("{{ $specName }}")}"
  project     = "{{ $gcpProject }}"
  region      = "{{ $region }}"
  alias       = "nodepool_{{ $resourceSuffix }}"
}
