#!/usr/bin/env bash
# swarm.sh — run agents in herdr panes so every one can be watched.
#
#   swarm.sh agent <tab> <name> <cwd> <role> <prompt-file>   start one agent in its own pane
#   swarm.sh story <slug>                                   build one <board>/stories/<slug>.md
#   swarm.sh conduct <epic>                                 a fresh conductor for one epic, in a workspace named for its HLD
#   swarm.sh wait [--stall] <name> [timeout-ms]             block until the agent settles; --stall: also exit 3 when a builder stalls
#   swarm.sh policy <role>                                  print the model and effort for a role
#   swarm.sh close <name> [cause]                           close a story's pane, a conductor's epic tab, or a tab and its overflow; closing a ready story's builder counts a failed build (attempts:) and clears its worktree, branch and PR; cause: met, impossible, stalled, bound, paused or cleared-on-error (the last three count nothing; impossible makes the story the lead's, and paused and cleared-on-error hold it for the lead), required with goal on while the story is ready
#   swarm.sh tell <slug> <kind> <file>                      send an idle builder (or any agent) a file's contents; kind: findings, nudge or resume
#   swarm.sh cost [--since YYYY-MM-DD]                      tokens and estimated cost per role, from the agents' logs
#   swarm.sh outcomes [--since YYYY-MM-DD]                  one TSV row per builder: story, kind, model, cost, tells, findings, PR, attempt
#   swarm.sh decisions [--since YYYY-MM-DD]                 JSONL, one object per decision the logs record (model, retry, finding, nudge, close) and its outcome
#   swarm.sh log-finding [--declined] <kind> <pr-url> <text>  log one review finding that was fixed (or, --declined, declined), by its kind (the outer loop)
#   swarm.sh lessons [--all]                                kinds recurring in 3+ PRs (or tagged lead memories) with no rule in lessons_file yet, and a long brief
#   swarm.sh next                                           the chain's next step, read from the board (resumable)
#   swarm.sh status [--all]                                 agents that need a look, what waits on you, and the next step
#   swarm.sh dash [--watch [seconds]] [--ladder] [--tree]  a read-only dashboard: what needs you, epics with their agents and PRs, recent events; --watch redraws in place, q quits, t tree, l ladder
#   swarm.sh tidy [--yes]                                   list, and with --yes close, empty panes and retired agents' panes
#   swarm.sh unblock                                        mark ready every blocked story whose blockers are all finished
#   swarm.sh finish <slug>                                  take a merged story or epic off the board (delete or mark done)
#   swarm.sh reset <slug> <reason>                          put an escalated story back as it was: its kind, no attempts:, no lead's block; for a held story (held_for:), lift the hold and keep attempts:
#   swarm.sh drop <slug> <reason>                           take an escalated story off the board; the lead commits that in a board PR
#   swarm.sh dialog <slug> <accepted|dismissed>             log how a builder's Fable usage-credits consent dialog was answered
#   swarm.sh review <slug> <pr-url>...                      a story or epic whose PRs are green and reviewed now waits on a human merge
#   swarm.sh reconcile                                      finish each review item whose PRs all merged; a closed one goes back to ready
#   swarm.sh findings <repo> <pr>                           every check-run note on a PR's head, and its open code-scanning alerts
#   swarm.sh watch [repo...]                                wait until a story or epic PR needs the lead, print why, and exit
#   swarm.sh config [key]                                   the project's settings and where each came from, or one value
#   swarm.sh init                                           from a git repo's root: add the board, .claude/swarm/ and the .gitignore lines
#   swarm.sh base <repo>                                    the base branch a repo's stories start from and its PRs go into
#   swarm.sh codex-review <base>                            codex's review of this directory against origin/<base>, stopped after codex_minutes
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
# A failed lookup (offline) is not an error: /swarm-dev:swarm must still run.
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
CFG_stall_minutes=30    # an agent working this long with no sign of life (a builder: commit, PR update or swarm action) is stalled?
CFG_sonnet_share=0      # N > 0: 1 in N code stories without risk: high is built on Sonnet (code-sonnet), to compare
CFG_escalate_after=2   # N > 0: a story whose attempts: reaches N is built as escalate (Fable); 0 is off
CFG_builder_subagent_model=""  # empty: building roles' subagents keep Claude Code's choice; else forced to this model
CFG_goal=off            # N > 0: each builder gets a goal condition (.swarm/briefs/<slug>.goal.md) bounded at N turns
CFG_codex_minutes=10    # codex-review stops a codex review that runs this long
CFG_lead=off            # session: a lead session acts for the user, so dash splits needs you into the user's steps and a lead's queue
CONFIG_KEYS="board_dir repos_dir base_branches finished merge review_bot sign_commits pr_per keep_panes lessons_file stall_minutes sonnet_share escalate_after builder_subagent_model goal codex_minutes lead"
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
      stall_minutes|codex_minutes)
        [[ "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: ${key} must be a positive whole number, not '${value}'" ;;
      sonnet_share|escalate_after)
        [[ "${value}" =~ ^(0|[1-9][0-9]*)$ ]] || die "${where}: ${key} must be a non-negative whole number, not '${value}'" ;;
      builder_subagent_model)
        [[ "${value}" =~ ^[A-Za-z0-9._-]*(\[1m\])?$ ]] || die "${where}: builder_subagent_model must be a model name such as haiku, not '${value}'" ;;
      goal)
        [[ "${value}" == off || "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: goal must be off or a positive whole number of turns, not '${value}'" ;;
      lead)
        [[ "${value}" == off || "${value}" == session ]] || die "${where}: lead must be off or session, not '${value}'" ;;
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
ROLE_GROUPS="design:hld,hld-review,hld-lead planning:survey,lead,skeptic,critic,codex building:code,code-risky,code-sonnet,docs,chore,verify,escalate conducting:conduct"
roles() { local g r=""; for g in ${ROLE_GROUPS}; do r+=" ${g#*:}"; done; r="${r//,/ }"; echo "${r# }"; }
# BUILDER_ROLES: the building group, the roles that build a story (outcomes, builder_subagent_model).
BUILDER_ROLES="${ROLE_GROUPS#*building:}"; BUILDER_ROLES="${BUILDER_ROLES%% *}"; BUILDER_ROLES="${BUILDER_ROLES//,/ }"
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
    code-sonnet) echo "claude sonnet high" ;;  # the sonnet_share sample of code stories, measured against code
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
#   agent_state(a, name, s=None) -> (state, needs_a_look), where a is herdr's agent in the pane (None
#     for an empty pane) and s is session_state's answer for <name>: EMPTY (a start that failed),
#     then from the session: working (busy), idle, WAITING (waiting; s[1] says on what), unknown or
#     gone (both need a look). With no session (s None: codex, none recorded, or a retired
#     <name>-done, which has no agents.tsv line of its own), herdr's word: WAITING (blocked on a
#     prompt), working, retired (renamed by retire_agent), or herdr's own status.
#   session_state(log, name, listing) -> (state, waitingFor) from Claude Code's own list: the newest
#     agents.tsv (<log>) line for <name>, its session id, then that id's entry in <listing> (the
#     text of `claude agents --json`, None when the call failed). state is busy, idle, waiting (with
#     waitingFor, when the entry has it, on one line and cut to WHY_MAX characters), unknown (the
#     call failed, or a status it does not know) or gone (no entry for the recorded session, or one
#     with no status: Claude Code lists status only while the process is alive). None for an agent
#     herdr must answer for: codex, no line, or a session of '-' (session_id's None).
#   login_expired(log, name, projects) -> True when the last user or assistant entry in <name>'s
#     transcript (<projects>/*/<session>.jsonl, the file cost finds) is Claude Code's "Login expired ·
#     Please run /login": an assistant entry whose error field is authentication_failed. A prompt
#     after it (a resume sent) clears it; Claude Code's own user entries do not (is_prompt: isMeta, a
#     <task-notification>, "[Request interrupted by user]", a slash command such as /login run in its
#     pane and its <local-command-stdout>). A transcript that cannot be read is not
#     expired. Never the pane.
#   shown_state(a, name, s, log, projects) -> agent_state, except that an idle Claude agent whose
#     login expired is (auth, True): only the user's /login clears it, so it needs them, never idle.
#     For the views (status, dash); wait reads login_expired itself.
PANES_PY='
import glob, json, os, re
WHY_MAX = 60
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
def agent_state(a, name, s=None):
    if a is None:
        return "EMPTY", True
    if s is not None:
        st = {"busy": "working", "waiting": "WAITING"}.get(s[0], s[0])
        return st, st not in ("working", "idle")
    st = a.get("agent_status") or "unknown"
    if st == "blocked":
        return "WAITING", True
    if st == "working":
        return "working", False
    if re.search(r"-done\d*$", name):
        return "retired", False
    return st, False
def session_id(log, name):
    line = None
    try:
        for l in open(log, encoding="utf-8", errors="replace"):
            f = l.rstrip("\n").split("\t")
            if len(f) == 7 and f[2] == name:
                line = f
    except OSError:
        pass
    return line[6] if line and line[3] == "claude" and line[6] not in ("", "-") else None
AUTOMATED_PROMPTS = ("<task-notification>", "[Request interrupted", "<command-name>", "<local-command")
def is_prompt(d):
    c = (d.get("message") or {}).get("content")
    if isinstance(c, list):
        c = next((x.get("text") for x in c if isinstance(x, dict) and x.get("type") == "text"), "")
    return not d.get("isMeta") and not str(c or "").startswith(AUTOMATED_PROMPTS)
def login_expired(log, name, projects):
    sid, last = session_id(log, name), None
    for path in glob.glob(os.path.join(projects, "*", sid + ".jsonl")) if sid else []:
        try:
            for l in open(path, encoding="utf-8", errors="replace"):
                if "\"type\":\"assistant\"" not in l and "\"type\":\"user\"" not in l:
                    continue
                try:
                    d = json.loads(l)
                except ValueError:
                    continue
                if not isinstance(d, dict) or d.get("isSidechain"):
                    continue
                if d.get("type") == "assistant" or (d.get("type") == "user" and is_prompt(d)):
                    last = d
        except OSError:
            return False
        break
    return last is not None and last.get("type") == "assistant" and last.get("error") == "authentication_failed"
def shown_state(a, name, s, log, projects):
    st, look = agent_state(a, name, s)
    return ("auth", True) if st == "idle" and s is not None and login_expired(log, name, projects) else (st, look)
def session_state(log, name, listing):
    sid = session_id(log, name)
    if sid is None:
        return None
    try:
        entries = json.loads(listing) if listing is not None else None
    except ValueError:
        entries = None
    if not isinstance(entries, list):
        return "unknown", ""
    e = next((x for x in entries if isinstance(x, dict) and x.get("sessionId") == sid), None)
    st = e.get("status") if e is not None else None
    if st is None:
        return "gone", ""
    if st == "waiting":
        why = " ".join(str(e.get("waitingFor") or "").split())
        return st, why if len(why) <= WHY_MAX else why[:WHY_MAX - 1] + "…"
    return (st, "") if st in ("busy", "idle") else ("unknown", "")
'

# STALL_PY: the one stall rule and agent-to-story mapping, shared by dash and `wait --stall` (each
# python exec's it from $SWARM_STALL_PY). herdr gives no time an agent entered its state, so a
# builder's last sign of life stands in for it.
#   story_for(name, stories) -> the slug whose agent is <name> (cut at 32 characters, any -doneN
#     dropped), preferring a story not done; stories are (slug, agent name, status). None if none.
#   sign_time(f) -> an events.tsv line's (fields) epoch when it is a sign of life, else None. A
#     nudge is not one, so `nudge` (wait's) and `tell:nudge` (the lead's) lines are skipped, and so
#     is any other tell whose outcome is not ok: it never reached the builder.
#   last_seen(events) -> {target: epoch} of each target's newest sign_time line, read once.
#   stall_age(seen, slug, name, signs, now) -> minutes before now (default: the clock) of the newest
#     of: seen[slug] or seen[name] (started, findings sent ...) and each of signs: epoch seconds (a
#     worktree's last commit or edit, an agent's session log write, the time a wait began) or ISO
#     times (a PR's updatedAt). None when there is no sign at all.
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
def sign_time(f):
    t = epoch(f[0]) if len(f) == 5 else None
    if t is None or f[1] in ("nudge", "tell:nudge") or (f[1].split(":")[0] == "tell" and f[4] != "ok"):
        return None
    return t
def last_seen(events):
    seen = {}
    try:
        for l in open(events, encoding="utf-8", errors="replace"):
            f = l.rstrip("\n").split("\t")
            t = sign_time(f)
            if t is not None and t > seen.get(f[2], 0):
                seen[f[2]] = t
    except OSError:
        pass
    return seen
def stall_age(seen, slug, name, signs, now=None):
    ts = [t for t in [seen.get(slug), seen.get(name)] + [epoch(x) for x in signs if x] if t is not None]
    return max(int(((now or time.time()) - max(ts)) // 60), 0) if ts else None
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

# MIN_CLAUDE: the oldest Claude Code with both `--session-id` and `claude agents --json`, which every
# Claude agent's state is read through (pinned by experiment; README's Requirements names it too).
MIN_CLAUDE=2.1.145
GOAL_MIN_CLAUDE=2.1.269   # the oldest with /goal, which goal = N needs (the epic's floor; the spike ran 2.1.299)
CLAUDE_CHECKED=""   # set once require_claude passes, so a run checks once

# require_claude [min] — stop unless the installed Claude Code is <min> (default MIN_CLAUDE) or later
# (`claude --version` prints `2.1.145 (Claude Code)`). When the caller is a Claude session herdr knows (the pane it runs
# in), that session must also be in Claude Code's own list (require_listed), or the readers would
# find no agent there. From a plain shell with no session, only the version is checked. Once a
# check passes, later calls in the same run return at once: `story` checks before its worktree (with
# goal on, for GOAL_MIN_CLAUDE), then start_agent asks again.
require_claude() {
  local min="${1:-${MIN_CLAUDE}}" have session
  [[ -z "${CLAUDE_CHECKED:-}" ]] || return 0
  command -v claude >/dev/null || die "Claude Code (claude) is not on PATH; swarm.sh needs ${min} or later."
  have="$(claude --version 2>/dev/null)" || have=""
  python3 -c '
import re, sys
m = re.match(r"\s*(\d+)\.(\d+)\.(\d+)", sys.argv[1])
sys.exit(0 if m and tuple(map(int, m.groups())) >= tuple(map(int, sys.argv[2].split("."))) else 1)' "${have}" "${min}" \
    || die "swarm.sh needs Claude Code ${min} or later, and claude --version says '${have%%$'\n'*}'. Update it (claude update), then try again."
  session="$(session_for_pane "${HERDR_PANE_ID:-}")"
  [[ -z "${session}" ]] || require_listed "${session}"
  CLAUDE_CHECKED=1
}

# require_listed <session> — stop unless <session> is in claude agents --json. A list that cannot be
# read stops too, and says so (its first error line, or what it printed instead of a JSON list).
require_listed() {
  local err list rc=0 why found
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-agents.XXXXXX")" || die "could not make a temporary file to read claude agents --json"
  list="$(claude_agents "${err}")" || rc=$?
  why="$(head -1 "${err}")"; rm -f "${err}"
  [[ ${rc} -eq 0 ]] || die "could not read claude agents --json (${why:-it exited ${rc}}), so this session (${1}) cannot be found in it. Check that the command works here, then try again."
  found="$(printf '%s' "${list}" | python3 -c '
import json, sys
text = sys.stdin.read()
try:
    entries = json.loads(text)
except ValueError:
    entries = None
if not isinstance(entries, list):
    print("empty output" if not text.strip() else "not a JSON list")
else:
    print("yes" if any(isinstance(e, dict) and e.get("sessionId") == sys.argv[1] for e in entries) else "no")' "$1")" || found=""
  case "${found}" in
    yes) ;;
    no) die "this session (${1}) is not in claude agents --json: the interactive listing every agent's state is read from is missing. Restart Claude Code on ${MIN_CLAUDE} or later, then try again." ;;
    *) die "could not read claude agents --json (${found:-python3 could not parse it}), so this session (${1}) cannot be found in it. Check that the command works here, then try again." ;;
  esac
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
  # Before the pane opens, so a refusal leaves no empty pane behind. A claude agent's session id is
  # minted here, once, so a retry reuses it and agents.tsv holds it from the start; codex has none.
  local session=-
  if [[ "${kind}" == claude ]]; then
    require_trusted "${cwd}"
    require_claude
    session="$(python3 -c 'import uuid; print(uuid.uuid4())')" || die "${name}: could not mint a session id (python3)"
  fi
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
      # builder_subagent_model: the session's env, through --settings since herdr passes no env. Without
      # _FORCE the model setting leaves an Explore subagent on the parent's model (opusplan-spike).
      [[ -n "${CFG_builder_subagent_model}" && " ${BUILDER_ROLES} " == *" ${role} "* ]] && guard+=(--settings \
        "{\"env\":{\"CLAUDE_CODE_SUBAGENT_MODEL\":\"${CFG_builder_subagent_model}\",\"CLAUDE_CODE_SUBAGENT_MODEL_FORCE\":\"1\"}}")
      out=$(herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- \
        --model "${model}" --effort "${effort}" --session-id "${session}" --permission-mode auto ${guard[@]+"${guard[@]}"} 2>&1) && break
    fi
    if [[ ${try} -eq 2 ]]; then
      # Close the pane rather than leave an empty shell; next_pane prunes it from the tab record.
      herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
      die "${name}: herdr could not start the agent: ${out}"
    fi
    sleep 3
  done
  # Before the brief, so an agent whose brief is not taken up is still on record.
  record_agent "${role}" "${name}" "${kind}" "${model}" "${effort}" "${session}"
  if [[ "${kind}" == codex && -n "$(codex_out_dir "${tab}")" ]]; then
    # Its working directory is the output dir, so say where the brief's relative paths start.
    local brief="${STATE_DIR}/brief-${name}.md"
    mkdir -p "${STATE_DIR}"
    { echo "The project is ${PROJECT_DIR}; every relative path below is relative to it. You can write only in $(codex_out_dir "${tab}")."; echo; cat "${prompt_file}"; } > "${brief}"
    prompt_file="${brief}"
  fi
  deliver_prompt "${name}" "${prompt_file}" "${pane}"
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

# CLAUDE_PROJECTS: Claude Code's per-project folders (session transcripts, memory), read by cost, outcomes,
# lessons and wait's login_expired.
CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/projects}"

# AGENTS_LOG: one line per agent started (date, role, name, kind, model, effort, session), so
# `cost` can attribute every token to a role. Beside state/, not in it: state/ holds tab records.
AGENTS_LOG="${PROJECT_DIR}/.swarm/agents.tsv"

# session_for_pane <pane> — the Claude session id herdr reports for the agent in <pane>, or nothing.
session_for_pane() {
  herdr agent list 2>/dev/null | json "next(((a.get('agent_session') or {}).get('value','') for a in d['result']['agents'] if a.get('pane_id')=='$1'),'')" 2>/dev/null || true
}

# claude_agents [err-file] — Claude Code's own list of its sessions, as JSON; fails when it cannot be
# read. Its errors go to <err-file>, else nowhere.
claude_agents() { claude agents --json 2>"${1:-/dev/null}"; }

# session_state <name> — the state Claude Code reports for <name>'s session (PANES_PY's
# session_state over one claude_agents call, its listing on stdin): busy, idle, waiting[:
# <waitingFor>], unknown or gone; `herdr` when herdr answers for the agent instead (codex, or no
# session recorded). A reader that fails, or prints nothing, is unknown, never herdr.
session_state() {
  local list ok=1 out
  list="$(claude_agents)" || ok=""
  out="$(printf '%s' "${list}" | SWARM_PANES_PY="${PANES_PY}" SWARM_LIST_OK="${ok}" python3 -c '
import os, sys
exec(os.environ["SWARM_PANES_PY"])
s = session_state(sys.argv[1], sys.argv[2], sys.stdin.read() if os.environ["SWARM_LIST_OK"] else None)
print("herdr" if s is None else s[0] + (": " + s[1] if s[1] else ""))' "${AGENTS_LOG}" "$1")" || out=""
  echo "${out:-unknown}"
}

# read_state <name> — <name>'s state for a reader that does not wait (tell, free_agent_name):
# session_state's word for a Claude agent, or `herdr:<herdr's status>` for one herdr answers for
# (codex, or no session recorded). The one place such a reader takes herdr's status.
read_state() {
  local s
  s="$(session_state "$1")"
  [[ "${s}" != herdr ]] || s="herdr:$(agent_status "$1")"
  echo "${s}"
}

# waiting_for <state> — what a waiting agent waits for (read_state's `waiting: <waitingFor>`), or
# "a prompt" when its state does not say.
waiting_for() { local w="${1#waiting: }"; [[ "${w}" != "$1" ]] || w="a prompt"; echo "${w}"; }

# login_expired <name> — succeed when <name>'s Claude session stopped on an expired login (PANES_PY's
# login_expired): only the user's /login clears it, so nudging or waiting on it is wasted.
login_expired() {
  SWARM_PANES_PY="${PANES_PY}" python3 -c '
import os, sys
exec(os.environ["SWARM_PANES_PY"])
sys.exit(0 if login_expired(*sys.argv[1:4]) else 1)' "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}"
}

