# Disaster recovery

This covers three scenarios, in increasing order of severity: one mirror
disk failing (degraded but online), restoring a single file/folder, and full
recovery after losing the main ZFS pool entirely.

## One mirror disk fails (degraded, not down)

This is the whole point of a mirror: losing one of the two disks does **not**
take Nextcloud offline. ZFS keeps serving reads/writes from the surviving
disk; you're running in a degraded state until the failed disk is replaced.

Check status any time with:

```bash
zpool status tandem
```

A failed/missing disk shows as `DEGRADED` with the bad member listed as
`UNAVAIL` or `FAULTED` — everything else stays `ONLINE` and the application
layer keeps working normally.

To replace the failed disk once you have a new one:

```bash
# Identify the new disk's stable id
ls -la /dev/disk/by-id/

sudo zpool replace tandem <old-disk-by-id-or-whatever-zpool-status-shows> /dev/disk/by-id/<new-disk>
zpool status tandem   # watch the resilver progress
```

No downtime, no Compose restart needed — this only touches the pool itself.

## Prerequisites (for the two scenarios below)

- The external backup disk (or your configured cloud backend) with a restic
  repository created by `scripts/backup.sh`.
- `RESTIC_REPOSITORY` and `RESTIC_PASSWORD` from your `.env` (or
  `RESTIC_REPOSITORY_COLD`/`RESTIC_PASSWORD_COLD` if restoring from the cloud
  backend).

Export them before running any restic command by hand:

```bash
set -a && source .env && set +a
```

## Checking what's available

```bash
scripts/restore.sh --list
```

This prints every snapshot with its ID, date, and host tag — restic keeps
7 daily / 4 weekly / 6 monthly snapshots per the retention policy in
`scripts/backup.sh`.

## Restoring a single file or folder

```bash
# Mount the repository as a browsable filesystem and copy out what you need
mkdir -p /tmp/restic-mount
restic mount /tmp/restic-mount &
# browse /tmp/restic-mount/snapshots/latest/...
fusermount -u /tmp/restic-mount
```

Or restore everything to a scratch directory and pick files out manually:

```bash
scripts/restore.sh --target /tmp/tandem-restore-check
```

## Full recovery after losing the main pool

Scenario: both mirrored disks failed, or the pool is otherwise unrecoverable,
and you're rebuilding on new disks.

1. **Replace the disks and recreate the pool.**

   ```bash
   # Identify the new disks
   ls -la /dev/disk/by-id/

   # Update TANDEM_ZFS_DISK_1 / TANDEM_ZFS_DISK_2 in .env, then:
   cd ansible
   set -a && source ../.env && set +a
   ansible-playbook -i inventory.ini playbook.yml --ask-become-pass --tags zfs-mirror
   ```

   This creates a fresh, empty mirrored pool and mounts the (currently empty)
   Nextcloud dataset at `TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD`.

2. **Stop the application layer** (it must not write to the target path
   while you restore into it):

   ```bash
   docker compose down
   ```

3. **Restore the latest snapshot straight into the new dataset:**

   ```bash
   scripts/restore.sh --snapshot latest --target "$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD"
   ```

   The script warns and asks for confirmation because the target directory
   already exists (it was just created by the ZFS role) — that's expected
   here, confirm to proceed.

4. **Fix ownership** (Nextcloud's container runs as `www-data`, uid 33 by
   default in the `nextcloud:29-apache` image):

   ```bash
   sudo chown -R 33:33 "$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD"
   ```

5. **Bring the stack back up and verify:**

   ```bash
   docker compose up -d
   docker compose logs -f nextcloud
   ```

   Once healthy, log in and spot-check a few files/folders per user against
   what you expect. Run `docker compose exec -u www-data nextcloud php occ
   files:scan --all` to make sure Nextcloud's internal file cache matches the
   restored files on disk.

6. **Re-establish the backup disk relationship.** The udev label survives on
   the external disk itself, so simply reconnecting it (or running
   `sudo systemctl start tandem-backup.service`) resumes incremental backups
   against the same restic repository — restic only needs to see the new
   pool's files once to compute the delta from the prior snapshot history.

## Testing this without a real failure

Simulate pool loss safely in a scratch VM or a spare pair of disks:
`zpool destroy tandem`, then follow steps 1–6 above end to end. This is worth
doing once after initial setup so you know the procedure works before you
actually need it under pressure.
