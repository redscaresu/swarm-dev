#!/usr/bin/env bash
# command_names_test.sh — nothing a user reads tells them to type a bare /swarm. In a fresh install
# Claude Code's slash menu completes /swarm to /swarm-dev:epic (it ranks the shorter name first), so
# the name that works is /swarm-dev:swarm. /epic and /plan-epic resolve as typed, /hld writes
# an HLD above them, and /plan-hld plans it into epics.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO}"
# A /swarm not part of a path (.claude/swarm, bin/swarm.sh) or a longer name (/swarm-dev:swarm).
bare="$(grep -rnE '(^|[^A-Za-z0-9_./-])/swarm([^A-Za-z0-9_./:-]|$)' \
  commands skills README.md docs/method.md docs/reference.md docs/dash.md docs/assets bin/swarm.sh bin/lib/*.sh || true)"
if [[ -n "${bare}" ]]; then
  echo "FAIL a bare /swarm, which runs /swarm-dev:epic; write /swarm-dev:swarm:"; echo "${bare}"; exit 1
fi
echo "ok   no bare /swarm"
if [[ ! -f commands/epic.md || ! -f commands/hld.md || ! -f commands/plan-hld.md ]]; then
  echo "FAIL commands/epic.md, commands/hld.md and commands/plan-hld.md must all exist"; exit 1
fi
echo "ok   /epic, /hld and /plan-hld are commands"
echo "all passed"
