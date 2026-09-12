# Tandem NAS

[![CI](https://github.com/OWNER/tandem-nas/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/tandem-nas/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

*[Leia em português](README.pt-BR.md)*

An open-source, self-hosted NAS stack: two disks mirrored in sync ("tandem"),
redundant storage, automatic versioned backups, multi-user with individual
quotas, and remote access from the official mobile apps or any browser — no
VPN required.

Built to run on an **already-in-use Ubuntu Desktop machine**, not a clean
dedicated appliance — it's designed to coexist with whatever else is running
on your box.

## What this gives you

- **Redundant storage**: two disks in a ZFS mirror, with checksums
  (self-healing against silent corruption) and cheap snapshots.
- **Automatic backup**: plug in an external disk, an incremental/versioned
  `restic` backup starts on its own — no cron, no clicking anything.
- **Multi-user**: each person gets their own account with a configurable
  storage quota, provisioned by a single command.
- **Remote access anywhere**: the official Nextcloud iOS/Android apps and any
  web browser, over HTTPS with a real certificate — from outside your home
  network, no VPN.
- **Secure by default**: automatic HTTPS (Caddy + Let's Encrypt), rate
  limiting, security headers, fail2ban, and 2FA enforced on Nextcloud
  accounts.
- **Cloud-ready, not cloud-locked**: the backup destination is just a restic
  repository URL — add an S3/B2/Wasabi/GCS/Azure destination later without
  touching the backup script.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full diagram and the
reasoning behind each design decision.

## Hardware this was built and tested against

- 2× 1TB SATA HDDs → ZFS mirror (the main pool)
- 1× 2TB external USB HDD → backup destination, connected intermittently
- Host: Ubuntu Desktop 24.04 (GNOME), already running other workloads

None of this is hardcoded — different disk counts/sizes work too, see
`.env.example`.

## Prerequisites

- Ubuntu 22.04+ (Desktop or Server) on the machine that will run this.
- At least two block devices for the mirror (more than two also works — ZFS
  mirrors can have more than 2 members) and, ideally, one removable disk for
  backups.
- A domain or subdomain you control, pointed at this machine's public IP
  (see [`docs/remote-access.md`](docs/remote-access.md) — including how to
  handle a dynamic IP via DDNS).
- `git`, `ansible` (`pipx install ansible-core` or `apt install
  ansible-core`), and Docker Engine + the Compose plugin.
- Sudo access on the target machine (the Ansible playbook needs it for disk
  and systemd changes — expect an interactive password prompt, this project
  does not assume passwordless sudo).

## Quickstart

```bash
git clone https://github.com/OWNER/tandem-nas.git
cd tandem-nas
cp .env.example .env
$EDITOR .env   # fill in your disk by-id paths, domain, passwords, etc.
```

Identify your disks by their stable ID (never use `/dev/sdX`, it can change
across reboots):

```bash
ls -la /dev/disk/by-id/
```

### 1. Host layer (Ansible) — disks, backup trigger, power settings, firewall

```bash
cd ansible
cp inventory.example.ini inventory.ini
$EDITOR inventory.ini   # set tandem_desktop_user; add remote hosts if replicating elsewhere
ansible-galaxy collection install -r requirements.yml

set -a && source ../.env && set +a
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
```

This creates the ZFS mirror pool, installs the udev rule + systemd service
that trigger backups when the external disk is connected, disables
suspend/screen-lock (a normal desktop would otherwise go to sleep and take
the NAS offline), and applies baseline firewall rules.

### 2. Application layer (Docker Compose) — Nextcloud, Caddy, fail2ban

```bash
cd ..
docker compose up -d
```

Watch it come up:

```bash
docker compose logs -f nextcloud
```

Once healthy, visit `https://<TANDEM_PUBLIC_DOMAIN>` and log in with
`NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD` from your `.env`. Then
turn on 2FA enforcement (see [`docs/remote-access.md`](docs/remote-access.md)) before adding anyone else.

### 3. Add users

```bash
scripts/provision-user.sh alice --quota 50G
```

See [`docs/adding-users.md`](docs/adding-users.md).

### 4. Prepare the backup disk (once)

```bash
sudo scripts/prepare-backup-disk.sh /dev/disk/by-id/<your-external-disk>
```

From then on, connecting that disk automatically runs a backup
(`journalctl -u tandem-backup.service` to watch it). See
[`docs/disaster-recovery.md`](docs/disaster-recovery.md) for restoring from
it, including full pool-loss recovery.

## Repository layout

```
tandem-nas/
├── docker-compose.yml       # Nextcloud, Postgres, Redis, Caddy, fail2ban
├── docker/                  # Caddy custom build + fail2ban jail/filter config
├── ansible/                 # Host layer: ZFS, udev/systemd, power, firewall
│   └── roles/
│       ├── zfs-mirror/
│       ├── udev-backup-trigger/
│       ├── desktop-power/
│       └── hardening/
├── scripts/                 # backup.sh, restore.sh, provision-user.sh, ...
└── docs/                    # Disaster recovery, adding users, remote access
```

## Status / known trade-offs

Anything accepted as a deliberate trade-off rather than fixed outright is
tracked in [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) with the reasoning — check
there before assuming something was simply missed.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Please read
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) too.

## License

[MIT](LICENSE).
