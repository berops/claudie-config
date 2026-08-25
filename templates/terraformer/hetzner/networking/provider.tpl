{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "hcloud" {
  token = "${file("{{ $specName }}")}"
  alias = "networking_{{ $resourceSuffix }}"
}
