#!/usr/bin/env bash
# config_test.sh — the project config: finding the project, parsing .claude/swarm/config, a board
# outside the project, repos_dir, the base branch, unblock and finish, and the minimum Claude Code.
# Fixture remotes are local bare repos; herdr and claude (tests/claude_stub.sh) are stubs on PATH.
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
project "${p}" "merge = maybe"
check "bad value names its line" "yes" "$(fails_with 'config:1: merge must be' run "${p}" config)"
# Switches that are gone: a line naming one is an unknown key. Each name is split with '' so
# removed_test.sh, which greps tests/ for them, finds none here.
for k in pr''_per base''_branches sign''_commits review''_bot keep''_panes finished; do
  project "${p}" "${k} = true"
  check "${k} is an unknown key" "yes" "$(fails_with "config:1: unknown key '${k}'" run "${p}" config)"
done
# lessons_file went with lessons: an old config that sets it still loads, with no error or output.
project "${p}" "lessons_file = AGENTS.md" "stall_minutes = 45"
check "a config with lessons_file loads silently" "45" "$(run "${p}" config stall_minutes)"
check "lessons points to outcomes' recurring block and exits 0, with or without --all" \
  "swarm.sh lessons is now outcomes' recurring block: swarm.sh outcomes [--since YYYY-MM-DD]|0|0" \
  "$(out="$(run "${p}" lessons)" && echo "${out}|0" || echo "${out}|$?")|$(run "${p}" lessons --all >/dev/null && echo 0 || echo $?)"
check "lessons refuses any other argument" "yes" "$(fails_with 'usage: swarm.sh lessons \[--all\]' run "${p}" lessons --bogus)"
project "${p}" "board_dir = \$(touch ${p}/pwned)"
check "a \$(...) value is refused" "yes" "$(fails_with 'config:1: board_dir: \$ and backticks' run "${p}" config)"
check "a \$(...) value never runs" "no" "$([[ -e "${p}/pwned" ]] && echo yes || echo no)"
project "${p}" "stall_minutes = 0"
check "stall_minutes must be a positive whole number" "yes" "$(fails_with 'config:1: stall_minutes must be' run "${p}" config)"
project "${p}" "stall_minutes = 45"
check "stall_minutes is read" "45" "$(run "${p}" config stall_minutes)"
check "codex_minutes ships on, at 10" "10" "$(project "${p}"; run "${p}" config codex_minutes)"
for v in 0 abc; do
  project "${p}" "codex_minutes = ${v}"
  check "codex_minutes = ${v} is refused, naming file and line" "yes" \
    "$(fails_with "${p}/.claude/swarm/config:1: codex_minutes must be a positive whole number" run "${p}" config)"
done
for v in -1 x 2.5 04; do
  project "${p}" "sonnet_share = ${v}"
  check "sonnet_share = ${v} is refused, naming the key" "yes" "$(fails_with 'config:1: sonnet_share must be a non-negative whole number' run "${p}" config)"
done
project "${p}" "sonnet_share = 4"
check "sonnet_share is read" "4" "$(run "${p}" config sonnet_share)"
check "sonnet_share ships off" "0" "$(project "${p}"; run "${p}" config sonnet_share)"
for v in -1 1.5 two; do
  project "${p}" "escalate_after = ${v}"
  check "escalate_after = ${v} is refused, naming file and line" "yes" \
    "$(fails_with "${p}/.claude/swarm/config:1: escalate_after must be a non-negative whole number" run "${p}" config)"
done
check "escalate_after ships on, at 2" "2" "$(project "${p}"; run "${p}" config escalate_after)"
check "goal ships off" "off" "$(project "${p}"; run "${p}" config goal)"
project "${p}" "goal = 10"
check "goal = 10 is read" "10" "$(run "${p}" config goal)"
for v in 0 -1 1.5 two on; do
  project "${p}" "goal = ${v}"
  check "goal = ${v} is refused, naming file and line" "yes" \
    "$(fails_with "${p}/.claude/swarm/config:1: goal must be off or a positive whole number" run "${p}" config)"
