{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID 	       := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}

    {{- $escapedAlternativeName := sanitizeStringForResourceName $alternativeName }}
    {{- $recordResourceName     := printf "record_%s_%s" $escapedAlternativeName $resourceSuffix }}

    resource "hcloud_zone_rrset" "{{ $recordResourceName }}" {
        provider = hcloud.hetzner_dns_{{ $resourceSuffix }}
        zone     = data.hcloud_zone.hetzner_zone_{{ $resourceSuffix }}.id
        name     = "{{ $alternativeName }}"
        type     = "CNAME"
        ttl      = 300

        records = [
            {value = "{{ $.Data.Hostname }}.{{ $.Data.DNSZone }}."}
        ]
    }

	output "{{ $clusterID }}_{{ $escapedAlternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = format("%s.%s", "{{ $alternativeName }}", "{{ $.Data.DNSZone }}") }
	}

	{{- end }}
{{- end }}
