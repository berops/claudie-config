{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $sanitisedRegion := replaceAll $region " " "_"}}
{{- $resourceSuffix  := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}

provider "azurerm" {
  features {}
  # azurerm >= 5.0 defaults to registering no resource providers ("none");
  # "core" keeps Microsoft.Compute/Network/Storage auto-registered, matching
  # the pre-5.0 behaviour.
  resource_provider_registrations = "core"
  subscription_id                 = "{{ $.Data.Provider.GetAzure.SubscriptionID }}"
  tenant_id                       = "{{ $.Data.Provider.GetAzure.TenantID }}"
  client_id                       = "{{ $.Data.Provider.GetAzure.ClientID }}"
  client_secret                   = file("{{ $specName }}")
  alias                           = "networking_{{ $resourceSuffix }}"
}

{{- end }}{{/* range .Data.Regions */}}
