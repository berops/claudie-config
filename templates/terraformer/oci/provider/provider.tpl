{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "oci" {
  tenancy_ocid      = "{{ $.Data.Provider.GetOci.TenancyOCID }}"
  user_ocid         = "{{ $.Data.Provider.GetOci.UserOCID }}"
  fingerprint       = "{{ $.Data.Provider.GetOci.KeyFingerprint }}"
  private_key_path  = "{{ $specName }}"
  region            = "{{ $region }}"
  alias             = "nodepool_{{ $resourceSuffix }}"
}
{{- end }}
