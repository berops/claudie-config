terraform {
  required_providers {
    verda = {
      source = "verda-cloud/verda"
      version = "~> 1.1"
    }
    # http and time are pulled in only because the verda nodepool template polls the
    # Verda API to work around an upstream null-ip race in verda_instance.Create.
    # Remove these two blocks once the upstream provider waits for the public IP
    # before returning, and the corresponding data.http blocks in nodepool/node.tpl
    # are dropped.
    http = {
      source = "hashicorp/http"
      version = "~> 3.4"
    }
    time = {
      source = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}
