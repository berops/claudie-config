{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

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

resource "aws_route53_record" "record_{{ $resourceSuffix }}" {
    provider  = aws.dns_aws_{{ $resourceSuffix }}
    zone_id   = "${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.zone_id}"
    name      = "{{ .Data.Hostname }}.${data.aws_route53_zone.aws_zone_{{ $resourceSuffix }}.name}"
    type      = "A"
    ttl       = 300
    records   = [
    {{- range $ip := .Data.RecordData.IP }}
        "{{ $ip.V4 }}",
    {{- end }}
    ]
}

output "{{ .Data.ClusterName }}_{{ .Data.ClusterHash }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
    value = { "{{ .Data.ClusterName }}-{{ .Data.ClusterHash }}-endpoint" = aws_route53_record.record_{{ $resourceSuffix }}.name }
}
