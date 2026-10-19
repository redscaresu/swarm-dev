#!/usr/bin/env bash
# swarm.sh — run agents in herdr panes so every one can be watched.
#
#   swarm.sh agent <tab> <name> <cwd> <role> <prompt-file>   start one agent in its own pane
#   swarm.sh story [--strict] <slug>                        build one <board>/stories/<slug>.md; warn when another epic's open story touches the same function or file, and with --strict refuse
#   swarm.sh conduct <epic>|--backlog                       a fresh conductor for one epic, in a workspace named for its HLD; --backlog: for the ready stories with no epic, in a workspace named backlog
#   swarm.sh wait [--stall] <name> [timeout-ms]             block until the agent settles (a review agent: until its findings file exists too); --stall: also exit 3 when a builder stalls
#   swarm.sh wait --until-report conduct-<epic>             block, with no timeout, until the conductor reports, waits on a prompt, is gone or needs a login
#   swarm.sh wait --lead [timeout-ms]                       block until the lead's queue gains a held or escalated story or a green PR in review that waits on the user (merge = human, or merge holds it); print each new one
#   swarm.sh policy <role>                                  print the model and effort for a role
#   swarm.sh close <name> [cause]                           close a story's pane, a conductor's epic tab, or a tab and its overflow; closing a ready story's builder counts a failed build (attempts:) and clears its worktree, branch and PR; cause: met, impossible, stalled, bound, paused or cleared-on-error (the last three count nothing; impossible makes the story the lead's, and paused and cleared-on-error hold it for the lead), required with goal on while the story is ready
#   swarm.sh tell <slug> <kind> <file>                      send an idle builder (or any agent) a file's contents; kind: findings, nudge or resume; or note: append it to a conductor's inbox, busy or not
#   swarm.sh cost | features | review-yield                 moved: each prints which flow section holds its numbers (cost, features, reviewers)
#   swarm.sh outcomes [--since YYYY-MM-DD]                  one TSV row per builder: story, kind, model, cost, tells, findings, PR, attempt, minutes start → PR → merge, main merges
#   swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]  one section per bin/lib/flow_*.py: cost (tokens and estimated cost per role), features (each docs/features.tsv feature's uses, metric, baseline, and delete? when unused or unmeasured), reviewers (findings raised, fixed and declined per reviewer and kind, and review rounds per PR), throughput (per epic: builders at once, stories per chain, review wait, stacked starts)
#   swarm.sh log-finding [--declined <reason> | --filed] [--reviewer <who>] <kind> <pr-url> <text>  log one review finding that was fixed (or, --declined, declined for <reason>: out-of-scope, nit or wrong; or, --filed, a declined out-of-scope one filed as a story, so next stops offering it), by its kind and the reviewer that raised it: codex, fallback, code-review, ci, conductor, lead, skeptic, critic, or escaped for a defect found after its PR merged (the outer loop)
#   swarm.sh lessons [--all]                                kinds recurring in 3+ PRs (or tagged lead memories) with no rule in lessons_file yet, and a long brief
#   swarm.sh next                                           the chain's next step, read from the board (resumable)
#   swarm.sh status [--all]                                 agents that need a look, stacked builds whose parent moved or merged, what waits on you, and the next step
#   swarm.sh dash [--watch [seconds]] [--ladder] [--tree] [--project <dir>]...  a read-only dashboard: what needs you, epics with their agents and PRs, recent events; --watch redraws in place, q quits, t tree, l ladder; each --project draws that project's frame, one after another
#   swarm.sh tidy [--yes]                                   list, and with --yes close, empty panes and retired agents' panes
#   swarm.sh unblock                                        mark ready every blocked story whose depends_on are all finished, or, while it has no worktree or story/<slug> branch, finished or stories in its repo with open PRs: it starts stacked on those (with a build already there it prints not stacked:); a child review held (held_by:) only once they all finish, to merge the base in and be reviewed again
#   swarm.sh finish <slug>                                  take a merged story or epic off the board (delete its file)
#   swarm.sh reset <slug> <reason>                          put an escalated story back as it was: its kind, no attempts:, no lead's block; for a held story (held_for:), lift the hold and keep attempts:
#   swarm.sh drop <slug> <reason>                           take an escalated story off the board; the lead commits that in a board PR
#   swarm.sh dialog <slug> <accepted|dismissed>             log how a builder's Fable usage-credits consent dialog was answered
#   swarm.sh plan-unasked [--declined] <epic>               record that a later epic next offered has had its unasked plan; --declined: that the user declined it, so next offers it no more
#   swarm.sh review <slug> <pr-url>...                      a story or epic whose PRs are green and reviewed now waits on a human merge
#   swarm.sh reconcile                                      finish each review item whose PRs all merged; a closed one goes back to ready
#   swarm.sh merge [--board|--release] [--head <sha>] <pr-url>  merge a green PR in review with its head pinned, wait for CI on the merge commit, then reconcile; with merge = agent, by any route, held for the user when a story listing it, or one it stacks on, has costs: money (or any value but none); --board: a board-only PR; --release: a PR into the project's base that changes only the version in .claude-plugin/plugin.json, no reconcile
#   swarm.sh wait-pr [--timeout <seconds>] <pr-url>        wait for a PR's checks on its head: print the head SHA and each check; exit 0 green, 1 red, 2 on a gh error (a transient one is retried 3 times), no check runs within 5 minutes, or still pending after <seconds> (default 1800)
#   swarm.sh board-pr start <name>                          a worktree <repo>-wt/_board-<name> on a new board/<name> from origin/<base>, for a board edit; prints its path
#   swarm.sh board-pr open <name> "<title>" <body-file>     commit (only board files may change), push and open the board PR; prints its URL
#   swarm.sh board-pr done <name>                           remove board/<name> on origin and here, and the worktree, once its PR merged or closed (or with no PR, nothing past the base)
#   swarm.sh findings <repo> <pr>                           every check-run note on a PR's head, its open code-scanning alerts, and each new test with no FAIL line in its body
#   swarm.sh watch [repo...]                                wait until a story PR needs the lead, print why, and exit
#   swarm.sh config [key]                                   the project's settings and where each came from, or one value
#   swarm.sh init                                           from a git repo's root: add the board, .claude/swarm/ and the .gitignore lines
#   swarm.sh base <repo>                                    the base branch a repo's stories start from and its PRs go into
#   swarm.sh codex-review <base>                            codex's review of this directory against origin/<base>, stopped after codex_minutes; with SWARM_STORY=<slug>, against that story's touches and Done when
#   swarm.sh review-agent <slug> <pr-url>                   start review-<slug>, a read-only agent in the story's worktree that reviews its PR against the story's touches and Done when, writes .swarm/reviews/<slug>.md, and returns at once
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

