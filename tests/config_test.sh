#!/usr/bin/env bash
# config_test.sh — the project config: finding the project, parsing .claude/swarm/config, a board
# outside the project, repos_dir, base branches, and finished = mark. Fixture remotes are local bare
# repos; herdr and claude (tests/claude_stub.sh) are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
first() { printf '%s' "${1%%$'\n'*}"; }
# fails_with <pattern> <command>... — "yes" when the command fails with <pattern> in its output.
fails_with() {
  local pat="$1" out; shift
  if out="$("$@")"; then echo "it succeeded: ${out}"; elif grep -q -- "${pat}" <<< "${out}"; then echo yes; else echo "${out}"; fi
}

# remote <dir> <head> <branch>... — a bare repo with one commit per branch, each on top of the last,
# so every branch has its own sha. <head> is origin's default branch.
remote() {
  local bare="$1" head="$2" w b; shift 2
  "${GIT[@]}" init -q --bare "${bare}"
  w="$(mktemp -d)"; "${GIT[@]}" -C "${w}" init -q
  for b in "$@"; do
    "${GIT[@]}" -C "${w}" checkout -q -B "${b}"
    "${GIT[@]}" -C "${w}" commit -q --allow-empty -m "${b}"
    "${GIT[@]}" -C "${w}" push -q "${bare}" "${b}"
  done
  git -C "${bare}" symbolic-ref HEAD "refs/heads/${head}"
  rm -rf "${w}"
}

# project <dir> <config line>... — a non-git project dir with those config lines.
project() {
  local dir="$1"; shift
  mkdir -p "${dir}/.claude/swarm"
  printf '%s\n' "$@" > "${dir}/.claude/swarm/config"
}

