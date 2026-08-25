{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "cloudrift" {
  token = file("{{ $specName }}")
  alias = "networking_{{ $resourceSuffix }}"
  {{- if .Data.Provider.GetCloudrift.TeamId }}
  team_id = "{{ .Data.Provider.GetCloudrift.TeamId }}"
  {{- end }}
}
