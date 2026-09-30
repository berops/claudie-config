{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "vastai" {
  api_key = file("{{ $specName }}")
  alias = "networking_{{ $resourceSuffix }}_personal"
}

{{- with .Data.Provider.GetVastai.GetTeamApiKey }}
provider "vastai" {
  api_key = "{{ . }}"
  alias = "networking_{{ $resourceSuffix }}_team"
}
{{- end }}
