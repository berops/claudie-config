{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}
    {{- $recordResourceName := printf "record_%s_%s" $alternativeName $resourceSuffix }}

    resource "ovh_domain_zone_record" "{{ $recordResourceName }}" {
        provider  = ovh.dns_{{ $resourceSuffix }}
        zone      = "{{ $.Data.DNSZone }}"
        subdomain = "{{ $alternativeName }}"
        fieldtype = "CNAME"
        target    = "{{ $.Data.Hostname }}.{{ $.Data.DNSZone }}."
        ttl       = 60
    }

	output "{{ $clusterID }}_{{ $alternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = format("%s.%s", "{{ $alternativeName }}", "{{ $.Data.DNSZone }}")}
	}

	{{- end }}
{{- end }}
