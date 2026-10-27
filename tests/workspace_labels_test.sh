#!/usr/bin/env bash
# workspace_labels_test.sh — each conductor's herdr workspace is labelled `<project> · <epic>` (or
# `<project> · backlog`), so three projects under one herdr never share one: two with one dir name
# (a/app and b/app) get distinct labels, the second's with its path hash. A workspace under the bare
# label an older swarm.sh gave is reused only when its cwd (its first pane's) is the project's. close
# and tidy still find a conductor's tab in its relabelled workspace. herdr, gh and claude are stubs on
# PATH; herdr's state (${ROOT}/herdr.json) is shared by every project.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
SEP=" · "

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: workspaces, tabs, panes and agents in ${ROOT}/herdr.json. A workspace w<n> is made with a
# placeholder tab w<n>:t0 whose pane has its --cwd; each tab or pane is <workspace>:t<n> or :p<n>.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nexec python3 "%s/bin/herdr.py" "$@"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat > "${ROOT}/bin/herdr.py" <<'EOF'
import json, os, sys
H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = os.path.join(H, "herdr.json")
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
elif cmd == "workspace list": out({"workspaces": s["workspaces"]})
elif cmd == "workspace create":
    ws = "w%d" % new(); tab = ws + ":t0"
    s["workspaces"].append({"workspace_id": ws, "label": opt("--label")})
    s["tabs"].append({"tab_id": tab, "label": "1", "workspace_id": ws}); pane(ws, tab, opt("--cwd"))
    out({"workspace": {"workspace_id": ws}, "tab": {"tab_id": tab}})
elif cmd == "tab create":
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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
