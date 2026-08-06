{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "ovh" {
  endpoint      = "{{ $nodepool.Details.Provider.GetOvh.Endpoint | default "ovh-eu" }}"
  client_id     = "{{ $nodepool.Details.Provider.GetOvh.ClientId }}"
  client_secret = file("{{ $specName }}")
  alias         = "nodepool_{{ $resourceSuffix }}"
}
