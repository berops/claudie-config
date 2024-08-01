{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Data.Regions }}

{{- $sanitisedRegion := replaceAll $region " " "_"}}
{{- $resourceSuffix := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}

provider "azurerm" {
  features {}
  subscription_id = "{{ $.Data.Provider.GetAzure.SubscriptionID }}"
  tenant_id       = "{{ $.Data.Provider.GetAzure.TenantID }}"
  client_id       = "{{ $.Data.Provider.GetAzure.ClientID }}"
  client_secret   = file("{{ $specName }}")
  alias           = "nodepool_{{ $resourceSuffix }}"
}

{{- end}}
