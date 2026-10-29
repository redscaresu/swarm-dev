#!/usr/bin/env bash
# swarm.sh — run agents in herdr panes so every one can be watched.
#
#   swarm.sh agent <tab> <name> <cwd> <role> <prompt-file>   start one agent in its own pane
#   swarm.sh story [--strict] <slug>                        build one <board>/stories/<slug>.md; warn when another epic's open story touches the same part (by its first word) of a file or both name the bare file, and with --strict refuse
#   swarm.sh conduct <epic>|--backlog                       a fresh conductor for one epic, in the workspace <project> · <its parent: epic, else the epic>; --backlog: for the ready stories with no epic, in <project> · backlog
#   swarm.sh wait [--stall] [--idle] <name> [timeout-ms]    block until the agent settles (a review agent: until its findings file exists too); exit 1 at the timeout; exit 4 with "stuck: api error" (an API-error stop wait's resumes did not clear) or "stuck: no output for <N>m (<pane>)"; on the usage limit it picks "continue automatically" and waits on; --stall: also exit 3 when a builder stalls; --idle, on a builder's wait (not a conductor's or a review agent's): exit 5 when it ends on anything but idle or done (auth, waiting, gone, stepped up:, stepping up:)
#   swarm.sh wait --until-report conduct-<epic>             block, with no timeout, until the conductor reports, waits on a prompt, is gone or needs a login; exit 4 when stuck, as wait
#   swarm.sh wait --lead [timeout-ms]                       block until the lead's queue gains a held, escalated or kept story, a green PR in review that waits on the user (merge = human, or merge holds it), a started story with no live agent (no-agent: <slug>, exit: <exit>), a PR whose review agent never started or went (no-review: ...), a failed step-up (step-up failed: ...), a brief still unsent (unsent brief: ...), an agent stuck on a prompt, a dialog, an expired login, an API error or manual mode (prompt: <agent> (<kind>), exit: <exit>), a blocked story whose dependency shares no touches part with it (idle: <story> waits on <dep> ...), or a ready story with no build past queue_minutes (idle: <story> is ready with no build, exit: <exit>), as next prints them, a reviewed green story PR left unmerged past queue_minutes (unmerged: <slug> <PR URL>, ...), a story PR that conflicts with its base (conflict: <slug> <PR URL>, ...), or any other line § The lead in docs/reference.md lists; print each new one
#   swarm.sh policy <role>                                  print the model and effort for a role
#   swarm.sh close <name> [cause] [--drop] [--all]          close a story's pane, a conductor's epic tab, or a tab and its overflow, keeping each tab that holds an agent working, waiting or with its story's PR open (named as kept; a conductor's own pane still closes) unless --all; closing a ready story's builder counts a failed build (attempts:) and clears its worktree and branch, but while its PR is open it keeps the PR, branch and worktree and counts nothing, unless --drop, which clears them too and prints each head SHA; cause: met, impossible, stalled, bound, paused or cleared-on-error (the last three count nothing; impossible makes the story the lead's, and paused and cleared-on-error hold it for the lead), required with goal on while the story is ready
#   swarm.sh step-up <slug> <trigger> [findings-file]       with escalate_ladder set, close a story's builder without counting an attempt and start the ladder's next model in the same worktree and branch, with a handover brief (and the file's findings); trigger: findings-<step_up_findings> (findings-3 by default), ci-red-2, stalled or no-pr. close, wait --stall, tell, watch and a review pane's wait-pr run it themselves
#   swarm.sh step-up --resume <slug>                        start the rung a step-up closed the old builder for but could not start, from the brief it wrote
#   swarm.sh restart <slug>                                start a started story's builder again once herdr no longer lists it, in its worktree, branch and tab: it reopens the builder's last Claude session when its resume command names one that took its brief, else starts a fresh builder on the last model with a handover brief; holds the story's step-up lock; refused while the builder is listed, with no worktree or one off story/<slug> or holding a git step left unfinished, for a story not ready, kind: lead, held or escalated, with a PR merged or set to auto-merge, or with a step-up waiting (step-up --resume)
#   swarm.sh tell <slug> <kind> <file>                      send an idle builder (or any agent) a file's contents, or queue it for a busy one's next idle; kind: findings, nudge or resume; or note: append it to a conductor's inbox, busy or not, and prompt one whose turn has ended to read it (once a minute at most, the rest a minute later); one with no pane, or whose session has ended, is refused once as could not reach, naming its exit
#   swarm.sh cost | features | review-yield                 moved: each prints which flow section holds its numbers (cost, features, reviewers)
#   swarm.sh outcomes [--since YYYY-MM-DD]                  one TSV row per builder: story, kind, model, cost, tells, findings, PR, attempt, minutes start → PR → merge, main merges
#   swarm.sh dataset                                        write .swarm/dataset.jsonl: one JSON line per finished story, its planned inputs (story text, kind, risk, touches, easy, estimate, planner model) and results (diff, attempts, findings rounds, rework, cost, minutes, models, escalations), and was_easy
#   swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]  one section per bin/lib/flow_*.py: cost (tokens and estimated cost per role), features (each docs/features.tsv feature's uses, metric, baseline, and delete? when unused or unmeasured), merges (stories finished per day), reviewers (findings raised, fixed and declined per reviewer and kind, the split critic's fixes beside its escaped split-gaps per split, and review rounds per PR), throughput (per epic: builders at once, stories per chain, review wait, stacked starts)
#   swarm.sh log-finding [--declined <reason> | --filed] [--reviewer <who>] [--round <n>] <kind> <pr-url> <text>  log one review finding that was fixed (or, --declined, declined for <reason>: out-of-scope, nit or wrong; or, --filed, a declined out-of-scope one filed as a story, so next stops offering it), by its kind and the reviewer that raised it: codex, fallback, code-review, ci, conductor, lead, skeptic, critic, split-critic, or escaped for a defect found after its PR merged, and with --round the review round it came from, 0 for a plan or board PR (the outer loop)
#   swarm.sh intervene <kind> "<one line>"                  log a time a person had to step in, as an incident line: lead-hand (the lead acted by hand where a command should have) or user-caught (the user found a problem first)
#   swarm.sh hold <slug> <why>                              log that a conductor held a ready story back this wave, and why (what it clashes with and the shared files, or the other reason), as a hold line with outcome ok (<why>); refused for a story whose PR was closed unmerged, which is the lead's
#   swarm.sh lessons [--all]                                moved: prints that recurring kinds are in outcomes' recurring block
#   swarm.sh next                                           the chain's next step, read from the board (resumable)
#   swarm.sh status [--all]                                 agents that need a look, stacked builds whose parent moved or merged, what waits on you, and the next step
#   swarm.sh where <agent>                                  this project's agent (a slug, review-<slug>, conduct-<epic> or a herdr agent name): its pane id, its workspace's label and its tab's label; the workspace label is - when herdr gives none, the tab the name swarm-dev gave it (no label, a gone tab, or a list it could not give); exit 1 when herdr lists no such agent in this project's panes
#   swarm.sh swarms                                         every swarm herdr runs on this machine: each `swarm-lead · <project>` workspace as a project, with its dir, then its workspaces (the lead's first) with their agents; a workspace is a project's by its label and its dir, never by a prefix of another project's label or a dir name two projects share
#   swarm.sh dash [--watch [seconds]] [--ladder] [--tree] [--check] [--project <dir>]...  a read-only dashboard: what needs you, epics with their agents and PRs, recent events; --watch redraws in place, q quits, t tree, l ladder; each --project draws that project's frame, one after another; --check compares each figure with the command that owns it (status, flow, next, events.tsv) and exits 1 naming each one that differs
#   swarm.sh upgrade [<epic>|backlog] [--foreground]        after claude plugin update: runs detached (log .swarm/upgrade-<version>.log; one per project, a second names it), in rounds: the epic's (backlog: the stories with no epic) conductor writes a handover (.swarm/handover-<epic>-<date>.md) and ends its turn, then each of its Claude agents (every one this project started, with no epic), once idle, is restarted in its pane with --resume on this version (its PATH's swarm.sh this one's), a builder not while its Claude review agent is busy on the old version; one still busy after SWARM_UPGRADE_WAIT_MS (2 hours) in all is named and left on its old version; worktrees are never touched; prints each agent's old and new version, exits 1 if any is left
#   swarm.sh tidy [--yes]                                   list, and with --yes close, empty panes and retired agents' panes
#   swarm.sh unblock [--startable <epic>|--backlog]         mark ready every blocked story whose depends_on are all finished, or, while it has no worktree or story/<slug> branch, finished or stories in its repo with open PRs: it starts stacked on those (with a build already there it prints not stacked:); a child review held (held_by:) only once they all finish, to merge the base in and be reviewed again; --startable: then print startable: <slug> for each ready story of that epic (--backlog: with no epic) whose build has not started, readied now or before, as reconcile last left the board (it never pulls), with (stacked on <parents>) or (its PR <url> was closed unmerged) when that applies; nothing once the epic's file is gone
#   swarm.sh finish <slug | hld>                            take a merged story or epic off the board (delete its file), or a planned HLD with no epic left, in a board PR
#   swarm.sh reset <slug> <reason>                          put an escalated story back as it was: its kind, no attempts:, no lead's block; for a held story (held_for:), lift the hold and keep attempts:
#   swarm.sh drop <slug> <reason>                           take an escalated story off the board; the lead commits that in a board PR
#   swarm.sh dialog <slug> <accepted|dismissed>             log how a builder's Fable usage-credits consent dialog was answered
#   swarm.sh grants <story | epic | hld | PR URL>          the agreed HLD over it (a story's epic:, then parent: up to an epic with hld:; a PR's stories, or a board PR's touched epics and stories, all under one HLD) and its grants, one per line, or none
#   swarm.sh plan-unasked [--declined] <epic>               record that a later epic next offered has had its unasked plan, so next offers it no more; --declined: that the user declined it
#   swarm.sh review <slug> [--head <sha>] <pr-url>...       a story or epic whose PRs are green and reviewed now waits on a human merge; --head: only while each PR's head is still <sha>, the head its review passed, and its prs: lists no other PR, else nothing changes (a moved head's refusal names review-agent --next)
#   swarm.sh reconcile                                      finish each review item whose PRs all merged; a closed one goes back to ready
#   swarm.sh merge [--board|--release] [--head <sha>] <pr-url>  merge a green PR in review with its head pinned, wait for CI on the merge commit, then reconcile; with merge = agent, by any route, held for the user when a story listing it, or one it stacks on, has costs: money (or any value but none), and a story PR held for the user when it changes .claude/, .github/, hooks/ or a root Makefile (the user merges it by hand); --board: a board-only PR; --release: a PR into the project's base that changes only the version in .claude-plugin/plugin.json, no reconcile; with merge = human, a story or board PR only under an agreed HLD that grants merge, and even then held for the user when it has costs: money; --release only when at least one story merged since the last tag and every one of them is under an HLD that grants release; a story or --board PR that sets an epic active with no ticket (agreed:, parent:, an HLD granting epics, or lead_epics = on) is refused; under either merge mode, a story or --board PR whose own merge of the base dropped a line of the base (dropped-lines, on the pinned head) is held for the user, as is one whose merges cannot be checked, and one whose head moved on GitHub meanwhile is refused for a new review
#   swarm.sh dropped-lines <owner/repo> <n> <head> <base>  read-only: fetch PR <n>'s head (refs/pull/<n>/head) into the clone of <owner/repo>, check it is <head>, and print each base line a merge on its first-parent chain dropped (`<sha7> <file>: <text>`), skipping only GitHub's merges of the base that merge recorded as base-merged; exit 0 none, 1 lines dropped, 2 when it cannot check (a moved or stale head, another origin, git below 2.36)
#   swarm.sh wait-pr [--timeout <seconds>] --head <sha> <pr-url>  wait for a PR's checks on <sha>, read again each poll until the PR's head is <sha> (a prefix of 7 or more; still another after 5 minutes exits 2); with no --head, on the head of its first read, which right after a push can be the old one: print the head SHA and each check; exit 0 green, 1 red, 2 on a gh error (a transient one is retried 3 times; a spent API budget is waited out once, to its printed reset, unless that is past --timeout), a PR that conflicts with its base, no check runs (or no run of a workflow its pull_request triggers) within 5 minutes, or still pending after <seconds> (default 1800); from the story's review pane with escalate_ladder set, a red head counts toward the ladder's ci-red step-up, which it runs itself (stepped up: <slug>)
#   swarm.sh board-pr start <name>                          a worktree <repo>-wt/_board-<name> on a new board/<name> from origin/<base>, for a board edit; prints its path
#   swarm.sh board-pr open <name> "<title>" <body-file>     commit (only board files may change), push and open the board PR; prints its URL
#   swarm.sh board-pr done <name>                           remove board/<name> on origin and here, and the worktree, once its PR merged or closed (or with no PR, nothing past the base)
#   swarm.sh findings <repo> <pr>                           every check-run note on a PR's head, its open code-scanning alerts, and each new test with no FAIL line in its body
#   swarm.sh watch [--epic <slug>|--backlog] [repo...]      wait until a story PR needs the lead (or waits queue_minutes, green, for a review), print why, and exit; with --epic or --backlog, also once when a story PR of theirs opens
#   swarm.sh config [key]                                   the project's settings and where each came from, or one value
#   swarm.sh init [--auto-mode-done]                        from a git repo's root: add the board, .claude/swarm/ and the .gitignore lines, and print the Claude Code steps left to you; --auto-mode-done: record (in .swarm/auto-mode-done) that you ran /auto-mode-setup, writing nothing outside .swarm/
#   swarm.sh base <repo>                                    the base branch a repo's stories start from and its PRs go into
#   swarm.sh codex-review <base>                            codex's review of this directory against origin/<base>, stopped after codex_minutes; with SWARM_STORY=<slug>, against that story's touches and Done when
#   swarm.sh review-agent <slug> <pr-url>                   start review-<slug>, an agent in the story's worktree that reviews its PR against the story's touches and Done when, writes .swarm/reviews/<slug>.md, and returns at once; it never edits the code, and on a pass it runs review --head on the head it reviewed, then merges the PR (merge = agent, or an HLD that grants merge) or leaves it for the user
#   swarm.sh review-agent --next <slug> <pr-url>            from review-<slug>'s own pane, its next round in the same session: once the worktree is at the PR's head, move the last findings aside, record the head, and print the round and what it runs; starts no agent
#   swarm.sh review-agent --recheck <slug> <pr-url> <old head> <file:line>...   from review-<slug>'s own pane, after a wording fix: pass when the PR's new head is green and its diff from <old head> rewrites each named line (as at <old head>) and nothing else, the lines the old head's .round.md names, writing the new head's findings file, a pass, and .head; else refuse, writing nothing, and name --next, which that refusal counts the round for, when the old head, its findings, the diff or a red head rule the recheck out
#   swarm.sh version                                        the installed version, and a warning when a newer one is out
#   swarm.sh update                                         update the plugin to the newest version
#
# The project is, first match wins: $SWARM_PROJECT; the nearest directory up from here with
# .claude/swarm/config (mapped to the main checkout when it is in a git worktree); the main checkout
# of the git repo you are in. With SWARM_FORBID_PROJECT naming a directory (the test runner and
# tests/test_helpers.sh name the checkout the tests run from), that project and its worktrees are refused.
# Settings live in .claude/swarm/config (see config below). Must run
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
# config line) or a set -e stop, exits 2; its temp files (WAIT_PR_TMP and its .expected memo) go either way.
WAIT_PR_RED=""; WAIT_PR_TMP=""
if [[ "${1:-}" == wait-pr ]]; then
  trap 'rc=$?; rm -f "${WAIT_PR_TMP}" ${WAIT_PR_TMP:+"${WAIT_PR_TMP}.expected"}; [[ ${rc} -eq 0 || -n "${WAIT_PR_RED}" ]] || exit 2' EXIT
