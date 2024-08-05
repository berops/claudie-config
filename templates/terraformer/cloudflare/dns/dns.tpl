{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "cloudflare" {
  api_token = "${file("{{ $specName }}")}"
  alias = "cloudflare_dns_{{ $resourceSuffix }}"
}

data "cloudflare_zone" "cloudflare_zone_{{ $resourceSuffix }}" {
  provider   = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
  name       = "{{ .Data.DNSZone }}"
}

{{- range $ip := .Data.RecordData.IP }}

    {{- $escapedIPv4 := replaceAll $ip.V4 "." "_"}}
    {{- $recordResourceName := printf "record_%s_%s" $escapedIPv4 $resourceSuffix }}

    resource "cloudflare_record" "{{ $recordResourceName }}" {
      provider = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
      zone_id  = data.cloudflare_zone.cloudflare_zone_{{ $resourceSuffix }}.id
      name     = "{{ $.Data.Hostname }}"
      value    = "{{ $ip.V4 }}"
      type     = "A"
      ttl      = 300
    }

{{- end }}

output "{{ .Data.ClusterName }}_{{ .Data.ClusterHash }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = { "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-endpoint" = format("%s.%s", "{{ .Data.Hostname }}", "{{ .Data.DNSZone }}")}
}
