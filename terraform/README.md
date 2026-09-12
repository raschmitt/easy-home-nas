# Cloudflare Tunnel — Terraform

Manages exactly the two resources this project's Cloudflare Tunnel path
needs: the tunnel itself, and the DNS record that routes your public
hostname to it. It deliberately does **not** touch anything else in your
zone — your existing MX/TXT/site records stay however you already manage
them. See [`docs/remote-access.md`](../docs/remote-access.md) for when you'd
use this (CG-NAT, or an ISP that blocks inbound 80/443) versus the
project's default of direct Caddy exposure.

## Prerequisites

- The domain's zone must already exist in Cloudflare (Free plan is fine).
  Terraform doesn't do zone onboarding — that's a one-time step you do in
  the dashboard once, since it involves reviewing/importing your existing
  DNS records by hand (see `docs/remote-access.md`).
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
- A Cloudflare API token (**not** your Global API Key) with exactly:
  - `Account` → `Cloudflare Tunnel` → `Edit`
  - `Zone` → `DNS` → `Edit` (scoped to the one zone above)

  Create it at <https://dash.cloudflare.com/profile/api-tokens> → **Create
  Token** → **Custom token**.

## Usage

```bash
cd terraform
export CLOUDFLARE_API_TOKEN=paste-your-token-here   # never put this in a file
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # account_id, zone_id, public_hostname

terraform init
terraform plan
terraform apply
```

On success, `docker/cloudflared/config.yml` and `credentials.json` are
written directly — nothing to copy by hand. Then, per the output's
"Remaining steps": set `TANDEM_CADDY_ADDRESS_PREFIX=http://` in `.env` and
run `docker compose --profile tunnel up -d`.

## Securing state

Terraform state (`terraform.tfstate`) contains the tunnel secret in plain
text — treat it like any other credential. It's git-ignored by default
here; if you move to remote state (recommended for anything beyond a single
machine), use a backend with encryption at rest (Terraform Cloud, or an S3
bucket with SSE + a restrictive bucket policy) rather than a local file
checked in anywhere.

## Tearing down

```bash
terraform destroy
```

This deletes the tunnel and its DNS record from Cloudflare. It does **not**
remove `docker/cloudflared/config.yml`/`credentials.json` from disk or stop
the `cloudflared` container — do `docker compose --profile tunnel down`
first if you're decommissioning this path entirely.
