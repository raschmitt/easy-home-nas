# Tandem NAS — Cloudflare Tunnel infrastructure.
#
# This is intentionally scoped to ONLY the resources this project introduces
# (the tunnel + its DNS record). It does not import or manage your zone's
# pre-existing records (MX, TXT, your site's A/AAAA/CNAME) — those stay
# exactly as they were before you added the domain to Cloudflare, managed
# however you already manage them. See docs/remote-access.md for why.

terraform {
  required_version = ">= 1.5"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "cloudflare" {
  # Reads CLOUDFLARE_API_TOKEN from the environment by default — see
  # terraform.tfvars.example for the token permissions this needs.
}
