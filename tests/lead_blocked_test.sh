#!/usr/bin/env bash
# lead_blocked_test.sh — a story blocked on work no agent builds says so: `next`'s also: lead line
# and `status`'s blocked line. If someone drops the by-hand case from blocking_leads, or
# lead_blocked from blocked_why, this goes red.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0
STUB_BIN="$(mktemp -d)"; trap 'rm -rf "${STUB_BIN}"' EXIT
export CLAUDE_CONFIG_DIR="${STUB_BIN}/claude-config"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"

# item <path> <front-matter line>... — write a board file under docs/.
item() {
  local path="docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# board <setup...> — a board in dir, with a conductor for e1 running (a herdr stub lists it).
board() {
  local agent
  dir="$(mktemp -d)"
  (cd "${dir}" && git init -q && mkdir -p docs/stories docs/epics bin .swarm/briefs .swarm/state && touch .swarm/briefs/conduct-e1.md
   echo "# Stories" > docs/stories/README.md)
  agent="$(cd "${dir}" && bash "${SWARM}" _name conduct-e1)"
  echo "w:7 ${agent}" > "${dir}/.swarm/state/tab"
  printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"${agent}\",\"agent_status\":\"idle\",\"pane_id\":\"w:7\"}]}}'" > "${dir}/bin/herdr"
  chmod +x "${dir}/bin/herdr"
  for step in "$@"; do (cd "${dir}" && eval "${step}"); done
}
nxt() { (cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next 2>&1); }
sts() { (cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status --all 2>&1); }
also() { grep '^also:' <<< "$1" || true; }
blocked() { grep '^  blocked:' <<< "$1" || true; }

# A parent blocked with no depends_on: next names it, status says no agent builds it.
board "item stories/hand.md 'status: blocked' 'kind: lead'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [hand]'"
check "next: a story blocked on a by-hand blocked parent gets an also: lead line" \
  "also: lead hand blocks child" "$(also "$(nxt)")"
check "status: the child of a by-hand blocked parent is blocked by one no agent builds" \
  "  blocked: child (by hand, which no agent builds)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

# A ready kind: lead parent: next prints as before, status gains the suffix.
board "item stories/lead.md 'status: ready' 'kind: lead'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [lead]'"
check "next: a ready kind: lead parent still gets its also: lead line" \
  "also: lead lead blocks child" "$(also "$(nxt)")"
check "status: the child of a kind: lead parent is blocked by one no agent builds" \
  "  blocked: child (by lead, which no agent builds)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

# A by-hand blocked parent of a kind an agent builds: finish would close it unbuilt, so no also: line.
# Only the lead readies it all the same, so status says no agent builds it.
board "item stories/hand.md 'status: blocked' 'kind: code'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [hand]'"
check "next: a by-hand blocked kind: code parent gets no also: line" "" "$(also "$(nxt)")"
check "status: the child of a by-hand blocked kind: code parent is blocked by one no agent builds" \
  "  blocked: child (by hand, which no agent builds)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

# A by-hand blocked parent in a later or draft epic is the user's: no also: line.
for st in later draft; do
  board "item epics/ep.md 'status: ${st}'" "item stories/hand.md 'status: blocked' 'kind: lead' 'epic: ep'" \
    "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [hand]'"
  check "next: a by-hand blocked parent in a ${st} epic gets no also: line" "" "$(also "$(nxt)")"
  rm -rf "${dir}"
done

# A hand-step dependency is cleared by a person: no agent builds it.
board "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [operator:x]'"
check "status: a child blocked on a hand step is blocked by one no agent builds" \
  "  blocked: child (by operator:x, which no agent builds)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"
board "item stories/lead.md 'status: ready' 'kind: lead'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [operator:x, lead]'"
check "status: a child blocked on a hand step and a lead story is blocked by ones no agent builds" \
  "  blocked: child (by operator:x lead, which no agent builds)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"
board "item stories/agent.md 'status: ready' 'kind: code' 'epic: e1'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [operator:x, agent]'"
check "status: a child blocked on a hand step and an agent's story reads as today" \
  "  blocked: child (by operator:x agent)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

# An open epic that shares its slug with a finished lead story is what the child waits on: a conductor builds it.
board "item epics/x.md 'status: active'" "item stories/x.md 'status: done' 'kind: lead'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [x]'"
check "status: a child blocked on an open epic is not blocked by one no agent builds, whatever a done story of its slug says" \
  "  blocked: child (by x)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

# A by-hand blocked parent with after: waits for its epic, so next does not send the lead to it yet.
board "item stories/hand.md 'status: blocked' 'kind: lead' 'epic: e1' 'after: e1'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [hand]'"
check "next: a by-hand blocked parent with after: gets no also: line" "" "$(also "$(nxt)")"
rm -rf "${dir}"

# A parent an agent builds: no also: line, and the blocked line is as before.
board "item stories/agent.md 'status: ready' 'kind: code' 'epic: e1'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [agent]'"
check "next: a parent an agent builds gets no also: line" "" "$(also "$(nxt)")"
check "status: the child of a parent an agent builds reads as today" \
  "  blocked: child (by agent)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

# One open parent an agent builds beside a lead one: the agent's parent keeps it as today.
board "item stories/lead.md 'status: ready' 'kind: lead'" "item stories/agent.md 'status: ready' 'kind: code' 'epic: e1'" \
  "item stories/child.md 'status: blocked' 'kind: code' 'depends_on: [lead, agent]'"
check "status: a child with a parent an agent builds and a lead parent reads as today" \
  "  blocked: child (by lead agent)" "$(blocked "$(sts)" | grep child)"
rm -rf "${dir}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