fi
# dropped-lines' exit 1 means base lines were dropped (DROPPED_FOUND), so any other stop, a die or a set
# -e stop, exits 2; the refs its fetch made (dropped_refs_drop) go either way. A stop before merge.sh is
# sourced (outside a swarm project, say) has no dropped_refs_drop, and no refs to drop.
DROPPED_FOUND=""; DROPPED_REF=""; DROPPED_DIR=""
if [[ "${1:-}" == dropped-lines ]]; then
  trap 'rc=$?; ! declare -F dropped_refs_drop >/dev/null || dropped_refs_drop; [[ ${rc} -eq 0 || -n "${DROPPED_FOUND}" ]] || exit 2' EXIT
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
# NO_PROJECT is 1 when the cwd stands in, so run_time_start logs no row there.
NO_PROJECT=""
if [[ "${1:-}" == dash && " $* " == *" --project "* && -z "${SWARM_PROJECT:-}" ]]; then
  PROJECT_DIR="$(find_project 2>/dev/null)" || { PROJECT_DIR="$(pwd -P)"; NO_PROJECT=1; }
else
  PROJECT_DIR="$(find_project)"
fi
# A test names the checkout it runs from in SWARM_FORBID_PROJECT (scripts/test.sh and tests/test_helpers.sh
# set it to the main checkout): swarm.sh refuses to act on that project, named directly (a cd into it,
# SWARM_PROJECT) or through a worktree of it (SWARM_PROJECT naming the worktree, which find_project
# takes as given, so its main checkout is compared too). That covers swarm.sh calls; the hooks' own
# event lines (hooks/merge-guard.sh record, hooks/lead-stop.sh log) are not swarm.sh calls and are not.
if [[ -n "${SWARM_FORBID_PROJECT:-}" ]]; then
  forbid_dir="$(cd "${SWARM_FORBID_PROJECT}" 2>/dev/null && pwd -P)" || forbid_dir=""
  forbid_main="$(main_checkout "${PROJECT_DIR}" 2>/dev/null)" || forbid_main=""
  [[ -z "${forbid_main}" ]] || forbid_main="$(cd "${forbid_main}" 2>/dev/null && pwd -P)" || forbid_main=""
  if [[ -n "${forbid_dir}" ]] && [[ "$(cd "${PROJECT_DIR}" && pwd -P)" == "${forbid_dir}" || "${forbid_main}" == "${forbid_dir}" ]]; then
    die "SWARM_FORBID_PROJECT: ${PROJECT_DIR} is the checkout the tests run from, or a worktree of it; a test cd's into a project of its own, or names one in SWARM_PROJECT"
  fi
  unset forbid_dir forbid_main
