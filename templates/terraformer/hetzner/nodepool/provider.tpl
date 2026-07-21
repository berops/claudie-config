{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "hcloud" {
  token = "${file("{{ $specName }}")}"
  alias = "nodepool_{{ $resourceSuffix }}"
}
