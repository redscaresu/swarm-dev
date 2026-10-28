#!/usr/bin/env bash
# workspace_labels_test.sh — each conductor's herdr workspace is labelled `<project> · <epic>` (or
# `<project> · backlog`), so three projects under one herdr never share one: two with one dir name
# (a/app and b/app) get distinct labels, the second's with its path hash. A workspace under the bare
# label an older swarm.sh gave is reused only when its cwd (its first pane's) is the project's. close
# and tidy still find a conductor's tab in its relabelled workspace. herdr, gh and claude are stubs on
# PATH; herdr's state (${ROOT}/herdr.json) is shared by every project. The lead's first command in
# a workspace labels it and its tab `swarm-lead · <project>`, once; an agent's, a nested swarm.sh's
# and a test hook's label nothing, and one in a conductor's or another project's lead's workspace
# keeps its label. Agents the lead starts open in `<project> · lead-agents`, kept the project's by a
# pane at its directory and by a record of the workspace's id and label.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# A Unix socket path has a short limit (104 bytes on macOS), so herdr's stand-in socket gets a short dir.
sock_dir="$(mktemp -d /tmp/swarm-lw.XXXXXX)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}" "${sock_dir}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
SEP=" · "
TAB=$'\t'

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: workspaces, tabs, panes and agents in ${ROOT}/herdr.json. A workspace w<n> is made with a
# placeholder tab w<n>:t0 whose pane has its --cwd; each tab or pane is <workspace>:t<n> or :p<n>.
# A file ${ROOT}/refuse makes every rename fail, ${ROOT}/refuse-tab every tab create, ${ROOT}/refuse-anchor
# the create of a tab labelled lead-agents, and ${ROOT}/hang makes workspace list sleep 60 s before
# answering. A file lock (herdr.lock) serialises the stub's reads and writes, for starts run at once.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nexec python3 "%s/bin/herdr.py" "$@"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat > "${ROOT}/bin/herdr.py" <<'EOF'
import fcntl, json, os, sys, time
H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = os.path.join(H, "herdr.json")
_lock = open(os.path.join(H, "herdr.lock"), "w"); fcntl.flock(_lock, fcntl.LOCK_EX)
s = json.load(open(F)) if os.path.exists(F) else {"n": 0, "workspaces": [], "tabs": [], "panes": [], "agents": []}
a = sys.argv[1:]
with open(os.path.join(H, "herdr.log"), "a") as log:
    log.write("|".join(a) + "\n")
def opt(k): return a[a.index(k) + 1] if k in a else ""
def new(): s["n"] += 1; return s["n"]
def pane(ws, tab, cwd):
    p = "%s:p%d" % (ws, new()); s["panes"].append({"pane_id": p, "tab_id": tab, "workspace_id": ws, "cwd": cwd}); return p
def out(r): print(json.dumps({"result": r}))
cmd = " ".join(a[:2])
if a[:1] == ["--version"]: print("herdr 0.9.5")
elif cmd == "workspace list":
    if os.path.exists(os.path.join(H, "hang")): time.sleep(60)
    out({"workspaces": s["workspaces"]})
elif cmd == "workspace create":
    ws = "w%d" % new(); tab = ws + ":t0"
    s["workspaces"].append({"workspace_id": ws, "label": opt("--label")})
    s["tabs"].append({"tab_id": tab, "label": "1", "workspace_id": ws}); pane(ws, tab, opt("--cwd"))
    out({"workspace": {"workspace_id": ws}, "tab": {"tab_id": tab}})
elif cmd == "tab create":
    if os.path.exists(os.path.join(H, "refuse-tab")) or (os.path.exists(os.path.join(H, "refuse-anchor")) and opt("--label") == "lead-agents"):
        sys.stderr.write("error: tab create refused\n"); sys.exit(1)
    ws = opt("--workspace"); tab = "%s:t%d" % (ws, new())
    s["tabs"].append({"tab_id": tab, "label": opt("--label"), "workspace_id": ws})
    out({"root_pane": {"pane_id": pane(ws, tab, opt("--cwd"))}})
elif cmd == "tab list": out({"tabs": [t for t in s["tabs"] if t["workspace_id"] == opt("--workspace")]})
elif cmd == "pane list": out({"panes": s["panes"]})
elif cmd == "pane split":
    p = next(p for p in s["panes"] if p["pane_id"] == a[2]); out({"pane": {"pane_id": pane(p["workspace_id"], p["tab_id"], opt("--cwd"))}})
elif cmd in ("tab close", "pane close"):
    gone = {p["pane_id"] for p in s["panes"] if a[2] in (p["pane_id"], p["tab_id"])}
    s["tabs"] = [t for t in s["tabs"] if t["tab_id"] != a[2]]
    s["panes"] = [p for p in s["panes"] if p["pane_id"] not in gone]
    s["agents"] = [g for g in s["agents"] if g["pane_id"] not in gone]
elif cmd == "agent start":
    p = opt("--pane"); cwd = next(x["cwd"] for x in s["panes"] if x["pane_id"] == p)
    s["agents"].append({"name": a[2], "pane_id": p, "cwd": cwd, "agent_status": "idle"})
elif cmd == "agent rename":
    for g in s["agents"]:
        if a[2] in (g["pane_id"], g["name"]): g["name"] = a[3]
elif cmd in ("workspace rename", "tab rename"):
    if os.path.exists(os.path.join(H, "hang-rename")): time.sleep(60)
    if os.path.exists(os.path.join(H, "refuse")) or (a[0] == "tab" and os.path.exists(os.path.join(H, "refuse-tab"))):
        sys.stderr.write("error: rename refused\n"); sys.exit(1)
    k = "workspaces" if a[0] == "workspace" else "tabs"
    for x in s[k]:
        if x[a[0] + "_id"] == a[2]: x["label"] = " ".join(a[3:])
