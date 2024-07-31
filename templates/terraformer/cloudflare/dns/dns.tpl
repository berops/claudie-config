{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "cloudflare" {
  api_token = "${file("{{ $specName }}")}"
  alias = "cloudflare_dns_{{ $resourceSuffix }}"
}

data "cloudflare_zone" "cloudflare-zone-{{ $resourceSuffix }}" {
  provider   = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
  name       = "{{ .Data.DNSZone }}"
}

{{- range $ip := .Data.RecordData.IP }}

    {{- $recordResourceName := printf "record-%s-%s" $ip.EscapedV4 $resourceSuffix }}

resource "cloudflare_record" "record-{{ replaceAll $IP "." "-" }}" {
  provider = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
  zone_id  = data.cloudflare_zone.cloudflare-zone-{{ $resourceSuffix }}.id
  name     = "{{ $.Data.HostnameHash }}"
  value    = "{{ $ip.V4 }}"
  type     = "A"
  ttl      = 300
}

{{- end }}

output "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-{{ $uniqueFingerPrint }}" {
  value = { "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-endpoint" = format("%s.%s", "{{ .Data.HostnameHash }}", "{{ .Data.DNSZone }}")}
}
