{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID 	       := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}
    {{- $recordResourceName := printf "record_%s_%s" $alternativeName $resourceSuffix }}

    resource "cloudflare_record" "{{ $recordResourceName }}" {
        provider = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
        zone_id = data.cloudflare_zone.cloudflare_zone_{{ $resourceSuffix }}.id
        name = "{{ $alternativeName }}"
        value = "{{ $.Data.Hostname }}.{{ $.Data.DNSZone }}"
        type = "CNAME"
        ttl = 300
    }

	output "{{ $clusterID }}_{{ $alternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = format("%s.%s", "{{ $alternativeName }}", "{{ $.Data.DNSZone }}")}
	}
	{{- end }}
{{- end }}
