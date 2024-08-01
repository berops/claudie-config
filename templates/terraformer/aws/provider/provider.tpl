{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "aws" {
  access_key = "{{ $.Data.Provider.GetAws.AccessKey }}"
  secret_key = file("{{ $specName }}")
  region     = "{{ $region }}"
  alias      = "nodepool_{{ $resourceSuffix }}"
  default_tags {
    tags = {
      Managed-by = "Claudie"
    }
  }
}

{{- end}}
