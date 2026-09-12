#!/usr/bin/env bash
# Shared helpers sourced by the other scripts/*.sh. Not meant to be run directly.

log()  { printf '[%(%Y-%m-%dT%H:%M:%S%z)T] %s\n' -1 "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

require_var() {
	local name="$1"
	if [ -z "${!name:-}" ]; then
		die "Required variable $name is not set (check your .env / backup.env)."
	fi
}

require_cmd() {
	local cmd="$1"
	command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found in PATH."
}

confirm() {
	local prompt="$1"
	local reply
	read -r -p "$prompt [y/N] " reply
	[ "$reply" = "y" ] || [ "$reply" = "Y" ]
}

gen_password() {
	# Not a plain `tr | head -c`: under `set -o pipefail`, head closing the
	# pipe early sends tr a SIGPIPE that turns into a nonzero pipeline
	# status, which would abort the whole script under `set -e`. The `||
	# true` absorbs that. The loop guards the other failure mode: on some
	# environments a single read from /dev/urandom through the pipeline can
	# come up short of what was asked for (observed intermittently in CI,
	# never locally) — keep pulling more until the password is actually the
	# requested length instead of silently returning a shorter one.
	local pw=""
	while [ "${#pw}" -lt 24 ]; do
		pw+="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$((24 - ${#pw}))" || true)"
	done
	printf '%s' "$pw"
}
