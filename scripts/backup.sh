#!/usr/bin/env bash
# Runs as tandem-backup.service, triggered by udev when the labeled backup
# disk is connected (see ansible/roles/udev-backup-trigger). Also runnable
# by hand for testing: `scripts/backup.sh`.
#
# Config comes from the environment — either already exported (manual run
# with .env sourced) or from /opt/tandem-nas/backup.env (systemd run).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_cmd restic
require_var RESTIC_REPOSITORY
require_var RESTIC_PASSWORD
require_var TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD

export RESTIC_REPOSITORY RESTIC_PASSWORD

if [ ! -d "$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD" ]; then
	die "Source data path '$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD' does not exist — is the ZFS dataset mounted?"
fi

if ! restic cat config >/dev/null 2>&1; then
	log "Repository not initialized yet, running 'restic init' on $RESTIC_REPOSITORY"
	restic init
fi

log "Starting backup of $TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD -> $RESTIC_REPOSITORY"
restic backup "$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD" \
	--tag tandem-nas \
	--host tandem-nas \
	--exclude-caches

log "Applying retention policy (7 daily / 4 weekly / 6 monthly)"
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

log "Verifying a sample of repository data (cheap integrity check)"
restic check --read-data-subset=5%

log "Local backup complete."

if [ -n "${RESTIC_REPOSITORY_COLD:-}" ]; then
	log "Cold storage backend configured, mirroring to $RESTIC_REPOSITORY_COLD"
	(
		export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_COLD"
		export RESTIC_PASSWORD="${RESTIC_PASSWORD_COLD:?RESTIC_PASSWORD_COLD must be set when RESTIC_REPOSITORY_COLD is set}"
		if ! restic cat config >/dev/null 2>&1; then
			log "Cold repository not initialized yet, running 'restic init'"
			restic init
		fi
		restic backup "$TANDEM_ZFS_MOUNTPOINT_NEXTCLOUD" --tag tandem-nas --host tandem-nas --exclude-caches
		restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
	)
	log "Cold storage backup complete."
else
	log "No cold storage backend configured (RESTIC_REPOSITORY_COLD empty) — skipping."
fi

log "Backup run finished successfully."
