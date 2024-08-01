{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- range $i, $nodepool := .Data.NodePools }}

{{- $region                     := $nodepool.Details.Region }}
{{- $specName                   := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix             := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- $subnetResourceName  := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $subnetName          := printf "snt-%s-%s-%s" $clusterHash $region $nodepool.Name }}
{{- $subnetCIDR          := $nodepool.Details.Cidr }}
{{- $vpcResourceName     := printf "claudie_vpc_%s"   $resourceSuffix }}

resource "aws_subnet" "{{ $subnetResourceName }}" {
  provider                = aws.nodepool_{{ $resourceSuffix }}
  vpc_id                  = aws_vpc.{{ $vpcResourceName }}.id
  cidr_block              = "{{ $subnetCIDR }}"
  map_public_ip_on_launch = true
  availability_zone       = "{{ $nodepool.Details.Zone }}"

  tags = {
    Name            = "{{ $subnetName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $associationResourceName  := printf "%s_%s_rta" $nodepool.Name $resourceSuffix }}
{{- $routeTableResourceName   := printf "claudie_route_table_%s"   $resourceSuffix }}

resource "aws_route_table_association" "{{ $associationResourceName }}" {
  provider       = aws.nodepool_{{ $resourceSuffix }}
  subnet_id      = aws_subnet.{{ $subnetResourceName }}.id
  route_table_id = aws_route_table.{{ $routeTableResourceName }}.id
}
{{- end }}
