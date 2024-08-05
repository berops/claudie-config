{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "hetznerdns" {
    apitoken = "${file("{{ $specName }}")}"
    alias = "hetzner_dns_{{ $resourceSuffix }}"
}

data "hetznerdns_zone" "hetzner_zone_{{ $resourceSuffix }}" {
    provider = hetznerdns.hetzner_dns_{{ $resourceSuffix }}
    name = "{{ .Data.DNSZone }}"
}

{{ range $ip := .Data.RecordData.IP }}

    {{- $escapedIPv4 := replaceAll $ip.V4 "." "_"}}
    {{- $recordResourceName := printf "record_%s_%s" $escapedIPv4 $resourceSuffix }}

    resource "hetznerdns_record" "{{ $recordResourceName }}" {
      provider = hetznerdns.hetzner_dns_{{ $resourceSuffix }}
      zone_id = data.hetznerdns_zone.hetzner_zone_{{ $resourceSuffix }}.id
      name = "{{ $.Data.Hostname }}"
      value = "{{ $ip.V4 }}"
      type = "A"
      ttl= 300
    }

{{- end }}

{{- $clusterID := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}
output "{{ $clusterID }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = { "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-endpoint" = format("%s.%s", "{{ .Data.Hostname }}", "{{ .Data.DNSZone }}")}
}
