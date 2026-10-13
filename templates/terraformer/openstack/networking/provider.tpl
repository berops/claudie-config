{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $rn := .Data.RegionNetwork }}

{{- $resourceSuffix := printf "%s_%s_%s_%s" $rn.Region (sanitizeStringForResourceName $rn.ExternalNetwork) $specName $uniqueFingerPrint }}

provider "openstack" {
  auth_url                      = "{{ $.Data.Provider.GetOpenstack.AuthURL }}"
  domain_id                     = "{{ $.Data.Provider.GetOpenstack.DomainID }}"
  tenant_id                     = "{{ $.Data.Provider.GetOpenstack.ProjectID }}"
  application_credential_id     = "{{ $.Data.Provider.GetOpenstack.ApplicationCredentialID }}"
  application_credential_secret = "{{ $.Data.Provider.GetOpenstack.ApplicationCredentialSecret }}"
  region                        = "{{ $rn.Region }}"
  alias                         = "networking_{{ $resourceSuffix }}"
}

{{- end }}{{/* range .Data.RegionNetwork */}}
