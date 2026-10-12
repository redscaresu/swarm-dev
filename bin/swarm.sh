#!/usr/bin/env bash
# swarm.sh — run agents in herdr panes so every one can be watched.
#
#   swarm.sh agent <tab> <name> <cwd> <role> <prompt-file>   start one agent in its own pane
#   swarm.sh story <slug>                                   build one <board>/stories/<slug>.md
#   swarm.sh conduct <epic>                                 a fresh conductor for one epic, in a workspace named for its HLD
#   swarm.sh wait [--stall] <name> [timeout-ms]             block until the agent settles; --stall: also exit 3 when a builder stalls
#   swarm.sh policy <role>                                  print the model and effort for a role
#   swarm.sh close <name>                                   close a story's pane, a conductor's epic tab, or a tab and its overflow
#   swarm.sh tell <slug> <file>                             send a builder (or any agent) the contents of a file, such as review findings
#   swarm.sh cost [YYYY-MM-DD]                              tokens and estimated cost per role, from the agents' logs
#   swarm.sh log-finding <kind> <pr-url> <text>             log one review finding that was fixed, by its kind (the outer loop)
#   swarm.sh lessons [--all]                                kinds recurring in 3+ PRs (or tagged lead memories) with no rule in lessons_file yet, and a long brief
#   swarm.sh next                                           the chain's next step, read from the board (resumable)
#   swarm.sh status [--all]                                 agents that need a look, what waits on you, and the next step
#   swarm.sh dash [--watch [seconds]] [--ladder] [--tree]  a read-only dashboard: what needs you, epics with their agents and PRs, recent events; --watch redraws in place, q quits, t tree, l ladder
#   swarm.sh tidy [--yes]                                   list, and with --yes close, empty panes and retired agents' panes
#   swarm.sh unblock                                        mark ready every blocked story whose blockers are all finished
#   swarm.sh finish <slug>                                  take a merged story or epic off the board (delete or mark done)
#   swarm.sh review <slug> <pr-url>...                      a story or epic whose PRs are green and reviewed now waits on a human merge
#   swarm.sh reconcile                                      finish each review item whose PRs all merged; a closed one goes back to ready
#   swarm.sh findings <repo> <pr>                           every check-run note on a PR's head, and its open code-scanning alerts
#   swarm.sh watch [repo...]                                wait until a story or epic PR needs the lead, print why, and exit
#   swarm.sh config [key]                                   the project's settings and where each came from, or one value
#   swarm.sh base <repo>                                    the base branch a repo's stories start from and its PRs go into
#   swarm.sh version                                        the installed version, and a warning when a newer one is out
#   swarm.sh update                                         update the plugin to the newest version
#
# The project is, first match wins: $SWARM_PROJECT; the nearest directory up from here with
# .claude/swarm/config (mapped to the main checkout when it is in a git worktree); the main checkout
# of the git repo you are in. Settings live in .claude/swarm/config (see config below). Must run
# inside herdr (HERDR_ENV=1). An epic gets a tab named for it: the conductor's pane, then a pane per
# story, each named. A story outside any epic gets its own tab. Tabs hold at most four panes (a 2x2
# grid); a fifth agent opens "<tab>-2", and so on, so no pane gets too small to follow.
set -euo pipefail

# die <message> — stop. Inside a logged command (main), a die at the command's own level (not in a
# nested $(...), which may be tolerated) also records its first line as the command's outcome.
die() {
  echo "swarm: $*" >&2
  if [[ -n "${DIE_FILE}" && "${BASH_SUBSHELL}" == "${DIE_LEVEL}" ]]; then
    local m="$*"
    { printf '%s\n' "${m%%$'\n'*}" > "${DIE_FILE}"; } 2>/dev/null || true
  fi
  exit 1
}
# Set only by main, in the subshell a logged command runs in; never taken from the environment.
DIE_FILE=""
DIE_LEVEL=-1

# The framework itself: this script's repo, whose docs/method.md the briefs point at.
SWARM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where the newest version is published, and the plugin's name in Claude Code. SWARM_LATEST_URL is
# overridable so the tests need no network.
LATEST_URL="${SWARM_LATEST_URL:-https://raw.githubusercontent.com/redscaresu/swarm-dev/main/.claude-plugin/plugin.json}"
PLUGIN=swarm-dev@swarm-dev
MARKETPLACE=swarm-dev

plugin_version() { python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"; }

# show_version — the installed version; when a newer one is published, a warning and how to update.
# A failed lookup (offline) is not an error: /swarm must still run.
show_version() {
  local have latest
  have="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json")"
  echo "swarm-dev ${have}"
  latest="$(curl -fsSL --max-time 5 "${LATEST_URL}" 2>/dev/null | plugin_version 2>/dev/null)" || return 0
  python3 -c "import sys; v=lambda s: tuple(int(x) for x in s.split('.')); sys.exit(v(sys.argv[2]) <= v(sys.argv[1]))" \
    "${have}" "${latest}" || return 0
  cat <<EOF
WARNING: swarm-dev ${latest} is out; this is ${have}. To update, run:
  swarm.sh update
then restart Claude Code so the new version is loaded.
EOF
}

# update_plugin — fetch the newest version. Claude Code loads it on its next start.
update_plugin() {
  claude plugin marketplace update "${MARKETPLACE}"
  claude plugin update "${PLUGIN}"
  echo "Restart Claude Code to load the new version."
}

# Neither needs a project: they run before one is looked for.
case "${1:-}" in
  version) show_version; exit ;;
  update)  update_plugin; exit ;;
esac

# main_checkout <dir> — <dir> as it sits in its repo's main checkout, so a worktree resolves to the
# same project as the checkout it came from. Fails when <dir> is not in a git repo.
main_checkout() {
  local common top rel
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  top="$(git -C "$1" rev-parse --show-toplevel)"
  rel="${1#"${top}"}"
  echo "$(dirname "${common}")${rel}"
}

find_project() {
  local d
  if [[ -n "${SWARM_PROJECT:-}" ]]; then
    (cd "${SWARM_PROJECT}" 2>/dev/null && pwd -P) || die "SWARM_PROJECT ${SWARM_PROJECT} is not a directory"
    return
  fi
  d="$(pwd -P)"
  while [[ "${d}" != / ]]; do
    if [[ -f "${d}/.claude/swarm/config" ]]; then
      main_checkout "${d}" || echo "${d}"
      return
    fi
    d="$(dirname "${d}")"
  done
  main_checkout "$(pwd -P)" || die "not in a swarm project: no .claude/swarm/config above here and not in a git repo"
}

PROJECT_DIR="$(find_project)"
CONFIG_FILE="${PROJECT_DIR}/.claude/swarm/config"

# Settings, with their defaults. CFG_<key> is the value, SRC_<key> where it came from.
CFG_board_dir=docs
CFG_repos_dir=""        # empty: the project dir's parent
CFG_base_branches=""    # empty: origin's default branch
CFG_finished=delete
CFG_merge=human         # human: no agent merges; a PR that is ready waits on the board for you
CFG_review_bot=off      # auto: the conductor also runs the repo's PR review bot (docs/review.md)
CFG_sign_commits=false  # true: every commit and merge is signed, or the agent stops
CFG_pr_per=story        # epic: stories merge into epic/<slug>, and each repo gets one PR per epic
CFG_keep_panes=false    # true: `close` leaves a finished agent's pane and tabs open to read
CFG_lessons_file=.claude/swarm/brief.md  # where adopted lesson rules live, e.g. AGENTS.md, which every agent already loads
CFG_stall_minutes=30    # a builder working this long with no commit, PR update or swarm action is stalled?
CONFIG_KEYS="board_dir repos_dir base_branches finished merge review_bot sign_commits pr_per keep_panes lessons_file stall_minutes"
for _key in ${CONFIG_KEYS}; do printf -v "SRC_${_key}" default; done

# load_config — read CONFIG_FILE as `key = value` lines. It is parsed, never sourced, so it cannot run
# code; a `$` or backtick is refused so nobody expects it to expand. Any bad line stops the script.
load_config() {
  local n=0 line key value where
  [[ -f "${CONFIG_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$((n + 1)); where="${CONFIG_FILE}:${n}"
    line="${line%%#*}"
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]] \
      || die "${where}: expected 'key = value'"
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    [[ "${value}" != *'$'* && "${value}" != *'`'* ]] || die "${where}: ${key}: \$ and backticks are not expanded; write the value out"
    case "${key}" in
      lessons_file)
        # Only a file every agent reads: the brief is pasted into each prompt, each brief says to read
        # AGENTS.md first, and Claude Code loads CLAUDE.md. A rule anywhere else would retire its
        # candidate without ever reaching an agent.
        case "${value}" in .claude/swarm/brief.md|AGENTS.md|CLAUDE.md|.claude/CLAUDE.md) ;;
          *) die "${where}: lessons_file must be one every agent reads: .claude/swarm/brief.md, AGENTS.md, CLAUDE.md or .claude/CLAUDE.md" ;;
        esac ;;
      board_dir|repos_dir)
        [[ -n "${value}" ]] || die "${where}: ${key} is empty"
        # shellcheck disable=SC2088 # a literal ~ in the file, expanded here
        [[ "${value}" == "~" || "${value}" == "~/"* ]] && value="${HOME}${value:1}" ;;
      base_branches)
        [[ "${value}" =~ ^[A-Za-z0-9._/[:space:]-]*$ ]] || die "${where}: base_branches: not branch names: ${value}" ;;
      finished)
        [[ "${value}" == delete || "${value}" == mark ]] || die "${where}: finished must be delete or mark, not '${value}'" ;;
      merge)
        [[ "${value}" == human || "${value}" == agent ]] || die "${where}: merge must be human or agent, not '${value}'" ;;
      review_bot)
        [[ "${value}" == off || "${value}" == auto ]] || die "${where}: review_bot must be off or auto, not '${value}'" ;;
      sign_commits|keep_panes)
        [[ "${value}" == true || "${value}" == false ]] || die "${where}: ${key} must be true or false, not '${value}'" ;;
      pr_per)
        [[ "${value}" == story || "${value}" == epic ]] || die "${where}: pr_per must be story or epic, not '${value}'" ;;
      stall_minutes)
        [[ "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: stall_minutes must be a positive whole number, not '${value}'" ;;
      *) die "${where}: unknown key '${key}' (known: ${CONFIG_KEYS})" ;;
    esac
    printf -v "CFG_${key}" '%s' "${value}"
    printf -v "SRC_${key}" '%s' "${where}"
  done < "${CONFIG_FILE}"
}
load_config

