#!/usr/bin/env bats
# Tests for scripts/setup.sh's "already configured/running" detection —
# the behavior that lets a re-run repair/update an existing install instead
# of blindly redoing every step (access path, stack state, user list).
# Uses a stubbed `docker` on PATH, controlled via env vars, the same
# pattern tests/unit/provision_user.bats uses.
#
# Note: setup.sh sets ENV_FILE (and REPO_ROOT) itself at source time, so
# every test below overrides ENV_FILE *after* sourcing, not before —
# otherwise the script's own assignment would clobber it.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	STUB_BIN="$(mktemp -d)"
	DOCKER_CALLS_LOG="$(mktemp)"
	export DOCKER_CALLS_LOG

	# DOCKER_STUB_RUNNING=1       -> `compose ps --status running -q` reports a container.
	# DOCKER_STUB_USER_LIST=...  -> `occ user:list` prints this (empty = no users yet).
	# DOCKER_STUB_SKELETON_FAIL=1 -> `occ config:system:set skeletondirectory` fails (Nextcloud not up).
	cat >"$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_CALLS_LOG"

if [[ "$*" == "compose ps --status running -q"* ]]; then
	[ "${DOCKER_STUB_RUNNING:-0}" = "1" ] && echo "fakecontainerid123"
	exit 0
fi
if [[ "$*" == *"occ user:list"* ]]; then
	[ -n "${DOCKER_STUB_USER_LIST:-}" ] && printf '%s\n' "$DOCKER_STUB_USER_LIST"
	exit 0
fi
if [[ "$*" == *"config:system:set skeletondirectory"* ]]; then
	[ "${DOCKER_STUB_SKELETON_FAIL:-0}" = "1" ] && exit 1
	exit 0
fi
exit 0
EOF
	chmod +x "$STUB_BIN/docker"
	export PATH="$STUB_BIN:$PATH"

	STDIN_FILE="$(mktemp)"
}

teardown() {
	rm -rf "$STUB_BIN"
	rm -f "$DOCKER_CALLS_LOG" "$STDIN_FILE"
}

# --- compose_profile_args_for_existing_config --------------------------

@test "compose_profile_args_for_existing_config recovers the tunnel profile from .env" {
	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE='$(mktemp)'
		printf 'TANDEM_CADDY_ADDRESS_PREFIX=http://\n' >\"\$ENV_FILE\"
		compose_profile_args_for_existing_config
	"
	[ "$output" = "--profile tunnel" ]
}

@test "compose_profile_args_for_existing_config is empty for a Path A (direct exposure) config" {
	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE='$(mktemp)'
		printf 'TANDEM_CADDY_ADDRESS_PREFIX=\n' >\"\$ENV_FILE\"
		compose_profile_args_for_existing_config
	"
	[ -z "$output" ]
}

# --- configure_access_path skip/keep ------------------------------------

@test "configure_access_path offers to keep an already-configured domain, restoring the tunnel profile" {
	printf 'y\n' >"$STDIN_FILE"

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE='$(mktemp)'
		printf 'TANDEM_PUBLIC_DOMAIN=nas.example.com\nTANDEM_CADDY_ADDRESS_PREFIX=http://\n' >\"\$ENV_FILE\"
		configure_access_path <'$STDIN_FILE'
		echo \"PROFILE_ARGS=\${COMPOSE_PROFILE_ARGS[*]}\"
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Mantendo configuração existente (nas.example.com)"* ]]
	[[ "$output" == *"PROFILE_ARGS=--profile tunnel"* ]]
}

@test "configure_access_path re-runs detection when the user declines to keep the existing config" {
	printf 'n\n' >"$STDIN_FILE"

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE='$(mktemp)'
		printf 'TANDEM_PUBLIC_DOMAIN=nas.example.com\n' >\"\$ENV_FILE\"
		detect_access_path() { ACCESS_PATH=RECONFIGURED; }
		setup_path_a() { echo 'setup_path_a ran'; }
		configure_access_path <'$STDIN_FILE'
	"
	[[ "$output" == *"setup_path_a ran"* ]]
}

# --- start_stack ---------------------------------------------------------

@test "start_stack detects an already-running stack and offers to apply changes instead" {
	export DOCKER_STUB_RUNNING=1
	printf 'y\n' >"$STDIN_FILE"

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE=/dev/null
		start_stack <'$STDIN_FILE'
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"A stack já está no ar."* ]]
	run cat "$DOCKER_CALLS_LOG"
	[[ "$output" == *"compose up -d"* ]]
}

@test "start_stack uses the first-install prompt when nothing is running yet" {
	printf 'y\n' >"$STDIN_FILE"

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE=/dev/null
		start_stack <'$STDIN_FILE'
	"
	[ "$status" -eq 0 ]
	[[ "$output" != *"A stack já está no ar."* ]]
	run cat "$DOCKER_CALLS_LOG"
	[[ "$output" == *"compose up -d"* ]]
}

# --- disable_default_skeleton_files ---------------------------------------

@test "disable_default_skeleton_files disables the skeleton and reports success" {
	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE=/dev/null
		disable_default_skeleton_files
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Desativados"* ]]
	run cat "$DOCKER_CALLS_LOG"
	[[ "$output" == *"config:system:set skeletondirectory --value="* ]]
}

@test "disable_default_skeleton_files falls back to a manual instruction when Nextcloud isn't up" {
	export DOCKER_STUB_SKELETON_FAIL=1

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE=/dev/null
		disable_default_skeleton_files
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Não consegui desativar"* ]]
	[[ "$output" == *"docker compose exec -u www-data nextcloud php occ config:system:set skeletondirectory"* ]]
}

# --- provision_first_user -------------------------------------------------

@test "provision_first_user lists existing users and offers to add another" {
	export DOCKER_STUB_USER_LIST="  - alice"
	printf 'n\n' >"$STDIN_FILE"

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE=/dev/null
		provision_first_user <'$STDIN_FILE' || true
	"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usuários já cadastrados:"* ]]
	[[ "$output" == *"alice"* ]]
}

@test "provision_first_user uses the first-user prompt when no users exist yet" {
	printf 'n\n' >"$STDIN_FILE"

	run bash -c "
		source '$REPO_ROOT/scripts/setup.sh'
		ENV_FILE=/dev/null
		provision_first_user <'$STDIN_FILE' || true
	"
	[ "$status" -eq 0 ]
	[[ "$output" != *"Usuários já cadastrados:"* ]]
}
