# Remote access

Tandem NAS exposes Nextcloud directly to the public internet over HTTPS —
no VPN required to use it from your phone or a browser anywhere. That
convenience is the reason the checklist below is mandatory, not optional.

## Which path do you need?

There are two ways to get a real public HTTPS URL, and **most people on a
residential internet connection will need the second one**, not the first:

| | Path A: Direct exposure | Path B: Cloudflare Tunnel |
|---|---|---|
| Works when... | Your ISP actually routes inbound traffic to your router | Your ISP blocks inbound ports outright (common on residential fiber/cable in Brazil and elsewhere), or you're behind CG-NAT |
| Requires | Port forward on your router; DDNS if your IP is dynamic | Your domain's DNS zone hosted on Cloudflare (free) |
| Where it's documented | "Path A" below | "Path B" below, `terraform/README.md` |

**Test which one you have before committing to either path.** Set up port
forwarding on your router first (forward TCP 80 and TCP+UDP 443 to this
machine's local IP — see Path A step 2), then check from *outside* your
network, independent of DNS or certificates:

```bash
# Replace with your router's actual public IP (check the router's own
# status page — WAN/Internet section — not just "what's my IP" from inside
# your network, so you can compare the two and catch CG-NAT too).
curl -s "https://check-host.net/check-tcp?host=YOUR_PUBLIC_IP:80&max_nodes=3" \
  -H "Accept: application/json"
# then, a few seconds later, fetch the result with the permanent_link's
# request_id:
curl -s "https://check-host.net/check-result/REQUEST_ID" -H "Accept: application/json"
```

If every node reports `"Connection timed out"` — not just one, and not just
on port 80/443 specifically (try a couple of other ports too, e.g. 8443, to
rule out the ISP blocking only "well-known" server ports) — port forwarding
genuinely cannot work no matter how you configure the router. Go straight to
**Path B**. If you get a real connection (even a TLS/HTTP-level error is
fine — that means the TCP connection itself succeeded), **Path A** will
work.

## Path A: Direct exposure (Caddy + Let's Encrypt)

1. **A domain or subdomain** pointing at this machine's public IP
   (`TANDEM_PUBLIC_DOMAIN` in `.env`). Caddy needs this to request a
   Let's Encrypt certificate — it cannot get one for a bare IP address.
2. **Port forwarding** on your router: forward TCP 80 and TCP+UDP 443 to
   this machine's local IP. Port 80 is required even though everything
   ends up on HTTPS — it's used for the ACME HTTP-01 challenge.
3. **A stable way to reach your IP.** If your ISP gives you a dynamic IP
   (most residential connections do), set up DDNS so your domain always
   points at the current IP:
   - Many consumer routers have built-in DDNS client support (No-IP,
     DuckDNS, Dynu, etc.) — check your router's admin page first.
   - Otherwise run a small DDNS client on this host (e.g. `ddclient`,
     configured for your DNS provider's API) as a systemd timer. This is
     intentionally left out of this repo's Ansible roles since the right
     client depends entirely on your DNS provider — pick one and add it as
     its own role if you need it.

With these three in place, `docker compose up -d` (per the main README) is
all you need — Caddy handles the certificate automatically on first start.

## Path B: Cloudflare Tunnel

This host makes an *outbound* connection to Cloudflare's edge, which
terminates public HTTPS and proxies traffic back over that tunnel — no
inbound port needs to be reachable at all, so it works from behind CG-NAT
or an ISP that blocks inbound ports.

**Trade-off to accept going in:** Cloudflare Tunnel requires your domain's
DNS **zone** (the whole domain, not just the subdomain) to be managed by
Cloudflare, since issuing a public certificate and routing the tunnel both
happen at the zone level — there's no way to delegate just a subdomain to
Cloudflare on the free tier. If your domain's DNS is currently elsewhere
(e.g. Netlify, your registrar's own DNS), migrating means recreating every
existing record (MX, TXT, your existing site's A/AAAA/CNAME) in Cloudflare
first, then switching nameservers at your registrar. Do this deliberately,
not as a rushed step, since it affects existing mail/site traffic too.

1. **Add your domain to Cloudflare** (Free plan is enough).
   - Use the **root domain** (`example.com`), not a subdomain
     (`drive.example.com`) — Cloudflare's "Add a site" flow explicitly
     rejects subdomains ("Please ensure you are providing the root domain
     and not any subdomains"), and even when it's accepted the underlying
     onboarding for a subdomain hangs indefinitely rather than erroring
     cleanly. This isn't a bug in your setup — Cloudflare zones are only
     ever root-domain-scoped.
   - Let it scan your existing DNS records, and **verify every record
     matches what you already have** before continuing.
   - For any record that's part of your existing site/mail (not the new
     NAS subdomain), set it to **DNS only** (grey cloud), not proxied, so
     Cloudflare doesn't change how that traffic behaves. Only the new
     tunnel record (added in step 3) needs to be proxied.
2. **Switch nameservers** at your registrar to the two Cloudflare assigns.
   This is the actual cutover — propagation is usually fast (minutes) but
   can take up to 48h. If the onboarding page's DNS scan spins forever
   (a known rough edge for some zones), don't wait it out — reload the
   "Add a site" flow from scratch; the zone itself is often created
   already even when the scan step hangs.
3. **Create the tunnel and wire it into the stack.** Two ways to do this:

   - **Terraform (recommended, see [`terraform/README.md`](../terraform/README.md))**
     — creates the tunnel and its DNS record, and writes
     `docker/cloudflared/config.yml` + `credentials.json` directly:
     ```bash
     cd terraform
     export CLOUDFLARE_API_TOKEN=...   # scoped token, see terraform/README.md
     cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars
     terraform init && terraform apply
     ```
   - **Manual**, if you'd rather not use Terraform:
     ```bash
     cloudflared tunnel login          # opens a browser to authorize
     cloudflared tunnel create tandem-nas
     cloudflared tunnel route dns tandem-nas $TANDEM_PUBLIC_DOMAIN
     cp docker/cloudflared/config.yml.example docker/cloudflared/config.yml
     # edit config.yml: set `tunnel:` to your tunnel ID and `hostname:` to
     # $TANDEM_PUBLIC_DOMAIN
     cp ~/.cloudflared/<tunnel-id>.json docker/cloudflared/credentials.json
     chmod 644 docker/cloudflared/credentials.json  # container reads it as a different uid
     ```

   Either way, in `.env` set `TANDEM_CADDY_ADDRESS_PREFIX=http://` — this
   tells Caddy to serve plain HTTP instead of also trying (and endlessly
   failing) to get its own Let's Encrypt certificate, since Cloudflare's
   edge is what terminates public HTTPS now.
4. **Start the tunnel service**, which is opt-in via a Compose profile:
   ```bash
   docker compose --profile tunnel up -d
   ```

Verify end to end: `curl -I https://$TANDEM_PUBLIC_DOMAIN/status.php` should
return `200`, and `openssl s_client -connect $TANDEM_PUBLIC_DOMAIN:443
-servername $TANDEM_PUBLIC_DOMAIN` should show a valid Let's Encrypt
certificate issued through Cloudflare. For extra confidence that it's
reachable from outside your own network (not just from this host), rerun
the `check-host.net` check from the diagnostic above against
`$TANDEM_PUBLIC_DOMAIN:443` instead of your router's IP.

## What's already protecting this by default

Applies whichever path you used — Caddy sits in front of Nextcloud either
way, direct or tunneled:

| Layer | What it does |
|---|---|
| Caddy | Automatic HTTPS via Let's Encrypt (Path A) or plain HTTP behind Cloudflare's edge TLS (Path B); HSTS + security headers either way; rate limiting on `/login` and DAV endpoints (`caddy-ratelimit`, see `docker/caddy/Caddyfile`) |
| fail2ban | Bans an IP for 1h after 5 failed Nextcloud logins in 10 minutes (`docker/fail2ban/jail.d/nextcloud.conf`) |
| Nextcloud | Built-in brute-force throttling, independent of fail2ban |
| ufw (host) | Only 22 (rate-limited), 80, 443 open; default-deny inbound otherwise |
| Cloudflare (Path B only) | DDoS protection and WAF at the edge, ahead of everything above |

## Turn on 2FA (do this before inviting anyone else)

Nextcloud ships TOTP two-factor auth as a first-party app. Enable and enforce
it for everyone:

```bash
docker compose exec -u www-data nextcloud php occ app:enable twofactor_totp
docker compose exec -u www-data nextcloud php occ twofactorauth:enforce
```

Each user then enrolls their authenticator app from
**Settings → Security → Two-Factor Authentication** on first login.

## Mobile and desktop apps

Point the official Nextcloud apps at `https://<TANDEM_PUBLIC_DOMAIN>`:

- iOS: [Nextcloud on the App Store](https://apps.apple.com/app/nextcloud/id1125420102)
- Android: [Nextcloud on Google Play](https://play.google.com/store/apps/details?id=com.nextcloud.client)
- Desktop sync clients: [nextcloud.com/install](https://nextcloud.com/install/)

No VPN, no special network config on the client side — it's a normal HTTPS
endpoint, regardless of which path (A or B) you used to get it.

## SSH stays separate

SSH administrative access to the host is **not** part of this public-facing
surface and does not follow the same exposure model:

- The `hardening` Ansible role only touches SSH if you explicitly set
  `TANDEM_HARDEN_SSH=true`, and even then it refuses to disable password
  auth unless it finds a working `authorized_keys` file first (to avoid
  locking you out).
- Recommended baseline regardless: key-only auth, `fail2ban` on `sshd`
  (already enabled by default, see `docker/fail2ban/jail.d/sshd.conf`), and
  keep the ufw rate-limit rule on port 22.
- If you want SSH off the public internet entirely, put it behind
  [Tailscale](https://tailscale.com/) (or another WireGuard-based overlay)
  and close port 22 in ufw/your router — this is a good idea precisely
  *because* Nextcloud itself does need to stay publicly reachable, so
  narrowing the admin surface separately reduces overall risk.