# item <board> <path> <front-matter line>... — a board file.
item() {
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

run() { (cd "$1" && shift && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" "$@" 2>&1); }

# --- The config file: parsed, never sourced; a typo stops the script with its line number.
p="${ROOT}/parse"
project "${p}" "# a comment" "boardd = x"
check "unknown key names its line" "yes" "$(fails_with 'config:2: unknown key' run "${p}" config)"
project "${p}" "finished = maybe"
check "bad value names its line" "yes" "$(fails_with 'config:1: finished must be' run "${p}" config)"
project "${p}" "board_dir = \$(touch ${p}/pwned)"
check "a \$(...) value is refused" "yes" "$(fails_with 'config:1: board_dir: \$ and backticks' run "${p}" config)"
check "a \$(...) value never runs" "no" "$([[ -e "${p}/pwned" ]] && echo yes || echo no)"
project "${p}" "stall_minutes = 0"
check "stall_minutes must be a positive whole number" "yes" "$(fails_with 'config:1: stall_minutes must be' run "${p}" config)"
project "${p}" "stall_minutes = 45"
check "stall_minutes is read" "45" "$(run "${p}" config stall_minutes)"
project "${p}" "" "repos_dir = ~/code   # trailing comment"
check "~ expands to HOME" "${HOME}/code" "$(run "${p}" config repos_dir)"

# --- A non-git project whose board is outside it, and repos in repos_dir.
remote "${ROOT}/svc.git" main main dev
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/repos/svc"
p="${ROOT}/kanban"; b="${ROOT}/elsewhere/board"
project "${p}" "board_dir = ../elsewhere/board" "repos_dir = ../repos" "base_branches = dev main"
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/no-repo.md "status: later" "kind: code"
item "${b}" stories/c.md "status: blocked" "kind: code" "repo: svc" "blocked_by: [gone]"
check "next reads a board outside the project" "story a" "$(first "$(run "${p}" next)")"
check "unblock reads a board outside the project" "ready: c" "$(run "${p}" unblock)"

# story, with a stub herdr that accepts every call.
mkdir -p "${ROOT}/bin"
cat > "${ROOT}/bin/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "tab create")   echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "pane split")   echo '{"result":{"pane":{"pane_id":"w:2"}}}' ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   echo '{"result":{"agents":[]}}' ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr"
story() { (cd "$1" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" story "$2" 2>&1); }
story "${p}" a >/dev/null
check "story starts from the first base branch origin has" \
  "$(git -C "${ROOT}/repos/svc" rev-parse origin/dev)" "$(git -C "${ROOT}/repos/svc-wt/a" rev-parse HEAD 2>&1)"
sed -i.bak 's/^status: later$/status: ready/' "${b}/stories/no-repo.md" && rm -f "${b}/stories/no-repo.md.bak"
check "a story with no repo: in a non-git project stops" "yes" \
  "$(fails_with 'no repo: named, and the project' story "${p}" no-repo)"
item "${b}" stories/untrusted.md "status: ready" "kind: code" "repo: svc"
mkdir -p "${ROOT}/untrusting" && echo '{"projects": {}}' > "${ROOT}/untrusting/.claude.json"
check "a story in a repo Claude Code does not trust stops, before any worktree" "yes|no worktree" \
  "$(CLAUDE_CONFIG_DIR="${ROOT}/untrusting" fails_with "does not trust ${ROOT}/repos/svc yet" story "${p}" untrusted)|$([[ -e "${ROOT}/repos/svc-wt/untrusted" ]] && echo worktree || echo no worktree)"
rm "${b}/stories/untrusted.md"

# --- Finding the project from a subdirectory, a worktree, and $SWARM_PROJECT. The story is only in
# the main checkout's board, so a run that stops at the worktree's own copy sees none.
g="${ROOT}/proj"
"${GIT[@]}" init -q "${g}"
project "${g}" "board_dir = board"
"${GIT[@]}" -C "${g}" add .claude && "${GIT[@]}" -C "${g}" commit -q -m config
"${GIT[@]}" -C "${g}" worktree add -q "${ROOT}/proj-wt/x"
item "${g}/board" stories/a.md "status: ready"
mkdir -p "${g}/sub/dir"
check "project found from a subdirectory" "story a" "$(first "$(run "${g}/sub/dir" next)")"
check "project found from a worktree is the main checkout" "story a" "$(first "$(run "${ROOT}/proj-wt/x" next)")"
check "SWARM_PROJECT wins" "story a" \
  "$(first "$(cd "${ROOT}" && env -u HERDR_ENV SWARM_PROJECT="${g}" bash "${SWARM}" next 2>&1)")"

# --- base_for: the first listed branch origin has, else origin's default branch; never a guess.
remote "${ROOT}/only-main.git" main main
remote "${ROOT}/trunk.git" trunk main trunk
for r in only-main trunk; do "${GIT[@]}" clone -q "${ROOT}/${r}.git" "${ROOT}/repos/${r}"; done
base() { # <config line> <repo>
  project "${ROOT}/cfg" "$1"
  run "${ROOT}/cfg" _base "${ROOT}/repos/$2"
}
check "dev main picks dev" "dev" "$(base "base_branches = dev main" svc)"
check "dev main without dev picks main" "main" "$(base "base_branches = dev main" only-main)"
check "empty list picks origin's default" "trunk" "$(base "" trunk)"
git -C "${ROOT}/trunk.git" symbolic-ref HEAD refs/heads/main
check "a changed default on origin is seen, not the cached one" "main" "$(base "" trunk)"
"${GIT[@]}" clone -q --single-branch --branch main "${ROOT}/svc.git" "${ROOT}/repos/single"
check "a single-branch clone still finds dev on origin" "dev" "$(base "base_branches = dev main" single)"
check "no listed branch on origin stops" "yes" \
  "$(fails_with 'origin has none of base_branches' base "base_branches = nope" svc)"

# --- finished = mark: a done item counts as finished, and stays on the board.
p="${ROOT}/marked"; b="${p}/docs"
project "${p}" "finished = mark"
item "${b}" stories/x.md "status: done" "kind: code"
item "${b}" stories/y.md "status: blocked" "kind: code" "blocked_by: [x]"
check "a done blocker unblocks" "ready: y" "$(run "${p}" unblock)"
# depends_on counts as well as blocked_by: a story waits until both lists are finished.
item "${b}" stories/gap.md "status: ready" "kind: code"
item "${b}" stories/read-set.md "status: blocked" "kind: code" "blocked_by: [x]" "depends_on: [gap, x]"
check "an open depends_on keeps a story blocked" "" "$(run "${p}" unblock)"
run "${p}" finish gap >/dev/null
check "it unblocks once depends_on is finished too" "ready: read-set" "$(run "${p}" unblock)"
rm "${b}/stories/read-set.md" "${b}/stories/gap.md"
# Blocked only by depends_on, with quoted slugs (YAML allows both kinds).
item "${b}" stories/gap2.md "status: ready" "kind: code"
item "${b}" stories/only-deps.md "status: blocked" "kind: code" "blocked_by: []" "depends_on: [\"gap2\", 'x']"
check "a story blocked only by depends_on waits for it" "" "$(run "${p}" unblock)"
run "${p}" finish gap2 >/dev/null
check "a story blocked only by depends_on, with quoted slugs, unblocks once they finish" "ready: only-deps" "$(run "${p}" unblock)"
rm "${b}/stories/only-deps.md"
rm "${b}/stories/y.md"
check "a done story is neither built nor a gate" "done" "$(first "$(run "${p}" next)")"
item "${b}" stories/z.md "status: ready" "kind: code"
run "${p}" finish z >/dev/null
check "finish marks the story done and keeps it" "done" "$(sed -n 's/^status: //p' "${b}/stories/z.md" 2>&1)"
project "${p}" "finished = delete"
run "${p}" finish z >/dev/null
check "finish with finished = delete deletes it" "gone" "$([[ -e "${b}/stories/z.md" ]] && echo there || echo gone)"

# --- version: a warning, with the one command to update, only when a newer version is published.
have="$(python3 -c "import json; print(json.load(open('$(dirname "${SWARM}")/../.claude-plugin/plugin.json'))['version'])")"
ver() { (cd "${ROOT}" && SWARM_LATEST_URL="$1" bash "${SWARM}" version 2>&1); }
published() { echo "{\"version\": \"$1\"}" > "${ROOT}/latest.json"; echo "file://${ROOT}/latest.json"; }
out="$(ver "$(published 99.0.0)")"
check "a newer version is out: warn, and name the update command" "swarm-dev ${have}|yes|yes" \
  "$(first "${out}")|$(grep -q "WARNING: swarm-dev 99.0.0 is out" <<< "${out}" && echo yes || echo no)|$(grep -qx '  swarm.sh update' <<< "${out}" && echo yes || echo no)"
check "the same version: no warning" "swarm-dev ${have}" "$(ver "$(published "${have}")")"
check "the lookup fails (offline): no warning, no error" "swarm-dev ${have}|0" "$(ver "file://${ROOT}/missing.json")|$?"

# --- Folder trust: an agent in a folder Claude Code does not trust stalls on its trust prompt, so
# the start is refused. Trust is keyed on the git root (a worktree's main checkout); outside git,
# on the folder or a trusted ancestor.
t="${ROOT}/trust"
project "${t}/proj"
mkdir -p "${t}/cfg" "${t}/plain/sub"
"${GIT[@]}" init -q "${t}/repo" && "${GIT[@]}" -C "${t}/repo" commit -q --allow-empty -m init
"${GIT[@]}" -C "${t}/repo" worktree add -q "${t}/repo-wt/story" -b story
trust() { python3 -c 'import json,sys; print(json.dumps({"projects": {p: {"hasTrustDialogAccepted": True} for p in sys.argv[1:]}}))' "$@" > "${t}/cfg/.claude.json"; }
trusted() { CLAUDE_CONFIG_DIR="${t}/cfg" run "${t}/proj" _trusted "$1" | tail -1; }
trust "${t}/repo"
check "a worktree is trusted through its main checkout" "trusted" "$(trusted "${t}/repo-wt/story")"
trust "${t}/repo-wt/story"
check "an untrusted main checkout is refused, and named" \
  "swarm: Claude Code does not trust ${t}/repo yet, so the agent would stall on its trust prompt. Run claude in ${t}/repo once, accept the prompt, then try again." \
  "$(trusted "${t}/repo-wt/story")"
trust "${t}"
check "outside git, a trusted ancestor covers a folder" "trusted" "$(trusted "${t}/plain/sub")"
check "a trusted ancestor does not cover a git repo inside it" \
  "swarm: Claude Code does not trust ${t}/repo yet, so the agent would stall on its trust prompt. Run claude in ${t}/repo once, accept the prompt, then try again." \
  "$(trusted "${t}/repo")"
"${GIT[@]}" init -q "${t}/lib" && "${GIT[@]}" -C "${t}/lib" commit -q --allow-empty -m lib
"${GIT[@]}" -C "${t}/repo" -c protocol.file.allow=always submodule add -q "${t}/lib" lib 2>/dev/null
trust "${t}/repo/lib"
check "a submodule is keyed on its own folder" "trusted" "$(trusted "${t}/repo/lib")"
rm "${t}/cfg/.claude.json"
check "no trust file to read: the start goes ahead" "trusted" "$(trusted "${t}/plain")"

# The stub. The version is one the real binary never prints, so a real claude on PATH cannot pass.
export CLAUDE_STUB_VERSION="0.0.1 (Claude Code)"
check "the stub prints CLAUDE_STUB_VERSION" "0.0.1 (Claude Code)" "$(claude --version)"
AGENTS_FIXTURE="${ROOT}/agents.json"
cat > "${AGENTS_FIXTURE}" <<'JSON'
[
  {
    "pid": 4242,
    "cwd": "/home/user/repo",
    "kind": "interactive",
    "startedAt": 1791256129171,
    "sessionId": "00000000-0000-4000-8000-000000000001",
    "name": "repo-ab",
    "status": "idle"
  }
]
JSON
export CLAUDE_STUB_AGENTS="${AGENTS_FIXTURE}"
check "agents --json prints the fixture it is given" "$(cat "${AGENTS_FIXTURE}")" "$(claude agents --json)"
check "agents --json prints [] with no fixture" "[]" "$(env -u CLAUDE_STUB_AGENTS claude agents --json)"
rc=0; claude foo >/dev/null 2>&1 || rc=$?
check "any other call exits 1" "1" "${rc}"
check "any other call names the call" "claude stub: unexpected call: foo" "$(claude foo 2>&1 || true)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
