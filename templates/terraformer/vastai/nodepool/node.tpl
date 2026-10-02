{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}

{{- $nodepool        := .Data.NodePool }}
{{- $specName        := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix  := printf "%s_%s" $specName $uniqueFingerPrint }}
{{- $networking      := .Data.Networking.All }}

{{- $claudieSshPort  := index $networking (printf "claudie_ssh_port_%s" $resourceSuffix) }}
{{- $wireguardPort   := index $networking (printf "claudie_wireguard_port_%s" $resourceSuffix) }}
{{- $bootstrapScript := index $networking (printf "vastai_bootstrap_script_%s" $resourceSuffix) }}
{{- $firewallScript  := index $networking (printf "vastai_firewall_script_%s" $resourceSuffix) }}
{{- if not $claudieSshPort }}{{ template "node.tpl: missing output 'claudie_ssh_port_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $wireguardPort }}{{ template "node.tpl: missing output 'claudie_wireguard_port_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $bootstrapScript }}{{ template "node.tpl: missing output 'vastai_bootstrap_script_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}
{{- if not $firewallScript }}{{ template "node.tpl: missing output 'vastai_firewall_script_<specName>_<fingerprint>' from the networking stage in .Networking.All" }}{{ end }}

# Instances are rented with the team API key when one is configured, otherwise with the personal key.
# SSH keys are always created with the personal API key.
# Vast.ai does not support SSH keys on a team account. Keys are held per user, and a key registered
# by a team member applies to the instances rented under that team.
{{- $account := "personal" }}
{{- if $nodepool.Details.Provider.GetVastai.GetTeamApiKey }}{{ $account = "team" }}{{ end }}
{{- $teamOrPersonalAlias := printf "vastai.nodepool_%s_%s" $resourceSuffix $account }}
{{- $personalAlias := printf "vastai.nodepool_%s_personal" $resourceSuffix }}

# Vast.ai filters offers by two-letter ISO 3166-1 country codes only. The InputManifest `region`
# is a space-separated list of such codes, and the aliases below expand a whole continent, so
# `region: europe` or `region: europe US` both work. Commas are not allowed, the region ends up
# in a node label. Every ISO country is assigned to exactly one alias.
{{- $regions := dict
  "europe"        (list "AD" "AL" "AT" "AX" "BA" "BE" "BG" "BY" "CH" "CY" "CZ" "DE" "DK" "EE" "ES" "FI" "FO" "FR" "GB" "GG" "GI" "GR" "HR" "HU" "IE" "IM" "IS" "IT" "JE" "LI" "LT" "LU" "LV" "MC" "MD" "ME" "MK" "MT" "NL" "NO" "PL" "PT" "RO" "RS" "SE" "SI" "SJ" "SK" "SM" "UA" "VA" "XK")
  "asia"          (list "AE" "AF" "AM" "AZ" "BD" "BH" "BN" "BT" "CN" "GE" "HK" "ID" "IL" "IN" "IO" "IQ" "IR" "JO" "JP" "KG" "KH" "KP" "KR" "KW" "KZ" "LA" "LB" "LK" "MM" "MN" "MO" "MV" "MY" "NP" "OM" "PH" "PK" "PS" "QA" "RU" "SA" "SG" "SY" "TH" "TJ" "TL" "TM" "TR" "TW" "UZ" "VN" "YE")
  "africa"        (list "AO" "BF" "BI" "BJ" "BW" "CD" "CF" "CG" "CI" "CM" "CV" "DJ" "DZ" "EG" "EH" "ER" "ET" "GA" "GH" "GM" "GN" "GQ" "GW" "KE" "KM" "LR" "LS" "LY" "MA" "MG" "ML" "MR" "MU" "MW" "MZ" "NA" "NE" "NG" "RE" "RW" "SC" "SD" "SH" "SL" "SN" "SO" "SS" "ST" "SZ" "TD" "TG" "TN" "TZ" "UG" "YT" "ZA" "ZM" "ZW")
  "north-america" (list "AG" "AI" "AW" "BB" "BL" "BM" "BQ" "BS" "BZ" "CA" "CR" "CU" "CW" "DM" "DO" "GD" "GL" "GP" "GT" "HN" "HT" "JM" "KN" "KY" "LC" "MF" "MQ" "MS" "MX" "NI" "PA" "PM" "PR" "SV" "SX" "TC" "TT" "US" "VC" "VG" "VI")
  "south-america" (list "AR" "BO" "BR" "CL" "CO" "EC" "FK" "GF" "GY" "PE" "PY" "SR" "UY" "VE")
  "oceania"       (list "AS" "AU" "CC" "CK" "CX" "FJ" "FM" "GU" "KI" "MH" "MP" "NC" "NF" "NR" "NU" "NZ" "PF" "PG" "PN" "PW" "SB" "TK" "TO" "TV" "UM" "VU" "WF" "WS") }}
{{- $geolocations := list }}
{{- range splitList " " $nodepool.Details.Region }}
  {{- $token := lower (trim .) }}
  {{- if hasKey $regions $token }}{{ $geolocations = concat $geolocations (index $regions $token) }}
  {{- else if $token }}{{ $geolocations = append $geolocations (upper $token) }}{{ end }}
{{- end }}

{{- $sshKeyResourceName := printf "key_%s_%s" $nodepool.Name $resourceSuffix }}
resource "vastai_ssh_key" "{{ $sshKeyResourceName }}" {
  provider   = {{ $personalAlias }}
  public_key = file("./{{ $nodepool.Name }}")
}

# Each instance searches the marketplace when it is created and rents the cheapest offer
# matching its search_offer block. Offers are one machine slot each and vanish once rented,
# so the nodes of this nodepool, and other nodepools applied in parallel, compete for the
# same cheapest offers. The provider skips an offer that was taken in the meantime and tries
# the next one, so `limit` is the nodepool size plus a few spares. The search never runs
# again after creation: plans, refreshes and destroys do not touch the marketplace.
{{- range $node := $nodepool.Nodes }}

{{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}

resource "vastai_instance" "{{ $serverResourceName }}" {
  depends_on     = [vastai_ssh_key.{{ $sshKeyResourceName }}]
  provider       = {{ $teamOrPersonalAlias }}
  label          = "{{ $serverResourceName }}"
  image          = "{{ $nodepool.Details.Image }}"
  disk           = {{ $nodepool.Details.StorageDiskSize }}
  cancel_unavail = true
  vm             = true
  runtype        = "ssh"
  # Publish the Claudie SSH port and WireGuard on the host so the node is
  # reachable through Vast.ai's NAT; the mapped host ports are read back from
  # `ports` in the output below.
  env            = "-p {{ $claudieSshPort }}:{{ $claudieSshPort }} -p {{ $wireguardPort }}:{{ $wireguardPort }}/udp"
  onstart        = <<-EOF
#!/bin/bash
{{ $bootstrapScript }}

{{ $firewallScript }}

{{- if $isKubernetesCluster }}
# Longhorn data directory on the OS disk. Vast.ai exposes no separate volume
# to attach to a VM here, so data shares the OS disk sized by storageDiskSize.
mkdir -p /opt/claudie/data
{{- end }}{{/* if $isKubernetesCluster */}}
EOF

  # all fields from machineSpec are required
  search_offer {
    type                = "ondemand"
    verified            = { eq = true }
    reliability         = { gte = 0.98 }
    vms_enabled         = { eq = true }
    static_ip           = { eq = true }
    {{- with $nodepool.Details.MachineSpec }}
    num_gpus            = { eq = {{ .NvidiaGpuCount }} }
    gpu_name            = { eq = "{{ .NvidiaGpuType }}" }
    gpu_ram             = { eq = {{ .Vram }} }
    cpu_cores_effective = { gte = {{ .CpuCount }} }
    cpu_ram             = { gte = {{ .Memory }} }
    {{- end }}{{/* with MachineSpec */}}
    cpu_arch            = { eq = "{{ $nodepool.Details.ServerType }}" }
    disk_space          = { gte = {{ $nodepool.Details.StorageDiskSize }} }
    geolocation         = { in = {{ toJson $geolocations }} }
    duration            = { gte = 2592000 }
    inet_down           = { gte = 300 }
    limit               = {{ add (len $nodepool.Nodes) 5 }}
    order               = [["dph_total", "asc"]]
  }
}

{{- end }}{{/* range $nodepool.Nodes */}}

# Output: [public_ip, ssh_port, wireguard_port] per node.
#
# Vast.ai VMs sit behind the host's NAT on a shared public IP. `ports` maps each
# published in-VM port ("<port>/<proto>") to the host port it is reachable on, so
# SSH is the host port mapped to <claudie_ssh_port>/tcp and WireGuard the host
# port mapped to <claudie_wireguard_port>/udp. If a mapping is missing the in-VM
# port is used as-is.
output "{{ $nodepool.Name }}_{{ $specName }}_{{ $uniqueFingerPrint }}" {
  value = {
    {{- range $node := $nodepool.Nodes }}
    {{- $serverResourceName := printf "%s_%s" $node.Name $resourceSuffix }}
    "{{ $node.Name }}" = [
      vastai_instance.{{ $serverResourceName }}.public_ipaddr,
      tostring(try(vastai_instance.{{ $serverResourceName }}.ports["{{ $claudieSshPort }}/tcp"], {{ $claudieSshPort }})),
      tostring(try(vastai_instance.{{ $serverResourceName }}.ports["{{ $wireguardPort }}/udp"], {{ $wireguardPort }})),
    ]
    {{- end }}
  }
}
