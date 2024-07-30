{{- $specName          := .Data.Provider.SpecName }}
{{- $gcpProject        := .Data.Provider.GcpProject }}
{{- $uniqueFingerPrint := .Fingerprint }}
{{- $resourceSuffix    := printf "%s_%s" $specName $uniqueFingerPrint }}

provider "oci" {
  tenancy_ocid      = "{{ .Provider.OciTenancyOcid }}"
  user_ocid         = "{{ .Provider.OciUserOcid }}"
  fingerprint       = "{{ .Provider.OciFingerprint }}"
  private_key_path  = "{{ .Provider.SpecName }}"
  region            = "eu-frankfurt-1"
  alias             = "dns_oci"
}

data "oci_dns_zones" "oci_zone" {
    provider        = oci.dns_oci
    compartment_id  = "{{ .Provider.OciCompartmentOcid }}"
    name            = "{{ .DNSZone }}"
}

resource "oci_dns_rrset" "record" {
    provider        = oci.dns_oci
    domain          = "{{ .HostnameHash }}.${data.oci_dns_zones.oci_zone.name}"
    rtype           = "A"
    zone_name_or_id = data.oci_dns_zones.oci_zone.name

    compartment_id  = "{{ .Provider.OciCompartmentOcid }}"
    {{- range $IP := .NodeIPs }}
    items {
       domain = "{{ $.HostnameHash }}.${data.oci_dns_zones.oci_zone.name}"
       rdata  = "{{ $IP }}"
       rtype  = "A"
       ttl    = 300
    }
    {{- end }}
}

output "{{ .ClusterName }}-{{ .ClusterHash }}" {
  value = { "{{ .ClusterName }}-{{ .ClusterHash }}-endpoint" = oci_dns_rrset.record.domain }
}
