#!/usr/bin/env bash
# One-line bootstrap: clones Easy Home NAS and launches the guided setup
# wizard (scripts/setup.sh).
#
#   curl -fsSL https://raw.githubusercontent.com/raschmitt/easy-home-nas/main/install.sh | bash
#
# Safe to re-run: if the repo is already cloned in the target directory,
# this just pulls the latest and re-launches the wizard, which is itself
# safe to re-run (see scripts/setup.sh).
set -euo pipefail

REPO_URL="${EASY_HOME_NAS_REPO_URL:-https://github.com/raschmitt/easy-home-nas.git}"
TARGET_DIR="${EASY_HOME_NAS_DIR:-$HOME/easy-home-nas}"

if ! command -v git >/dev/null 2>&1; then
	echo "git não encontrado. Instale com: sudo apt install git" >&2
	exit 1
fi

if [ -d "$TARGET_DIR/.git" ]; then
	echo "Easy Home NAS já clonado em $TARGET_DIR — atualizando..."
	git -C "$TARGET_DIR" pull --ff-only
else
	echo "Clonando Easy Home NAS em $TARGET_DIR..."
	git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

# `curl | bash` hands this script's own stdin to the pipe, so a plain `read`
# in the wizard would read from the (already exhausted) pipe instead of the
# terminal. Explicitly reconnect stdin to the real terminal so the wizard's
# prompts still work — this only works when there IS one (an interactive
# shell), which is the only case that makes sense for an interactive wizard
# anyway.
if (exec 3</dev/tty) 2>/dev/null; then
	exec ./scripts/setup.sh </dev/tty
else
	cat <<EOF

Repositório pronto em: $TARGET_DIR
Não encontrei um terminal interativo pra continuar automaticamente — rode
você mesmo:

  cd $TARGET_DIR && ./scripts/setup.sh
EOF
fi
