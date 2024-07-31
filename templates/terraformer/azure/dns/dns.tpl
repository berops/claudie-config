{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "azurerm" {
  features {}
  subscription_id = "{{ .Provider.GetAzure.SubscriptionID }}"
  tenant_id       = "{{ .Provider.GetAzure.TenantID }}"
  client_id       = "{{ .Provider.GetAzure.ClientID }}"
  client_secret   = "${file("{{ $specName }}")}"
  alias           = "dns_azure_{{ $resourceSuffix }}"
}

data "azurerm_dns_zone" "azure_zone_{{ $resourceSuffix }}" {
    provider = azurerm.dns_azure_{{ $resourceSuffix }}
    name     = "{{ .Data.DNSZone }}"
}

resource "azurerm_dns_a_record" "record_{{ $resourceSuffix }}" {
  provider            = azurerm.dns_azure_{{ $resourceSuffix }}
  name                = "{{ .Data.HostnameHash }}"
  zone_name           = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.name
  resource_group_name = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.resource_group_name
  ttl                 = 300
  records             = [
  {{- range $ip := .Data.RecordData.IP }}
  "{{ $ip.V4 }}",
  {{- end }}
  ]
}

output "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}" {
    value = { "{{ .Data.ClusterName }}-{{.Data.ClusterHash }}-endpoint" = format("%s.%s", azurerm_dns_a_record.record_{{ $resourceSuffix }}.name, azurerm_dns_a_record.record_{{ $resourceSuffix }}.zone_name)}
}