fi
CONFIG_FILE="${PROJECT_DIR}/.claude/swarm/config"

# Every gh call this command makes, and every agent it starts (launch_file passes PATH and SWARM_*
# on), goes through bin/gh-shim, which logs it to this project's .swarm/gh-calls.tsv for flow's
# gh_calls section, with the agent that ran it (SWARM_GH_CALLER, which launch_file sets) and, for
# this command's own calls, `swarm.sh <command>` as its via: the outermost command's, so what a
# command runs through another swarm.sh (dash --check's status, merge's wait) counts as the command
# that caused it. launch_file drops the via, so an agent's own swarm.sh starts afresh. A dash
# --project runs swarm.sh again for each project, so each one's calls land in its own log.
GH_VIA="${1:-}"
# Set when another swarm.sh runs this one, which passes its SWARM_GH_VIA on (lead_rename reads it).
NESTED_CALL="${SWARM_GH_VIA:+1}"
export SWARM_GH_LOG="${PROJECT_DIR}/.swarm/gh-calls.tsv" SWARM_GH_VIA="${SWARM_GH_VIA:-swarm.sh ${GH_VIA//[^a-z-]/}}"
# First, not just present: a folder with a gh before it would take swarm.sh's calls past the shim.
GH_SHIM="${SWARM_HOME}/bin/gh-shim"
if [[ "${PATH}" != "${GH_SHIM}" && "${PATH}" != "${GH_SHIM}:"* ]]; then
  GH_PATH=":${PATH}:"; GH_PATH="${GH_PATH//:${GH_SHIM}:/:}"; GH_PATH="${GH_PATH#:}"; GH_PATH="${GH_PATH%:}"
  export PATH="${GH_SHIM}${GH_PATH:+:${GH_PATH}}"
fi

# Settings, with their defaults. CFG_<key> is the value, SRC_<key> where it came from.
CFG_board_dir=docs
CFG_repos_dir=""        # empty: the project dir's parent
CFG_base_branches=""    # empty: origin's default branch; else branches to try in order, such as dev main
CFG_sign_commits=false  # true: every commit and merge is signed (swarm.sh's own and each agent's), or the agent stops
CFG_merge=human         # human: a PR that is ready waits on the board for you, unless an HLD grants merge (merge_grant)
CFG_stall_minutes=30    # an agent working this long with no sign of life (a builder: commit, PR update or swarm action) is stalled?; a busy one whose pane has not changed, stuck
CFG_queue_minutes=30    # a story PR green and mergeable this long with no review agent on its head is queued: (watch, next); a ready story with no build this long gets next's idle: line; a reviewed story PR left unmerged this long gets wait --lead's unmerged: line
CFG_sonnet_share=0      # N > 0: 1 in N code stories with easy: true and without risk: high is built on Sonnet (code-sonnet), to compare
CFG_escalate_after=2   # N > 0: a story whose attempts: reaches N is built as escalate (Fable); 0 is off
CFG_escalate_ladder=""  # empty: off; else models low to high, such as sonnet,opus,fable: step-up hands a build to the next one
CFG_step_up_findings=3  # with escalate_ladder set, the findings round of a build that steps it up instead of being sent
CFG_top_rung_rounds=2   # with escalate_ladder set, the findings round on its top rung that holds the story for the lead
CFG_builder_subagent_model=""  # empty: building roles' subagents keep Claude Code's choice; else forced to this model
CFG_goal=off            # N > 0: each builder gets a goal condition (.swarm/briefs/<slug>.goal.md) bounded at N turns
CFG_codex_minutes=10    # codex-review stops a codex review that runs this long
CFG_fallback_reviewer="" # empty: a codex usage limit skips codex's review; else a review agent on this model reviews in its place
CFG_lead=off            # session: a lead session acts for the user, so dash splits needs you into the user's steps and a lead's queue
CFG_merge_admin=off     # on: swarm.sh merge passes --admin to gh pr merge, once its own checks pass (a ruleset that wants an approving review)
# shellcheck disable=SC2034 # nothing reads it yet; epic-guard-board-pr does
CFG_lead_epics=off      # on: the lead may set an epic active on its own; off: an epic goes active only through the user or a grant
CFG_commit_trailers=""  # empty: none; else trailers every builder adds to each commit, ; between several
CFG_agent_env=""        # empty: none; else variable names every agent gets with the session's values, such as a provider's key
CONFIG_KEYS="board_dir repos_dir base_branches sign_commits merge stall_minutes queue_minutes sonnet_share escalate_after escalate_ladder step_up_findings top_rung_rounds builder_subagent_model goal codex_minutes fallback_reviewer lead merge_admin lead_epics commit_trailers agent_env"
for _key in ${CONFIG_KEYS}; do printf -v "SRC_${_key}" default; done
# Keys an older swarm-dev read: a config that sets one still loads, with a warning, whatever its value.
REMOVED_KEYS="pr_per finished review_bot keep_panes"

