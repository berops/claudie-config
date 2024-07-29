{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "genesiscloud" {
    token = "${file("{{ $specName }}")}"
    alias = "nodepool_{{ $resourceSuffix }}"
}

{{- end }}
