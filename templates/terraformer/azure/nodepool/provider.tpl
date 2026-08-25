{{- $nodepool          := .Data.NodePool }}
{{- $specName          := $nodepool.Details.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $sanitisedRegion   := replaceAll $nodepool.Details.Region " " "_"}}
{{- $resourceSuffix    := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}

provider "azurerm" {
  features {}
  # azurerm >= 5.0 defaults to registering no resource providers ("none");
  # "core" keeps Microsoft.Compute/Network/Storage auto-registered, matching
  # the pre-5.0 behaviour.
  resource_provider_registrations = "core"
  subscription_id                 = "{{ $nodepool.Details.Provider.GetAzure.SubscriptionID }}"
  tenant_id                       = "{{ $nodepool.Details.Provider.GetAzure.TenantID }}"
  client_id                       = "{{ $nodepool.Details.Provider.GetAzure.ClientID }}"
  client_secret                   = file("{{ $specName }}")
  alias                           = "nodepool_{{ $resourceSuffix }}"
}
