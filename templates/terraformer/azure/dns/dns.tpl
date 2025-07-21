{{- $hostname          := .Data.Hostname }}
{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "azurerm" {
  features {}
  subscription_id = "{{ .Data.Provider.GetAzure.SubscriptionID }}"
  tenant_id       = "{{ .Data.Provider.GetAzure.TenantID }}"
  client_id       = "{{ .Data.Provider.GetAzure.ClientID }}"
  client_secret   = "${file("{{ $specName }}")}"
  alias           = "dns_azure_{{ $resourceSuffix }}"
}

data "azurerm_dns_zone" "azure_zone_{{ $resourceSuffix }}" {
  provider = azurerm.dns_azure_{{ $resourceSuffix }}
  name     = "{{ .Data.DNSZone }}"
}

resource "azurerm_traffic_manager_profile" "traffic_manager_{{ $hostname }}_{{ $resourceSuffix}}" {
  provider            = azurerm.dns_azure_{{ $resourceSuffix }}
  name                = "traffic-manager-{{ $hostname }}"
  resource_group_name = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.resource_group_name

  traffic_routing_method = "Weighted"

  dns_config {
    relative_name = "{{ $hostname }}"
    ttl           = 30
  }

  monitor_config {
    protocol = "TCP"
    # Claudie creates a default role for loadbalancers which acts as a healthcheck, that is open on port 65534
    port     = 65534
  }
}

{{- range $_, $ip := .Data.RecordData.IP }}
  {{- $escapedIPv4 := replaceAll $ip.V4 "." "_" }}
  resource "azurerm_traffic_manager_external_endpoint" "endpoint_{{ $hostname }}_{{ $escapedIPv4 }}_{{ $resourceSuffix}}" {
    provider             = azurerm.dns_azure_{{ $resourceSuffix }}
    name                 = "{{ $hostname }}_{{ $escapedIPv4 }}_{{ $resourceSuffix}}"
    profile_id           = azurerm_traffic_manager_profile.traffic_manager_{{ $hostname }}_{{ $resourceSuffix}}.id
    weight               = 1
    target               = "{{ $ip.V4 }}"
  }
{{- end }}

resource "azurerm_dns_cname_record" "record_{{ $hostname }}_{{ $resourceSuffix }}" {
  provider            = azurerm.dns_azure_{{ $resourceSuffix }}
  name                = "{{ $hostname }}"
  zone_name           = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.name
  resource_group_name = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.resource_group_name
  ttl                 = 300
  record              = azurerm_traffic_manager_profile.traffic_manager_{{ $hostname }}_{{ $resourceSuffix}}.fqdn
}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
  value = { "{{ $clusterID }}-endpoint" = format("%s.%s", azurerm_dns_cname_record.record_{{ $hostname }}_{{ $resourceSuffix }}.name, azurerm_dns_cname_record.record_{{ $hostname }}_{{ $resourceSuffix }}.zone_name)}
}
