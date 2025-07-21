{{- $hostname          := .Data.Hostname }}
{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "aws" {
  secret_key = "${file("{{ $specName }}")}"
  access_key = "{{ .Data.Provider.GetAws.AccessKey }}"
  # we need to supply some aws region even though the records DNS are global.
  # this a requirement otherwise terraform will exit with an error.
  region     = "eu-central-1"
  alias      = "dns_aws_{{ $resourceSuffix }}"
  default_tags {
    tags = {
      Managed-by = "Claudie"
    }
  }
}

data "aws_route53_zone" "aws_zone_{{ $resourceSuffix }}" {
    provider  = aws.dns_aws_{{ $resourceSuffix }}
    name      = "{{ .Data.DNSZone }}"
}

{{- range $_, $ip := .Data.RecordData.IP }}
  {{- $escapedIPv4 := replaceAll $ip.V4 "." "_" }}
  resource "aws_route53_record" "record_{{ $hostname }}_{{ $escapedIPv4 }}_{{ $resourceSuffix }}" {
    provider  = aws.dns_aws_{{ $resourceSuffix }}
    zone_id   = "${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.zone_id}"
    name      = "{{ $hostname }}.${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.name}"
    type      = "A"
    ttl       = 300
    records   = [
      "{{ $ip.V4 }}",
    ]

    set_identifier  = "record_{{ $hostname }}_{{ $escapedIPv4 }}_{{ $resourceSuffix }}"
    health_check_id = aws_route53_health_check.hc_{{ $hostname }}_{{ $escapedIPv4 }}_{{ $resourceSuffix }}.id

    weighted_routing_policy {
      weight = 1
    }
  }

  resource "aws_route53_health_check" "hc_{{ $hostname }}_{{ $escapedIPv4 }}_{{ $resourceSuffix }}" {
    provider          = aws.dns_aws_{{ $resourceSuffix }}
    # Claudie creates a default role for loadbalancers which acts as a healthcheck, that is open on port 65534
    port              = 65534
    type              = "TCP"
    request_interval  = 30
    failure_threshold = 3
    ip_address        = "{{ $ip.V4 }}"
  }
{{- end }}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
  value = { "{{ $clusterID }}-endpoint" = "{{ $hostname }}.${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.name}" }
}
