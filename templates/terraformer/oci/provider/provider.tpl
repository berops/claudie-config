{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "oci" {
  tenancy_ocid      = "{{ $.Provider.GetOci.TenancyOCID }}"
  user_ocid         = "{{ $.Provider.GetOci.UserOCID }}"
  fingerprint       = "{{ $.Provider.GetOci.KeyFingerprint }}"
  private_key_path  = "{{ $specName }}"
  region            = "{{ $region }}"
  alias             = "nodepool_{{ $resourceSuffix }}"
}
{{- end }}
