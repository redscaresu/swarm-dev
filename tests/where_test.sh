#!/usr/bin/env bash
# where_test.sh — swarm.sh where <agent> prints this project's agent's pane, its workspace's label and
# its tab's label. Two projects under one herdr (a stub on PATH, its lists in ${ROOT}/herdr.json) each
# have an agent called s1; herdr lists b's first, so a where that read any project's agent would give
# a's s1 b's labels. An agent herdr lists only in the other project's panes, or not at all, exits 1.
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
printf '#!/bin/sh\nexec python3 "%s/bin/herdr.py" "$@"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat > "${ROOT}/bin/herdr.py" <<'EOF'
import json, os, sys
s = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "herdr.json")))
cmd = " ".join(sys.argv[1:3])
if cmd == "agent list": print(json.dumps({"result": {"agents": s["agents"]}}))
elif cmd == "workspace list": print(json.dumps({"result": {"workspaces": s["workspaces"]}}))
elif cmd == "tab list": print(json.dumps({"result": {"tabs": s["tabs"]}}))
else: sys.exit(1)
EOF
chmod +x "${ROOT}/bin/herdr"
export PATH="${ROOT}/bin:${PATH}"

cat > "${ROOT}/herdr.json" <<'EOF'
{"workspaces": [{"workspace_id": "w1", "label": "a · e1"}, {"workspace_id": "w2", "label": "b · e2"}],
 "tabs": [{"tab_id": "w1:t1", "workspace_id": "w1", "label": "e1"}, {"tab_id": "w2:t1", "workspace_id": "w2", "label": "e2-2"}],
 "agents": [{"name": "s1", "pane_id": "w2:p1", "tab_id": "w2:t1", "workspace_id": "w2"},
            {"name": "s2", "pane_id": "w2:p2", "tab_id": "w2:t1", "workspace_id": "w2"},
            {"name": "s1", "pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1"},
            {"name": "conduct-e1", "pane_id": "w1:p2", "tab_id": "w1:t1", "workspace_id": "w1"}]}
EOF

# project <dir> <tab-record lines> — a swarm project whose tab record names the panes it opened.
project() {
  mkdir -p "$1/.claude/swarm" "$1/docs/stories" "$1/docs/epics" "$1/.swarm/state"
  : > "$1/.claude/swarm/config"
  printf '%s\n' "$2" > "$1/.swarm/state/t1"
}
A="${ROOT}/a"; B="${ROOT}/b"
project "${A}" $'w1:p1 s1\nw1:p2 conduct-e1'
project "${B}" $'w2:p1 s1\nw2:p2 s2'

# where_in <project> <agent> — where's stdout, then its exit code on the last line.
where_in() { (cd "$1" || exit 1; rc=0; bash "${SWARM}" where "$2" 2>&1 || rc=$?; echo "${rc}"); }

check "a's s1: a's pane, workspace and tab" $'s1: pane w1:p1, workspace a · e1, tab e1\n0' "$(where_in "${A}" s1)"
check "b's s1: b's pane, workspace and tab" $'s1: pane w2:p1, workspace b · e2, tab e2-2\n0' "$(where_in "${B}" s1)"
check "a conductor, by conduct-<epic>" $'conduct-e1: pane w1:p2, workspace a · e1, tab e1\n0' "$(where_in "${A}" conduct-e1)"
check "an agent only in the other project's panes exits 1" \
  $'swarm: where: herdr lists no agent called s2 in this project\'s panes\n1' "$(where_in "${A}" s2)"
check "an agent herdr does not list exits 1" \
  $'swarm: where: herdr lists no agent called s9 in this project\'s panes\n1' "$(where_in "${B}" s9)"
check "where logs nothing (read-only)" "no log" "$([[ -s "${A}/.swarm/events.tsv" ]] && echo logged || echo "no log")"

if [[ ${fails} -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
