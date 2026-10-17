#!/usr/bin/env bash
# command_names_test.sh — nothing a user reads tells them to type a bare /swarm. In a fresh install
# Claude Code's slash menu completes /swarm to /swarm-dev:hld (it ranks the shorter name first), so
# the name that works is /swarm-dev:swarm. /hld, /plan-hld and /plan-epic resolve as typed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO}"
# A /swarm not part of a path (.claude/swarm, bin/swarm.sh) or a longer name (/swarm-dev:swarm).
bare="$(grep -rnE '(^|[^A-Za-z0-9_./-])/swarm([^A-Za-z0-9_./:-]|$)' \
  commands skills README.md docs/method.md docs/reference.md docs/dash.md docs/assets bin/swarm.sh bin/lib/*.sh || true)"
if [[ -n "${bare}" ]]; then
  echo "FAIL a bare /swarm, which runs /swarm-dev:hld; write /swarm-dev:swarm:"; echo "${bare}"; exit 1
fi
echo "ok   no bare /swarm"
echo "all passed"
