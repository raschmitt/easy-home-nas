# Adding and managing users

Users are provisioned via script, not by clicking through the Nextcloud admin
UI, so it stays repeatable and auditable.

Every command below is a template: `{{username}}` (and, where a second
account is involved, `{{other_username}}`) is a placeholder, not a literal
value — replace it with the actual login you're creating or managing (e.g.
`alice`, `jsmith`, `rogerio`).

## Create a user

```bash
scripts/provision-user.sh {{username}} --quota 50G
```

- `--quota` accepts Nextcloud's quota syntax (`10G`, `500M`, `none` for
  unlimited). If omitted, it falls back to `NEXTCLOUD_DEFAULT_QUOTA` from
  `.env`.
- If you don't pass `--password`, a random 24-character password is
  generated and printed once to your terminal (never stored to disk or
  logged) — send it to the user through a channel you trust and have them
  change it on first login.

```bash
scripts/provision-user.sh {{username}} --quota 100G --password 'a-password-you-chose'
```

## Change an existing user's quota

```bash
docker compose exec -u www-data nextcloud php occ user:setting {{username}} files quota 80G
```

## List users and their current quota/usage

```bash
docker compose exec -u www-data nextcloud php occ user:list
docker compose exec -u www-data nextcloud php occ user:report
```

## Enforce 2FA (should already be on — see docs/remote-access.md)

```bash
docker compose exec -u www-data nextcloud php occ twofactorauth:enforce
```

## Remove a user

```bash
docker compose exec -u www-data nextcloud php occ user:delete {{username}}
```

This deletes the user's Nextcloud account and files. If you want to keep
their files, transfer ownership first (`{{username}}` is the account being
removed, `{{other_username}}` is who receives their files):

```bash
docker compose exec -u www-data nextcloud php occ files:transfer-ownership {{username}} {{other_username}}
```

## Default sample files (Documents, Photos, Templates)

Nextcloud normally seeds every new account with a "skeleton" of sample
files. `scripts/setup.sh` disables this right after bringing the stack up
(`occ config:system:set skeletondirectory --value=""`), so users created
from then on start with an empty account. If you're on an install from
before that step existed, or skipped it, run it yourself once:

```bash
docker compose exec -u www-data nextcloud php occ config:system:set skeletondirectory --value=""
```

This only affects accounts created afterward — it doesn't remove files
already copied into an existing user's folder.

## Why not a ZFS dataset per user?

See the "Multi-tenancy" section of `ARCHITECTURE.md` for the reasoning, and
`docs/zfs-per-user-quota-advanced.md` if you specifically need
filesystem-level per-user isolation instead of (or in addition to)
Nextcloud's own quota enforcement.