done
check "lead ships off" "off" "$(project "${p}"; run "${p}" config lead)"
project "${p}" "lead = session"
check "lead = session is read" "session" "$(run "${p}" config lead)"
project "${p}" "lead = on"
check "lead = on is refused, naming file and line" "yes" \
  "$(fails_with "${p}/.claude/swarm/config:1: lead must be off or session, not 'on'" run "${p}" config)"
check "merge_admin ships off" "off" "$(project "${p}"; run "${p}" config merge_admin)"
project "${p}" "merge_admin = on"
check "merge_admin = on is read" "on" "$(run "${p}" config merge_admin)"
project "${p}" "merge_admin = yes"
check "merge_admin = yes is refused, naming file and line" "yes" \
  "$(fails_with "${p}/.claude/swarm/config:1: merge_admin must be off or on, not 'yes'" run "${p}" config)"
project "${p}" 'builder_subagent_model = haiku"}'
check "builder_subagent_model that is not a model name is refused, naming the key" "yes" \
  "$(fails_with 'config:1: builder_subagent_model must be a model name' run "${p}" config)"
project "${p}" "builder_subagent_model = claude-haiku-5-5"
check "builder_subagent_model is read" "claude-haiku-5-5" "$(run "${p}" config builder_subagent_model)"
check "fallback_reviewer ships empty" "" "$(project "${p}"; run "${p}" config fallback_reviewer)"
project "${p}" "fallback_reviewer = sonnet"
check "fallback_reviewer is read" "sonnet" "$(run "${p}" config fallback_reviewer)"
project "${p}" "fallback_reviewer = son net"
check "fallback_reviewer that is not a model name is refused, naming the key" "yes" \
  "$(fails_with "config:1: fallback_reviewer must be a model name such as haiku, not 'son net'" run "${p}" config)"
project "${p}" "" "repos_dir = ~/code   # trailing comment"
check "~ expands to HOME" "${HOME}/code" "$(run "${p}" config repos_dir)"

# --- One set of keys: the method's config table, CONFIG_KEYS and load_config's case arms. A key
# missing from any of the three is named.
REPO="$(dirname "${SWARM}")/.."
# shellcheck disable=SC2016 # the backticks are the table's, not a command
table_keys="$(sed -n '/^## Configuring a project/,/^## /s/^| `\([a-z_]*\)` |.*/\1/p' "${REPO}/docs/method.md")"
list_keys="$(sed -n 's/^CONFIG_KEYS="\(.*\)"$/\1/p' "${SWARM}" | tr ' ' '\n')"
arm_keys="$(sed -n '/^load_config() {/,/^}/p' "${SWARM}" | sed -n 's/^      \([a-z_|]*\)).*/\1/p' | tr '|' '\n')"
# absent <keys> — each key of the three lists that is not in <keys>, space-separated.
absent() {
  local k out=""
  for k in $(printf '%s\n' "${table_keys}" "${list_keys}" "${arm_keys}" | sort -u); do
    grep -qxF -- "${k}" <<< "$1" || out+="${k} "
  done
  printf '%s' "${out% }"
}
check "the three key lists were all read" "yes" \
  "$([[ -n "${table_keys}" && -n "${list_keys}" && -n "${arm_keys}" ]] && echo yes || echo no)"
check "no key is missing from the method's config table" "" "$(absent "${table_keys}")"
check "no key is missing from CONFIG_KEYS" "" "$(absent "${list_keys}")"
check "no key is missing from load_config's case arms" "" "$(absent "${arm_keys}")"
# shellcheck disable=SC2016 # the backticks are the table's
check "the table's goal row has the Default CFG_goal ships" "\`$(project "${p}"; run "${p}" config goal)\`" \
  "$(sed -n 's/^| `goal` | \([^|]*\) |.*/\1/p' "${REPO}/docs/method.md")"
