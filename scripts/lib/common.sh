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