elif cmd == "agent list": out({"agents": s["agents"]})
elif cmd == "agent prompt": out({"agent": {"agent_status": "working"}})
elif cmd == "agent wait": out({"agent": {"agent_status": "idle"}})
json.dump(s, open(F, "w"))
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"
# herdr_q <python expression over s> — a read of the stub's state.
herdr_q() { python3 -c "import json, sys; s = json.load(open(sys.argv[1])); print($1)" "${ROOT}/herdr.json"; }
# seed <label> <cwd>... — a workspace left from earlier, with a pane in each <cwd>, in that order.
seed() {
  python3 - "${ROOT}/herdr.json" "$@" <<'EOF'
import json, os, sys
f, label, cwds = sys.argv[1], sys.argv[2], sys.argv[3:]
s = json.load(open(f)) if os.path.exists(f) else {"n": 0, "workspaces": [], "tabs": [], "panes": [], "agents": []}
s["n"] += 1; ws = "w%d" % s["n"]
s["workspaces"].append({"workspace_id": ws, "label": label})
s["tabs"].append({"tab_id": ws + ":t0", "label": "old", "workspace_id": ws})
for i, cwd in enumerate(cwds):
    s["panes"].append({"pane_id": "%s:p0%d" % (ws, i), "tab_id": ws + ":t0", "workspace_id": ws, "cwd": cwd})
json.dump(s, open(f, "w"))
EOF
}

A="${ROOT}/a/app"; B="${ROOT}/b/app"; C="${ROOT}/c/web"; E="${ROOT}/e/cart"
for p in "${A}" "${B}" "${C}" "${E}"; do
  mkdir -p "${p}/.claude/swarm" "${p}/docs/stories" "${p}/docs/epics"; : > "${p}/.claude/swarm/config"
  git -C "${p}" init -q
  : > "${p}/docs/stories/README.md"
  for e in x y keep old r z x2; do printf -- '---\nstatus: active\n---\n\n# %s\n' "${e}" > "${p}/docs/epics/${e}.md"; done
