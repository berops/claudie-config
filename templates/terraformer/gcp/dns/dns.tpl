{{- $specName          := .Data.Provider.SpecName }}
{{- $hostname          := .Data.Hostname }}
{{- $gcpProject        := .Data.Provider.GetGcp.Project }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "google" {
    credentials = "${file("{{ $specName }}")}"
    project     = "{{ $gcpProject }}"
    alias       = "dns_gcp_{{ $resourceSuffix }}"
}

resource "google_compute_health_check" "gcp_health_check_{{ $resourceSuffix }}" {
  provider = google.dns_gcp_{{ $resourceSuffix }}
  name               = "health-check-{{ $hostname }}"
  check_interval_sec = 30
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2
  tcp_health_check {
    # Claudie creates a default role for loadbalancers which acts as a healthcheck, that is open on port 65534
    port = 65534
  }
  source_regions = ["europe-central2", "us-central1", "asia-northeast1"]
}

data "google_dns_managed_zone" "gcp_zone_{{ $resourceSuffix }}" {
  provider  = google.dns_gcp_{{ $resourceSuffix }}
  name      = "{{ .Data.DNSZone }}"
}

resource "google_dns_record_set" "record_{{ $resourceSuffix }}" {
  provider = google.dns_gcp_{{ $resourceSuffix }}

  name = "{{ $hostname }}.${data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.gcp_zone_{{ $resourceSuffix }}.name

  routing_policy {
    health_check = google_compute_health_check.gcp_health_check_{{ $resourceSuffix }}.id
    wrr {
      health_checked_targets {
        external_endpoints = [
        {{- range $ip := .Data.RecordData.IP }}
          "{{ $ip.V4 }}",
        {{- end }}
        ]
      }
      weight = 1
    }
  }
}

output "{{ $clusterID }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = { "{{ $clusterID }}-endpoint" = google_dns_record_set.record_{{ $resourceSuffix }}.name }
}
