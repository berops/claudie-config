{{- $hostname          := .Data.Hostname }}
{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID 	       := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}

    {{- $escapedAlternativeName := sanitizeStringForResourceName $alternativeName }}
    {{- $recordResourceName     := printf "record_%s_%s" $escapedAlternativeName $resourceSuffix }}

	resource "oci_dns_rrset" "{{ $recordResourceName }}" {
		provider        = oci.dns_oci_{{ $resourceSuffix }}
		domain          = "{{ $alternativeName }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"
		rtype           = "CNAME"
		zone_name_or_id = data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name

		items {
    		domain = "{{ $alternativeName }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"
			rtype  = "CNAME"
			ttl    = 300
			rdata  = "{{ $hostname }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"
  		}
	}
	output "{{ $clusterID }}_{{ $escapedAlternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = oci_dns_rrset.{{ $recordResourceName }}.domain }
	}
	{{- end }}
{{- end }}