# shellcheck disable=SC2016 # the backticks are the table's
check "the table's codex_minutes row has the Default CFG_codex_minutes ships" "\`$(project "${p}"; run "${p}" config codex_minutes)\`" \
  "$(sed -n 's/^| `codex_minutes` | \([^|]*\) |.*/\1/p' "${REPO}/docs/method.md")"
# shellcheck disable=SC2016 # the backticks are the table's
check "the table's lead row has the Default CFG_lead ships" "\`$(project "${p}"; run "${p}" config lead)\`" \
  "$(sed -n 's/^| `lead` | \([^|]*\) |.*/\1/p' "${REPO}/docs/method.md")"

# --- A non-git project whose board is outside it, and repos in repos_dir.
remote "${ROOT}/svc.git" main main dev
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/repos/svc"
p="${ROOT}/kanban"; b="${ROOT}/elsewhere/board"
project "${p}" "board_dir = ../elsewhere/board" "repos_dir = ../repos"
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/no-repo.md "status: later" "kind: code"
item "${b}" stories/c.md "status: blocked" "kind: code" "repo: svc" "depends_on: [gone]"
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
story "${p}" a >/dev/null || true   # a start that fails shows as the FAIL below, not an abort
check "story starts from origin's default branch" \
  "$(git -C "${ROOT}/repos/svc" rev-parse origin/main)" "$(git -C "${ROOT}/repos/svc-wt/a" rev-parse HEAD 2>&1)"
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

# --- base_for: origin's default branch, asked of origin; never a guess.
remote "${ROOT}/trunk.git" trunk main trunk
"${GIT[@]}" clone -q "${ROOT}/trunk.git" "${ROOT}/repos/trunk"
project "${ROOT}/cfg"
base() { run "${ROOT}/cfg" _base "${ROOT}/repos/$1"; }
check "picks origin's default" "trunk" "$(base trunk)"
git -C "${ROOT}/trunk.git" symbolic-ref HEAD refs/heads/main
check "a changed default on origin is seen, not the cached one" "main" "$(base trunk)"
remote "${ROOT}/dev-default.git" dev main dev
"${GIT[@]}" clone -q --single-branch --branch dev "${ROOT}/dev-default.git" "${ROOT}/repos/single"
check "a single-branch clone of origin's default, dev, finds dev" "dev" "$(base single)"

# --- unblock and finish: a done item counts as finished, and finish deletes the file.
p="${ROOT}/marked"; b="${p}/docs"
project "${p}"
item "${b}" stories/x.md "status: done" "kind: code"
item "${b}" stories/y.md "status: blocked" "kind: code" "depends_on: [x]"
check "a done blocker unblocks" "ready: y" "$(run "${p}" unblock)"
# depends_on is what counts: a legacy blocked_by naming only part of it never unblocks the story early.
item "${b}" stories/gap.md "status: ready" "kind: code"
item "${b}" stories/read-set.md "status: blocked" "kind: code" "blocked_by: [x]" "depends_on: [gap, x]"
check "an open depends_on slug that blocked_by leaves out keeps a story blocked" "" "$(run "${p}" unblock)"
run "${p}" finish gap >/dev/null
check "it unblocks once depends_on is finished, and leaves its blocked_by line as it is" "ready: read-set|blocked_by: [x]" \
  "$(run "${p}" unblock)|$(grep blocked_by "${b}/stories/read-set.md")"
rm "${b}/stories/read-set.md"
# No blocked_by line at all: depends_on [a] waits while a is open, and the waiting list names a.
item "${b}" stories/a.md "status: ready" "kind: code"
item "${b}" stories/wait.md "status: blocked" "kind: code" "depends_on: [a, x]"
check "a story with depends_on [a] and no blocked_by stays blocked while a is open" "" "$(run "${p}" unblock)"
check "status --all names its open depends_on slugs" "yes" \
  "$(grep -qxF '  blocked: wait (by a)' <<< "$(run "${p}" status --all)" && echo yes || echo "no, got: $(run "${p}" status --all)")"