# wait-pr's exit 1 means a check is red (WAIT_PR_RED), so anything else that stops it, a die (a bad
# config line) or a set -e stop, exits 2; its temp file (WAIT_PR_TMP) goes either way.
WAIT_PR_RED=""; WAIT_PR_TMP=""
if [[ "${1:-}" == wait-pr ]]; then
  trap 'rc=$?; rm -f "${WAIT_PR_TMP}"; [[ ${rc} -eq 0 || -n "${WAIT_PR_RED}" ]] || exit 2' EXIT
fi

# SWARM_SLEEP_SCALE multiplies the fixed sleeps (nap; default 1, make test sets 0.01). It is checked
# here, before anything runs: a bad one found at its first sleep would stop a command halfway, after a
# merge, a started agent or a started codex. At least 0.001, so the shortest of them (1 s) still
# sleeps a millisecond: 0, or a scale that rounds to it, would make a poll loop a busy one.
awk -v k="${SWARM_SLEEP_SCALE:-1}" 'BEGIN { exit !(k ~ /^[0-9]*\.?[0-9]+$/ && k + 0 >= 0.001) }' \
  || die "SWARM_SLEEP_SCALE: '${SWARM_SLEEP_SCALE}' is not a number of at least 0.001"

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

# dash --project draws only the projects it names, so it runs anywhere: with no project here, the
# cwd stands in (no config there, so every setting keeps its default). Without SWARM_PROJECT the
# lookup's only failure is "not in a swarm project"; a bad SWARM_PROJECT still stops it.
if [[ "${1:-}" == dash && " $* " == *" --project "* && -z "${SWARM_PROJECT:-}" ]]; then
  PROJECT_DIR="$(find_project 2>/dev/null)" || PROJECT_DIR="$(pwd -P)"
else
  PROJECT_DIR="$(find_project)"
fi
CONFIG_FILE="${PROJECT_DIR}/.claude/swarm/config"

