{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "exoscale" {
  key    = "{{ .Data.Provider.GetExoscale.ApiKey }}"
  secret = file("{{ $specName }}")
  alias  = "dns_{{ $resourceSuffix }}"
}

data "exoscale_domain" "dns_zone_{{ $resourceSuffix }}" {
  provider = exoscale.dns_{{ $resourceSuffix }}
  name     = "{{ .Data.DNSZone }}"
}

{{ range $ip := .Data.RecordData.IP }}

    {{- $escapedIPv4 := replaceAll $ip.V4 "." "_"}}
    {{- $recordResourceName := printf "record_%s_%s" $escapedIPv4 $resourceSuffix }}

    resource "exoscale_domain_record" "{{ $recordResourceName }}" {
      provider    = exoscale.dns_{{ $resourceSuffix }}
      domain      = data.exoscale_domain.dns_zone_{{ $resourceSuffix }}.id
      name        = "{{ $.Data.Hostname }}"
      content     = "{{ $ip.V4 }}"
      record_type = "A"
      ttl         = 300
    }

{{- end }}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
  value = { "{{ $clusterID }}-endpoint" = format("%s.%s", "{{ .Data.Hostname }}", "{{ .Data.DNSZone }}")}
}
