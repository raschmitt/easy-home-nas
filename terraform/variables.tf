variable "cloudflare_account_id" {
  description = "Cloudflare account ID (Account Home in the dashboard, right sidebar)."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID for the domain that will host TANDEM_PUBLIC_DOMAIN (zone overview page, right sidebar). The zone itself must already exist in Cloudflare — this project does not manage zone onboarding, see docs/remote-access.md."
  type        = string
}

variable "tunnel_name" {
  description = "Name shown for this tunnel in the Cloudflare dashboard."
  type        = string
  default     = "tandem-nas"
}

variable "public_hostname" {
  description = "Full public hostname to route through the tunnel, e.g. drive.example.com. Must match TANDEM_PUBLIC_DOMAIN in your .env."
  type        = string
}

variable "caddy_service_address" {
  description = "Where cloudflared forwards traffic inside the docker compose network. Leave as the default unless you renamed the caddy service."
  type        = string
  default     = "http://caddy:80"
}

variable "compose_cloudflared_dir" {
  description = "Path to docker/cloudflared relative to this terraform/ directory. Terraform writes config.yml and credentials.json there so docker compose --profile tunnel picks them up directly."
  type        = string
  default     = "../docker/cloudflared"
}
