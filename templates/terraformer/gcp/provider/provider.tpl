{{- $specName          := .Data.Provider.SpecName }}
{{- $gcpProject        := .Data.Provider.GetGcp.Project }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions}}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "google" {
  credentials = "${file("{{ $specName }}")}"
  project     = "{{ $gcpProject }}"
  region      = "{{ $region }}"
  alias       = "nodepool_{{ $resourceSuffix }}"
}
{{- end}}
