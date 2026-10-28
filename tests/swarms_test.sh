#!/usr/bin/env bash
# swarms_test.sh — swarm.sh swarms lists each swarm-lead workspace herdr has with only its own
# project's workspaces and agents. herdr is a stub on PATH, its lists in ${ROOT}/herdr.json. Three
# projects: a/app and a/app-2, where one label is a prefix of the other, and b/app, whose dir name is
# a/app's (its label app-<hash>, and one conductor workspace labelled plain app · e4, as project_label
# gives once a/app has none). A workspace counted by a label prefix, by label alone, or by its dir's
# name lands under the wrong lead. Decoys: an app · workspace in a dir no lead runs in, an app-2 ·
# workspace in a/app's dir, and an unlabelled one. a/app's lead runs in a/app/docs. a/app · e1 and
# b/app's app-<hash> · e3 have one pane left, in a folder of a story worktree (<dir>-wt/<slug>/src,
# the second worktree with the project's config, the first without); each counts as its project's
# dir. Two more projects keep their board outside the repo, where their lead runs: d/svc with
# board_dir = ../svc-board (after an older board_dir line, which the last one overrides), and e/web
# with board_dir = ~/web-board. a/app-2's lead-agents workspace has only a pane in another repo's
# worktree, and is its own by the project's lead-agents record. f/foo-wt/c is a main checkout in a
# folder whose name ends in -wt. b/app's label is its real path hash; app-000000 · e11 in b/app is a
# decoy. The lead's own agent has no name. A stalled list read is cut at SWARM_REPORT_SECONDS.
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
import json, os, sys, time
H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = json.load(open(os.path.join(H, "herdr.json")))
cmd = " ".join(sys.argv[1:3])
with open(os.path.join(H, "herdr.log"), "a") as log: log.write(cmd + "\n")
# A file ${ROOT}/fail-<list> (fail-pane) makes that list fail; slow-<list> makes it stall.
if os.path.exists(os.path.join(H, "fail-" + sys.argv[1])): sys.exit(1)
if os.path.exists(os.path.join(H, "slow-" + sys.argv[1])): time.sleep(20)
if cmd == "agent list": print(json.dumps({"result": {"agents": s["agents"]}}))
elif cmd == "workspace list": print(json.dumps({"result": {"workspaces": s["workspaces"]}}))
elif cmd == "pane list": print(json.dumps({"result": {"panes": s["panes"]}}))
else: sys.exit(1)
EOF
chmod +x "${ROOT}/bin/herdr"
export PATH="${ROOT}/bin:${PATH}"

A="${ROOT}/a/app"; A2="${ROOT}/a/app-2"; B="${ROOT}/b/app"; C="${ROOT}/c/app"
for d in "${A}" "${A2}" "${B}"; do
  mkdir -p "${d}/.claude/swarm" "${d}/docs/stories" "${d}/docs/epics" "${d}-wt"
  : > "${d}/.claude/swarm/config"
done
mkdir -p "${C}" "${ROOT}/d/svc/.claude/swarm" "${ROOT}/d/svc-board/epics"
printf 'board_dir = docs\nboard_dir = ../svc-board   # outside the repo\n' > "${ROOT}/d/svc/.claude/swarm/config"
mkdir -p "${A2}/.swarm/lead" "${ROOT}/f/foo-wt/c/.claude/swarm"
printf 'w12\tapp-2 · lead-agents\n' > "${A2}/.swarm/lead/agents-workspace"
: > "${ROOT}/f/foo-wt/c/.claude/swarm/config"
# b/app's path hash, as path_hash in bin/lib/build.sh makes it.
crc="$(printf '%s' "${B}" | cksum)"; HB="$(printf '%06x' $((${crc%% *} % 16777216)))"
mkdir -p "${ROOT}/e/web/.claude/swarm" "${ROOT}/home/web-board" "${B}-wt/s3/.claude/swarm" "${A}-wt/s1/src" "${B}-wt/s3/src"
printf 'board_dir = ~/web-board\n' > "${ROOT}/e/web/.claude/swarm/config"
: > "${B}-wt/s3/.claude/swarm/config"
export HOME="${ROOT}/home"

