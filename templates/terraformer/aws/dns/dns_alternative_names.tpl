{{- $hostname          := .Data.Hostname }}
{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID 	       := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

{{- if hasExtension .Data "AlternativeNamesExtension" }}
	{{- range $_, $alternativeName := .Data.AlternativeNamesExtension.Names }}

    {{- $escapedAlternativeName := sanitizeStringForResourceName $alternativeName }}
    {{- $recordResourceName     := printf "record_%s_%s" $escapedAlternativeName $resourceSuffix }}

    resource "aws_route53_record" "{{ $recordResourceName }}" {
      provider    = aws.dns_aws_{{ $resourceSuffix }}
      zone_id     = "${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.zone_id }"
      name        = "{{ $alternativeName }}"
      type        = "CNAME"
      ttl         = 300
      records     = ["{{ $hostname }}.${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.name}"]

      set_identifier = "record_{{ $alternativeName }}_{{ $resourceSuffix }}"
      weighted_routing_policy {
        weight = 1
      }
    }

	output "{{ $clusterID }}_{{ $escapedAlternativeName }}_{{ $resourceSuffix }}" {
	  value = { "{{ $clusterID }}-{{ $alternativeName }}-endpoint" = aws_route53_record.{{ $recordResourceName }}.fqdn }
	}

	{{- end }}
{{- end }}
