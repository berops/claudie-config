{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $region            := $nodepool.Details.Region }}
{{- $resourceSuffix    := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "oci" {
  tenancy_ocid      = "{{ $nodepool.Details.Provider.GetOci.TenancyOCID }}"
  user_ocid         = "{{ $nodepool.Details.Provider.GetOci.UserOCID }}"
  fingerprint       = "{{ $nodepool.Details.Provider.GetOci.KeyFingerprint }}"
  private_key_path  = "{{ $specName }}"
  region            = "{{ $region }}"
  alias             = "nodepool_{{ $resourceSuffix }}"
}
