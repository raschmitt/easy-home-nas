# Advanced: per-user ZFS datasets instead of Nextcloud quotas

The default setup (see `ARCHITECTURE.md`) enforces per-user storage limits
through Nextcloud's own quota system, backed by one shared ZFS dataset. This
is simpler to automate and doesn't require restarting containers when users
are added.

If you specifically need **filesystem-level** isolation — e.g. users also
get direct filesystem access (Samba/NFS export) alongside Nextcloud, and you
want the quota enforced by the kernel regardless of what touches the files —
you can create one ZFS dataset per user instead. This is not wired up by the
default `zfs-mirror` role; treat this as a recipe to adapt.

## The pattern

```bash
# One dataset per user, each with its own hard quota
sudo zfs create -o quota=50G tandem/users/alice
sudo zfs create -o quota=100G tandem/users/bob
```

## Wiring it into Nextcloud

Nextcloud doesn't natively bind-mount arbitrary host paths per user; you'd
use the **External Storage** app to map each dataset in as that user's
storage, or bind-mount each dataset into the container at a per-user path
and use `occ files_external`. Either way, every new user means:

1. `zfs create -o quota=<size> tandem/users/<name>`
2. Add the corresponding bind mount (docker-compose.yml) or
   `occ files_external:create` entry.
3. Restart the `nextcloud` container if you changed `docker-compose.yml`.

## Trade-off recap

| | Nextcloud quota (default) | ZFS dataset per user |
|---|---|---|
| New user requires container restart | No | Yes (if bind-mounted) |
| Quota enforced by | Nextcloud application layer | Kernel (ZFS) |
| Works for non-Nextcloud access (Samba/NFS) | No | Yes |
| Automation complexity | Low (`scripts/provision-user.sh`) | Higher (compose file edits per user) |

Use this pattern if you're extending Tandem NAS to serve files outside of
Nextcloud (e.g. adding Samba later) and need one enforcement point that
covers both.
