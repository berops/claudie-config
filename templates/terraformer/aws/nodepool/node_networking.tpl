{{- $clusterName       := .Data.ClusterData.ClusterName }}
{{- $clusterHash       := .Data.ClusterData.ClusterHash }}
{{- $uniqueFingerPrint := $.Fingerprint }}

{{- range $i, $nodepool := .Data.NodePools }}

{{- $region                     := $nodepool.Details.Region }}
{{- $specName                   := $nodepool.Details.Provider.SpecName }}
{{- $resourceSuffix             := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}
{{- $vpcResourceName            := printf "claudie_vpc_%s"   $resourceSuffix }}
{{- $routeTableResourceName     := printf "claudie_route_table_%s"   $resourceSuffix }}

{{- if $nodepool.Details.Zone }}
{{- /* Zone is specified - create a single subnet for the nodepool */}}

{{- $subnetResourceName  := printf "%s_%s_subnet" $nodepool.Name $resourceSuffix }}
{{- $subnetName          := printf "snt-%s-%s-%s" $clusterHash $region $nodepool.Name }}
{{- $subnetCIDR          := $nodepool.Details.Cidr }}

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

resource "aws_route_table_association" "{{ $associationResourceName }}" {
  provider       = aws.nodepool_{{ $resourceSuffix }}
  subnet_id      = aws_subnet.{{ $subnetResourceName }}.id
  route_table_id = aws_route_table.{{ $routeTableResourceName }}.id
}

{{- else }}
{{- /* Zone is NOT specified - create per-node subnets distributed across availability zones */}}

    {{- range $nodeIndex, $node := $nodepool.Nodes }}

        {{- $subnetResourceName        := printf "%s_%s_%s_subnet" $nodepool.Name $node.Name $resourceSuffix }}
        {{- $subnetName                := printf "snt-%s-%s-%s-%s" $clusterHash $region $nodepool.Name $node.Name }}
        {{- /* Calculate subnet CIDR: base CIDR with node-specific offset */}}
        {{- /* Using /24 subnets within the nodepool's CIDR range */}}

resource "aws_subnet" "{{ $subnetResourceName }}" {
  provider                = aws.nodepool_{{ $resourceSuffix }}
  vpc_id                  = aws_vpc.{{ $vpcResourceName }}.id
  cidr_block              = cidrsubnet("{{ $nodepool.Details.Cidr }}", 4, {{ $nodeIndex }})
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available_{{ $resourceSuffix }}.names, {{ $nodeIndex }} % length(data.aws_availability_zones.available_{{ $resourceSuffix }}.names))

  tags = {
    Name            = "{{ $subnetName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

        {{- $associationResourceName := printf "%s_%s_%s_rta" $nodepool.Name $node.Name $resourceSuffix }}

resource "aws_route_table_association" "{{ $associationResourceName }}" {
  provider       = aws.nodepool_{{ $resourceSuffix }}
  subnet_id      = aws_subnet.{{ $subnetResourceName }}.id
  route_table_id = aws_route_table.{{ $routeTableResourceName }}.id
}

    {{- end }}
{{- end }}
{{- end }}
