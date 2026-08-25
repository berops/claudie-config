{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $region            := $nodepool.Details.Region }}
{{- $resourceSuffix    := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

provider "aws" {
  access_key = "{{ $nodepool.Details.Provider.GetAws.AccessKey }}"
  secret_key = file("{{ $specName }}")
  region     = "{{ $region }}"
  alias      = "nodepool_{{ $resourceSuffix }}"
  default_tags {
    tags = {
      Managed-by = "Claudie"
    }
  }
}