# record_agent <role> <name> <kind> <model> <effort> <session> — append the agent's line; session is
# '-' for codex.
record_agent() {
  mkdir -p "$(dirname "${AGENTS_LOG}")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$1" "$2" "$3" "$4" "$5" "${6:--}" >> "${AGENTS_LOG}"
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

# record_finding <kind> <pr-url> <text> <fixed|declined> — log one finding and what became of it.
# A row is date, kind, PR, text, outcome; rows from before the outcome column have four fields and
# were all fixed. lessons, outcomes and dash count only fixed rows; decisions reads both.
record_finding() {
  local kind="$1" pr="$2" text="$3" outcome="$4"
  [[ -n "${kind}" && -n "${pr}" && -n "${text//[[:space:]]/}" ]] || die "usage: swarm.sh log-finding [--declined] <kind> <pr-url> <one line>"
  [[ "${kind}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#kind} -le 32 ]] \
    || die "kind '${kind}' must be short kebab-case (32 characters at most), like vacuous-test"
  text="${text:0:200}"
  [[ "${pr}" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+(/[^[:space:]]*)?$ || "${pr}" =~ ^[^/#[:space:]]+/[^/#[:space:]]+#[0-9]+$ ]] \
    || die "pr '${pr}' must be a PR URL or owner/repo#N, so the same PR always counts once"
  mkdir -p "${PROJECT_DIR}/.swarm"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "${kind}" "${pr//[$'\t\n\r']/ }" "${text//[$'\t\n\r']/ }" "${outcome}" \
    >> "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}"
  echo "recorded ${kind} (${outcome})"
}

# REPORT_PY: what the reports share (each python exec's it from $SWARM_REPORT_PY), so they agree.
#   pr_key(pr) is one PR however it was written: https://github.com/o/r/pull/12[/...], o/r#12, or as given.
#   session_log(projects, session) is a session's .jsonl under Claude Code's projects dir, or "".
#   finding_rows(path) is findings.tsv's well-formed rows as (date, kind, pr, text, outcome); a row
#   from before the outcome column is "fixed". fixed_rows(path) is the fixed ones' first four fields.
#   session_usage(path, seen) is one session's (input, cache write, cache read, output) tokens, est.
#   USD and models, from Claude Code's own log, skipping (and adding to seen) message ids already counted.
REPORT_PY='
import glob, json, os, re
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}

def pr_key(pr):
    m = re.search(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)", pr) or re.fullmatch(r"\s*([^/\s#]+/[^/\s#]+)#(\d+)\s*", pr)
    return f"{m.group(1).lower()}#{m.group(2)}" if m else pr.strip().rstrip("/")

def session_log(projects, session):
    paths = glob.glob(os.path.join(projects, "*", session + ".jsonl")) if session not in ("", "-") else []
    return paths[0] if paths else ""

def finding_rows(path):
    if not os.path.exists(path):
        return []
    rows = (l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8", errors="replace", newline="\n"))
    return [f if len(f) == 5 else f + ["fixed"] for f in rows if len(f) == 4 or (len(f) == 5 and f[4] in ("fixed", "declined"))]

def fixed_rows(path):
    return [f[:4] for f in finding_rows(path) if f[4] == "fixed"]

def session_usage(path, seen):
    tok, usd, models = [0, 0, 0, 0], 0.0, set()
    for line in open(path, errors="ignore"):
        try:
            m = json.loads(line).get("message") or {}
        except (ValueError, AttributeError):
            continue
        u, mid = m.get("usage"), m.get("id")
        if not u or not mid or mid in seen:
            continue
        seen.add(mid)
        t = [u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)]
        model = m.get("model", "?")
        models.add(model)
        tok = [x + y for x, y in zip(tok, t)]
        price = next((v for k, v in PRICES.items() if k in model), None)
        if price:
            usd += sum(x * p for x, p in zip(t, price)) / 1e6
    return tok, usd, models
'

# lessons [--all] — the "brief" below is lessons_file (default the brief itself).
# Kinds fixed in at least LESSON_MIN_PRS distinct PRs, recently, that the brief has
# no rule for (candidates), and a brief that has grown too long. A rule in the brief carries its kind
# as <!-- lesson: <kind> -->. The brief is read from the default branch, where adopted rules land; a
# declined rule is a closed 'lesson: <kind>' PR, which /swarm-dev:swarm checks before proposing. A lead's memory
# (Claude Code's per-project memory directory, which builders in their own worktrees never see) that
# carries `lesson: <kind>` in its frontmatter is a candidate too, until the brief rules that kind. There is no staleness check: the log is local while the brief is committed, and a
# rule that works stops its own findings, so "quiet" cannot tell a working rule from an unneeded one.
lessons_report() {
  [[ -z "${1:-}" || "${1}" == --all ]] || die "usage: swarm.sh lessons [--all]"
  # Claude Code keys memory on the repo root (the cwd outside git), not on a project's subdirectory.
  local key; key="$(git -C "${PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || echo "${PROJECT_DIR}")"
  local memory="${SWARM_MEMORY_DIR:-${CLAUDE_PROJECTS}/${key//[^A-Za-z0-9]/-}/memory}"
  # The size cap is the brief's, the file pasted into every prompt; a lessons_file like AGENTS.md
  # is long by design and loaded by the agents themselves.
  SWARM_REPORT_PY="${REPORT_PY}" python3 - "${PROJECT_DIR}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${LESSONS_FILE}" \
    "${LESSON_MIN_PRS}" "${LESSON_RECENT_DAYS}" "${BRIEF_MAX_BYTES}" "${1:-}" "${memory}" "${PROJECT_BRIEF}" <<'PY'
import collections, datetime, glob, os, re, subprocess, sys
exec(os.environ["SWARM_REPORT_PY"])
project, log, brief, min_prs, recent_days, max_bytes, flag, memory, swarm_brief = sys.argv[1:10]
min_prs, recent_days, max_bytes = int(min_prs), int(recent_days), int(max_bytes)
cutoff = (datetime.date.today() - datetime.timedelta(days=recent_days)).isoformat()

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
for parts in fixed_rows(log):  # a declined finding is no lesson
    try:
        when = datetime.date.fromisoformat(parts[0]) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", parts[0]) else None
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

# cost [--since YYYY-MM-DD] — tokens and estimated cost per role, for every agent this project's swarm started
# (and the calling session, as "lead", when run inside herdr). Usage comes from Claude Code's own
# session logs, deduplicated by message id; codex agents are listed but not priced (not logged here).
cost_report() {
  local lead="" since=""
  # A bare date is the older form, still what dash passes.
  if [[ $# -eq 1 ]]; then since="$1"; elif [[ $# -eq 2 && "$1" == --since ]]; then since="$2"; fi
  [[ $# -eq 0 || "${since}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "usage: swarm.sh cost [--since YYYY-MM-DD]"
  [[ "${HERDR_ENV:-}" == 1 ]] && lead="$(session_for_pane "${HERDR_PANE_ID:-}")"
  [[ -f "${AGENTS_LOG}" || -n "${lead}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  SWARM_REPORT_PY="${REPORT_PY}" python3 - "${AGENTS_LOG}" "${since:-0000-00-00}" "${lead}" "${CLAUDE_PROJECTS}" <<'PY'
import os, sys
exec(os.environ["SWARM_REPORT_PY"])
log, since, lead, projects = sys.argv[1:5]
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
    path = session_log(projects, a["session"])
    if a["kind"] != "claude" or not path:
        r["unpriced"] += 1
        continue
    tok, usd, models = session_usage(path, seen)
    r["models"] |= models
    r["tok"] = [x + y for x, y in zip(r["tok"], tok)]
    r["usd"] += usd
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

# outcomes [--since YYYY-MM-DD] — one TSV row per builder agent in agents.tsv, joining what the logs
# already hold: the story it built (slug, kind, risk), its model and effort, its cost, the tells it
# took by kind (findings, nudge, resume; a refused tell never reached it, so is not counted), the closes, the findings fixed on its PR, how the PR ended, and which attempt at the slug it was.
# agents.tsv cuts names at 32 characters, so the slug is the session's worktree (its cwd's last part).
outcomes_report() {
  local since="" rows meta="" slug text kind src pr state
  [[ -z "${1:-}" || ( "$1" == --since && "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ) ]] \
    || die "usage: swarm.sh outcomes [--since YYYY-MM-DD]"
  [[ -z "${1:-}" ]] || since="$2"
  [[ -f "${AGENTS_LOG}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  # date, slug, role, model, effort, cost_usd, tokens, tells_findings, tells_nudge, tells_resume, closes, attempts
  rows="$(SWARM_REPORT_PY="${REPORT_PY}" python3 - "${AGENTS_LOG}" "${EVENTS_LOG}" "${since:-0000-00-00}" \
    "${CLAUDE_PROJECTS}" "${BUILDER_ROLES}" <<'PY'
import collections, json, os, sys
exec(os.environ["SWARM_REPORT_PY"])
log, events, since, projects, roles = sys.argv[1:6]

def slug_of(path, name):
    # A builder runs in <repo>-wt/<slug>; any other cwd (or none logged) leaves the agents.tsv name.
    for line in open(path, errors="ignore") if path else ():
        try:
            cwd = json.loads(line).get("cwd")
        except (ValueError, AttributeError):
            continue
        if cwd:
            return os.path.basename(cwd.rstrip("/")) if os.path.dirname(cwd.rstrip("/")).endswith("-wt") else name
    return name

steer = collections.Counter()
if os.path.exists(events):
    for line in open(events, errors="ignore"):
        f = line.rstrip("\n").split("\t")
        # A tell is logged as tell:<kind>; a bare tell, from logs before kinds, sent findings. Only an
        # ok tell reached the builder: a refused or interrupted one is not counted.
        c = {"tell": "tell:findings"}.get(f[1], f[1]) if len(f) == 5 else ""
        # A close is counted whatever its cause (close:<cause>).
        c = "close" if c.split(":")[0] == "close" else c
        if c.split(":")[0] in ("tell", "close") and f[4] == "ok":
            steer[c, f[2]] += 1
attempts = collections.Counter()
for line in open(log, errors="ignore"):
    f = line.rstrip("\n").split("\t")
    if len(f) != 7 or f[1] not in roles.split():
        continue
    day, role, name, _, model, effort, session = f
    path = session_log(projects, session)
    slug = slug_of(path, name)
    attempts[slug] += 1
    if day < since:
        continue
    cost = tokens = ""
    if path:
        tok, usd, _ = session_usage(path, set())
        cost, tokens = f"{usd:.2f}", str(sum(tok))
    targets = {slug, name}
    counts = [str(sum(steer[c, t] for t in targets)) for c in ("tell:findings", "tell:nudge", "tell:resume", "close")]
    print("\t".join([day, slug, role, model, effort, cost, tokens] + counts + [str(attempts[slug])]))
PY
)"
  # Per slug: kind, risk and the PR, from the story (on the board, or its last version in git once a
  # merge deleted it) and gh. A gh that fails leaves the PR empty; it never fails the run.
  while IFS= read -r slug; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    text="$(story_text "${slug}")"; pr=""; state=""
    kind="$(sed -n 's/^kind: *//p' <<< "${text}" | head -1)"; [[ -z "${text}" ]] || kind="${kind:-code}"
    if src="$(repo_dir "$(sed -n 's/^repo: *//p' <<< "${text}" | head -1)")"; then
      IFS=$'\t' read -r pr state <<< "$( (cd "${src}" && gh pr list --head "story/${slug}" --state all --limit 1 \
        --json url,state --jq '.[] | [.url, .state] | @tsv') 2>/dev/null || true)"
    fi
    meta+="${slug}"$'\t'"${kind}"$'\t'"$(sed -n 's/^risk: *//p' <<< "${text}" | head -1)"$'\t'"${pr}"$'\t'"${state}"$'\n'
  done <<< "$(cut -f2 <<< "${rows}" | sort -u)"
  SWARM_REPORT_PY="${REPORT_PY}" SWARM_META="${meta}" SWARM_ROWS="${rows}" python3 - "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" <<'PY'
import collections, os, sys
exec(os.environ["SWARM_REPORT_PY"])
meta = {f[0]: f[1:] for f in (l.split("\t") for l in os.environ["SWARM_META"].splitlines()) if len(f) == 5}
fixed = collections.Counter(pr_key(f[2]) for f in fixed_rows(sys.argv[1]))
print("date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells_findings\ttells_nudge\ttells_resume\tcloses\tfindings_fixed\tpr\tpr_state\tattempts")
for line in os.environ["SWARM_ROWS"].splitlines():
    day, slug, role, model, effort, cost, tokens, tf, tn, tr, closes, attempts = line.split("\t")
    kind, risk, pr, state = meta.get(slug, ("", "", "", ""))
    print("\t".join([day, slug, kind, risk, role, model, effort, cost, tokens, tf, tn, tr, closes,
                     str(fixed[pr_key(pr)]) if pr else "0", pr, state, attempts]))
PY
}

# decisions [--since YYYY-MM-DD] — one JSON object per line for each decision the logs record, for
# training a decision model: decision (model_choice, retry, finding_accept, nudge, close), time,
# subject, context, options, chosen and outcome (the build's row in `outcomes`: merged, PR, every
# tells* column it prints, fixed findings, attempts, cost). A builder's context is its story as committed to the board by the
# end of its start day. What the logs do not hold is null, never guessed. It writes nothing.
decisions_report() {
  local since="" rows=""
  [[ -z "${1:-}" || ( "$1" == --since && "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ) ]] \
    || die "usage: swarm.sh decisions [--since YYYY-MM-DD]"
  [[ -z "${1:-}" ]] || since="$2"
  # Every row, unfiltered, so its rows line up one to one with agents.tsv's builder lines.
  [[ ! -f "${AGENTS_LOG}" ]] || rows="$(outcomes_report)"
  SWARM_REPORT_PY="${REPORT_PY}" SWARM_ROWS="${rows}" python3 - "${AGENTS_LOG}" "${EVENTS_LOG}" \
    "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${since:-0000-00-00}" "${BUILDER_ROLES}" "${BOARD}" <<'PY'
import json, os, subprocess, sys
exec(os.environ["SWARM_REPORT_PY"])
log, events, findings, since, roles, board = sys.argv[1:7]

def outcome(r):
    # Read by column name, so the tells columns are whichever outcomes prints (one or one per kind).
    o = {"merged": r["pr_state"] == "MERGED" if r["pr_state"] else None, "pr": r["pr"] or None,
         "findings": int(r["findings_fixed"]) if r["pr"] else None, "attempts": int(r["attempts"]),
         "cost_usd": float(r["cost_usd"]) if r["cost_usd"] else None}
    o.update({k: int(v) for k, v in r.items() if k.startswith("tells")})
    return o

def story_at(slug, day):
    # The story's last committed version on or before <day>; None when git has none.
    got = subprocess.run(["git", "-C", board, "log", "-1", "--format=%H", "--diff-filter=d", f"--until={day} 23:59:59",
                          "--", f"stories/{slug}.md"], capture_output=True, text=True)
    c = got.stdout.strip() if got.returncode == 0 else ""
    shown = subprocess.run(["git", "-C", board, "show", f"{c}:./stories/{slug}.md"], capture_output=True, text=True) if c else None
    return shown.stdout if shown and shown.returncode == 0 else None

def rec(decision, time, subject, context, options, chosen, out):
    return {"decision": decision, "time": time, "subject": subject, "context": context, "options": options,
            "chosen": chosen, "outcome": out}

table = [l.split("\t") for l in os.environ["SWARM_ROWS"].splitlines()]
rows = [dict(zip(table[0], f)) for f in table[1:] if len(f) == len(table[0])]
builds = []   # (day, keys, outcome): what a finding, nudge or close is joined to
out = []
lines = [l.rstrip("\n").split("\t") for l in open(log, errors="ignore")] if os.path.exists(log) else []
for f in (f for f in lines if len(f) == 7):
    day, role, name, kind, model, effort, _ = f
    r = rows.pop(0) if role in roles.split() and rows else None
    o, slug = (outcome(r), r["slug"]) if r else (None, None)
    if r:
        builds.append((day, {slug, name, pr_key(r["pr"])} if r["pr"] else {slug, name}, o))
    if day < since:
        continue
    context = story_at(slug, day) if slug else None
    out.append(rec("model_choice", day, slug or name, context, None, {"role": role, "kind": kind, "model": model, "effort": effort}, o))
    if o and o["attempts"] > 1:
        out.append(rec("retry", day, slug, context, None, {"role": role, "model": model, "effort": effort}, o))

def joined(key, day):
    # The newest build of <key> started on or before <day>.
    return next((o for d, keys, o in reversed(builds) if key in keys and d <= day), None)

for day, kind, pr, text, chosen in finding_rows(findings):
    if day >= since:
        out.append(rec("finding_accept", day, pr, text, ["fixed", "declined"], chosen, joined(pr_key(pr), day)))
for f in ([l.rstrip("\n").split("\t") for l in open(events, errors="ignore")] if os.path.exists(events) else []):
    # A close with a cause (close:<cause>) is a close whose chosen value carries the cause.
    close = len(f) == 5 and f[1].split(":")[0] == "close"
    if len(f) == 5 and (close or f[1] in ("nudge", "tell:nudge")) and f[4] == "ok" and f[0][:10] >= since:
        d = "close" if close else "nudge"
        out.append(rec(d, f[0], f[2], None, None, f[1], joined(f[2], f[0][:10])))
for r in sorted(out, key=lambda r: r["time"]):
    print(json.dumps(r))
PY
}

# story_text <slug> — the story file on the board or, once a merge deleted it, its last version in
# the board's git history; nothing when neither has it.
story_text() {
  local f="${BOARD}/stories/$1.md" c
  if [[ -f "${f}" ]]; then cat "${f}"; return; fi
  c="$(git -C "${BOARD}" log --diff-filter=D -1 --format=%H -- "stories/$1.md" 2>/dev/null)" || return 0
  [[ -z "${c}" ]] || git -C "${BOARD}" show "${c}^:./stories/$1.md" 2>/dev/null || true
}

# PROMPT_TIMEOUT_MS: how long a prompt has to be taken up (deliver_prompt), and a /goal to show in
# the session log (send_goal).
PROMPT_TIMEOUT_MS="${SWARM_PROMPT_TIMEOUT_MS:-60000}"

# deliver_prompt <name> <prompt-file> [<pane>] [once] — submit the brief and confirm the agent acted on it.
# `agent start` returns once the agent is ready, but a slow starter (Fable at xhigh) could
# still drop a prompt sent at once, leaving it idle at an empty prompt while every later
# `wait` returned immediately. So the submission waits until herdr sees the agent working
# (or blocked on a question), retries once, and fails loudly rather than reporting success.
# With once, it is sent a single time and the caller confirms it: a /goal sent again would reset
# a goal that set, and whether it set is in the session log, not in herdr's status.
deliver_prompt() {
  local name="$1" prompt_file="$2" status target="${3:-}"
  [[ -n "${target}" ]] || target="$(own_target "${name}")"
  if [[ "${4:-}" == once ]]; then
    herdr agent prompt "${target}" "$(cat "${prompt_file}")" >/dev/null 2>&1 \
      || die "${name}: herdr could not send it the prompt; see herdr agent read ${name}"
    return
  fi
  for _ in 1 2; do
    status=$(herdr agent prompt "${target}" "$(cat "${prompt_file}")" --wait --until working --until blocked \
      --timeout "${PROMPT_TIMEOUT_MS}" 2>/dev/null | json "d.get('result',{}).get('agent',{}).get('agent_status','')" 2>/dev/null || true)
    case "${status}" in
      working|blocked) return 0 ;;
    esac
    sleep 5
  done
  die "${name}: the brief was not taken up after 2 attempts (status '${status:-none}'); see herdr agent read ${name}"
}

# IDLE_NUDGES: how many times one `wait` re-prompts a builder that went idle before its story has a
# PR (its turn died on a dropped stream, or it stopped early): nothing else would wake it. Enough to ride
# out a dropped stream; few enough that a builder that is truly stuck still comes back to the lead.
IDLE_NUDGES=3

# nudge_reason <name> — when <name> builds a ready code, docs or chore story that has no open or
# merged PR (a closed one is an earlier attempt's, closed by a counted close; an epic story with
# pr_per = epic, as build_story builds it: story/<slug> is not pushed), print why a nudge is sent and
# succeed. A name with
# no story (a conductor, hld, a planner) or a verify story is never nudged, and a repo that cannot
# be resolved, or a gh or git call that fails, counts as having a PR.
nudge_reason() {
  local slug f src url n rc=0
  slug="$(stall_py story "$1")"; [[ -n "${slug}" ]] || return 1
  f="${BOARD}/stories/${slug}.md"
  case "$(fm "${f}" kind)" in ""|code|docs|chore) ;; *) return 1 ;; esac
  [[ "$(fm "${f}" status)" == ready ]] || return 1   # a story being built stays ready until review
  src="$(repo_dir "$(fm "${f}" repo)")" || return 1
  if [[ "${CFG_pr_per}" == epic && -n "$(fm "${f}" epic)" ]]; then
    git -C "${src}" ls-remote --exit-code origin "refs/heads/story/${slug}" >/dev/null 2>&1 || rc=$?
    [[ ${rc} -eq 2 ]] || return 1   # 2: no such branch; 0 is pushed, anything else a failure
    echo "you are idle and story/${slug} is not pushed"; return
  fi
  url="$(git -C "${src}" remote get-url origin 2>/dev/null)" || return 1
  n="$(gh pr list -R "${url}" --head "story/${slug}" --state all --json state -q '[.[] | select(.state != "CLOSED")] | length' 2>/dev/null)" || return 1
  [[ "${n}" == 0 ]] || return 1
  echo "you are idle and story/${slug} has no PR"
}

# STALL_PATHS: how many of a worktree's changed and untracked files story_work_time reads the mtime of.
STALL_PATHS=300

# story_work_time <slug> — the epoch time a story's worktree last showed work: the newer of its last
# commit and the newest mtime among its changed and untracked files (git status, the first
# STALL_PATHS of them), so a builder holding its diff uncommitted is not stalled; empty when it has
# neither (not started, or its repo is not here).
story_work_time() {
  local src wt ct
  src="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo 2>/dev/null)")" || return 0
  wt="$(worktree_for "${src}" "$1")"
  ct="$(git -C "${wt}" log -1 --format=%ct 2>/dev/null || true)"
  { GIT_OPTIONAL_LOCKS=0 git -C "${wt}" status --porcelain -z --untracked-files=all 2>/dev/null || true; } \
    | python3 -c '
import os, sys
wt, cap, best = sys.argv[1], int(sys.argv[2]), [float(sys.argv[3])] if sys.argv[3] else []
es, i = sys.stdin.read().split("\0"), 0
while i < len(es) and cap > 0:
    e, i = es[i], i + 1
    if len(e) < 4:
        continue
    i += e[0] in "RC"   # a rename or copy: its source path follows
    cap -= 1
    try:
        best.append(os.lstat(os.path.join(wt, e[3:])).st_mtime)
    except OSError:   # deleted
        pass
print(int(max(best)) if best else "")' "${wt}" "${STALL_PATHS}" "${ct}" || echo "${ct}"
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

# session_mtime <name> — the epoch mtime of <name>'s Claude session log (its agents.tsv session id,
# REPORT_PY's session_log), which the session writes on every turn and tool call; empty when it has none.
session_mtime() {
  SWARM_PANES_PY="${PANES_PY}" SWARM_REPORT_PY="${REPORT_PY}" python3 - "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}" <<'PY' || true
import os, sys
exec(os.environ["SWARM_PANES_PY"]); exec(os.environ["SWARM_REPORT_PY"])
sid = session_id(sys.argv[1], sys.argv[2])
path = session_log(sys.argv[3], sid) if sid else ""
try:
    print(int(os.path.getmtime(path)) if path else "")
except OSError:   # removed since the glob: no sign
    print("")
PY
}

# agent_stalled <name> <since> — when <name> is a story's builder that has shown no sign of life for
# stall_minutes (STALL_PY), counting <since> (epoch: when the wait began), its worktree's last commit
# or edit (story_work_time) and its session log's mtime (session_mtime) as signs, print how many
# minutes and succeed. Its PRs are asked for their updatedAt only once the rest already looks
# stalled, so gh is rarely called.
agent_stalled() {
  local slug url age ct sl prs=()
  slug="$(stall_py story "$1")"
  [[ -n "${slug}" ]] || return 1
  ct="$(story_work_time "${slug}")"; sl="$(session_mtime "$1")"
  age="$(stall_py age "${slug}" "$1" "$2" "${ct}" "${sl}")"
  [[ -n "${age}" && "${age}" -ge "${CFG_stall_minutes}" ]] || return 1
  for url in $(fm "${BOARD}/stories/${slug}.md" prs | grep -o 'https://github.com/[^] ,"]*/pull/[0-9]*'); do
    prs+=("$(gh pr view "${url}" --json updatedAt -q .updatedAt 2>/dev/null || true)")
  done
  age="$(stall_py age "${slug}" "$1" "$2" "${ct}" "${sl}" "${prs[@]+"${prs[@]}"}")"
  [[ -n "${age}" && "${age}" -ge "${CFG_stall_minutes}" ]] || return 1
  echo "${age}"
}

# STALL_POLL_MS: how often `wait --stall` checks whether the agent it waits on has stalled.
STALL_POLL_MS="${SWARM_STALL_POLL_MS:-60000}"
# WAIT_STALLED: the exit code of `wait --stall` when it returns because the agent stalled.
WAIT_STALLED=3

# timed_out <stderr file> — true when herdr's failed agent wait only timed out.
timed_out() { grep -q '"timeout"' "$1"; }

# herdr_wait <target> <name> <timeout-ms> [<since>] — the wait for an agent with no Claude session to
# read (codex, or no session recorded), and the one place a wait takes herdr's own status: herdr
# agent wait in STALL_POLL_MS steps; with <since>, between steps an agent stalled since then
# (agent_stalled) ends the wait with "stalled: ...". herdr's stderr goes to a file, read only to tell
# a step's timeout from a real failure; a real failure, and the last step, fail as one unbroken wait does.
herdr_wait() {
  local target="$1" name="$2" left="$3" since="${4:-}" out err min
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-wait.XXXXXX")"
  while [[ ${left} -gt ${STALL_POLL_MS} ]]; do
    if out="$(herdr agent wait "${target}" --timeout "${STALL_POLL_MS}" 2>"${err}")"; then
      rm -f "${err}"; json "d['result']['agent']['agent_status']" <<< "${out}"; return
    fi
    timed_out "${err}" || break
    left=$((left - STALL_POLL_MS))
    if [[ -n "${since}" ]] && min="$(agent_stalled "${name}" "${since}")"; then
      rm -f "${err}"; echo "stalled: working ${min} min with no commit, edit, session-log write or PR update"; return
    fi
  done
  rm -f "${err}"
  herdr agent wait "${target}" --timeout "${left}" | json "d['result']['agent']['agent_status']"
}

# SETTLED: the session states a wait returns on.
SETTLED='^(idle|waiting|gone)(:|$)'

# now_ms — the time in milliseconds (bash 3.2 has no EPOCHREALTIME). sleep_ms <ms> — sleep that
# long; nothing for zero or less.
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
sleep_ms() { [[ $1 -le 0 ]] || sleep "$(($1 / 1000)).$(printf '%03d' $(($1 % 1000)))"; }

# settle <target> <name> <timeout-ms> [<since>] [wake] — block until the agent settles and print its
# state. A Claude agent has settled when its session says so (session_state: idle, waiting or gone);
# herdr's agent wait is only the wake-up, in STALL_POLL_MS slices, and its status is never parsed.
# The session is read before the first wake and right after each; every decision is taken on that
# read. Settled, it returns at once. A herdr wait that fails other than by timing out fails the wait.
# With <since>, a busy builder stalled since then (agent_stalled) ends it with "stalled: ...". Busy or
# unknown (said once on stderr), it sleeps out the rest of the slice, the last one only to the
# deadline (now plus <timeout-ms>), where it reads once more, prints that state and fails. With
# wake (after a nudge), an idle read ends the wait only once a whole slice has passed, unless the
# session read busy (or waiting, or gone) in between: two nudges are never closer than a slice.
settle() {
  local target="$1" name="$2" since="${4:-}" wake="${5:-}" state deadline t0 end err min said="" rc=0 hold=0
  state="$(session_state "${name}")"
  [[ "${state}" != herdr ]] || { herdr_wait "${target}" "${name}" "$3" "${since}"; return; }
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-wait.XXXXXX")"; deadline=$(($(now_ms) + $3))
  [[ -z "${wake}" ]] || hold=$(($(now_ms) + STALL_POLL_MS))
  while [[ ${hold} -gt 0 || ! "${state}" =~ ${SETTLED} ]]; do
    t0="$(now_ms)"; end=$((t0 + STALL_POLL_MS < deadline ? t0 + STALL_POLL_MS : deadline))
    if [[ ${end} -gt ${t0} ]]; then
      herdr agent wait "${target}" --timeout $((end - t0)) >/dev/null 2>"${err}" || timed_out "${err}" || rc=1
    fi
    state="$(session_state "${name}")"
    [[ "${state}" =~ ^(idle|unknown)$ ]] || hold=0
    if [[ "${state}" =~ ${SETTLED} ]] && [[ ${hold} -eq 0 || $(now_ms) -ge ${hold} ]]; then rc=0; break; fi
    if [[ ${rc} -ne 0 ]]; then cat "${err}" >&2; break; fi
    if [[ "${state}" == unknown && -z "${said}" ]]; then
      said=1; echo "swarm: ${name}: Claude Code gives no state for its session (unknown); waiting on" >&2
    fi
    if [[ "${state}" == busy && -n "${since}" ]] && min="$(agent_stalled "${name}" "${since}")"; then
      state="stalled: working ${min} min with no commit, edit, session-log write or PR update"; break
    fi
    t0="$(now_ms)"
    if [[ ${t0} -ge ${deadline} ]]; then rc=1; break; fi
    sleep_ms $((end - t0))
  done
  rm -f "${err}"; echo "${state}"; return "${rc}"
}

# wait_agent <name> <timeout-ms> [--stall] — block until the agent settles (settle) and print its
# state; at the timeout, print the last one and fail. A builder whose session is idle before its
# story has a PR (nudge_reason) has not settled: tell it why, log `nudge <name>`, and wait again, up
# to IDLE_NUDGES times. An idle agent whose transcript ends on an expired login (login_expired) is
# never nudged: wait prints `auth`, with a line on stderr naming it. With goal on, no builder is
# nudged: a nudge would bury the reply and goal entry the conductor reads the cause from, so wait
# returns idle. A nudge herdr could not
# deliver is neither logged nor counted: wait stops nudging and returns the idle state. With --stall, a builder that shows no sign of life
# for stall_minutes after the wait began also ends it: it prints "stalled: ..." and returns
# WAIT_STALLED. SWARM_WAIT_STARTED (epoch) overrides when the wait began, for tests.
wait_agent() {
  local name="$1" timeout="$2" stall="${3:-}" status nudges=0 target since="" rc wake="" reason
  [[ -z "${stall}" ]] || since="${SWARM_WAIT_STARTED:-$(date +%s)}"
  target="$(own_target "${name}")" || return 1
  while :; do
    rc=0; status="$(settle "${target}" "${name}" "${timeout}" "${since}" "${wake}")" || rc=$?
    if [[ "${status}" == stalled:* ]]; then echo "${status}"; return "${WAIT_STALLED}"; fi
    [[ ${rc} -eq 0 ]] || { echo "${status}"; return "${rc}"; }
    if [[ "${status}" == idle ]] && login_expired "${name}"; then
      echo "swarm: ${name}: its login expired (Login expired · Please run /login); only your /login clears it" >&2
      echo auth; return 0
    fi
    # Only a Claude session is nudged: herdr's idle (a codex agent's) gives settle no session to hold on.
    [[ "${status}" == idle && ${nudges} -lt ${IDLE_NUDGES} && "$(session_state "${name}")" == idle ]] || break
    # With goal on, the conductor reads why the builder stopped from its reply and session log.
    [[ "${CFG_goal}" == off ]] || break
    reason="$(nudge_reason "${name}")" || break
    if ! herdr agent prompt "${target}" "From swarm: ${reason}. Carry on from where you stopped and finish the story, or say what blocks you." \
      >/dev/null 2>&1; then
      echo "swarm: ${name}: ${reason}, but the nudge could not be delivered; returning ${status}" >&2; break
    fi
    nudges=$((nudges + 1)); wake=1   # settle holds a slice, or until busy, before it takes idle again
    record_event nudge "${name}"
    echo "swarm: ${name}: ${reason}; told it to carry on (${nudges}/${IDLE_NUDGES})" >&2
  done
  echo "${status}"
}

# wait_conductor <agent> <timeout-ms> — a conductor is idle whenever it waits on its own builders, so
# idle is not settled: wait on until its report exists, it is waiting on a prompt or gone, or its
# login expired (wait_agent's auth).
# <timeout-ms> is the whole wait, so a conductor that stopped without a report cannot hang it.
wait_conductor() {
  local name="$1" status deadline=$((SECONDS + $2 / 1000)) poll rc
  while :; do
    rc=0; status="$(wait_agent "${name}" "$(( (deadline - SECONDS) * 1000 > 1000 ? (deadline - SECONDS) * 1000 : 1000 ))")" || rc=$?
    [[ "${status}" =~ ^(idle|done)$ && ! -f "$(conductor_report "${name}")" ]] || break
    [[ ${SECONDS} -lt ${deadline} ]] || break
    poll="${SWARM_CONDUCTOR_POLL:-30}"; (( poll <= deadline - SECONDS )) || poll=$((deadline - SECONDS))
    sleep "${poll}"
  done
  echo "${status}"
  return "${rc}"
}

# is_tell_kind <word> — true for a kind tell takes: findings, nudge or resume.
is_tell_kind() { case "$1" in findings|nudge|resume) return 0 ;; esac; return 1; }

# tell_agent <slug> <kind> <file> — send an agent a file's contents through deliver_prompt (it
# retries, and counts a permission prompt as taken up). <kind> says why (findings, nudge or resume;
# main logs it as tell:<kind>). A header line comes first, so findings that begin with '-' are never
# read as a flag. Only an idle agent is told (read_state): it refuses one mid-turn (findings sent then
# would be counted as taken up at once), waiting on a prompt (the text would land in the dialog), gone,
# or of unknown state, rather than waiting on it. With goal on, findings get a fresh goal (findings_goal).
tell_agent() {
  local kind="$2" f="$3" name msg state since
  is_tell_kind "${kind}" || die "tell: the kind must be findings, nudge or resume, not '${kind}' (swarm.sh tell <slug> <kind> <file>)"
  [[ -f "${f}" ]] || die "no such file '${f}'"
  name="$(agent_name "$1")"
  if [[ -z "$(agent_field "${name}" pane_id)" ]]; then
    [[ -z "$(agent_field "${name}" agent_status any)" ]] || die "${name}: the agent holding this name is not one this project started; it is never told from here"
    die "could not reach ${name}: no agent this project started holds the name; is its pane still open?"
  fi
  state="$(read_state "${name}")"
  case "${state}" in
    idle|herdr:idle|herdr:done) ;;
    busy|herdr:working) die "${name} is still working; run \`swarm.sh wait $1\` in the background, then tell it" ;;
    waiting*|herdr:blocked) die "${name} is waiting on $(waiting_for "${state}"); answer it (herdr agent read ${name}), then tell it" ;;
    gone) die "${name}: its Claude session has ended (gone); there is no one to tell" ;;
    unknown) die "${name}: Claude Code gives no state for its session (unknown); look at it (herdr agent read ${name}) before telling it" ;;
    herdr:unknown) die "${name}: herdr gives no state for it (unknown); look at it (herdr agent read ${name}) before telling it" ;;
    *) die "could not reach ${name} (status '${state#herdr:}'): is its pane still open?" ;;
  esac
  msg="$(mktemp "${TMPDIR:-/tmp}/swarm-tell.XXXXXX")"
  # shellcheck disable=SC2064 # expand now: msg is local, and deliver_prompt may exit through die
  trap "rm -f '${msg}' '${msg}.goal'" EXIT
  { echo "From the conductor:"; echo; cat "${f}"; } > "${msg}"
  if [[ "${CFG_goal}" == off || "${kind}" != findings ]]; then deliver_prompt "${name}" "${msg}"; echo "told ${name}"; return; fi
  since="$(python3 -c 'import time; print(time.time())')"   # to the sub-second: an earlier tell's goal may share the second
  deliver_prompt "${name}" "${msg}"
  # The findings reached the builder: if the goal step fails, log that delivery as an ok tell
  # (outcomes and the stall rule count only ok ones), beside main's line for the failure.
  # shellcheck disable=SC2064 # expand now, as above
  trap "rc=\$?; rm -f '${msg}' '${msg}.goal'; [[ \${rc} -eq 0 ]] || record_event tell:findings '$1'" EXIT
  findings_goal "$1" "${since}" "${msg}.goal"
  echo "told ${name}"
}

# findings_goal <slug> <since> <goal-file> — send the builder a fresh /goal mid-turn, once its findings
# are taken up, so the goal drives the fix (sent after the turn, the judge would find it met at once): the
# findings addressed, the reply its brief asks for in its mode, and the turn bound. Mid-turn it sets at
# once and costs one extra short turn, as build_story's does. send_goal confirms it from entries newer
# than the tell, so the build-time goal never counts; a refusal or no entry fails naming the story.
findings_goal() {
  local slug="$1" goal="$3" mode=story
  [[ "${CFG_pr_per}" != epic || -z "$(fm "${BOARD}/stories/${slug}.md" epic 2>/dev/null)" ]] || mode=epic
  printf '%s %s %s\n' "The goal: the conductor's review findings, sent to you just before this goal, are addressed (each fixed, or declined with a reason in your reply) and you have replied." \
    "$(reply_sentence "${mode}")" "It is met once both hold, or stop after ${CFG_goal} more turns." > "${goal}"
  send_goal "${slug}" "${goal}" findings "$2"
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
A story is reviewed only when its latest head has passed \`$(codex_review_cmd '<base>')\`
in its worktree, and, when it changes code (not only docs, board files or a dependency bump), the
/code-review skill on its PR (\`/code-review <PR>\`). $(codex_rule) Send every real finding to the story's
builder with \`${SWARM_HOME}/bin/swarm.sh tell <slug> findings <file>\` (a file holding the findings and
what to decline), wait for it, and review the new head. Stop at the first pass on the latest head
with nothing substantive: one that finds only nits, edge cases outside the story, or points already
declined is such a pass, even if it is not empty. Rebut what it found in the PR with a reason. Never merge a story, and never run \`swarm.sh close <slug>\` on its builder, before
its latest head has passed.$(rules_review_rule)

$(finding_rule)
EOF
}

# codex_review_cmd <base> — how a brief runs codex: through codex-review, which stops it after
# codex_minutes. SWARM_PROJECT, as in finding_rule, so a sibling repo's worktree reads this config.
codex_review_cmd() { printf 'SWARM_PROJECT=%q %q codex-review %s' "${PROJECT_DIR}" "${SWARM_HOME}/bin/swarm.sh" "$1"; }
# codex_rule — how to run codex-review, and what a usage limit or a timeout means, for a builder, a
# conductor and the lead alike. In the background, because a foreground Bash call ends sooner (Claude
# Code stops one at 2 minutes by default, 10 at most) and the tool's kill would preempt the timeout.
codex_rule() {
  printf '%s ' "Run codex-review in the background (Bash run_in_background) and wait for it to finish: it can run for ${CFG_codex_minutes} minutes, longer than a foreground Bash call may last."
  printf '%s' 'If codex reports a usage limit, or codex-review stops it and prints "codex skipped: timed out", do not wait or run it again: a builder carries on without it, a conductor or the lead reviews the diff itself, and the PR (or a reply, where there is none) says "codex skipped: usage limit" or "codex skipped: timed out".'
}

# finding_rule — every fixed finding feeds the outer loop (swarm.sh lessons); declined ones are
# logged too, for `decisions`, and never count as lessons.
finding_rule() {
  local proj sw
  proj="$(printf '%q' "${PROJECT_DIR}")"; sw="$(printf '%q' "${SWARM_HOME}/bin/swarm.sh")"
  cat <<EOF
Log each finding that was fixed, and each one declined (rebutted with a reason), from any directory, with:

    SWARM_PROJECT=${proj} ${sw} log-finding <kind> <PR URL> "<one line>"
    SWARM_PROJECT=${proj} ${sw} log-finding --declined <kind> <PR URL> "<the finding, and why it was declined>"

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
stays blocked until the human merges and `/swarm-dev:swarm` reconciles the board. When every story left
in the epic is in review and the epic's **Done when** will hold once they merge, run
`swarm.sh review <epic> <every PR URL still waiting>`: the epic leaves the board once they all merge.
RULE
  else
    cat <<'RULE'
Merge a PR only when it is green and reviewed. A queued merge (auto-merge, a merge queue) has not
happened yet: wait until the PR is merged. Then run `swarm.sh review <slug> <PR URL>` and
`swarm.sh reconcile`, never a plain `git pull`: reconcile first puts back swarm.sh's own edits to the
story (a retry's `attempts:`), which would stop the pull, then pulls the board and finishes the
story. Only then run `swarm.sh unblock` and `swarm.sh close <slug>` to close that story's tab:
closing a story that is still `ready` counts a failed build. When the epic's **Done when** holds, take the epic off the board with
`swarm.sh finish <epic>`.
RULE
  fi
}

# A test that passes with its fix removed proves nothing; a builder shows each one can fail.
mutation_rule() {
  printf '%s' "For a code change, prove each new or changed test can fail: back up the file you fixed with cp, break the fix, see the test fail, then restore it with cp (never git checkout, which drops uncommitted work), and note which test failed and how."
}

# reply_sentence <epic|story> — what a builder replies, and when: the brief's rule on finishing, and
# what its goal condition waits for. One sentence per mode, so the two cannot drift.
reply_sentence() {
  if [[ "$1" == epic ]]; then
    printf '%s' "When your branch is pushed, reply with the branch, what changed in three lines, the codex findings and the mutation, then stop."
  else
    printf '%s' "When CI is green, reply with the PR URL, what changed in three lines, and the codex findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR."
  fi
}

# goal_condition <slug> <epic|story> — the builder's /goal: the story's **Done when** and **From
# review** blocks, the reply its brief asks for in that mode, an escape for a story that cannot be
# done, and the goal's turn bound. A block runs from its bold heading to the first blank line after
# its content, or to the next bold line. Fails, printing why, with no Done when or none under it.
goal_condition() {
  local blocks
  blocks="$(awk '
    /^\*\*(Done when|From review)/ {
      if (on) print ""
      on = 1; dw = /^\*\*Done when/; rest = $0; sub(/^\*\*[^*]*\*\*[[:space:]]*/, "", rest)
      has = (rest != ""); if (has && dw) items = 1
      print; next
    }
    on && /^\*\*/ { on = 0; print ""; next }
    on && /^[[:space:]]*$/ { if (has) { on = 0; print "" }; next }
    on { has = 1; if (dw) items = 1; print }
    END { exit !items }' "${BOARD}/stories/$1.md")" \
    || { echo "$1 has no **Done when** with an item under it, so its goal would have nothing to meet"; return 1; }
  printf '%s\n\n%s\n\n%s\n' "${blocks}" "$(reply_sentence "$2")" \
    "If the story cannot be done, reply \`IMPOSSIBLE: <why>\` and stop; that reply meets this goal. The goal is met once all of the above holds and you have replied, or stop after ${CFG_goal} more turns."
}
GOAL_MAX_CHARS=4000   # Claude Code's own cap on a /goal condition

# goal_entry <name> <since-epoch> [<goal-file>] — the kind of the newest goal entry written at or
# after <since> in <name>'s session log (its agents.tsv session id, REPORT_PY's session_log under
# CLAUDE_PROJECTS), or nothing. Never the pane. The kinds, as the goal spike (Claude Code 2.1.299)
# found them: set (goal_status with sentinel:true), continuing (the judge's met:false), met (the
# judge's met:true, which is also how a turn bound and an IMPOSSIBLE escape are written), and
# `refused: <Claude Code's reason>` (a system/local_command whose stdout is a /goal refusal, as with
# hooks restricted or an untrusted folder; no goal_status follows). The spike saw no entry for a
# stalled, paused or errored goal, so none is read. With <goal-file>, a goal_status for another
# condition (whitespace aside) is skipped.
goal_entry() {
  SWARM_PANES_PY="${PANES_PY}" SWARM_REPORT_PY="${REPORT_PY}" python3 - "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}" "$2" "${3:-}" <<'PY'
import datetime, json, os, re, sys
exec(os.environ["SWARM_PANES_PY"]); exec(os.environ["SWARM_REPORT_PY"])
log, name, projects, since, cond = sys.argv[1:6]
want = " ".join(open(cond, encoding="utf-8").read().split()) if cond else None
sid = session_id(log, name)
path, kind = session_log(projects, sid) if sid else "", ""
for l in open(path, encoding="utf-8", errors="replace") if path else []:
    if "goal_status" not in l and "local_command" not in l:
        continue
    try:
        d = json.loads(l)
        t = datetime.datetime.fromisoformat(str(d.get("timestamp")).replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        continue
    a = d.get("attachment")
    if d.get("type") == "attachment" and isinstance(a, dict) and a.get("type") == "goal_status":
        if want is not None and " ".join(str(a.get("condition") or "").split()) != want:
            continue
        k = "set" if a.get("sentinel") else "met" if a.get("met") else "continuing"
    elif d.get("type") == "system" and d.get("subtype") == "local_command":
        m = re.match(r"<local-command-stdout>(/goal [^<]*)", str(d.get("content") or ""))
        if not m:
            continue
        k = "refused: " + " ".join(m.group(1).split())
    else:
        continue
    if t >= float(since):
        kind = k
print(kind)
PY
}

# send_goal <slug> <goal-file> <brief|findings> [<since-epoch>] — send <slug>'s builder `/goal <condition>` once (deliver_prompt's
# once mode) and confirm it set from its session log (goal_entry, for this condition), polling up to
# PROMPT_TIMEOUT_MS. The condition goes on one line: the spike only saw a one-line /goal set, and a
# multi-line paste could be split or become a "[Pasted text]" placeholder; goal_entry compares it
# whitespace aside. Any goal_status newer than the send means it set: the judge may already have
# written its own after the sentinel. A refusal, or no entry, fails naming the story and why, and
# leaves the builder open for the lead to read. <since> defaults to now. The /goal goes only into a
# turn that has started: herdr can say working while the session is still idle, and deliver_prompt
# takes blocked as taken up, so it waits up to PROMPT_TIMEOUT_MS for the session (session_state) to
# read busy, and fails with nothing sent if it reads waiting (a dialog, where Enter could approve
# what auto mode flagged) or never reads busy. Each failure says the brief or the findings were
# delivered, so they are not sent again.
send_goal() {
  local slug="$1" goal="$2" name since="${4:-$(date +%s)}" entry deadline cond state pre post
  name="$(agent_name "${slug}")"
  pre="${slug}: the brief was delivered, but"; post="; do not send it again"
  [[ "$3" != findings ]] || { pre="${slug}: the findings were delivered, but"; post="; do not send them again"; }
  deadline=$((SECONDS + PROMPT_TIMEOUT_MS / 1000))
  while state="$(session_state "${name}")"; [[ "${state}" != busy && "${state}" != waiting* && ${SECONDS} -lt ${deadline} ]]; do sleep 1; done
  case "${state}" in
    busy) ;;
    waiting*) die "${pre} its builder is waiting on $(waiting_for "${state}"), so no /goal was sent; answer it (herdr agent read ${name})${post}" ;;
    *) die "${pre} its session did not read busy within $((PROMPT_TIMEOUT_MS / 1000))s (${state}), so no /goal was sent${post}" ;;
  esac
  cond="$(tr -s '[:space:]' ' ' < "${goal}")"; cond="${cond# }"; cond="${cond% }"
  deliver_prompt "${name}" <(printf '/goal %s' "${cond}") "" once   # read once, so a pipe will do
  deadline=$((SECONDS + PROMPT_TIMEOUT_MS / 1000))
  while entry="$(goal_entry "${name}" "${since}" "${goal}")"; [[ -z "${entry}" && ${SECONDS} -lt ${deadline} ]]; do sleep 1; done
  case "${entry}" in
    refused:*) die "${pre} Claude Code refused its /goal (${entry#refused: }); its builder is still open${post}" ;;
    "") die "${pre} its session log shows no goal set for its condition $((PROMPT_TIMEOUT_MS / 1000))s after the /goal; its builder is still open${post}" ;;
  esac
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
\`$(codex_review_cmd "${epic_branch}")\` before committing; fix real findings, decline
nits with a reason, and converge on one clean pass. $(codex_rule) Run the repo's tests and make them pass. $(mutation_rule)
$(reply_sentence epic)
EOF
  else
    before="open the PR"
    cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit and PR with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} $(merge_rule) Never touch real cloud or
credentials. Open the PR against \`${base}\`. Run \`$(codex_review_cmd "${base}")\` before
committing; fix real findings, decline nits with a reason, converge on one clean pass, and record the
loop in the PR body. $(codex_rule) If \`gh pr view --json mergeable\` says
CONFLICTING, merge origin/${base} into your branch, resolve it (keep both sides of any list), re-run
the tests and push: a conflicted PR runs no checks and waits forever. $(mutation_rule) Record it
in the PR body. $(reply_sentence story)
EOF
  fi
  epic="$(fm "${BOARD}/stories/${slug}.md" epic)"
  check=""; [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || extra+="Before you ${before}, also run the epic's check from the worktree root, and make it pass: \`${check}\`"$'\n'
  [[ "${CFG_sign_commits}" != true ]] || extra+="$(sign_rule)"$'\n'
  [[ -z "${extra}" ]] || printf '%s' "${extra}"
  local rules; rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\n%s\n' "${rules}"
  rules_check_step "${before}" "${rules}"
}

# rule_kinds — the kinds of the tagged rules (<!-- lesson: <kind> -->) on stdin, one per line.
rule_kinds() {
  grep -oE -- '<!--[[:space:]]*lesson:[[:space:]]*[a-z0-9-]+[[:space:]]*-->' | sed -E 's/.*lesson:[[:space:]]*([a-z0-9-]+).*/\1/' | sort -u || true
}

# rules_check_step <before> <rules> — a rule pasted into the brief does not stop the mistake, so a
# builder walks its diff against each tagged rule and says what it checked. Nothing without one.
rules_check_step() {
  local kinds where="the PR body"; kinds="$(rule_kinds <<< "$2")"
  [[ -n "${kinds}" ]] || return 0
  [[ "$1" == "open the PR" ]] || where="your reply"
  cat <<EOF

Before you $1, walk your diff against each rule tagged \`<!-- lesson: <kind> -->\` above. Then give
${where} a \`Rules checked:\` section with one line per kind: what in the diff you checked (file:line),
or \`n/a: <why>\`:

Rules checked:
EOF
  sed 's/^/- /; s/$/: <file:line>, or n\/a: <why>/' <<< "${kinds}"
}

# rules_review_rule — the conductor's half of rules_check_step, while the project has tagged rules.
rules_review_rule() {
  [[ -n "$(project_rules | rule_kinds)" ]] || return 0
  printf '\n\n%s' "A builder's PR body (its reply, when it opens no PR) must carry a \`Rules checked:\` section with a line per tagged rule's kind, each naming what it checked (file:line) or \`n/a: <why>\`. A missing section, a missing kind, or a line that names nothing is a finding of kind \`rules-unchecked\`: send it back like any other."
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

# story_role <slug> — the role a story is built as: escalate for a kind an agent builds once its
# attempts: reaches escalate_after (> 0), else its kind, code-risky for code with risk: high, and with
# sonnet_share = N, code-sonnet for the other code stories whose slug's cksum mod N is 0, so a slug
# always lands in the same arm. Only a first attempt is sampled: a slug with an agents.tsv line
# already goes back to code. A missing story or a bad attempts: prints the reason and returns 1.
story_role() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind risk attempts sum
  [[ -f "${story}" ]] || { echo "no story ${story}"; return 1; }
  kind="$(fm "${story}" kind)"; kind="${kind:-code}"; risk="$(fm "${story}" risk)"
  attempts="$(get_fm "${story}" attempts)"; attempts="${attempts:-0}"
  # Checked before any arithmetic, which would evaluate it.
  [[ "${attempts}" =~ ^(0|[1-9][0-9]*)$ ]] \
    || { echo "${story}: attempts must be a non-negative whole number, not '${attempts}'"; return 1; }
  if agent_kind "${kind}" && (( CFG_escalate_after > 0 && attempts >= CFG_escalate_after )); then echo escalate; return; fi
  if [[ "${kind}" != code ]]; then echo "${kind}"; return; fi
  if [[ "${risk}" == high ]]; then echo code-risky; return; fi
  sum="$(printf '%s' "${slug}" | cksum)"; sum="${sum%% *}"
  if [[ ${CFG_sonnet_share} -gt 0 && $((sum % CFG_sonnet_share)) -eq 0 ]] \
     && ! awk -F'\t' -v n="$(agent_name "${slug}")" '$3 == n { f = 1 } END { exit !f }' "${AGENTS_LOG}" 2>/dev/null; then
    echo code-sonnet
  else
    echo code
  fi
}

build_story() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind repo src role wt branch prompt base epic from epic_branch goal="" mode=story
  [[ -f "${story}" ]] || die "no story ${story}"
  grep -q '^status: ready$' "${story}" || die "${slug} is not status: ready"
  kind=$(sed -n 's/^kind: *//p' "${story}" | head -1); kind="${kind:-code}"
  case "${kind}" in
    code|docs|chore|verify) ;;
    lead) die "${slug} is kind: lead — real cloud, credentials or a human step; the lead runs it, not a swarm agent" ;;
    operator) die "${slug} is kind: operator, which is now kind: lead: change it, and mark the user's step **You:**" ;;
    *) die "${slug} has kind: ${kind}; an agent builds only code, docs, chore or verify" ;;
  esac
  repo=$(sed -n 's/^repo: *//p' "${story}" | head -1)   # a repo in repos_dir; empty is the project's own
  role="$(story_role "${slug}")" || die "${role}"
  policy "${role}" >/dev/null
  src="$(repo_dir "${repo}")" || die "${slug}: ${src}"
  # Decided once: the epic branch below, the brief's reply (keyed on that branch) and the goal's.
  epic="$(fm "${story}" epic)"
  [[ "${CFG_pr_per}" != epic || -z "${epic}" ]] || mode=epic
  # Before the epic branch and the worktree exist, so a refusal leaves nothing to clean up.
  require_trusted "${src}"
  if [[ "${CFG_goal}" == off ]]; then require_claude; else
    goal="$(goal_condition "${slug}" "${mode}")" || die "${goal}"
    (( ${#goal} <= GOAL_MAX_CHARS )) \
      || die "${slug}: its goal condition is ${#goal} characters, over Claude Code's ${GOAL_MAX_CHARS}; shorten its **Done when** or **From review**"
    require_claude "${GOAL_MIN_CLAUDE}"
  fi
  base="$(base_for "${src}")"
  from="origin/${base}"; epic_branch=""
  if [[ "${mode}" == epic ]]; then
    [[ -f "${BOARD}/epics/${epic}.md" ]] || die "${slug}: no epic ${BOARD}/epics/${epic}.md"
    epic_branch="$(epic_branch_for "${src}" "${epic}" "${base}")"; from="origin/${epic_branch}"
    add_epic_repo "${epic}" "${repo:-$(basename "${PROJECT_DIR}")}"
  fi
  branch="story/${slug}"; wt="$(worktree_for "${src}" "${slug}")"
  git -C "${src}" worktree add -q -b "${branch}" "${wt}" "${from}"
  prompt="${PROJECT_DIR}/.swarm/briefs/${slug}.md"; mkdir -p "$(dirname "${prompt}")"
  rm -f "${prompt%.md}.goal.md"   # an earlier build's, which a goal-off retry must not keep
  story_brief "${slug}" "${src}" "${base}" "${epic_branch}" > "${prompt}"
  [[ -z "${goal}" ]] || printf '%s\n' "${goal}" > "${prompt%.md}.goal.md"
  # An epic's story gets a pane in the epic's tab; a one-off gets a tab of its own.
  start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}"
  # story_role has checked attempts: is a whole number. The build is attempt attempts + 1.
  [[ "${role}" != escalate ]] || record_event escalate "${slug}" "ok (attempt $(( $(get_fm "${story}" attempts) + 1 )))"
  # Once the brief is taken up, mid-turn: the goal sets at once and costs one extra short turn.
  [[ -z "${goal}" ]] || send_goal "${slug}" "${prompt%.md}.goal.md" brief
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
for the user, unless it has \`escalated_from:\`: that one is the lead's, as above. Stop when the epic's **Done when** holds or when nothing ready is left.
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

# auth_rule — what a conductor does when `wait` on a builder prints auth.
auth_rule() {
  cat <<EOF
A builder whose \`swarm.sh wait\` prints \`auth\` stopped on an expired login, which only the user's
/login clears: do not tell it, nudge it or wait on it again. Note it, and once you are told your
login is renewed, tell each such builder to resume (\`swarm.sh tell <slug> resume <file>\`) and wait on it
again with \`swarm.sh wait <slug>\` in the background.
EOF
}

# goal_rule — with goal on, how a conductor reads why a builder stopped short of its reply, and the
# close that cause takes. The causes are close_agent's; reading them is the goal spike's.
goal_rule() {
  cat <<EOF
Each builder works to a goal (goal = ${CFG_goal}). When \`swarm.sh wait\` returns idle for a builder
short of its reply, read why it stopped from its reply and its transcript, never its pane. The
transcript is \`${CLAUDE_PROJECTS}/*/<session>.jsonl\`, where <session> is field 7 of the last line in
.swarm/agents.tsv whose name (field 3) is the builder's agent name: its slug lowercased, each
character outside a-z, 0-9, _ and - made -, an s in front unless it starts with a letter, then cut
to 32 characters. That line is the current build. Read the reply first: \`IMPOSSIBLE:\` or the story's reply. Then read
the \`reason\` of the last \`goal_status\` entry with \`met:true\`. Act on the cause:
- met: the story's reply is there. Review it as below; the closes after review or merge stay bare.
- impossible: the reply starts \`IMPOSSIBLE:\`.
  Run \`swarm.sh close <slug> impossible\`, which makes the story \`kind: lead\`, and list it for the lead.
- stalled: \`wait --stall\` returned stalled.
  Run \`swarm.sh close <slug> stalled\` and start the story again in a later wave.
- bound: the reply is not there, and the met entry's reason says the stop-after clause applied.
  Run \`swarm.sh close <slug> bound\` and start the story again in a later wave.
- paused: the goal is still set, with no met entry since, and the builder is idle.
  Send it one \`swarm.sh tell <slug> resume <file>\` and wait on it again.
  If it stops paused again, run \`swarm.sh close <slug> paused\`. It counts nothing and holds the
  story for the lead (\`kind: lead\`, \`held_for: paused\`): list it for the lead, as for cleared-on-error.
- cleared-on-error: the transcript holds a \`/goal\` refusal (a \`system\` \`local_command\` entry whose
  stdout refuses \`/goal\`, with no \`goal_status\` after it), or the goal is gone and the transcript
  ends on an API error; or \`swarm.sh story\` failed on a refused goal.
  Run \`swarm.sh close <slug> cleared-on-error\`, start nothing more in this wave, and list it for
  the lead, who decides whether to build it again. The close holds the story for the lead
  (\`kind: lead\`, \`held_for: cleared-on-error\`), so no wave builds it until the lead lifts the hold.
  If either close prints no \`held:\` line (it prints \`not held:\` instead), the story stays \`ready\`
  with nothing on it to say so: do not start it again in a later wave. It waits for the lead.
- none of the above fits (no reply, no refusal, no stall, and no goal entry, or a met entry whose
  reason is not the stop-after clause): run \`swarm.sh close <slug> stalled\`, which counts the
  attempt so escalate_after bounds the retries, and start the story again in a later wave.
EOF
}

# give_up_rule — when a conductor stops waiting on a builder and builds the story again, and how it
# answers Fable's usage-credits consent, which is not giving up. With goal on, an idle builder is the
# goal rule's, and the stall close names its cause.
give_up_rule() {
  local retry idle="when it is idle with no PR
(with one PR per epic, no pushed story/<slug>) after wait's nudges, " close="\`swarm.sh close <slug>\`" one="That is the one close before a review passes." goal=""
  if [[ "${CFG_goal}" != off ]]; then
    idle=""
    close="\`swarm.sh close <slug> stalled\` for a stall, or \`swarm.sh close <slug> met\` when review has not converged"
    one="Those and the goal rule's closes are the only ones before a review passes."
    goal="
A builder idle short of its reply is not one to give up on here: it is the goal rule's, which picks
its close and whether the story is started again."
  fi
  if (( CFG_escalate_after > 0 )); then
    retry="swarm.sh picks Fable for build $((CFG_escalate_after + 1)) (escalate_after = ${CFG_escalate_after})."
  else
    retry="escalation is off (escalate_after = 0), so once a story has failed twice
(\`attempts: 2\`), do not start it again: report it to the lead."
  fi
  cat <<EOF
Give up on a builder when \`swarm.sh wait --stall <slug>\` returns stalled, ${idle}or when review has
not converged in the rounds you allow. Run ${close}: on a code, docs or chore story still \`ready\` it
counts the attempt and clears its worktree, branch and PR. ${one} Start the story again in a later
wave with \`swarm.sh story <slug>\`, and never choose a model: ${retry}${goal}
A story that comes back \`kind: lead\` with \`escalated_from:\` is the lead's to decide: report it
to the lead, and do not count it as waiting on the user.

A builder whose wait prints \`waiting: dialog open\` may be on Fable's usage-credits consent. Answer it
only when it is an escalate build (\`swarm.sh _role <slug>\` prints \`escalate\`) and its pane
(\`swarm.sh _target <slug>\` prints it) shows that consent in \`herdr agent read <pane>\`. Then accept it
with \`herdr pane send-keys <pane> <key>...\`, run \`swarm.sh dialog <slug> accepted\` (or \`dismissed\`
if it would not accept, and tell the lead), and wait on it again. Never close or tell it over a
dialog: a dialog is not an attempt. Any other dialog, and every permission or tool prompt, is not
yours to answer: never send keys to it; leave it for the lead.
EOF
}

# goal_rule_if_on — goal_rule after a blank line, or nothing with goal off.
goal_rule_if_on() { [[ "${CFG_goal}" == off ]] || printf '\n\n%s' "$(goal_rule)"; }

# pr_per = story: a PR per story.
conduct_story_mode() {
  local epic="$1"
  cat <<EOF
Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) to merge, as method.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap,
start each with \`${SWARM_HOME}/bin/swarm.sh story <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch --epic ${epic}\` in the background, and review each PR. Each story's base branch is in its brief,
.swarm/briefs/<slug>.md.

$(auth_rule)$(goal_rule_if_on)

$(give_up_rule)

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

$(auth_rule)$(goal_rule_if_on)

$(give_up_rule)

When a builder reports, review its branch.$(rules_review_rule)

Then, one story at a time, merge it into the epic branch
in a worktree of epic/${epic} beside its repo (../<repo>-wt/epic-${epic}):
\`git merge --no-ff${sign} origin/story/<slug>\`, run the repo's tests${check} there,
and push epic/${epic}. Then run \`swarm.sh finish <slug>\`, \`swarm.sh unblock\` and
\`swarm.sh close <slug>\`, and go on to the next wave.

When the epic's stories are all finished (a fresh conductor may start here; the epic's \`repos:\`
line lists every repo with an epic branch), review the whole epic: in each repo's epic worktree,
\`$(codex_review_cmd '<base>')\`, where \`swarm.sh base <repo>\` prints the base.
$(codex_rule) Fix real findings on the epic branch and rebut the rest. Then open one PR per repo from epic/${epic} into its
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
  # Before the brief, the old report's removal and the workspace, so a refusal changes nothing.
  require_claude
  prompt="${PROJECT_DIR}/.swarm/briefs/conduct-${epic}.md"; mkdir -p "$(dirname "${prompt}")"
  conduct_brief "${epic}" > "${prompt}"
  rm -f "$(conductor_report "conduct-${epic}")"   # a report left by an earlier run is not this one's
  read -r ws placeholder <<< "$(hld_workspace "${hld}")"
  # On exit, not after start_agent: a conductor that fails to start dies, and left the tab empty.
  # shellcheck disable=SC2064 # expand now; the tab id is herdr's, [a-zA-Z0-9:]
  [[ -z "${placeholder}" ]] || trap "herdr tab close '${placeholder}' >/dev/null 2>&1 || true" EXIT
  HERDR_WORKSPACE_ID="${ws}" start_agent "${epic}" "conduct-${epic}" "${PROJECT_DIR}" conduct "${prompt}" conductor
  echo "workspace ${hld} (${ws})"
  # An epic being built is active, or status and next list it as a later epic waiting on the user.
  # An uncommitted board edit, as unblock's are; any other status is left as it is. The conductor is
  # already running, so a file that cannot be written is reported, never fatal: a failed conduct
  # would invite a second conductor.
  [[ "$(get_fm "${epic_file}" status)" == later ]] || return 0
  if set_fm "${epic_file}" status active 2>/dev/null; then
    echo "epic ${epic}: status later -> active (uncommitted board edit)"
  else
    rm -f "${epic_file}.tmp"
    echo "epic ${epic}: could not write ${epic_file}, so it is still later; set status: active by hand" >&2
  fi
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
#   wait <agent>      a conductor exists and has not reported (idle between its own steps counts);
#                     why starts `auth:` when its login expired (wait then prints auth at once)
#   conduct <epic>    an active epic has a story an agent can build, or (pr_per = epic) every story
#                     merged into its epic branch and no PR yet
#   resume <slug>     a one-off already started (its worktree exists): wait for it, then review
#   story <slug>      a ready story outside any epic
#   plan-epic <epic>  an active epic has no stories yet
#   plan-hld <hld>    an agreed HLD has no epics listed under ## Epics
#   hld <hld>         an HLD is still a draft
#   escalated <slug>  a story whose Fable build failed, whose builder called its Done when
#                     impossible, or that close held (paused, cleared-on-error; held_for:), all kind:
#                     lead with escalated_from:: the lead re-scopes it or lifts the hold and runs
#                     reset, or drops it
#   gate              only the user can move the board: lead stories, blocked
#                     stories, later stories and epics, and PRs awaiting the user's merge
#   done              nothing open; start the next HLD with /hld <title>
next_step() {
  local f slug epic kind story_epic src buildable="" waiting="" b open when held
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    # Any status: idle is not finished. Only the conductor's report file says it is done.
    # A retired conductor (renamed <name>-done, -done2 ...) has finished: never wait on it.
    # herdr lists every project's agents: only one in a pane this project opened counts.
    slug=$(herdr agent list 2>/dev/null | SWARM_PANES="$(own_panes)" json "next((a['name'] for a in d['result']['agents'] if a.get('name','').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done') and a.get('pane_id') in e.get('SWARM_PANES','').split()),'')" 2>/dev/null || true)
    if [[ -n "${slug}" ]]; then
      if [[ -f "$(conductor_report "${slug}")" ]]; then
        echo "collect ${slug}"; echo "the conductor ${slug} has finished and written its report"
      elif [[ "$(session_state "${slug}")" == idle ]] && login_expired "${slug}"; then
        # As in wait, only an idle session is auth: wait returns it at once, and /swarm-dev:swarm stops there
        # for the user's /login.
        echo "wait ${slug}"; echo "auth: the conductor ${slug} stopped on an expired login; run /login, then /swarm-dev:swarm tells it to resume"
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
    # Stories are scoped against the code its dependencies build, so wait until they are done.
    open=0
    for b in $(sed -n 's/^depends_on: *\[\(.*\)\]$/\1/p' "${f}" | tr ',' ' ' | tr -d "\"'"); do
      if open_item "${BOARD}/stories/${b}.md" || open_item "${BOARD}/epics/${b}.md"; then open=1; fi
    done
    [[ ${open} -eq 0 ]] || continue
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
  while IFS= read -r f; do
    is_escalated "${f}" || continue
    slug=$(basename "${f}" .md); when="$(reset_at "${slug}")"; held="$(get_fm "${f}" held_for)"
    echo "escalated ${slug}"
    if [[ -n "${held}" ]]; then
      echo "${slug} is held (${held}): its builder stopped on its goal, which counts nothing; lift the hold with swarm.sh reset ${slug} <reason> to build it again, or swarm.sh drop ${slug} <reason>, then tell the user why"
    elif [[ -n "${when}" ]] && impossible_block "${f}"; then
      echo "${slug}'s builder called its Done when impossible after its one reset (${when}): drop it with swarm.sh drop ${slug} <reason>, then tell the user why"
    elif impossible_block "${f}"; then
      echo "${slug}'s builder called its Done when impossible: re-scope it and run swarm.sh reset ${slug} <reason>, or swarm.sh drop ${slug} <reason>, then tell the user why"
    elif [[ -n "${when}" ]]; then
      echo "${slug} failed on Fable again after its one reset (${when}): drop it with swarm.sh drop ${slug} <reason>, then tell the user why"
    else
      echo "${slug} failed on Fable: re-scope it and run swarm.sh reset ${slug} <reason>, or swarm.sh drop ${slug} <reason>, then tell the user why"
    fi
    return
  done < <(board stories)
  waiting="$(waiting_on_user)"
  if [[ -n "${waiting}" ]]; then
    echo "gate"; echo "only you can move the board now:"; printf '%s\n' "${waiting}"; return
  fi
  echo "done"; echo "nothing is open; start the next HLD with /hld <title>"
}

# is_escalated <story-file> — true for a story lead_block handed on: ready, kind: lead, with
# escalated_from:. It is the lead's to decide (next's escalated step), never the user's, impossible
# ones (impossible_block) included.
is_escalated() { [[ "$(fm "$1" status)" == ready && "$(fm "$1" kind)" == lead && -n "$(get_fm "$1" escalated_from)" ]]; }

# impossible_block <story-file> — true when the story's lead block is impossible_story's.
impossible_block() {
  awk -v o="${ESCALATED_OPEN}" -v c="${ESCALATED_CLOSE}" '$0 == o { s = 1 } $0 == c { s = 0 }
    s && index($0, "**Impossible.**") == 1 { y = 1 } END { exit !y }' "$1"
}

# waiting_on_user — one line per board item only the user can move: lead stories (not an escalated
# one, which is the lead's), blocked and later items, and PRs awaiting the user's merge. Shared by
# next_step's gate, status and dash.
waiting_on_user() {
  local f kind slug waiting=""
  while IFS= read -r f; do
    kind=$(fm "${f}" kind); slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      ready) agent_kind "${kind}" || is_escalated "${f}" || waiting+="  ${kind}: ${slug}"$'\n' ;;
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

# reset_at <slug> — when the slug was reset (its first ok reset line in events.tsv), or nothing. A story
# is reset at most once.
reset_at() { awk -F'\t' -v s="$1" '$2 == "reset" && $3 == s && index($5, "ok") == 1 { print $1; exit }' "${EVENTS_LOG}" 2>/dev/null || true; }

# reset <slug> <reason> — put a story the lead re-scoped back in the build queue: drop attempts:,
# put kind back from escalated_from: (no kind: line for NO_KIND_LINE) while the story still says
# kind: lead, so a kind the lead re-scoped stays, drop escalated_from:, and remove escalate_story's
# block. A held story (held_for:, held_story) keeps attempts: and loses held_for:, and its reset is not
# counted as the one. A story with
# neither attempts: nor escalated_from: is refused, and so is a second reset (an ok reset line for the
# slug in events.tsv): at most one per story. So is a block whose close marker is gone, which would
# take the rest of the file with it. main logs the reason as the outcome.
reset_story() {
  local slug="$1" f from when put kind held
  [[ -n "${slug}" ]] || die "reset: <slug> is missing: swarm.sh reset <slug> <reason>"
  [[ -n "${2//[[:space:]]/}" ]] || die "reset: <reason> is missing: swarm.sh reset ${slug} <reason>"
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "reset: bad slug '${slug}'"
  f="${BOARD}/stories/${slug}.md"
  [[ -f "${f}" ]] || die "reset: no story ${f}"
  from="$(get_fm "${f}" escalated_from)"
  [[ -n "${from}$(get_fm "${f}" attempts)" ]] || die "reset: ${slug} has neither attempts: nor escalated_from:, so there is nothing to reset"
  held="$(get_fm "${f}" held_for)"
  when="$(reset_at "${slug}")"
  [[ -n "${held}" || -z "${when}" ]] || die "reset: ${slug} was reset already, at ${when} (events.tsv); a story is reset at most once, so drop it: swarm.sh drop ${slug} <reason>"
  awk -v o="${ESCALATED_OPEN}" -v c="${ESCALATED_CLOSE}" '$0 == o { s = 1 } $0 == c { s = 0 } END { exit s }' "${f}" \
    || die "reset: ${f} has the line '${ESCALATED_OPEN}' and no '${ESCALATED_CLOSE}' after it, so the block's end is unknown; put that line back where the block ends, then reset again"
  put="${from}"; [[ "${from}" != "${NO_KIND_LINE}" ]] || put=""
  [[ -z "${from}" || "$(get_fm "${f}" kind)" != lead ]] || set_fm "${f}" kind "${put}"
  set_fm "${f}" escalated_from
  set_fm "${f}" held_for
  [[ -n "${held}" ]] || set_fm "${f}" attempts
  awk -v o="${ESCALATED_OPEN}" -v c="${ESCALATED_CLOSE}" '$0 == o { s = 1 } !s { print } $0 == c { s = 0 }' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
  kind="$(get_fm "${f}" kind)"
  if [[ -n "${held}" ]]; then echo "reset: ${slug} (kind: ${kind:-none, so code}; the ${held} hold is lifted, attempts: as it was)"; return; fi
  echo "reset: ${slug} (kind: ${kind:-none, so code}; no attempts:)"
}

# drop <slug> <reason> — the lead drops an escalated story (is_escalated): take it off the board as
# finish does (delete it, or with finished = mark set status: done), so next stops naming it, and the
# lead commits the change in a board PR. Any other story is
# refused. main logs the reason as the outcome.
drop_story() {
  local f="${BOARD}/stories/$1.md"
  [[ -n "$1" ]] || die "drop: <slug> is missing: swarm.sh drop <slug> <reason>"
  [[ -n "${2//[[:space:]]/}" ]] || die "drop: <reason> is missing: swarm.sh drop $1 <reason>"
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "drop: bad slug '$1'"
  [[ -f "${f}" ]] || die "drop: no story ${f}"
  is_escalated "${f}" || die "drop: $1 is not an escalated story (ready, kind: lead, with escalated_from:), so it is not dropped"
  finish_item "$1"
  echo "dropped: $1; commit the change to the board in a board PR"
}

# dialog <slug> <accepted|dismissed> — a conductor answered an escalate builder's Fable usage-credits
# consent (wait printed `waiting: dialog open`). It changes nothing: main logs `dialog <slug>` with
# `ok (<result>)` as the outcome, so each escalation step is in events.tsv with its time.
dialog_answered() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "dialog: bad slug '$1': swarm.sh dialog <slug> <accepted|dismissed>"
  [[ -f "${BOARD}/stories/$1.md" ]] || die "dialog: no story ${BOARD}/stories/$1.md"
  [[ "$2" == accepted || "$2" == dismissed ]] || die "dialog: the result must be accepted or dismissed, not '$2'"
  echo "logged: dialog $1 $2"
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

# SET_FM_KEYS: the front-matter keys swarm.sh writes (set_fm refuses any other): status, prs and
# blocked_by too, which review and unblock write. reconcile puts them back as committed on an item
# whose PRs merged, and carries another board file's edit to them over its pull, so they never stop it.
SET_FM_KEYS="attempts kind escalated_from held_for status prs blocked_by"

# set_fm <file> <key> [value] — in the front matter, set <key>'s line to <value>, adding it at the end
# when there is none, or drop it when <value> is empty. <key> must be one of SET_FM_KEYS.
set_fm() {
  [[ " ${SET_FM_KEYS} " == *" $2 "* ]] || die "set_fm: $2 is not in SET_FM_KEYS"
  awk -v k="$2" -v v="${3:-}" '
    /^---$/ && ++n == 2 && !d && v != "" { print k ": " v }
    n == 1 && index($0, k ":") == 1 { if (!d && v != "") print k ": " v; d = 1; next }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# get_fm <file> <key> — <key>'s value in the front matter alone, where set_fm writes it (fm takes the
# first line for <key> anywhere, so a story's body could answer). <file> may be - for stdin.
get_fm() {
  awk -v k="$2" '/^---$/ && ++n == 2 { exit }
    n == 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^ +/, "", v); print v; exit }' "$1"
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

# builder_state <slug> — open when this project's builder for <slug> is open in herdr, none when it is
# not, unknown when herdr cannot list its agents. Outside herdr (HERDR_ENV unset) it is none, and herdr
# is never called.
builder_state() {
  local agents
  [[ "${HERDR_ENV:-}" == 1 ]] || { echo none; return; }
  # One list, read as agent_field reads it: a pane this project opened, under the builder's name.
  agents="$(herdr agent list 2>/dev/null)" \
    && SWARM_NAME="$(agent_name "$1")" SWARM_PANES="$(own_panes)" json "'open' if any(a.get('name') == e['SWARM_NAME'] and a.get('pane_id') in e['SWARM_PANES'].split() for a in d['result']['agents']) else 'none'" <<< "${agents}" 2>/dev/null \
    || echo unknown
}

# reconcile — for each item in review: finish it once every PR it lists has merged; send it back to
# ready, saying which, if any closed without merging; otherwise leave it waiting. A story's build is
# cleared (clear_build) before the pull, while its file still names its repo: always once it merged,
# after closing its builder if one is open (still in review, so close counts nothing), and saying so
# when herdr cannot tell whether one is; after a
# closed PR only when no builder is open (one may be fixing it; so may one herdr cannot list), so the
# story can be built again.
reconcile() {
  local f slug url state closed waiting urls builder merged=()
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
      if [[ "${f}" == "${BOARD}/stories/"* ]]; then
        case "$(builder_state "${slug}")" in
          none) clear_build "${slug}" "the PR of ${slug} closed unmerged" "[]" </dev/null ;;
          open) echo "build kept: ${slug}'s builder is still open, so its worktree and story/${slug} stay" ;;
          *) echo "build kept: ${slug}'s builder may be open (herdr cannot list its agents), so its worktree and story/${slug} stay" ;;
        esac
      fi
      set_status "${f}" ready
      record_event reconcile "${slug}" "ok (reopened)"
      echo "back to ready: ${slug} (closed without merging:${closed})"
    elif [[ ${waiting} -eq 0 ]]; then
      if [[ "${f}" == "${BOARD}/stories/"* ]]; then
        builder="$(builder_state "${slug}")"
        [[ "${builder}" != open ]] || close_agent "${slug}" </dev/null   # stdin is this loop's list
        clear_build "${slug}" "the PR of ${slug} merged" "[]" </dev/null
        [[ "${builder}" != unknown ]] \
          || echo "build cleared: ${slug}'s builder may still be open (herdr cannot list its agents); close its pane with swarm.sh close ${slug}"
      fi
      merged+=("${slug}")
    fi
  done < <(board stories; board epics)
  [[ ${#merged[@]} -gt 0 ]] || return 0
  local i k committed saved=()
  if [[ ${BOARD_IN_REPO} == 1 ]]; then
    # The board is in the project repo, and a merged PR may itself have taken the item off it or
    # changed it. Our own edits (each SET_FM_KEYS key, such as the review status or a retry's
    # attempts:) would block that pull, so put them back as committed first, and the whole file as it
    # was if the pull fails. A hand edit is left alone, and still stops the pull.
    for slug in "${merged[@]}"; do
      f="$(item_file "${slug}")"; saved+=("$(cat "${f}"; echo .)")   # the dot keeps trailing newlines
      if committed="$(git -C "${PROJECT_DIR}" show "HEAD:${f#"${PROJECT_DIR}"/}" 2>/dev/null)"; then
        for k in ${SET_FM_KEYS}; do set_fm "${f}" "${k}" "$(get_fm - "${k}" <<< "${committed}")"; done
      fi
    done
    if git -C "${PROJECT_DIR}" rev-parse -q --verify '@{upstream}' >/dev/null && ! pull_board_repo; then
      for i in "${!merged[@]}"; do printf '%s' "${saved[i]%.}" > "$(item_file "${merged[i]}")"; done
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
# stopped by it. It also backs up and checks out each unstaged board file the pull changes whose edit
# is only to SET_FM_KEYS (swarm_edit), and puts those keys back after the pull; one the pull deletes
# stays deleted, named. It stops, touching nothing, naming the file, when the base changed one of
# those keys too, or a dependency under a status flip (key_clash). Any other edit is left alone. If
# the pull still fails, every file is restored from the backup in STATE_DIR/reconcile-backup/; the
# backup also stays, named, when the pull deleted a kept file or a key could not be set again. On
# failure PULL_WHY says why.
PULL_WHY=""
pull_board_repo() {
  local line path rel bak changed old k lost=0 put=() keep=()
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
    if git -C "${PROJECT_DIR}" cat-file -e "@{upstream}:${path}" 2>/dev/null \
      && git -C "${PROJECT_DIR}" show "@{upstream}:${path}" | cmp -s - "${PROJECT_DIR}/${path}"; then
      put+=("${path}")
    elif [[ "${line:0:2}" == " M" ]] && swarm_edit "${path}"; then
      k="$(key_clash "${path}")"
      [[ -z "${k}" ]] || { PULL_WHY="${path} has an uncommitted front-matter edit, and the base changed its ${k}: too"; return 1; }
      keep+=("${path}")
    fi
  done < <(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=all -- "${BOARD}")
  bak="${STATE_DIR}/reconcile-backup/$(date +%Y%m%dT%H%M%S)-$$"
  for path in "${put[@]+"${put[@]}"}" "${keep[@]+"${keep[@]}"}"; do
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
  for path in "${keep[@]+"${keep[@]}"}"; do
    echo "reconcile: ${path} changes only swarm.sh's front-matter keys; checking it out for the pull, to set them again after it (backup in ${bak})"
    git -C "${PROJECT_DIR}" checkout -q -- "${path}"
  done
  old="$(git -C "${PROJECT_DIR}" rev-parse HEAD)"
  # Fast-forward to the upstream fetched above, which every check here read: a pull would fetch again.
  if ! git -C "${PROJECT_DIR}" merge -q --ff-only '@{upstream}'; then
    for path in "${put[@]+"${put[@]}"}" "${keep[@]+"${keep[@]}"}"; do cp -p "${bak}/${path}" "${PROJECT_DIR}/${path}"; done
    PULL_WHY="the pull failed, and every board edit is as it was$(board_edits_named)"
    return 1
  fi
  for path in "${keep[@]+"${keep[@]}"}"; do keys_back "${path}" "${old}" "${bak}/${path}" || lost=1; done
  if [[ ${lost} -eq 1 ]]; then echo "reconcile: the backup stays in ${bak}"; return 0; fi
  rm -rf "${bak}"; rmdir "${STATE_DIR}/reconcile-backup" 2>/dev/null || true
}

# fm_rest <file> — <file> without the SET_FM_KEYS lines of its front matter; <file> may be - for stdin.
fm_rest() {
  awk -v keys=" ${SET_FM_KEYS} " '/^---$/ { n++ }
    n == 1 && match($0, /^[a-z_]+:/) && index(keys, " " substr($0, 1, RLENGTH - 1) " ") { next }
    { print }' "$1"
}

# swarm_edit <path> — true when the pull changes the board file <path> and its unstaged edit is only
# to SET_FM_KEYS (an unblock flip, a review), so it can be checked out for the pull and put back.
swarm_edit() {
  [[ "$(git -C "${PROJECT_DIR}" rev-parse -q --verify "HEAD:$1")" != "$(git -C "${PROJECT_DIR}" rev-parse -q --verify "@{upstream}:$1")" ]] \
    && cmp -s <(git -C "${PROJECT_DIR}" show "HEAD:$1" | fm_rest -) <(fm_rest "${PROJECT_DIR}/$1")
}

# key_clash <path> — the first SET_FM_KEYS key the unstaged board file <path> changes from HEAD's that
# the base changed to another value too, or, when the edit changes status, blocked_by or depends_on
# if the base changed it (a status is not set again over a new dependency); nothing when there is
# none, or the base deleted <path>.
key_clash() {
  local k l h u head up deps=""
  up="$(git -C "${PROJECT_DIR}" show "@{upstream}:$1" 2>/dev/null)" || return 0
  head="$(git -C "${PROJECT_DIR}" show "HEAD:$1")"
  [[ "$(get_fm "${PROJECT_DIR}/$1" status)" == "$(get_fm - status <<< "${head}")" ]] || deps="blocked_by depends_on"
  for k in ${SET_FM_KEYS} ${deps}; do
    l="$(get_fm "${PROJECT_DIR}/$1" "${k}")"; h="$(get_fm - "${k}" <<< "${head}")"; u="$(get_fm - "${k}" <<< "${up}")"
    [[ "${u}" == "${h}" || "${u}" == "${l}" ]] && continue
    [[ "${l}" == "${h}" && " ${deps} " != *" ${k} "* ]] && continue
    echo "${k}"; return 0
  done
}

# keys_back <path> <rev> <saved> — after the pull, set on the board file <path> each SET_FM_KEYS key
# whose value in <saved>, its copy from before, differs from <rev>'s. It fails, naming <saved>, when
# the pull deleted <path> or a key cannot be set.
keys_back() {
  local k v was bad=""
  [[ -f "${PROJECT_DIR}/$1" ]] || { echo "reconcile: the pull deleted $1, and its uncommitted front-matter edit with it (its copy is in $3)"; return 1; }
  was="$(git -C "${PROJECT_DIR}" show "$2:$1")"
  for k in ${SET_FM_KEYS}; do
    v="$(get_fm "$3" "${k}")"
    [[ "${v}" == "$(get_fm - "${k}" <<< "${was}")" ]] || set_fm "${PROJECT_DIR}/$1" "${k}" "${v}" || bad+=" ${k}"
  done
  [[ -z "${bad}" ]] || { echo "reconcile: cannot set${bad} again on $1 after the pull (its copy is in $3)"; return 1; }
  echo "reconcile: $1 took the pull and keeps its uncommitted front-matter edit"
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
# or when its head has had no check at all for WATCH_STALL_SECS (default 600). An agent of this
# project whose session is waiting (herdr's blocked, for an agent herdr answers for) also needs the
# lead, named with what it waits for. Each head is reported once, and each agent's wait once, until a
# poll finds that agent no longer waiting (state in .swarm/state).
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
      local agents sessions now e news="" tmp
      # Only agents in panes this project opened: herdr lists every project's. Each one's state is
      # PANES_PY's agent_state: its session's, else herdr's (codex, or no session recorded). One line
      # per agent waiting, "<name> (<what it waits for>)". A read that fails (herdr's list, Claude
      # Code's, or the reader) changes nothing: a failed Claude list would read every session unknown.
      if agents="$(herdr agent list 2>/dev/null)" && sessions="$(claude_agents)" \
        && now="$(printf '%s' "${agents}" | SWARM_PANES_PY="${PANES_PY}" SWARM_OWN="$(own_panes)" SWARM_SESSIONS="${sessions}" \
        python3 -c '
import json, os, sys
exec(os.environ["SWARM_PANES_PY"])
own = set(os.environ["SWARM_OWN"].split())
for a in json.load(sys.stdin)["result"]["agents"]:
    name = a.get("name")
    if name and a.get("pane_id") in own:
        s = session_state(sys.argv[1], name, os.environ["SWARM_SESSIONS"])
        if agent_state(a, name, s)[0] == "WAITING":
            print(name + (f" ({s[1]})" if s and s[1] else ""))' "${AGENTS_LOG}" 2>/dev/null)"; then
        while IFS= read -r e; do
          if [[ -n "${e}" ]] && ! grep -qxF "waiting ${e}" "${seen}"; then news=1; fi
        done <<< "${now}"
        # seen's waiting lines become exactly the agents waiting now: an agent that stopped waiting is
        # forgotten at once, so its next wait is reported again, whoever else still waits.
        if [[ "$(sed -n 's/^waiting //p' "${seen}" | sort)" != "$(sort <<< "${now}")" ]]; then
          tmp="$(mktemp "${STATE_DIR}/watch-seen.XXXXXX")"
          { grep -v '^waiting ' "${seen}" || true; [[ -z "${now}" ]] || printf 'waiting %s\n' "${now//$'\n'/$'\n'waiting }"; } > "${tmp}"
          mv "${tmp}" "${seen}"
        fi
        if [[ -n "${news}" ]]; then echo "agent(s) waiting: ${now//$'\n'/, }"; return 0; fi
      fi
    fi
    sleep 60
  done
}

# status [--all] — one summary for the user: the agents that need a look or are working, what is
# waiting on them, and what `next` would do; idle agents and blocked stories are only counted unless
# --all. A pane with no agent in it is shown as empty: a start that failed. Panes closed by hand are
# left out. A Claude agent's state is its session's (one claude_agents call per run); herdr's word
# only for codex, an agent with no session recorded, and a retired one.
status_report() {
  local all="${1:-}" agents panes waiting sessions
  if [[ "${HERDR_ENV:-}" == 1 ]] && agents=$(herdr agent list 2>/dev/null) && panes=$(herdr pane list 2>/dev/null); then
    sessions="$(claude_agents)" || sessions=""   # a failed call reads as unknown, as an empty one does
    SWARM_PANES_PY="${PANES_PY}" SWARM_OWN="$(own_panes)" SWARM_SESSIONS="${sessions}" \
      python3 - "${STATE_DIR}" "${agents}" "${panes}" "${all}" "${AGENTS_LOG}" "${CLAUDE_PROJECTS}" <<'PY'
import json, os, sys
exec(os.environ["SWARM_PANES_PY"])
state, agents_json, panes_json, show_all, log, projects = sys.argv[1:7]
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
        s = session_state(log, name, os.environ["SWARM_SESSIONS"])
        st, _ = shown_state(a, name, s, log, projects)
        what = {"EMPTY": "EMPTY: no agent started in this pane; close it",
                "auth": "auth: its login expired; run /login, then /swarm-dev:swarm tells it to resume",
                "WAITING": f"WAITING on {(s or ('', ''))[1] or 'a question'}: herdr agent read {name}",
                "retired": "done (retired)",
                "unknown": "unknown: no session state" if s else "unknown",
                "gone": "gone: session ended",
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
  # init's marker; checked after the arguments and before any drawing, so --watch never draws an empty board either.
  [[ -f "${BOARD}/stories/README.md" ]] || die "dash: no board at ${BOARD}; run swarm.sh init from the project's root"
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
# names story/<slug> (its own PR's merge), or is the story's own work (it also changes a file that is
# not the board's own (its stories/, epics/, Board.base and README.md) nor a repo-root *.md, and its
# subject names no board/, close/ or epic/ branch: a squash-merged story PR, whose work may sit beside
# the board, as docs/operations.md does), the swarm finished it (finish, or reconcile "finished", in events.tsv), or
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
BOARD_OWN = tuple(prefix + f for f in ("stories/", "epics/", "Board.base", "README.md"))   # the board's own files
tips = [ref] + (["HEAD"] if ref != "HEAD" else [])
log = git(["log", "--first-parent", "--diff-merges=first-parent", "--no-color", "--no-renames", "--name-status", "--format=%x00%H%x09%s"] + tips + ["--"])
todo = []   # (slug, cat-file spec, closed by its commit), newest first
for chunk in log.decode("utf-8", "replace").split("\0")[1:]:
    head, _, changes = chunk.partition("\n")
    commit, _, subject = head.partition("\t")
    paths = [c.partition("\t")[2] for c in changes.splitlines() if "\t" in c]
    work = not BOOKKEEPING.search(subject) and any(
        not p.startswith(BOARD_OWN) and ("/" in p or not p.endswith(".md")) for p in paths)
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
  local every="$1" tty="$2" tpl="" frame last="" key i winch=0 inst="" ver="" path="" now=""
  # The installed copy this runs from, if it is one: its scope and project, to re-read each frame. A
  # dev checkout matches no entry, so it never jumps to the installed copy.
  IFS=$'\t' read -r inst path ver <<< "$(dash_installed)"
  if [[ ${tty} == 1 ]]; then
    trap 'printf "\033[?25h\033[?1049l"' EXIT
    printf '\033[?1049h\033[?25l'
  fi
  trap 'exit 0' INT TERM HUP
  trap 'winch=1' WINCH
  while :; do
    if [[ -n "${inst}" ]]; then
      IFS=$'\t' read -r _ path now <<< "$(dash_installed "${inst}")"
      [[ -z "${now}" || "${now}" == "${ver}" ]] || dash_reexec "${path}/bin/swarm.sh" "${every}" "${tty}"
    fi
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

# dash_installed [<install>] — this plugin's entry in installed_plugins.json as its install
# (scope:projectPath, as project installs share a scope), installPath and version, tab-separated: that
# install's entry, or with none the entry installed at SWARM_HOME (paths resolved). Installs at the
# same version share an installPath, so this project's own install wins, then one with no project.
# Prints nothing when the file is missing or unreadable or has no such entry.
dash_installed() {
  python3 - "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/installed_plugins.json" "${PLUGIN}" \
    "${SWARM_HOME}" "${PROJECT_DIR}" "${1:-}" <<'PY' 2>/dev/null || true
import json, os, sys
path, plugin, home, project, inst = sys.argv[1:]
real = os.path.realpath
try:
    entries = [(f"{e['scope']}:{e.get('projectPath', '')}", e) for e in json.load(open(path))["plugins"][plugin]]
    if inst:
        found = [(k, e) for k, e in entries if k == inst]
    else:
        def rank(ke):
            where = ke[1].get("projectPath")
            return 1 if not where else 0 if real(where) == real(project) else 2
        found = sorted(((k, e) for k, e in entries if real(e["installPath"]) == real(home)), key=rank)
    if found:
        print(found[0][0], found[0][1]["installPath"], found[0][1]["version"], sep="\t")
except Exception:
    pass
PY
}

# dash_reexec <script> <seconds> <tty> — exec the newly installed <script> as `dash --watch <seconds>`
# on this project (the cwd may be gone), with the tree and ladder as they stand now. exec keeps the
# PID and skips the EXIT trap, so a terminal is restored first, in case the new script dies before
# it enters the alternate screen again. A script that is not an executable file is ignored.
dash_reexec() {
  [[ -f "$1" && -x "$1" ]] || return 0
  local script="$1"
  [[ $3 == 0 ]] || printf '\033[?25h\033[?1049l'
  set -- dash --watch "$2"
  [[ ${DASH_LADDER} == 0 ]] || set -- "$@" --ladder
  [[ ${DASH_TREE} == 0 ]] || set -- "$@" --tree
  SWARM_PROJECT="${PROJECT_DIR}" exec "${script}" "$@"
}

# dash_fields <file> — a board item's status, prs, epic, kind, title (its first "# " heading) and who
# its step waits on, tab-separated, in one fork. The last is `held` for a held story (held_for: too), `escalated` for an escalated story
# (escalated_from: set; is_escalated's other tests are dash's), which is the lead's whatever it says,
# else `you` for a **You:** step (it starts a line, after any list marker, or a sentence: prose that
# names the convention, "has no **You:** step", is no step), else empty. The keys are read from the front matter only (a leading ---, up to the next; CRLF
# tolerated), by fm's rule: a key's first line wins, an empty value too. dash_finished's front()
# reads them the same way.
dash_fields() {
  awk '{ sub(/\r$/, "") }
    NR == 1 && $0 == "---" { n = 1; next }
    n == 1 && $0 == "---" { n = 2; next }
    n == 1 && !hs && sub(/^status: */, "") { hs = 1; s = $0; next }
    n == 1 && !hp && sub(/^prs: */, "") { hp = 1; p = $0; next }
    n == 1 && !he && sub(/^epic: */, "") { he = 1; e = $0; next }
    n == 1 && !hk && sub(/^kind: */, "") { hk = 1; k = $0; next }
    n == 1 && !hx && sub(/^escalated_from: */, "") { hx = 1; x = $0; next }
    n == 1 && !hh && sub(/^held_for: */, "") { hh = 1; h = $0; next }
    n != 1 && /(^[[:space:]]*([-*] )?|[.!?] )\*\*You:\*\*/ { y = 1 }
    n != 1 && !ht && sub(/^# /, "") { ht = 1; t = $0 }
    END { printf "%s\t%s\t%s\t%s\t%s\t%s", s, p, e, k, t, (x != "" ? (h != "" ? "held" : "escalated") : (y ? "you" : "")) }' "$1"
}

# dash_render — gather what the dashboard shows (read-only), then lay it out in python at DASH_W x
# DASH_H. herdr is asked whenever it is on PATH, inside a herdr pane or not: dash only reads. Claude
# Code's list of sessions is read once a frame (DASH_SESSIONS); with no claude, every recorded
# session is unknown.
dash_render() {
  local agents="" panes="" workspaces="" sessions="" board="" policies="" merges="" drift=0 commits="" f d r x
  if command -v herdr >/dev/null 2>&1; then
    { agents="$(herdr agent list 2>/dev/null)" && panes="$(herdr pane list 2>/dev/null)" \
      && workspaces="$(herdr workspace list 2>/dev/null)"; } || agents=""
  fi
  [[ -z "${agents}" ]] || sessions="$(claude_agents)" || sessions=""
  # One line per item: dir, slug, status, prs, its agent name, (an epic) its conductor's, epic, kind, title, you.
  for d in hld epics stories; do
    while IFS= read -r f; do
      r="$(basename "${f}" .md)"; x="$(dash_fields "${f}")"
      board+="${d}"$'\t'"${r}"$'\t'"${x%%$'\t'*}"$'\t'"$(cut -f2 <<< "${x}")"$'\t'"$(agent_name "${r}")"$'\t'"$(agent_name "conduct-${r}")"$'\t'"$(cut -f3- <<< "${x}")"$'\n'
    done < <(board "${d}")
  done
  # The last worktree commit or edit of each working builder's story (STALL_PY's story_for), for the stall rule.
  while IFS= read -r r; do
    [[ -z "${r}" ]] || commits+="${r}"$'\t'"$(story_work_time "${r}")"$'\n'
  done < <(awk -F'\t' '$1 == "stories" { print $2 "\t" $5 "\t" $3 }' <<< "${board}" \
    | SWARM_STALL_PY="${STALL_PY}" SWARM_PANES_PY="${PANES_PY}" SWARM_OWN="$(own_panes)" DASH_AGENTS="${agents}" \
      DASH_SESSIONS="${sessions}" DASH_AGENTS_LOG="${AGENTS_LOG}" python3 -c '
import json, os, sys
exec(os.environ["SWARM_STALL_PY"])
exec(os.environ["SWARM_PANES_PY"])
E = os.environ
rows = [l.rstrip("\n").split("\t") for l in sys.stdin]
own = set(E["SWARM_OWN"].split())
try:
    agents = json.loads(E["DASH_AGENTS"])["result"]["agents"]
except (ValueError, KeyError, TypeError):
    agents = []
for a in agents:
    n = a.get("name") if isinstance(a, dict) else None
    if n and a.get("pane_id") in own and agent_state(a, n, session_state(E["DASH_AGENTS_LOG"], n, E["DASH_SESSIONS"]))[0] == "working":
        print(story_for(n, rows) or "")' 2>/dev/null || true)
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
  DASH_MERGE="${CFG_merge}" DASH_LEAD="${CFG_lead}" DASH_NEXT="$(next_step | sed -n 1p)" DASH_BOARD="${board}" DASH_POLICY="${policies}" \
  DASH_WAITING="$(waiting_on_user)" DASH_MERGES="${merges}" DASH_DRIFT="${drift}" \
  DASH_AGENTS="${agents}" DASH_PANES="${panes}" DASH_WORKSPACES="${workspaces}" DASH_STATE="${STATE_DIR}" \
  SWARM_OWN="$(own_panes)" SWARM_PANES_PY="${PANES_PY}" DASH_COLS="${DASH_W:-100}" DASH_LINES="${DASH_H:-0}" \
  DASH_COLOR="${DASH_COLOR:-0}" DASH_PRSTATE="${DASH_PRSTATE:-}" DASH_COST="${DASH_COST:-}" \
  DASH_FINISHED="${DASH_FINISHED:-}" DASH_TREE="${DASH_TREE:-0}" DASH_LADDER="${DASH_LADDER:-0}" \
  DASH_COMMITS="${commits}" DASH_STALL_MIN="${CFG_stall_minutes}" SWARM_STALL_PY="${STALL_PY}" DASH_SESSIONS="${sessions}" \
  DASH_AGENTS_LOG="${AGENTS_LOG}" DASH_PROJECTS="${CLAUDE_PROJECTS}" DASH_FINDINGS="${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" DASH_EVENTS="${EVENTS_LOG}" \
  DASH_ESCALATE_AFTER="${CFG_escalate_after}" DASH_CODEX_MIN="${CFG_codex_minutes}" SWARM_REPORT_PY="${REPORT_PY}" python3 - <<'PY'
import collections, datetime, glob, itertools, json, os, re, time
E = os.environ
exec(E["SWARM_REPORT_PY"])
exec(E["SWARM_PANES_PY"])
exec(E["SWARM_STALL_PY"])
W = max(int(E.get("DASH_COLS") or 100), 40)
H = int(E.get("DASH_LINES") or 0)
# Now, and so today: DASH_NOW (epoch seconds) fixes them, so a test's "today" holds across midnight.
NOW = float(E.get("DASH_NOW") or time.time())
TODAY = datetime.date.fromtimestamp(NOW)
NARROW = W < 100   # stacked: the role and model columns and the recent actor column go
WIDE = W >= 140   # two columns: needs you and the epics on the left, recent as a log on the right
RW = W * 2 // 5 if WIDE else 0
LW = W - RW - 1 if WIDE else W
COLOR = E.get("DASH_COLOR") == "1"
KEYS = E.get("DASH_KEYS") == "1"
STYLE = {"h": "1;36", "ok": "32", "warn": "33", "bad": "1;31", "dim": "2", "b": "1", "grey": "90"}
# One status vocabulary: the symbol carries the meaning in plain text, the colour on a terminal.
SYM = {"working": ("●", "ok"), "ready": ("○", "h"), "review": ("◐", "warn"), "done": ("✓", "ok"), "failed": ("✗", "bad"),
       "blocked": ("⏸", "grey"), "look": ("!", "bad"), "unknown": ("?", "")}
# A colour per model (256-colour ANSI), the same wherever it shows: its name in that colour, and from
# 140 columns a label on that colour.
MODEL_COLOR = {"fable": 213, "opus": 208, "sonnet": 75, "haiku": 114, "codex": 250}
for m, c in MODEL_COLOR.items():
    STYLE[m], STYLE[m + "-label"] = f"38;5;{c}", f"38;5;16;48;5;{c}"

def model_style(model, label=False):
    k = next((m for m in MODEL_COLOR if m in model.lower()), None)
    return (k + "-label" if label else k) if k else "dim"

LEGEND = ["● working", "○ ready", "◐ review / CI running", "✓ done / green", "✗ failing", "⏸ blocked", "! needs you (session gone or unknown)", "? unknown"]
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

# The board: dir, slug, status, prs, agent name, conductor name, epic, kind, title, you (dash_fields').
board = [(l.split("\t") + [""] * 10)[:10] for l in lines("DASH_BOARD")]
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

# Agents: this project's panes (its tab records). A working agent shows how long since its last sign
# of life (STALL_PY's stall_age); past stall_minutes it is stalled, and needs you. A story's builder
# counts its worktree's commits and PR updates; an agent with no story (a conductor or planner)
# its own events.tsv lines: by target, and once it has a start line, by the pane that ran them.
commit_of = dict(l.split("\t", 1) for l in E.get("DASH_COMMITS", "").splitlines() if "\t" in l)
seen = last_seen(E["DASH_EVENTS"])
STARTS = ("agent", "conduct", "story")
started = {}   # target -> when its newest start (agent, conduct or story) in events.tsv ran
ran = {}       # pane -> when the newest sign of life it ran (STALL_PY's sign_time) was written
for f in read_tsv(E["DASH_EVENTS"], 5):
    t = sign_time(f)
    if t is not None and t > ran.get(f[3], 0):
        ran[f[3]] = t
    t = epoch(f[0]) if f[1] in STARTS and f[4] == "ok" else None
    if t is not None and t > started.get(f[2], 0):
        started[f[2]] = t
# Escalation: today's ok escalate builds, and each slug's newest one (its attempt and when).
ESCALATION = ("escalate", "dialog", "escalated", "reset", "reset:held", "drop")
escalations, escalated_at, was_reset = 0, {}, set()   # was_reset: slugs with an ok reset (reset_at's rule)
for f in read_tsv(E["DASH_EVENTS"], 5):
    if f[1] == "reset" and f[4].startswith("ok"):
        was_reset.add(f[2])
    t = epoch(f[0]) if f[1] == "escalate" else None
    m = re.match(r"ok \(attempt (\d+)\)", f[4])
    if t is None or not f[4].startswith("ok"):
        continue
    escalations += datetime.date.fromtimestamp(t) == TODAY
    if m and t > escalated_at.get(f[2], (0,))[0]:
        escalated_at[f[2]] = (t, m.group(1))
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
    return (story_by_slug.get(tab) or [""] * 10)[6] or None

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
            s = session_state(E["DASH_AGENTS_LOG"], name, E["DASH_SESSIONS"])
            st, look = shown_state(a, name, s, E["DASH_AGENTS_LOG"], E["DASH_PROJECTS"])
            if st in ("idle", "done") and reported(base):
                st = "reported"
            slug = story_for(name, story_rows)
            why = s[1] if s and st == "WAITING" else ""
            words = {"EMPTY": "empty pane", "WAITING": f"waiting on {why or 'a prompt'}", "done": "idle", "auth": "auth: login expired",
                     "gone": "gone: session ended", "unknown": "unknown: no session state" if s else "unknown"}.get(st, st)
            since = started.get(slug) or started.get(epic_of.get(base)) or started.get(base)
            if st == "working":
                # Any agent with a Claude session: its session log, written on every turn and tool call.
                log = session_log(E["DASH_PROJECTS"], rec[6]) if rec else ""
                try:
                    logged = os.path.getmtime(log) if log else None
                except OSError:   # removed since the glob: no sign
                    logged = None
                if slug:
                    signs = [commit_of.get(slug, ""), logged] + [(PRS.get(m.group(0)) or {}).get("updatedAt") for m in URL.finditer(story_by_slug[slug][3])]
                    age, lack = stall_age(seen, slug, base, signs, NOW), "no commit, edit, session-log write or PR update"
                else:
                    age, lack = stall_age(seen, epic_of.get(base), base, ([since, ran.get(pane)] if since else []) + [logged], NOW), "no swarm action"
                if age is not None and age >= int(E["DASH_STALL_MIN"]):
                    st, look, words = "stalled", True, f"stalled {age}m"
                    stalled.append((name, age, lack))
                elif age is not None:
                    words = f"working {age}m"
            r.update(name=name, role=rec[1] if rec else "?", model=(f"{rec[4] if rec[3] == 'claude' else rec[3]}·{rec[5]}") if rec else "?",
                     look=look, why=why, slug=slug, epic=epic_for(base, slug, label), state=st, words=words, prs=(story_by_slug.get(slug) or [""] * 4)[3],
                     open=bool(slug) and story_by_slug[slug][2] != "done",
                     since=since,
                     escalated=escalated_at.get(slug or base) if rec and rec[1] == "escalate" else None)
        except Exception as err:  # one odd agent record must not cost the whole panel
            r.update(state="unreadable", words=f"unreadable: {type(err).__name__}", prs="", open=False)
        r["sym"] = "look" if r["look"] else {"working": "working", "reported": "done", "idle": "done", "done": "done", "retired": "done"}.get(r["state"], "unknown")
        recs.append(r)

# Shown: what needs a look, works, reported, or is tied to an open story; the rest is one +N idle.
shown = [r for r in recs if r["look"] or r["state"] in ("working", "reported") or r["open"]]
idle = len(recs) - len(shown)

# Running codex reviews (codex-review's markers): one row each, under the epic of its worktree's story
# (or of its epic-<epic> worktree), never in needs you or the lead's queue. A marker whose pid is dead
# or that is older than codex_minutes plus 1 shows nothing; dash only reads, so it leaves both.
def alive(pid):
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True

for path in sorted(glob.glob(os.path.join(E["DASH_STATE"], "codex-review.*"))):
    try:
        pid = int(path.rsplit(".", 1)[1])
        t, base, cwd = open(path).read().rstrip("\n").split("\t", 2)
        age = max(int(NOW - float(t)) // 60, 0)
    except (OSError, ValueError):
        continue
    if pid <= 0 or not alive(pid) or NOW - float(t) > (int(E["DASH_CODEX_MIN"]) + 1) * 60:
        continue
    wt = os.path.basename(cwd.rstrip("/"))
    # The name column is cut at name_w, so the base goes with the age, in the words.
    shown.append({"name": f"codex review {wt}", "role": "codex", "model": "codex", "words": f"running {age}m vs {base}",
                  "state": "codex", "sym": "working", "look": False, "open": False, "prs": "",
                  "epic": epic_for("", None, re.sub(r"^epic-", "", wt))})

# Needs you: only what you act on, each as a short action. With lead = session a lead session acts
# for you, so needs you keeps your steps (a story's **You:** line, an expired login, a draft HLD) and
# the rest goes to the lead's queue (lq); with lead off, lq is needs you.
need, blocked, later, green, need_slugs = [], 0, 0, 0, set()
LEAD = E.get("DASH_LEAD") == "session"
queue = []
lq = queue if LEAD else need
bang = [sym("look")]

def story_title(slug):
    title = (story_by_slug.get(slug) or [""] * 10)[8]
    return f": {title[:1].lower()}{title[1:]}" if title and title != slug else ""

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
            lq.append(bang + [(f"merge {what}: no PR on its file", "")])
        for u in urls:
            st = pr_state(u.group(0))
            if st is None:
                lq.append(bang + [(f"merge {what}: ", ""), (u.group(0), "dim")])
                continue
            green += st[0] == "done"
            lq.append(bang + [(f"merge {pr_ref(u)} (", ""), (SYM[st[0]][0] + " " + st[1], SYM[st[0]][1]), (")  ", ""), (what, "dim")])
        continue
    m = re.match(r"(\S+): (\S+)$", l)
    if m:
        need_slugs.add(m.group(2))
        you = (story_by_slug.get(m.group(2)) or [""] * 10)[9] == "you"
        (need if you else lq).append(bang + [(f"run {m.group(1)} story {m.group(2)}{story_title(m.group(2))}", "")])
    else:
        lq.append(bang + [(l, "")])
# An escalated lead story, impossible or failed on Fable, is the lead's (next's escalated step): waiting_on_user
# leaves it out, so only the lead's queue shows it. Once reset, drop is all that is left, except for a
# held story, whose hold reset always lifts (as next says).
if LEAD:
    queue += [bang + [(f"decide escalated story {b[1]}{story_title(b[1])}: ", ""),
                      (("" if b[1] in was_reset and b[9] != "held" else f"swarm.sh reset {b[1]} or ") + f"swarm.sh drop {b[1]}", "dim")]
              for b in stories if b[2] == "ready" and b[7] == "lead" and b[9] in ("escalated", "held")]
for r in recs:
    if r["state"] == "WAITING":
        why = f" (waiting on {r['why']})" if r.get("why") else ""
        lq.append(bang + [(f"answer {r['name']}{why}: ", ""), (f"herdr agent read {r['name']}", "dim")])
    elif r["state"] == "auth":
        need.append(bang + [(f"auth: run /login ({r['name']}'s login expired), then /swarm-dev:swarm tells it to resume", "")])
    elif r["state"] == "EMPTY":
        lq.append(bang + [(f"close the empty pane {r['name']}: ", ""), ("swarm.sh tidy", "dim")])
    elif r["state"] in ("gone", "unknown") and r["look"]:
        lq.append(bang + [(f"look at {r['name']}: " + ("session ended" if r["state"] == "gone" else "no session state"), "")])
lq += [bang + [(f"look at {n}: working {age} min with {lack}", "")] for n, age, lack in stalled]
need += [bang + [(f"agree draft HLD {b[1]}: ", ""), (f"/hld {b[1]}", "dim")] for b in board if b[0] == "hld" and b[2] == "draft"]

# Epics: one row per active epic (and any other epic an agent shown works for), its progress, then
# its live agents and open PRs beneath it.
groups = collections.OrderedDict((s, []) for s, b in epics.items() if b[2] == "active")
for r in shown:
    groups.setdefault(r["epic"] if r["epic"] in epics else "", []).append(r)
name_w = min(max((len(r["name"]) for r in shown), default=0), 30 if not NARROW else max(12, (W - 20) // 2))

def agent_cols(r):
    # Role and model, then the state (a working agent's with its age); from 140 columns the model is
    # a label in its colour, and a working agent shows how long since it started.
    row = []
    if WIDE:
        label = f" {r['model']} "
        row = [(f"{r['role']:<10} ", "dim"), (label, model_style(r["model"], True)), (" " * max(16 - len(label), 1), "")]
    elif not NARROW:
        row = [(f"{r['role']:<10} ", "dim"), (f"{r['model']:<12} ", model_style(r["model"]))]
    row.append((r["words"], SYM[r["sym"]][1] if r["sym"] != "done" else "dim"))
    if WIDE and r.get("state") == "working" and r.get("since"):
        m = max(int(NOW - r["since"]) // 60, 0)
        row.append((f"  {m}m" if m < 60 else f"  {m // 60}h{m % 60:02d}m", "dim"))
    if r.get("escalated"):
        t, n = r["escalated"]
        row.append((f"  attempt {n} · {datetime.datetime.fromtimestamp(t).strftime('%H:%M')}", "fable"))
    return row

def agent_row(r):
    return [("  ", ""), sym(r["sym"]), (f"{cut(r['name'], name_w):<{name_w}}  ", "")] + agent_cols(r)

if WIDE:
    # The left column takes what its widest agent card needs from recent's, down to a third of the
    # screen, so a card's state age never cuts the escalation time after it.
    grow = min(max((sum(len(t) for t, _ in agent_row(r)) + 4 for r in shown), default=0) - LW, RW - W // 3)
    if grow > 0:
        LW, RW = LW + grow, RW - grow

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
epic_w = min(max((len(epic_label(s)) for s in groups if s), default=0), LW // 3)
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
                row = [(stem, "dim"), sym(r["sym"]), (f"{cut(r['name'], width):<{width}}  ", "")] + agent_cols(r)
                rows.append(row + [(f"  {r['prs']}" if r["prs"] else "", "dim")])
    return rows or [[("no agents open in this project's panes", "dim")]]

# Recent: swarm actions (events.tsv), merges on the base branch and fixed findings, newest first.
# Findings are one row per PR and day, and at most a third of the rows, so they never crowd out the rest.
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

events = []   # (time, actor, text, icon key)
for l in lines("DASH_MERGES"):
    f = l.split("\t", 2)
    if len(f) == 3:
        m = re.match(r"Merge pull request #(\d+) from [^/\s]+/(\S+)", f[2])
        events.append((f[0], f[1], f"merged #{m.group(1)} {m.group(2)}" if m else f[2], "merge"))
found = collections.OrderedDict()
for f in fixed_rows(E["DASH_FINDINGS"]):
    m = re.search(r"(\d+)\D*$", f[2])
    found.setdefault((f[0], m.group(1) if m else f[2]), []).append(f)
for (day, pr), fs in found.items():
    text = fs[0][3] if len(fs) == 1 else f"{len(fs)} findings: " + "; ".join(x[3] for x in fs)
    events.append((day, fs[0][1] if len(fs) == 1 else "findings", f"{text} (#{pr})", "finding"))
# A fixed finding's log-finding line is left out: its findings.tsv row above shows it. A run of ok
# declined lines on one PR, with nothing but fixed ones between, is one row at the newest's time.
run = None   # [index in events, PR, count] of the declined run still open
for f in read_tsv(E["DASH_EVENTS"], 5):
    ok = f[4].startswith("ok")
    if f[1] == "log-finding" and ok:
        continue
    pr = pr_key((f[2].split() or [""])[-1])
    if f[1] == "log-finding:declined" and ok and run and run[1] == pr:
        run[2] += 1
        events[run[0]] = (f[0], f[3], f"{run[2]} findings declined on #{pr.rsplit('#', 1)[-1]}", "action")
        continue
    run = [len(events), pr, 1] if f[1] == "log-finding:declined" and ok else None
    events.append((f[0], f[3], f"{f[1]} {f[2]}" + ("" if f[4] == "ok" else f": {f[4]}"),
                   "failed" if not ok else "start" if f[1] in STARTS else "escalation" if f[1] in ESCALATION else "action"))
ICON = {"merge": ("⇡", "ok"), "finding": ("✎", "warn"), "start": ("▶", "ok"), "action": ("·", "dim"), "failed": ("✗", "bad"),
        "escalation": ("▲", "fable")}
dated = sorted(((when(e[0]), e) for e in events if when(e[0])[0]), key=lambda x: x[0][0], reverse=True)

def stamp(raw, t):
    # The log's time column: HH:MM today, the date before; a dated finding of today is "today".
    t = t.astimezone()
    return t.strftime("%m-%d") if t.date() != TODAY else "today" if len(raw) == 10 else t.strftime("%H:%M")

def recent_box(w, n, clock=False):
    rec, findings = [], 0
    actor_w = 0 if w < 100 else 14
    tw = 5 if clock else 9
    for (t, ago), (raw, actor, text, kind) in dated:
        if len(rec) >= n:
            break
        if kind == "finding":
            findings += 1
            if findings > max(1, n // 3):
                continue
        room = max(w - 4 - tw - 2 - 2 - (actor_w + 2 if actor_w else 0), 0)
        row = [(f"{stamp(raw, t) if clock else ago:>{tw}}  ", "dim"), (ICON[kind][0] + " ", ICON[kind][1]), (cut(text, room).ljust(room), "")]
        if actor_w:
            row.append((f"  {cut(actor, actor_w):>{actor_w}}", "dim"))
        rec.append(row)
    return box("recent", rec, w)

def line_model(l):
    # A log line's model, or "" for none, a non-string, or "<synthetic>" (a failed turn's entry).
    try:
        m = (json.loads(l).get("message") or {}).get("model")
    except (ValueError, AttributeError):
        return ""
    return m if isinstance(m, str) and not m.startswith("<") else ""

def first_model(path):
    # The first real model in a session's log; reading stops there, so a --watch redraw stays
    # cheap. An unreadable log names none, as a missing one does.
    try:
        with open(path, errors="ignore") as f:
            m = next((m for m in map(line_model, f) if m), "")
    except OSError:
        return ""
    return next((k for k in MODEL_COLOR if k in m.lower()), m)

def ladder_box(w):
    # Per role: its policy model, then how many agents agents.tsv recorded and the models their
    # sessions ran on (a session with no log or no model counts but names none). The cell is the
    # longest row plus a gap, so no row runs into the next.
    ran = collections.defaultdict(lambda: [0, set()])
    for f in read_tsv(E["DASH_AGENTS_LOG"], 7):
        path = session_log(E["DASH_PROJECTS"], f[6])
        ran[f[1]][0] += 1
        ran[f[1]][1].add(first_model(path) if path else "")
    rows = []
    for p in (l.split() for l in lines("DASH_POLICY")):
        n, models = ran[p[0]]
        m = f"{p[2] if p[1] == 'claude' else p[1]} · {p[3]}"
        rows.append([(f"{p[0]:<11}→ ", ""), (m, model_style(m)), (f"  {n}", "dim")] + [(" " + x, model_style(x)) for x in sorted(models - {""})])
    cell = max((sum(len(t) for t, _ in r) for r in rows), default=0) + 2
    rows = [r + [(" " * (cell - sum(len(t) for t, _ in r)), "")] for r in rows]
    per = max(1, (w - 4) // cell)
    return box("ladder", [sum(rows[i:i + per], []) for i in range(0, len(rows), per)], w)

# Layout. Header: one line, the clock at the right; then the summary line (from 140 columns, the
# status bar at the bottom carries it, with the merge mode).
right = E.get("DASH_CLOCK") or datetime.datetime.now().strftime("%H:%M:%S")
head = [(os.path.basename(E["DASH_PROJECT"].rstrip("/")), "b"), (f"  swarm-dev {E['DASH_VERSION']}", "dim"),
        ("  merge ", "dim"), (E["DASH_MERGE"], ""), ("  next ", "dim"), (E["DASH_NEXT"], "warn")]
if WIDE:
    head = head[:2] + head[4:]
if sum(len(t) for t, _ in head) > W - len(right) - 1:
    head = head[:1] + head[4:]   # narrow: the version and merge mode go before next is cut
out.append(fit(head, W - len(right) - 1) + " " + paint(right, "dim"))
n_active = sum(b[2] == "active" for b in epics.values())
n_working = sum(r["state"] == "working" for r in recs)
summary = [(f"{n_active} epics active", ""), (" · ", "dim"), (f"{n_working} agents working", "ok" if n_working else ""), (" · ", "dim"),
           (f"{green} PRs green, waiting", "ok" if green else ""), (" · ", "dim"), (f"{len(stalled)} stalled", "bad" if stalled else "")]
if E.get("DASH_COST"):
    summary += [(" · ", "dim"), (f"${E['DASH_COST']} today", "")]
# Who is on call (the escalate role's model, off when escalate_after is 0) and today's escalations, a
# zero count too. It goes on the summary's line when it fits there, else on a line of its own.
esc = next((p for p in (l.split() for l in lines("DASH_POLICY")) if p[0] == "escalate" and len(p) > 3), None)
on_call = "off" if E.get("DASH_ESCALATE_AFTER") == "0" or not esc else f"{esc[2] if esc[1] == 'claude' else esc[1]}·{esc[3]}"
on_call = [("on call: ", "dim"), (on_call, model_style(on_call)), (" · ", "dim"),
           (f"{escalations} escalation{'' if escalations == 1 else 's'} today", "fable" if escalations else "")]
SEP = (" · ", "dim")

def pack(groups, n):
    # Groups of styled segments onto as few lines of n as they fit, never splitting a group; each
    # group carries the separator it takes after another on the same line.
    rows = [[]]
    for sep, g in groups:
        if rows[-1] and sum(len(t) for t, _ in rows[-1] + [sep] + g) > n:
            rows.append([])
        rows[-1] += ([sep] if rows[-1] else []) + g
    return [fit(r, n) for r in rows]

if not WIDE:
    out += pack([(SEP, summary), (SEP, on_call)], W)
drift = int(E.get("DASH_DRIFT") or 0)
if drift:
    out.append(fit([(f"board: {drift} uncommitted edit{'' if drift == 1 else 's'} in the main checkout (reconcile pulls first)", "warn")], W))

# The main column: needs you, the epics (or the tree), the blocked count. From 140 columns it is the
# left column, LW wide.
left = box("needs you", [l for r in need for l in wrap(r, LW - 4)], LW, "bad") if need else [fit([sym("done"), ("nothing needs you", "dim")], LW)]
if queue:
    left += box("lead's queue", [l for r in queue for l in wrap(r, LW - 4)], LW, "warn")
if E.get("DASH_TREE") == "1":
    left += box("agents by workspace and tab", tree_view(), LW)
elif epic_view:
    left += box("epics", epic_view, LW)
if blocked or later:
    left.append(fit([sym("blocked"), (f"{blocked} blocked · {later} later  (swarm.sh status --all lists them)", "dim")], LW))

# The legend, packed onto as few lines as the width allows; from 140 columns the keys go to the status bar.
KEYWORDS = "q quit · t tree · l ladder · r redraw"
legend, cur = [], ""
# With lead = session most ! rows are the lead's queue, so the legend says so.
for item in [l.replace("! needs you", "! needs you or the lead") if LEAD else l for l in LEGEND] + ([KEYWORDS] if KEYS and not WIDE else []):
    if cur and len(cur) + 3 + len(item) > W:
        legend.append(cur); cur = item
    else:
        cur = f"{cur}   {item}" if cur else item
legend.append(cur)
foot = [fit([(cut(l, W), "dim")], W) for l in legend]
if WIDE:
    foot += pack([(SEP, [("merge ", "dim"), (E["DASH_MERGE"], "b"), (" · ", "dim")] + summary), (SEP, on_call),
                  (("   ", ""), [(KEYWORDS if KEYS else KEYWORDS + " (with --watch)", "dim")])], W)

# Recent fills the height left. Under 140 columns it and a shown ladder are stacked under the main
# column; from 140 they are the right column, the ladder on top.
# A watched frame drops what does not fit, never the foot; a one-shot dash shows at least 5 rows.
ladder = E.get("DASH_LADDER") == "1"
if WIDE:
    side = ladder_box(RW) if ladder else []
    room = H - len(out) - len(foot) - len(side) - 2 if H else max(8, len(left) - len(side) - 2)
    if not KEYS:
        room = max(5, room)
    if room > 0:
        side += recent_box(RW, room, clock=True)
    out += [(a if a is not None else " " * LW) + " " + (b or "") for a, b in itertools.zip_longest(left, side)]
else:
    out += left
    if ladder:
        out += ladder_box(W)
    room = H - len(out) - 2 - len(foot) if H else 8
    if not KEYS:
        room = max(5, room)
    if room > 0:
        out += recent_box(W, room)
if KEYS and H:
    out = out[:max(H - len(foot), 0)]   # a watched frame never scrolls the screen
out += foot
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

# archive_session <name> — keep a gzip'd copy of <name>'s Claude session log (its newest agents.tsv
# line's session) as .swarm/sessions/<date>-<name>-<session>.jsonl.gz, once per session: Claude Code
# deletes session logs after cleanupPeriodDays. .swarm/ is git-ignored, so the copy stays on this
# machine, readable by its user only; nothing is redacted. An agent with no session (codex) has nothing to keep. A copy that
# fails is reported and never stops the close: the session log itself is untouched.
archive_session() {
  local name session src dir
  name="$(agent_name "$1")"
  [[ -f "${AGENTS_LOG}" ]] || return 0
  session="$(awk -F'\t' -v n="${name}" 'NF == 7 && $3 == n { s = $7 } END { print s }' "${AGENTS_LOG}" 2>/dev/null || true)"
  [[ -n "${session}" && "${session}" != - ]] || return 0
  dir="${PROJECT_DIR}/.swarm/sessions"
  compgen -G "${dir}/*-${session}.jsonl.gz" >/dev/null && return 0
  src="$(SWARM_REPORT_PY="${REPORT_PY}" python3 -c 'import os, sys; exec(os.environ["SWARM_REPORT_PY"]); print(session_log(*sys.argv[1:3]))' \
    "${CLAUDE_PROJECTS}" "${session}" 2>/dev/null || true)"
  [[ -n "${src}" ]] || return 0
  # Readable by this user only: the copy may hold secrets.
  ( umask 077 && mkdir -p "${dir}" && gzip -c "${src}" > "${dir}/.${session}.tmp" \
    && mv "${dir}/.${session}.tmp" "${dir}/$(date +%F)-${name}-${session}.jsonl.gz" ) \
    || { rm -f "${dir}/.${session}.tmp"; echo "${name}: could not archive session ${session}; its log is still at ${src}" >&2; }
}

# is_close_cause <word> — true for a cause close takes: why the builder stopped. met, stalled and
# bound are attempts; impossible, paused and cleared-on-error are not.
is_close_cause() { case "$1" in met|impossible|stalled|bound|paused|cleared-on-error) return 0 ;; esac; return 1; }
CLOSE_CAUSES="met, impossible, stalled, bound, paused or cleared-on-error"

# close_agent <name> [cause] — close what was opened for <name> (close_panes), or with keep_panes = true
# leave it open to read and only retire the agent. Either way, its session log is archived first.
# An unknown cause is refused before anything closes, and so, with goal on, is a missing one while
# <name>'s story is still ready (its builder is giving up), and so is impossible for a story that
# cannot be handed on (impossible_refused). A close that ends a failed build (failed_build, decided
# before anything closes, while the builder can still be found) then clears the attempt away
# (clear_build), so the next build starts fresh. With no cause, met, stalled or bound it first raises
# the story's attempts: by one, and when that build was escalate, the story becomes the lead's
# (escalate_story). impossible, paused and cleared-on-error count nothing. impossible makes the story
# the lead's (impossible_story) whether or not there was a build to clear; paused and cleared-on-error
# hold it for the lead (held_story) when the close ends a build, or a ready verify story's open builder.
close_agent() {
  local cause="${2:-}" f="${BOARD}/stories/$1.md" prs counted=0 n why open
  # The message never repeats the word: main logs a die's first line.
  [[ -z "${cause}" ]] || is_close_cause "${cause}" \
    || die "close: the cause must be ${CLOSE_CAUSES} (swarm.sh close <name> [cause])"
  [[ -n "${cause}" || "${CFG_goal}" == off || ! -f "${f}" || "$(fm "${f}" status)" != ready ]] \
    || die "close: with goal on, $1's story is still ready, so say why its builder stopped: swarm.sh close $1 <cause>, the cause one of ${CLOSE_CAUSES}"
  if [[ "${cause}" == impossible ]] && why="$(impossible_refused "$1")"; then
    die "close: $1 cannot be closed impossible, because ${why}; nothing was closed"
  fi
  archive_session "$1"
  if prs="$(failed_build "$1")"; then counted=1; fi
  open="$(agent_field "$(agent_name "$1")" pane_id)"
  # One builder, two names: herdr's (agent_name, cut at 32 characters), which failed_build and
  # retire_agent map to, and the pane record's full slug (start_agent's pane name), which close_panes
  # matches. Passing close_panes the cut name would leave a long slug's pane open.
  if [[ "${CFG_keep_panes}" == true ]]; then retire_agent "$1"; else close_panes "$1"; fi
  if [[ "${cause}" == impossible ]]; then
    # The build is cleared even when failed_build declined (a verify story, a builder gone, gh down),
    # so the story builds again after reset; only PRs failed_build listed are closed.
    clear_build "$1" "the build of $1 stopped (impossible), which is not an attempt" "${prs:-[]}"
    impossible_story "$1" "${prs}" "${counted}"
    return 0
  fi
  case "${cause}" in paused|cleared-on-error)
    # Held, its build cleared so it builds again once the hold is lifted, when the close ends a build
    # (counted), or closes the open builder of a ready verify story, whose close never counts. A story
    # whose PR merged or is merging, or whose PRs gh could not list, is left as it was, and for a story
    # an agent builds the close says so (not held:).
    if [[ ${counted} == 1 || ( -n "${open}" && -f "${f}" && "$(fm "${f}" kind)" == verify && "$(fm "${f}" status)" == ready ) ]]; then
      clear_build "$1" "the build of $1 stopped (${cause}), which is not an attempt" "${prs:-[]}"
      held_story "$1" "${cause}" "${prs:-[]}" "${counted}"
    elif ! impossible_refused "$1" >/dev/null; then
      echo "not held: $1 (${cause}) ended no build here (no builder open, a PR merged or merging, or gh could not list its PRs), so its story is as it was: list it for the lead and do not start it again"
    fi
    return 0 ;;
  esac
  [[ ${counted} == 1 ]] || return 0
  n="$(get_fm "${f}" attempts)"
  # Checked before the arithmetic, which would evaluate it.
  [[ "${n}" =~ ^(0|[1-9][0-9]*)?$ ]] \
    || { echo "swarm: ${f}: attempts must be a non-negative whole number, not '${n}'; this failed build is not counted or cleared" >&2; return 0; }
  n=$((${n:-0} + 1))
  set_fm "${f}" attempts "${n}"
  clear_build "$1" "attempt ${n} at $1 failed" "${prs}"
  escalate_story "$1" "${n}" "${prs}"
}

# impossible_refused <name> — print why `close <name> impossible` cannot hand <name>'s story on, and
# succeed; fail, printing nothing, when it can: a story on the board, still ready, of a kind an agent
# builds (agent_kind). Whether its build can be cleared does not matter.
impossible_refused() {
  local f="${BOARD}/stories/$1.md" st kind
  [[ "$1" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || { echo "there is no story file ${f}"; return 0; }
  st="$(fm "${f}" status)"
  [[ "${st}" == ready ]] || { echo "its story is ${st:-without a status}, not ready"; return 0; }
  kind="$(fm "${f}" kind)"
  agent_kind "${kind}" || { echo "its story is kind: ${kind}, which no agent builds"; return 0; }
  return 1
}

# ESCALATED_OPEN, ESCALATED_CLOSE: the markers around the lead's block, which escalate_story appends
# to a story and reset_story removes.
ESCALATED_OPEN="<!-- swarm.sh escalated: swarm.sh reset removes this block -->"
ESCALATED_CLOSE="<!-- /swarm.sh escalated -->"
# NO_KIND_LINE: escalated_from:'s value for a story that had no kind: line (built as code), so reset
# takes the line out again and the file is its committed text.
NO_KIND_LINE="code (default)"

# escalate_story <slug> <attempt> <prs> — after a counted close of an escalate build (the role on
# the newest agents.tsv line for the slug's agent), the story is the lead's to decide (lead_block),
# with a block naming the lead's choices. A story reset once already (reset_at) is offered only drop.
# The close of any other build changes nothing here.
escalate_story() {
  local f="${BOARD}/stories/$1.md" role from text when put k
  role="$(awk -F'\t' -v n="$(agent_name "$1")" '$3 == n { r = $2 } END { print r }' "${AGENTS_LOG}" 2>/dev/null || true)"
  [[ "${role}" == escalate ]] || return 0
  from="$(get_fm "${f}" kind)"; from="${from:-${NO_KIND_LINE}}"
  put="puts back \`kind: ${from}\`"
  [[ "${from}" != "${NO_KIND_LINE}" ]] || put="takes the \`kind:\` line out again (it had none, so it builds as code)"
  when="$(reset_at "$1")"
  text="**Escalated.** Attempt $2, built on Fable, failed, so no agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'
  if [[ -n "${when}" ]]; then
    text+="- It was reset once already (${when}), and \`swarm.sh reset\` refuses a second, so drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."
  else
    text+="- Re-scope the story, then run \`swarm.sh reset $1 <reason>\`, which ${put} while it still says \`kind: lead\` (a kind you set yourself stays), and clears \`attempts:\`. When the board is in the story's repo, a builder reads the story from the branch it starts from: merge the re-scope as a board PR first (with pr_per = epic, then merge the base into epic/<epic>), then reset and pull the board in one go. At most one reset per story: after a second failed escalate build, drop it."$'\n'
    text+="- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."
  fi
  k="$(lead_block "$1" "${text}" "$3")"
  record_event escalated "$1" "ok (attempts $2, ${k} PRs)"
  echo "escalated: $1 is kind: lead now, for the lead to reset or drop"
}

# impossible_story <slug> <prs> <listed> — after `close <slug> impossible`, the builder replied
# IMPOSSIBLE: the story's **Done when** cannot be met, so, like a failed Fable build, it is the lead's
# to decide: a lead_block with no **You:** step, naming the lead's choices, with <prs> (failed_build's
# list). Unless <listed> is 1, failed_build listed no PRs, and the block says so. attempts: stays as it was.
impossible_story() {
  local when choice none=""
  when="$(reset_at "$1")"
  choice="- Re-scope its **Done when** (the judge called it impossible from the builder's session), then run \`swarm.sh reset $1 <reason>\`, which puts its kind back so it is built again. When the board is in the story's repo, a builder reads the story from the branch it starts from: merge the re-scope as a board PR first (with pr_per = epic, then merge the base into epic/<epic>), then reset and pull the board in one go."$'\n'"- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."
  [[ -z "${when}" ]] || choice="- It was reset once already (${when}), and \`swarm.sh reset\` refuses a second, so drop it: run \`swarm.sh drop $1 <reason>\`, and put a re-scoped **Done when** in a new story if it is still wanted."
  [[ "$3" == 1 ]] || none="swarm.sh did not list the PRs on story/$1, so look at them before you reset it: \`gh pr list --head story/$1 --state all\` in its repo."
  lead_block "$1" "**Impossible.** The builder replied \`IMPOSSIBLE:\`, and this build was not counted as an attempt. No agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'"${choice}" "$2" "${none}" >/dev/null
  echo "impossible: $1 is kind: lead now, for the lead to re-scope or drop"
}

# held_story <slug> <cause> <prs> <listed> — after `close <slug> paused` or `close <slug> cleared-on-error`
# ends a build, or closes a ready verify story's open builder, the story is held for the lead: a lead_block with no **You:** step and held_for: <cause>, so
# no conductor or /swarm-dev:swarm run builds it again. attempts: stays as it was. Lifting the hold with reset
# is not the story's one reset (main logs it as reset:held, which reset_at does not read).
held_story() {
  local why="it paused on its goal" none=""
  # Unless <listed> is 1, failed_build listed no PRs: the story is verify, which has none.
  [[ "$4" == 1 ]] || none="A verify story has no PRs."
  [[ "$2" != cleared-on-error ]] || why="its goal was cleared on an error"
  lead_block "$1" "**Held ($2).** The builder stopped because ${why}, and this build was not counted as an attempt. No agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'"- Lift the hold: run \`swarm.sh reset $1 <reason>\`, which puts its kind back and leaves \`attempts:\` as it is, so it is built again. Lifting a hold is not the story's one reset, and a later pause or error holds it again."$'\n'"- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR." "$3" "${none}" >/dev/null
  set_fm "${BOARD}/stories/$1.md" held_for "$2"
  echo "held: $1 is kind: lead now (${2}), for the lead to lift the hold with reset, or drop"
}

# lead_block <slug> <text> <prs> [none] — no agent builds the story now: kind: lead, escalated_from: its
# kind (NO_KIND_LINE when it has no kind: line), still ready, and a marked block at its end with <text>
# and every PR in <prs> (failed_build's gh list; empty with pr_per = epic), or [none] when <prs> has
# none (by default, that no PR was found). Prints how many PRs it named.
lead_block() {
  local f="${BOARD}/stories/$1.md" from urls k=0
  from="$(get_fm "${f}" kind)"
  urls="$(json "'\n'.join('- ' + p['url'] for p in d)" <<< "${3:-[]}")"
  [[ -z "${urls}" ]] || k="$(grep -c . <<< "${urls}")"
  set_fm "${f}" kind lead
  set_fm "${f}" escalated_from "${from:-${NO_KIND_LINE}}"
  [[ -z "$(tail -c1 "${f}")" ]] || echo >> "${f}"
  { echo "${ESCALATED_OPEN}"
    echo
    printf '%s\n' "$2"
    echo
    if [[ -n "${urls}" ]]; then printf "The attempts' PRs:\n\n%s\n" "${urls}"; else echo "${4:-No PR was found on story/$1.}"; fi
    echo "${ESCALATED_CLOSE}"; } >> "${f}"
  echo "${k}"
}

# failed_build <name> — succeed when closing <name> ends a failed build, and print gh's list of the
# PRs on story/<name> (nothing with pr_per = epic, whose epic stories have none): <name> is a story
# on the board, still ready, of kind code, docs or chore, whose builder this project has open in herdr
# under that name (not closed by hand, not already retired), and none of its PRs merged or is open with
# auto-merge set: with merge = agent a close that comes before the board is pulled, or while the merge
# waits on auto-merge, finds the story still ready, so only the PR tells. One gh call answers both;
# when it fails, nothing is counted or cleared, and stderr says so.
failed_build() {
  local slug="$1" f="${BOARD}/stories/$1.md" src url prs merging
  [[ "${slug}" =~ ^[a-z0-9-]+$ && -f "${f}" && "$(fm "${f}" status)" == ready ]] || return 1
  # A verify story has no PR, so nothing here tells its pass from a failure: its close never counts.
  case "$(fm "${f}" kind)" in ""|code|docs|chore) ;; *) return 1 ;; esac
  [[ -n "$(agent_field "$(agent_name "${slug}")" pane_id)" ]] || return 1
  # The conductor finishes an epic's story before closing it, so a ready one never merged.
  [[ "${CFG_pr_per}" == epic && -n "$(fm "${f}" epic)" ]] && return 0
  src="$(repo_dir "$(fm "${f}" repo)")" \
    || { echo "swarm: ${slug}: ${src}, so this close counts no failed build and clears nothing" >&2; return 1; }
  if ! url="$(git -C "${src}" remote get-url origin)" \
     || ! prs="$(gh pr list -R "${url}" --head "story/${slug}" --state all --json number,state,url,autoMergeRequest)" \
     || ! merging="$(json "any(p['state'] == 'MERGED' or (p['state'] == 'OPEN' and p.get('autoMergeRequest')) for p in d)" <<< "${prs}")"; then
    echo "swarm: ${slug}: could not list the PRs on story/${slug}, so this close counts no failed build and clears nothing" >&2
    return 1
  fi
  [[ "${merging}" == False ]] || return 1
  printf '%s\n' "${prs}"
}

# clear_build <slug> <why> <prs> — clear a build away (a failed one, or one reconcile found merged or
# closed), so the next one starts fresh: in
# the story's repo, its worktree and story/<slug>; each of <prs> (failed_build's gh list) still open,
# closed unmerged with a comment saying <why> (the attempt, or the cause); then story/<slug> on origin. A step that fails
# is said on stderr, and the rest still run.
clear_build() {
  local slug="$1" b="story/$1" src wt url
  src="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo)")" || { echo "swarm: ${slug}: ${src}; nothing cleared" >&2; return 0; }
  wt="$(worktree_for "${src}" "${slug}")"
  if [[ -e "${wt}" ]]; then git -C "${src}" worktree remove --force "${wt}" || echo "swarm: ${slug}: could not remove ${wt}" >&2; fi
  # A worktree whose directory went by hand is still registered, and would keep the branch.
  git -C "${src}" worktree prune || echo "swarm: ${slug}: could not prune ${src}'s worktrees" >&2
  if git -C "${src}" show-ref -q --verify "refs/heads/${b}"; then
    git -C "${src}" branch -q -D "${b}" || echo "swarm: ${slug}: could not delete ${b} in ${src}" >&2
  fi
  while IFS= read -r url; do
    [[ -n "${url}" ]] || continue
    gh pr close "${url}" --comment "swarm.sh close: $2, so this PR is closed unmerged and the next build starts fresh." >/dev/null \
      || echo "swarm: ${slug}: gh could not close ${url}" >&2
  done < <(json "'\n'.join(p['url'] for p in d if p['state'] == 'OPEN')" <<< "${3:-[]}")
  if git -C "${src}" ls-remote --exit-code origin "refs/heads/${b}" >/dev/null 2>&1; then
    git -C "${src}" push -q origin --delete "${b}" || echo "swarm: ${slug}: could not delete ${b} on origin" >&2
  fi
}

# close_panes <name> — close <name>'s pane, or its tab when that was the tab's last pane. A
# conductor's name closes its epic's tabs, with any story panes left in them.
close_panes() {
  local state pane epic
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
# `lead`) failed and left an empty pane. herdr's holder decides first: with none, the name is free,
# whatever an old session says. A holder this project started is retired only when it has finished
# (read_state: idle, its session gone, or herdr's idle or done) and refused in any other state,
# naming it, so a live agent is never renamed. Names are unique across every herdr workspace, so a holder in another project is
# refused, never retired: it is that project's agent. Runs before any pane opens.
free_agent_name() {
  local state
  if [[ -z "$(agent_field "$1" pane_id)" ]]; then
    [[ -z "$(agent_field "$1" agent_status any)" ]] && return 0
    die "$1: an agent this project did not start (no tab record in .swarm/state) holds this name (herdr agent list); it is never retired from here. Wait for it to finish, or close its pane"
  fi
  state="$(read_state "$1")"
  case "${state}" in
    idle|gone|herdr:idle|herdr:done) ;;   # finished: the only states retired
    busy|herdr:working) die "$1: an agent with this name is still working; wait for it, or use another name" ;;
    waiting*|herdr:blocked) die "$1: an agent with this name is waiting on $(waiting_for "${state}"); answer it (herdr agent read $1), or use another name" ;;
    unknown) die "$1: Claude Code gives no state for the session holding this name (unknown); look at it (herdr agent read $1), or use another name" ;;
    herdr:unknown) die "$1: herdr gives no state for the agent holding this name (unknown); look at it (herdr agent read $1), or use another name" ;;
    *) die "$1: the agent holding this name is '${state#herdr:}', not finished, so it is not retired; look at it (herdr agent read $1), or use another name" ;;
  esac
  retire_agent "$1" >/dev/null
  [[ -z "$(agent_field "$1" pane_id)" ]] || die "$1: the name is still taken after retiring it; close its pane (herdr agent list), or use another name"
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

# init_check — refuse init anywhere but the project's git root. main runs it before logging, since a
# project found from a subdirectory is that subdirectory, and a refused run must write nothing there.
init_check() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "init: not in a git repo; run it from your project's root"
  [[ "$(pwd -P)" == "${top}" ]] || die "init: run it from the root of the git repo, ${top}"
  [[ "${PROJECT_DIR}" == "${top}" ]] || die "init: the project is ${PROJECT_DIR}; run init there"
}

# init_project — set the project up from the installed plugin, from its git root: the board templates
# (never over a file that exists), .claude/swarm/, and the .gitignore lines. A second run changes nothing.
init_project() {
  local rel f line n=0
  mkdir -p "${BOARD}" && BOARD="$(cd "${BOARD}" && pwd -P)"
  # The board's path from the root with a trailing /, or empty when the board is the root.
  rel=""; [[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel="${BOARD#"${PROJECT_DIR}/"}/"
  while IFS= read -r f; do
    if [[ -e "${BOARD}/${f}" ]]; then echo "left   ${rel}${f} (it exists)"; continue; fi
    mkdir -p "$(dirname "${BOARD}/${f}")" && cp "${SWARM_HOME}/templates/docs/${f}" "${BOARD}/${f}"
    echo "copied ${rel}${f}"; n=$((n + 1))
  done < <(cd "${SWARM_HOME}/templates/docs" && find . -type f | sed 's|^\./||' | sort)
  [[ ${n} -gt 0 ]] || echo "copied nothing: the board has every template file"
  [[ -d .claude/swarm ]] || { mkdir -p .claude/swarm; echo "created .claude/swarm/"; }
  n=0
  for line in .swarm/ "${rel}.obsidian/*" "!${rel}.obsidian/app.json"; do
    # A board outside the repo is not the repo's to ignore.
    [[ "${line}" == .swarm/ || "${BOARD}/" == "${PROJECT_DIR}/"* ]] || continue
    # CRs stripped, so a CRLF file's lines still match.
    tr -d '\r' 2>/dev/null < .gitignore | grep -qxF -- "${line}" && continue
    [[ ! -s .gitignore || -z "$(tail -c1 .gitignore)" ]] || echo >> .gitignore
    echo "${line}" >> .gitignore; echo "added ${line} to .gitignore"; n=$((n + 1))
  done
  [[ ${n} -gt 0 ]] || echo ".gitignore already has every line"
  echo "One step left: run claude once in ${PROJECT_DIR} and accept the folder trust prompt. Agents won't start until it is trusted."
}

# close_tabs <label> — close every tab this script opened under <label>, and its state, archiving the
# session of each agent in it first. A tab may be in another workspace (a conductor's is its HLD's):
# its first pane id, "<workspace>:<pane>", says which.
close_tabs() {
  local label state tab_label id ws n
  label="$(tab_label "$1")"
  for state in "${STATE_DIR}/${label}" "${STATE_DIR}/${label}"-*; do
    [[ -f "${state}" ]] || continue
    while read -r _ n; do [[ -z "${n}" ]] || archive_session "${n}"; done < "${state}"
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
    close)  require_herdr; close_agent "${1:?name}" "${2:-}" ;;
    tell)   require_herdr; tell_agent "${1:?slug}" "${2:-}" "${3:-}" ;;
    unblock) unblock ;;
    next)   next_step ;;
    status) status_report "${1:-}" ;;
    dash)   dash "$@" ;;
    tidy)   require_herdr; tidy_panes "${1:-}" ;;
    cost)   cost_report "$@" ;;
    outcomes) outcomes_report "$@" ;;
    decisions) decisions_report "$@" ;;
    log-finding) o=fixed; if [[ "${1:-}" == --declined ]]; then o=declined; shift; fi
            record_finding "${1:-}" "${2:-}" "${*:3}" "${o}" ;;
    lessons) lessons_report "${1:-}" ;;
    watch)  watch_prs "$@" ;;
    finish) finish_item "${1:?slug}" ;;
    reset)  reset_story "${1:-}" "${*:2}" ;;
    drop)   drop_story "${1:-}" "${*:2}" ;;
    dialog) dialog_answered "${1:-}" "${2:-}" ;;
    review) mark_review "$@" ;;
    reconcile) reconcile ;;
    findings) findings "${1:?repo}" "${2:?pr}" ;;
    config) show_config "${1:-}" ;;
    init)   init_project ;;
    base)   src="$(repo_dir "${1:-}")" || die "${src}"; base_for "${src}" ;;
    codex-review) codex_review "${1:-}" ;;
    _base)  base_for "${1:?repo dir}" ;;                          # test hook: the base branch for a repo
    _role)  role="$(story_role "${1:?slug}")" || die "${role}"; echo "${role}" ;;   # test hook: the role a story is built as
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
# The one line a read-only command writes is wait's `nudge <name>`, one per nudge it sends.
# Every other command is logged (fail closed: a new command is logged until it is named here), and so
# is tidy --yes; tidy alone only lists. A command that is not one (a typo, --help) is not logged.
READ_ONLY_COMMANDS="dash status next config policy cost outcomes decisions lessons findings wait watch base _base _role _name _target _label _trusted _pane"

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

CODEX_GRACE=3   # seconds a TERMed codex has to exit before what is left of it is KILLed

# tree_pids <pid> — a process and everything under it, children first.
tree_pids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do tree_pids "${c}"; done; echo "$1"; }

# stop_codex <pid> — TERM codex and everything under it, give it CODEX_GRACE seconds, then KILL each
# process left and whatever is under it by then (a TERM trap can start more). The tree is read before
# the TERM, since a child whose parent dies leaves it. Stderr is off, so bash prints no "Terminated"
# line for the job.
stop_codex() {
  local pids p left
  pids="$(tree_pids "$1")"
  # shellcheck disable=SC2046,SC2086 # one pid per word
  {
    kill -TERM ${pids}
    for ((left = CODEX_GRACE; left > 0; left--)); do kill -0 ${pids} || break; sleep 1; done
    for p in ${pids}; do kill -KILL $(tree_pids "${p}"); done
    wait "$1"
  } 2>/dev/null || true
}

# codex_review <base> — codex's review of the cwd against origin/<base>: no prompt (codex refuses one
# beside --base) and stdin from /dev/null, so it never waits on input. codex stays in the caller's
# process group, so a harness that kills that group kills codex too. stop_codex stops it after
# codex_minutes (SWARM_CODEX_SECONDS overrides it, for tests), or when this command is sent TERM or
# HUP, which main_signal sends it on an interrupt and then waits out. The timeout dies, so
# events.tsv's line says so; otherwise it exits as codex did, a usage limit too.
codex_review() {
  local pid left rc=0 m
  [[ -n "$1" ]] || die "usage: swarm.sh codex-review <base>"
  left="${SWARM_CODEX_SECONDS:-$((CFG_codex_minutes * 60))}"
  # The marker dash shows the run by: main's pid (alive for the whole run; bash 3.2 has no BASHPID),
  # holding start epoch, base and cwd, removed on any exit but a KILL. A dead pid's marker goes here.
  mkdir -p "${STATE_DIR}"
  for m in "${STATE_DIR}"/codex-review.*; do
    # Only a pid suffix: retire rewrites every state file through <file>.tmp.
    [[ -f "${m}" && "${m##*.}" =~ ^[0-9]+$ ]] || continue
    kill -0 "${m##*.}" 2>/dev/null || rm -f "${m}"
  done
  m="${STATE_DIR}/codex-review.$$"
  printf '%s\t%s\t%s\n' "$(date +%s)" "$1" "${PWD}" > "${m}"
  # shellcheck disable=SC2064 # this run's marker, fixed now
  trap "rm -f $(printf %q "${m}")" EXIT
  codex exec review --base "origin/$1" < /dev/null &
  pid=$!
  # shellcheck disable=SC2064 # this codex's pid, fixed now
  trap "stop_codex ${pid}; exit 143" TERM HUP
  while ((left-- > 0)) && kill -0 "${pid}" 2>/dev/null; do sleep 1; done
  if ! kill -0 "${pid}" 2>/dev/null; then
    wait "${pid}" || rc=$?
    return "${rc}"
  fi
  stop_codex "${pid}"
  die "codex skipped: timed out after ${CFG_codex_minutes} min"
}

# main_signal <INT|TERM|HUP> — stop the logged command at once (it runs in the background, so this
# trap runs as soon as the signal lands; codex-review is waited for while it stops codex), log it as
# interrupted, remove the temp file, and die of the same signal, so the exit status stays 128+N.
# shellcheck disable=SC2317,SC2329 # invoked by the signal traps
main_signal() {
  if [[ -n "${EV_CHILD:-}" && "${EV_CMD}" == codex-review ]]; then
    # It stops codex itself (stop_codex, from its tree as it stands), so it alone gets the TERM, and
    # swarm.sh exits only once codex is gone.
    kill -TERM "${EV_CHILD}" 2>/dev/null || true; wait "${EV_CHILD}" || true
  elif [[ -n "${EV_CHILD:-}" ]]; then kill_tree "${EV_CHILD}"; fi
  record_event "${EV_CMD}" "${EV_TARGET#+}" interrupted
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  trap - "$1"
  kill -"$1" "$$"
}

# main <command> [args] — dispatch, and log each command that is not read-only to EVENTS_LOG with its
# outcome: ok, interrupted, the first line of a die at the command's own level, or failed (exit N).
# A die inside a nested $(...) gives only failed (exit N): a caller may have tolerated it, so its
# message could name the wrong failure; it was printed to stderr all the same. reconcile and unblock
# log one line per item themselves. A tell's command is tell:<kind>, and a close's close:<cause>, so
# the target stays the slug. A reset or drop that succeeds logs ok (<reason>); a reset that lifts a
# hold (held_for:) logs as reset:held.
main() {
  local rc why
  [[ "${1:-}" != init ]] || init_check
  EV_CMD="${1:-}"; EV_TARGET=""; EV_OK=""; EV_ERR=/dev/null; EV_CHILD=""
  if [[ -z "${EV_CMD}" || " ${READ_ONLY_COMMANDS} " == *" ${EV_CMD} "* || ( "${EV_CMD}" == tidy && "${2:-}" != --yes ) ]] \
     || ! is_command "${EV_CMD}"; then
    dispatch "$@"; return
  fi
  case "${EV_CMD}" in
    agent) [[ -z "${3:-}" ]] || EV_TARGET="$(agent_name "$3")" ;;
    # A decline is logged as log-finding:declined, so its target stays <kind> <pr>, as for a fix.
    log-finding) EV_TARGET="${2:-} ${3:-}"
                 if [[ "${2:-}" == --declined ]]; then EV_CMD="log-finding:declined"; EV_TARGET="${3:-} ${4:-}"; fi
                 EV_TARGET="${EV_TARGET# }"; EV_TARGET="${EV_TARGET% }" ;;
    reconcile|unblock) EV_TARGET=+ ;;
    tidy) EV_TARGET=- ;;
    # The slug, which the stall rule reads; the kind goes with the command, and only a real one (the
    # old form, tell <slug> <file>, would put a path there).
    tell) EV_TARGET="${2:-}"; if is_tell_kind "${3:-}"; then EV_CMD="tell:$3"; fi ;;
    # Likewise a close's cause, and only a real one.
    close) EV_TARGET="${2:-}"; if is_close_cause "${3:-}"; then EV_CMD="close:$3"; fi ;;
    reset|drop) EV_TARGET="${2:-}"; EV_OK="ok (${*:3})"
                # Lifting a hold is not the story's one reset, so reset_at must not read it.
                if [[ "${EV_CMD}" == reset && "${2:-}" =~ ^[a-z0-9-]+$ && -f "${BOARD}/stories/$2.md" \
                      && -n "$(get_fm "${BOARD}/stories/$2.md" held_for)" ]]; then EV_CMD="reset:held"; fi ;;
    dialog) EV_TARGET="${2:-}"; EV_OK="ok (${3:-})" ;;
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
    record_event "${EV_CMD}" "${EV_TARGET}" "${EV_OK}"
  fi
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  return "${rc}"
}

main "$@"; exit