done
run() { local p="$1"; shift; (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# conduct <project> <epic>|--backlog — start its conductor, then mark it finished (herdr renames it
# <name>-done and keeps its pane), so another project may take the same name. Prints the label of
# the workspace the conductor's pane is in, then its workspace id.
conduct() {
  local name out
  out="$(run "$1" conduct "$2")" || { echo "conduct $2 in $1 failed: ${out}"; return; }
  name="$(herdr_q "s['agents'][-1]['name']")"   # the agent just started
  herdr_q "next('%s|%s' % (w['label'], w['workspace_id']) for g in s['agents'] if g['name'] == '${name}' for p in s['panes'] if p['pane_id'] == g['pane_id'] for w in s['workspaces'] if w['workspace_id'] == p['workspace_id'])"
  "${ROOT}/bin/herdr" agent rename "${name}" "${name}-done" >/dev/null
}
hash_of() { local n; n="$(run "$1" _conductor backlog)"; echo "${n##*-}"; }
creates() { grep -c '^workspace|create|' "${ROOT}/herdr.log" || true; }

# --- Two projects, one epic slug, and each one's backlog.
a_x="$(conduct "${A}" x)"; c_x="$(conduct "${C}" x)"
check "each project's conductor for epic x lands in its own workspace, <project> · x" "app${SEP}x|web${SEP}x|yes" \
  "${a_x%|*}|${c_x%|*}|$([[ "${a_x#*|}" != "${c_x#*|}" ]] && echo yes || echo no)"
a_b="$(conduct "${A}" --backlog)"; c_b="$(conduct "${C}" --backlog)"
check "each project's backlog conductor lands in its own workspace, <project> · backlog" "app${SEP}backlog|web${SEP}backlog|yes" \
  "${a_b%|*}|${c_b%|*}|$([[ "${a_b#*|}" != "${c_b#*|}" ]] && echo yes || echo no)"

# --- Two dirs of one name: b/app sees app · x in a/app, so its label carries its path hash.
b_x="$(conduct "${B}" x)"
check "b/app, beside a/app, gets app-<its path hash> · x, a workspace of its own" "app-$(hash_of "${B}")${SEP}x|yes" \
  "${b_x%|*}|$([[ "${b_x#*|}" != "${a_x#*|}" ]] && echo yes || echo no)"
a_y="$(conduct "${A}" y)"
check "a/app keeps its plain label beside b/app's hashed one" "app${SEP}y" "${a_y%|*}"

# --- An older swarm.sh's bare label: reused only where the workspace's cwd is the project's.
seed keep "${A}"; seed old "${C}"
keep_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'keep')")"
old_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'old')")"
n="$(creates)"; a_keep="$(conduct "${A}" keep)"
check "a bare-label workspace whose cwd is the project is reused, and none is made" "keep|${keep_ws}|${n}" \
  "${a_keep%|*}|${a_keep#*|}|$(creates)"
a_old="$(conduct "${A}" old)"
check "a bare-label workspace whose cwd is another project is not taken: <project> · old is made" "app${SEP}old|yes" \
  "${a_old%|*}|$([[ "${a_old#*|}" != "${old_ws}" ]] && echo yes || echo no)"

# --- A bare-label workspace an older swarm.sh shared: its first pane is the project's, but another
# project's pane is in it too, so it is not reused.
seed x2 "${A}" "${C}"
x2_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'x2')")"
a_x2="$(conduct "${A}" x2)"
check "a bare-label workspace that also holds another project's pane is not reused: <project> · x2 is made" "app${SEP}x2|yes" \
  "${a_x2%|*}|$([[ "${a_x2#*|}" != "${x2_ws}" ]] && echo yes || echo no)"

# --- The conductor's tab record still lists a live pane (a retired conductor's) in a bare backlog
# workspace another project's pane heads: the conductor opens in its own new workspace, not beside it.
e_name="$(run "${E}" _conductor backlog)"
seed backlog "${C}" "${E}"
old_bl="$(herdr_q "[w['workspace_id'] for w in s['workspaces'] if w['label'] == 'backlog'][-1]")"
mkdir -p "${E}/.swarm/state"; echo "${old_bl}:p01 ${e_name}-done" > "${E}/.swarm/state/${e_name}"
e_b="$(conduct "${E}" --backlog)"
check "a conductor whose tab record lists a live pane in another workspace opens in its own, cart · backlog" "cart${SEP}backlog|yes" \
  "${e_b%|*}|$([[ "${e_b#*|}" != "${old_bl}" ]] && echo yes || echo no)"

# --- The same for any later pane in an epic's tab (a builder's, a review agent's), started from the
# project's own workspace: a tab record whose live pane is in an old shared workspace is not split.
seed xs "${C}" "${A}"
xs_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'xs')")"
echo "${xs_ws}:p01 s-old" > "${A}/.swarm/state/xs"
xs_pane="$(cd "${A}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID="${a_x#*|}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" _pane xs "${A}" 2>&1)"
check "a later pane for a tab whose record is in another workspace opens in the caller's, app · x" "${a_x#*|}" "${xs_pane%%:*}"

# --- A project's workspace under its hashed label is still its own once the plain one is free:
# with only a/app's own app · ... workspaces, a/app's label is app, and it still finds this one.
seed "app-$(hash_of "${A}")${SEP}r" "${A}"
r_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'].endswith(' r'))")"
n="$(creates)"; a_r="$(conduct "${A}" r)"
check "a workspace under the project's hashed label and cwd is reused, and none is made" "${r_ws}|${n}" "${a_r#*|}|$(creates)"

# --- A workspace whose conductor pane has gone, its first pane now a builder's in a story worktree
# (<project>-wt/<slug>), is still the project's: reused, and its plain label is not taken for another dir's.
seed "app${SEP}z" "${A}-wt/s1" "${A}"
z_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'app${SEP}z')")"
n="$(creates)"; a_z="$(conduct "${A}" z)"
check "a workspace whose first pane is the project's builder is still the project's, and none is made" "app${SEP}z|${z_ws}|${n}" \
  "${a_z%|*}|${a_z#*|}|$(creates)"

# --- A project whose own dir is in a folder ending -wt (a worktree as the project) still owns the
# workspace its conductor's pane is in, and so does a project whose workspace has only its builders left.
W="${ROOT}/repo-wt/shop"
mkdir -p "${W}/.claude/swarm" "${W}/docs/stories" "${W}/docs/epics"; : > "${W}/.claude/swarm/config"; git -C "${W}" init -q
: > "${W}/docs/stories/README.md"; printf -- '---\nstatus: active\n---\n\n# q\n' > "${W}/docs/epics/q.md"
seed "shop${SEP}q" "${W}"
q_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'shop${SEP}q')")"
seed "app${SEP}y2" "${A}-wt/s2"
cp "${A}/docs/epics/x.md" "${A}/docs/epics/y2.md"
y2_ws="$(herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == 'app${SEP}y2')")"
n="$(creates)"; w_q="$(conduct "${W}" q)"; a_y2="$(conduct "${A}" y2)"
check "a project in a -wt folder, and one with only its builders left, each reuse their workspace, and none is made" \
  "${q_ws}|${y2_ws}|${n}" "${w_q#*|}|${a_y2#*|}|$(creates)"

