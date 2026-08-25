{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "cloudrift" {
  token = file("{{ $specName }}")
  alias = "nodepool_{{ $resourceSuffix }}"
  {{- if $nodepool.Details.Provider.GetCloudrift.TeamId }}
  team_id = "{{ $nodepool.Details.Provider.GetCloudrift.TeamId }}"
  {{- end }}
}
