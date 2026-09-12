# Mobile access

Setting up the official Nextcloud app on a phone — file access, automatic
photo backup, and 2FA — from outside your home network, no VPN.

## Prerequisites

- The server is reachable at `https://<TANDEM_PUBLIC_DOMAIN>` — confirm
  this works in a browser first (see `docs/remote-access.md` if it doesn't;
  get that working before troubleshooting the mobile app, since the app
  can't do anything a browser can't).
- A user account already provisioned (`scripts/provision-user.sh`, see
  `docs/adding-users.md`) — don't use the `admin` account day to day on a
  phone.
- 2FA enforced (`docs/remote-access.md` → "Turn on 2FA") — set this up
  *before* installing the app on anyone else's phone, since enrollment
  happens on first login.

## Install and add the account

1. Install the official app:
   - iOS: [Nextcloud on the App Store](https://apps.apple.com/app/nextcloud/id1125420102)
   - Android: [Nextcloud on Google Play](https://play.google.com/store/apps/details?id=com.nextcloud.client)
2. Open the app → **Log in** → enter the server address:
   `https://<TANDEM_PUBLIC_DOMAIN>` (the full `https://`, not just the
   domain — some older app versions need the scheme typed explicitly).
3. The app opens an in-app browser to Nextcloud's own login page (this is
   normal — it's not a third-party page, it's your server, just rendered
   in a webview so the app never sees the password directly). Log in with
   the user's own credentials, not the admin account.
4. If 2FA is enforced, it prompts for the TOTP code at this point —
   30 seconds from install to this being over.
5. Nextcloud issues the app a device-specific token behind the scenes (an
   "app password"), not a copy of the account password. Confirm this under
   **Settings → Security** on the web: a new entry appears named after the
   device/app, distinct from the main password. Nothing else to do here —
   the app handles this on its own — but it's why revoking access from one
   phone (below) doesn't touch the account password at all.

## Automatic photo/video backup

This is usually the actual reason to install the app rather than just using
a browser. In the app:

**Settings → Auto upload** (exact wording varies slightly iOS vs Android):

- Turn it on, pick the folder(s) to watch (camera roll at minimum).
- **Upload on Wi-Fi only** vs. **any connection**: pick Wi-Fi only unless
  the user has an unmetered mobile plan — first-run backup of an existing
  camera roll can be tens of GB.
- Destination folder on the server, and whether to keep the local copy or
  free space once uploaded (be conservative here — "delete from phone
  after upload" is a one-way door for anything not backed up elsewhere).

Multiple devices from the same user land in the same account's quota (see
`docs/adding-users.md` for changing it if photo backup pushes someone over
their limit).

## Revoking a lost or old device

Don't change the account password for this — it would log out every device,
not just one. Instead, on the web:

```bash
docker compose exec -u www-data nextcloud php occ user:list
```

Then **Settings → Security** for that user (as them, or as an admin viewing
their account) → find the device's app password entry under "Devices &
sessions" → revoke just that one. The device stops syncing immediately; the
account's actual password is untouched and every other device stays logged
in.

## Troubleshooting

- **Works on Wi-Fi, fails on mobile data (or vice versa):** if it's
  *specifically* one network type that fails, that's not a Nextcloud
  problem — it means the domain isn't actually resolving/reachable the
  same way on both, which usually points to a home-network-only DNS
  override (e.g. a Pi-hole or router entry that only exists on your LAN)
  shadowing the real public DNS record. The domain should behave
  identically on any network, precisely because there's no VPN or
  local-network dependency in this setup — if it doesn't, something
  local is intercepting the name, not the server.
- **"Untrusted certificate" or similar TLS warning:** shouldn't happen with
  either Path A (Let's Encrypt) or Path B (Cloudflare) — if it does, check
  `docs/remote-access.md`'s verification steps (the `openssl s_client`
  check) from the server itself first, since a real cert problem shows up
  there too, before assuming it's the phone.
- **Login works but auto-upload silently doesn't:** check the account's
  quota isn't already full (`docs/adding-users.md`) — Nextcloud's mobile
  app doesn't always surface a clear "quota exceeded" error for background
  uploads.
- **Using Path B (Cloudflare Tunnel) and things feel slow/flaky:** check
  `docker compose logs cloudflared` for reconnects — a healthy tunnel shows
  multiple stable `Registered tunnel connection` lines and no repeated
  disconnect/reconnect churn.
