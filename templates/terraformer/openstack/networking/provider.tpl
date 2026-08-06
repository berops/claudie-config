{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "openstack" {
  auth_url                      = "{{ $.Data.Provider.GetOpenstack.AuthURL }}"
  domain_id                     = "{{ $.Data.Provider.GetOpenstack.DomainID }}"
  tenant_id                     = "{{ $.Data.Provider.GetOpenstack.ProjectID }}"
  application_credential_id     = "{{ $.Data.Provider.GetOpenstack.ApplicationCredentialID }}"
  application_credential_secret = "{{ $.Data.Provider.GetOpenstack.ApplicationCredentialSecret }}"
  region                        = "{{ $region }}"
  alias                         = "networking_{{ $resourceSuffix }}"
}

{{- end }}{{/* range .Data.Regions */}}
