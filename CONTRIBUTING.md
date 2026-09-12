# Contributing to Tandem NAS

Thanks for considering it. This document is meant to be actionable — if a
step here is vague, that's a bug in this file, please open an issue about it.

## Proposing a change

1. Fork the repository.
2. Create a branch off `main` named `<type>/<short-description>`, e.g.
   `fix/udev-rule-race`, `feat/samba-export`, `docs/adding-users-clarify`.
3. Make your change, with tests/lint passing locally (see below).
4. Open a pull request against `main`. Describe *why*, not just *what* — the
   what is visible in the diff.

## Commit convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <description>

[optional body]
[optional footer]
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.
Example:

```
fix(zfs-mirror): refuse to create pool over disks with existing signatures

blkid was only checked when the pool didn't already exist, but the loop
variable shadowed the outer disk list, so the safety check silently no-op'd
on the second disk. Added a regression note in KNOWN_ISSUES.md until a test
harness for the Ansible roles exists.
```

## Running CI checks locally before opening a PR

All of these are exactly what `.github/workflows/ci.yml` runs — matching
locally avoids a red CI run after you've already opened the PR.

```bash
# Docker Compose syntax
docker compose config -q

# Ansible lint
pipx install ansible-lint   # or: pip install ansible-lint
ansible-lint ansible/

# Shellcheck on every script
shellcheck scripts/*.sh scripts/lib/*.sh

# Secret scanning
gitleaks detect --source . --no-git -v   # or --source . to also scan history
```

If you don't want to install these tools locally, open a draft PR — CI runs
the same checks and you'll see the same output.

## Review process

Every PR is expected to go through the same three-role discipline this
project's initial build used:

1. **Feasibility** — does the change fit the project's constraints (no
   hardcoded paths/hosts, no secrets committed, modular Ansible/Compose)?
   Raised as a PR comment before deep implementation review, if it's not
   obvious from the diff alone.
2. **Implementation review** — concrete issues only: bugs, security gaps,
   deviation from what the PR description claims, missing docs for
   user-facing behavior. Not style nits (let the linters handle style).
3. **Resolution, recorded in the PR thread** — every point raised ends in one
   of two states, stated explicitly in the thread:
   - **Fixed now**: reviewer confirms the fix addresses the point before
     approving.
   - **Deferred**: opened as its own issue with the reasoning for accepting
     the current state, linked from the PR description. Never left
     implicit — "I'll leave that for later" without a linked issue means the
     PR isn't done.

## Reporting bugs / requesting features

Use the issue templates under `.github/ISSUE_TEMPLATE/` — they ask for the
minimum information needed to act on the report (for bugs: your hardware
layout, `.env` values that matter with secrets redacted, and the actual
command + output).

## Code of conduct

Participation in this project is governed by
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
