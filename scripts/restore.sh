#!/usr/bin/env bash
# Restores a restic snapshot for disaster recovery. See
# docs/disaster-recovery.md for the full step-by-step (including what to do
# with the restored files once this script finishes).
#
# Usage:
#   scripts/restore.sh [--snapshot ID] [--target DIR] [--repo local|cold] [--list]
#
#   --list              List available snapshots and exit (no restore).
#   --snapshot ID        Restic snapshot ID to restore (default: latest).
#   --target DIR         Where to write restored files (default: see below).
#   --repo local|cold     Which repository to restore from (default: local).
#
# This NEVER writes directly into the live ZFS-mounted Nextcloud path — it
# restores to a separate directory so you can inspect the result before
# swapping it in, and never silently clobbers data mid-incident.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

snapshot="latest"
target="${TANDEM_RESTORE_TARGET:-/srv/tandem-nas/restore-$(date +%Y%m%d-%H%M%S)}"
repo="local"
list_only=false

while [ $# -gt 0 ]; do
	case "$1" in
	--snapshot)
		snapshot="$2"
		shift 2
		;;
	--target)
		target="$2"
		shift 2
		;;
	--repo)
		repo="$2"
		shift 2
		;;
	--list)
		list_only=true
		shift
		;;
	*)
		die "Unknown argument: $1"
		;;
	esac
done

require_cmd restic

if [ "$repo" = "cold" ]; then
	require_var RESTIC_REPOSITORY_COLD
	require_var RESTIC_PASSWORD_COLD
	export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_COLD"
	export RESTIC_PASSWORD="$RESTIC_PASSWORD_COLD"
else
	require_var RESTIC_REPOSITORY
	require_var RESTIC_PASSWORD
	export RESTIC_REPOSITORY RESTIC_PASSWORD
fi

if [ "$list_only" = true ]; then
	restic snapshots
	exit 0
fi

if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
	confirm "Target '$target' already exists and is not empty. Continue anyway?" || die "Aborted."
fi

mkdir -p "$target"

log "Restoring snapshot '$snapshot' from $RESTIC_REPOSITORY into $target"
restic restore "$snapshot" --target "$target"

log "Restore complete: $target"
log "Next steps (see docs/disaster-recovery.md):"
log "  1. Stop the stack:      docker compose down"
log "  2. Review restored data under: $target"
log "  3. Move it into the ZFS-mounted path used by Nextcloud, then"
log "     start the stack again: docker compose up -d"