rm "${b}/stories/a.md"
check "and is ready once a's file is gone" "ready: wait" "$(run "${p}" unblock)"
rm "${b}/stories/wait.md"
# depends_on is read from the front matter only: a body line that looks like it is not the list.
item "${b}" stories/body-deps.md "status: blocked" "kind: code"
echo "depends_on: [x]" >> "${b}/stories/body-deps.md"
item "${b}" stories/deps-done.md "status: blocked" "kind: code" "depends_on: [x]"
all="$(run "${p}" status --all)"
check "a blocked story with no depends_on in its front matter says it is held by hand" "yes" \
  "$(grep -qxF '  blocked: body-deps (by hand: no depends_on)' <<< "${all}" && echo yes || echo "no, got: ${all}")"
check "a blocked story whose depends_on is finished says unblock readies it" "yes" \
  "$(grep -qxF '  blocked: deps-done (its depends_on is finished: swarm.sh unblock readies it)' <<< "${all}" && echo yes || echo "no, got: ${all}")"
check "a depends_on line in the body never unblocks a story" "ready: deps-done" "$(run "${p}" unblock)"
rm "${b}/stories/body-deps.md" "${b}/stories/deps-done.md"
# Trailing whitespace, a CR or a # comment after the list is not part of its last slug.
item "${b}" stories/gap3.md "status: ready" "kind: code"
item "${b}" stories/trail.md "status: blocked" "kind: code" "depends_on: [gap3, x] "
item "${b}" stories/trail-cr.md "status: blocked" "kind: code" $'depends_on: [x]\r'
item "${b}" stories/trail-note.md "status: blocked" "kind: code" "depends_on: [x]  # after gap3"
check "a depends_on list with trailing space names its slugs, not 'x]'" "yes" \
  "$(grep -qxF '  blocked: trail (by gap3)' <<< "$(run "${p}" status --all)" && echo yes || echo "no, got: $(run "${p}" status --all)")"
run "${p}" finish gap3 >/dev/null
check "a depends_on list ending in a space, a CR or a # comment unblocks once its slugs finish" $'ready: trail\nready: trail-cr\nready: trail-note' \
  "$(run "${p}" unblock | sort)"
rm "${b}/stories/trail.md" "${b}/stories/trail-cr.md" "${b}/stories/trail-note.md"
# Quoted slugs (YAML allows both kinds).
item "${b}" stories/gap2.md "status: ready" "kind: code"
item "${b}" stories/only-deps.md "status: blocked" "kind: code" "depends_on: [\"gap2\", 'x']"
check "a story blocked only by depends_on waits for it" "" "$(run "${p}" unblock)"
run "${p}" finish gap2 >/dev/null
check "a story blocked only by depends_on, with quoted slugs, unblocks once they finish" "ready: only-deps" "$(run "${p}" unblock)"
rm "${b}/stories/only-deps.md"
rm "${b}/stories/y.md"
check "a done story is neither built nor a gate" "done" "$(first "$(run "${p}" next)")"
item "${b}" stories/z.md "status: ready" "kind: code"
run "${p}" finish z >/dev/null
check "finish deletes the story's file" "gone" "$([[ -e "${b}/stories/z.md" ]] && echo there || echo gone)"

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
# run_stub runs claude only when the stub is what `claude` resolves to; otherwise it prints a marker
# that fails the check, so the real binary (which may open a logged-in session) is never run.
run_stub() { if [[ "$(command -v claude || true)" == "${STUB_BIN}/claude" ]]; then "$@"; else echo "claude is not the stub"; fi; }
check "claude on PATH is the stub" "${STUB_BIN}/claude" "$(command -v claude || true)"
export CLAUDE_STUB_VERSION="0.0.1 (Claude Code)"
check "the stub prints CLAUDE_STUB_VERSION" "0.0.1 (Claude Code)" "$(run_stub claude --version)"
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
check "agents --json prints the fixture it is given" "$(cat "${AGENTS_FIXTURE}")" "$(run_stub claude agents --json)"
check "agents --json prints [] with no fixture" "[]" "$(unset CLAUDE_STUB_AGENTS; run_stub claude agents --json)"
rc=0; run_stub claude foo >/dev/null 2>&1 || rc=$?
check "any other call exits 1" "1" "${rc}"
check "any other call names the call" "claude stub: unexpected call: foo" "$(run_stub claude foo 2>&1 || true)"

