#!/usr/bin/env bash
# agent_labels_test.sh — status and dash end each agent's row with its pane, its workspace's label and
# its tab's. Two projects under one herdr (a stub on PATH, its lists in ${ROOT}/herdr.json) each have
# an agent called s1; herdr lists b's first, so a report that took any project's s1 would give a's s1
# b's labels. a's s3 has no tab or workspace in herdr's agent list, only in its pane list, which comes
# first. Each report reads herdr's workspace and tab lists once.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

mkdir -p "${ROOT}/bin"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"
printf '#!/bin/sh\nexec python3 "%s/bin/herdr.py" "$@"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat > "${ROOT}/bin/herdr.py" <<'EOF'
import json, os, sys
H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = json.load(open(os.path.join(H, "herdr.json")))
cmd = " ".join(sys.argv[1:3])
with open(os.path.join(H, "herdr.log"), "a") as log: log.write(cmd + "\n")
if cmd == "agent list": print(json.dumps({"result": {"agents": s["agents"]}}))
elif cmd == "pane list": print(json.dumps({"result": {"panes": s["panes"]}}))
elif cmd == "workspace list": print(json.dumps({"result": {"workspaces": s["workspaces"]}}))
elif cmd == "tab list": print(json.dumps({"result": {"tabs": s["tabs"]}}))
elif cmd == "agent read": print("")
else: sys.exit(1)
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude" "${ROOT}/bin/gh"
export PATH="${ROOT}/bin:${PATH}"

cat > "${ROOT}/herdr.json" <<'EOF'
{"workspaces": [{"workspace_id": "w1", "label": "a · e1"}, {"workspace_id": "w2", "label": "b · e2"}],
 "tabs": [{"tab_id": "w1:t1", "workspace_id": "w1", "label": "e1"}, {"tab_id": "w1:t2", "workspace_id": "w1", "label": "e1-2"},
          {"tab_id": "w2:t1", "workspace_id": "w2", "label": "e2-2"}],
 "agents": [{"name": "s1", "agent_status": "working", "pane_id": "w2:p1", "tab_id": "w2:t1", "workspace_id": "w2"},
            {"name": "s1", "agent_status": "working", "pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1"},
            {"name": "s3", "agent_status": "working", "pane_id": "w1:p3"}],
 "panes": [{"pane_id": "w2:p1", "tab_id": "w2:t1", "workspace_id": "w2"}, {"pane_id": "w1:p1"},
           {"pane_id": "w1:p3", "tab_id": "w1:t2", "workspace_id": "w1"}]}
EOF

# project <dir> <tab-record lines> — a swarm project whose tab record names the panes it opened.
project() {
  mkdir -p "$1/.claude/swarm" "$1/docs/stories" "$1/docs/epics" "$1/.swarm/state"
  : > "$1/.claude/swarm/config"; : > "$1/docs/stories/README.md"
  printf '%s\n' "$2" > "$1/.swarm/state/t1"
}
A="${ROOT}/a"; B="${ROOT}/b"
project "${A}" $'w1:p1 s1\nw1:p3 s3'
project "${B}" $'w2:p1 s1'

# report <project> <command>... — its output from <project>, herdr's log emptied first.
report() { : > "${ROOT}/herdr.log"; (cd "$1" || exit 1; shift; HERDR_ENV=1 DASH_W=200 bash "${SWARM}" "$@" 2>&1) || true; }
# row <agent> <output> — <agent>'s row: status's from two spaces in, dash's from its symbol on.
row() { sed -n "s/^  $1  .*\\[\\(.*\\)\\]\$/\\1/p; s/^│   [^ ] $1  .*  \\(w[0-9]:p[0-9] in .*›[^│]*[^ │]\\) *│.*/\\1/p" <<< "$2"; }
lists() { grep -c "^$1 list\$" "${ROOT}/herdr.log" || true; }

out="$(report "${A}" status --all)"
check "status: a's s1 names a's pane, workspace and tab" "pane w1:p1, workspace a · e1, tab e1" "$(row s1 "${out}")"
check "status: a's s3 takes its tab and workspace from herdr's pane list" "pane w1:p3, workspace a · e1, tab e1-2" "$(row s3 "${out}")"
check "status reads herdr's workspace list once" 1 "$(lists workspace)"
check "status reads herdr's tab list once" 1 "$(lists tab)"
out="$(report "${B}" status --all)"
check "status: b's s1 names b's pane, workspace and tab" "pane w2:p1, workspace b · e2, tab e2-2" "$(row s1 "${out}")"

out="$(report "${A}" dash)"
check "dash: a's s1 names a's pane, workspace and tab" "w1:p1 in a · e1 › e1" "$(row s1 "${out}")"
check "dash: a's s3 takes its tab and workspace from herdr's pane list" "w1:p3 in a · e1 › e1-2" "$(row s3 "${out}")"
check "dash reads herdr's workspace list once" 1 "$(lists workspace)"
check "dash reads herdr's tab list once" 1 "$(lists tab)"
out="$(report "${B}" dash)"
check "dash: b's s1 names b's pane, workspace and tab" "w2:p1 in b · e2 › e2-2" "$(row s1 "${out}")"

if [[ ${fails} -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
