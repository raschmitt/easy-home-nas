#!/usr/bin/env bats
# Integration-style tests for install.sh's clone/pull logic and its
# no-real-tty fallback. Real network access to GitHub is out of scope —
# TANDEM_NAS_REPO_URL points at a throwaway local git repo instead.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

	FAKE_REPO="$(mktemp -d)"
	git -C "$FAKE_REPO" init -q -b main
	git -C "$FAKE_REPO" config user.email "test@example.com"
	git -C "$FAKE_REPO" config user.name "Test"
	echo "v1" >"$FAKE_REPO/marker.txt"
	git -C "$FAKE_REPO" add marker.txt
	git -C "$FAKE_REPO" commit -q -m "initial"
	# A real repo needs scripts/setup.sh to exist for the exec path, even
	# though these tests exercise the clone/pull/fallback logic, not the
	# wizard itself (which the no-tty branch never actually execs).
	mkdir -p "$FAKE_REPO/scripts"
	printf '#!/usr/bin/env bash\necho "wizard ran"\n' >"$FAKE_REPO/scripts/setup.sh"
	chmod +x "$FAKE_REPO/scripts/setup.sh"
	git -C "$FAKE_REPO" add scripts/setup.sh
	git -C "$FAKE_REPO" commit -q -m "add setup.sh"

	TARGET_DIR="$(mktemp -d)"
	rmdir "$TARGET_DIR" # install.sh must create it itself via git clone

	export TANDEM_NAS_REPO_URL="$FAKE_REPO"
	export TANDEM_NAS_DIR="$TARGET_DIR"
}

teardown() {
	rm -rf "$FAKE_REPO" "$TARGET_DIR"
}

@test "clones into TARGET_DIR when it doesn't exist yet" {
	run bash "$REPO_ROOT/install.sh" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"Clonando"* ]]
	[ -d "$TARGET_DIR/.git" ]
	[ -f "$TARGET_DIR/marker.txt" ]
}

@test "pulls instead of re-cloning when TARGET_DIR already has a checkout" {
	git clone -q "$FAKE_REPO" "$TARGET_DIR"

	# Simulate an upstream update.
	echo "v2" >"$FAKE_REPO/marker.txt"
	git -C "$FAKE_REPO" add marker.txt
	git -C "$FAKE_REPO" commit -q -m "update"

	run bash "$REPO_ROOT/install.sh" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"já clonado"* ]]
	[[ "$output" != *"Clonando"* ]]
	[ "$(cat "$TARGET_DIR/marker.txt")" = "v2" ]
}

@test "falls back to printed instructions when there is no real controlling terminal" {
	# bats itself runs without a controlling tty attached to this process,
	# so a plain run (stdin from /dev/null, no `script`/pty wrapper) already
	# exercises the fallback branch — this is the same situation `curl |
	# bash` puts the script in in a non-interactive context (e.g. CI).
	run bash "$REPO_ROOT/install.sh" </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"Não encontrei um terminal interativo"* ]]
	[[ "$output" == *"cd $TARGET_DIR && ./scripts/setup.sh"* ]]
	[[ "$output" != *"wizard ran"* ]]
}

@test "fails clearly when git is not available" {
	local empty_path_dir bash_bin
	empty_path_dir="$(mktemp -d)"
	# Resolve bash's own absolute path first — PATH is about to be emptied
	# for the script-under-test's environment, and `run` needs to still be
	# able to find the bash binary itself to execute install.sh with.
	bash_bin="$(command -v bash)"
	PATH="$empty_path_dir" run "$bash_bin" "$REPO_ROOT/install.sh" </dev/null
	rmdir "$empty_path_dir"
	[ "$status" -eq 1 ]
	[[ "$output" == *"git não encontrado"* ]]
}
