#!/usr/bin/env bats
# Tests for the pure/parsing logic in scripts/setup.sh. Anything that
# touches the network, docker, ansible, or terraform is out of scope here
# by design — see tests/README.md.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	# shellcheck source=../../scripts/setup.sh
	source "$REPO_ROOT/scripts/setup.sh"
}

# --- gen_password -----------------------------------------------------

@test "gen_password produces a 24-character string" {
	run gen_password
	[ "$status" -eq 0 ]
	[ "${#output}" -eq 24 ]
}

@test "gen_password produces only alphanumeric characters" {
	run gen_password
	[[ "$output" =~ ^[A-Za-z0-9]+$ ]]
}

@test "gen_password does not repeat across calls" {
	local p1 p2
	p1="$(gen_password)"
	p2="$(gen_password)"
	[ "$p1" != "$p2" ]
}

@test "gen_password survives set -o pipefail (regression: tr|head SIGPIPE)" {
	# This is exactly the bug that motivated these tests: `tr ... | head -c
	# N` under pipefail turns tr's SIGPIPE into a nonzero pipeline exit
	# status, which would abort the whole wizard the first time a password
	# was generated. gen_password must not use that pattern.
	run bash -c "set -euo pipefail; source '$REPO_ROOT/scripts/setup.sh' >/dev/null 2>&1 || true; gen_password"
	[ "$status" -eq 0 ]
}

# --- set_env_var / get_env_var -----------------------------------------

@test "set_env_var appends a new key" {
	ENV_FILE="$(mktemp)"
	: >"$ENV_FILE"
	set_env_var FOO bar
	[ "$(get_env_var FOO)" = "bar" ]
	rm -f "$ENV_FILE"
}

@test "set_env_var updates an existing key in place" {
	ENV_FILE="$(mktemp)"
	printf 'FOO=old\nBAZ=untouched\n' >"$ENV_FILE"
	set_env_var FOO new
	[ "$(get_env_var FOO)" = "new" ]
	[ "$(get_env_var BAZ)" = "untouched" ]
	[ "$(grep -c '^FOO=' "$ENV_FILE")" -eq 1 ]
	rm -f "$ENV_FILE"
}

@test "get_env_var returns empty for a missing key" {
	ENV_FILE="$(mktemp)"
	: >"$ENV_FILE"
	[ -z "$(get_env_var NOPE)" ]
	rm -f "$ENV_FILE"
}

# --- list_candidate_disks / pick_disks filtering ------------------------

@test "list_candidate_disks lists whole disks but excludes partitions" {
	TANDEM_BY_ID_DIR="$REPO_ROOT/tests/fixtures/by-id"
	run bash -c "source '$REPO_ROOT/scripts/setup.sh'; TANDEM_BY_ID_DIR='$TANDEM_BY_ID_DIR' list_candidate_disks | tr '\0' '\n'"
	[[ "$output" == *"ata-FAKE-DISK-1"* ]]
	[[ "$output" == *"ata-FAKE-DISK-2"* ]]
	[[ "$output" != *"part"* ]]
}

@test "pick_disks fails clearly with fewer than 2 candidate disks" {
	empty_dir="$(mktemp -d)"
	run bash -c "source '$REPO_ROOT/scripts/setup.sh'; TANDEM_BY_ID_DIR='$empty_dir' pick_disks"
	[ "$status" -ne 0 ]
	[[ "$output" == *"não dá pra montar o mirror"* ]]
	rmdir "$empty_dir"
}

# --- reachability_suggests_path_a --------------------------------------

@test "reachability_suggests_path_a is true when a node reports OK" {
	local result='{"node1":[[1,0.5,"OK",200,"1.2.3.4"]]}'
	run reachability_suggests_path_a "$result"
	[ "$status" -eq 0 ]
}

@test "reachability_suggests_path_a is false when every node times out" {
	local result='{"node1":[{"error":"Connection timed out"}],"node2":[{"error":"Connection timed out"}]}'
	run reachability_suggests_path_a "$result"
	[ "$status" -eq 1 ]
}

@test "reachability_suggests_path_a is false for empty input" {
	run reachability_suggests_path_a ""
	[ "$status" -eq 1 ]
}

# --- extract_check_host_request_id --------------------------------------

@test "extract_check_host_request_id parses a real-shaped response" {
	local resp='{"ok":1,"permanent_link":"https://check-host.net/check-report/abc","request_id":"abc123"}'
	run extract_check_host_request_id "$resp"
	[ "$output" = "abc123" ]
}

@test "extract_check_host_request_id returns empty for malformed input" {
	run extract_check_host_request_id "not json at all"
	[ -z "$output" ]
}

# --- extract_cloudflare_account_id / extract_cloudflare_zone_id --------

@test "extract_cloudflare_account_id parses a real-shaped zones response" {
	local json='{"result":[{"id":"zone123","account":{"id":"acct456"}}],"success":true}'
	run extract_cloudflare_account_id "$json"
	[ "$output" = "acct456" ]
}

@test "extract_cloudflare_zone_id parses a real-shaped zones response" {
	local json='{"result":[{"id":"zone123","account":{"id":"acct456"}}],"success":true}'
	run extract_cloudflare_zone_id "$json"
	[ "$output" = "zone123" ]
}

@test "extract_cloudflare_account_id returns empty when result is an empty list (zone not found)" {
	local json='{"result":[],"success":true}'
	run extract_cloudflare_account_id "$json"
	[ -z "$output" ]
}

@test "extract_cloudflare_zone_id returns empty for malformed input" {
	run extract_cloudflare_zone_id "not json at all"
	[ -z "$output" ]
}
