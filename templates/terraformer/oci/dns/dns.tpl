{{- $specName          := .Data.Provider.SpecName }}
{{- $hostname          := .Data.Hostname }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "oci" {
  tenancy_ocid      = "{{ .Data.Provider.GetOci.TenancyOCID }}"
  user_ocid         = "{{ .Data.Provider.GetOci.UserOCID }}"
  fingerprint       = "{{ .Data.Provider.GetOci.KeyFingerprint }}"
  private_key_path  = "{{ $specName }}"
  region            = "eu-frankfurt-1"
  alias             = "dns_oci_{{ $resourceSuffix }}"
}

data "oci_dns_zones" "oci_zone_{{ $resourceSuffix }}" {
  provider        = oci.dns_oci_{{ $resourceSuffix }}
  compartment_id  = "{{ .Data.Provider.GetOci.CompartmentOCID }}"
  name            = "{{ .Data.DNSZone }}"
}

resource "oci_health_checks_ping_monitor" "oci_health_checks_{{ $resourceSuffix }}" {
  provider            = oci.dns_oci_{{ $resourceSuffix }}
  compartment_id      = "{{ .Data.Provider.GetOci.CompartmentOCID }}"
  display_name        = "health-check-{{ $hostname }}"
  interval_in_seconds = 30
  protocol = "TCP"
  # Claudie creates a default role for loadbalancers which acts as a healthcheck, that is open on port 65534
  port  = 65534
  targets = [
    {{- range $ip := .Data.RecordData.IP }}
      "{{ $ip.V4 }}",
    {{- end }}
  ]
}

resource "oci_dns_steering_policy" "oci_steering_policy_{{ $resourceSuffix }}" {
  provider                = oci.dns_oci_{{ $resourceSuffix }}
  compartment_id          = "{{ .Data.Provider.GetOci.CompartmentOCID }}"
  display_name            = "{{ $hostname }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"
  template                = "LOAD_BALANCE"
  ttl                     = 300
  health_check_monitor_id = oci_health_checks_ping_monitor.oci_health_checks_{{ $resourceSuffix }}.id

  {{- range $ip := .Data.RecordData.IP }}
  answers {
    name = "{{ $ip.V4 }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"
    rdata = "{{ $ip.V4 }}"
    rtype = "A"
  }
  {{- end }}

  rules {
    rule_type   = "FILTER"
    description = "Removes disabled answers."
    default_answer_data {
        answer_condition = "answer.isDisabled != true"
        should_keep      = "true"
    }
  }

  rules {
    rule_type   = "HEALTH"
    description = "Removes unhealthy target"
  }

  rules {
	rule_type = "WEIGHTED"
    {{- range $ip := .Data.RecordData.IP }}
    default_answer_data {
      answer_condition = "answer.name == '{{ $ip.V4 }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}'"
      value = 1
    }
    {{- end }}
  }

  rules {
    rule_type = "LIMIT"
    default_count = "1"
  }
}

locals {
  matching_zone_{{ $resourceSuffix }} = [for z in data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.zones : z if z.name == "${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"][0]
}

resource "oci_dns_steering_policy_attachment" "dns_steering_policy_attachment_{{ $resourceSuffix }}" {
  provider           = oci.dns_oci_{{ $resourceSuffix }}
  domain_name        = "{{ $hostname }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}"
  steering_policy_id = oci_dns_steering_policy.oci_steering_policy_{{ $resourceSuffix }}.id
  zone_id            = local.matching_zone_{{ $resourceSuffix }}.id
}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
  value = { "{{ $clusterID }}-endpoint" = "{{ $hostname }}.${data.oci_dns_zones.oci_zone_{{ $resourceSuffix }}.name}" }
}
