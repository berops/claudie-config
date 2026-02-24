{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "hcloud" {
    token = "${file("{{ $specName }}")}"
    alias = "hetzner_dns_{{ $resourceSuffix }}"
}

data "hcloud_zone" "hetzner_zone_{{ $resourceSuffix }}" {
    provider = hcloud.hetzner_dns_{{ $resourceSuffix }}
    name = "{{ .Data.DNSZone }}"
}


{{ range $ip := .Data.RecordData.IP }}

  {{- $escapedIPv4 := replaceAll $ip.V4 "." "_"}}
  {{- $recordResourceName := printf "record_%s_%s" $escapedIPv4 $resourceSuffix }}

  resource "hcloud_zone_rrset" "{{ $recordResourceName }}" {
    provider = hcloud.hetzner_dns_{{ $resourceSuffix }}
    zone     = data.hcloud_zone.hetzner_zone_{{ $resourceSuffix }}.id
    name     = "{{ $.Data.Hostname }}"
    type     = "A"
    ttl      = 300

    records = [
        { value = "{{ $ip.V4 }}" }
    ]
  }

{{- end }}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
  value = { "{{ $clusterID }}-endpoint" = format("%s.%s", "{{ .Data.Hostname }}", "{{ .Data.DNSZone }}")}
}
