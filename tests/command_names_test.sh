#!/usr/bin/env bash
# command_names_test.sh — nothing a user reads tells them to type a bare /swarm. In a fresh install
# Claude Code's slash menu completes /swarm to /swarm-dev:epic (it ranks the shorter name first), so
# the name that works is /swarm-dev:swarm. /epic and /plan-epic resolve as typed, /hld writes
# an HLD above them, and /plan-hld plans it into epics. The commands whose agents write prose a person
# agrees (hld, epic, plan-hld, and swarm's release docs) name the humanizer, and the commands whose
# agents get a brief (hld, epic, plan-epic, plan-hld) name the plugin's rules.md.
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
for f in hld epic plan-hld swarm; do
  if ! grep -q 'humanizer' "commands/${f}.md"; then
    echo "FAIL commands/${f}.md does not name the humanizer skill"; exit 1
  fi
done
echo "ok   hld, epic, plan-hld and swarm name the humanizer"
# shellcheck disable=SC2016  # the literal text of the placeholder, not a shell expansion
rules_ref='${CLAUDE_PLUGIN_ROOT}/rules.md'
# hld and epic carry two briefs (co-author, reviewer); plan-epic and plan-hld carry one set of ground rules.
for spec in hld:2 epic:2 plan-epic:1 plan-hld:1; do
  f="${spec%%:*}"; want="${spec##*:}"
  got="$(grep -cF "${rules_ref}" "commands/${f}.md" || true)"
  if (( got < want )); then
    echo "FAIL commands/${f}.md names \${CLAUDE_PLUGIN_ROOT}/rules.md ${got} times, needs ${want}"; exit 1
  fi
done
echo "ok   hld, epic, plan-epic and plan-hld briefs name rules.md"
echo "all passed"