# load_config — read CONFIG_FILE as `key = value` lines. It is parsed, never sourced, so it cannot run
# code; a `$` or backtick is refused so nobody expects it to expand. Any bad line stops the script.
load_config() {
  local n=0 line key value where words w trailer='[A-Za-z][A-Za-z0-9-]*: [^;]*[^;[:space:]]'
  [[ -f "${CONFIG_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$((n + 1)); where="${CONFIG_FILE}:${n}"
    line="${line%%#*}"
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]] \
      || die "${where}: expected 'key = value'"
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    [[ "${key}" != lessons_file ]] || continue   # removed with lessons; an old config still loads, whatever its value
    if [[ " ${REMOVED_KEYS} " == *" ${key} "* ]]; then
      echo "swarm: warning: ${where}: ${key} was removed and is ignored; delete the line" >&2; continue
    fi
    [[ "${value}" != *'$'* && "${value}" != *'`'* ]] || die "${where}: ${key}: \$ and backticks are not expanded; write the value out"
    case "${key}" in
      board_dir|repos_dir)
        [[ -n "${value}" ]] || die "${where}: ${key} is empty"
        # init writes board_dir into quoted strings in CI's gate and the pre-commit hook.
        [[ "${key}" != board_dir || "${value}" != *[\"\\]* ]] || die "${where}: board_dir: \" and \\ are refused; name a plain path"
        # shellcheck disable=SC2088 # a literal ~ in the file, expanded here
        [[ "${value}" == "~" || "${value}" == "~/"* ]] && value="${HOME}${value:1}" ;;
      base_branches)
        [[ "${value}" =~ ^[A-Za-z0-9._/[:space:]-]*$ ]] || die "${where}: base_branches must be branch names separated by spaces, such as dev main, not '${value}'" ;;
      sign_commits)
        [[ "${value}" == true || "${value}" == false ]] || die "${where}: sign_commits must be true or false, not '${value}'" ;;
      merge)
        [[ "${value}" == human || "${value}" == agent ]] || die "${where}: merge must be human or agent, not '${value}'" ;;
      stall_minutes|queue_minutes|codex_minutes|step_up_findings)
        [[ "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: ${key} must be a positive whole number, not '${value}'" ;;
      top_rung_rounds)
        # 1 would hold the first findings round after the lead's reset too, so no findings ever reach the builder.
        [[ "${value}" =~ ^[1-9][0-9]*$ && "${value}" -ge 2 ]] \
          || die "${where}: top_rung_rounds must be a whole number of 2 or more, not '${value}': at 1, every findings round after the lead lifts a top-rung hold would hold it again" ;;
      sonnet_share|escalate_after)
        [[ "${value}" =~ ^(0|[1-9][0-9]*)$ ]] || die "${where}: ${key} must be a non-negative whole number, not '${value}'" ;;
      escalate_ladder)
        # Its models are checked once LADDER_MODELS is defined (model_rank).
        [[ "${value}" =~ ^([a-z0-9.-]+(,[a-z0-9.-]+)*)?$ ]] || die "${where}: escalate_ladder must be models separated by commas, such as sonnet,opus,fable, not '${value}'" ;;
      builder_subagent_model|fallback_reviewer)
        [[ "${value}" =~ ^[A-Za-z0-9._-]*(\[1m\])?$ ]] || die "${where}: ${key} must be a model name such as haiku, not '${value}'" ;;
      goal)
        [[ "${value}" == off || "${value}" =~ ^[1-9][0-9]*$ ]] || die "${where}: goal must be off or a positive whole number of turns, not '${value}'" ;;
      lead)
        [[ "${value}" == off || "${value}" == session ]] || die "${where}: lead must be off or session, not '${value}'" ;;
      merge_admin)
        [[ "${value}" == off || "${value}" == on ]] || die "${where}: merge_admin must be off or on, not '${value}'" ;;
      lead_epics)
        [[ "${value}" == off || "${value}" == on ]] || die "${where}: lead_epics must be off or on, not '${value}'" ;;
      commit_trailers)
        [[ -z "${value}" || "${value}" =~ ^${trailer}([[:space:]]*\;[[:space:]]*${trailer})*$ ]] \
          || die "${where}: commit_trailers must be trailers such as Co-Authored-By: Name <email>, ; between several, not '${value}' (a # starts a comment, so no trailer can hold one)" ;;   # loose-match: ok trailer is a fixed regex
      agent_env)
        # Reserved names are refused once agents.sh, which defines them, is loaded (reserved_env).
        read -r -a words <<< "${value}"   # read, not a bare word list, so a * is never globbed
        for w in ${words[@]+"${words[@]}"}; do
          [[ "${w}" =~ ^[A-Z_][A-Z0-9_]*$ ]] || die "${where}: agent_env: '${w}' is not a variable name ([A-Z_][A-Z0-9_]*)"
        done ;;
      *) die "${where}: unknown key '${key}' (known: ${CONFIG_KEYS})" ;;
    esac
    printf -v "CFG_${key}" '%s' "${value}"
    printf -v "SRC_${key}" '%s' "${where}"
  done < "${CONFIG_FILE}"
}
load_config

