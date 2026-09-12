#!/usr/bin/env bash
# Creates a new Nextcloud user with an individual storage quota, without
# touching the web UI. See docs/adding-users.md for the full walkthrough.
#
# Usage:
#   scripts/provision-user.sh <username> [--quota 20G] [--password SECRET]
#
# If --password is omitted, a random password is generated and printed once
# (it is not stored anywhere) — pass it to the user through a secure channel
# and have them change it on first login.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

[ $# -ge 1 ] || die "Usage: $0 <username> [--quota 20G] [--password SECRET]"

username="$1"
shift
quota="${NEXTCLOUD_DEFAULT_QUOTA:-20G}"
password=""

while [ $# -gt 0 ]; do
	case "$1" in
	--quota)
		quota="$2"
		shift 2
		;;
	--password)
		password="$2"
		shift 2
		;;
	*)
		die "Unknown argument: $1"
		;;
	esac
done

require_cmd docker

if [ -z "$password" ]; then
	password="$(gen_password)"
	generated=true
else
	generated=false
fi

cd "$REPO_ROOT"

log "Creating Nextcloud user '$username' with quota '$quota'"
OC_PASS="$password" docker compose exec -T -u www-data -e OC_PASS nextcloud \
	php occ user:add --password-from-env "$username"

docker compose exec -T -u www-data nextcloud \
	php occ user:setting "$username" files quota "$quota"

log "User '$username' created with quota $quota."
if [ "$generated" = true ]; then
	log "Generated password (shown once, not stored): $password"
	log "Have the user change it after first login."
fi
