{{- $clusterName           := .Data.ClusterData.ClusterName}}
{{- $clusterHash           := .Data.ClusterData.ClusterHash}}
{{- $specName              := .Data.Provider.SpecName }}
{{- $uniqueFingerPrint     := .Fingerprint }}
{{- $isKubernetesCluster   := eq .Data.ClusterData.ClusterType "K8s" }}
{{- $isLoadbalancerCluster := eq .Data.ClusterData.ClusterType "LB" }}
{{- $LoadBalancerRoles     := .Data.LBData.Roles }}
{{- $K8sHasAPIServer       := .Data.K8sData.HasAPIServer }}

{{- range $_, $region := .Data.Regions }}

{{- $resourceSuffix := printf "%s_%s_%s" $region $specName $uniqueFingerPrint }}

{{- $vpcResourceName  := printf "claudie_vpc_%s"   $resourceSuffix }}
{{- $vpcName          := printf "vpc-%s-%s-%s" $clusterHash $region $specName}}

resource "aws_vpc" "{{ $vpcResourceName }}" {
  provider   = aws.nodepool_{{ $resourceSuffix }}
  cidr_block = "10.0.0.0/16"

  tags = {
    Name            = "{{ $vpcName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}


{{- $internetGatewayResourceName  := printf "claudie_gateway_%s"   $resourceSuffix }}
{{- $internetGatewayName          := printf "gtw-%s-%s-%s" $clusterHash $region $specName}}

resource "aws_internet_gateway" "{{ $internetGatewayResourceName }}" {
  provider = aws.nodepool_{{ $resourceSuffix }}
  vpc_id   = aws_vpc.{{ $vpcResourceName }}.id

  tags = {
    Name            = "{{ $internetGatewayName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $routeTableResourceName  := printf "claudie_route_table_%s"   $resourceSuffix }}
{{- $routeTableName          := printf "rt-%s-%s-%s" $clusterHash $region $specName}}

resource "aws_route_table" "{{ $routeTableResourceName }}" {
  provider     = aws.nodepool_{{ $resourceSuffix }}
  vpc_id       = aws_vpc.{{ $vpcResourceName }}.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.{{ $internetGatewayResourceName }}.id
  }

  tags = {
    Name            = "{{ $routeTableResourceName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

{{- $securityGroupResourceName  := printf "claudie_sg_%s"   $resourceSuffix }}
{{- $securityGroupName          := printf "sg-%s-%s-%s" $clusterHash $region $specName}}

resource "aws_security_group" "{{ $securityGroupResourceName }}" {
  provider               = aws.nodepool_{{ $resourceSuffix }}
  vpc_id                 = aws_vpc.{{ $vpcResourceName }}.id
  revoke_rules_on_delete = true

  tags = {
    Name            = "{{ $securityGroupName }}"
    Claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

resource "aws_security_group_rule" "allow_egress_{{ $resourceSuffix }}" {
  provider          = aws.nodepool_{{ $resourceSuffix }}
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.{{ $securityGroupResourceName }}.id
}


resource "aws_security_group_rule" "allow_ssh_{{ $resourceSuffix }}" {
  provider          = aws.nodepool_{{ $resourceSuffix }}
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.{{ $securityGroupResourceName }}.id
}

{{- if $isKubernetesCluster  }}
    {{- if $K8sHasAPIServer }}
resource "aws_security_group_rule" "allow_kube_api_{{ $resourceSuffix }}" {
  provider          = aws.nodepool_{{ $resourceSuffix }}
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.{{ $securityGroupResourceName }}.id
}
    {{- end }}
{{- end }}


{{- if $isLoadbalancerCluster }}
    {{- range $role := $LoadBalancerRoles }}
resource "aws_security_group_rule" "allow_{{ $role.Port }}_{{ $resourceSuffix }}" {
  provider          = aws.nodepool_{{ $resourceSuffix }}
  type              = "ingress"
  from_port         = {{ $role.Port }}
  to_port           = {{ $role.Port }}
  protocol          = "{{ $role.Protocol }}"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.{{ $securityGroupResourceName }}.id
}
    {{- end }}
{{- end }}

resource "aws_security_group_rule" "allow_wireguard_{{ $resourceSuffix }}" {
  provider          = aws.nodepool_{{ $resourceSuffix }}
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.{{ $securityGroupResourceName }}.id
}

resource "aws_security_group_rule" "allow_icmp_{{ $resourceSuffix }}" {
  provider          = aws.nodepool_{{ $resourceSuffix }}
  type              = "ingress"
  from_port         = 8
  to_port           = 0
  protocol          = "icmp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.{{ $securityGroupResourceName }}.id
}
{{- end }}
