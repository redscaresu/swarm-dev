#!/usr/bin/env bash
# command_names_test.sh — nothing a user reads tells them to type a bare /swarm. In a fresh install
# Claude Code's slash menu completes /swarm to /swarm-dev:epic (it ranks the shorter name first), so
# the name that works is /swarm-dev:swarm. The scan reads the Go source too, which prints messages
# people read. /epic and /plan-epic resolve as typed, /hld writes
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
# The Go files the binary is built from: every *.go under cmd/ and internal/ but tests and testdata/.
# find gets only the directories that exist, since a grep or find over a missing one fails and hiding
# that would hide every other error. cmd/ must give at least one, or the Go scan would pass on nothing.
go_dirs=()
for d in cmd internal; do [[ -d "${d}" ]] && go_dirs+=("${d}"); done
go_files=()
if (( ${#go_dirs[@]} > 0 )); then
  while IFS= read -r f; do go_files+=("${f}"); done < <(find "${go_dirs[@]}" -name testdata -prune -o \
    -type f -name '*.go' ! -name '*_test.go' -print | LC_ALL=C sort)
fi
cmd_go=0
for f in ${go_files[@]+"${go_files[@]}"}; do [[ "${f}" == cmd/* ]] && cmd_go=$((cmd_go + 1)); done
if (( cmd_go == 0 )); then
  echo "FAIL the bare /swarm scan found no Go file under cmd/, so it scanned none"; exit 1
fi
# A /swarm not part of a path (.claude/swarm, bin/swarm.sh) or a longer name (/swarm-dev:swarm).
# grep exits 1 when nothing matches, the pass; 2 is an error, such as a path that is gone.
rc=0
bare="$(grep -rnE '(^|[^A-Za-z0-9_./-])/swarm([^A-Za-z0-9_./:-]|$)' \
  commands skills README.md docs/method.md docs/reference*.md docs/assets bin/swarm.sh bin/lib/*.sh \
  "${go_files[@]}")" || rc=$?
if (( rc > 1 )); then
  echo "FAIL the bare /swarm scan's grep exited ${rc}"; exit 1
fi
if [[ -n "${bare}" ]]; then
  echo "FAIL a bare /swarm, which runs /swarm-dev:epic; write /swarm-dev:swarm:"; echo "${bare}"; exit 1
fi
echo "ok   no bare /swarm (${#go_files[@]} Go files scanned, ${cmd_go} under cmd/)"
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
