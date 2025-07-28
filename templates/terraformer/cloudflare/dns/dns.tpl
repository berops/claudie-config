{{- $specName          := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $clusterID         := printf "%s-%s" .Data.ClusterName .Data.ClusterHash }}

provider "cloudflare" {
  api_token = "${file("{{ $specName }}")}"
  alias = "cloudflare_dns_{{ $resourceSuffix }}"
}

data "cloudflare_zone" "cloudflare_zone_{{ $resourceSuffix }}" {
  provider   = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
  name       = "{{ .Data.DNSZone }}"
}

### If subscription has paid addon Cloudflare Load Balancing,
### implement load balancer with health check, otherwise
### create A records without load balancer and health check
{{- if and (hasExtension .Data "ProviderExtrasExtension") (.Data.ProviderExtrasExtension.SubscriptionAllowsHA ) }}
  resource "cloudflare_load_balancer_pool" "lb_pool_{{ $resourceSuffix }}" {
    provider    = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
    account_id  = "{{ .Data.Provider.GetCloudflare.GetAccountID }}"
    name        = "pool-{{ $resourceSuffix }}"

    {{- range $_, $ip := .Data.RecordData.IP }}
      {{- $escapedIPv4 := replaceAll $ip.V4 "." "_" }}
      origins {
        name    = "origin-{{ $escapedIPv4 }}"
        address = "{{ $ip.V4 }}"
        weight  = 1
      }
    {{- end }}

      monitor = cloudflare_load_balancer_monitor.monitor_{{ $resourceSuffix }}.id
  }

  resource "cloudflare_load_balancer_monitor" "monitor_{{ $resourceSuffix }}" {
    provider    = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
    account_id  = "{{ .Data.Provider.GetCloudflare.GetAccountID }}"
    type        = "tcp"
    # Claudie creates a default role for loadbalancers which acts as a healthcheck, that is open on port 65534
    port        = 65534
    timeout     = 5
    retries     = 2
    interval    = 60
  }

  resource "cloudflare_load_balancer" "load_balancer_{{ $resourceSuffix }}" {
    provider          = cloudflare.cloudflare_dns_{{ $resourceSuffix }}
    zone_id           = data.cloudflare_zone.cloudflare_zone_{{ $resourceSuffix }}.id
    name              = "{{ $.Data.Hostname }}.{{ .Data.DNSZone }}"
    fallback_pool_id  = cloudflare_load_balancer_pool.lb_pool_{{ $resourceSuffix }}.id

    default_pool_ids = [
      cloudflare_load_balancer_pool.lb_pool_{{ $resourceSuffix }}.id,
    ]
    ttl     = 30

    steering_policy="random"
  }
### If subscription does not include claudflare paid addon
### for DNS balancing, create DNS A records with no health check
{{- else }}
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
{{- end }}

output "{{ $clusterID }}_{{ $resourceSuffix }}" {
    value = { "{{ $clusterID }}-endpoint" = format("%s.%s", "{{ .Data.Hostname }}", "{{ .Data.DNSZone }}")}
}