# abs_path <path> — <path>, relative to the project dir unless it is absolute.
abs_path() { if [[ "$1" == /* ]]; then echo "$1"; else echo "${PROJECT_DIR}/$1"; fi; }
# board_rel — the board's path from the project root with a trailing /, empty for a board at the root
# (a board outside the repo gives its full path, with the /). Read from BOARD when called, so it
# follows init_project, which resolves BOARD once it has made the board.
board_rel() { [[ "${BOARD}" == "${PROJECT_DIR}" ]] || echo "${BOARD#"${PROJECT_DIR}"/}/"; }
BOARD="$(abs_path "${CFG_board_dir}")"
[[ -d "${BOARD}" ]] && BOARD="$(cd "${BOARD}" && pwd -P)"   # so a board_dir with .. is compared as the real path
REPOS_DIR="$(dirname "${PROJECT_DIR}")"; [[ -z "${CFG_repos_dir}" ]] || REPOS_DIR="$(abs_path "${CFG_repos_dir}")"
PROJECT_IS_GIT=0; [[ -e "${PROJECT_DIR}/.git" ]] && PROJECT_IS_GIT=1
# A builder can change the board in its own PR only when the board is in the project's repo.
BOARD_IN_REPO=0; [[ ${PROJECT_IS_GIT} == 1 && "${BOARD}/" == "${PROJECT_DIR}/"* ]] && BOARD_IN_REPO=1

STATE_DIR="${PROJECT_DIR}/.swarm/state"
# Project rules every builder gets after the standard ones: commit trailers, secrets, ADR rules.
PROJECT_BRIEF="${PROJECT_DIR}/.claude/swarm/brief.md"
PANES_PER_TAB=4

show_config() {
  local key v
  if [[ -n "${1:-}" ]]; then
    case "$1" in
      board_dir) echo "${BOARD}" ;;
      repos_dir) echo "${REPOS_DIR}" ;;
      project) echo "${PROJECT_DIR}" ;;
      *) [[ " ${CONFIG_KEYS} " == *" $1 "* ]] || die "unknown key '$1' (known: project ${CONFIG_KEYS})"
         v="CFG_$1"; echo "${!v}" ;;
    esac
    return
  fi
  echo "project = ${PROJECT_DIR}"
  for key in ${CONFIG_KEYS}; do
    v="CFG_${key}"; local s="SRC_${key}"
    case "${key}" in board_dir) v=BOARD ;; repos_dir) v=REPOS_DIR ;; esac
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
# would get wrong. A listed branch origin has but that will not fetch stops it, never falling back
# to the next. Never a guess.
base_for() {
  local src="$1" b head branches heads
  if [[ -n "${CFG_base_branches// /}" ]]; then
    heads="$(git -C "${src}" ls-remote --heads origin)" || die "${src}: cannot list origin's branches"
    read -r -a branches <<< "${CFG_base_branches}"
    for b in "${branches[@]}"; do
      awk -v r="refs/heads/${b}" '$2 == r { f = 1 } END { exit !f }' <<< "${heads}" || continue
      git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" || die "${src}: cannot fetch ${b}"
      echo "${b}"; return
    done
    die "${src}: origin has none of base_branches (${CFG_base_branches})"
  fi
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
ROLE_GROUPS="design:epic,epic-review,hld,hld-review,hld-lead planning:survey,lead,skeptic,critic,codex building:code,code-risky,code-sonnet,docs,chore,escalate conducting:conduct,review,review-fallback"
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
    hld)        echo "claude fable high" ;;    # co-writes a draft HLD with the user, who waits on every turn
    hld-review) echo "claude fable xhigh" ;;   # attacks the finished HLD draft, its grants first, before it is agreed
    hld-lead)   echo "claude fable xhigh" ;;   # one decomposition decides every epic an HLD becomes
    survey)     echo "claude sonnet high" ;;   # reads and cites; feeds the lead, so not low
    lead)       echo "claude opus xhigh" ;;    # one decomposition decides the whole epic
    skeptic)    echo "claude opus high" ;;     # checks a risk: high story before it is built, and one epic of a /plan-hld plan; the critic checks the rest
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

# LADDER_MODELS: the models a building role runs on, low to high (the policy's). escalate_ladder names
# some of them, each once and rising, so a step-up never steps down or back; a build on a model below
# the ladder's first rung (a chore on haiku) steps to it.
LADDER_MODELS="haiku sonnet opus fable"
# model_rank <model> — how many of LADDER_MODELS come before <model>; fails for any other model.
model_rank() {
  local p=" ${LADDER_MODELS} " w
  [[ "${p}" == *" $1 "* ]] || return 1
  read -r -a w <<< "${p%%" $1 "*}"
  echo "${#w[@]}"
}
_rank=-1
for _m in ${CFG_escalate_ladder//,/ }; do
  # shellcheck disable=SC2154 # load_config assigns it with printf -v
  _r="$(model_rank "${_m}")" \
    || die "${SRC_escalate_ladder}: escalate_ladder: '${_m}' is not one of the models building roles run on (${LADDER_MODELS})"
  (( _r > _rank )) \
    || die "${SRC_escalate_ladder}: escalate_ladder: '${_m}' comes after a model as high or higher; name each model once, from low to high, such as sonnet,opus,fable"
  _rank=${_r}
done

# step_role <role> <model> — the role a step-up from a build of <role> starts on <model>: escalate on
# escalate's model (the ladder's Fable rung); a code build (code-sonnet, code, code-risky) code-sonnet
# on code-sonnet's model and code on any other; any other (docs, chore) its own role, which start_agent
# runs on <model>.
step_role() {
  local m
  read -r _ m _ <<< "$(policy escalate)"
  if [[ "$2" == "${m}" ]]; then echo escalate; return; fi
  case "$1" in
    code|code-sonnet|code-risky) read -r _ m _ <<< "$(policy code-sonnet)"; if [[ "$2" == "${m}" ]]; then echo code-sonnet; else echo code; fi ;;
    *) echo "$1" ;;
  esac
}

# agent_name <name> — the herdr agent name for anything started or waited on. start_agent and
# `wait` both map through here, so every caller agrees: lowercase, [a-z0-9_-], starting with a letter, at most AGENT_NAME_MAX characters.
AGENT_NAME_MAX=32
agent_name() {
  local n
  n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
  [[ "${n}" =~ ^[a-z] ]] || n="s${n}"
  printf '%s' "${n:0:${AGENT_NAME_MAX}}"
}

# cut_record <herdr-name> [names] — the one full name this project's records hold (cut_names; <names>
# is their lines read once, for a caller that asks about many) whose agent name is <herdr-name>. Fails,
# printing nothing: 1 when none does, 2 when more than one does, since names that share their first
# AGENT_NAME_MAX characters share herdr's name, which then never says whose it is.
cut_record() {
  local n c hit="" k=0
  while IFS= read -r n; do
    [[ -n "${n}" ]] || continue
    # A slug, the usual name, is its own agent name up to the cut; only another name pays agent_name's forks.
    if [[ "${n}" =~ ^[a-z][a-z0-9_-]*$ ]]; then c="${n:0:${AGENT_NAME_MAX}}"; else c="$(agent_name "${n}")"; fi
    [[ "${c}" == "$1" ]] || continue
    hit="${n}"; k=$((k + 1))
  done < <(printf '%s\n' "${2-$(cut_names)}" | sort -u)
  [[ ${k} -gt 0 ]] || return 1
  [[ ${k} -eq 1 ]] || return 2
  echo "${hit}"
}

# cut_names — the full names this project's records hold, one a line: the tab records' pane names
# (.swarm/state; a conductor's line names its role, and its brief its name), the briefs'
# (.swarm/briefs/<name>.md; <name>.held-findings.md and the like are a build's other files) and the
# board's stories'. Of .swarm/state it reads the tab records alone, whose names are labels with no
# dot: a file whose name has one is skipped, since codex's brief copies there (brief-<name>.md) hold
# prose that can be shaped like a tab record's line, and codex-review.<pid> markers, .tmp files and
# watch-seen's temporary files are no pane's. An epic named brief-<x> keeps its record brief-<x>,
# with no dot, so only the dot tells them apart. Like own_panes, it reads only lines shaped like a
# tab record, and always succeeds.
cut_names() {
  local f b files=()
  for f in "${STATE_DIR}"/*; do
    b="${f##*/}"
    [[ -f "${f}" && "${b}" != *.* ]] || continue
    files+=("${f}")
  done
  [[ ${#files[@]} -eq 0 ]] \
    || awk 'NF == 2 && $1 ~ /^[A-Za-z0-9]+:[A-Za-z0-9]+$/ && $2 != "conductor" { print $2 }' "${files[@]}" 2>/dev/null || true
  for f in "${PROJECT_DIR}/.swarm/briefs"/*.md "${BOARD}/stories"/*.md; do
    f="${f##*/}"; f="${f%.md}"
    [[ "${f}" == *[.*]* ]] || echo "${f}"
  done
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
# agent_env's names, each checked for its form by load_config, which runs before agents.sh is loaded.
for _key in ${CFG_agent_env}; do
  # shellcheck disable=SC2154 # load_config assigns it with printf -v
  ! reserved_env "${_key}" \
    || die "${SRC_agent_env}: agent_env: ${_key} is reserved: every agent gets it already, herdr or the lead's own session sets it, or it loads code"
done
# INTERVENE_KINDS: the times a person stepped in that intervene logs, and the kinds dash's speedometer
# counts (dash passes them as DASH_INTERVENE_KINDS).
INTERVENE_KINDS="lead-hand user-caught"

# intervene <kind> <line> — log one time a person had to step in: an incident line, target -, outcome
# `<kind>: <line>`, which flow's incidents section counts per day and kind. Its only line: main logs
# none for it (target !), so an unknown kind or an empty line logs nothing. A line that could not be
# written (unwritable, disk full) fails here, not with a logged: that counts nothing.
intervene() {
  [[ "$1" =~ ^[a-z-]+$ && " ${INTERVENE_KINDS} " == *" $1 "* ]] || die "intervene: the kind must be one of ${INTERVENE_KINDS}, not '$1'"
  [[ -n "${2//[[:space:]]/}" ]] || die "intervene: say in one line what happened: swarm.sh intervene $1 \"<one line>\""
  append_event incident - "$1: $2" || die "intervene: could not write ${EVENTS_LOG}; nothing was logged"
  echo "logged: $1: $2"
}

# hold <slug> <why> — log that a conductor held a ready story back: a hold line, target the slug, outcome
# ok (<why>). Its only line, as intervene's (target !), so a slug that is not a ready story logs nothing.
# A story whose last event is reconcile's reopen is refused: a hold line after it would drop the
# (its PR <url> was closed unmerged) mark unblock --startable reads from that event.
hold() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "hold: bad slug '$1': swarm.sh hold <slug> <why>"
  [[ -f "${BOARD}/stories/$1.md" && "$(get_fm "${BOARD}/stories/$1.md" status)" == ready ]] || die "hold: $1 is not a ready story on the board"
  [[ "$(last_event "$1")" != $'reconcile\tok (reopened)' ]] || die "hold: $1's PR was closed unmerged; it is the lead's: list it in your report"
  [[ -n "${2//[[:space:]]/}" ]] || die "hold: say why: swarm.sh hold $1 '<why>'"
  append_event hold "$1" "ok ($2)" || die "hold: could not write ${EVENTS_LOG}; nothing was logged"
  echo "logged: hold $1: $2"
}

# Everything runs from main, called on the last line with `exit` beside it: bash reads a
# script as it executes, so a `git pull` that rewrites this file during a long `wait` would
# otherwise make it resume reading the new file mid-line.
# dispatch <command> [args] — run one command.
dispatch() {
  cmd="${1:-}"; shift || true
  # The lead's first command labels its herdr workspace; the test hooks and lead-stop.sh's _step
  # (whose stderr the hook drops, which would hide a refusal) do not.
  [[ "${cmd}" == _* ]] || lead_rename
  case "${cmd}" in
    policy) policy "${1:?role}" ;;
    agent)  require_herdr; agent_cmd "$@" ;;
    story)  require_herdr; [[ $# -le 2 ]] || die "story: too many arguments: $*"
            if [[ "${1:-}" == --strict ]]; then build_story "${2:?slug}" strict
            elif [[ "${2:-}" == --strict ]]; then build_story "$1" strict
            else [[ -z "${2:-}" ]] || die "story: unknown argument '$2'"; build_story "${1:?slug}"; fi ;;
    conduct) require_herdr; start_conductor "${1:?epic}" ;;
    close)  require_herdr
            if [[ "${*: -1}" == --all ]]; then CLOSE_ALL=1; set -- "${@:1:$#-1}"; fi
            if [[ "${*: -1}" == --drop ]]; then CLOSE_DROP=1; set -- "${@:1:$#-1}"; fi
            [[ "${1:-}" != -* && "${2:-}" != -* ]] || die "close: --drop and --all go last, in that order: swarm.sh close <name> [cause] [--drop] [--all]"
            close_agent "${1:?name}" "${2:-}"
            # A pane close refused (said above) fails the close: nothing was counted, cleared or kept.
            [[ -z "${CLOSE_REFUSED}" ]] || die "close: no pane was closed for $1 (see above), and nothing was counted, cleared or kept" ;;
    # _step-up: ladder_step's, not logged, and a failure after the old builder closed exits STEP_UP_PARTWAY
    step-up|_step-up) require_herdr; [[ "${cmd}" != _step-up ]] || STEP_UP_AUTO=1
            if [[ "${1:-}" == --resume ]]; then step_up_resume "${2:-}"; else step_up "${1:-}" "${2:-}" "${3:-}"; fi ;;
    tell)   require_herdr; tell_agent "${1:?slug}" "${2:-}" "${3:-}" ;;
    # _review-red-scan: wait-pr's, on a red head, under its deadline (review_red_scan); not logged
    _review-red-scan) review_red_scan "${1:?repo}" "${2:?head}" "${3:-}" "${4:-}" ;;
    restart) require_herdr; [[ $# -eq 1 ]] || die "restart: takes one slug (swarm.sh restart <slug>)"; restart_build "$1" ;;
    unblock) if [[ "${1:-}" == --startable ]]; then
               [[ $# -eq 2 && ( "$2" == --backlog || "$2" =~ ^[a-z0-9-]+$ ) ]] || die "unblock: --startable takes <epic> or --backlog"
               unblock_startable "$2"
             else [[ -z "${1:-}" ]] || die "unblock: unknown argument '$1'"; unblock; fi ;;
    next)   timed next next_report ;;
    status) timed status status_report "${1:-}" ;;
    dash)   timed dash dash "$@" ;;
    tidy)   require_herdr; tidy_panes "${1:-}" ;;
    upgrade) require_herdr; upgrade_agents "$@" ;;
    cost)   moved cost "flow's cost section" "flow [--since YYYY-MM-DD] [--until YYYY-MM-DD]" ;;
    outcomes) outcomes_report "$@" ;;
    flow)   flow_report "$@" ;;
    dataset) dataset_report "$@" ;;
    review-yield) moved review-yield "flow's reviewers section" "flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]" ;;
    log-finding) finding_flags "$@"; shift "${FINDING_SKIP}"
            record_finding "${1:-}" "${2:-}" "${*:3}" "${FINDING_OUTCOME}" ${FINDING_REVIEWER+"${FINDING_REVIEWER}"} ;;
    intervene) intervene "${1:-}" "${*:2}" ;;
    hold)   hold "${1:-}" "${*:2}" ;;
    lessons) [[ $# -eq 0 || ( $# -eq 1 && "$1" == --all ) ]] || die "usage: swarm.sh lessons [--all]"
            moved lessons "outcomes' recurring block" "outcomes [--since YYYY-MM-DD]" ;;
    features) moved features "flow's features section" "flow [--since YYYY-MM-DD] [--until YYYY-MM-DD]" ;;
    watch)  watch_prs "$@" ;;
    finish) finish_item "${1:?slug}" ;;
    reset)  reset_story "${1:-}" "${*:2}" ;;
    drop)   drop_story "${1:-}" "${*:2}" ;;
    dialog) dialog_answered "${1:-}" "${2:-}" ;;
    plan-unasked) plan_unasked "$@" ;;
    grants) grants "$@" ;;
    where)  [[ $# -eq 1 ]] || die "where: takes one agent (swarm.sh where <agent>)"
            local out p w t; out="$(agent_where "$1" 2>/dev/null)" || die "where: ${out:-herdr gave a list swarm.sh could not read}"
            IFS=$'\t' read -r p w t <<< "${out}"
            echo "$(agent_name "$1"): pane ${p}, workspace ${w}, tab ${t}" ;;
    swarms) [[ $# -eq 0 ]] || die "swarms: takes no arguments (swarm.sh swarms)"; swarms ;;
    review) mark_review "$@" ;;
    reconcile) reconcile ;;
    merge)  merge_pr "$@" ;;
    dropped-lines) dropped_lines "$@" ;;
    wait-pr) wait_pr "$@" ;;
    board-pr) board_pr "$@" ;;
    findings) findings "${1:?repo}" "${2:?pr}" ;;
    config) show_config "${1:-}" ;;
    init)   case "$*" in
              "") init_project ;;
              --auto-mode-done) auto_mode_done ;;
              *) die "usage: swarm.sh init [--auto-mode-done]" ;;
            esac ;;
    base)   src="$(repo_dir "${1:-}")" || die "${src}"; base_for "${src}" ;;
    codex-review) codex_review "${1:-}" ;;
    review-agent) require_herdr
            case "${1:-}" in
              --next) review_next "${2:-}" "${3:-}" ;;
              --recheck) review_recheck "${2:-}" "${3:-}" "${4:-}" "${@:5}" ;;
              *) review_agent "${1:-}" "${2:-}" ;;
            esac ;;
    _base)  base_for "${1:?repo dir}" ;;                          # test hook: the base branch for a repo
    _role)  role="$(story_role "${1:?slug}")" || die "${role}"; echo "${role}" ;;   # test hook: the role a story is built as
    _name)  agent_name "${1:?slug}"; echo ;;                      # test hook: the agent name for a slug
    _step)  if [[ "${1:-}" == --dash ]]; then a="$(herdr agent list 2>/dev/null)" || a=""; dash_no_agent "${a}"; fi
            next_step ;;                                          # hooks/lead-stop.sh: next's step without the gh calls next_report adds; --dash: dash --check's, its no-agent lines read as dash reads them
    _conductor) conductor_name "${1:?epic or backlog}"; echo ;;   # test hook: a conductor's agent name
    _brief) src="$(repo_dir "$(fm "${BOARD}/stories/${1:?slug}.md" repo)")" || die "${src}"; story_brief "$1" "${src}" main ;;   # test hook: a story's builder brief
    _board-rel) board_rel ;;                                      # test hook: the board's path from the project root
    _target) own_target "$(agent_name "${1:?name}")" ;;          # this project's pane for an agent name, to address herdr by
    _archive) archive_session "${1:?name}" ;;                     # test hook: close's copy of an agent's session log
    _mtime) session_mtime "${1:?name}" ;;                         # test hook: the session-log mtime the stall rule reads
    _trusted) require_trusted "${1:?cwd}"; echo trusted ;;        # test hook: whether Claude Code trusts a folder
    _pane)  require_herdr; next_pane "${1:?tab}" "${2:?cwd}" "${3:-}" ;;   # layout test hook: a pane, no agent
    _tell-queue-check) tell_queue_check "${1:-}" "${2:-}" ;;      # tell_queue_later's check on a busy agent's queued tells
    wait)   wait_command "$@" ;;
    *) awk 'NR > 1 && /^#$/ && ++blank == 2 { exit } NR > 1' "$0"; exit 2 ;;   # the header up to the command list's end
  esac
}

