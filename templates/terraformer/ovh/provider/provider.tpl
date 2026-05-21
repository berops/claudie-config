{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "ovh" {
{{- if .Data.Provider.GetOvh.Endpoint }}
  endpoint      = "{{ .Data.Provider.GetOvh.Endpoint }}"
{{- else }}
  endpoint      = "ovh-eu"
{{- end }}
  client_id     = "{{ .Data.Provider.GetOvh.ClientId }}"
  client_secret = file("{{ $specName }}")
  alias         = "nodepool_{{ $resourceSuffix }}"
}