# <workspace> <label> <pane cwd>... ; then the agents, <pane> <name> <status>.
ROOT="${ROOT}" HB="${HB}" python3 -I - > "${ROOT}/herdr.json" <<'EOF'
import json, os
r, hb = os.environ["ROOT"], os.environ["HB"]
ws = [("w8", "app-2 · e8", [r + "/a/app"]),
      ("w6", "app · e6", [r + "/c/app"]),
      ("w2", "app-2 · e2", [r + "/a/app-2", r + "/a/app-2-wt/s2"]),
      ("w3", "app-%s · e3" % hb, [r + "/b/app-wt/s3/src"]),
      ("w4", "app · e4", [r + "/b/app"]),
      ("w1", "app · e1", [r + "/a/app-wt/s1/src"]),
      ("L1", "swarm-lead · app", [r + "/a/app/docs"]),
      ("L2", "swarm-lead · app-2", [r + "/a/app-2"]),
      ("L3", "swarm-lead · app-%s" % hb, [r + "/b/app"]),
      ("w5", "app · lead-agents", [r + "/a/app"]),
      ("w7", "notes", [r + "/a/app"]),
      ("L4", "swarm-lead · svc", [r + "/d/svc-board"]),
      ("w9", "svc · e9", [r + "/d/svc"]),
      ("L5", "swarm-lead · web", [r + "/home/web-board"]),
      ("w10", "web · e10", [r + "/e/web"]),
      ("w11", "app-000000 · e11", [r + "/b/app"]),
      ("w12", "app-2 · lead-agents", [r + "/x/other-wt/s9"]),
      ("L6", "swarm-lead · c", [r + "/f/foo-wt/c"]),
      ("w13", "c · e13", [r + "/f/foo-wt/c"])]
agents = [("L1:p1", "", "working"), ("w1:p1", "conduct-e1", "working"), ("w1:p2", "s1", "idle"),
          ("w2:p1", "conduct-e2", "working"), ("w2:p2", "s2", "idle"),
          ("w3:p1", "conduct-e3", "working"), ("w3:p2", "s3", "blocked"),
          ("w4:p1", "conduct-e4", "idle"), ("w6:p1", "x6", "idle"), ("w8:p1", "x8", "idle"), ("w9:p1", "conduct-e9", "working"), ("w10:p1", "conduct-e10", "idle"),
          ("w11:p1", "x11", "idle"), ("w12:p1", "planner", "idle"), ("w13:p1", "conduct-e13", "idle")]
print(json.dumps({
    "panes": [{"pane_id": "%s:p%d" % (i, n + 1), "workspace_id": i, "cwd": c} for i, _, cs in ws for n, c in enumerate(cs)],
    "agents": [{"name": n, "pane_id": p, "workspace_id": p.split(":")[0], "agent_status": st} for p, n, st in agents]
              + [{"agent_status": "idle"}],
    "workspaces": [{"workspace_id": i, "label": l} for i, l, _ in ws] + [{"label": "app · no-id"}]}))
EOF

# swarms_in <dir> [arg...] — swarms' output, stderr too, then its exit code on the last line.
swarms_in() { (cd "$1" || exit 1; shift; rc=0; bash "${SWARM}" swarms "$@" 2>&1 || rc=$?; echo "${rc}"); }

want="app  ${A}
  swarm-lead · app: L1:p1 (no name)
  app · e1: conduct-e1, s1
  app · lead-agents: no agents
app-2  ${A2}
  swarm-lead · app-2: no agents
  app-2 · e2: conduct-e2, s2
  app-2 · lead-agents: planner
app-${HB}  ${B}
  swarm-lead · app-${HB}: no agents
  app-${HB} · e3: conduct-e3, s3
  app · e4: conduct-e4
svc  ${ROOT}/d/svc-board
  swarm-lead · svc: no agents
  svc · e9: conduct-e9
web  ${ROOT}/home/web-board
  swarm-lead · web: no agents
  web · e10: conduct-e10
c  ${ROOT}/f/foo-wt/c
  swarm-lead · c: no agents
  c · e13: conduct-e13
0"
: > "${ROOT}/herdr.log"
check "each lead lists only its own project's workspaces and agents" "${want}" "$(swarms_in "${A}")"
check "swarms reads each herdr list once" $'workspace list\npane list\nagent list' "$(cat "${ROOT}/herdr.log")"
check "the same from another project" "${want}" "$(swarms_in "${B}")"
check "swarms logs nothing (read-only)" "no log" "$([[ -s "${A}/.swarm/events.tsv" ]] && echo logged || echo "no log")"
check "swarms takes no arguments" $'swarm: swarms: takes no arguments (swarm.sh swarms)\n1' "$(swarms_in "${A}" x)"

touch "${ROOT}/fail-pane"
check "a pane list herdr cannot give exits 1" $'swarm: swarms: herdr gave no pane list\n1' "$(swarms_in "${A}")"
rm "${ROOT}/fail-pane"; touch "${ROOT}/slow-pane"
# 5 s, not 1: on a loaded machine the reads that answer at once can take over a second to start.
check "a pane list herdr stalls on is cut, and exits 1" $'swarm: swarms: herdr\'s pane list was cut after 5 s\n1' "$(SWARM_REPORT_SECONDS=5 swarms_in "${A}")"
rm "${ROOT}/slow-pane"

python3 -I -c 'import json, sys; s = json.load(open(sys.argv[1])); s["workspaces"] = [w for w in s["workspaces"] if not w["label"].startswith("swarm-lead")]; json.dump(s, open(sys.argv[1], "w"))' "${ROOT}/herdr.json"
check "no swarm-lead workspace says so" $'no swarm runs here: herdr has no swarm-lead · <project> workspace\n0' "$(swarms_in "${A}")"

[[ ${fails} -eq 0 ]] || exit 1
echo "all passed"
