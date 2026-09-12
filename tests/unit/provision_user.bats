#!/usr/bin/env bats
# Integration-style tests for scripts/provision-user.sh: runs the real
# script with a stubbed `docker` on PATH so we exercise real argument
# parsing and command construction without needing an actual Nextcloud.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	STUB_BIN="$(mktemp -d)"
	DOCKER_CALLS_LOG="$(mktemp)"
	export DOCKER_CALLS_LOG

	cat >"$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_CALLS_LOG"
exit 0
EOF
	chmod +x "$STUB_BIN/docker"
	export PATH="$STUB_BIN:$PATH"
}

teardown() {
	rm -rf "$STUB_BIN"
	rm -f "$DOCKER_CALLS_LOG"
}

@test "requires a username argument" {
	run "$REPO_ROOT/scripts/provision-user.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Usage:"* ]]
}

@test "rejects unknown flags" {
	run "$REPO_ROOT/scripts/provision-user.sh" alice --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unknown argument"* ]]
}

@test "falls back to NEXTCLOUD_DEFAULT_QUOTA when --quota is omitted" {
	NEXTCLOUD_DEFAULT_QUOTA=50G run "$REPO_ROOT/scripts/provision-user.sh" alice --password test1234567890
	[ "$status" -eq 0 ]
	run cat "$DOCKER_CALLS_LOG"
	[[ "$output" == *"quota 50G"* ]]
}

@test "--quota overrides the default" {
	run "$REPO_ROOT/scripts/provision-user.sh" alice --quota 5G --password test1234567890
	[ "$status" -eq 0 ]
	run cat "$DOCKER_CALLS_LOG"
	[[ "$output" == *"quota 5G"* ]]
}

@test "passes the username through to both the user:add and quota calls" {
	run "$REPO_ROOT/scripts/provision-user.sh" bob --quota 10G --password test1234567890
	[ "$status" -eq 0 ]
	run cat "$DOCKER_CALLS_LOG"
	[[ "$output" == *"user:add --password-from-env bob"* ]]
	[[ "$output" == *"user:setting bob files quota 10G"* ]]
}

@test "with no --password, generates one, reports it once, and still succeeds (SIGPIPE regression)" {
	run "$REPO_ROOT/scripts/provision-user.sh" alice
	[ "$status" -eq 0 ]
	[[ "$output" == *"Generated password"* ]]
}

@test "with --password given, does not print a generated-password message" {
	run "$REPO_ROOT/scripts/provision-user.sh" alice --password test1234567890
	[ "$status" -eq 0 ]
	[[ "$output" != *"Generated password"* ]]
}