# READ_ONLY_COMMANDS change nothing, so they are not logged: the readers, the waits conductors run
# all the time (wait, wait-pr, watch), and the test hooks (_name ...; _pane opens a pane for a layout test only).
# The lines a read-only command writes are wait's `nudge <name>` and `resume <name>`, one per nudge or API-error resume it sends.
# outcomes (and flow, dataset and dash, which run it) also appends to .swarm/outcomes-prs.tsv, its cache of finished stories' PRs.
# status, next and dash each append one row to .swarm/run-times.tsv (timed), which flow's run_times section reads.
# Every other command is logged (fail closed: a new command is logged until it is named here), and so
# is tidy --yes; tidy alone only lists. A command that is not one (a typo, --help) is not logged.
READ_ONLY_COMMANDS="dash status where swarms next config policy grants cost outcomes flow dataset review-yield features lessons findings wait wait-pr watch dropped-lines base _base _role _name _conductor _brief _board-rel _target _trusted _pane _mtime _step-up _review-red-scan _step _tell-queue-check"

# timed <command> <function> [args] — run the function, then log the run's row in RUN_TIMES_LOG (run_time_end).
# run_time_start <command> — note the run's start, its time and the 1-minute load average then.
# run_time_drop — forget it, so the run logs no row (a watch whose first frame failed).
# run_time_end — append the noted run's row, once: its start (UTC), command, seconds and load (- when
# uptime gives none). dash --watch calls it after its first frame, which never returns. Only the
# status, next and dash arms call these: _step and wait --lead read the board as next does, and log
# nothing. A run that fails before its end logs no row, nor does one with no .swarm/ to log in, or
# dash --project from outside a project, where the cwd stands in (NO_PROJECT). A clock (now_ms) or a
# write that fails is skipped, and never fails the run. A run under
# a timed one (dash --project's frames, dash --check's status, a watch that re-execs itself) is not
# timed: SWARM_RUN_TIMED, exported by the first, marks it. An agent never inherits it (launch_file
# unsets it), though next starts conductors.
RUN_TIMES_LOG="${PROJECT_DIR}/.swarm/run-times.tsv"
RUN_TIME=""
timed() { run_time_start "$1"; shift; "$@"; run_time_end; }
run_time_start() {
  [[ -z "${SWARM_RUN_TIMED:-}" ]] || return 0
  export SWARM_RUN_TIMED=1   # set even outside a project, so the frames it draws stay untimed
  [[ -z "${NO_PROJECT}" ]] || return 0
  local load at ms
  load="$(LC_ALL=C uptime 2>/dev/null | sed -nE 's/.*load averages?: *([0-9.]+).*/\1/p')" || load=""
  at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" && ms="$(now_ms 2>/dev/null)" || return 0
  RUN_TIME="$1 ${at} ${ms} ${load:--}"
}
# shellcheck disable=SC2329 # called from dash_watch, in bin/lib/dash.sh
run_time_drop() { RUN_TIME=""; }
run_time_end() {
  [[ -n "${RUN_TIME}" ]] || return 0
  local cmd at ms load now
  read -r cmd at ms load <<< "${RUN_TIME}"
  RUN_TIME=""
  now="$(now_ms 2>/dev/null)" || return 0
  ms=$((now - ms))
  [[ -d "${RUN_TIMES_LOG%/*}" ]] || return 0
  { printf '%s\t%s\t%d.%03d\t%s\n' "${at}" "${cmd}" $((ms / 1000)) $((ms % 1000)) "${load}" >> "${RUN_TIMES_LOG}"; } 2>/dev/null || true
}

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
# SWARM_CODEX_GRACE overrides it, for tests, when it is a whole number of seconds; anything else is ignored.
[[ ! "${SWARM_CODEX_GRACE:-}" =~ ^[1-9][0-9]*$ ]] || CODEX_GRACE="${SWARM_CODEX_GRACE}"

