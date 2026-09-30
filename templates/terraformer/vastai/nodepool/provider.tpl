{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "vastai" {
  api_key = file("{{ $specName }}")
  alias = "nodepool_{{ $resourceSuffix }}_personal"
}

{{- with $nodepool.Details.Provider.GetVastai.GetTeamApiKey }}
provider "vastai" {
  api_key = "{{ . }}"
  alias = "nodepool_{{ $resourceSuffix }}_team"
}
{{- end }}
