#!/usr/bin/env bats
# Tests for scripts/lib/common.sh

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	source "$REPO_ROOT/scripts/lib/common.sh"
}

@test "log includes the message" {
	run log "hello world"
	[ "$status" -eq 0 ]
	[[ "$output" == *"hello world"* ]]
}

@test "die exits nonzero and prefixes ERROR" {
	run die "boom"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ERROR: boom"* ]]
}

@test "require_cmd succeeds for a command that exists" {
	run require_cmd bash
	[ "$status" -eq 0 ]
}

@test "require_cmd fails for a command that does not exist" {
	run require_cmd this-command-does-not-exist-anywhere
	[ "$status" -eq 1 ]
}

@test "require_var succeeds when the variable is set and non-empty" {
	export SOME_TEST_VAR="value"
	run require_var SOME_TEST_VAR
	[ "$status" -eq 0 ]
}

@test "require_var fails when the variable is unset" {
	unset SOME_TEST_VAR
	run require_var SOME_TEST_VAR
	[ "$status" -eq 1 ]
}

@test "require_var fails when the variable is set but empty" {
	export SOME_TEST_VAR=""
	run require_var SOME_TEST_VAR
	[ "$status" -eq 1 ]
}

@test "confirm accepts y" {
	run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; confirm 'ok?'" <<<"y"
	[ "$status" -eq 0 ]
}

@test "confirm accepts Y" {
	run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; confirm 'ok?'" <<<"Y"
	[ "$status" -eq 0 ]
}

@test "confirm rejects n" {
	run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; confirm 'ok?'" <<<"n"
	[ "$status" -eq 1 ]
}

@test "confirm rejects an empty reply (safe default)" {
	run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; confirm 'ok?'" <<<""
	[ "$status" -eq 1 ]
}

@test "confirm rejects garbage input" {
	run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; confirm 'ok?'" <<<"sure"
	[ "$status" -eq 1 ]
}