# tree_pids <pid> — a process and everything under it, children first.
tree_pids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do tree_pids "${c}"; done; echo "$1"; }
# frozen <pid>... — STOP each process and everything under it, and print them all, children first. Each
# pass STOPs the pids it found, then reads the process table once for their children: a parent is
# stopped before the read, so one that loops (a stub's while, codex's own) cannot start a child behind
# it, as it could behind a KILL to its children. Passes go on until a read finds no new child, one per
# level of the tree, but at most FREEZE_PASSES (a process that forks on would hold codex-review for
# good); what the last pass found is KILLed unstopped. kill(2) returns once the STOP is pending, so a
# process on another CPU may fork before it stops. A pid the STOP fails on, one that died in the grace,
# is dropped. Children first, so no stopped child is orphaned (a group of its own gets HUP and CONT then) before its own KILL.
FREEZE_PASSES=20   # ponytail: a tree deeper than this loses what is under its last level; raise it if codex ever nests deeper
frozen() {
  local out="" new="$*" got p i
  for ((i = 0; i < FREEZE_PASSES && ${#new} > 0; i++)); do
    got=""
    for p in ${new}; do kill -STOP "${p}" 2>/dev/null && got="${got} ${p}"; done
    out="${got} ${out}"
    new="$(ps -Ao pid=,ppid= | awk -v have=" ${out} " 'index(have, " " $2 " ") && !index(have, " " $1 " ") { print $1 }')"
  done
  echo "${new} ${out}"
}

# stop_codex <pid> — TERM codex and everything under it, give it CODEX_GRACE seconds, then freeze
# each process left and whatever is under it by then (a TERM trap can start more) and KILL them. The
# tree is read before the TERM, since a child whose parent dies leaves it. Stderr is off, so bash
# prints no "Terminated" line for the job.
stop_codex() {
  local pids
  pids="$(tree_pids "$1")"
  # shellcheck disable=SC2046,SC2086 # one pid per word
  {
    kill -TERM ${pids}
    poll_while "${CODEX_GRACE}" kill -0 ${pids}
    kill -KILL $(frozen ${pids})
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
# goal_condition), and SCOPE_RULE. Fails with no Done when item.
codex_story_prompt() {
  local done_when from_review
  done_when="$(story_items "$2" 'Done when')"
  [[ -n "${done_when}" ]] || return 1
  from_review="$(story_items "$2" 'From review')"
  [[ -z "${from_review}" ]] || from_review=$'\n\nIts From review:\n'"${from_review}"
  # shellcheck disable=SC2016 # the $(...) is for codex to run
  printf 'Review the changes on this branch against origin/%s, committed or not: git diff $(git merge-base origin/%s HEAD) for tracked files, and each untracked file git status --porcelain lists. They implement a story that touches: %s\n\nIts Done when:\n%s%s\n\nReview them against these touches and items. %s' \
    "$1" "$1" "$(fm "$2" touches)" "${done_when}" "${from_review}" "${SCOPE_RULE}"
}

# codex_review <base> — codex's review of the cwd against origin/<base>: no prompt (codex refuses one
# beside --base) and stdin from /dev/null, so it never waits on input. With SWARM_STORY=<slug>, a
# prompt instead of --base (codex_story_prompt), so codex reviews against that story. codex stays in
# the caller's process group, so a harness that kills that group kills codex too (on macOS a KILL to the
# group can miss a child forked while it is sent: STOP the group first). stop_codex stops it
# after codex_minutes (SWARM_CODEX_SECONDS, a whole number of seconds, overrides it, for tests), or when this command is sent
# TERM or HUP, which main_signal sends it on an interrupt and then waits out. The timeout dies, so
# events.tsv's line says so, and it writes a reap line, target codex-<story or base>; otherwise it exits as codex did. codex's output, stderr merged into
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
  left=$((CFG_codex_minutes * 60))
  [[ ! "${SWARM_CODEX_SECONDS:-}" =~ ^[1-9][0-9]*$ ]] || left="${SWARM_CODEX_SECONDS}"
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
    if [[ ${rc} -ne 0 ]] && tail -n 5 "${log}" | grep -Eq "${CODEX_LIMIT_RE}"; then   # loose-match: ok CODEX_LIMIT_RE is a regex
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
  record_event reap "codex-${SWARM_STORY:-$1}" "timed out after ${CFG_codex_minutes} min"
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
  [[ ! -s "${err}" ]] || cat "${err}" >&2   # a brief written with a warning (project_rules: no rules.md)
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
  record_name "${pane}"
}

# record_name <pane> [records] — the name the tab records give <pane>, or nothing; <records> is their
# lines read once, for a caller that asks about many panes.
record_name() { awk -v p="$1" 'NF == 2 && $1 == p { print $2; exit }' <<< "${2-$(cat "${STATE_DIR}"/* 2>/dev/null || true)}"; }

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
# <findings file> in the form codex prints them; review_checklist, with SWARM_STORY's story when set,
# then project_rules, as the review agent's brief carries them.
fallback_brief() {
  # shellcheck disable=SC2016 # the $(...) is for the agent to run
  local diff='Review the changes on this branch against origin/'"$1"', committed or not: git diff $(git merge-base origin/'"$1"' HEAD) for tracked files, and each untracked file git status --porcelain lists.'
  cat <<EOF
codex hit its usage limit, so you review in its place. You are read-only: never edit, commit or push
here, and never merge, by any route. The one file you write is $3.

${2:-${diff}}

$(review_checklist "${SWARM_STORY:+${BOARD}/stories/${SWARM_STORY}.md}")

$(project_rules)

You have no Edit, Write or NotebookEdit tool. When done, write your findings with Bash to $3.tmp,
then mv it to $3 (codex-review waits until that exists): each finding as codex prints one, most severe first, \`- [P<0-3>] <title> — <file>:<line>\` with a line
or two on why under it, or the one line \`No findings.\` when there are none.
EOF
}

# main_signal <INT|TERM|HUP> — stop the logged command at once (it runs in the background, so this
# trap runs as soon as the signal lands; codex-review is waited for while it stops codex, and merge
# while it takes a queued PR out of the queue), log it as
# interrupted, remove the temp file, and die of the same signal, so the exit status stays 128+N.
# shellcheck disable=SC2317,SC2329 # invoked by the signal traps
main_signal() {
  if [[ -n "${EV_CHILD:-}" && "${EV_CMD}" == codex-review ]]; then
    # It stops codex itself (stop_codex, from its tree as it stands), so it alone gets the TERM, and
    # swarm.sh exits only once codex is gone.
    kill -TERM "${EV_CHILD}" 2>/dev/null || true; wait "${EV_CHILD}" || true
  elif [[ -n "${EV_CHILD:-}" ]]; then
    kill_tree "${EV_CHILD}"
    # A merge waiting on a merge queue stops the PR first (queue_merge), and an upgrade tells each
    # conductor it paused to carry on (upgrade_stopped), so both are waited for.
    [[ "${EV_CMD}" != merge && "${EV_CMD}" != upgrade ]] || wait "${EV_CHILD}" || true
  fi
  record_event "${EV_CMD}" "${EV_TARGET#[+!]}" interrupted
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  trap - "$1"
  kill -"$1" "$$"
}

# main <command> [args] — dispatch, and log each command that is not read-only to EVENTS_LOG with its
# outcome: ok, interrupted, the first line of a die at the command's own level, or failed (exit N).
# A die inside a nested $(...) gives only failed (exit N): a caller may have tolerated it, so its
# message could name the wrong failure; it was printed to stderr all the same. reconcile and unblock
# log one line per item themselves, and merge, intervene and hold (target !) every line they write, so main logs none
# for them but an interrupt. A tell's command is tell:<kind>, a close's close:<cause> and a
# board-pr's board-pr:<step>, a review-agent --next's review-agent:next with ok (round <n>) and a --recheck's
# review-agent:recheck, so the target
# stays the slug (a board-pr's name). A reset or drop
# that succeeds logs ok (<reason>), and a review ok (<PR URLs>), so outcomes can tell which PRs an
# epic's review handed over; a reset that lifts a hold (held_for:) logs as reset:held. A tell that sent
# nothing, queued for a busy agent or replaced by a newer one (on its way, or sent or queued since it
# read the agent's state), logs the queued: or replaced: line tell_outcome leaves in the die file, so
# it counts as no round.
main() {
  local rc why a
  [[ "${1:-}" != init ]] || init_check
  EV_CMD="${1:-}"; EV_TARGET=""; EV_OK=""; EV_ERR=/dev/null; EV_CHILD=""
  # upgrade's starter only detaches its worker (SWARM_UPGRADE_WORKER), which logs the run's one event.
  if [[ -z "${EV_CMD}" || " ${READ_ONLY_COMMANDS} " == *" ${EV_CMD} "* || ( "${EV_CMD}" == tidy && "${2:-}" != --yes ) ]] \
     || [[ "${EV_CMD}" == upgrade && "${SWARM_UPGRADE_WORKER:-}" != 1 && " $* " != *" --foreground "* ]] \
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
    merge|intervene|hold) EV_TARGET='!' ;;
    tidy) EV_TARGET=- ;;
    # The slug, which the stall rule reads; the kind goes with the command, and only a real one (the
    # old form, tell <slug> <file>, would put a path there).
    tell) EV_TARGET="${2:-}"; if is_tell_kind "${3:-}"; then EV_CMD="tell:$3"; fi ;;
    # Likewise a close's cause, and only a real one.
    close) EV_TARGET="${2:-}"; if is_close_cause "${3:-}"; then EV_CMD="close:$3"; fi ;;
    upgrade) EV_TARGET=""; for a in "${@:2}"; do [[ "${a}" == --* ]] || EV_TARGET="${a}"; done ;;   # its epic, not --foreground
    reset|drop) EV_TARGET="${2:-}"; EV_OK="ok (${*:3})"
                # Lifting a hold is not the story's one reset, so reset_at must not read it.
                if [[ "${EV_CMD}" == reset && "${2:-}" =~ ^[a-z0-9-]+$ && -f "${BOARD}/stories/$2.md" \
                      && -n "$(get_fm "${BOARD}/stories/$2.md" held_for)" ]]; then EV_CMD="reset:held"; fi ;;
    dialog) EV_TARGET="${2:-}"; EV_OK="ok (${3:-})" ;;
    # --head <sha> is no PR URL: the outcome lists the URLs alone, as without it.
    review) EV_TARGET="${2:-}"; if [[ "${3:-}" == --head ]]; then EV_OK="ok (${*:5})"; else EV_OK="ok (${*:3})"; fi ;;
    board-pr) EV_TARGET="${3:-}"; case "${2:-}" in start|open|done) EV_CMD="board-pr:$2" ;; esac ;;
    story) EV_TARGET="${2:-}"; [[ "${EV_TARGET}" != --strict ]] || EV_TARGET="${3:-}" ;;
    step-up) EV_TARGET="${2:-}"; if [[ "${EV_TARGET}" == --resume ]]; then EV_CMD="step-up:resume"; EV_TARGET="${3:-}"; fi ;;
    # A --next round or a --recheck is no review start, so flow's review-agent starts and review_wait never
    # read it; a recheck that passes counts no round, and one refused with a full round due counts the
    # round its wording nudge did not (review_rounds).
    review-agent) EV_TARGET="${2:-}"
            case "${EV_TARGET}" in
              --next) EV_CMD="review-agent:next"; EV_TARGET="${3:-}"; EV_OK="ok (round $(review_round "${3:-}"))" ;;
              --recheck) EV_CMD="review-agent:recheck"; EV_TARGET="${3:-}" ;;
            esac ;;
    *) EV_TARGET="${2:-}" ;;
  esac
  EV_ERR="$(mktemp "${TMPDIR:-/tmp}/swarm-die.XXXXXX" 2>/dev/null)" || EV_ERR=/dev/null
  EV_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
  elif [[ "${EV_CMD}" == close* ]] && stepped_up_since "${EV_TARGET}" "${EV_START}"; then
    :   # a step-up took the close's place (close_agent): its escalate line ends that build
  elif [[ "${EV_CMD}" == restart ]]; then
    :   # restart_build logged its own ok line, naming how it started the builder
  elif [[ "${EV_CMD}" == tell:* ]] && why="$(head -1 "${EV_ERR}" 2>/dev/null)" && [[ "${why}" == queued:* || "${why}" == replaced:* ]]; then
    record_event "${EV_CMD}" "${EV_TARGET}" "${why}"   # tell_outcome's: nothing sent, so not ok
  elif [[ "${EV_TARGET}" != + ]]; then
    record_event "${EV_CMD}" "${EV_TARGET}" "${EV_OK}"
  fi
  [[ "${EV_ERR}" == /dev/null ]] || rm -f "${EV_ERR}"
  return "${rc}"
}

main "$@"; exit
