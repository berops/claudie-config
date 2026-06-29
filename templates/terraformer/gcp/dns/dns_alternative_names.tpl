{{- $specName          := .Data.Provider.SpecName }}
{{- $hostname          := .Data.Hostname }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID 	       := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}

    {{- $escapedAlternativeName := sanitizeStringForResourceName $alternativeName }}
    {{- $recordResourceName     := printf "record_%s_%s" $escapedAlternativeName $resourceSuffix }}

	resource "google_dns_record_set" "{{ $recordResourceName }}" {
	  provider = google.dns_gcp_{{ $resourceSuffix }}

	  name = "{{ $alternativeName }}.${data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.dns_name}"
	  type = "CNAME"
	  ttl  = 300

	  managed_zone = data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.name
	  rrdatas = ["{{ $hostname }}.${data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.dns_name}"]
	}

	output "{{ $clusterID }}_{{ $escapedAlternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = trimsuffix(google_dns_record_set.{{ $recordResourceName }}.name, ".") }
	}
	{{- end }}
{{- end }}
