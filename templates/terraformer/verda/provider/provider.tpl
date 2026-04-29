{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "verda" {
  client_id     = "{{ .Data.Provider.GetVerda.ClientId }}"
  client_secret = file("{{ $specName }}")
{{- if .Data.Provider.GetVerda.BaseUrl }}
  base_url      = "{{ .Data.Provider.GetVerda.BaseUrl }}"
{{- end }}
  alias         = "nodepool_{{ $resourceSuffix }}"
}
