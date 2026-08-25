{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $region            := $nodepool.Details.Region }}
{{- $resourceSuffix    := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "openstack" {
  auth_url                      = "{{ $nodepool.Details.Provider.GetOpenstack.AuthURL }}"
  domain_id                     = "{{ $nodepool.Details.Provider.GetOpenstack.DomainID }}"
  tenant_id                     = "{{ $nodepool.Details.Provider.GetOpenstack.ProjectID }}"
  application_credential_id     = "{{ $nodepool.Details.Provider.GetOpenstack.ApplicationCredentialID }}"
  application_credential_secret = "{{ $nodepool.Details.Provider.GetOpenstack.ApplicationCredentialSecret }}"
  region                        = "{{ $region }}"
  alias                         = "nodepool_{{ $resourceSuffix }}"
}
