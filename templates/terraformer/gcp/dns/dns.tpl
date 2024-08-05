{{- $specName          := .Data.Provider.SpecName }}
{{- $gcpProject        := .Data.Provider.GetGcp.Project }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "google" {
    credentials = "${file("{{ $specName }}")}"
    project     = "{{ $gcpProject }}"
    alias       = "dns_gcp_{{ $resourceSuffix }}"
}

data "google_dns_managed_zone" "gcp_zone_{{ $resourceSuffix }}" {
  provider  = google.dns_gcp_{{ $resourceSuffix }}
  name      = "{{ .Data.DNSZone }}"
}

resource "google_dns_record_set" "record_{{ $resourceSuffix }}" {
  provider = google.dns_gcp_{{ $resourceSuffix }}

  name = "{{ .Data.Hostname }}.${data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.name

  rrdatas = [
      {{- range $ip := .Data.RecordData.IP }}
          "{{ $ip.V4 }}",
      {{- end }}
    ]
}

{{- $clusterID := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}
output "{{ $clusterID }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = { "{{.Data.ClusterName}}-{{.Data.ClusterHash}}-endpoint" = google_dns_record_set.record_{{ $resourceSuffix }}.name }
}
