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
	# head closing the pipe early after 24 bytes sends tr a SIGPIPE. Two
	# separate things can go wrong from that, both handled here:
	#   - Under `set -o pipefail`, tr's signal-driven exit turns into a
	#     nonzero pipeline status that would abort the whole script under
	#     `set -e` — the `|| true` absorbs that.
	#   - If SIGPIPE is inherited as ignored (observed on GitHub Actions'
	#     hosted runners, never locally) tr instead gets EPIPE back from
	#     write() and prints "tr: write error: Broken pipe" to stderr. That
	#     text would otherwise leak into a caller's captured output (e.g.
	#     bats' `run`, which merges stdout+stderr) and corrupt the
	#     password — `2>/dev/null` on tr specifically discards it.
	# The loop is defense in depth: keep pulling more bytes until the
	# password actually reaches the requested length instead of trusting a
	# single read to always deliver exactly that much.
	local pw=""
	while [ "${#pw}" -lt 24 ]; do
		pw+="$(tr -dc 'A-Za-z0-9' 2>/dev/null </dev/urandom | head -c "$((24 - ${#pw}))" || true)"
	done
	printf '%s' "$pw"
}
