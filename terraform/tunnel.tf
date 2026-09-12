# The tunnel secret is generated once and stored in Terraform state (state
# is sensitive for exactly this reason — see the README note on securing
# it). It never appears in your shell history or a .tfvars file.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tandem_nas" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  config_src    = "local" # We manage ingress via config.yml, not the dashboard.
  tunnel_secret = random_id.tunnel_secret.b64_std
}

# Routes the public hostname to this tunnel. Must be proxied (orange cloud)
# for Cloudflare's edge to actually terminate the connection and hand it off
# through the tunnel — a "DNS only" record would just point at an
# unreachable internal hostname.
resource "cloudflare_dns_record" "tunnel_cname" {
  zone_id = var.cloudflare_zone_id
  name    = var.public_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tandem_nas.id}.cfargotunnel.com"
  ttl     = 1 # "Automatic" — required by Cloudflare when proxied is true.
  proxied = true
}

# cloudflared's credentials file format — a plain JSON file, not something
# the Cloudflare API hands back after tunnel creation for locally-managed
# tunnels, so we construct it ourselves from values Terraform already has.
resource "local_sensitive_file" "credentials" {
  filename = "${var.compose_cloudflared_dir}/credentials.json"
  content = jsonencode({
    AccountTag   = var.cloudflare_account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.tandem_nas.id
    TunnelSecret = random_id.tunnel_secret.b64_std
  })
  # 0644, not 0600: the cloudflared container reads this as a bind mount
  # under a different UID than the file's owner on the host, so 0600 makes
  # it unreadable inside the container. Host-level protection here is the
  # bind-mount/filesystem permissions on docker/cloudflared/ itself, not
  # this file's own mode.
  file_permission = "0644"
}

resource "local_file" "config_yml" {
  filename = "${var.compose_cloudflared_dir}/config.yml"
  content = templatefile("${path.module}/templates/config.yml.tftpl", {
    tunnel_id             = cloudflare_zero_trust_tunnel_cloudflared.tandem_nas.id
    public_hostname       = var.public_hostname
    caddy_service_address = var.caddy_service_address
  })
  file_permission = "0644"
}
