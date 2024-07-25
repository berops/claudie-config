{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "hetznerdns" {
    apitoken = "${file("{{ $specName }}")}"
    alias = "hetzner_dns_{{ $resourceSuffix }}"
}

data "hetznerdns_zone" "hetzner-zone_{{ $resourceSuffix }}" {
    provider = hetznerdns.hetzner_dns_{{ $resourceSuffix }}
    name = "{{ .Data.DNSZone }}"
}

{{ range $ip := .Data.RecordData.IP }}

    {{- $recordResourceName := printf "record_%s_%s" $ip.EscapedV4 $resourceSuffix }}

    resource "hetznerdns_record" "{{ $recordResourceName }}" {
      provider = hetznerdns.hetzner_dns_{{ $resourceSuffix }}
      zone_id = data.hetznerdns_zone.hetzner-zone_{{ $resourceSuffix }}.id
      name = "{{ $.Data.HostnameHash }}"
      value = "{{ $ip.V4 }}"
      type = "A"
      ttl= 300
    }

{{- end }}

output "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-{{ $uniqueFingerPrint }}" {
  value = { "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-endpoint" = format("%s.%s", "{{ .Data.HostnameHash }}", "{{ .Data.DNSZone }}")}
}