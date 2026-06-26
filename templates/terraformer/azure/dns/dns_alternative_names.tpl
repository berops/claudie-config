{{- $hostname          := .Data.Hostname }}
{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID 	       := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

### Alternative Name must be as CNAME pointing to azure traffic manager profile
{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}


    {{- $escapedAlternativeName := sanitizeStringForResourceName $alternativeName }}
    {{- $recordResourceName     := printf "record_%s_%s" $escapedAlternativeName $resourceSuffix }}

	resource "azurerm_dns_cname_record" "{{ $recordResourceName }}" {
		provider            = azurerm.dns_azure_{{ $resourceSuffix }}
		name                = "{{ $alternativeName }}"
		zone_name           = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.name
		resource_group_name = data.azurerm_dns_zone.azure_zone_{{ $resourceSuffix }}.resource_group_name
		ttl                 = 300
		record              = azurerm_traffic_manager_profile.traffic_manager_{{ $hostname }}_{{ $resourceSuffix }}.fqdn
	}

	output "{{ $clusterID }}_{{ $escapedAlternativeName }}_{{ $resourceSuffix }}" {
		value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = trimsuffix(azurerm_dns_cname_record.{{ $recordResourceName }}.fqdn, ".")}
	}

	{{- end }}
{{- end }}
