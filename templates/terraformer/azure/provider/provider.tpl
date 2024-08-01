{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}

{{- range $_, $region := .Regions }}

{{- $sanitisedRegion := replaceAll $region " " "_"}}
{{- $resourceSuffix := printf "%s_%s_%s" $sanitisedRegion $specName $uniqueFingerPrint }}

provider "azurerm" {
  features {}
  subscription_id = "{{ $.Data.Provider.SubscriptionID }}"
  tenant_id       = "{{ $.Data.Provider.TenantID }}"
  client_id       = "{{ $.Data.Provider.ClientID }}"
  client_secret   = file("{{ $specName }}")
  alias           = "nodepool_{{ $resourceSuffix }}"
}

{{- end}}
