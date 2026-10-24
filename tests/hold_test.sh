#!/usr/bin/env bash
# hold_test.sh — `swarm.sh hold <slug> <why>`: a ready story adds one events.tsv hold line with the
# slug and ok (<reason>); a missing or non-ready story, a story whose PR was closed unmerged
# (its last event reconcile's reopen), or no reason fails and logs nothing. The conductor brief
# conduct renders tells it to run hold for each startable story it does not start.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# The claude stub, and a herdr and gh that fail, so conduct writes its brief and stops at herdr.
STUB_BIN="${ROOT}/bin"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp"
cp "${REPO}/tests/claude_stub.sh" "${STUB_BIN}/claude"
for c in herdr gh; do printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/${c}"; chmod +x "${STUB_BIN}/${c}"; done
echo '[]' > "${ROOT}/claude.json"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"

P="${ROOT}/p"; mkdir -p "${P}/.swarm" "${P}/docs/stories" "${P}/docs/epics"; git -C "${P}" init -q; touch "${P}/docs/stories/README.md"
story() { printf -- '---\nkind: code\nstatus: %s\nepic: e\n---\n\n# %s\n' "$2" "$1" > "${P}/docs/stories/$1.md"; }
story r ready; story b blocked; story c ready
printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
EV="${P}/.swarm/events.tsv"
sw() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "$@"); }
lines() { if [[ -f "${EV}" ]]; then wc -l < "${EV}" | tr -d ' '; else echo 0; fi; }

rc=0; sw hold gone 'touches docs/x.md with #432' >/dev/null 2>&1 || rc=$?
check "hold on a missing story fails and logs nothing" "${rc} $(lines)" "1 0"
rc=0; sw hold b 'touches docs/x.md with #432' >/dev/null 2>&1 || rc=$?
check "hold on a blocked story fails and logs nothing" "${rc} $(lines)" "1 0"
rc=0; sw hold r '  ' >/dev/null 2>&1 || rc=$?
check "hold with no reason fails and logs nothing" "${rc} $(lines)" "1 0"
sw hold r 'touches docs/x.md with #432' >/dev/null
check "hold on a ready story adds one events.tsv line: hold, the slug, ok (the reason)" "$(lines) $(cut -f2,3,5 "${EV}")" \
  $'1 hold\tr\tok (touches docs/x.md with #432)'

# c's PR was closed unmerged: reconcile's reopen is its last event, which unblock --startable reads
# to mark it for the lead, so hold refuses it and leaves that event last.
printf '2026-10-24T00:00:00Z\treconcile\tc\t-\tok (reopened)\n' >> "${EV}"
rc=0; sw hold c 'touches docs/x.md with #432' >/dev/null 2>&1 || rc=$?
check "hold on a story whose PR was closed unmerged fails and logs nothing" "${rc} $(lines)" "1 2"

(cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 bash "${REPO}/bin/swarm.sh" conduct e) >/dev/null 2>&1 || true
check "the conductor brief tells it to log each startable story it does not start with hold, but a closed-unmerged one" \
  "$(tr -s '[:space:]' ' ' < "${P}/.swarm/briefs/conduct-e.md" | grep -cF "For each \`startable:\` story you do not start, other than a closed-unmerged one, run \`swarm.sh hold <slug> '<why>'\`")" 1

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
