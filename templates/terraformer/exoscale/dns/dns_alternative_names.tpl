{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}
    {{- $recordResourceName := printf "record_%s_%s" $alternativeName $resourceSuffix }}

    resource "exoscale_domain_record" "{{ $recordResourceName }}" {
        provider    = exoscale.dns_{{ $resourceSuffix }}
        domain      = data.exoscale_domain.dns_zone_{{ $resourceSuffix }}.id
        name        = "{{ $alternativeName }}"
        content     = "{{ $.Data.Hostname }}.{{ $.Data.DNSZone }}"
        record_type = "CNAME"
        ttl         = 300
    }

	output "{{ $clusterID }}_{{ $alternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = format("%s.%s", "{{ $alternativeName }}", "{{ $.Data.DNSZone }}")}
	}

	{{- end }}
{{- end }}