# Settings, with their defaults. CFG_<key> is the value, SRC_<key> where it came from.
CFG_board_dir=docs
CFG_repos_dir=""        # empty: the project dir's parent
CFG_merge=human         # human: no agent merges; a PR that is ready waits on the board for you
CFG_lessons_file=.claude/swarm/brief.md  # where adopted lesson rules live, e.g. AGENTS.md, which every agent already loads
CFG_stall_minutes=30    # an agent working this long with no sign of life (a builder: commit, PR update or swarm action) is stalled?
CFG_sonnet_share=0      # N > 0: 1 in N code stories with easy: true and without risk: high is built on Sonnet (code-sonnet), to compare
CFG_escalate_after=2   # N > 0: a story whose attempts: reaches N is built as escalate (Fable); 0 is off
CFG_builder_subagent_model=""  # empty: building roles' subagents keep Claude Code's choice; else forced to this model
CFG_goal=off            # N > 0: each builder gets a goal condition (.swarm/briefs/<slug>.goal.md) bounded at N turns
CFG_codex_minutes=10    # codex-review stops a codex review that runs this long
CFG_fallback_reviewer="" # empty: a codex usage limit skips codex's review; else a review agent on this model reviews in its place
CFG_lead=off            # session: a lead session acts for the user, so dash splits needs you into the user's steps and a lead's queue
CFG_merge_admin=off     # on: swarm.sh merge passes --admin to gh pr merge, once its own checks pass (a ruleset that wants an approving review)
CONFIG_KEYS="board_dir repos_dir merge lessons_file stall_minutes sonnet_share escalate_after builder_subagent_model goal codex_minutes fallback_reviewer lead merge_admin"
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
      merge)
        [[ "${value}" == human || "${value}" == agent ]] || die "${where}: merge must be human or agent, not '${value}'" ;;
      stall_minutes|codex_minutes)
        [[ "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: ${key} must be a positive whole number, not '${value}'" ;;
      sonnet_share|escalate_after)
        [[ "${value}" =~ ^(0|[1-9][0-9]*)$ ]] || die "${where}: ${key} must be a non-negative whole number, not '${value}'" ;;
      builder_subagent_model|fallback_reviewer)
        [[ "${value}" =~ ^[A-Za-z0-9._-]*(\[1m\])?$ ]] || die "${where}: ${key} must be a model name such as haiku, not '${value}'" ;;
      goal)
        [[ "${value}" == off || "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: goal must be off or a positive whole number of turns, not '${value}'" ;;
      lead)
        [[ "${value}" == off || "${value}" == session ]] || die "${where}: lead must be off or session, not '${value}'" ;;
      merge_admin)
        [[ "${value}" == off || "${value}" == on ]] || die "${where}: merge_admin must be off or on, not '${value}'" ;;
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

# base_for <repo-dir> — the branch a story starts from and merges into, fetched: origin's default
# branch, asked of origin itself, not the clone's cached refs, which a changed default would get
# wrong. Never a guess.
base_for() {
  local src="$1" b head
  if ! git -C "${src}" remote set-head origin --auto >/dev/null 2>&1 \
     || ! head="$(git -C "${src}" symbolic-ref -q --short refs/remotes/origin/HEAD)"; then
    die "${src}: cannot tell origin's default branch"
  fi
  b="${head#origin/}"
  git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" || die "${src}: cannot fetch ${b}"
  echo "${b}"
}

# The model and effort for each role. This is the one place the policy lives
# (docs/reference.md § Model and effort explains the reasoning). ROLE_GROUPS lists every role policy
# knows, by group: the usage message and `dash` read it.
ROLE_GROUPS="design:epic,epic-review planning:survey,lead,skeptic,critic,codex building:code,code-risky,code-sonnet,docs,chore,escalate conducting:conduct,review,review-fallback"
roles() { local g r=""; for g in ${ROLE_GROUPS}; do r+=" ${g#*:}"; done; r="${r//,/ }"; echo "${r# }"; }
# BUILDER_ROLES: the building group, the roles that build a story (outcomes, builder_subagent_model),
# plus LEGACY_BUILDER_ROLES: roles nothing starts now, kept so agents.tsv's past builds still count.
# They are in neither policy nor the ladder.
LEGACY_BUILDER_ROLES="verify"
BUILDER_ROLES="${ROLE_GROUPS#*building:}"; BUILDER_ROLES="${BUILDER_ROLES%% *}"; BUILDER_ROLES="${BUILDER_ROLES//,/ } ${LEGACY_BUILDER_ROLES}"
policy() {
  case "$1" in
    epic)       echo "claude fable high" ;;    # co-writes a draft epic with the user, who waits on every turn
    epic-review) echo "claude fable xhigh" ;;  # attacks the finished draft before it is agreed
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
    escalate)   echo "claude fable xhigh" ;;   # only after a story failed twice, or an unreconcilable epic
    conduct)    echo "claude opus high" ;;     # dispatches, reviews, merges one epic; a fresh session each time
    review)     echo "claude opus high" ;;     # one story's PR review, the model the conductor reviewed with
    review-fallback) echo "claude ${CFG_fallback_reviewer:-sonnet} high" ;;  # codex's review when codex hit its usage limit; started only with fallback_reviewer set
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

