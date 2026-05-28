{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "ovh" {
  endpoint      = "{{ .Data.Provider.GetOvh.Endpoint | default "ovh-eu" }}"
  client_id     = "{{ .Data.Provider.GetOvh.ClientId }}"
  client_secret = file("{{ $specName }}")
  alias         = "nodepool_{{ $resourceSuffix }}"
}
