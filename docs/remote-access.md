# Remote access

Tandem NAS exposes Nextcloud directly to the public internet over HTTPS —
no VPN required to use it from your phone or a browser anywhere. That
convenience is the reason the checklist below is mandatory, not optional.

## Prerequisites

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

## What's already protecting this by default

| Layer | What it does |
|---|---|
| Caddy | Automatic HTTPS via Let's Encrypt, HSTS + security headers, rate limiting on `/login` and DAV endpoints (`caddy-ratelimit`, see `docker/caddy/Caddyfile`) |
| fail2ban | Bans an IP for 1h after 5 failed Nextcloud logins in 10 minutes (`docker/fail2ban/jail.d/nextcloud.conf`) |
| Nextcloud | Built-in brute-force throttling, independent of fail2ban |
| ufw (host) | Only 22 (rate-limited), 80, 443 open; default-deny inbound otherwise |

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
endpoint.

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
