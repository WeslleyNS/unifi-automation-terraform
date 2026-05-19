###############################################################################
# providers.tf - Provider Ubiquiti UniFi para UDM Pro (Lojas Granado)
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    unifi = {
      source  = "paultyng/unifi"
      version = "~> 0.41.0"
    }
  }
}

provider "unifi" {
  username       = "Suporte"
  password       = "@Suporte$yst3m"
  api_url        = "https://192.168.1.1:443"
  allow_insecure = true
}
