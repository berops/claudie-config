{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}

    {{- $escapedAlternativeName := sanitizeStringForResourceName $alternativeName }}
    {{- $recordResourceName     := printf "record_%s_%s" $escapedAlternativeName $resourceSuffix }}

    resource "ovh_domain_zone_record" "{{ $recordResourceName }}" {
        provider  = ovh.dns_{{ $resourceSuffix }}
        zone      = "{{ $.Data.DNSZone }}"
        subdomain = "{{ $alternativeName }}"
        fieldtype = "CNAME"
        target    = "{{ $.Data.Hostname }}.{{ $.Data.DNSZone }}"
        ttl       = 60
    }

	output "{{ $clusterID }}_{{ $escapedAlternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = format("%s.%s", "{{ $alternativeName }}", "{{ $.Data.DNSZone }}")}
	}

	{{- end }}
{{- end }}
