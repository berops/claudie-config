# claudie-config

Terraform templates used by [Claudie](https://github.com/berops/claudie)'s `terraformer` service to provision infrastructure across supported cloud providers. Claudie renders these Go templates with cluster-specific data and applies the resulting Terraform code.

## Structure

```
templates/terraformer/<provider>/
├── provider_version.tpl        # pins the Terraform provider source & version
├── networking/
│   ├── provider.tpl            # provider block for the networking stage
│   └── networking.tpl          # VPC/network, subnets, firewall rules, gateways
├── nodepool/
│   ├── provider.tpl            # provider block for the nodepool stage
│   ├── node.tpl                # VMs, disks, public IPs, spot scheduling
│   └── node_networking.tpl    # per-node subnet/NIC wiring (aws, azure, gcp, oci only)
└── dns/
    ├── dns.tpl                     # DNS zone + records for the cluster endpoint
    └── dns_alternative_names.tpl   # records for alternative endpoint names
```

Not every provider has every directory — e.g. Cloudflare is DNS-only, and OpenStack, CloudRift and Verda have no `dns/`.

## Supported providers

AWS, Azure, GCP, OCI, Hetzner, Exoscale, OVH, OpenStack, CloudRift, Verda, and Cloudflare (DNS only).
