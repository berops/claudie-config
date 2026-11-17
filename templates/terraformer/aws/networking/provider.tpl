{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "aws" {
  access_key = "{{ $.Data.Provider.GetAws.AccessKey }}"
  secret_key = file("{{ $specName }}")
  region     = "{{ $region }}"
  alias      = "networking_{{ $resourceSuffix }}"
  # max_retries is the total number of attempts: 1 = no retries. 0 is ignored
  max_retries = 1
  default_tags {
    tags = {
      Managed-by = "Claudie"
    }
  }
}

{{- end }}{{/* range .Data.Regions */}}