# shellcheck source=bin/lib/agents.sh
source "${SWARM_HOME}/bin/lib/agents.sh"
# shellcheck source=bin/lib/reports.sh
source "${SWARM_HOME}/bin/lib/reports.sh"
# shellcheck source=bin/lib/build.sh
source "${SWARM_HOME}/bin/lib/build.sh"
# shellcheck source=bin/lib/board.sh
source "${SWARM_HOME}/bin/lib/board.sh"
# shellcheck source=bin/lib/merge.sh
source "${SWARM_HOME}/bin/lib/merge.sh"
# shellcheck source=bin/lib/lifecycle.sh
source "${SWARM_HOME}/bin/lib/lifecycle.sh"
# shellcheck source=bin/lib/dash.sh
source "${SWARM_HOME}/bin/lib/dash.sh"
# Everything runs from main, called on the last line with `exit` beside it: bash reads a
# script as it executes, so a `git pull` that rewrites this file during a long `wait` would
# otherwise make it resume reading the new file mid-line.
# dispatch <command> [args] — run one command.
dispatch() {
  cmd="${1:-}"; shift || true
  case "${cmd}" in
    policy) policy "${1:?role}" ;;
    agent)  require_herdr; agent_cmd "$@" ;;
    story)  require_herdr; [[ $# -le 2 ]] || die "story: too many arguments: $*"
            if [[ "${1:-}" == --strict ]]; then build_story "${2:?slug}" strict
            elif [[ "${2:-}" == --strict ]]; then build_story "$1" strict
            else [[ -z "${2:-}" ]] || die "story: unknown argument '$2'"; build_story "${1:?slug}"; fi ;;
    conduct) require_herdr; start_conductor "${1:?epic}" ;;
    close)  require_herdr; close_agent "${1:?name}" "${2:-}" ;;
    tell)   require_herdr; tell_agent "${1:?slug}" "${2:-}" "${3:-}" ;;
    unblock) unblock ;;
    next)   next_report ;;
    status) status_report "${1:-}" ;;
    dash)   dash "$@" ;;
    tidy)   require_herdr; tidy_panes "${1:-}" ;;
    cost)   moved cost cost "[--since YYYY-MM-DD] [--until YYYY-MM-DD]" ;;
    outcomes) outcomes_report "$@" ;;
    flow)   flow_report "$@" ;;
    review-yield) moved review-yield reviewers "[--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]" ;;
    log-finding) finding_flags "$@"; shift "${FINDING_SKIP}"
            record_finding "${1:-}" "${2:-}" "${*:3}" "${FINDING_OUTCOME}" ${FINDING_REVIEWER+"${FINDING_REVIEWER}"} ;;
    lessons) lessons_report "${1:-}" ;;
    features) moved features features "[--since YYYY-MM-DD] [--until YYYY-MM-DD]" ;;
    watch)  watch_prs "$@" ;;
    finish) finish_item "${1:?slug}" ;;
    reset)  reset_story "${1:-}" "${*:2}" ;;
    drop)   drop_story "${1:-}" "${*:2}" ;;
    dialog) dialog_answered "${1:-}" "${2:-}" ;;
    plan-unasked) plan_unasked "$@" ;;
    review) mark_review "$@" ;;
    reconcile) reconcile ;;
    merge)  merge_pr "$@" ;;
    wait-pr) wait_pr "$@" ;;
    board-pr) board_pr "$@" ;;
    findings) findings "${1:?repo}" "${2:?pr}" ;;
    config) show_config "${1:-}" ;;
    init)   init_project ;;
    base)   src="$(repo_dir "${1:-}")" || die "${src}"; base_for "${src}" ;;
    codex-review) codex_review "${1:-}" ;;
    review-agent) require_herdr; review_agent "${1:-}" "${2:-}" ;;
    _base)  base_for "${1:?repo dir}" ;;                          # test hook: the base branch for a repo
    _role)  role="$(story_role "${1:?slug}")" || die "${role}"; echo "${role}" ;;   # test hook: the role a story is built as
    _name)  agent_name "${1:?slug}"; echo ;;                      # test hook: the agent name for a slug
    _conductor) conductor_name "${1:?epic or backlog}"; echo ;;   # test hook: a conductor's agent name
    _brief) src="$(repo_dir "$(fm "${BOARD}/stories/${1:?slug}.md" repo)")" || die "${src}"; story_brief "$1" "${src}" main ;;   # test hook: a story's builder brief
    _target) own_target "$(agent_name "${1:?name}")" ;;          # this project's pane for an agent name, to address herdr by
    _label) tab_label "${1:?name}" ;;                             # test hook: the tab label for an agent name
    _archive) archive_session "${1:?name}" ;;                     # test hook: close's copy of an agent's session log
    _mtime) session_mtime "${1:?name}" ;;                         # test hook: the session-log mtime the stall rule reads
    _trusted) require_trusted "${1:?cwd}"; echo trusted ;;        # test hook: whether Claude Code trusts a folder
    _pane)  require_herdr; next_pane "${1:?tab}" "${2:?cwd}" "${3:-}" ;;   # layout test hook: a pane, no agent
    wait)   wait_command "$@" ;;
    *) awk 'NR > 1 && /^#$/ && ++blank == 2 { exit } NR > 1' "$0"; exit 2 ;;   # the header up to the command list's end
  esac
}

