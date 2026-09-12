output "tunnel_id" {
  description = "Cloudflare Tunnel ID."
  value       = cloudflare_zero_trust_tunnel_cloudflared.tandem_nas.id
}

output "next_steps" {
  value = <<-EOT
    Tunnel '${var.tunnel_name}' created and routed to https://${var.public_hostname}.

    config.yml and credentials.json were written directly into
    ${var.compose_cloudflared_dir}/ — docker compose picks them up as-is.

    Remaining steps (see docs/remote-access.md):
      1. In .env, set TANDEM_CADDY_ADDRESS_PREFIX=http://
      2. docker compose --profile tunnel up -d
      3. curl -I https://${var.public_hostname}/status.php   # expect 200
  EOT
}
