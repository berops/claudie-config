{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "verda" {
  client_id     = "{{ $nodepool.Details.Provider.GetVerda.ClientId }}"
  client_secret = file("{{ $specName }}")
  {{- if $nodepool.Details.Provider.GetVerda.BaseUrl }}
  base_url      = "{{ $nodepool.Details.Provider.GetVerda.BaseUrl }}"
  {{- end }}
  alias         = "nodepool_{{ $resourceSuffix }}"
}