# abs_path <path> — <path>, relative to the project dir unless it is absolute.
abs_path() { if [[ "$1" == /* ]]; then echo "$1"; else echo "${PROJECT_DIR}/$1"; fi; }
BOARD="$(abs_path "${CFG_board_dir}")"
[[ -d "${BOARD}" ]] && BOARD="$(cd "${BOARD}" && pwd -P)"   # so a board_dir with .. is compared as the real path
REPOS_DIR="$(dirname "${PROJECT_DIR}")"; [[ -z "${CFG_repos_dir}" ]] || REPOS_DIR="$(abs_path "${CFG_repos_dir}")"
PROJECT_IS_GIT=0; [[ -e "${PROJECT_DIR}/.git" ]] && PROJECT_IS_GIT=1
# A builder can change the board in its own PR only when the board is in the project's repo.
BOARD_IN_REPO=0; [[ ${PROJECT_IS_GIT} == 1 && "${BOARD}/" == "${PROJECT_DIR}/"* ]] && BOARD_IN_REPO=1

STATE_DIR="${PROJECT_DIR}/.swarm/state"
# Project rules every builder gets after the standard ones: commit trailers, secrets, ADR rules.
PROJECT_BRIEF="${PROJECT_DIR}/.claude/swarm/brief.md"
# Where lesson rules are read from. The briefs paste the brief whole and, from any other
# lessons_file, only its tagged rule lines (project_rules), never the whole file.
LESSONS_FILE="$(abs_path "${CFG_lessons_file}")"
PANES_PER_TAB=4

show_config() {
  local key v
  if [[ -n "${1:-}" ]]; then
    case "$1" in
      board_dir) echo "${BOARD}" ;;
      repos_dir) echo "${REPOS_DIR}" ;;
      lessons_file) echo "${LESSONS_FILE}" ;;
      project) echo "${PROJECT_DIR}" ;;
      *) [[ " ${CONFIG_KEYS} " == *" $1 "* ]] || die "unknown key '$1' (known: project ${CONFIG_KEYS})"
         v="CFG_$1"; echo "${!v}" ;;
    esac
    return
  fi
  echo "project = ${PROJECT_DIR}"
  for key in ${CONFIG_KEYS}; do
    v="CFG_${key}"; local s="SRC_${key}"
    case "${key}" in board_dir) v=BOARD ;; repos_dir) v=REPOS_DIR ;; lessons_file) v=LESSONS_FILE ;; esac
    echo "${key} = ${!v}    (${!s})"
  done
}

# repo_dir <name> — where a story's repo is: the project itself when <name> is empty or the
# project's own name, else <repos_dir>/<name>. Fails, printing why, when there is no such repo.
repo_dir() {
  local name="$1" dir
  if [[ -z "${name}" || ( "${name}" == "$(basename "${PROJECT_DIR}")" && ${PROJECT_IS_GIT} == 1 ) ]]; then
    [[ ${PROJECT_IS_GIT} == 1 ]] || { echo "no repo: named, and the project ${PROJECT_DIR} is not a git repo"; return 1; }
    echo "${PROJECT_DIR}"; return
  fi
  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad repo '${name}'"; return 1; }
  dir="${REPOS_DIR}/${name}"
  [[ -e "${dir}/.git" ]] || { echo "no repo at ${dir}"; return 1; }
  echo "${dir}"
}

# worktree_for <repo-dir> <slug> — where a story's worktree goes: beside its repo, in <repo>-wt/.
worktree_for() { echo "$(dirname "$1")/$(basename "$1")-wt/$2"; }

# base_for <repo-dir> — the branch a story starts from and merges into, fetched: the first
# base_branches entry origin has, or origin's default branch when the list is empty. Each is asked
# of origin itself, not the clone's cached refs, which a single-branch clone or a changed default
# would get wrong. Never a guess.
base_for() {
  local src="$1" b head branches
  if [[ -n "${CFG_base_branches// /}" ]]; then
    read -r -a branches <<< "${CFG_base_branches}"
    for b in "${branches[@]}"; do
      git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" 2>/dev/null && { echo "${b}"; return; }
    done
    die "${src}: origin has none of base_branches (${CFG_base_branches})"
  fi
  if ! git -C "${src}" remote set-head origin --auto >/dev/null 2>&1 \
     || ! head="$(git -C "${src}" symbolic-ref -q --short refs/remotes/origin/HEAD)"; then
    die "${src}: cannot tell origin's default branch; set base_branches"
  fi
  b="${head#origin/}"
  git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" || die "${src}: cannot fetch ${b}"
  echo "${b}"
}

# The model and effort for each role. This is the one place the policy lives
# (docs/method.md § Model and effort explains the reasoning). ROLE_GROUPS lists every role policy
# knows, by group: the usage message and `dash` read it.
ROLE_GROUPS="design:hld,hld-review,hld-lead planning:survey,lead,skeptic,critic,codex building:code,code-risky,docs,chore,verify,escalate conducting:conduct"
roles() { local g r=""; for g in ${ROLE_GROUPS}; do r+=" ${g#*:}"; done; r="${r//,/ }"; echo "${r# }"; }
policy() {
  case "$1" in
    hld)        echo "claude fable high" ;;    # co-writes the HLD with the user, who waits on every turn
    hld-review) echo "claude fable xhigh" ;;   # attacks the finished draft before it is agreed
    hld-lead)   echo "claude fable xhigh" ;;   # HLD into epics: one call that shapes everything below it
    survey)     echo "claude sonnet high" ;;   # reads and cites; feeds the lead, so not low
    lead)       echo "claude opus xhigh" ;;    # one decomposition decides the whole epic
    skeptic)    echo "claude opus high" ;;     # the only gate a story passes before it is built
    critic)     echo "claude opus high" ;;
    codex)      echo "codex default high" ;;   # a different model family, read-only
    code)       echo "claude opus high" ;;
    code-risky) echo "claude opus xhigh" ;;    # Layer 3, teardown, safety or hygiene paths
    docs)       echo "claude sonnet medium" ;; # prose a reviewer reads, often held to a doc test
    chore)      echo "claude haiku medium" ;;  # mechanical edits with a checkable result
    verify)     echo "claude haiku medium" ;;  # run tests or commands and report
    escalate)   echo "claude fable xhigh" ;;   # only after a story failed twice, or an unreconcilable epic
    conduct)    echo "claude opus high" ;;     # dispatches, reviews, merges one epic; a fresh session each time
    *) die "unknown role '$1' ($(roles))" ;;
  esac
}

# agent_name <name> — the herdr agent name for anything started or waited on. start_agent and
# `wait` both map through here, so every caller agrees: lowercase, [a-z0-9_-], starting with a letter, at most 32 characters.
agent_name() {
  local n
  n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
  [[ "${n}" =~ ^[a-z] ]] || n="s${n}"
  printf '%s' "${n:0:32}"
}

json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }

# PANES_PY: the one reader of this project's panes, shared by status, tidy and dash (each python
# exec's it from $SWARM_PANES_PY), so the three views agree.
#   pane_records(state, keep) yields (tab label, pane, recorded name) for each pane in keep (own_panes
#     and still live), from the tab records in STATE_DIR, skipping *.tmp; a pane's first record wins.
#   agent_state(a, name) -> (state, needs_a_look), where a is herdr's agent in the pane (None for an
#     empty pane): EMPTY (a start that failed), WAITING (blocked on a prompt), working, retired
#     (renamed <name>-done by retire_agent), or herdr's own status.
PANES_PY='
import glob, os, re
def pane_records(state, keep):
    seen = set()
    for path in sorted(glob.glob(os.path.join(state, "*"))):
        if not os.path.isfile(path) or path.endswith(".tmp"):
            continue
        for line in open(path, errors="replace"):
            f = line.split()
            if not f or f[0] not in keep or f[0] in seen:
                continue
            seen.add(f[0])
            yield os.path.basename(path), f[0], (f[1] if len(f) > 1 else "-")
def agent_state(a, name):
    if a is None:
        return "EMPTY", True
    st = a.get("agent_status") or "unknown"
    if st == "blocked":
        return "WAITING", True
    if st == "working":
        return "working", False
    if re.search(r"-done\d*$", name):
        return "retired", False
    return st, False
'

# STALL_PY: the one stall rule and agent-to-story mapping, shared by dash and `wait --stall` (each
# python exec's it from $SWARM_STALL_PY). herdr gives no time an agent entered its state, so a
# builder's last sign of life stands in for it.
#   story_for(name, stories) -> the slug whose agent is <name> (cut at 32 characters, any -doneN
#     dropped), preferring a story not done; stories are (slug, agent name, status). None if none.
#   last_seen(events) -> {target: epoch} of each target's newest line in events.tsv, read once.
#   stall_age(seen, slug, name, signs) -> minutes since the newest of: seen[slug] or seen[name]
#     (started, findings sent ...) and each of signs: epoch seconds (a worktree's last commit, the
#     time a wait began) or ISO times (a PR's updatedAt). None when there is no sign at all.
#   A working builder whose stall_age reaches stall_minutes is stalled?.
STALL_PY='
import datetime, re, time
def story_for(name, stories):
    base = re.sub(r"-done\d*$", "", name)
    hits = [s for s in stories if s[1] == base]
    hits.sort(key=lambda s: s[2] == "done")
    return hits[0][0] if hits else None
def epoch(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        try:
            return datetime.datetime.fromisoformat(str(x).replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
def last_seen(events):
    seen = {}
    try:
        for l in open(events, encoding="utf-8", errors="replace"):
            f = l.rstrip("\n").split("\t")
            t = epoch(f[0]) if len(f) == 5 else None
            if t is not None and t > seen.get(f[2], 0):
                seen[f[2]] = t
    except OSError:
        pass
    return seen
def stall_age(seen, slug, name, signs):
    ts = [t for t in [seen.get(slug), seen.get(name)] + [epoch(x) for x in signs if x] if t is not None]
    return int((time.time() - max(ts)) // 60) if ts else None
'

# own_panes — the herdr panes this project opened (next_pane records "<pane> [name]" per tab in
# STATE_DIR). herdr lists every project's agents; a pane id says which are this project's.
# Only lines shaped like a tab record ("<pane> [name]", a pane id like w1:p6K) count: STATE_DIR also
# holds codex briefs, watch-seen and .tmp files, and a list of those to skip would fail open.
own_panes() {
  cat "${STATE_DIR}"/* 2>/dev/null | awk 'NF <= 2 && $1 ~ /^[A-Za-z0-9]+:[A-Za-z0-9]+$/ {print $1}'
}

require_herdr() { [[ "${HERDR_ENV:-}" == 1 ]] || die "not running inside a herdr pane (HERDR_ENV != 1)"; }

# require_trusted <cwd> — stop unless Claude Code already trusts <cwd>. In an untrusted folder,
# Claude Code opens its "do you trust this folder?" prompt, and the agent stalls there unseen.
# Claude Code keys trust on the git root, and for a worktree on its main checkout, so a new story
# worktree is covered once its repo is trusted. Outside git, a trusted ancestor covers it. Trust
# lives in ~/.claude.json, which every running session rewrites, so this only reads it; if the
# file cannot be read, the start goes ahead.
require_trusted() {
  local cwd="$1" in_git="" root gitdir common
  if root=$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null); then
    in_git=git
    # A linked worktree's git dir differs from the shared one: trust is keyed on the main checkout.
    # A submodule's are the same (.git/modules/<name>), so it keeps its own top level.
    gitdir=$(git -C "${cwd}" rev-parse --path-format=absolute --git-dir)
    common=$(git -C "${cwd}" rev-parse --path-format=absolute --git-common-dir)
    [[ "${gitdir}" == "${common}" ]] || root="$(dirname "${common}")"
  else
    root="$(cd "${cwd}" && pwd -P)"
  fi
  python3 - "${root}" "${CLAUDE_CONFIG_DIR:-${HOME}}/.claude.json" "${in_git}" <<'PY' \
    || die "Claude Code does not trust ${root} yet, so the agent would stall on its trust prompt. Run claude in ${root} once, accept the prompt, then try again."
import json, os, sys
root, config, in_git = sys.argv[1], sys.argv[2], sys.argv[3] == "git"
try:
    projects = json.load(open(config)).get("projects", {})
except (OSError, ValueError):
    sys.exit(0)
paths = [root]
while not in_git and os.path.dirname(paths[-1]) != paths[-1]:
    paths.append(os.path.dirname(paths[-1]))
sys.exit(0 if any(projects.get(p, {}).get("hasTrustDialogAccepted") is True for p in paths) else 1)
PY
}

# next_pane <tab-label> <cwd> — a fresh shell pane in a tab with room, creating tabs as needed.
# prune_dead_panes <state> — drop the panes herdr no longer has (closed by hand), so the next split
# targets a live pane. Left alone when herdr cannot list its panes.
prune_dead_panes() {
  local live
  live=$(herdr pane list 2>/dev/null | json "' '.join(p['pane_id'] for p in d['result']['panes'])" 2>/dev/null) || return 0
  awk -v live=" ${live} " 'index(live, " " $1 " ")' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

next_pane() {
  local label="$1" cwd="$2" name="${3:-}" n=1 state panes count pane
  mkdir -p "${STATE_DIR}"
  while :; do
    local tab_label="${label}"; [[ ${n} -gt 1 ]] && tab_label="${label}-${n}"
    state="${STATE_DIR}/${tab_label}"
    [[ -f "${state}" ]] && prune_dead_panes "${state}"
    count=0; [[ -f "${state}" ]] && count=$(wc -l < "${state}" | tr -d ' ')
    if [[ ${count} -lt ${PANES_PER_TAB} ]]; then
      if [[ ${count} -eq 0 ]]; then
        pane=$(herdr tab create --workspace "${HERDR_WORKSPACE_ID}" --cwd "${cwd}" --label "${tab_label}" --no-focus \
          | json "d['result']['root_pane']['pane_id']")
      else
        # 2x2: 2nd splits the first to the right, 3rd splits the first down, 4th splits the second down.
        read -r -a panes <<< "$(awk '{ print $1 }' "${state}" | tr '\n' ' ')"
        case ${count} in
          1) pane=$(herdr pane split "${panes[0]}" --direction right --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          2) pane=$(herdr pane split "${panes[0]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          3) pane=$(herdr pane split "${panes[1]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
        esac
      fi
      [[ -n "${pane}" ]] || die "herdr could not open a pane in tab ${tab_label}"
      [[ -z "${name}" ]] || herdr pane rename "${pane}" "${name}" >/dev/null 2>&1 || true
      echo "${pane}${name:+ ${name}}" >> "${state}"
      echo "${pane}"
      return
    fi
    n=$((n + 1))
  done
}

start_agent() {
  local tab="$1" name cwd="$3" role="$4" prompt_file="$5" pane_name="${6:-$2}" kind model effort pane
  name="$(agent_name "$2")"   # the one place names are mapped, so `wait <same name>` always finds it
  [[ -f "${prompt_file}" ]] || die "no prompt file ${prompt_file}"
  read -r kind model effort <<< "$(policy "${role}")"
  # Before the pane opens, so a refusal leaves no empty pane behind.
  if [[ "${kind}" == claude ]]; then require_trusted "${cwd}"; fi
  free_agent_name "${name}"
  pane=$(next_pane "${tab}" "${cwd}" "${pane_name}")
  # A freshly split pane is not always an available shell yet (agent_pane_busy): retry once.
  local try out
  for try in 1 2; do
    if [[ "${kind}" == codex ]]; then
      # No update check: codex's startup prompt to upgrade takes the pane, and the brief then
      # lands in a bare shell. A planning codex must write its one answer file, and read-only made it
      # ask the user for every write: it runs workspace-write rooted (-C) at its tab's output dir, so
      # it reads as before and writes only there. Any other tab stays read-only. Hooks off: codex
      # opens a review dialog for an untrusted hook (herdr's, ~/.codex/hooks.json) when the brief
      # starts the session, and the brief is lost behind it. Off trusts nothing; none runs here.
      local sandbox=(-s read-only) dir
      dir="$(codex_out_dir "${tab}")"
      if [[ -n "${dir}" ]]; then mkdir -p "${dir}"; sandbox=(-s workspace-write -C "${dir}"); fi
      out=$(herdr agent start "${name}" --kind codex --pane "${pane}" --timeout 60000 -- \
        "${sandbox[@]}" -c features.hooks=false -c "model_reasoning_effort=\"${effort}\"" -c check_for_update_on_startup=false 2>&1) && break
    else
      # merge = human: no agent can run `gh pr merge`. `gh api` could still merge, so the briefs say it too.
      local guard=()
      [[ "${CFG_merge}" == human ]] && guard=(--disallowedTools "Bash(gh pr merge:*)")
      out=$(herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- \
        --model "${model}" --effort "${effort}" --permission-mode auto ${guard[@]+"${guard[@]}"} 2>&1) && break
    fi
    if [[ ${try} -eq 2 ]]; then
      # Close the pane rather than leave an empty shell; next_pane prunes it from the tab record.
      herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
      die "${name}: herdr could not start the agent: ${out}"
    fi
    sleep 3
  done
  if [[ "${kind}" == codex && -n "$(codex_out_dir "${tab}")" ]]; then
    # Its working directory is the output dir, so say where the brief's relative paths start.
    local brief="${STATE_DIR}/brief-${name}.md"
    mkdir -p "${STATE_DIR}"
    { echo "The project is ${PROJECT_DIR}; every relative path below is relative to it. You can write only in $(codex_out_dir "${tab}")."; echo; cat "${prompt_file}"; } > "${brief}"
    prompt_file="${brief}"
  fi
  deliver_prompt "${name}" "${prompt_file}" "${pane}"
  record_agent "${role}" "${name}" "${kind}" "${model}" "${effort}" "${pane}"
  echo "${name} ${pane} ${kind}:${model}:${effort}"
}

# codex_out_dir <tab> — where a planning tab's agents write their answers: .swarm/<epic> for
# scope-<epic>, .swarm/<hld> for plan-<hld>; empty for any other tab.
codex_out_dir() {
  case "$1" in
    scope-?*) echo "${PROJECT_DIR}/.swarm/${1#scope-}" ;;
    plan-?*)  echo "${PROJECT_DIR}/.swarm/${1#plan-}" ;;
  esac
}

# AGENTS_LOG: one line per agent started (date, role, name, kind, model, effort, session), so
# `cost` can attribute every token to a role. Beside state/, not in it: state/ holds tab records.
AGENTS_LOG="${PROJECT_DIR}/.swarm/agents.tsv"

# session_for_pane <pane> — the Claude session id herdr reports for the agent in <pane>, or nothing.
session_for_pane() {
  herdr agent list 2>/dev/null | json "next(((a.get('agent_session') or {}).get('value','') for a in d['result']['agents'] if a.get('pane_id')=='$1'),'')" 2>/dev/null || true
}

record_agent() {
  local role="$1" name="$2" kind="$3" model="$4" effort="$5" pane="$6" session
  session="$(session_for_pane "${pane}")"
  mkdir -p "$(dirname "${AGENTS_LOG}")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "${role}" "${name}" "${kind}" "${model}" "${effort}" "${session:--}" >> "${AGENTS_LOG}"
}

# EVENTS_LOG: an append-only audit of every command that changes state, one line each (time, command,
# target, the actor's herdr pane, outcome). Names and paths only, never a brief's or a message's contents.
EVENTS_LOG="${PROJECT_DIR}/.swarm/events.tsv"

# record_event <command> <target> [outcome] — append one line. A log that cannot be written never
# fails the command it records.
record_event() {
  local x fields=()
  for x in "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:--}" "${HERDR_PANE_ID:--}" "${3:-ok}"; do fields+=("${x//[$'\t\n\r']/ }"); done
  { mkdir -p "${EVENTS_LOG%/*}" && printf '%s\t%s\t%s\t%s\t%s\n' "${fields[@]}" >> "${EVENTS_LOG}"; } 2>/dev/null || true
}

# The outer loop: every review finding someone fixed is logged by kind, so a kind that keeps coming
# back across PRs can become a standing rule in the project's brief. Rules are proposed, never written.
FINDINGS_LOG_NAME="findings.tsv"
LESSON_MIN_PRS=3           # the rule of three: a kind in this many distinct PRs is a candidate rule
LESSON_RECENT_DAYS=90      # a candidate's kind must have been fixed this recently: an old pattern is not news
BRIEF_MAX_BYTES=4096       # past this, the brief every agent reads is too long to stay read; prune by hand

# record_finding <kind> <pr-url> <text> — log one fixed finding.
record_finding() {
  local kind="$1" pr="$2" text="$3"
  [[ -n "${kind}" && -n "${pr}" && -n "${text//[[:space:]]/}" ]] || die "usage: swarm.sh log-finding <kind> <pr-url> <one line>"
  [[ "${kind}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#kind} -le 32 ]] \
    || die "kind '${kind}' must be short kebab-case (32 characters at most), like vacuous-test"
  text="${text:0:200}"
  [[ "${pr}" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+(/[^[:space:]]*)?$ || "${pr}" =~ ^[^/#[:space:]]+/[^/#[:space:]]+#[0-9]+$ ]] \
    || die "pr '${pr}' must be a PR URL or owner/repo#N, so the same PR always counts once"
  mkdir -p "${PROJECT_DIR}/.swarm"
  printf '%s\t%s\t%s\t%s\n' "$(date +%F)" "${kind}" "${pr//[$'\t\n\r']/ }" "${text//[$'\t\n\r']/ }" \
    >> "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}"
  echo "recorded ${kind}"
}

# lessons [--all] — the "brief" below is lessons_file (default the brief itself).
# Kinds fixed in at least LESSON_MIN_PRS distinct PRs, recently, that the brief has
# no rule for (candidates), and a brief that has grown too long. A rule in the brief carries its kind
# as <!-- lesson: <kind> -->. The brief is read from the default branch, where adopted rules land; a
# declined rule is a closed 'lesson: <kind>' PR, which /swarm checks before proposing. A lead's memory
# (Claude Code's per-project memory directory, which builders in their own worktrees never see) that
# carries `lesson: <kind>` in its frontmatter is a candidate too, until the brief rules that kind. There is no staleness check: the log is local while the brief is committed, and a
# rule that works stops its own findings, so "quiet" cannot tell a working rule from an unneeded one.
lessons_report() {
  [[ -z "${1:-}" || "${1}" == --all ]] || die "usage: swarm.sh lessons [--all]"
  # Claude Code keys memory on the repo root (the cwd outside git), not on a project's subdirectory.
  local key; key="$(git -C "${PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || echo "${PROJECT_DIR}")"
  local memory="${SWARM_MEMORY_DIR:-${CLAUDE_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/projects}/${key//[^A-Za-z0-9]/-}/memory}"
  # The size cap is the brief's, the file pasted into every prompt; a lessons_file like AGENTS.md
  # is long by design and loaded by the agents themselves.
  python3 - "${PROJECT_DIR}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${LESSONS_FILE}" \
    "${LESSON_MIN_PRS}" "${LESSON_RECENT_DAYS}" "${BRIEF_MAX_BYTES}" "${1:-}" "${memory}" "${PROJECT_BRIEF}" <<'PY'
import collections, datetime, glob, os, re, subprocess, sys
project, log, brief, min_prs, recent_days, max_bytes, flag, memory, swarm_brief = sys.argv[1:10]
min_prs, recent_days, max_bytes = int(min_prs), int(recent_days), int(max_bytes)
cutoff = (datetime.date.today() - datetime.timedelta(days=recent_days)).isoformat()

def pr_key(pr):
    # One PR, however it was written: https://github.com/o/r/pull/12[/...], o/r#12, or as given.
    m = re.search(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)", pr) or re.fullmatch(r"\s*([^/\s#]+/[^/\s#]+)#(\d+)\s*", pr)
    return f"{m.group(1).lower()}#{m.group(2)}" if m else pr.strip().rstrip("/")

def adopted(kind):
    # The day the kind's current rule landed on the default branch, from git; "" when it cannot be told.
    # The tag is searched as written in the brief, and the newest commit that changed its count is taken:
    # the rule is present now, so that commit is its latest addition (a rule pruned and re-added is new).
    tag, path = tags.get(kind, ("", ""))
    if not tag or not path:
        return ""
    got = subprocess.run(["git", "-C", project, "log", "--format=%cs", "-S", tag, "origin/HEAD", "--",
                          f":(top){path}"], capture_output=True, text=True)
    return got.stdout.split()[0] if got.returncode == 0 and got.stdout.strip() else ""

def read_brief(brief=brief):
    # The brief on the default branch, where adopted rules land. git paths are from the repo root,
    # so the project's own prefix is added for a project in a subdirectory of its repo.
    prefix = subprocess.run(["git", "-C", project, "rev-parse", "--show-prefix"], capture_output=True, text=True)
    path = prefix.stdout.strip() + os.path.relpath(brief, project)
    got = subprocess.run(["git", "-C", project, "show", f"origin/HEAD:{path}"], capture_output=True)
    if got.returncode == 0:
        return got.stdout.decode("utf-8", errors="replace"), "", path
    if not os.path.exists(brief):
        return "", "", ""
    note = f"note: no {os.path.relpath(brief, project)} on origin/HEAD, so it was read from the working tree (any branch)"
    return open(brief, encoding="utf-8", errors="replace").read(), note, ""

prs, recent, dated = collections.defaultdict(set), collections.defaultdict(set), collections.defaultdict(list)
last, example = {}, {}
if os.path.exists(log):
    for line in open(log, encoding="utf-8", errors="replace", newline="\n"):
        parts = line.rstrip("\n").split("\t")
        try:
            when = datetime.date.fromisoformat(parts[0]) if len(parts) == 4 and re.fullmatch(r"\d{4}-\d{2}-\d{2}", parts[0]) else None
        except ValueError:
            when = None
        if when is None or when > datetime.date.today():
            continue  # a malformed, impossible or future row must not count, least of all as recent
        _, kind, pr, finding = parts
        day = when.isoformat()
        prs[kind].add(pr_key(pr)); last[kind] = max(last.get(kind, ""), day); example[kind] = finding
        dated[kind].append((day, pr_key(pr)))
        if day >= cutoff:
            recent[kind].add(pr_key(pr))  # only PRs inside the window count toward a candidate
brief_text, note, brief_path = read_brief()
# The brief is pasted into every prompt, so a rule it still tags rules its kind too. Each kind keeps
# its tag as written and the file it is in, for its adoption date.
cap_text, cap_note, cap_path = (brief_text, "", brief_path) if swarm_brief == brief else read_brief(swarm_brief)
tags = {}
for text, path in ((cap_text, cap_path), (brief_text, brief_path)):  # lessons_file wins a kind in both
    tags.update({m.group(1): (m.group(0), path) for m in re.finditer(r"<!--\s*lesson:\s*([a-z0-9-]+)\s*-->", text)})
ruled = set(tags)
out = []
for kind in sorted(prs, key=lambda k: -len(prs[k])):
    n_recent = len(recent[kind])
    if flag == "--all":
        out.append(f"{kind}\t{len(prs[kind])} PR(s)\t{n_recent} in the last {recent_days} days\t{'ruled' if kind in ruled else ''}")
    elif n_recent >= min_prs and kind not in ruled:
        out.append(f"candidate {kind}: fixed in {n_recent} PRs in the last {recent_days} days, last {last[kind]}; e.g. {example[kind]}")
    elif kind in ruled:
        since = adopted(kind)
        after = {pr for day, pr in dated[kind] if since and day > since}
        if len(after) >= min_prs:
            out.append(f"recurring {kind}: fixed in {len(after)} PRs since its brief rule landed on {since}; "
                       "the rule is not working: turn it into a step agents must do, or drop it")
for path in sorted(glob.glob(os.path.join(memory, "*.md"))):
    # Only the frontmatter is read, and only a tagged memory is named: the rest of memory stays private.
    try:
        head = re.match(r"---\n(.*?)\n---", open(path, encoding="utf-8", errors="replace").read(), re.S)
    except OSError:
        continue  # an unreadable entry must not cost the rest of the report
    tag = head and re.search(r"^\s*lesson:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*$", head.group(1), re.M)
    if tag and tag.group(1) not in ruled and flag != "--all" and not any(l.startswith(f"candidate {tag.group(1)}:") for l in out):
        out.append(f"candidate {tag.group(1)}: from the lead's memory {path}; draft the rule from it")
# The cap measures what every prompt carries: the brief, plus lessons_file's tagged lines when it is
# another file (project_rules pastes those too).
pasted = "" if swarm_brief == brief else "\n".join(re.findall(r"^.*<!--\s*lesson:\s*[a-z0-9-]+\s*-->.*$", brief_text, re.M))
size = len((cap_text + pasted).encode("utf-8", errors="surrogateescape"))
if size > max_bytes:
    where = (f"origin/HEAD:{cap_path}" if cap_path else swarm_brief) + (" plus lessons_file's rules" if pasted else "")
    out.append(f"long brief: {where} is {size} bytes, over {max_bytes}; merge or retire rules")
notes = list(dict.fromkeys(n for n in (note, cap_note) if n))
print("\n".join((out or ["no lessons: nothing has recurred in enough PRs yet"]) + notes))
PY
}

# cost [since] — tokens and estimated cost per role, for every agent this project's swarm started
# (and the calling session, as "lead", when run inside herdr). Usage comes from Claude Code's own
# session logs, deduplicated by message id; codex agents are listed but not priced (not logged here).
cost_report() {
  local lead=""
  [[ "${HERDR_ENV:-}" == 1 ]] && lead="$(session_for_pane "${HERDR_PANE_ID:-}")"
  [[ -f "${AGENTS_LOG}" || -n "${lead}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  python3 - "${AGENTS_LOG}" "${1:-0000-00-00}" "${lead}" "${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}" <<'PY'
import glob, json, os, sys
log, since, lead, projects = sys.argv[1:5]
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}
agents = []
if os.path.exists(log):
    for line in open(log):
        f = line.rstrip("\n").split("\t")
        if len(f) == 7 and f[0] >= since:
            agents.append({"role": f[1], "kind": f[3], "session": f[6]})
if lead:
    agents.append({"role": "lead", "kind": "claude", "session": lead})
rows, seen = {}, set()
for a in agents:
    r = rows.setdefault(a["role"], {"agents": 0, "models": set(), "tok": [0, 0, 0, 0], "usd": 0.0, "unpriced": 0})
    r["agents"] += 1
    paths = glob.glob(os.path.join(projects, "*", a["session"] + ".jsonl")) if a["session"] != "-" else []
    if a["kind"] != "claude" or not paths:
        r["unpriced"] += 1
        continue
    for line in open(paths[0], errors="ignore"):
        try:
            m = json.loads(line).get("message") or {}
        except ValueError:
            continue
        u, mid = m.get("usage"), m.get("id")
        if not u or not mid or mid in seen:
            continue
        seen.add(mid)
        t = [u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)]
        model = m.get("model", "?")
        r["models"].add(model)
        r["tok"] = [x + y for x, y in zip(r["tok"], t)]
        price = next((v for k, v in PRICES.items() if k in model), None)
        if price:
            r["usd"] += sum(x * p for x, p in zip(t, price)) / 1e6
def n(x):
    return f"{x/1e6:.1f}M" if x >= 1e6 else f"{x/1e3:.0f}k"
print("| role | agents | model | input | cache write | cache read | output | est. $ |")
print("|---|---|---|---|---|---|---|---|")
tot = [0, 0, 0, 0]; usd = 0.0
for role, r in sorted(rows.items(), key=lambda kv: -kv[1]["usd"]):
    tot = [x + y for x, y in zip(tot, r["tok"])]; usd += r["usd"]
    note = f" ({r['unpriced']} not in the logs)" if r["unpriced"] else ""
    print(f"| {role} | {r['agents']}{note} | {', '.join(sorted(r['models'])) or '-'} | " + " | ".join(n(x) for x in r["tok"]) + f" | {r['usd']:.2f} |")
print(f"| **total** | {sum(r['agents'] for r in rows.values())} | | " + " | ".join(n(x) for x in tot) + f" | {usd:.2f} |")
print("\nList prices; on a subscription this is plan usage, not a bill. Codex agents are not priced.")
PY
}

# deliver_prompt <name> <prompt-file> — submit the brief and confirm the agent acted on it.
# `agent start` returns once the agent is ready, but a slow starter (Fable at xhigh) could
# still drop a prompt sent at once, leaving it idle at an empty prompt while every later
# `wait` returned immediately. So the submission waits until herdr sees the agent working
# (or blocked on a question), retries once, and fails loudly rather than reporting success.
deliver_prompt() {
  local name="$1" prompt_file="$2" status target="${3:-}"
  [[ -n "${target}" ]] || target="$(own_target "${name}")"
  for _ in 1 2; do
    status=$(herdr agent prompt "${target}" "$(cat "${prompt_file}")" --wait --until working --until blocked \
      --timeout 60000 2>/dev/null | json "d.get('result',{}).get('agent',{}).get('agent_status','')" 2>/dev/null || true)
    case "${status}" in
      working|blocked) return 0 ;;
    esac
    sleep 5
  done
  die "${name}: the brief was not taken up after 2 attempts (status '${status:-none}'); see herdr agent read ${name}"
}

# API_ERROR_NUDGES: how many times one `wait` re-prompts an agent whose turn died on an API error.
# Enough to ride out a dropped stream; few enough that a hard error (a bad key) still surfaces.
API_ERROR_NUDGES=3

# ended_on_api_error <name> — true when the agent's last event (Claude Code marks each with ⏺)
# is an API error, such as "The response stopped arriving". The agent then sits idle, its work
# unfinished, and nothing else will wake it.
ended_on_api_error() {
  local target
  target="$(agent_field "$1" pane_id)"; [[ -n "${target}" ]] || return 1
  herdr agent read "${target}" --source recent-unwrapped 2>/dev/null | grep '⏺' | tail -1 | grep -q '⏺ API Error'
}

# story_commit_time <slug> — the epoch time of the last commit in a story's worktree; empty when it
# has none (not started, or its repo is not here).
story_commit_time() {
  local src
  src="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo 2>/dev/null)")" || return 0
  git -C "$(worktree_for "${src}" "$1")" log -1 --format=%ct 2>/dev/null || true
}

# story_rows — one "slug<TAB>agent name<TAB>status<TAB>prs" line per story, for STALL_PY's story_for.
story_rows() {
  local f r
  while IFS= read -r f; do
    r="$(basename "${f}" .md)"
    printf '%s\t%s\t%s\t%s\n' "${r}" "$(agent_name "${r}")" "$(fm "${f}" status)" "$(fm "${f}" prs)"
  done < <(board stories)
}

# stall_py <mode> <args...> — run STALL_PY: `story <name>` prints the agent's story (story_for, over
# story_rows); `age <slug> <name> <sign>...` prints stall_age, or nothing.
stall_py() {
  local rows=""
  [[ "$1" != story ]] || rows="$(story_rows)"
  SWARM_STALL_PY="${STALL_PY}" SWARM_STORY_ROWS="${rows}" python3 - "${EVENTS_LOG}" "$@" <<'PY'
import os, sys
exec(os.environ["SWARM_STALL_PY"])
events, mode, args = sys.argv[1], sys.argv[2], sys.argv[3:]
if mode == "story":
    rows = [l.split("\t") for l in os.environ["SWARM_STORY_ROWS"].splitlines() if l.count("\t") >= 2]
    print(story_for(args[0], rows) or "")
else:
    a = stall_age(last_seen(events), args[0], args[1], args[2:])
    print("" if a is None else a)
PY
}

# agent_stalled <name> <since> — when <name> is a story's builder that has shown no sign of life for
# stall_minutes (STALL_PY), counting <since> (epoch: when the wait began) as one, print how many
# minutes and succeed. Its PRs are asked for their updatedAt only once the rest already looks
# stalled, so gh is rarely called.
agent_stalled() {
  local slug url age ct prs=()
  slug="$(stall_py story "$1")"
  [[ -n "${slug}" ]] || return 1
  ct="$(story_commit_time "${slug}")"
  age="$(stall_py age "${slug}" "$1" "$2" "${ct}")"
  [[ -n "${age}" && "${age}" -ge "${CFG_stall_minutes}" ]] || return 1
  for url in $(fm "${BOARD}/stories/${slug}.md" prs | grep -o 'https://github.com/[^] ,"]*/pull/[0-9]*'); do
    prs+=("$(gh pr view "${url}" --json updatedAt -q .updatedAt 2>/dev/null || true)")
  done
  age="$(stall_py age "${slug}" "$1" "$2" "${ct}" "${prs[@]+"${prs[@]}"}")"
  [[ -n "${age}" && "${age}" -ge "${CFG_stall_minutes}" ]] || return 1
  echo "${age}"
}

# STALL_POLL_MS: how often `wait --stall` checks whether the agent it waits on has stalled.
STALL_POLL_MS="${SWARM_STALL_POLL_MS:-60000}"
# WAIT_STALLED: the exit code of `wait --stall` when it returns because the agent stalled.
WAIT_STALLED=3

# settle <target> <name> <timeout-ms> <since> — for `wait --stall`: herdr agent wait in
# STALL_POLL_MS steps; between steps, an agent stalled since <since> (agent_stalled) ends the wait
# with "stalled: ...". herdr's stderr goes to a file, read only to tell a step's timeout from a real
# failure; a real failure, and the last step, fail as one unbroken wait does.
settle() {
  local target="$1" name="$2" left="$3" since="$4" out err min
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-wait.XXXXXX")"
  while [[ ${left} -gt ${STALL_POLL_MS} ]]; do
    if out="$(herdr agent wait "${target}" --timeout "${STALL_POLL_MS}" 2>"${err}")"; then
      rm -f "${err}"; json "d['result']['agent']['agent_status']" <<< "${out}"; return
    fi
    grep -q '"timeout"' "${err}" || break
    left=$((left - STALL_POLL_MS))
    if min="$(agent_stalled "${name}" "${since}")"; then
      rm -f "${err}"; echo "stalled: working ${min} min with no commit or PR update"; return
    fi
  done
  rm -f "${err}"
  herdr agent wait "${target}" --timeout "${left}" | json "d['result']['agent']['agent_status']"
}

# wait_agent <name> <timeout-ms> [--stall] — block until the agent settles and print its status. An
# agent idle after an API error has not settled: tell it to carry on, and wait again. With --stall, a
# builder that shows no sign of life for stall_minutes after the wait began also ends it (settle):
# it prints "stalled: ..." and returns WAIT_STALLED. SWARM_WAIT_STARTED (epoch) overrides when the
# wait began, for tests.
wait_agent() {
  local name="$1" timeout="$2" stall="${3:-}" status nudges=0 target since
  since="${SWARM_WAIT_STARTED:-$(date +%s)}"
  target="$(own_target "${name}")" || return 1
  while :; do
    if [[ -n "${stall}" ]]; then
      status="$(settle "${target}" "${name}" "${timeout}" "${since}")"
      if [[ "${status}" == stalled:* ]]; then echo "${status}"; return "${WAIT_STALLED}"; fi
    else
      status=$(herdr agent wait "${target}" --timeout "${timeout}" | json "d['result']['agent']['agent_status']")
    fi
    # herdr reports an agent whose turn ended as idle or done; both can be an API-error stop.
    if [[ ! "${status}" =~ ^(idle|done)$ || ${nudges} -ge ${API_ERROR_NUDGES} ]] || ! ended_on_api_error "${name}"; then
      break
    fi
    nudges=$((nudges + 1))
    echo "swarm: ${name} stopped on an API error; telling it to carry on (${nudges}/${API_ERROR_NUDGES})" >&2
    herdr agent prompt "${target}" "Your last turn ended on an API error. Carry on from where you stopped." \
      --wait --until working --timeout 60000 >/dev/null 2>&1 || true
  done
  echo "${status}"
}

# wait_conductor <agent> <timeout-ms> — a conductor is idle (or done) whenever it waits on its own
# builders, so neither is settled: wait on until its report exists or it is blocked or gone.
# <timeout-ms> is the whole wait, so a conductor that stopped without a report cannot hang it.
wait_conductor() {
  local name="$1" status deadline=$((SECONDS + $2 / 1000)) poll
  while :; do
    status="$(wait_agent "${name}" "$(( (deadline - SECONDS) * 1000 > 1000 ? (deadline - SECONDS) * 1000 : 1000 ))")"
    [[ "${status}" =~ ^(idle|done)$ && ! -f "$(conductor_report "${name}")" ]] || break
    ended_on_api_error "${name}" && break   # stuck after wait_agent's nudges: never nudge again
    [[ ${SECONDS} -lt ${deadline} ]] || break
    poll="${SWARM_CONDUCTOR_POLL:-30}"; (( poll <= deadline - SECONDS )) || poll=$((deadline - SECONDS))
    sleep "${poll}"
  done
  echo "${status}"
}

# tell_agent <slug> <file> — send an agent a file's contents, such as review findings, through
# deliver_prompt (it retries, and counts a permission prompt as taken up). A header line comes first,
# so findings that begin with '-' are never read as a flag.
# It refuses an agent that is mid-turn (findings sent then would be counted as taken up at once) or
# sitting on a permission prompt (the text would land in the dialog), rather than waiting on it.
tell_agent() {
  local f="$2" name msg status
  [[ -f "${f}" ]] || die "no such file '${f}'"
  name="$(agent_name "$1")"
  status="$(agent_status "${name}")"
  case "${status}" in
    idle|done) ;;
    working) die "${name} is still working; run \`swarm.sh wait $1\` in the background, then tell it" ;;
    blocked) die "${name} is waiting on a prompt; answer it (herdr agent read ${name}), then tell it" ;;
    *) [[ -n "${status}" || -z "$(agent_field "${name}" agent_status any)" ]] || die "${name}: the agent holding this name is not one this project started; it is never told from here"
       die "could not reach ${name} (status '${status:-none}'): is its pane still open?" ;;
  esac
  msg="$(mktemp "${TMPDIR:-/tmp}/swarm-tell.XXXXXX")"
  # shellcheck disable=SC2064 # expand now: msg is local, and deliver_prompt may exit through die
  trap "rm -f '${msg}'" EXIT
  { echo "From the conductor:"; echo; cat "${f}"; } > "${msg}"
  deliver_prompt "${name}" "${msg}"
  echo "told ${name}"
}

