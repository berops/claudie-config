{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "exoscale" {
  key    = "{{ $nodepool.Details.Provider.GetExoscale.ApiKey }}"
  secret = file("{{ $specName }}")
  alias  = "nodepool_{{ $resourceSuffix }}"
}
