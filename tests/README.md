# Tests

Unit and integration tests for `scripts/`, using
[bats-core](https://bats-core.readthedocs.io/). Run them with:

```bash
bats tests/unit/
```

## Scope

- **Unit**: pure logic extracted specifically to be testable without side
  effects — password generation, `.env` read/write, disk-listing filters,
  and the JSON-parsing helpers in `scripts/setup.sh` (check-host.net
  responses, Cloudflare API responses). These take a string in and return a
  string or exit code, no network/disk/docker involved.
- **Integration**: `tests/unit/provision_user.bats` runs the real
  `scripts/provision-user.sh` end to end, with a stubbed `docker` on `PATH`
  that just logs what it was called with — this exercises real argument
  parsing and command construction without needing an actual Nextcloud
  instance.

## What's deliberately NOT covered here

Anything that needs real infrastructure — creating the actual ZFS pool,
running the real Ansible playbook, a real `terraform apply` against
Cloudflare, an actual `docker compose up` — is out of scope for automated
tests the same way it's out of scope for CI elsewhere in this project (see
`KNOWN_ISSUES.md`: disaster-recovery is validated manually against a
scratch VM/disks for the same reason). `scripts/setup.sh`'s wizard
functions that shell out to `ansible-playbook`, `terraform`, and
`docker compose` are intentionally left untested at this level — the pure
logic they depend on (env var handling, JSON parsing, path detection) is
covered instead.

## Adding a test

- Pure logic: extract it into its own function that takes input as an
  argument (not read from a global, stdin, or the network) and returns
  output via stdout/exit code — then it's trivial to test with `run`.
- Something that shells out to an external command: stub that command by
  putting a fake executable earlier on `PATH` (see the `docker` stub in
  `provision_user.bats` for the pattern).