# The merge, signing and review rules, shared by the briefs.
merge_rule() {
  if [[ "${CFG_merge}" == human ]]; then echo "Never merge, by any route (a human merges)."
  else echo "Never merge (the lead merges)."; fi
}
sign_rule() { echo "Sign every commit and merge with -S. If signing fails, stop and report that you are blocked; never commit unsigned."; }
sign_rule_if_on() { [[ "${CFG_sign_commits}" != true ]] || printf '\n\n%s' "$(sign_rule)"; }
review_bot_rule() {
  [[ "${CFG_review_bot}" == auto ]] || return 0
  printf '\n\nThen run the PR review bot of the repo as %s/docs/review.md says, and clear its findings the same way.' "${SWARM_HOME}"
}
# The review every story's PR (or branch) passes before its builder is closed. The builder keeps its
# context until then, so findings go back to it rather than to a fresh agent that has none.
# review_rule — for pr_per=story, where each story has its own PR and its builder stays open.
review_rule() {
  cat <<EOF
A story is reviewed only when its latest head has passed \`codex exec review --base origin/<base>\`
in its worktree, and, when it changes code (not only docs, board files or a dependency bump), the
/code-review skill on its PR (\`/code-review <PR>\`). If codex
reports a usage limit, do not wait for it: rely on the other review and your own reading of the
diff, and say "codex skipped: usage limit" in the PR. Send every real finding to the story's
builder with \`${SWARM_HOME}/bin/swarm.sh tell <slug> <file>\` (a file holding the findings and
what to decline), wait for it, and review the new head. Stop at the first pass on the latest head
with nothing substantive: one that finds only nits, edge cases outside the story, or points already
declined is such a pass, even if it is not empty. Rebut what it found in the PR with a reason. Never merge a story, and never run \`swarm.sh close <slug>\` on its builder, before
its latest head has passed.

$(finding_rule)
EOF
}

# finding_rule — every fixed finding feeds the outer loop (swarm.sh lessons).
finding_rule() {
  local proj sw
  proj="$(printf '%q' "${PROJECT_DIR}")"; sw="$(printf '%q' "${SWARM_HOME}/bin/swarm.sh")"
  cat <<EOF
Log each finding that was fixed (not the ones rebutted), from any directory, with:

    SWARM_PROJECT=${proj} ${sw} log-finding <kind> <PR URL> "<one line>"

The kind is a short kebab-case name for the class of mistake, not this instance (vacuous-test,
denylist, docs-misstate-code, fails-open); reuse one that
\`SWARM_PROJECT=${proj} ${sw} lessons --all\` already lists when it fits.
EOF
}
conduct_merge_rule() {
  if [[ "${CFG_merge}" == human ]]; then
    cat <<'RULE'
Never merge a PR, by any route: not `gh pr merge`, not `gh api`, not the web page. A human merges.
When a story's PR is green and reviewed, run `swarm.sh review <slug> <PR URL>` and
`swarm.sh close <slug>`, then carry on with stories that do not wait on it. A story that does wait
stays blocked until the human merges and `/swarm` reconciles the board. When every story left
in the epic is in review and the epic's **Done when** will hold once they merge, run
`swarm.sh review <epic> <every PR URL still waiting>`: the epic leaves the board once they all merge.
RULE
  else
    cat <<'RULE'
Merge a PR only when it is green and reviewed, then run `swarm.sh unblock` and `swarm.sh close <slug>` to close
that story's tab. If a merged story is still open on the board once you have pulled (its file is
there and not `status: done`), run `swarm.sh finish <slug>` first. When the epic's **Done when**
holds, take the epic off the board with `swarm.sh finish <epic>`.
RULE
  fi
}

# A test that passes with its fix removed proves nothing; a builder shows each one can fail.
mutation_rule() {
  printf '%s' "For a code change, prove each new or changed test can fail: back up the file you fixed with cp, break the fix, see the test fail, then restore it with cp (never git checkout, which drops uncommitted work), and note which test failed and how."
}

# The brief every story builder gets. The story file is the task; these are the rules.
story_brief() {
  local slug="$1" src="$2" base="$3" epic_branch="${4:-}" story_ref cleanup rel epic check extra="" before
  if [[ -n "${epic_branch}" ]]; then
    story_ref="${BOARD}/stories/${slug}.md"
    [[ ${BOARD_IN_REPO} == 1 && "${src}" == "${PROJECT_DIR}" ]] && story_ref="${BOARD#"${PROJECT_DIR}/"}/stories/${slug}.md"
    cleanup="Do not touch the story file; the conductor takes it off the board."
  elif [[ "${src}" == "${PROJECT_DIR}" && ${BOARD_IN_REPO} == 1 ]]; then
    # The board is in this repo: the PR takes the story off it.
    rel="${BOARD#"${PROJECT_DIR}/"}/stories"
    story_ref="${rel}/${slug}.md"
    if [[ "${CFG_finished}" == mark ]]; then
      cleanup="In your PR, set \`status: done\` in ${rel}/${slug}.md, and change nothing else under ${rel}/."
    else
      cleanup="Delete ${rel}/${slug}.md in your PR, and nothing else under ${rel}/."
    fi
  else
    # The board is elsewhere: read the story there, and leave it for the lead.
    story_ref="${BOARD}/stories/${slug}.md (this worktree is $(basename "${src}"))"
    cleanup="Do not touch the story file; the lead takes it off the board after your PR merges."
  fi
  if [[ -n "${epic_branch}" ]]; then
    before="reply"
    cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} $(merge_rule) Never touch real cloud or
credentials. This project opens one PR per epic, so open no PR: commit on your branch,
story/${slug}, and push it; the conductor merges it into \`${epic_branch}\`. Run
\`codex exec review --base origin/${epic_branch}\` before committing; fix real findings, decline
nits with a reason, and converge on one clean pass. If codex reports a usage limit, do not wait for
it to reset: carry on without it and say so. Run the repo's tests and make them pass. $(mutation_rule)
When your branch is pushed, reply with the branch, what changed in three lines, the codex findings
and the mutation, then stop.
EOF
  else
    before="open the PR"
    cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit and PR with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} $(merge_rule) Never touch real cloud or
credentials. Open the PR against \`${base}\`. Run \`codex exec review --base origin/${base}\` before
committing; fix real findings, decline nits with a reason, converge on one clean pass, and record the
loop in the PR body. If codex reports a usage limit, do not wait for it to reset: carry on without it
and write "codex skipped: usage limit" in the PR body. If \`gh pr view --json mergeable\` says
CONFLICTING, merge origin/${base} into your branch, resolve it (keep both sides of any list), re-run
the tests and push: a conflicted PR runs no checks and waits forever. $(mutation_rule) Record it
in the PR body. When CI is green, reply with the PR URL, what changed in three lines, and the codex
findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR.
EOF
  fi
  epic="$(fm "${BOARD}/stories/${slug}.md" epic)"
  check=""; [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || extra+="Before you ${before}, also run the epic's check from the worktree root, and make it pass: \`${check}\`"$'\n'
  [[ "${CFG_sign_commits}" != true ]] || extra+="$(sign_rule)"$'\n'
  [[ -z "${extra}" ]] || printf '%s' "${extra}"
  local rules; rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\n%s\n' "${rules}"
}

# project_rules — the brief, then, when lessons_file is another file, only its tagged rule lines: a
# builder in another repo's worktree never reads this project's AGENTS.md.
project_rules() {
  [[ ! -f "${PROJECT_BRIEF}" ]] || { cat "${PROJECT_BRIEF}"; echo; }   # a brief may lack its final newline
  [[ "${LESSONS_FILE}" == "${PROJECT_BRIEF}" ]] || grep -hE -- '<!--[[:space:]]*lesson:[[:space:]]*[a-z0-9-]+[[:space:]]*-->' "${LESSONS_FILE}" 2>/dev/null || true
}

# agent_kind — true for a kind a swarm agent may build; an empty kind means code. Anything else,
# lead or a typo, stays with the lead, so an unknown kind can never reach an agent.
agent_kind() {
  case "$1" in ""|code|docs|chore|verify) return 0 ;; *) return 1 ;; esac
}

build_story() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind risk repo src role wt branch prompt base epic from epic_branch
  [[ -f "${story}" ]] || die "no story ${story}"
  grep -q '^status: ready$' "${story}" || die "${slug} is not status: ready"
  kind=$(sed -n 's/^kind: *//p' "${story}" | head -1); kind="${kind:-code}"
  case "${kind}" in
    code|docs|chore|verify) ;;
    lead) die "${slug} is kind: lead — real cloud, credentials or a human step; the lead runs it, not a swarm agent" ;;
    operator) die "${slug} is kind: operator, which is now kind: lead: change it, and mark the user's step **You:**" ;;
    *) die "${slug} has kind: ${kind}; an agent builds only code, docs, chore or verify" ;;
  esac
  risk=$(sed -n 's/^risk: *//p' "${story}" | head -1)
  repo=$(sed -n 's/^repo: *//p' "${story}" | head -1)   # a repo in repos_dir; empty is the project's own
  role="${kind}"; [[ "${kind}" == code && "${risk}" == high ]] && role=code-risky
  policy "${role}" >/dev/null
  src="$(repo_dir "${repo}")" || die "${slug}: ${src}"
  # Before the epic branch and the worktree exist, so a refusal leaves nothing to clean up.
  require_trusted "${src}"
  base="$(base_for "${src}")"
  epic="$(fm "${story}" epic)"; from="origin/${base}"; epic_branch=""
  if [[ "${CFG_pr_per}" == epic && -n "${epic}" ]]; then
    [[ -f "${BOARD}/epics/${epic}.md" ]] || die "${slug}: no epic ${BOARD}/epics/${epic}.md"
    epic_branch="$(epic_branch_for "${src}" "${epic}" "${base}")"; from="origin/${epic_branch}"
    add_epic_repo "${epic}" "${repo:-$(basename "${PROJECT_DIR}")}"
  fi
  branch="story/${slug}"; wt="$(worktree_for "${src}" "${slug}")"
  git -C "${src}" worktree add -q -b "${branch}" "${wt}" "${from}"
  prompt="${PROJECT_DIR}/.swarm/briefs/${slug}.md"; mkdir -p "$(dirname "${prompt}")"
  story_brief "${slug}" "${src}" "${base}" "${epic_branch}" > "${prompt}"
  # An epic's story gets a pane in the epic's tab; a one-off gets a tab of its own.
  start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}"
}

# epic_branch_for <repo-dir> <epic> <base> — epic/<epic>, fetched from origin; pushed there from
# <base> the first time a story of the epic is built in that repo.
epic_branch_for() {
  local src="$1" b="epic/$2"
  if ! git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" 2>/dev/null; then
    git -C "${src}" push -q origin "refs/remotes/origin/$3:refs/heads/${b}" || die "${src}: cannot push ${b}"
    git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}"
  fi
  echo "${b}"
}

# add_epic_repo <epic> <repo> — list <repo> on the epic's repos: line, the repos with an epic
# branch. It is how a fresh conductor finds the branches, and how `next` sees a stalled epic.
add_epic_repo() {
  local f="${BOARD}/epics/$1.md"
  [[ " $(fm "${f}" repos) " == *" $2 "* ]] && return 0
  awk -v r="$2" '
    /^---$/ { n++ }
    n == 1 && /^repos:/ { print $0 " " r; d = 1; next }
    n == 2 && !d { print "repos: " r; d = 1 }
    { print }' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
}

# The brief a conductor gets: one epic, from a fresh session, so its context holds only that epic.
conduct_brief() {
  local epic="$1"
  cat <<EOF
You are the conductor for the epic ${BOARD}/epics/${epic}.md. Read AGENTS.md (and STATUS.md if there
is one), ${SWARM_HOME}/docs/method.md and the epic first.

EOF
  if [[ "${CFG_pr_per}" == epic ]]; then conduct_epic_mode "${epic}"; else conduct_story_mode "${epic}"; fi
  cat <<EOF

Stay inside this epic: start no story outside it, and leave the HLD and other epics alone. A
story whose \`kind\` is set and is not code, docs, chore or verify (a \`lead\` story: real cloud, credentials, a human step) is not yours to run; list it
for the user. Stop when the epic's **Done when** holds or when nothing ready is left.
EOF
  local rules; rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\nThe project'"'"'s rules, which every builder also gets:\n\n%s\n' "${rules}"
  cat <<EOF

Your last act, after everything else: write your report (what merged, what is left, what waits on
the user) to ${PROJECT_DIR}/.swarm/conduct-${epic}.report.md, then reply with the same. The lead
treats that file as the only sign you have finished: being idle while you wait on your own
background work is not.
EOF
}

# The green rule every conductor follows, whatever it opens PRs for.
green_rule() {
  cat <<EOF
A PR is green only when every check on its head has passed and you have triaged the output of
\`${SWARM_HOME}/bin/swarm.sh findings <repo> <pr>\`: the notes on every check run, whatever its
conclusion, and open code-scanning alerts. Fix each real one; rebut the rest with a reason in the
PR (scanners often flag a name, not a value). Never change code only to silence a scanner, and
never dismiss an alert.$(review_bot_rule)
EOF
}

# pr_per = story: a PR per story.
conduct_story_mode() {
  local epic="$1"
  cat <<EOF
Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) to merge, as method.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap,
start each with \`${SWARM_HOME}/bin/swarm.sh story <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch --epic ${epic}\` in the background, and review each PR. Each story's base branch is in its brief,
.swarm/briefs/<slug>.md.

$(green_rule)

$(review_rule)

$(conduct_merge_rule)$(sign_rule_if_on)
EOF
}

# pr_per = epic: stories merge into epic/<epic>, and each repo gets one PR for the whole epic.
conduct_epic_mode() {
  local epic="$1" check sign="" merge_step tick='`'
  check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || check=" and the epic check ${tick}${check}${tick}"
  [[ "${CFG_sign_commits}" != true ]] || sign=" -S"
  if [[ "${CFG_merge}" == human ]]; then
    merge_step="Never merge a PR, by any route: not \`gh pr merge\`, not \`gh api\`, not the web page. A human
merges. When every PR is green and reviewed, run \`swarm.sh review ${epic} <every PR URL>\`."
  else
    merge_step="Merge each PR once it is green and reviewed, then run \`swarm.sh finish ${epic}\`."
  fi
  cat <<EOF
This project opens one PR per epic, not per story. \`${SWARM_HOME}/bin/swarm.sh story <slug>\`
starts each builder on story/<slug>, branched from epic/${epic}; builders push their branch and open
no PR. Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) as method.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap, start each,
and wait with \`swarm.sh wait <slug>\` in the background.

When a builder reports, review its branch. Then, one story at a time, merge it into the epic branch
in a worktree of epic/${epic} beside its repo (../<repo>-wt/epic-${epic}):
\`git merge --no-ff${sign} origin/story/<slug>\`, run the repo's tests${check} there,
and push epic/${epic}. Then run \`swarm.sh finish <slug>\`, \`swarm.sh unblock\` and
\`swarm.sh close <slug>\`, and go on to the next wave.

When the epic's stories are all finished (a fresh conductor may start here; the epic's \`repos:\`
line lists every repo with an epic branch), review the whole epic: in each repo's epic worktree,
\`codex exec review --base origin/<base>\`, where \`swarm.sh base <repo>\` prints the base. Fix real
findings on the epic branch and rebut the rest. Then open one PR per repo from epic/${epic} into its
base, written for a reader who knows nothing of how it was built: what changes and why, with no
waves, stories or board names. If a PR from epic/${epic} is already open, update its body instead,
keeping any structure someone wrote by hand. Wait on the PRs with \`swarm.sh watch --epic ${epic}\`
in the background.

$(green_rule)

An epic PR that changes code is reviewed only once the /code-review skill (\`/code-review <PR>\`)
has also passed on it, its real findings fixed on the epic branch and the rest rebutted in the PR.

$(finding_rule)

${merge_step}$(sign_rule_if_on)
EOF
}

# hld_workspace <label> — the herdr workspace labelled <label>, created if there is none. Every epic
# of one HLD shares it; a new workspace's placeholder tab is closed once the caller has added its own.
hld_workspace() {
  local label="$1" ws
  ws=$(herdr workspace list | json "next((w['workspace_id'] for w in d['result']['workspaces'] if w.get('label')=='${label}'),'')")
  if [[ -z "${ws}" ]]; then
    ws=$(herdr workspace create --label "${label}" --cwd "${PROJECT_DIR}" --no-focus \
      | json "d['result']['workspace']['workspace_id']+' '+d['result']['tab']['tab_id']")
  fi
  echo "${ws}"
}

# conductor_report <agent> — where a conductor writes its report as its last act.
conductor_report() { echo "${PROJECT_DIR}/.swarm/conduct-$(conduct_epic "$1").report.md"; }

# conduct_epic <agent> — the epic a conductor's agent name is for. The name may be cut at 32
# characters, so it is matched against the conductors started here (their briefs), which outlive
# the epic's own file. Two long epics can share a cut name; the newest brief is the one running.
conduct_epic() {
  local f e want
  want="$(agent_name "$1")"
  # shellcheck disable=SC2012 # newest first; brief names are epic slugs, [a-z0-9-]
  while IFS= read -r f; do
    e="$(basename "${f}" .md)"; e="${e#conduct-}"
    [[ "$(agent_name "conduct-${e}")" == "${want}" ]] && { echo "${e}"; return; }
  done < <(ls -t "${PROJECT_DIR}/.swarm/briefs"/conduct-*.md 2>/dev/null)
  echo "${want#conduct-}"
}

start_conductor() {
  local epic="$1" epic_file="${BOARD}/epics/$1.md" hld prompt ws placeholder
  [[ "${epic}" =~ ^[a-z0-9-]+$ ]] || die "bad epic '${epic}'"
  [[ -f "${epic_file}" ]] || die "no epic ${epic_file}"
  hld=$(sed -n 's/^hld: *//p' "${epic_file}" | head -1); hld="${hld:-${epic}}"
  [[ "${hld}" =~ ^[a-z0-9-]+$ ]] || die "${epic}: bad hld '${hld}'"
  prompt="${PROJECT_DIR}/.swarm/briefs/conduct-${epic}.md"; mkdir -p "$(dirname "${prompt}")"
  conduct_brief "${epic}" > "${prompt}"
  rm -f "$(conductor_report "conduct-${epic}")"   # a report left by an earlier run is not this one's
  read -r ws placeholder <<< "$(hld_workspace "${hld}")"
  # On exit, not after start_agent: a conductor that fails to start dies, and left the tab empty.
  # shellcheck disable=SC2064 # expand now; the tab id is herdr's, [a-zA-Z0-9:]
  [[ -z "${placeholder}" ]] || trap "herdr tab close '${placeholder}' >/dev/null 2>&1 || true" EXIT
  HERDR_WORKSPACE_ID="${ws}" start_agent "${epic}" "conduct-${epic}" "${PROJECT_DIR}" conduct "${prompt}" conductor
  echo "workspace ${hld} (${ws})"
}

# fm <file> <key> — the first front-matter value for <key>, or nothing.
fm() { sed -n "s/^$2: *//p" "$1" | head -1; }

# board <dir> — the item files in <board>/<dir>/, never the README.
board() {
  local f
  for f in "${BOARD}/$1"/*.md; do
    [[ -e "${f}" && "$(basename "${f}")" != README.md ]] && echo "${f}"
  done
  return 0
}

# epic_has_open_stories <epic> — true while any story of <epic> is still on the board and not done.
epic_has_open_stories() {
  local s
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] && open_item "${s}" && return 0
  done < <(board stories)
  return 1
}

# epic_has_stories <epic> — true when any story names <epic>.
epic_has_stories() {
  local s
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] && return 0
  done < <(board stories)
  return 1
}

# next_step — what the chain does next, read from the board alone, so a run can stop anywhere and
# pick up again. Prints "<action> <arg>" on the first line and why on the second. In order:
#   collect <agent>   a conductor has written its report: read it, then close its tab
#   wait <agent>      a conductor exists and has not reported (idle between its own steps counts)
#   conduct <epic>    an active epic has a story an agent can build, or (pr_per = epic) every story
#                     merged into its epic branch and no PR yet
#   resume <slug>     a one-off already started (its worktree exists): wait for it, then review
#   story <slug>      a ready story outside any epic
#   plan-epic <epic>  an active epic has no stories yet
#   plan-hld <hld>    an agreed HLD has no epics listed under ## Epics
#   hld <hld>         an HLD is still a draft
#   gate              only the user can move the board: lead stories, blocked
#                     stories, later stories and epics, and PRs awaiting the user's merge
#   done              nothing open; start the next HLD with /hld <title>
next_step() {
  local f slug epic kind story_epic src buildable="" waiting=""
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    # Any status: idle is not finished. Only the conductor's report file says it is done.
    # A retired conductor (renamed <name>-done, -done2 ...) has finished: never wait on it.
    # herdr lists every project's agents: only one in a pane this project opened counts.
    slug=$(herdr agent list 2>/dev/null | SWARM_PANES="$(own_panes)" json "next((a['name'] for a in d['result']['agents'] if a.get('name','').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done') and a.get('pane_id') in e.get('SWARM_PANES','').split()),'')" 2>/dev/null || true)
    if [[ -n "${slug}" ]]; then
      if [[ -f "$(conductor_report "${slug}")" ]]; then
        echo "collect ${slug}"; echo "the conductor ${slug} has finished and written its report"
      else
        echo "wait ${slug}"; echo "the conductor ${slug} is still working (it has not written its report)"
      fi
      return
    fi
  fi
  # Stories an agent can build: ready, and of a kind an agent builds. "<epic> <slug>" per line.
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == ready ]] || continue
    kind=$(fm "${f}" kind)
    agent_kind "${kind}" || continue
    buildable+="$(fm "${f}" epic) $(basename "${f}" .md)"$'\n'
  done < <(board stories)
  # A one-off keeps status: ready until its PR merges, so an existing worktree means it has started.
  while read -r story_epic slug; do
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    src="$(repo_dir "$(fm "${BOARD}/stories/${story_epic}.md" repo)")" || continue
    [[ -d "$(worktree_for "${src}" "${story_epic}")" ]] || continue
    echo "resume ${story_epic}"; echo "${story_epic} has already started: wait for its agent, then review its PR"; return
  done <<< "${buildable}"
  # An active epic's stories first: finish what is started before anything new.
  while read -r story_epic slug; do
    [[ -n "${slug}" && "$(fm "${BOARD}/epics/${story_epic}.md" status 2>/dev/null)" == active ]] || continue
    echo "conduct ${story_epic}"; echo "${slug} is ready in the active epic ${story_epic}"; return
  done <<< "${buildable}"
  if [[ "${CFG_pr_per}" == epic ]]; then
    # Stories went into the epic branch (repos: says where) and none is left, but the epic is still
    # active, not in review: its conductor stopped before the PRs. A fresh one picks it up there.
    while IFS= read -r f; do
      [[ "$(fm "${f}" status)" == active && -n "$(fm "${f}" repos)" ]] || continue
      epic=$(basename "${f}" .md)
      epic_has_open_stories "${epic}" && continue
      echo "conduct ${epic}"; echo "every story of ${epic} is in its epic branch, and the epic has no PR yet"; return
    done < <(board epics)
  fi
  while read -r story_epic slug; do
    # A one-off: `read` puts the lone slug in story_epic.
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    echo "story ${story_epic}"; echo "${story_epic} is ready and belongs to no epic"; return
  done <<< "${buildable}"
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == active ]] || continue
    epic=$(basename "${f}" .md)
    epic_has_stories "${epic}" && continue
    echo "plan-epic ${epic}"; echo "the active epic ${epic} has no stories yet"; return
  done < <(board epics)
  while IFS= read -r f; do
    slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      agreed)
        if [[ $(awk '/^## Epics/{e=1;next} /^## /{e=0} e && /^[-*] /{n++} END{print n+0}' "${f}") -eq 0 ]]; then
          echo "plan-hld ${slug}"; echo "the agreed HLD ${slug} has no epics yet"; return
        fi ;;
      draft) echo "hld ${slug}"; echo "the HLD ${slug} is still a draft"; return ;;
    esac
  done < <(board hld)
  waiting="$(waiting_on_user)"
  if [[ -n "${waiting}" ]]; then
    echo "gate"; echo "only you can move the board now:"; printf '%s\n' "${waiting}"; return
  fi
  echo "done"; echo "nothing is open; start the next HLD with /hld <title>"
}

# waiting_on_user — one line per board item only the user can move: lead stories, blocked and later
# items, and PRs awaiting the user's merge. Shared by next_step's gate and status.
waiting_on_user() {
  local f kind slug waiting=""
  while IFS= read -r f; do
    kind=$(fm "${f}" kind); slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      ready) agent_kind "${kind}" || waiting+="  ${kind}: ${slug}"$'\n' ;;
      blocked) waiting+="  blocked: ${slug} (by $(fm "${f}" blocked_by))"$'\n' ;;
      later) waiting+="  later story: ${slug}"$'\n' ;;
      review) waiting+="  awaiting your merge: ${slug} $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board stories)
  while IFS= read -r f; do
    case "$(fm "${f}" status)" in
      later) waiting+="  later epic: $(basename "${f}" .md)"$'\n' ;;
      review) waiting+="  awaiting your merge: epic $(basename "${f}" .md) $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board epics)
  printf '%s' "${waiting%$'\n'}"
}

# open_item <file> — true while a board item is still open: its file exists and is not status: done.
open_item() { [[ -f "$1" && "$(fm "$1" status)" != "done" ]]; }

# unblock — a finished story is deleted or marked done, so a blocked story whose every blocked_by and
# depends_on slug (either list may be empty) is no open story or epic, and names no hand step, is
# ready. Prints each story it flips.
unblock() {
  local story slug blockers b open
  while IFS= read -r story; do
    grep -q '^status: blocked$' "${story}" || continue
    # Both lists count: blocked_by may name only some of what the story waits on. YAML quotes go.
    blockers=$(sed -n -e 's/^blocked_by: *\[\(.*\)\]$/\1/p' -e 's/^depends_on: *\[\(.*\)\]$/\1/p' "${story}" | tr ',\n' '  ' | tr -d "\"'")
    [[ -n "${blockers// /}" ]] || continue   # blocked for a reason no merge clears
    open=0
    for b in ${blockers}; do
      # Open while its story exists, its epic exists, or it is not a plain slug (a hand step such
      # as "operator:planted-leak-proof" is cleared by hand, never by a merge).
      if open_item "${BOARD}/stories/${b}.md" || open_item "${BOARD}/epics/${b}.md" || [[ ! "${b}" =~ ^[a-z0-9-]+$ ]]; then open=1; fi
    done
    [[ ${open} -eq 0 ]] || continue
    sed -i.bak -e 's/^status: blocked$/status: ready/' -e '/^blocked_by:/d' "${story}" && rm -f "${story}.bak"
    record_event unblock "$(basename "${story}" .md)"
    echo "ready: $(basename "${story}" .md)"
  done < <(board stories)
}

# finish <slug> — take a merged story or epic off the board: delete its file, or with
# finished = mark set its status to done and keep it.
finish_item() {
  local slug="$1" f
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "bad slug '${slug}'"
  for f in "${BOARD}/stories/${slug}.md" "${BOARD}/epics/${slug}.md"; do
    [[ -f "${f}" ]] || continue
    if [[ "${CFG_finished}" == mark ]]; then
      awk '!d && /^status: /{print "status: done"; d=1; next} {print}' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
      echo "done: ${f}"
    else
      rm "${f}"; echo "deleted: ${f}"
    fi
    return
  done
  die "no story or epic '${slug}' in ${BOARD}"
}

# item_file <slug> — the story or epic file for <slug>.
item_file() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "bad slug '$1'"
  if [[ -f "${BOARD}/stories/$1.md" ]]; then echo "${BOARD}/stories/$1.md"
  elif [[ -f "${BOARD}/epics/$1.md" ]]; then echo "${BOARD}/epics/$1.md"
  else die "no story or epic '$1' in ${BOARD}"; fi
}

# set_status <file> <status> [prs] — in the front matter, set the status line and replace the prs
# line with [prs], or drop it when [prs] is empty.
set_status() {
  awk -v st="$2" -v prs="${3:-}" '
    /^---$/ { n++ }
    n == 1 && /^prs: / { next }
    n == 1 && !d && /^status: / { print "status: " st; if (prs != "") print "prs: " prs; d = 1; next }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# review <slug> <pr-url>... — the item's PRs are green and reviewed and wait on a human merge.
mark_review() {
  local f url
  f="$(item_file "${1:?slug}")"; shift
  [[ $# -gt 0 ]] || die "review: name the PR URLs"
  for url in "$@"; do
    [[ "${url}" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$ ]] || die "review: not a PR URL: ${url}"
  done
  set_status "${f}" review "$*"
  echo "review: $(basename "${f}" .md) $*"
}

# reconcile — for each item in review: finish it once every PR it lists has merged; send it back to
# ready, saying which, if any closed without merging; otherwise leave it waiting.
reconcile() {
  local f slug url state closed waiting urls merged=() merged_prs=()
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == review ]] || continue
    slug="$(basename "${f}" .md)"
    read -r -a urls <<< "$(fm "${f}" prs)"
    if [[ ${#urls[@]} -eq 0 ]]; then echo "in review with no prs: line: ${slug}"; continue; fi
    closed=""; waiting=0
    for url in "${urls[@]}"; do
      if ! state="$(gh pr view "${url}" --json state | json "d['state']")"; then
        echo "cannot read ${url}; ${slug} stays in review"; waiting=1; continue
      fi
      case "${state}" in
        MERGED) ;;
        CLOSED) closed+=" ${url}" ;;
        *) waiting=1 ;;
      esac
    done
    if [[ -n "${closed}" ]]; then
      set_status "${f}" ready
      record_event reconcile "${slug}" "ok (reopened)"
      echo "back to ready: ${slug} (closed without merging:${closed})"
    elif [[ ${waiting} -eq 0 ]]; then
      merged+=("${slug}"); merged_prs+=("${urls[*]}")
    fi
  done < <(board stories; board epics)
  [[ ${#merged[@]} -gt 0 ]] || return 0
  local i committed
  if [[ ${BOARD_IN_REPO} == 1 ]]; then
    # The board is in the project repo, and a merged PR may itself have taken the item off it. Our
    # review edit would block that pull, so undo just that edit first, and redo it if the pull fails.
    for slug in "${merged[@]}"; do
      f="$(item_file "${slug}")"
      if committed="$(git -C "${PROJECT_DIR}" show "HEAD:${f#"${PROJECT_DIR}"/}" 2>/dev/null)"; then
        set_status "${f}" "$(sed -n 's/^status: *//p' <<< "${committed}" | head -1)"
      fi
    done
    if git -C "${PROJECT_DIR}" rev-parse -q --verify '@{upstream}' >/dev/null && ! pull_board_repo; then
      for i in "${!merged[@]}"; do set_status "$(item_file "${merged[i]}")" review "${merged_prs[i]}"; done
      die "reconcile: cannot pull ${PROJECT_DIR}: ${PULL_WHY}; pull it by hand, then run reconcile again"
    fi
  fi
  for slug in "${merged[@]}"; do
    f="${BOARD}/stories/${slug}.md"; [[ -f "${f}" ]] || f="${BOARD}/epics/${slug}.md"
    [[ -f "${f}" && "$(fm "${f}" status)" != "done" ]] || { record_event reconcile "${slug}" "ok (finished by its PR)"; echo "merged: ${slug}"; continue; }
    finish_item "${slug}"
    record_event reconcile "${slug}" "ok (finished)"
  done
}

# pull_board_repo — pull the main checkout fast-forward, never losing an edit. It stops, touching
# nothing, when the pull cannot fast-forward (local commits) or a tracked file outside the board is
# changed. Otherwise it backs up, then puts back, each unstaged board edit (` M`, or `??` untracked)
# whose bytes are already the upstream branch's, so the pull that brings the same content is not
# stopped by it; a staged or differing edit is left alone. If the pull still fails, every file is
# restored from the backup in STATE_DIR/reconcile-backup/. On failure PULL_WHY says why.
PULL_WHY=""
pull_board_repo() {
  local line path rel bak changed put=()
  git -C "${PROJECT_DIR}" fetch -q || { PULL_WHY="cannot fetch"; return 1; }
  if ! git -C "${PROJECT_DIR}" merge-base --is-ancestor HEAD '@{upstream}'; then
    PULL_WHY="it has commits the base does not ($(git -C "${PROJECT_DIR}" log --format=%h '@{upstream}..HEAD' | paste -sd' ' -)), so it cannot fast-forward"
    return 1
  fi
  rel="${BOARD#"${PROJECT_DIR}"/}/"
  changed="$(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=no | cut -c4- | awk -v b="${rel}" 'index($0, b) != 1' | paste -sd' ' -)"
  [[ -z "${changed}" ]] || { PULL_WHY="files outside the board are changed: ${changed}"; return 1; }
  while IFS= read -r line; do
    path="${line:3}"
    [[ "${line:0:2}" == " M" || "${line:0:2}" == "??" ]] || continue   # staged, deleted or renamed: left alone
    git -C "${PROJECT_DIR}" cat-file -e "@{upstream}:${path}" 2>/dev/null || continue
    git -C "${PROJECT_DIR}" show "@{upstream}:${path}" | cmp -s - "${PROJECT_DIR}/${path}" || continue
    put+=("${path}")
  done < <(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=all -- "${BOARD}")
  bak="${STATE_DIR}/reconcile-backup/$(date +%Y%m%dT%H%M%S)-$$"
  for path in "${put[@]+"${put[@]}"}"; do
    if ! { mkdir -p "$(dirname "${bak}/${path}")" && cp -p "${PROJECT_DIR}/${path}" "${bak}/${path}"; }; then
      PULL_WHY="cannot back up ${path}"; return 1
    fi
  done
  for path in "${put[@]+"${put[@]}"}"; do
    if git -C "${PROJECT_DIR}" ls-files --error-unmatch -- "${path}" >/dev/null 2>&1; then
      git -C "${PROJECT_DIR}" checkout -q -- "${path}"
    else
      rm -f "${PROJECT_DIR}/${path}"
    fi
    echo "reconcile: ${path} was already the base's; put it back before the pull (backup in ${bak})"
  done
  if ! git -C "${PROJECT_DIR}" pull -q --ff-only; then
    for path in "${put[@]+"${put[@]}"}"; do cp -p "${bak}/${path}" "${PROJECT_DIR}/${path}"; done
    PULL_WHY="the pull failed, and every board edit is as it was$(board_edits_named)"
    return 1
  fi
  rm -rf "${bak}"; rmdir "${STATE_DIR}/reconcile-backup" 2>/dev/null || true
}

# board_edits_named — "; board files changed here: <files>" for the board files the main checkout
# has changed, or nothing when there are none.
board_edits_named() {
  local files
  files="$(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=all -- "${BOARD}" | cut -c4- | paste -sd' ' -)"
  [[ -z "${files}" ]] || echo "; board files changed here: ${files}"
}

# findings <repo> <pr> — what a green check can hide: the notes (annotations) on every check run of
# the PR's head, whatever its conclusion, and the PR's open code-scanning alerts.
findings() {
  local src full sha
  src="$(repo_dir "${1:?repo}")" || die "findings: ${src}"
  [[ "${2:?pr}" =~ ^[0-9]+$ ]] || die "findings: not a PR number: $2"
  full="$(gh repo view "$(git -C "${src}" remote get-url origin)" --json nameWithOwner | json "d['nameWithOwner']")" \
    || die "no GitHub origin for ${src}"
  sha="$(gh api "repos/${full}/pulls/$2" | json "d['head']['sha']")" || die "cannot read ${full}#$2"
  echo "${full}#$2 at ${sha:0:7}"
  local id name
  while IFS=$'\t' read -r id name; do
    [[ -n "${id}" ]] || continue
    gh api "repos/${full}/check-runs/${id}/annotations?per_page=100" | python3 -c '
import json, sys
for a in json.load(sys.stdin):
    msg = (a.get("message") or "").splitlines() or [""]
    print("  check %s: %s %s:%s %s" % (sys.argv[1], a.get("annotation_level"), a.get("path"), a.get("start_line"), msg[0]))' "${name}"
  done < <(gh api "repos/${full}/commits/${sha}/check-runs?per_page=100" | python3 -c '
import json, sys
for c in json.load(sys.stdin)["check_runs"]:
    if c["output"].get("annotations_count"):
        print("%s\t%s (%s)" % (c["id"], c["name"], c.get("conclusion")))')
  local alerts
  if alerts="$(gh api "repos/${full}/code-scanning/alerts?ref=refs/pull/$2/merge&state=open&per_page=100" 2>/dev/null)"; then
    python3 -c '
import json, sys
for a in json.load(sys.stdin):
    r, inst = a["rule"], a["most_recent_instance"]
    loc, msg = inst["location"], (inst["message"]["text"].splitlines() or [""])[0]
    sev = r.get("security_severity_level") or r.get("severity")
    print("  alert #%s %s %s %s:%s %s" % (a["number"], sev, r.get("id"), loc.get("path"), loc.get("start_line"), msg))' <<< "${alerts}"
  else
    echo "  code scanning: not available on ${full}"
  fi
}

# watch [--epic <slug>] [repo...] — block until a story/* or epic/* PR in these repos needs the lead, print
# one line saying which and why, and exit 0. With --epic, only that epic's PRs count (epic/<slug> and
# its stories' story/<slug> branches), and the default repos are its stories' repos plus the epic's
# repos: line (its stories may already be finished and deleted when the epic PR opens): a conductor
# must not wake for another epic's PR on the same board. A PR needs the lead when its checks on a new head have all finished,
# when it conflicts with its base (a conflicted PR runs no checks, so waiting on checks never ends),
# or when its head has had no check at all for WATCH_STALL_SECS (default 600). A herdr agent
# blocked on a prompt also needs the lead. Each head is reported once (state in .swarm/state).
watch_prs() {
  local epic="" stories=("${BOARD}"/stories/*.md) epic_heads="" epic_repos="" f
  if [[ "${1:-}" == --epic ]]; then
    epic="${2:?watch --epic needs an epic slug}"; shift 2
    [[ -f "${BOARD}/epics/${epic}.md" ]] || die "watch: no epic ${BOARD}/epics/${epic}.md"
    stories=(); epic_heads="epic/${epic}"; epic_repos="$(fm "${BOARD}/epics/${epic}.md" repos)"
    for f in "${BOARD}"/stories/*.md; do
      [[ -f "${f}" && "$(fm "${f}" epic)" == "${epic}" ]] || continue
      stories+=("${f}"); epic_heads="${epic_heads} story/$(basename "${f}" .md)"
    done
  fi
  local repos=("$@") seen="${STATE_DIR}/watch-seen" stall="${WATCH_STALL_SECS:-600}" repo n sha br mergeable age total pending
  # Default: the project (when it is a repo) plus every repo a story names, so a new repo needs no edit here.
  if [[ ${#repos[@]} -eq 0 ]]; then
    local own=""; [[ ${PROJECT_IS_GIT} == 1 ]] && own="$(basename "${PROJECT_DIR}")"
    read -r -a repos <<< "${own} ${epic_repos} $( (( ${#stories[@]} )) && sed -n 's/^repo: *//p' "${stories[@]}" 2>/dev/null | sort -u | tr '\n' ' ')"
  fi
  # With nothing to poll, the loop below would sleep forever.
  [[ ${#repos[@]} -gt 0 ]] || die "watch: no repo to watch${epic:+ for epic ${epic}}"
  # Each repo as owner/name, from its own origin: repos on one board need not share an owner.
  local full=() r src
  for r in "${repos[@]}"; do
    src="$(repo_dir "${r}")" || die "watch ${r}: ${src}"
    r="$(gh repo view "$(git -C "${src}" remote get-url origin)" --json nameWithOwner -q .nameWithOwner)" \
      || die "no GitHub origin for ${src}"
    [[ " ${full[*]-} " == *" ${r} "* ]] || full+=("${r}")
  done
  repos=("${full[@]}")
  mkdir -p "${STATE_DIR}"; touch "${seen}"
  while :; do
    for repo in "${repos[@]}"; do
      while read -r n sha br mergeable age; do
        [[ -n "${n}" ]] || continue
        [[ -z "${epic_heads}" || " ${epic_heads} " == *" ${br} "* ]] || continue
        if [[ "${mergeable}" == CONFLICTING ]] && ! grep -qx "conflict ${sha}" "${seen}"; then
          echo "conflict ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} CONFLICTS with its base"; return 0
        fi
        grep -qx "done ${sha}" "${seen}" && continue
        read -r total pending < <(gh api "repos/${repo}/commits/${sha}/check-runs" \
          -q '"\(.check_runs|length) \([.check_runs[]|select(.status!="completed")]|length)"')
        if [[ "${total:-0}" -gt 0 && "${pending}" == 0 ]]; then
          echo "done ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} checks finished on ${sha:0:7}"; return 0
        fi
        if [[ "${total:-0}" == 0 && "${age}" -gt "${stall}" ]] && ! grep -qx "stall ${sha}" "${seen}"; then
          echo "stall ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} has had no checks for ${age}s"; return 0
        fi
      done < <(gh pr list -R "${repo}" --state open --json number,headRefName,headRefOid,mergeable,updatedAt \
        -q '.[]|select(.headRefName|startswith("story/") or startswith("epic/"))|"\(.number) \(.headRefOid) \(.headRefName) \(.mergeable) \((now - (.updatedAt|fromdateiso8601))|floor)"')
    done
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
      local blocked
      # Only agents in panes this project opened: herdr lists every project's.
      blocked=$(herdr agent list 2>/dev/null | SWARM_PANES="$(own_panes)" json "','.join(a['name'] for a in d['result']['agents'] if a.get('agent_status')=='blocked' and a.get('name') and a.get('pane_id') in e.get('SWARM_PANES','').split())" 2>/dev/null || true)
      if [[ -n "${blocked}" ]] && ! grep -qx "blocked ${blocked}" "${seen}"; then
        echo "blocked ${blocked}" >> "${seen}"; echo "agent(s) blocked on a prompt: ${blocked}"; return 0
      fi
    fi
    sleep 60
  done
}

# status [--all] — one summary for the user: the agents that need a look or are working, what is
# waiting on them, and what `next` would do; idle agents and blocked stories are only counted unless
# --all. A pane with no agent in it is shown as empty: a start that failed. Panes closed by hand are
# left out.
status_report() {
  local all="${1:-}" agents panes waiting
  if [[ "${HERDR_ENV:-}" == 1 ]] && agents=$(herdr agent list 2>/dev/null) && panes=$(herdr pane list 2>/dev/null); then
    SWARM_PANES_PY="${PANES_PY}" SWARM_OWN="$(own_panes)" python3 - "${STATE_DIR}" "${agents}" "${panes}" "${all}" <<'PY'
import json, os, sys
exec(os.environ["SWARM_PANES_PY"])
state, agents_json, panes_json, show_all = sys.argv[1:5]
try:
    agents = {a.get("pane_id"): a for a in json.loads(agents_json)["result"]["agents"]}
    live = {p["pane_id"] for p in json.loads(panes_json)["result"]["panes"]}
except (ValueError, KeyError):
    print("Agents\n  (herdr gave no agent list)"); sys.exit(0)
rows = []
for tab, pane, name in pane_records(state, set(os.environ["SWARM_OWN"].split()) & live):
        a = agents.get(pane)
        if a is not None:
            name = a.get("name") or name
        st, _ = agent_state(a, name)
        what = {"EMPTY": "EMPTY: no agent started in this pane; close it",
                "WAITING": f"WAITING on a question: herdr agent read {name}",
                "retired": "done (retired)",
                "idle": "idle: finished, or waiting for its next step",
                "done": "idle: finished, or waiting for its next step"}.get(st, st)
        rows.append((name, what, f"{tab} {pane}"))
quiet = [r for r in rows if r[1].startswith(("idle", "done"))]
shown = rows if show_all == "--all" else [r for r in rows if r not in quiet]
counts = [f"{len(rows) - len(quiet)} need a look or are working", f"{len(quiet)} idle or done"]
print("Agents: " + ", ".join(counts) if rows else "Agents: none open")
width = max((len(r[0]) for r in shown), default=0)
for name, what, where in shown:
    print(f"  {name:<{width}}  {what}  [{where}]")
if quiet and show_all != "--all":
    print("  (swarm.sh status --all lists them all)")
PY
  else
    echo "Agents: not inside herdr, so their states are not available"
  fi
  echo; echo "Waiting on you"
  waiting="$(waiting_on_user)"
  if [[ "${all}" != --all ]]; then
    local blocked
    blocked=$(grep -c '^  blocked:' <<< "${waiting}" || true)
    waiting="$(grep -v '^  blocked:' <<< "${waiting}" || true)"
    [[ "${blocked}" -eq 0 ]] || waiting+="${waiting:+$'\n'}  ${blocked} blocked stories wait on others (swarm.sh status --all lists them)"
  fi
  if [[ -n "${waiting}" ]]; then printf '%s\n' "${waiting}"; else echo "  nothing"; fi
  echo; echo "Next"
  next_step | sed 's/^/  /'
}

# dash [--watch [seconds]] [--ladder] [--tree] — a read-only dashboard: a header and a summary
# line, what needs you, each active epic's progress with its live agents and open PRs, and the recent
# events. --ladder adds the model per role; --tree shows the agents by herdr workspace and tab in
# place of the epics. It never writes the board, state or logs, and never opens or closes a pane.
# --watch rebuilds it every N seconds (default 2) and repaints in place; q quits, t and l toggle the
# tree and the ladder. Colour only on a terminal with NO_COLOR unset.
dash() {
  local every="" tty=0
  DASH_LADDER=0; DASH_TREE=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --watch)
        every=2
        if [[ -n "${2:-}" && "$2" != --* ]]; then every="$2"; shift; fi
        [[ "${every}" =~ ^[1-9][0-9]*$ ]] || die "dash --watch: seconds must be a positive whole number, not '${every}'" ;;
      --ladder) DASH_LADDER=1 ;;
      --tree) DASH_TREE=1 ;;
      *) die "usage: swarm.sh dash [--watch [seconds]] [--ladder] [--tree]" ;;
    esac
    shift
  done
  DASH_COLOR=0
  if [[ -t 1 ]]; then
    tty=1
    [[ -n "${NO_COLOR+x}" ]] || DASH_COLOR=1
  fi
  dash_size
  if [[ -z "${every}" ]]; then dash_slow; dash_render; return; fi
  dash_watch "${every}" "${tty}"
}

# dash_size — the terminal's columns and lines into DASH_W and DASH_H. Measured here, never in the
# render's $(...), where there is no terminal (tput answers 80 there): stty on /dev/tty, then tput
# on a terminal, then COLUMNS and LINES, then 100 columns and an unknown height (0).
dash_size() {
  local s="" c="" r=""
  s="$( { stty size </dev/tty; } 2>/dev/null)" || s=""
  r="${s% *}"; c="${s#* }"
  if [[ ! "${c}" =~ ^[1-9][0-9]*$ ]]; then
    c=""; r=""
    if [[ -t 1 ]]; then c="$(tput cols 2>/dev/null)" || c=""; r="$(tput lines 2>/dev/null)" || r=""; fi
  fi
  [[ "${c}" =~ ^[1-9][0-9]*$ ]] || c="${COLUMNS:-}"
  [[ "${c}" =~ ^[1-9][0-9]*$ ]] || c=100
  [[ "${r}" =~ ^[1-9][0-9]*$ ]] || r="${LINES:-}"
  [[ "${r}" =~ ^[1-9][0-9]*$ ]] || r=0
  DASH_W="${c}"; DASH_H="${r}"
}

# dash_base_ref [dir] — in the repo at [dir] (default PROJECT_DIR), the base branch as last fetched
# (origin/<base>; dash never fetches), else HEAD.
dash_base_ref() {
  local r
  for r in ${CFG_base_branches} HEAD; do
    git -C "${1:-${PROJECT_DIR}}" rev-parse -q --verify "origin/${r}" >/dev/null 2>&1 && { echo "origin/${r}"; return; }
  done
  echo HEAD
}

# dash_slow — the fields too slow for every frame, cached for a minute in a file under $TMPDIR (never
# under .swarm), so a one-shot dash reuses it too: today's estimated cost (the total line of
# cost_report), each open board item's PR checks, merge state and last update, one gh pr view per
# PR with a 5-second limit (a PR gh cannot answer in time is left out, and shows as its URL), and how
# many stories of each epic finished (dash_finished).
dash_slow() {
  local cache f urls
  # -2: the cache gained finished-story lines; a name of its own, so an older swarm.sh's cache is never read.
  cache="${TMPDIR:-/tmp}/swarm-dash-2-$(printf '%s' "${PROJECT_DIR}" | cksum | cut -d' ' -f1)"
  if [[ -z "$(find "${cache}" -mmin -1 2>/dev/null)" ]]; then
    urls="$( { board stories; board epics; } | while IFS= read -r f; do
        [[ "$(fm "${f}" status)" == "done" ]] || fm "${f}" prs; done | grep -o 'https://github.com/[^] ,"]*/pull/[0-9]*' | sort -u || true)"
    {
      printf 'cost\t%s\n' "$( (cost_report "$(date +%F)") 2>/dev/null | sed -n 's/^| \*\*total\*\* |.* \([0-9][0-9.]*\) |$/\1/p' || true)"
      dash_finished
      # shellcheck disable=SC2086 # one URL per word
      if command -v gh >/dev/null 2>&1 && [[ -n "${urls}" ]]; then python3 - ${urls} <<'PY'
import os, signal, subprocess, sys
for url in sys.argv[1:]:
    p = subprocess.Popen(["gh", "pr", "view", url, "--json", "statusCheckRollup,mergeStateStatus,updatedAt"],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL); p.communicate()
        continue
    if p.returncode == 0:
        print(url + "\t" + out.replace("\n", "").replace("\t", ""))
PY
      fi
    } > "${cache}.$$" 2>/dev/null && mv -f "${cache}.$$" "${cache}"
  fi
  DASH_COST="$(awk -F'\t' '$1 == "cost" { print $2 }' "${cache}" 2>/dev/null || true)"
  DASH_FINISHED="$(awk -F'\t' '$1 == "finished" { print $2 "\t" $3 }' "${cache}" 2>/dev/null || true)"
  DASH_PRSTATE="$(grep '^https://' "${cache}" 2>/dev/null || true)"
}

# dash_finished — "finished<TAB>epic<TAB>count" per epic, from the board's own repo (none when the
# board is not in git). A finished story's file is deleted, so these are the story files deleted on
# the first-parent history of that repo's base branch and HEAD: one git log, names only, commits split
# on NUL (no diff text, so diff.noprefix or color settings cannot change it), each deleted file read
# from the parent's tree by one git cat-file --batch, its keys from the front matter only. A slug is
# counted once, and not at all while its file is on the board here (an unpulled checkout, or a slug
# added again): it is open. It counts when any of its deletions closed the story: the deleting commit
# names story/<slug> (its own PR's merge), or is the story's own work (it also changes a file outside
# the board that is not a repo-root *.md, and its subject names no board/, close/ or epic/ branch: a
# squash-merged story PR), the swarm finished it (finish, or reconcile "finished", in events.tsv), or
# the deleted file's last status was done or review (reconcile finishes only items in review) or it
# listed prs. A re-scope (a board/ PR, or a commit that edits only the board and root notes such as
# STATUS.md) has none of these, so it counts as nothing.
dash_finished() {
  local prefix
  prefix="$(git -C "${BOARD}" rev-parse --show-prefix 2>/dev/null)" || return 0
  python3 - "${BOARD}" "${prefix}" "$(dash_base_ref "${BOARD}")" "${EVENTS_LOG}" <<'PY' 2>/dev/null || true
import collections, os, re, subprocess, sys
board, prefix, ref, events = sys.argv[1:5]
def git(args, data=None):
    return subprocess.run(["git", "-c", "core.quotePath=false"] + args, cwd=board, input=data,
                          capture_output=True, check=True).stdout
KEY = re.compile(r"([A-Za-z_]+): *(.*)$")
def front(text):
    # The front matter's keys, as dash_fields reads them: only after a leading ---, up to the next;
    # a key's first line wins, an empty value too; CRLF tolerated.
    keys, lines = {}, [l.rstrip("\r") for l in text.split("\n")]
    if lines[0] != "---":
        return keys
    for l in lines[1:]:
        if l == "---":
            break
        m = KEY.match(l)
        if m and m.group(1) not in keys:
            keys[m.group(1)] = m.group(2)
    return keys
finished_here = set()
try:
    for l in open(events, encoding="utf-8", errors="replace"):
        f = l.rstrip("\n").split("\t")
        if len(f) == 5 and ((f[1] == "finish" and f[4] == "ok") or (f[1] == "reconcile" and "finished" in f[4])):
            finished_here.add(f[2])
except OSError:
    pass
stories = prefix + "stories/"
BOOKKEEPING = re.compile(r"(^|[\s/])(board|close|epic)/")   # a board, close or epic branch, never a story's own work
tips = [ref] + (["HEAD"] if ref != "HEAD" else [])
log = git(["log", "--first-parent", "--diff-merges=first-parent", "--no-color", "--no-renames", "--name-status", "--format=%x00%H%x09%s"] + tips + ["--"])
todo = []   # (slug, cat-file spec, closed by its commit), newest first
for chunk in log.decode("utf-8", "replace").split("\0")[1:]:
    head, _, changes = chunk.partition("\n")
    commit, _, subject = head.partition("\t")
    paths = [c.partition("\t")[2] for c in changes.splitlines() if "\t" in c]
    work = not BOOKKEEPING.search(subject) and any(
        not p.startswith(prefix) and ("/" in p or not p.endswith(".md")) for p in paths)
    for c in changes.splitlines():
        st, _, path = c.partition("\t")
        if st != "D" or not path.startswith(stories) or not path.endswith(".md") or "/" in path[len(stories):]:
            continue
        slug = path[len(stories):-3]
        if slug != "README" and not os.path.exists(os.path.join(board, "stories", slug + ".md")):
            own = re.search(r"story/" + re.escape(slug) + r"(\s|$)", subject) or work or slug in finished_here
            todo.append((slug, f"{commit}^1:{path}", bool(own)))
out = git(["cat-file", "--batch"], "".join(t[1] + "\n" for t in todo).encode()) if todo else b""
count, done, pos = collections.Counter(), set(), 0
for slug, _, own in todo:
    nl = out.index(b"\n", pos)
    head, pos = out[pos:nl], nl + 1
    if head.endswith(b" missing"):
        continue
    size = int(head.rsplit(b" ", 1)[1])
    fm = front(out[pos:pos + size].decode("utf-8", "replace"))
    pos += size + 1
    if slug not in done and fm.get("epic") and (own or fm.get("status") in ("done", "review") or fm.get("prs")):
        done.add(slug)
        count[fm["epic"]] += 1
for epic, n in sorted(count.items()):
    print(f"finished\t{epic}\t{n}")
PY
}

# dash_watch <seconds> <tty> — rebuild the frame every <seconds>, and repaint only when it changed;
# when only the clock moved, just the header line is rewritten. On a terminal it draws on the
# alternate screen with the cursor hidden, re-measures every frame, reads q (quit), r (redraw), t
# (the tree) and l (the ladder) without blocking, and redraws within a second of a resize (bash
# 3.2's read -t is not cut short by SIGWINCH, so it waits in one-second steps). Off a terminal it
# prints each changed frame, plain.
dash_watch() {
  local every="$1" tty="$2" tpl="" frame last="" key i winch=0
  if [[ ${tty} == 1 ]]; then
    trap 'printf "\033[?25h\033[?1049l"' EXIT
    printf '\033[?1049h\033[?25l'
  fi
  trap 'exit 0' INT TERM HUP
  trap 'winch=1' WINCH
  while :; do
    [[ ${tty} == 0 ]] || dash_size
    dash_slow   # the cache file decides whether this asks gh again
    # A failed render shows its error in the frame and the loop carries on: a watch must not die quietly.
    if ! tpl="$(DASH_CLOCK=HH:MM:SS DASH_KEYS="${tty}" dash_render 2>&1)"; then
      # Keep the error line on screen: cut the rest to one line short of the terminal's height.
      [[ ${tty} == 0 || ${DASH_H} -lt 2 ]] || tpl="$(head -n $((DASH_H - 1)) <<< "${tpl}")"
      tpl+=$'\n'"(dash: this render failed; retrying in ${every}s)"
    fi
    frame="${tpl//HH:MM:SS/$(date +%H:%M:%S)}"
    if [[ ${tty} == 0 ]]; then
      [[ "${tpl}" == "${last}" ]] || printf '%s\n\n' "${frame}"
    elif [[ "${tpl}" != "${last}" ]]; then
      printf '\033[H%s\033[K\033[J' "${frame//$'\n'/$'\033[K\n'}"
    else
      printf '\033[H%s\033[K' "${frame%%$'\n'*}"
    fi
    last="${tpl}"; winch=0
    for ((i = 0; i < every; i++)); do
      if [[ ${tty} == 1 ]]; then
        key=""; read -rsn1 -t 1 key </dev/tty || true
        case "${key}" in
          q|Q) exit 0 ;;
          r|R) last=""; break ;;
          t|T) DASH_TREE=$((1 - DASH_TREE)); last=""; break ;;
          l|L) DASH_LADDER=$((1 - DASH_LADDER)); last=""; break ;;
        esac
      else
        sleep 1
      fi
      [[ ${winch} == 0 ]] || { last=""; break; }
    done
  done
}

# dash_fields <file> — a board item's status, prs, epic, kind and title (its first "# " heading),
# tab-separated, in one fork. The keys are read from the front matter only (a leading ---, up to the
# next; CRLF tolerated), by fm's rule: a key's first line wins, an empty value too. dash_finished's
# front() reads them the same way.
dash_fields() {
  awk '{ sub(/\r$/, "") }
    NR == 1 && $0 == "---" { n = 1; next }
    n == 1 && $0 == "---" { n = 2; next }
    n == 1 && !hs && sub(/^status: */, "") { hs = 1; s = $0; next }
    n == 1 && !hp && sub(/^prs: */, "") { hp = 1; p = $0; next }
    n == 1 && !he && sub(/^epic: */, "") { he = 1; e = $0; next }
    n == 1 && !hk && sub(/^kind: */, "") { hk = 1; k = $0; next }
    n != 1 && !ht && sub(/^# /, "") { ht = 1; t = $0 }
    END { printf "%s\t%s\t%s\t%s\t%s", s, p, e, k, t }' "$1"
}

# dash_render — gather what the dashboard shows (read-only), then lay it out in python at DASH_W x
# DASH_H. herdr is asked whenever it is on PATH, inside a herdr pane or not: dash only reads.
dash_render() {
  local agents="" panes="" workspaces="" board="" policies="" merges="" drift=0 commits="" f d r x
  if command -v herdr >/dev/null 2>&1; then
    { agents="$(herdr agent list 2>/dev/null)" && panes="$(herdr pane list 2>/dev/null)" \
      && workspaces="$(herdr workspace list 2>/dev/null)"; } || agents=""
  fi
  # One line per item: dir, slug, status, prs, its agent name, (an epic) its conductor's, epic, kind, title.
  for d in hld epics stories; do
    while IFS= read -r f; do
      r="$(basename "${f}" .md)"; x="$(dash_fields "${f}")"
      board+="${d}"$'\t'"${r}"$'\t'"${x%%$'\t'*}"$'\t'"$(cut -f2 <<< "${x}")"$'\t'"$(agent_name "${r}")"$'\t'"$(agent_name "conduct-${r}")"$'\t'"$(cut -f3- <<< "${x}")"$'\n'
    done < <(board "${d}")
  done
  # The last worktree commit of each working builder's story (STALL_PY's story_for), for the stall rule.
  while IFS= read -r r; do
    [[ -z "${r}" ]] || commits+="${r}"$'\t'"$(story_commit_time "${r}")"$'\n'
  done < <(awk -F'\t' '$1 == "stories" { print $2 "\t" $5 "\t" $3 }' <<< "${board}" \
    | SWARM_STALL_PY="${STALL_PY}" SWARM_OWN="$(own_panes)" DASH_AGENTS="${agents}" python3 -c '
import json, os, sys
exec(os.environ["SWARM_STALL_PY"])
rows = [l.rstrip("\n").split("\t") for l in sys.stdin]
own = set(os.environ["SWARM_OWN"].split())
try:
    agents = json.loads(os.environ["DASH_AGENTS"])["result"]["agents"]
except (ValueError, KeyError, TypeError):
    agents = []
for a in agents:
    if isinstance(a, dict) and a.get("agent_status") == "working" and a.get("pane_id") in own and a.get("name"):
        print(story_for(a["name"], rows) or "")' 2>/dev/null || true)
  # ponytail: a few forks per board item each redraw; read the front matter in python if boards grow past ~150 items.
  for r in $(roles); do policies+="${r} $(policy "${r}")"$'\n'; done
  if [[ ${PROJECT_IS_GIT} == 1 ]]; then
    merges="$(git -C "${PROJECT_DIR}" log --first-parent --merges -n 40 --format='%cI%x09%an%x09%s' "$(dash_base_ref)" 2>/dev/null || true)"
    # Uncommitted board edits in the main checkout; no optional locks, so status writes no index.
    drift="$(GIT_OPTIONAL_LOCKS=0 git -C "${PROJECT_DIR}" status --porcelain --untracked-files=all -- "${BOARD}" 2>/dev/null | grep -c . || true)"
  fi
  # sed, not head: head exits after a line, and where SIGPIPE is ignored (CI) next_step's second echo
  # prints "Broken pipe" into the frame, now and then, so --watch sees a changed frame.
  DASH_PROJECT="${PROJECT_DIR}" DASH_VERSION="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json")" \
  DASH_MERGE="${CFG_merge}" DASH_NEXT="$(next_step | sed -n 1p)" DASH_BOARD="${board}" DASH_POLICY="${policies}" \
  DASH_WAITING="$(waiting_on_user)" DASH_MERGES="${merges}" DASH_DRIFT="${drift}" \
  DASH_AGENTS="${agents}" DASH_PANES="${panes}" DASH_WORKSPACES="${workspaces}" DASH_STATE="${STATE_DIR}" \
  SWARM_OWN="$(own_panes)" SWARM_PANES_PY="${PANES_PY}" DASH_COLS="${DASH_W:-100}" DASH_LINES="${DASH_H:-0}" \
  DASH_COLOR="${DASH_COLOR:-0}" DASH_PRSTATE="${DASH_PRSTATE:-}" DASH_COST="${DASH_COST:-}" \
  DASH_FINISHED="${DASH_FINISHED:-}" DASH_TREE="${DASH_TREE:-0}" DASH_LADDER="${DASH_LADDER:-0}" \
  DASH_COMMITS="${commits}" DASH_STALL_MIN="${CFG_stall_minutes}" SWARM_STALL_PY="${STALL_PY}" \
  DASH_AGENTS_LOG="${AGENTS_LOG}" DASH_FINDINGS="${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" DASH_EVENTS="${EVENTS_LOG}" \
    python3 - <<'PY'
import collections, datetime, itertools, json, os, re, time
E = os.environ
exec(E["SWARM_PANES_PY"])
exec(E["SWARM_STALL_PY"])
W = max(int(E.get("DASH_COLS") or 100), 40)
H = int(E.get("DASH_LINES") or 0)
NARROW = W < 100   # stacked: the role and model columns and the recent actor column go
COLOR = E.get("DASH_COLOR") == "1"
KEYS = E.get("DASH_KEYS") == "1"
STYLE = {"h": "1;36", "ok": "32", "warn": "33", "bad": "1;31", "dim": "2", "b": "1", "grey": "90"}
# One status vocabulary: the symbol carries the meaning in plain text, the colour on a terminal.
SYM = {"working": ("●", "ok"), "ready": ("○", "h"), "review": ("◐", "warn"), "done": ("✓", "ok"), "failed": ("✗", "bad"),
       "blocked": ("⏸", "grey"), "look": ("!", "bad"), "unknown": ("?", "")}
LEGEND = ["● working", "○ ready", "◐ review / CI running", "✓ done / green", "✗ failing", "⏸ blocked", "! needs you", "? unknown"]
out = []

def paint(t, s):
    return f"\033[{STYLE[s]}m{t}\033[0m" if COLOR and s and t else t

def sym(k):
    return SYM[k][0] + " ", SYM[k][1]

def cut(t, n):
    return t if len(t) <= n else t[:max(n - 1, 0)] + "…"

def fit(segs, n):
    # Truncate, never wrap: plain lengths are measured before any colour is added.
    res, left = [], n
    for t, s in segs:
        if left <= 0:
            break
        t = cut(t, left)
        res.append(paint(t, s)); left -= len(t)
    return "".join(res) + " " * left

def wrap(segs, n, indent=2):
    # Word-wrap styled segments into lines of at most n, the later lines indented; only a single
    # word longer than a line is cut (by fit).
    lines, cur, used = [], [], 0
    for t, s in segs:
        for w in re.findall(r"\s*\S+\s*|\s+", t):
            if cur and used + len(w.rstrip()) > n:
                lines.append(cur[:-1] + [(cur[-1][0].rstrip(), cur[-1][1])])
                cur, used, w = [(" " * indent, "")], indent, w.lstrip()
            cur.append((w, s)); used += len(w)
    return lines + [cur] if cur else lines

def box(title, rows, w, style="h"):
    res = ["╭─ " + paint(title, style) + " " + "─" * max(w - len(title) - 5, 0) + "╮"]
    for r in rows or [[("(none)", "dim")]]:
        res.append("│ " + fit([(r, "")] if isinstance(r, str) else r, w - 4) + " │")
    return res + ["╰" + "─" * (w - 2) + "╯"]

def read_tsv(path, n):
    try:
        return [f for f in (l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8", errors="replace")) if len(f) == n]
    except OSError:
        return []

def lines(key):
    return [l for l in E.get(key, "").splitlines() if l.strip()]

# The board: dir, slug, status, prs, agent name, conductor name, epic, kind, title.
board = [(l.split("\t") + [""] * 9)[:9] for l in lines("DASH_BOARD")]
stories = [b for b in board if b[0] == "stories"]
story_rows = [(b[1], b[4], b[2]) for b in stories]
story_by_slug = {b[1]: b for b in stories}
epics = collections.OrderedDict((b[1], b) for b in board if b[0] == "epics")
epic_of = {b[5]: b[1] for b in epics.values()}
finished = collections.Counter()
for l in lines("DASH_FINISHED"):
    e, _, n = l.partition("\t")
    finished[e] += int(n) if n.isdigit() else 0

PRS = {}
for l in lines("DASH_PRSTATE"):
    url, _, j = l.partition("\t")
    try:
        PRS[url] = json.loads(j)
    except ValueError:
        pass
URL = re.compile(r"https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)")
FAILED = ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE")

def pr_state(url):
    # (vocabulary key, words) for a PR's checks and merge state; None when gh gave nothing.
    s = PRS.get(url)
    if not isinstance(s, dict):
        return None
    roll = s.get("statusCheckRollup") or []
    bad = any((c.get("conclusion") or c.get("state") or "").upper() in FAILED for c in roll)
    running = any((c.get("status") or "COMPLETED").upper() != "COMPLETED" or (c.get("state") or "").upper() in ("PENDING", "EXPECTED") for c in roll)
    k, words = ("failed", "failing") if bad else ("review", "CI running") if running else ("done", "green") if roll else ("review", "no checks")
    behind = {"BEHIND": " · behind", "DIRTY": " · conflicts"}.get((s.get("mergeStateStatus") or "").upper(), "")
    return k, words + behind

def pr_ref(m):
    return f"{m.group(2)}#{m.group(3)}"

# Agents: this project's panes (its tab records). A story's builder that is working with no sign of
# life for stall_minutes (STALL_PY) is stalled, and needs you.
commit_of = dict(l.split("\t", 1) for l in E.get("DASH_COMMITS", "").splitlines() if "\t" in l)
seen = last_seen(E["DASH_EVENTS"])
recs, stalled = [], []
try:
    agents = {a.get("pane_id"): a for a in json.loads(E["DASH_AGENTS"])["result"]["agents"]}
    live = {p["pane_id"] for p in json.loads(E["DASH_PANES"])["result"]["panes"]}
    ws_label = {w["workspace_id"]: w.get("label") or w["workspace_id"] for w in json.loads(E["DASH_WORKSPACES"])["result"]["workspaces"]}
except (ValueError, KeyError, TypeError):
    agents = None

def reported(base):
    # A conductor that wrote its report, which the lead has not collected yet.
    epic = epic_of.get(base) or (base[len("conduct-"):] if base.startswith("conduct-") else "")
    return bool(epic) and os.path.exists(os.path.join(E["DASH_PROJECT"], ".swarm", f"conduct-{epic}.report.md"))

def epic_for(base, slug, tab):
    if base in epic_of:
        return epic_of[base]
    if slug:
        return story_by_slug[slug][6] or None
    if tab in epics:
        return tab
    return (story_by_slug.get(tab) or [""] * 9)[6] or None

if agents is not None:
    by_session, by_name = {}, {}
    for f in read_tsv(E["DASH_AGENTS_LOG"], 7):
        by_name[f[2]] = by_session[f[6]] = f
    for label, pane, recorded in pane_records(E["DASH_STATE"], set(E.get("SWARM_OWN", "").split()) & live):
        r = {"ws": ws_label.get(pane.split(":")[0], pane.split(":")[0]), "tab": label, "name": recorded, "role": "?",
             "model": "?", "look": True, "slug": None, "epic": epic_for("", None, label)}
        try:
            a = agents.get(pane)
            name = (a or {}).get("name") or recorded
            base = re.sub(r"-done\d*$", "", name)
            rec = by_session.get(((a or {}).get("agent_session") or {}).get("value", "")) or by_name.get(base)
            st, look = agent_state(a, name)
            if st in ("idle", "done") and reported(base):
                st = "reported"
            slug = story_for(name, story_rows)
            words = {"EMPTY": "empty pane", "WAITING": "waiting on a prompt", "done": "idle"}.get(st, st)
            if st == "working" and slug:
                b = story_by_slug[slug]
                signs = [commit_of.get(slug, "")] + [(PRS.get(m.group(0)) or {}).get("updatedAt") for m in URL.finditer(b[3])]
                age = stall_age(seen, slug, base, signs)
                if age is not None and age >= int(E["DASH_STALL_MIN"]):
                    st, look, words = "stalled", True, f"stalled {age}m"
                    stalled.append((name, age))
            r.update(name=name, role=rec[1] if rec else "?", model=(f"{rec[4] if rec[3] == 'claude' else rec[3]}·{rec[5]}") if rec else "?",
                     look=look, slug=slug, epic=epic_for(base, slug, label), state=st, words=words, prs=(story_by_slug.get(slug) or [""] * 4)[3],
                     open=bool(slug) and story_by_slug[slug][2] != "done")
        except Exception as err:  # one odd agent record must not cost the whole panel
            r.update(state="unreadable", words=f"unreadable: {type(err).__name__}", prs="", open=False)
        r["sym"] = "look" if r["look"] else {"working": "working", "reported": "done", "idle": "done", "done": "done", "retired": "done"}.get(r["state"], "unknown")
        recs.append(r)

# Shown: what needs a look, works, reported, or is tied to an open story; the rest is one +N idle.
shown = [r for r in recs if r["look"] or r["state"] in ("working", "reported") or r["open"]]
idle = len(recs) - len(shown)

# Needs you: only what you act on, each as a short action.
need, blocked, later, green, need_slugs = [], 0, 0, 0, set()
bang = [sym("look")]
for l in lines("DASH_WAITING"):
    l = l.strip()
    if l.startswith("blocked:"):
        blocked += 1
        continue
    if l.startswith("later "):
        later += 1
        continue
    m = re.match(r"awaiting your merge: (epic )?(\S+) ?(.*)$", l)
    if m:
        what = ("epic " if m.group(1) else "") + m.group(2)
        urls = list(URL.finditer(m.group(3)))
        if not urls:
            need.append(bang + [(f"merge {what}: no PR on its file", "")])
        for u in urls:
            st = pr_state(u.group(0))
            if st is None:
                need.append(bang + [(f"merge {what}: ", ""), (u.group(0), "dim")])
                continue
            green += st[0] == "done"
            need.append(bang + [(f"merge {pr_ref(u)} (", ""), (SYM[st[0]][0] + " " + st[1], SYM[st[0]][1]), (")  ", ""), (what, "dim")])
        continue
    m = re.match(r"(\S+): (\S+)$", l)
    if m:
        need_slugs.add(m.group(2))
        title = (story_by_slug.get(m.group(2)) or [""] * 9)[8]
        title = f": {title[:1].lower()}{title[1:]}" if title and title != m.group(2) else ""
        need.append(bang + [(f"run {m.group(1)} story {m.group(2)}{title}", "")])
    else:
        need.append(bang + [(l, "")])
for r in recs:
    if r["state"] == "WAITING":
        need.append(bang + [(f"answer {r['name']}: ", ""), (f"herdr agent read {r['name']}", "dim")])
    elif r["state"] == "EMPTY":
        need.append(bang + [(f"close the empty pane {r['name']}: ", ""), ("swarm.sh tidy", "dim")])
need += [bang + [(f"look at {n}: working {age} min with no commit or PR update", "")] for n, age in stalled]
need += [bang + [(f"agree draft HLD {b[1]}: ", ""), (f"/hld {b[1]}", "dim")] for b in board if b[0] == "hld" and b[2] == "draft"]

# Epics: one row per active epic (and any other epic an agent shown works for), its progress, then
# its live agents and open PRs beneath it.
groups = collections.OrderedDict((s, []) for s, b in epics.items() if b[2] == "active")
for r in shown:
    groups.setdefault(r["epic"] if r["epic"] in epics else "", []).append(r)
name_w = min(max((len(r["name"]) for r in shown), default=0), 30 if not NARROW else max(12, (W - 20) // 2))

def agent_row(r):
    row = [("  ", ""), sym(r["sym"]), (f"{cut(r['name'], name_w):<{name_w}}  ", "")]
    if not NARROW:
        row += [(f"{r['role']:<10} ", "dim"), (f"{r['model']:<12} ", "dim")]
    return row + [(r["words"], SYM[r["sym"]][1] if r["sym"] != "done" else "dim")]

def epic_label(slug):
    return slug if epics[slug][2] == "active" else f"{slug} ({epics[slug][2]})"

def epic_rows(slug, members):
    if not slug:
        return [[("  ", ""), ("no epic", "dim")]] + [agent_row(r) for r in members]
    mine = [b for b in stories if b[6] == slug]
    done = finished[slug] + sum(b[2] == "done" for b in mine)
    left = collections.Counter(b[2] or "?" for b in mine if b[2] != "done")
    total = done + sum(left.values())
    prs = [(m, b[1]) for b in mine + [epics[slug]] if b[2] != "done" for m in URL.finditer(b[3])]
    states = [pr_state(m.group(0)) for m, _ in prs]
    k = ("look" if any(r["look"] for r in members) or any(s and s[0] == "failed" for s in states) or any(b[1] in need_slugs for b in mine)
         else "working" if any(r["state"] == "working" for r in members)
         else "review" if prs or left["review"] else "done" if not left else "ready" if left["ready"]
         else "blocked" if set(left) <= {"blocked", "later"} else "unknown")
    bar_w = 6 if NARROW else 12
    fill = round(bar_w * done / total) if total else 0
    order = ["review", "ready", "blocked", "later"]
    counts = " · ".join(f"{left[s]} {s}" for s in order + sorted(s for s in left if s not in order) if left[s])
    rows = [[sym(k), (f"{cut(epic_label(slug), epic_w):<{epic_w}}  ", "b"), ("█" * fill, "ok"), ("░" * (bar_w - fill), "dim"),
             (f" {done:>2}/{total:<2}  " if total else "   –   ", ""), (counts or ("" if total else "no stories on the board or in git"), "dim")]]
    rows += [agent_row(r) for r in members]
    for (m, owner), st in zip(prs, states):
        k = st[0] if st else "review"
        rows.append([("  ", ""), sym(k), (f"{cut(pr_ref(m), name_w):<{name_w}}  ", ""), (st[1] if st else "checks unknown", SYM[k][1]),
                     (f"  {owner}", "dim")])
    return rows

def rank(item):
    # Epics that need you, then working ones, then the rest; agents with no epic last.
    slug, members = item
    if not slug:
        return 3
    if any(r["look"] for r in members) or any(b[6] == slug and b[1] in need_slugs for b in stories):
        return 0
    return 1 if any(r["state"] == "working" for r in members) else 2

# An active epic with no open story and no agent shown is one line for them all.
quiet = [s for s, m in groups.items() if s and not m and not any(b[6] == s and b[2] != "done" for b in stories)]
groups = collections.OrderedDict((s, m) for s, m in groups.items() if s not in quiet)
epic_w = min(max((len(epic_label(s)) for s in groups if s), default=0), W // 3)
epic_view = [row for item in sorted(groups.items(), key=rank) for row in epic_rows(*item)]
if quiet:
    epic_view.append([sym("done"), (f"{len(quiet)} active epic{'' if len(quiet) == 1 else 's'} with no open story: {', '.join(quiet)}", "dim")])
if agents is None:
    epic_view.append([("agents unavailable: herdr is not on PATH, or gave no list", "dim")])
if idle:
    epic_view.append([(f"+{idle} idle", "dim"), ("  (t shows the tree)" if KEYS else "  (--tree lists them)", "dim")])

# The tree (t, or --tree): every agent of this project's panes, by herdr workspace, then tab.
def tree_view():
    if agents is None:
        return [[("agents unavailable: herdr is not on PATH, or gave no list", "dim")]]
    tree = collections.OrderedDict()
    for r in recs:
        tree.setdefault(r["ws"], collections.OrderedDict()).setdefault(r["tab"], []).append(r)
    width = min(max((len(r["name"]) for r in recs), default=0), 30)
    rows = []
    for ws, tabs in tree.items():
        rows.append([(ws, "b")])
        for i, (tab, items) in enumerate(tabs.items()):
            last_tab = i == len(tabs) - 1
            rows.append([(" └─ " if last_tab else " ├─ ", "dim"), (tab, "h")])
            for j, r in enumerate(items):
                stem = ("    " if last_tab else " │  ") + ("└─ " if j == len(items) - 1 else "├─ ")
                row = [(stem, "dim"), sym(r["sym"]), (f"{cut(r['name'], width):<{width}}  ", "")]
                if not NARROW:
                    row += [(f"{r['role']:<10} ", "dim"), (f"{r['model']:<12} ", "dim")]
                rows.append(row + [(r["words"], SYM[r["sym"]][1] if r["sym"] != "done" else "dim"), (f"  {r['prs']}" if r["prs"] else "", "dim")])
    return rows or [[("no agents open in this project's panes", "dim")]]

# Recent: swarm actions (events.tsv), merges on the base branch and fixed findings, newest first.
# Findings are one row per PR and day, and at most a third of the rows, so they never crowd out the rest.
NOW = time.time()
TODAY = datetime.date.today()

def when(s):
    # (sort time, relative time). A date alone (findings.tsv) sorts as the end of that local day,
    # after the day's timed events, and reads in calendar days: today, yesterday, Nd ago.
    try:
        if len(s) == 10:
            days = (TODAY - datetime.date.fromisoformat(s)).days
            return (datetime.datetime.fromisoformat(s + "T23:59:59").astimezone(),
                    "today" if days <= 0 else "yesterday" if days == 1 else f"{days}d ago")
        t = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.astimezone()
        secs = max(int(NOW - t.timestamp()), 0)
        if secs < 86400:
            return t, "now" if secs < 60 else f"{secs // 60}m ago" if secs < 3600 else f"{secs // 3600}h ago"
        days = (TODAY - t.astimezone().date()).days   # a day or more: calendar days, as for a date
        return t, "yesterday" if days <= 1 else f"{days}d ago"
    except ValueError:
        return None, s

STARTS = ("agent", "conduct", "story")
events = []   # (time, actor, text, icon key)
for l in lines("DASH_MERGES"):
    f = l.split("\t", 2)
    if len(f) == 3:
        m = re.match(r"Merge pull request #(\d+) from [^/\s]+/(\S+)", f[2])
        events.append((f[0], f[1], f"merged #{m.group(1)} {m.group(2)}" if m else f[2], "merge"))
found = collections.OrderedDict()
for f in read_tsv(E["DASH_FINDINGS"], 4):
    m = re.search(r"(\d+)\D*$", f[2])
    found.setdefault((f[0], m.group(1) if m else f[2]), []).append(f)
for (day, pr), fs in found.items():
    text = fs[0][3] if len(fs) == 1 else f"{len(fs)} findings: " + "; ".join(x[3] for x in fs)
    events.append((day, fs[0][1] if len(fs) == 1 else "findings", f"{text} (#{pr})", "finding"))
for f in read_tsv(E["DASH_EVENTS"], 5):
    ok = f[4].startswith("ok")
    events.append((f[0], f[3], f"{f[1]} {f[2]}" + ("" if f[4] == "ok" else f": {f[4]}"), "failed" if not ok else "start" if f[1] in STARTS else "action"))
ICON = {"merge": ("⇡", "ok"), "finding": ("✎", "warn"), "start": ("▶", "ok"), "action": ("·", "dim"), "failed": ("✗", "bad")}
dated = sorted(((when(e[0]), e) for e in events if when(e[0])[0]), key=lambda x: x[0][0], reverse=True)

def recent_box(w, n):
    rec, findings = [], 0
    actor_w = 0 if w < 100 else 14
    for (_, ago), (_, actor, text, kind) in dated:
        if len(rec) >= n:
            break
        if kind == "finding":
            findings += 1
            if findings > max(1, n // 3):
                continue
        room = max(w - 4 - 11 - 2 - (actor_w + 2 if actor_w else 0), 0)
        row = [(f"{ago:>9}  ", "dim"), (ICON[kind][0] + " ", ICON[kind][1]), (cut(text, room).ljust(room), "")]
        if actor_w:
            row.append((f"  {cut(actor, actor_w):>{actor_w}}", "dim"))
        rec.append(row)
    return box("recent", rec, w)

def ladder_box(w, cell=30):
    policy = [l.split() for l in lines("DASH_POLICY")]
    ladder = [f"{p[0]:<11}→ {p[2] if p[1] == 'claude' else p[1]} · {p[3]}" for p in policy]
    per = max(1, (w - 4) // cell)
    return box("ladder", [[(c.ljust(cell), "") for c in ladder[i:i + per]] for i in range(0, len(ladder), per)], w)

# Layout. Header: one line, the clock at the right; then the summary line.
right = E.get("DASH_CLOCK") or datetime.datetime.now().strftime("%H:%M:%S")
head = [(os.path.basename(E["DASH_PROJECT"].rstrip("/")), "b"), (f"  swarm-dev {E['DASH_VERSION']}", "dim"),
        ("  merge ", "dim"), (E["DASH_MERGE"], ""), ("  next ", "dim"), (E["DASH_NEXT"], "warn")]
if sum(len(t) for t, _ in head) > W - len(right) - 1:
    head = head[:1] + head[4:]   # narrow: the version and merge mode go before next is cut
out.append(fit(head, W - len(right) - 1) + " " + paint(right, "dim"))
n_active = sum(b[2] == "active" for b in epics.values())
n_working = sum(r["state"] == "working" for r in recs)
summary = [(f"{n_active} epics active", ""), (" · ", "dim"), (f"{n_working} agents working", "ok" if n_working else ""), (" · ", "dim"),
           (f"{green} PRs green, waiting", "ok" if green else ""), (" · ", "dim"), (f"{len(stalled)} stalled", "bad" if stalled else "")]
if E.get("DASH_COST"):
    summary += [(" · ", "dim"), (f"${E['DASH_COST']} today", "")]
out.append(fit(summary, W))
drift = int(E.get("DASH_DRIFT") or 0)
if drift:
    out.append(fit([(f"board: {drift} uncommitted edit{'' if drift == 1 else 's'} in the main checkout (reconcile pulls first)", "warn")], W))

out += box("needs you", [l for r in need for l in wrap(r, W - 4)], W, "bad") if need else [fit([sym("done"), ("nothing needs you", "dim")], W)]
if E.get("DASH_TREE") == "1":
    out += box("agents by workspace and tab", tree_view(), W)
elif epic_view:
    out += box("epics", epic_view, W)
if blocked or later:
    out.append(fit([sym("blocked"), (f"{blocked} blocked · {later} later  (swarm.sh status --all lists them)", "dim")], W))

# The legend, packed onto as few lines as the width allows.
legend, cur = [], ""
for item in LEGEND + (["q quit · t tree · l ladder · r redraw"] if KEYS else []):
    if cur and len(cur) + 3 + len(item) > W:
        legend.append(cur); cur = item
    else:
        cur = f"{cur}   {item}" if cur else item
legend.append(cur)

# Recent fills the height left; from 140 columns a shown ladder sits beside it.
ladder = E.get("DASH_LADDER") == "1"
if ladder and W < 140:
    out += ladder_box(W)
# A watched frame drops what does not fit, never the legend; a one-shot dash shows at least 5 rows.
room = H - len(out) - 2 - len(legend) if H else 8
if not KEYS:
    room = max(5, room)
if ladder and W >= 140:
    lw = 64
    lad = ladder_box(lw)
    rec = recent_box(W - lw - 1, max(room, len(lad) - 2))
    out += [(a or " " * lw) + " " + (b or "") for a, b in itertools.zip_longest(lad, rec, fillvalue=None)]
elif room > 0:
    out += recent_box(W, room)
if KEYS and H:
    out = out[:max(H - len(legend), 0)]   # a watched frame never scrolls the screen
out += [fit([(cut(l, W), "dim")], W) for l in legend]
if KEYS and H:
    out = out[:H]
print("\n".join(l.rstrip() for l in out))
PY
}

# tab_label <name> — the tab label an agent name came from. Agent names stop at 32 characters
# (agent_name), tab labels do not, so `next` can hand back a name that is not the label. The first
# state file whose agent name matches wins: the base tab sorts before its "-2", "-3" overflow.
tab_label() {
  local want state
  want="$(agent_name "$1")"
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" && "$(agent_name "$(basename "${state}")")" == "${want}" ]] || continue
    basename "${state}"; return
  done
  echo "$1"
}

# close_agent <name> — close what was opened for <name>: its pane, or its tab when that was the
# tab's last pane. A conductor's name closes its epic's tabs, with any story panes left in them.
# With keep_panes = true, everything stays open to read, and the agent is only retired.
close_agent() {
  local state pane epic
  if [[ "${CFG_keep_panes}" == true ]]; then retire_agent "$1"; return; fi
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    pane="$(awk -v n="$1" 'NF > 1 && $2 == n { print $1; exit }' "${state}")"
    [[ -n "${pane}" ]] || continue
    if [[ $(wc -l < "${state}") -le 1 ]]; then close_tabs "$(basename "${state}")"; return; fi
    herdr pane close "${pane}" >/dev/null
    awk -v p="${pane}" '$1 != p' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
    echo "closed pane $1"; return
  done
  if [[ "$(agent_name "$1")" == conduct-* ]]; then
    epic="$(conduct_epic "$1")"
    close_tabs "${epic}"
  fi
  close_tabs "$1"
}

# free_agent_name <name> — herdr refuses a name already in use (agent_name_taken). With
# keep_panes = true a finished agent keeps its name, so a second run reusing it (a second epic's
# `lead`) failed and left an empty pane. Retire a finished holder; refuse a working one. Names are
# unique across every herdr workspace, so a holder in another project is refused, never retired:
# it is that project's agent. Runs before any pane opens.
free_agent_name() {
  local status
  status=$(agent_status "$1")
  case "${status}" in
    "") [[ -z "$(agent_field "$1" agent_status any)" ]] && return 0
        die "$1: an agent this project did not start (no tab record in .swarm/state) holds this name (herdr agent list); it is never retired from here. Wait for it to finish, or close its pane" ;;
    working|blocked) die "$1: an agent with this name is still ${status}; wait for it, or use another name" ;;
  esac
  retire_agent "$1" >/dev/null
  [[ -z "$(agent_status "$1")" ]] || die "$1: the name is still taken after retiring it; close its pane (herdr agent list), or use another name"
}

# agent_field <name> <field> [any] — <field> (agent_status, pane_id) of this project's agent called
# <name> (its pane is one own_panes recorded), or nothing. With "any", of whichever project's agent
# holds the name: herdr names are unique across all workspaces.
agent_field() {
  herdr agent list 2>/dev/null | SWARM_NAME="$1" SWARM_FIELD="$2" SWARM_ANY="${3:-}" SWARM_PANES="$(own_panes)" json "next((a.get(e['SWARM_FIELD']) or ('unknown' if e['SWARM_FIELD']=='agent_status' else '') for a in d['result']['agents'] if a.get('name')==e['SWARM_NAME'] and (e['SWARM_ANY'] or a.get('pane_id') in e['SWARM_PANES'].split())),'')" 2>/dev/null || true
}

# agent_status <name> — herdr's status for this project's agent called <name>, or nothing if there is none.
agent_status() { agent_field "$1" agent_status; }

# own_target <name> — the pane of this project's agent called <name>, to address herdr by: a name
# alone could reach another project's agent, since herdr names span workspaces.
own_target() {
  local pane
  pane="$(agent_field "$1" pane_id)"
  [[ -n "${pane}" ]] || die "$1: no agent this project started holds this name now: it has exited or its pane was closed, or another project holds the name, which is never addressed"
  echo "${pane}"
}

# retire_agent <name> — leave <name>'s pane open, but free its name for the next agent (a story
# retried, a new conductor for the epic): herdr renames the agent <name>-done, and the pane keeps
# its slot in the tab's state under that name, so no later agent is split into it.
retire_agent() {
  local name state new i pane
  name="$(agent_name "$1")"
  # A name reused more than once already has a <name>-done; take the first free suffix (free in any
  # project: names are unique across workspaces).
  new="${name:0:27}-done"
  for i in 2 3 4 5 6 7 8 9; do
    [[ -z "$(agent_field "${new}" agent_status any)" ]] && break
    new="${name:0:26}-done${i}"
  done
  # By pane, and only this project's: renaming by name would rename another project's agent.
  pane="$(agent_field "${name}" pane_id)"
  if [[ -z "${pane}" ]]; then echo "no agent this project started is called $1; nothing to retire"; return 0; fi
  herdr agent rename "${pane}" "${new}" >/dev/null 2>&1 \
    || die "$1: herdr could not rename it to ${new}, so its name is not free; close its pane (herdr agent list)"
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    # That pane's tab record only: STATE_DIR also holds codex briefs, whose prose must not change.
    awk -v p="${pane}" -v n="${new}" 'NF == 2 && $1 == p { $2 = n } { print }' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
  done
  echo "kept $1 open (keep_panes)"
}

# tidy [--yes] — the panes this script opened that hold nothing to read any more: no agent in them
# (a start that failed) or a retired agent (<name>-done, left open by keep_panes). Lists them; with
# --yes, closes them and drops them from the tab records. Working, waiting and idle agents are never
# touched, nor the pane this runs in. Run it when nothing is starting: a pane whose agent is still
# starting has no agent yet, so it looks empty.
tidy_panes() {
  local yes="${1:-}" agents panes closable pane name reason file n=0
  [[ "${yes}" != --yes || -n "${HERDR_PANE_ID:-}" ]] || die "tidy --yes: HERDR_PANE_ID is not set, so this pane could not be kept open"
  agents=$(herdr agent list 2>/dev/null) || die "tidy: herdr gave no agent list"
  panes=$(herdr pane list 2>/dev/null) || die "tidy: herdr gave no pane list"
  closable=$(SWARM_PANES_PY="${PANES_PY}" SWARM_OWN="$(own_panes)" python3 - "${STATE_DIR}" "${agents}" "${panes}" "${HERDR_PANE_ID:-}" <<'PY'
import json, os, sys
exec(os.environ["SWARM_PANES_PY"])
state, agents_json, panes_json, me = sys.argv[1:5]
agents = {a.get("pane_id"): a for a in json.loads(agents_json)["result"]["agents"]}
live = {p["pane_id"] for p in json.loads(panes_json)["result"]["panes"]}
for tab, pane, recorded in pane_records(state, (set(os.environ["SWARM_OWN"].split()) & live) - {me}):
    a = agents.get(pane)
    name = (a or {}).get("name") or recorded
    reason = {"EMPTY": "empty: no agent started", "retired": "retired"}.get(agent_state(a, name)[0])
    if reason:
        print("\t".join((pane, name, reason, tab)))
PY
) || die "tidy: could not read herdr's lists"
  if [[ -z "${closable}" ]]; then echo "nothing to tidy"; return 0; fi
  while IFS=$'\t' read -r pane name reason file; do echo "  ${name}  ${reason}  [${file} ${pane}]"; done <<< "${closable}"
  if [[ "${yes}" != --yes ]]; then echo "(swarm.sh tidy --yes closes them)"; return 0; fi
  while IFS=$'\t' read -r pane name reason file; do
    herdr pane close "${pane}" >/dev/null 2>&1 || { echo "could not close ${pane} (${name})"; continue; }
    { awk -v p="${pane}" '$1 != p' "${STATE_DIR}/${file}" > "${STATE_DIR}/${file}.tmp" && mv "${STATE_DIR}/${file}.tmp" "${STATE_DIR}/${file}"; } \
      || die "tidy: closed ${pane} but could not update ${STATE_DIR}/${file}"
    [[ -s "${STATE_DIR}/${file}" ]] || rm -f "${STATE_DIR}/${file}"
    n=$((n + 1))
  done <<< "${closable}"
  echo "closed ${n}"
}

# close_tabs <label> — close every tab this script opened under <label>, and its state. A tab may be
# in another workspace (a conductor's is its HLD's): its first pane id, "<workspace>:<pane>", says which.
close_tabs() {
  local label state tab_label id ws
  label="$(tab_label "$1")"
  for state in "${STATE_DIR}/${label}" "${STATE_DIR}/${label}"-*; do
    [[ -f "${state}" ]] || continue
    tab_label="$(basename "${state}")"
    ws="$(head -1 "${state}")"; ws="${ws%%:*}"; ws="${ws:-${HERDR_WORKSPACE_ID}}"
    id=$(herdr tab list --workspace "${ws}" | python3 -c "
import json,sys
for t in json.load(sys.stdin)['result']['tabs']:
    if t.get('label') == sys.argv[1]: print(t['tab_id'])" "${tab_label}")
    # Two tabs can carry one label (a run that reopened it); close each, one id per call.
    while read -r t; do [[ -z "${t}" ]] || herdr tab close "${t}" >/dev/null; done <<< "${id}"
    rm -f "${state}"
    echo "closed ${tab_label}"
  done
}

# Everything runs from main, called on the last line with `exit` beside it: bash reads a
# script as it executes, so a `git pull` that rewrites this file during a long `wait` would
# otherwise make it resume reading the new file mid-line.
# dispatch <command> [args] — run one command.
dispatch() {
  cmd="${1:-}"; shift || true
  case "${cmd}" in
    policy) policy "${1:?role}" ;;
    agent)  require_herdr; start_agent "$@" ;;
    story)  require_herdr; build_story "${1:?slug}" ;;
    conduct) require_herdr; start_conductor "${1:?epic}" ;;
    close)  require_herdr; close_agent "${1:?name}" ;;
    tell)   require_herdr; tell_agent "${1:?slug}" "${2:?file}" ;;
    unblock) unblock ;;
    next)   next_step ;;
    status) status_report "${1:-}" ;;
    dash)   dash "$@" ;;
    tidy)   require_herdr; tidy_panes "${1:-}" ;;
    cost)   cost_report "${1:-}" ;;
    log-finding) record_finding "${1:-}" "${2:-}" "${*:3}" ;;
    lessons) lessons_report "${1:-}" ;;
    watch)  watch_prs "$@" ;;
    finish) finish_item "${1:?slug}" ;;
    review) mark_review "$@" ;;
    reconcile) reconcile ;;
    findings) findings "${1:?repo}" "${2:?pr}" ;;
    config) show_config "${1:-}" ;;
    base)   src="$(repo_dir "${1:-}")" || die "${src}"; base_for "${src}" ;;
    _base)  base_for "${1:?repo dir}" ;;                          # test hook: the base branch for a repo
    _name)  agent_name "${1:?slug}"; echo ;;                      # test hook: the agent name for a slug
    _target) own_target "$(agent_name "${1:?name}")" ;;          # this project's pane for an agent name, to address herdr by
    _label) tab_label "${1:?name}" ;;                             # test hook: the tab label for an agent name
    _trusted) require_trusted "${1:?cwd}"; echo trusted ;;        # test hook: whether Claude Code trusts a folder
    _pane)  require_herdr; next_pane "${1:?tab}" "${2:?cwd}" "${3:-}" ;;   # layout test hook: a pane, no agent
    wait)   require_herdr; stall=""; if [[ "${1:-}" == --stall ]]; then stall=--stall; shift; fi
            n="$(agent_name "${1:?name}")"
            if [[ "${n}" == conduct-* && ! "${n}" =~ -done[0-9]*$ ]]; then wait_conductor "${n}" "${2:-3600000}"
            else wait_agent "${n}" "${2:-3600000}" "${stall}"; fi ;;
    *) awk 'NR > 1 && /^#$/ && ++blank == 2 { exit } NR > 1' "$0"; exit 2 ;;   # the header up to the command list's end
  esac
}

# READ_ONLY_COMMANDS change nothing, so they are not logged: the readers, the waits conductors run
# all the time (wait, watch), and the test hooks (_name ...; _pane opens a pane for a layout test only).
# Every other command is logged (fail closed: a new command is logged until it is named here), and so
# is tidy --yes; tidy alone only lists. A command that is not one (a typo, --help) is not logged.
READ_ONLY_COMMANDS="dash status next config policy cost lessons findings wait watch base _base _name _target _label _trusted _pane"

# is_command <name> — true when <name> is one of dispatch's arms, read off its case statement.
is_command() {
  awk -v want="$1" '/^dispatch\(\) \{/ { d = 1; next } d && /^  esac/ { exit 1 }
    d && match($0, /^    [a-z_|-]+\)/) { n = split(substr($0, 5, RLENGTH - 5), a, "|"); for (i = 1; i <= n; i++) if (a[i] == want) exit 0 }' "$0"
}

# kill_tree <pid> — TERM a process and everything under it, children first, so nothing is orphaned.
# shellcheck disable=SC2317,SC2329 # called from main_signal
kill_tree() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "${c}"; done
  kill -TERM "$1" 2>/dev/null || true
}

# main_signal <INT|TERM|HUP> — stop the logged command at once (it runs in the background, so this
# trap runs as soon as the signal lands), log it as interrupted, remove the temp file, and die of the
# same signal, so the exit status stays 128+N.
# shellcheck disable=SC2317,SC2329 # invoked by the signal traps
main_signal() {
  [[ -z "${EV_CHILD:-}" ]] || kill_tree "${EV_CHILD}"
  record_event "${EV_CMD}" "${EV_TARGET#+}" interrupted
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  trap - "$1"
  kill -"$1" "$$"
}

# main <command> [args] — dispatch, and log each command that is not read-only to EVENTS_LOG with its
# outcome: ok, interrupted, the first line of a die at the command's own level, or failed (exit N).
# A die inside a nested $(...) gives only failed (exit N): a caller may have tolerated it, so its
# message could name the wrong failure; it was printed to stderr all the same. reconcile and unblock
# log one line per item themselves.
main() {
  local rc why
  EV_CMD="${1:-}"; EV_TARGET=""; EV_ERR=/dev/null; EV_CHILD=""
  if [[ -z "${EV_CMD}" || " ${READ_ONLY_COMMANDS} " == *" ${EV_CMD} "* || ( "${EV_CMD}" == tidy && "${2:-}" != --yes ) ]] \
     || ! is_command "${EV_CMD}"; then
    dispatch "$@"; return
  fi
  case "${EV_CMD}" in
    agent) [[ -z "${3:-}" ]] || EV_TARGET="$(agent_name "$3")" ;;
    log-finding) EV_TARGET="${2:-} ${3:-}"; EV_TARGET="${EV_TARGET# }"; EV_TARGET="${EV_TARGET% }" ;;
    reconcile|unblock) EV_TARGET=+ ;;
    tidy) EV_TARGET=- ;;
    *) EV_TARGET="${2:-}" ;;
  esac
  EV_ERR="$(mktemp "${TMPDIR:-/tmp}/swarm-die.XXXXXX" 2>/dev/null)" || EV_ERR=/dev/null
  trap 'main_signal INT' INT; trap 'main_signal TERM' TERM; trap 'main_signal HUP' HUP
  # In the background, with stdin kept, so `wait` returns the moment a signal lands.
  set +e
  (DIE_FILE="${EV_ERR}"; DIE_LEVEL="${BASH_SUBSHELL}"; set -e; dispatch "$@") <&0 &
  EV_CHILD=$!
  wait "${EV_CHILD}"; rc=$?
  set -e
  trap - INT TERM HUP
  if [[ ${rc} -ne 0 ]]; then
    why="$(head -1 "${EV_ERR}" 2>/dev/null || true)"
    record_event "${EV_CMD}" "${EV_TARGET#+}" "${why:-failed (exit ${rc})}"
  elif [[ "${EV_TARGET}" != + ]]; then
    record_event "${EV_CMD}" "${EV_TARGET}"
  fi
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  return "${rc}"
}

main "$@"; exit
