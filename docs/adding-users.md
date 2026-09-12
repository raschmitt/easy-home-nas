# Adding and managing users

Users are provisioned via script, not by clicking through the Nextcloud admin
UI, so it stays repeatable and auditable.

## Create a user

```bash
scripts/provision-user.sh alice --quota 50G
```

- `--quota` accepts Nextcloud's quota syntax (`10G`, `500M`, `none` for
  unlimited). If omitted, it falls back to `NEXTCLOUD_DEFAULT_QUOTA` from
  `.env`.
- If you don't pass `--password`, a random 24-character password is
  generated and printed once to your terminal (never stored to disk or
  logged) — send it to the user through a channel you trust and have them
  change it on first login.

```bash
scripts/provision-user.sh bob --quota 100G --password 'a-password-you-chose'
```

## Change an existing user's quota

```bash
docker compose exec -u www-data nextcloud php occ user:setting alice files quota 80G
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
docker compose exec -u www-data nextcloud php occ user:delete alice
```

This deletes the user's Nextcloud account and files. If you want to keep
their files, transfer ownership first:

```bash
docker compose exec -u www-data nextcloud php occ files:transfer-ownership alice bob
```

## Why not a ZFS dataset per user?

See the "Multi-tenancy" section of `ARCHITECTURE.md` for the reasoning, and
`docs/zfs-per-user-quota-advanced.md` if you specifically need
filesystem-level per-user isolation instead of (or in addition to)
Nextcloud's own quota enforcement.
