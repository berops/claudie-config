{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "exoscale" {
  key    = "{{ .Data.Provider.GetExoscale.ApiKey }}"
  secret = file("{{ $specName }}")
  alias  = "nodepool_{{ $resourceSuffix }}"
}
