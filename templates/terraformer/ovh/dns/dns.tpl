{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "ovh" {
  endpoint      = "{{ .Data.Provider.GetOvh.Endpoint | default "ovh-eu" }}"
  client_id     = "{{ .Data.Provider.GetOvh.ClientId }}"
  client_secret = file("{{ $specName }}")
  alias         = "dns_{{ $resourceSuffix }}"
}

{{ range $ip := .Data.RecordData.IP }}

    {{- $escapedIPv4 := replaceAll $ip.V4 "." "_"}}
    {{- $recordResourceName := printf "record_%s_%s" $escapedIPv4 $resourceSuffix }}

    resource "ovh_domain_zone_record" "{{ $recordResourceName }}" {
      provider  = ovh.dns_{{ $resourceSuffix }}
      zone      = "{{ $.Data.DNSZone }}"
      subdomain = "{{ $.Data.Hostname }}"
      fieldtype = "A"
      target    = "{{ $ip.V4 }}"
      ttl       = 60
    }

{{- end }}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
  value = { "{{ $clusterID }}-endpoint" = format("%s.%s", "{{ .Data.Hostname }}", "{{ .Data.DNSZone }}")}
}