# --- tidy and close find a conductor's tab in its relabelled workspace.
t="$(run "${A}" tidy)"
check "tidy in a/app lists its finished conductor's pane in app · x, and not web's" "yes|no" \
  "$(grep -qF "conduct-x-done" <<< "${t}" && grep -qF "${a_x#*|}:" <<< "${t}" && echo yes || echo "no, got: ${t}")|$(grep -qF "${c_x#*|}:" <<< "${t}" && echo yes || echo no)"
x_tab="$(herdr_q "next(t['tab_id'] for t in s['tabs'] if t['workspace_id'] == '${a_x#*|}' and t['label'] == 'x')")"
out="$(run "${A}" close x --all || echo "exit $?")"
check "close x in a/app closes its tab in app · x, and leaves web · x's" "yes|no|yes" \
  "$(grep -qxF "tab|close|${x_tab}" "${ROOT}/herdr.log" && echo yes || echo "no, got: ${out}")|$(herdr_q "any(t['workspace_id'] == '${a_x#*|}' and t['label'] == 'x' for t in s['tabs'])" | sed 's/True/yes/;s/False/no/')|$(herdr_q "any(t['workspace_id'] == '${c_x#*|}' and t['label'] == 'x' for t in s['tabs'])" | sed 's/True/yes/;s/False/no/')"

# --- The lead's workspace. lead <project> <workspace> [VAR=value...] <command>... runs swarm.sh from the
# lead's pane in <workspace>'s tab <workspace>:t0, with herdr's socket (a socket file nothing listens
# on: the stub herdr answers), its stderr appended to ${ROOT}/lead.err, or to LEAD_ERR when set. Each
# herdr call may take LEAD_WAIT seconds (SWARM_LEAD_HERDR_WAIT; 60 here, so a loaded machine's slow stub
# is never cut off; the hang cases set 3).
SOCK="${sock_dir}/h.sock"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "${SOCK}"
lead() {
  local p="$1" ws="$2" vars=()
  shift 2
  while [[ "${1:-}" == *=* ]]; do vars+=("$1"); shift; done
  (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID="${ws}" HERDR_TAB_ID="${ws}:t0" HERDR_SOCKET_PATH="${SOCK}" \
    SWARM_LEAD_HERDR_WAIT="${LEAD_WAIT:-60}" PATH="${ROOT}/bin:${PATH}" ${vars[@]+"${vars[@]}"} bash "${SWARM}" "$@" 2>> "${LEAD_ERR:-${ROOT}/lead.err}")
}
ws_of() { herdr_q "next(w['workspace_id'] for w in s['workspaces'] if w['label'] == '$1')"; }
# labels <workspace> — "<its label>|<its tab <workspace>:t0's label>".
labels() { herdr_q "'%s|%s' % (next(w['label'] for w in s['workspaces'] if w['workspace_id'] == '$1'), next(t['label'] for t in s['tabs'] if t['tab_id'] == '$1:t0'))"; }
wlabel() { herdr_q "next(w['label'] for w in s['workspaces'] if w['workspace_id'] == '$1')"; }
renames() { grep -c '^[a-z]*|rename|' "${ROOT}/herdr.log" || true; }
calls() { grep -c '' "${ROOT}/herdr.log" || true; }
record() { cat "$1/.swarm/lead/workspace" 2>/dev/null || echo none; }

# Two projects of one dir name: each lead's workspace takes its project's own label (b/app's with its
# path hash, as its conductors' have), and stdout carries only the command's own answer.
seed "lead a" "${A}"; seed "lead b" "${B}"
la="$(ws_of "lead a")"; lb="$(ws_of "lead b")"
oa="$(lead "${A}" "${la}" config board_dir)"; ob="$(lead "${B}" "${lb}" config board_dir)"
check "the first command from each lead labels its workspace and tab swarm-lead · <its project>, and records it" \
  "swarm-lead${SEP}app|swarm-lead${SEP}app|swarm-lead${SEP}app-$(hash_of "${B}")|swarm-lead${SEP}app-$(hash_of "${B}")|${la}${TAB}swarm-lead${SEP}app|${A}/docs|${B}/docs" \
  "$(labels "${la}")|$(labels "${lb}")|$(record "${A}")|${oa}|${ob}"

n="$(renames)"; lead "${A}" "${la}" policy conduct > /dev/null
check "a second command from the lead's workspace sends no rename" "${n}" "$(renames)"
n="$(calls)"; lead "${A}" "${la}" config > /dev/null
check "a read-only command with the record present makes no herdr call" "${n}" "$(calls)"
n="$(calls)"; run "${A}" config > /dev/null
check "with no herdr socket, as every other test runs, the lead's command in a new workspace makes no herdr call" "${n}" "$(calls)"

# A lead that moves to another workspace has it labelled with its own label (its first workspace,
# in its record, is no other lead's), and coming back to the first sends nothing.
seed "lead a2" "${A}"; la2="$(ws_of "lead a2")"
lead "${A}" "${la2}" config > /dev/null
n="$(renames)"; lead "${A}" "${la}" config > /dev/null
check "a lead that moves gets its own label there, and back in its first workspace sends no rename" \
  "swarm-lead${SEP}app|swarm-lead${SEP}app|${n}|2" "$(labels "${la2}")|$(renames)|$(grep -c '' "${A}/.swarm/lead/workspace")"

# A workspace herdr no longer lists drops out of the record when the lead labels another.
python3 -c 'import json, sys; f = sys.argv[1]; s = json.load(open(f)); s["workspaces"] = [w for w in s["workspaces"] if w["workspace_id"] != sys.argv[2]]; json.dump(s, open(f, "w"))' \
  "${ROOT}/herdr.json" "${la2}"
seed "lead a3" "${A}"; la3="$(ws_of "lead a3")"
lead "${A}" "${la3}" config > /dev/null
check "a workspace herdr no longer lists drops out of the record when the lead labels another" \
  "${la}${TAB}swarm-lead${SEP}app ${la3}${TAB}swarm-lead${SEP}app" "$(record "${A}" | paste -sd ' ' -)"

# Two projects of one dir name with no conductor yet: the second lead sees the first's swarm-lead
# workspace, so its label carries its path hash.
P="${ROOT}/p/site"; Q="${ROOT}/q/site"
for p in "${P}" "${Q}"; do
  mkdir -p "${p}/.claude/swarm" "${p}/docs/stories"; : > "${p}/.claude/swarm/config"; git -C "${p}" init -q
done
seed "lead p" "${P}"; seed "lead q" "${Q}"
lp="$(ws_of "lead p")"; lq="$(ws_of "lead q")"
lead "${P}" "${lp}" config > /dev/null; lead "${Q}" "${lq}" config > /dev/null
check "two leads of one dir name with no conductor get distinct labels, the second with its path hash" \
  "swarm-lead${SEP}site|swarm-lead${SEP}site|swarm-lead${SEP}site-$(hash_of "${Q}")|swarm-lead${SEP}site-$(hash_of "${Q}")" \
  "$(labels "${lp}")|$(labels "${lq}")"

# A lead whose folder is in no project (a board kept outside the repo), with SWARM_PROJECT naming its
# project, is that project's lead: its workspace is labelled.
K="${ROOT}/kanban"; mkdir -p "${K}"
seed kanban "${K}"; lk="$(ws_of kanban)"
lead "${K}" "${lk}" SWARM_PROJECT="${P}" config > /dev/null
check "a lead in a folder outside any project, with SWARM_PROJECT naming its project, is labelled for that project" \
  "swarm-lead${SEP}site|swarm-lead${SEP}site" "$(labels "${lk}")"

# After the record is deleted (the retry the refusal names), the lead's own swarm-lead workspaces
# still count as its own: their dir is the project's, or its board kept outside the repo. A new
# workspace takes the project's own label, not its hash.
rm -f "${A}/.swarm/lead/workspace"
seed "lead a4" "${A}"; la4="$(ws_of "lead a4")"
lead "${A}" "${la4}" config > /dev/null
printf 'board_dir = %s\n' "${K}" > "${P}/.claude/swarm/config"; rm -f "${P}/.swarm/lead/workspace"
seed kanban2 "${K}"; lk2="$(ws_of kanban2)"
lead "${K}" "${lk2}" SWARM_PROJECT="${P}" config > /dev/null
check "with the record deleted, the lead's own workspaces (in the project, or its board outside the repo) are no other lead's" \
  "swarm-lead${SEP}app|swarm-lead${SEP}site" "$(wlabel "${la4}")|$(wlabel "${lk2}")"

# A lead opened in a conductor's workspace leaves the conductor its label, `<project> · <epic>` or an
# older swarm.sh's bare `<epic>`: said once, and recorded as kept.
: > "${ROOT}/lead.err"; n="$(renames)"
lead "${A}" "${a_x#*|}" config > /dev/null
seed y "${A}"; yws="$(herdr_q "s['workspaces'][-1]['workspace_id']")"
lead "${A}" "${yws}" config > /dev/null; lead "${A}" "${yws}" config > /dev/null
check "a lead in a conductor's workspace (app · x, an older bare y) keeps its label, says so once each, and records it as kept" \
  "${n}|app${SEP}x|y|2|kept" \
  "$(renames)|$(wlabel "${a_x#*|}")|$(wlabel "${yws}")|$(grep -c 'keeps that label' "${ROOT}/lead.err" || true)|$(awk -F'\t' -v w="${yws}" '$1 == w { print $2 }' "${A}/.swarm/lead/workspace")"

# A lead opened in a workspace another project's lead labelled (`swarm-lead · app`, its pane in a/app)
# leaves it that label and its tab's too: said once, and recorded as kept, so the first lead's record
# stays true.
: > "${ROOT}/lead.err"; n="$(renames)"
lead "${B}" "${la}" config > /dev/null; lead "${B}" "${la}" config > /dev/null
check "a lead in another project's lead workspace (swarm-lead · app, in a/app) keeps its label, says so once, and records it as kept" \
  "${n}|swarm-lead${SEP}app|swarm-lead${SEP}app|1|kept" \
  "$(renames)|$(labels "${la}")|$(grep -c "labelled for another project's lead, so it keeps that label" "${ROOT}/lead.err" || true)|$(awk -F'\t' -v w="${la}" '$1 == w { print $2 }' "${B}/.swarm/lead/workspace")"

# A hung herdr is cut off (SWARM_LEAD_HERDR_WAIT, 3 s here), well before the stub's 60 s. A list herdr
# does not give records nothing, so the next command labels the workspace.
seed "lead a5" "${A}"; la5="$(ws_of "lead a5")"
touch "${ROOT}/hang"; t0=${SECONDS}
LEAD_WAIT=3 lead "${A}" "${la5}" config > /dev/null
took=$((SECONDS - t0)); rm -f "${ROOT}/hang"
r1="$(grep -c "^${la5}${TAB}" "${A}/.swarm/lead/workspace" || true)"
lead "${A}" "${la5}" config > /dev/null
check "a hung herdr list is cut off, records nothing, and the next command labels the workspace" \
  "yes|0|swarm-lead${SEP}app" "$([[ ${took} -lt 40 ]] && echo yes || echo "no, it took ${took}s")|${r1}|$(wlabel "${la5}")"

# A rename cut off is no refusal: nothing is recorded or said, and the next command labels the workspace.
seed "lead a6" "${A}"; la6="$(ws_of "lead a6")"
touch "${ROOT}/hang-rename"; : > "${ROOT}/lead.err"
LEAD_WAIT=3 lead "${A}" "${la6}" config > /dev/null
rm -f "${ROOT}/hang-rename"
r1="$(grep -c "^${la6}${TAB}" "${A}/.swarm/lead/workspace" || true)"; said="$(grep -c 'would not label' "${ROOT}/lead.err" || true)"
lead "${A}" "${la6}" config > /dev/null
check "a rename cut off records and says nothing, and the next command labels the workspace" \
  "0|0|swarm-lead${SEP}app|swarm-lead${SEP}app" "${r1}|${said}|$(labels "${la6}")"

# A list without the lead's workspace (herdr restarting) sends no rename and records nothing; once
# herdr lists the workspace, the next command labels it.
n="$(renames)"; lead "${A}" wback config > /dev/null
n1="$(renames)"; r1="$(grep -c "^wback${TAB}" "${A}/.swarm/lead/workspace" || true)"
python3 -c 'import json, sys; f = sys.argv[1]; s = json.load(open(f)); w = "wback"
s["workspaces"].append({"workspace_id": w, "label": "back"}); s["tabs"].append({"tab_id": w + ":t0", "label": "old", "workspace_id": w})
s["panes"].append({"pane_id": w + ":p0", "tab_id": w + ":t0", "workspace_id": w, "cwd": sys.argv[2]}); json.dump(s, open(f, "w"))' "${ROOT}/herdr.json" "${A}"
lead "${A}" wback config > /dev/null
check "a list without the lead's workspace sends no rename and records nothing; once listed, the next command labels it" \
  "${n}|0|swarm-lead${SEP}app" "${n1}|${r1}|$(wlabel wback)"

# An agent's pane, a swarm.sh another one runs, a test hook and a command for another project label
# nothing. not_lead <what> <folder> [VAR=value...] <command>... runs it from <folder>, in a new
# workspace of its own: it must send no rename, and the workspace and its tab keep their labels. The
# nested swarm.sh runs from the board folder outside any project, as from a lead kept there, where
# only NESTED_CALL stops it.
not_lead() {
  local what="$1" dir="$2" n ws
  shift 2
  seed "not lead" "${dir}"; ws="$(herdr_q "s['workspaces'][-1]['workspace_id']")"
  n="$(renames)"; lead "${dir}" "${ws}" "$@" > /dev/null || true
  check "${what} renames nothing" "${n}|not lead|old" "$(renames)|$(labels "${ws}")"
}
not_lead "a command with SWARM_AGENT set (a Claude agent's pane)" "${A}" SWARM_AGENT=build-s1 config board_dir
not_lead "a command with SWARM_GH_CALLER set (any agent's pane)" "${A}" SWARM_GH_CALLER=build-s1 config board_dir
not_lead "a swarm.sh another one runs (dash --project's, for another project)" "${K}" SWARM_GH_VIA="swarm.sh dash" SWARM_PROJECT="${B}" config board_dir
not_lead "a test hook (as lead-stop.sh's _step)" "${A}" _name s1
LEAD_ERR=/dev/null not_lead "a command whose stderr goes to /dev/null (as the Stop hook's do)" "${A}" config board_dir
not_lead "a command for another project (SWARM_PROJECT) from a project's folder" "${A}" SWARM_PROJECT="${B}" config board_dir

# A rename herdr refuses is said once and recorded, so the next command tries nothing.
seed "lead c" "${C}"; lc="$(ws_of "lead c")"
touch "${ROOT}/refuse"; : > "${ROOT}/lead.err"; n="$(renames)"
lead "${C}" "${lc}" config board_dir > /dev/null; lead "${C}" "${lc}" config board_dir > /dev/null
rm -f "${ROOT}/refuse"
check "a refused rename is said once, naming the record to delete to try again, recorded as refused, and not tried again" \
  "1|$((n + 1))|lead c|old|${lc}${TAB}refused" \
  "$(grep -c "would not label the lead's workspace.*until you delete ${C}/.swarm/lead/workspace" "${ROOT}/lead.err" || true)|$(renames)|$(labels "${lc}")|$(record "${C}")"

# A tab rename herdr refuses after the workspace's went through: the message and the record say the
# tab alone was refused.
seed "lead c2" "${C}"; lc2="$(ws_of "lead c2")"
touch "${ROOT}/refuse-tab"; : > "${ROOT}/lead.err"
lead "${C}" "${lc2}" config > /dev/null; rm -f "${ROOT}/refuse-tab"
check "a refused tab rename: the workspace has its label, the message and record name the tab alone" \
  "swarm-lead${SEP}web|old|1|0|${lc2}${TAB}swarm-lead${SEP}web${TAB}tab refused" \
  "$(labels "${lc2}")|$(grep -c 'labelled the lead.s workspace .* but would not label its tab' "${ROOT}/lead.err" || true)|$(grep -c 'would not label the lead.s workspace' "${ROOT}/lead.err" || true)|$(grep "^${lc2}${TAB}" "${C}/.swarm/lead/workspace")"

# --- Agents the lead starts. `swarm.sh agent` from each lead opens its tab in its project's
# `<project> · lead-agents` workspace, never the lead's own, and the new workspace's placeholder tab
# is closed; a second agent reuses it. From a conductor's environment (SWARM_AGENT) it opens in the
# caller's workspace, and conduct from the lead still opens in the epic's. close finds the tab.
printf 'co-write\n' > "${ROOT}/brief.md"
# tab_ws <tab label> — "<its workspace's label>|<its workspace id>" for the newest tab of that label;
# "none|none" with no such tab, or one in a workspace herdr no longer lists.
tab_ws() { herdr_q "next(('%s|%s' % (w['label'], w['workspace_id']) for t in reversed(s['tabs']) if t['label'] == '$1' for w in s['workspaces'] if w['workspace_id'] == t['workspace_id']), 'none|none')"; }
# ws_tabs <workspace> — its tabs' labels, space-separated.
ws_tabs() { herdr_q "' '.join(t['label'] for t in s['tabs'] if t['workspace_id'] == '$1')"; }
lead "${A}" "${la}" agent hld-a hld-a "${A}" hld "${ROOT}/brief.md" > /dev/null
lead "${B}" "${lb}" agent hld-b hld-b "${B}" hld "${ROOT}/brief.md" > /dev/null
ha="$(tab_ws hld-a)"; hb="$(tab_ws hld-b)"
check "swarm.sh agent from each lead opens in its project's lead-agents workspace, placeholder closed, never the lead's" \
  "app${SEP}lead-agents|app-$(hash_of "${B}")${SEP}lead-agents|hld-a|hld-b|yes" \
  "${ha%|*}|${hb%|*}|$(ws_tabs "${ha#*|}")|$(ws_tabs "${hb#*|}")|$([[ "${ha#*|}" != "${la}" && "${hb#*|}" != "${lb}" && "${ha#*|}" != "${hb#*|}" ]] && echo yes || echo no)"
n="$(creates)"; lead "${A}" "${la}" agent plan-a plan-a "${A}" survey "${ROOT}/brief.md" > /dev/null
check "a second agent from the lead reuses its lead-agents workspace, and none is made" "app${SEP}lead-agents|${ha#*|}|${n}" "$(tab_ws plan-a)|$(creates)"

lead "${A}" "${a_x#*|}" SWARM_AGENT=conduct-x agent s-x s-x "${A}" code "${ROOT}/brief.md" > /dev/null
out="$(lead "${A}" "${la}" conduct r 2>&1 || echo "exit $?")"
got="$(herdr_q "next((g['pane_id'].split(':')[0] for g in s['agents'] if g['name'] == 'conduct-r'), 'none')")"
[[ "${got}" != none ]] || got="no conductor conduct-r, got: ${out}"
check "from a conductor's environment the agent opens in the caller's workspace, and conduct from the lead in the epic's" \
  "${a_x#*|}|${a_r#*|}" "$(tab_ws s-x | cut -d'|' -f2)|${got}"

ta="$(herdr_q "next(t['tab_id'] for t in s['tabs'] if t['label'] == 'hld-a')")"
out="$(lead "${A}" "${la}" close hld-a || echo "exit $?")"
check "close closes the agent's tab in the lead-agents workspace" "$(ws_of "app${SEP}lead-agents" 2>/dev/null)|yes|no" \
  "${ta%%:*}|$(grep -qxF "tab|close|${ta}" "${ROOT}/herdr.log" && echo yes || echo "no, got: ${out}")|$(herdr_q "any(t['tab_id'] == '${ta}' for t in s['tabs'])" | sed 's/True/yes/;s/False/no/')"

# The lead-agents workspace is kept by its record, .swarm/lead/agents-workspace, not by its panes'
# directories: web's lead starts an agent in another repo's worktree (zzz-wt/s9, whose path does not
# say whose it is), which makes web · lead-agents with that pane alone, and its next agent, in the
# project, opens there too. Once herdr no longer lists the recorded workspace, a new one is made.
mkdir -p "${ROOT}/zzz-wt/s9"
lead "${C}" "${lc}" agent s9 s9 "${ROOT}/zzz-wt/s9" code "${ROOT}/brief.md" > /dev/null
s9="$(tab_ws s9)"
n="$(creates)"; lead "${C}" "${lc}" agent hld-c hld-c "${C}" hld "${ROOT}/brief.md" > /dev/null
check "a lead-agents workspace whose only pane is in another repo's worktree is reused from its record, and none is made" \
  "web${SEP}lead-agents|${s9#*|}|${n}|${s9#*|}${TAB}web${SEP}lead-agents" \
  "$(tab_ws hld-c)|$(creates)|$(cat "${C}/.swarm/lead/agents-workspace")"
python3 -c 'import json, sys; f = sys.argv[1]; s = json.load(open(f)); s["workspaces"] = [w for w in s["workspaces"] if w["workspace_id"] != sys.argv[2]]; json.dump(s, open(f, "w"))' \
  "${ROOT}/herdr.json" "${s9#*|}"
n="$(creates)"; lead "${C}" "${lc}" agent plan-c plan-c "${C}" survey "${ROOT}/brief.md" > /dev/null
pc="$(tab_ws plan-c)"
check "a recorded workspace herdr no longer lists is not used: a new web · lead-agents is made and recorded" \
  "web${SEP}lead-agents|yes|$((n + 1))|${pc#*|}${TAB}web${SEP}lead-agents" \
  "${pc%|*}|$([[ "${pc#*|}" != "${s9#*|}" ]] && echo yes || echo no)|$(creates)|$(cat "${C}/.swarm/lead/agents-workspace")"

# A tab create herdr refuses, in a lead-agents workspace just made, still closes the placeholder tab
# and says why, through _pane, a direct call of next_pane under errexit (start_agent's command
# substitution drops errexit, so there the close ran either way); the next agent then opens in that
# workspace (recorded, and still listed by the stub) with its own tab alone.
seed "lead e" "${E}"; le="$(ws_of "lead e")"
touch "${ROOT}/refuse-tab"; : > "${ROOT}/lead.err"
out="$(lead "${E}" "${le}" _pane hld-e "${E}" || echo "exit $?")"
rm -f "${ROOT}/refuse-tab"
se="$(ws_of "cart${SEP}lead-agents")"
lead "${E}" "${le}" agent hld-e hld-e "${E}" hld "${ROOT}/brief.md" > /dev/null
check "a refused first tab in a new lead-agents workspace closes its placeholder and says so; the next agent opens there alone" \
  "yes|${se}|hld-e" \
  "$(grep -q 'could not open a pane in tab hld-e' "${ROOT}/lead.err" && echo yes || echo "no, got: ${out}; $(tail -1 "${ROOT}/lead.err")")|$(tab_ws hld-e | cut -d'|' -f2)|$(ws_tabs "${se}")"

# --- Review round 1. An epic named lead-agents, or whose parent: is, would share the lead's agents'
# workspace: conduct refuses it before any herdr call, as it refuses one named backlog.
printf -- '---\nstatus: active\n---\n\n# lead-agents\n' > "${A}/docs/epics/lead-agents.md"
printf -- '---\nstatus: active\nparent: lead-agents\n---\n\n# child\n' > "${A}/docs/epics/child.md"
n="$(creates)"
o1="$(run "${A}" conduct lead-agents || echo "exit $?")"; o2="$(run "${A}" conduct child || echo "exit $?")"
refused() { grep -q "$1 would take the lead's agents' workspace" <<< "$2" && grep -qx 'exit 1' <<< "$2" && echo yes || echo "no, got: $2"; }
check "conduct refuses an epic named lead-agents, or with that parent:, and makes no workspace" "yes|yes|${n}" \
  "$(refused lead-agents "${o1}")|$(refused child "${o2}")|$(creates)"

# The lead of a board kept outside the repo (K, with SWARM_PROJECT naming P) starts the HLD co-author in
# its own folder, outside the project: the agent opens in site · lead-agents with the placeholder kept
# ahead of it, relabelled lead-agents, at the project's directory, so the workspace's directory stays
# the project's and P's conductor keeps the plain label site · x.
# first_cwd <workspace> — the cwd of its first pane, which herdr_workspaces takes as the workspace's.
first_cwd() { herdr_q "next((p['cwd'] for p in s['panes'] if p['workspace_id'] == '$1'), 'none')"; }
pb="$(run "${P}" config board_dir)"; mkdir -p "${pb}/epics" "${pb}/stories"; : > "${pb}/stories/README.md"
printf -- '---\nstatus: active\n---\n\n# x\n' > "${pb}/epics/x.md"
lead "${K}" "${lk}" SWARM_PROJECT="${P}" agent hld-k hld-k "${K}" hld "${ROOT}/brief.md" > /dev/null
hk="$(tab_ws hld-k)"; p_x="$(conduct "${P}" x)"
check "an agent the lead starts outside the project keeps a pane at the project dir ahead of it, and the project's labels stay plain" \
  "site${SEP}lead-agents|lead-agents hld-k|${P}|site${SEP}x" "${hk%|*}|$(ws_tabs "${hk#*|}")|$(first_cwd "${hk#*|}")|${p_x%|*}"

# A found lead-agents workspace with no pane left at the project (plan-c closed) gets one made at the
# project dir, labelled lead-agents, ahead of an agent started outside the project.
mkdir -p "${ROOT}/elsewhere"
lead "${C}" "${lc}" close plan-c > /dev/null || true
cw="$(cut -f1 "${C}/.swarm/lead/agents-workspace")"
lead "${C}" "${lc}" agent s11 s11 "${ROOT}/elsewhere" code "${ROOT}/brief.md" > /dev/null
check "a lead-agents workspace with no pane at the project gets one made ahead of an agent outside it" \
  "${cw}|lead-agents s11|${C}" "$(tab_ws s11 | cut -d'|' -f2)|$(ws_tabs "${cw}")|$(first_cwd "${cw}")"

# A recorded workspace herdr now lists under another label (relabelled by hand, or an id given again)
# is left alone: a new web · lead-agents is made and recorded.
"${ROOT}/bin/herdr" workspace rename "${cw}" "my scratch" > /dev/null
n="$(creates)"; lead "${C}" "${lc}" agent hld-c2 hld-c2 "${C}" hld "${ROOT}/brief.md" > /dev/null
hc="$(tab_ws hld-c2)"
check "a recorded workspace under another label is not used: a new web · lead-agents is made and recorded" \
  "web${SEP}lead-agents|yes|$((n + 1))|${hc#*|}${TAB}web${SEP}lead-agents|my scratch" \
  "${hc%|*}|$([[ "${hc#*|}" != "${cw}" ]] && echo yes || echo no)|$(creates)|$(cat "${C}/.swarm/lead/agents-workspace")|$(herdr_q "next(w['label'] for w in s['workspaces'] if w['workspace_id'] == '${cw}')")"

# herdr hanging on its workspace list: the lookup is cut short (LEAD_AGENTS_HERDR_WAIT seconds), and
# the agent opens in the lead's own workspace instead, with the reason on stderr, so the start goes on.
touch "${ROOT}/hang"; : > "${ROOT}/lead.err"
t0=${SECONDS}; lead "${A}" "${la}" agent slow-a slow-a "${A}" survey "${ROOT}/brief.md" > /dev/null; dt=$((SECONDS - t0))
rm -f "${ROOT}/hang"
check "a herdr that hangs on its lists is cut short, and the agent opens in the lead's own workspace, saying why" \
  "${la}|yes|yes" \
  "$(tab_ws slow-a | cut -d'|' -f2)|$(grep -q 'the agent opens in this workspace instead' "${ROOT}/lead.err" && echo yes || echo "no: $(tail -1 "${ROOT}/lead.err")")|$([[ ${dt} -lt 40 ]] && echo yes || echo "no, ${dt}s")"

# --- Final round. A found lead-agents workspace with no pane at the project, where herdr refuses the
# pane at the project dir: the agent opens in the lead's own workspace instead, saying why, and the
# lead-agents workspace is left empty, so the outside dir is never its first pane's.
lead "${C}" "${lc}" close hld-c2 > /dev/null || true
touch "${ROOT}/refuse-anchor"; : > "${ROOT}/lead.err"
lead "${C}" "${lc}" agent s12 s12 "${ROOT}/elsewhere" code "${ROOT}/brief.md" > /dev/null
rm -f "${ROOT}/refuse-anchor"
check "a refused pane at the project dir sends the agent to the lead's own workspace, saying why, and leaves the lead-agents workspace empty" \
  "${lc}|yes|" \
  "$(tab_ws s12 | cut -d'|' -f2)|$(grep -q 'would not open a pane at .* the agent opens in this workspace instead' "${ROOT}/lead.err" && echo yes || echo "no: $(tail -1 "${ROOT}/lead.err")")|$(ws_tabs "${hc#*|}")"

# Two first agents the lead starts at once (plan-hld's surveys), with no record yet: the record's lock
# makes the second wait for the first's workspace, so both open in one site-<hash> · lead-agents, one
# workspace is made, and no lock is left.
n="$(creates)"
lead "${Q}" "${lq}" agent sv-1 sv-1 "${Q}" survey "${ROOT}/brief.md" > /dev/null & p1=$!
lead "${Q}" "${lq}" agent sv-2 sv-2 "${Q}" survey "${ROOT}/brief.md" > /dev/null & p2=$!
wait "${p1}" "${p2}" || true
q1="$(tab_ws sv-1)"; q2="$(tab_ws sv-2)"
check "two first agents started at once share one lead-agents workspace, one is made, and no lock is left" \
  "site-$(hash_of "${Q}")${SEP}lead-agents|yes|$((n + 1))|no lock" \
  "${q1%|*}|$([[ "${q1#*|}" == "${q2#*|}" ]] && echo yes || echo "no: ${q1#*|} vs ${q2#*|}")|$(creates)|$([[ -e "${Q}/.swarm/lead/agents-workspace.lock" ]] && echo 'lock left' || echo 'no lock')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