# --- require_claude: an old Claude Code, a missing one, or a caller session missing from Claude
# Code's own list is refused before any pane or workspace opens. The caller runs in pane w:0;
# herdr's agent list names its session when $HERDR_CALLER is set. Every herdr call is logged, so a
# pane or workspace opened shows.
rc="${ROOT}/rc"; mkdir -p "${rc}/bin"; echo brief > "${rc}/brief.md"
cat > "${rc}/bin/herdr" <<'EOF'
#!/bin/sh
echo "$*" >> "${HERDR_LOG}"
case "$1 $2" in
  "tab create")   echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "pane split")   echo '{"result":{"pane":{"pane_id":"w:2"}}}' ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   echo "{\"result\":{\"agents\":[${HERDR_CALLER:-}]}}" ;;
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"ws"},"tab":{"tab_id":"ws:t"}}}' ;;
esac
EOF
chmod +x "${rc}/bin/herdr"
export HERDR_LOG="${rc}/herdr.log" HERDR_CALLER=""
caller_id="00000000-0000-4000-8000-0000000000aa"
caller="{\"name\":\"lead\",\"agent_status\":\"working\",\"pane_id\":\"w:0\",\"agent_session\":{\"value\":\"${caller_id}\"}}"
sed "s/00000000-0000-4000-8000-000000000001/${caller_id}/" "${AGENTS_FIXTURE}" > "${rc}/with-caller.json"
kb="${ROOT}/kanban"
item "${ROOT}/elsewhere/board" stories/old-claude.md "status: ready" "kind: code" "repo: svc"
item "${ROOT}/elsewhere/board" epics/old-claude.md "status: active"
# in_herdr <PATH> <command>... — swarm.sh in the kanban project from pane w:0, with an empty herdr log.
in_herdr() { local path="$1"; shift; : > "${HERDR_LOG}"; (cd "${kb}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_PANE_ID=w:0 PATH="${path}" bash "${SWARM}" "$@" 2>&1); }
start() { in_herdr "${rc}/bin:${PATH}" agent rc rc-agent "${ROOT}/repos/svc" code "${rc}/brief.md"; }
started() { local out; out="$(start)"; [[ "${out##*$'\n'}" == "rc-agent w:"* ]] && echo started || echo "${out}"; }
panes() { grep -cE '^(tab create|pane split|workspace create)' "${HERDR_LOG}" || true; }
need="needs Claude Code 2.1.145 or later"

CLAUDE_STUB_VERSION="2.1.144 (Claude Code)"
check "agent: below the minimum is refused, naming both versions, before any pane" "yes|0" \
  "$(fails_with "${need}, and claude --version says '2.1.144 (Claude Code)'" start)|$(panes)"
check "story: below the minimum is refused before any pane or worktree" "yes|0|no worktree" \
  "$(fails_with "${need}" in_herdr "${rc}/bin:${PATH}" story old-claude)|$(panes)|$([[ -e "${ROOT}/repos/svc-wt/old-claude" ]] && echo worktree || echo no worktree)"
report="${kb}/.swarm/conduct-old-claude.report.md"; mkdir -p "${kb}/.swarm"; echo earlier > "${report}"
check "conduct: below the minimum is refused before any workspace or pane, and the old report stays" "yes|0|report kept" \
  "$(fails_with "${need}" in_herdr "${rc}/bin:${PATH}" conduct old-claude)|$(panes)|$([[ -f "${report}" ]] && echo report kept || echo report gone)"
CLAUDE_STUB_VERSION="2.1.99 (Claude Code)"
check "versions compare as numbers: 2.1.99 is below 2.1.145" "yes" "$(fails_with "${need}" start)"

CLAUDE_STUB_VERSION="2.1.145 (Claude Code)" HERDR_CALLER="${caller}" CLAUDE_STUB_AGENTS="${AGENTS_FIXTURE}"
check "at the minimum, a caller session missing from claude agents --json is refused before any pane" "yes|0" \
  "$(fails_with "this session (${caller_id}) is not in claude agents --json" start)|$(panes)"
CLAUDE_STUB_AGENTS="${rc}/no-such-file"
check "a listing that fails is refused as unreadable, with its error, before any pane" "yes|0" \
  "$(fails_with "could not read claude agents --json (cat: ${rc}/no-such-file: No such file or directory), so this session (${caller_id})" start)|$(panes)"
CLAUDE_STUB_AGENTS="${rc}/empty.json"; : > "${CLAUDE_STUB_AGENTS}"
check "a listing that prints nothing is refused as unreadable" "yes" \
  "$(fails_with "could not read claude agents --json (empty output)" start)"
CLAUDE_STUB_AGENTS="${rc}/with-caller.json"
check "at the minimum, a caller session in the list starts" "started" "$(started)"
HERDR_CALLER="" CLAUDE_STUB_AGENTS="${AGENTS_FIXTURE}"
check "at the minimum, with no caller session, the version alone starts" "started" "$(started)"

# goal = N needs /goal, so story asks for GOAL_MIN_CLAUDE; with goal off the same version builds.
item "${ROOT}/elsewhere/board" stories/goal-claude.md "status: ready" "kind: code" "repo: svc"
printf '\n**Done when:**\n- it holds\n' >> "${ROOT}/elsewhere/board/stories/goal-claude.md"
cfg="$(cat "${kb}/.claude/swarm/config")"
CLAUDE_STUB_VERSION="2.1.268 (Claude Code)"
printf '%s\n' "${cfg}" "goal = 5" > "${kb}/.claude/swarm/config"
check "story with goal = 5: one below the goal minimum is refused, naming that version, before any pane or worktree" "yes|0|no worktree" \
  "$(fails_with "needs Claude Code 2.1.269 or later, and claude --version says '2.1.268 (Claude Code)'" in_herdr "${rc}/bin:${PATH}" story goal-claude)|$(panes)|$([[ -e "${ROOT}/repos/svc-wt/goal-claude" ]] && echo worktree || echo no worktree)"
printf '%s\n' "${cfg}" > "${kb}/.claude/swarm/config"
out="$(in_herdr "${rc}/bin:${PATH}" story goal-claude)" && out=started
check "story with goal off: the same version builds" "started" "${out}"
CLAUDE_STUB_VERSION="2.1.145 (Claude Code)"

no_claude="${rc}/bin"; IFS=: read -r -a dirs <<< "${PATH}"
for d in "${dirs[@]}"; do [[ -x "${d}/claude" ]] || no_claude+=":${d}"; done
check "the PATH without claude has none" "" "$(PATH="${no_claude}"; command -v claude || true)"
check "no claude on PATH is refused before any pane" "yes|0" \
  "$(fails_with "Claude Code (claude) is not on PATH; swarm.sh needs 2.1.145 or later" in_herdr "${no_claude}" agent rc rc-agent "${ROOT}/repos/svc" code "${rc}/brief.md")|$(panes)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
