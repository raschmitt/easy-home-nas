# Known issues / accepted trade-offs

Per this project's contribution process (see `CONTRIBUTING.md`), nothing
gets deferred silently — anything not resolved during initial implementation
is recorded here with the reasoning, ready to become a GitHub issue once the
repository is pushed (`gh issue create` from each entry below, or paste
directly into the New Issue form).

## 1. No automated test harness for Ansible roles

**Status:** deferred.
**Why:** Molecule (the standard Ansible role test framework) needs a
container/VM driver to actually exercise `zpool create` and udev rules,
which is disproportionate setup for a first release. `ansible-lint` in CI
catches syntax/style issues; role logic is currently verified by hand
against the read-only scan of a real machine (documented in this repo's
initial implementation) and the disaster-recovery walkthrough in
`docs/disaster-recovery.md`.
**Acceptance:** fine for now because the roles are short and each destructive
action (pool creation, SSH hardening) already has an explicit safety check
that fails loudly rather than silently proceeding.

## 2. `tandem-backup.service` doesn't defend against rapid disk bounce

**Status:** accepted limitation.
**Why:** `StartLimitBurst=1` on the unit limits re-triggering within its
`StartLimitIntervalSec=600` window, but if the external disk is unplugged
mid-backup and replugged, the mount/unmount sequence could race. This is a
narrow edge case (a person actively wiggling the cable during a backup) and
not the intermittent-connect-then-leave-it usage pattern this project
targets.
**Fix later if:** someone hits this in practice — the fix would be a
`flock`-based lock file around the mount+backup+unmount sequence.

## 3. No DDNS client is provisioned automatically

**Status:** deferred, by design.
**Why:** the right DDNS client is entirely provider-specific (router
built-in client, `ddclient`, provider's own CLI). Baking in one provider's
tool would contradict the "modular, not hardcoded" requirement more than it
would help. `docs/remote-access.md` documents the decision points instead.
**Acceptance:** appropriate — this is a config/deployment choice, not a gap
in the stack itself.

## 4. Caddy's `caddy-ratelimit` module isn't pinned to a specific version

**Status:** tech debt, should fix before wide adoption.
**Why:** `docker/caddy/Dockerfile` builds `github.com/mholt/caddy-ratelimit`
without a version constraint, so a build today and a build in six months
could pick up breaking changes in the plugin.
**Fix:** pin `xcaddy build --with github.com/mholt/caddy-ratelimit@<tag>` to
a specific released tag, and bump deliberately.

## 5. fail2ban container requires host networking + `NET_ADMIN`/`NET_RAW`

**Status:** accepted constraint, documented.
**Why:** IP-level banning via `iptables` from inside a container requires
this; there's no functional rootless/sandboxed alternative that still bans
at the host firewall level. On a Docker setup where this capability is
restricted (some managed/rootless Docker configurations), the fail2ban
service simply won't start — Nextcloud's own brute-force throttling and
Caddy rate limiting still apply in that case, just without the IP ban layer.
**Acceptance:** acceptable given this is a single-host, self-hosted project
where you also control the Docker daemon configuration.

## 6. Full disaster-recovery flow isn't exercised in CI

**Status:** deferred, manual test only.
**Why:** actually destroying a ZFS pool and restoring from restic needs real
(or virtualized) disks — not something to run against shared CI runners.
`docs/disaster-recovery.md` includes a "test this without a real failure"
section describing how to do it in a scratch VM; that remains a manual step
for now.
**Fix later if:** someone wants to invest in a VM-based CI job (e.g. using
KVM-in-CI) specifically for this — worth it once the project has more than
one active maintainer to keep that pipeline healthy.

## 7. Postgres isn't on the ZFS mirror and isn't in the automated backup

**Status:** open, not yet fixed.
**Why:** `docker-compose.yml` bind-mounts Postgres at
`${TANDEM_DATA_ROOT}/postgres`, a plain directory on the host's root
filesystem — not under the ZFS mirror (only
`$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD` is a ZFS dataset). `scripts/backup.sh`
only backs up that ZFS mountpoint via restic, so the database holding every
user account, share, and file-index entry currently has neither the
mirror's redundancy/checksums nor a place in the automated backup — only
Nextcloud's files/appdata are actually protected. Found while taking a
manual `pg_dump` as a safety net before a Nextcloud version upgrade, since
that was the only backup of the database that existed at the time.
**Fix later:** either move the Postgres bind mount onto a ZFS dataset
(`tandem/postgres`, same pattern as `tandem/nextcloud`), or add a
`pg_dump` step to `scripts/backup.sh` ahead of the restic run — probably
both, since the ZFS mirror protects against disk failure and the backup
protects against everything else (accidental deletion, upgrade gone
wrong, ransomware).