# READ_ONLY_COMMANDS change nothing, so they are not logged: the readers, the waits conductors run
# all the time (wait, wait-pr, watch), and the test hooks (_name ...; _pane opens a pane for a layout test only).
# The one line a read-only command writes is wait's `nudge <name>`, one per nudge it sends.
# Every other command is logged (fail closed: a new command is logged until it is named here), and so
# is tidy --yes; tidy alone only lists. A command that is not one (a typo, --help) is not logged.
READ_ONLY_COMMANDS="dash status next config policy cost outcomes flow review-yield features lessons findings wait wait-pr watch base _base _role _name _conductor _brief _target _label _trusted _pane _mtime"

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
  local pids p
  pids="$(tree_pids "$1")"
  # shellcheck disable=SC2046,SC2086 # one pid per word
  {
    kill -TERM ${pids}
    poll_while "${CODEX_GRACE}" kill -0 ${pids}
    for p in ${pids}; do kill -KILL $(tree_pids "${p}"); done
    wait "$1"
  } 2>/dev/null || true
}

# story_items <story file> <heading> — the items under a story's bold **<heading>** line: any text on
# that line, then the non-blank lines under it, up to the next bold line or markdown heading.
story_items() {
  awk -v h="$2" 'index($0, "**" h) == 1 { on = 1; sub(/^\*\*[^*]*\*\*[[:space:]]*/, ""); if ($0 != "") print; next }
    on && /^(\*\*|#+[[:space:]])/ { exit } on && /[^[:space:]]/' "$1"
}
# codex_story_prompt <base> <story file> — the review prompt: the branch's diff against origin/<base>,
# the story's touches, its **Done when** and **From review** items (the builder's acceptance, as in
# goal_condition), and that work outside them is not a finding. Fails with no Done when item.
codex_story_prompt() {
  local done_when from_review
  done_when="$(story_items "$2" 'Done when')"
  [[ -n "${done_when}" ]] || return 1
  from_review="$(story_items "$2" 'From review')"
  [[ -z "${from_review}" ]] || from_review=$'\n\nIts From review:\n'"${from_review}"
  # shellcheck disable=SC2016 # the $(...) is for codex to run
  printf 'Review the changes on this branch against origin/%s, committed or not: git diff $(git merge-base origin/%s HEAD) for tracked files, and each untracked file git status --porcelain lists. They implement a story that touches: %s\n\nIts Done when:\n%s%s\n\nReview them against these touches and items. Work outside them is not a finding.' \
    "$1" "$1" "$(fm "$2" touches)" "${done_when}" "${from_review}"
}

# codex_review <base> — codex's review of the cwd against origin/<base>: no prompt (codex refuses one
# beside --base) and stdin from /dev/null, so it never waits on input. With SWARM_STORY=<slug>, a
# prompt instead of --base (codex_story_prompt), so codex reviews against that story. codex stays in
# the caller's process group, so a harness that kills that group kills codex too. stop_codex stops it
# after codex_minutes (SWARM_CODEX_SECONDS overrides it, for tests), or when this command is sent
# TERM or HUP, which main_signal sends it on an interrupt and then waits out. The timeout dies, so
# events.tsv's line says so; otherwise it exits as codex did. codex's output, stderr merged into
# stdout, streams through tee into a temp file; tee gets CODEX_GRACE seconds after codex exits, since a
# child of codex left holding the pipe would keep it open, and codex_cleanup stops it on any exit. A failed codex whose last lines hold its own
# limit message (CODEX_LIMIT_RE, not the transcript, which may quote a diff about limits) logs a
# codex-limit incident, and with fallback_reviewer set, codex_fallback reviews in its place, in what
# is left of codex_minutes.
codex_review() {
  local pid tpid left t0 rc=0 m i args story prompt="" dir log files
  [[ -n "$1" ]] || die "usage: swarm.sh codex-review <base>"
  args=(--base "origin/$1")
  if [[ -n "${SWARM_STORY:-}" ]]; then
    [[ "${SWARM_STORY}" =~ ^[a-z0-9-]+$ ]] || die "SWARM_STORY: bad slug '${SWARM_STORY}'"
    story="${BOARD}/stories/${SWARM_STORY}.md"
    [[ -f "${story}" ]] || die "SWARM_STORY=${SWARM_STORY}: no story file ${story}"
    prompt="$(codex_story_prompt "$1" "${story}")" \
      || die "SWARM_STORY=${SWARM_STORY}: ${story} has no **Done when** with an item under it"
    args=("${prompt}")
  fi
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
  # Each trap is this run's files and tee, fixed when set: the marker's before it is written.
  files="$(printf %q "${m}")"
  # shellcheck disable=SC2064
  trap "codex_cleanup - ${files}" EXIT
  printf '%s\t%s\t%s\n' "$(date +%s)" "$1" "${PWD}" > "${m}"
  # The log and its fifo in a directory of this run's own (mktemp -d: mode 700), so no other user
  # can make or read them first.
  dir="$(mktemp -d "${TMPDIR:-/tmp}/swarm-codex.XXXXXX")"; log="${dir}/log"
  files+=" $(printf %q "${dir}")"
  # shellcheck disable=SC2064
  trap "codex_cleanup - ${files}" EXIT
  mkfifo "${dir}/fifo"
  tee "${log}" < "${dir}/fifo" &
  tpid=$!
  # shellcheck disable=SC2064
  trap "codex_cleanup ${tpid} ${files}" EXIT
  codex exec review "${args[@]}" < /dev/null > "${dir}/fifo" 2>&1 &
  pid=$!
  # shellcheck disable=SC2064 # this codex's pid, fixed now
  trap "stop_codex ${pid}; exit 143" TERM HUP
  t0=${SECONDS}
  poll_while "${left}" kill -0 "${pid}" 2>/dev/null
  # What codex used is gone: a fallback gets only the rest.
  left=$((left - (SECONDS - t0))); ((left > 0)) || left=0
  if ! kill -0 "${pid}" 2>/dev/null; then
    wait "${pid}" || rc=$?
    for ((i = CODEX_GRACE * 5; i > 0; i--)); do kill -0 "${tpid}" 2>/dev/null || break; sleep 0.2; done
    { kill "${tpid}"; wait "${tpid}"; } 2>/dev/null || true
    # Both reaped: no trap may signal their pids again, which another process could have taken.
    # shellcheck disable=SC2064
    trap "codex_cleanup - ${files}" EXIT
    trap "exit 143" TERM HUP
    if [[ ${rc} -ne 0 ]] && tail -n 5 "${log}" | grep -Eq "${CODEX_LIMIT_RE}"; then
      # Not the slug alone, which is also its builder's agent name: login_incident would take this
      # line for the end of that builder's login episode.
      record_event incident "codex-${SWARM_STORY:-$1}" "codex-limit: usage limit"
      # Last in its list, never a condition, so errexit stays on in codex_fallback; a fallback that
      # does not review exits there, as codex did.
      [[ -z "${CFG_fallback_reviewer}" ]] || { codex_fallback "$1" "${prompt}" "${left}" "${log}" "${rc}"; return 0; }
    fi
    return "${rc}"
  fi
  stop_codex "${pid}"
  die "codex skipped: timed out after ${CFG_codex_minutes} min"
}

# codex_cleanup <tee pid, or -> <file>... — codex-review's EXIT trap, so every way out (codex done, the
# timeout, an interrupt, a failed step) runs it: stop tee, which a child of codex left holding its
# pipe would keep running, and the caller's stdout open with it; then remove the run's files and
# its directory.
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
codex_cleanup() {
  [[ "$1" == - ]] || { kill "$1"; wait "$1"; } 2>/dev/null || true
  shift; rm -rf "$@"
}

# CODEX_LIMIT_RE: codex's own usage-limit line, as `codex exec` prints it (ERROR: or ■ before it,
# and a curly apostrophe: "ERROR: You’ve hit your usage limit. Upgrade to Pro ...").
CODEX_LIMIT_RE="^(ERROR: |■ )?You(’ve|'ve| have) hit your usage limit"

# FALLBACK_MIN_SECONDS: the least of codex_minutes that must be left for a fallback reviewer to be
# worth starting (SWARM_FALLBACK_MIN_SECONDS overrides it, for tests).
FALLBACK_MIN_SECONDS="${SWARM_FALLBACK_MIN_SECONDS:-120}"

# fallback_skip <codex's exit> <why> — codex was skipped after all: say why, and exit as codex did.
fallback_skip() { echo "codex skipped: usage limit ($2)" >&2; exit "$1"; }

# codex_fallback <base> <prompt> <seconds left> <scratch file> <codex's exit> — codex hit its usage
# limit and fallback_reviewer names a model: start fallback-<story> (role review-fallback, on that
# model) in the cwd with codex's prompt, wait what is left of codex's time (<seconds left>, its start
# bounded by it and counted against it) for its
# findings file (.swarm/reviews/fallback/<story>.md) as `wait review-<slug>` does, print it in codex's
# place under the line the PR body takes, and close the agent, findings or not; an interrupt closes
# it too. Every other way out is fallback_skip: outside herdr, under FALLBACK_MIN_SECONDS left, its
# 32-character name held by another story's fallback or by a fallback still reviewing, a brief it
# could not write, a start that failed,
# or no file in time. Called with errexit on (never in a condition), and start_agent runs in a
# background subshell, which keeps errexit on, so a step that fails inside it stops the start.
codex_fallback() {
  local id full name out brief holder wpid deadline=$((SECONDS + $3)) left="$3" err="$4"
  [[ "${HERDR_ENV:-}" == 1 ]] || fallback_skip "$5" "fallback did not start: not in a herdr pane (HERDR_ENV != 1)"
  (( left >= FALLBACK_MIN_SECONDS )) || fallback_skip "$5" "no time left for a fallback"
  id="${SWARM_STORY:-$(agent_name "$(basename "${PWD}")")}"; full="fallback-${id}"; name="$(agent_name "${full}")"
  out="${PROJECT_DIR}/.swarm/reviews/fallback/${id}.md"; brief="${PROJECT_DIR}/.swarm/briefs/fallback/${id}.md"
  holder="$(pane_name_of "${name}")"
  [[ -z "${holder}" || "${holder}" == "${full}" ]] || fallback_skip "$5" "fallback did not start: ${name} is held by ${holder}"
  # Before any file is touched: a fallback still reviewing (another run's) is refused and kept, a
  # finished one retired. The name is then free, so any pane holding it after a failed start is ours.
  (free_agent_name "${name}") 2> "${err}" || { holder="$(tail -1 "${err}")"; fallback_skip "$5" "fallback did not start: ${holder#swarm: }"; }
  { mkdir -p "${out%/*}" "${brief%/*}" && rm -f "${out}" && fallback_brief "$1" "$2" "${out}" > "${brief}"; } 2> "${err}" \
    || fallback_skip "$5" "fallback did not start: could not write its brief ${brief}: $(tail -1 "${err}")"
  # A tab of its own, fallback-<story>: a usage limit hits every builder at once, and fallbacks
  # sharing one tab record would race on it.
  (start_agent "${full}" "${name}" "${PWD}" review-fallback "${brief}" "${full}" > /dev/null) 2> "${err}" & wpid=$!
  # shellcheck disable=SC2064 # this start and agent, fixed now
  trap "kill_tree ${wpid}; fallback_close ${full}; exit 143" TERM HUP
  # start_agent can retry for minutes: past codex's time it is stopped, and what it opened closed.
  while kill -0 "${wpid}" 2>/dev/null && ((SECONDS < deadline)); do sleep 1; done
  if kill -0 "${wpid}" 2>/dev/null; then
    kill_tree "${wpid}"; { wait "${wpid}" || true; } 2>/dev/null; fallback_close "${full}"
    fallback_skip "$5" "fallback did not start: its start ran out of codex's time"
  fi
  if ! wait "${wpid}"; then
    # A start that fails after its pane opened (the brief not taken up) leaves that pane: closed.
    fallback_close "${full}"
    holder="$(tail -1 "${err}")"; fallback_skip "$5" "fallback did not start: ${holder#swarm: }"
  fi
  # The start is reaped: the trap names no pid again until the wait has one.
  # shellcheck disable=SC2064 # this agent, fixed now
  trap "fallback_close ${full}; exit 143" TERM HUP
  left=$((deadline - SECONDS))
  # Until its findings file exists, within the time left: an agent idle while a subagent or a
  # background Bash call of its own still runs has not finished. In the background, so an interrupt
  # is handled at once, not after a poll.
  wait_conductor "${name}" $(( (left > 0 ? left : 1) * 1000 )) "${out}" > "${err}" 2>&1 & wpid=$!
  # shellcheck disable=SC2064 # this wait and agent, fixed now
  trap "kill_tree ${wpid}; fallback_close ${full}; exit 143" TERM HUP
  wait "${wpid}" || true
  # shellcheck disable=SC2064 # this agent, fixed now
  trap "fallback_close ${full}; exit 143" TERM HUP
  fallback_close "${full}"
  [[ -f "${out}" ]] || fallback_skip "$5" "${name} wrote no findings in time: $(tail -1 "${err}")"
  echo "reviewed by fallback ${CFG_fallback_reviewer}: codex usage limit"
  cat "${out}"
}

# pane_name_of <agent name> — the full name the tab records give the pane this project's agent
# <name> holds (start_agent's pane name), or nothing.
pane_name_of() {
  local pane
  pane="$(agent_field "$1" pane_id)"; [[ -n "${pane}" ]] || return 0
  cat "${STATE_DIR}"/* 2>/dev/null | awk -v p="${pane}" 'NF == 2 && $1 == p { print $2; exit }' || true
}

# fallback_close <name> — close a fallback agent as `swarm.sh close` does a review agent: its session
# log archived, and its tab (fallback-<story>, its own) closed by that exact label, so no other
# fallback's tab goes with it.
fallback_close() {
  local state="${STATE_DIR}/$1" pane t
  archive_session "$1" || true
  [[ -f "${state}" ]] || return 0
  pane="$(awk 'NF == 2 { print $1; exit }' "${state}")"
  for t in $(herdr tab list --workspace "${pane%%:*}" 2>/dev/null \
    | SWARM_LABEL="$1" json "' '.join(t['tab_id'] for t in d['result']['tabs'] if t.get('label') == e['SWARM_LABEL'])" 2>/dev/null); do
    herdr tab close "${t}" > /dev/null 2>&1 || true
  done
  rm -f "${state}"
}

# fallback_brief <base> <prompt> <findings file> — the fallback reviewer's brief: codex's prompt (the
# branch's diff against origin/<base> when codex had none), read-only, and its findings written to
# <findings file> in the form codex prints them.
fallback_brief() {
  # shellcheck disable=SC2016 # the $(...) is for the agent to run
  local diff='Review the changes on this branch against origin/'"$1"', committed or not: git diff $(git merge-base origin/'"$1"' HEAD) for tracked files, and each untracked file git status --porcelain lists.'
  cat <<EOF
codex hit its usage limit, so you review in its place. You are read-only: never edit, commit or push
here, and never merge, by any route. The one file you write is $3.

${2:-${diff}}

You have no Edit, Write or NotebookEdit tool. When done, write your findings with Bash to $3.tmp,
then mv it to $3 (codex-review waits until that exists): each finding as codex prints one, most severe first, \`- [P<0-3>] <title> — <file>:<line>\` with a line
or two on why under it, or the one line \`No findings.\` when there are none.
EOF
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
  record_event "${EV_CMD}" "${EV_TARGET#[+!]}" interrupted
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  trap - "$1"
  kill -"$1" "$$"
}

# main <command> [args] — dispatch, and log each command that is not read-only to EVENTS_LOG with its
# outcome: ok, interrupted, the first line of a die at the command's own level, or failed (exit N).
# A die inside a nested $(...) gives only failed (exit N): a caller may have tolerated it, so its
# message could name the wrong failure; it was printed to stderr all the same. reconcile and unblock
# log one line per item themselves, and merge (target !) every line it writes, so main logs none
# for it but an interrupt. A tell's command is tell:<kind>, a close's close:<cause> and a
# board-pr's board-pr:<step>, so the target stays the slug (a board-pr's name). A reset or drop
# that succeeds logs ok (<reason>), and a review ok (<PR URLs>), so outcomes can tell which PRs an
# epic's review handed over; a reset that lifts a hold (held_for:) logs as reset:held.
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
    # A decline is logged as log-finding:declined (a filed one as log-finding:filed), so its target stays <kind> <pr>, as for a fix; the
    # flags are skipped as dispatch skips them (finding_flags).
    log-finding) finding_flags "${@:2}"
                 [[ "${FINDING_OUTCOME}" == fixed ]] || EV_CMD="log-finding:${FINDING_OUTCOME}"
                 EV_TARGET="${*:$((FINDING_SKIP + 2)):2}" ;;
    reconcile|unblock) EV_TARGET=+ ;;
    merge) EV_TARGET='!' ;;
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
    review) EV_TARGET="${2:-}"; EV_OK="ok (${*:3})" ;;
    board-pr) EV_TARGET="${3:-}"; case "${2:-}" in start|open|done) EV_CMD="board-pr:$2" ;; esac ;;
    story) EV_TARGET="${2:-}"; [[ "${EV_TARGET}" != --strict ]] || EV_TARGET="${3:-}" ;;
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
  if [[ "${EV_TARGET}" == '!' ]]; then
    :
  elif [[ ${rc} -ne 0 ]]; then
    why="$(head -1 "${EV_ERR}" 2>/dev/null || true)"
    record_event "${EV_CMD}" "${EV_TARGET#+}" "${why:-failed (exit ${rc})}"
  elif [[ "${EV_TARGET}" != + ]]; then
    record_event "${EV_CMD}" "${EV_TARGET}" "${EV_OK}"
  fi
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  return "${rc}"
}

main "$@"; exit
