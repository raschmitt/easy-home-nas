#!/usr/bin/env bash
# One-time setup for the external backup disk: wipes it, creates a single
# ext4 partition, and labels it so the udev rule in
# ansible/roles/udev-backup-trigger recognizes it on connect.
#
# THIS IS DESTRUCTIVE. Run it once, deliberately, against the external disk
# only — never against the main mirrored pool's disks.
#
# Usage: sudo scripts/prepare-backup-disk.sh /dev/disk/by-id/usb-...
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

[ $# -eq 1 ] || die "Usage: $0 /dev/disk/by-id/<your-external-disk>"
disk="$1"
label="${TANDEM_BACKUP_DISK_LABEL:-TANDEM_BACKUP}"

[ "$(id -u)" -eq 0 ] || die "Run this with sudo."
require_cmd wipefs
require_cmd parted
require_cmd mkfs.ext4

case "$disk" in
/dev/disk/by-id/*) ;;
*) die "Pass a stable /dev/disk/by-id/... path, not $disk (by-id survives reboots; /dev/sdX does not)." ;;
esac

[ -e "$disk" ] || die "$disk does not exist. List real disks with: ls -la /dev/disk/by-id/"

real_dev="$(readlink -f "$disk")"
log "Target: $disk -> $real_dev"
lsblk "$real_dev"

echo
echo "!!! Everything on $real_dev will be PERMANENTLY ERASED. !!!"
confirm "Type y to continue" || die "Aborted, nothing was touched."
confirm "Really sure? This cannot be undone" || die "Aborted, nothing was touched."

log "Wiping existing signatures on $real_dev"
wipefs -a "$real_dev"

log "Creating a single ext4 partition labeled '$label'"
parted -s "$real_dev" mklabel gpt mkpart primary ext4 0% 100%
partprobe "$real_dev"
sleep 2
part="${real_dev}1"
[ -e "$part" ] || part="${real_dev}p1"
mkfs.ext4 -L "$label" "$part"

log "Done. Label '$label' is now on $part."
log "Reconnect the disk (or run: sudo systemctl start tandem-backup.service) to trigger the first backup."
