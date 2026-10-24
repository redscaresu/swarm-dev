# shellcheck shell=bash

# The outer loop: every review finding someone fixed is logged by kind, so a kind that keeps coming
# back across PRs (outcomes' recurring block) gets a check story.
FINDINGS_LOG_NAME="findings.tsv"
# Who can raise a finding (log-finding --reviewer); ci is a PR review bot, check-run notes or
# code-scanning alerts (swarm.sh findings). fallback is the agent codex-review starts in codex's place
# on a usage limit (fallback_reviewer). skeptic and critic are the plan reviewers, and split-critic
# the check on a large epic's split into child epics, all logging on a board PR; escaped is a defect
# a later fix found in merged work, logged against the original PR. A row logged without --reviewer
# says unknown. The reports read this list as SWARM_FINDING_REVIEWERS.
# A new reviewer a conductor logs also needs its line in finding_rule's mapping and in the story arm
# of commands/swarm.md, which tell whoever logs a finding which value names which reviewer.
FINDING_REVIEWERS="codex fallback code-review ci conductor lead skeptic critic split-critic escaped"
# Why a finding was declined (log-finding --declined <reason>).
FINDING_REASONS="out-of-scope nit wrong"

# finding_flags <args...> — log-finding's flags, which come before the kind in either order: sets
# FINDING_OUTCOME (fixed, declined with --declined, or filed with --filed), FINDING_REASON to --declined's reason (empty
# when the next word is a flag or missing), FINDING_REVIEWER to --reviewer's value (unset without
# one), FINDING_ROUND to --round's value (unset without one) and FINDING_SKIP to how many words the flags took. It checks nothing and never dies, so main
# reads the events target with it before the command runs.
finding_flags() {
  local n
  FINDING_OUTCOME=fixed; FINDING_REASON=""; unset FINDING_REVIEWER FINDING_ROUND; FINDING_SKIP=0
  while [[ "${1:-}" == --declined || "${1:-}" == --reviewer || "${1:-}" == --filed || "${1:-}" == --round ]]; do
    n=1
    # shellcheck disable=SC2034 # read in another file
    if [[ "$1" == --filed ]]; then FINDING_OUTCOME=filed
    elif [[ "$1" == --round ]]; then FINDING_ROUND="${2-}"; [[ $# -lt 2 ]] || n=2
    elif [[ "$1" == --declined ]]; then
      FINDING_OUTCOME=declined
      [[ $# -lt 2 || "$2" == --* ]] || { FINDING_REASON="$2"; n=2; }
    else FINDING_REVIEWER="${2:-}"; [[ $# -lt 2 ]] || n=2; fi
    shift "${n}"; FINDING_SKIP=$((FINDING_SKIP + n))
  done
}

# record_finding <kind> <pr-url> <text> <fixed|declined|filed> [reviewer] — log one finding, what became of
# it and who raised it: one of FINDING_REVIEWERS, or unknown when it is left out. A declined one's
# reason (one of FINDING_REASONS) comes from finding_flags' FINDING_REASON. A row is date, kind, PR,
# text, outcome, reviewer, and a declined row adds the reason; with --round (finding_flags'
# FINDING_ROUND: the review round, 0 for a plan or board PR) an eighth field holds it, after an empty
# reason on a row that has none. Rows from before the outcome column have four fields and were all
# fixed, rows from before the reviewer column have five, and rows from before the round column (or
# logged without --round) are round unknown. An escaped defect's outcome is escaped, so outcomes and
# flow's reviewers, which count what review raised, leave it out; outcomes' recurring block and dash count fixed and escaped rows, never declined ones. A
# filed row (a declined out-of-scope finding the lead filed as a story) is counted by none of them: it
# only stops out_of_scope_findings offering that text again.
record_finding() {
  local kind="$1" pr="$2" text="$3" outcome="$4" reviewer="${5-unknown}" reason="" round=""
  [[ -n "${kind}" && -n "${pr}" && -n "${text//[[:space:]]/}" ]] \
    || die "usage: swarm.sh log-finding [--declined <reason> | --filed] [--reviewer <who>] [--round <n>] <kind> <pr-url> <one line>"
  # A defect review missed is no finding review raised: its own outcome keeps it out of their counts.
  if [[ "${reviewer}" == escaped ]]; then
    [[ "${outcome}" == fixed ]] || die "an escaped defect is fixed, never declined or filed: drop --${outcome}"
    outcome=escaped
  fi
  if [[ "${outcome}" == declined ]]; then
    [[ "${FINDING_REASON:-}" =~ ^[a-z-]+$ && " ${FINDING_REASONS} " == *" ${FINDING_REASON} "* ]] \
      || die "--declined needs a reason, one of: ${FINDING_REASONS}"
    reason=$'\t'"${FINDING_REASON}"
  fi
  if [[ -n "${FINDING_ROUND+set}" ]]; then
    [[ "${FINDING_ROUND}" =~ ^[0-9]{1,3}$ ]] || die "--round needs the review round, a number (0 for a plan or board PR)"
    round=$'\t'"${FINDING_ROUND}"; [[ -n "${reason}" ]] || reason=$'\t'
  fi
  [[ $# -lt 5 || ( "${reviewer}" =~ ^[a-z-]+$ && " ${FINDING_REVIEWERS} " == *" ${reviewer} "* ) ]] \
    || die "reviewer '${reviewer}' must be one of: ${FINDING_REVIEWERS}"
  [[ "${kind}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#kind} -le 32 ]] \
    || die "kind '${kind}' must be short kebab-case (32 characters at most), like vacuous-test"
  text="${text:0:200}"
  [[ "${pr}" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+(/[^[:space:]]*)?$ || "${pr}" =~ ^[^/#[:space:]]+/[^/#[:space:]]+#[0-9]+$ ]] \
    || die "pr '${pr}' must be a PR URL or owner/repo#N, so the same PR always counts once"
  mkdir -p "${PROJECT_DIR}/.swarm"
  printf '%s\t%s\t%s\t%s\t%s\t%s%s\n' "$(date +%F)" "${kind}" "${pr//[$'\t\n\r']/ }" "${text//[$'\t\n\r']/ }" "${outcome}" "${reviewer}" "${reason}${round}" \
    >> "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}"
  echo "recorded ${kind} (${outcome})"
}

# out_of_scope_findings — the findings declined as out-of-scope in the last IDLE_FINDING_DAYS days,
# newest first, as "<date> <kind> <pr>: <text>": the swarm's own follow-ups, which idle_lines offers.
# A text is listed once, and only while its newest row is that decline: the lead's log-finding
# --filed once it files one as a story (commands/swarm.md), or a later fixed row, drops it. That
# record works wherever the board is and whatever the story says. In case the lead did not log it,
# a story that carries the text also drops it: one on the board, or, when the board is in a git
# repo, one any branch (an open board PR's too) added or removed since the finding's day.
IDLE_FINDING_DAYS=30
out_of_scope_findings() {
  local since text day line git=""
  since="$(date -v-"${IDLE_FINDING_DAYS}"d +%F 2>/dev/null || date -d "${IDLE_FINDING_DAYS} days ago" +%F)"
  git -C "${BOARD}" rev-parse -q --git-dir >/dev/null 2>&1 && git=1
  while IFS=$'\t' read -r text day line; do
    grep -qsF -- "${text}" "${BOARD}"/stories/*.md && continue
    [[ -z "${git}" || -z "$(git -C "${BOARD}" log --all -1 --since="${day} 00:00" -S"${text}" --format=%h -- stories 2>/dev/null)" ]] || continue
    printf '%s\n' "${line}"
  done < <(awk -F'\t' -v s="${since}" '{ t[NR] = $4; last[$4] = NR }
    $5 == "declined" && $7 == "out-of-scope" && $1 >= s { r[NR] = $1 " " $2 " " $3 ": " $4; d[NR] = $1 }
    END { for (i = NR; i > 0; i--) if ((i in r) && last[t[i]] == i) print t[i] "\t" d[i] "\t" r[i] }' "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" 2>/dev/null || true)
}

# bin/lib/report.py: what the reports share (each python imports it), so they agree.
#   pr_key(pr) is one PR however it was written: https://github.com/o/r/pull/12[/...], o/r#12, or as given.
#   session_log(projects, session[, archive]) is a session's .jsonl under Claude Code's projects dir,
#   or "". With archive (a project's .swarm/sessions), a session whose log Claude Code deleted falls
#   back to archive_session's gzip copy there; only reports pass it, never a liveness check.
#   log_lines(path) is either one's lines as text; a damaged copy reads as the lines before the damage.
#   finding_rows(path[, outcomes]) is findings.tsv's well-formed rows as (date, kind, pr, text, outcome,
#   reviewer) whose outcome is one of outcomes (fixed and declined: what review raised, so an escaped
#   row is not one); a row from before the outcome column is "fixed", and one from before the reviewer
#   column "unknown".
#   A reviewer is one of SWARM_FINDING_REVIEWERS (bash's FINDING_REVIEWERS, which every report that
#   reads findings passes) or unknown. Fields past the sixth (a declined row's reason, the round) are
#   ignored, so a column appended later drops no row; width=8 keeps those two, "" where a row has none. fixed_rows(path) is the first four fields of the fixed and
#   escaped ones: both are a mistake someone fixed.
#   turns(path, seen) is each of one session's turns, once, as (record, model, tokens, est. USD).
#   session_usage(path, seen) is one session's (input, cache write, cache read, output) tokens, est.
#   USD and models, from Claude Code's own log, skipping (and adding to seen) message ids already counted.

# cost_report <YYYY-MM-DD> — flow's cost section alone, since that day, for dash's cost of the day.
# No calling session: dash runs every project's frame from one pane, and that session is no
# project's own (a lead's is already in its project's Claude Code directory).
cost_report() {
  flow_sections "$1" 9999-12-30 "" "" "" cost
}

# A finished story's PR rows, read once: its file off the board, every PR merged or closed and every
# check on them completed, they never change. Each line <slug> TAB <its newest build's day>/<builds that day> TAB <prs>
# (outcomes' join), so a rebuild reads gh again; per story gh was flow's and dash's top GraphQL caller,
# at one gh pr list per story ever built on every run (dataset still lists each merged story's own).
OUTCOMES_PRS_CACHE="${PROJECT_DIR}/.swarm/outcomes-prs.tsv"
# The other finished GitHub records outcomes and flow read (bin/lib/gh_cache.py); SWARM_GH_CACHE set
# empty turns both caches off. GH_FRESH (flow --no-cache) reads neither, and writes what gh answers over them.
GH_CACHE="${SWARM_GH_CACHE-${PROJECT_DIR}/.swarm/gh-cache}"
GH_FRESH=""

# outcomes [--since YYYY-MM-DD] — one TSV row per builder agent in agents.tsv, joining what the logs
# already hold: the story it built (slug, kind, risk), its model and effort, its cost, the tells it
# took by kind (findings, nudge, resume; a refused tell never reached it, so is not counted), the closes, the findings fixed on its PR, how the PR ended, and which attempt at the slug it was.
# Then when it started (its session log's first timestamp, UTC), its tokens by type, its last close's
# cause, the times of its escalation steps (escalate, dialog with its answer, escalated, reset,
# drop), then its story's epic:, when its PR merged, whether any PR of the story merged (empty when
# unknown), the findings declined, both counts by reviewer, when its PR was created, the minutes from
# its start to that and from that to the merge, the commits on the PR that merge the base into it,
# its subagents' cost, in all and per model (its own cost and tokens leave them out), its
# start-to-merge minutes split into building, CI, review wait, fixing and merge wait (outcomes_join.py's
# time_in_state, from its PR's review and tell:findings events and its head's checks), and last rework
# (report.py's rework_of over every merged PR of the builds' repos, from one gh list: 1 when a later fix
# reworked its merged PR, on the latest build on it, once 7 days have passed; empty when gh failed), then on a story's first build the minutes it waited ready under the
# conductor run it started in (held), and its whole wait from ready to start (ready_wait). A finding goes to the latest build on
# its PR that started on or before its day, so builds sharing a PR never count it twice. Each events.tsv line goes to one build: an escalation step to the escalate build whose cycle
# was open when it was logged (by event order), any other to the build that started last at or before
# it. A build with no session log starts at 00:00 local time on its agents.tsv day.
# A build's PR is the last of the slug's PRs its session log names, so each attempt keeps its own;
# with no log, the slug's PR when it has exactly one.
# agents.tsv cuts names at 32 characters, so the slug is the session's worktree (its cwd's last part),
# read from close's copy of the session log once Claude Code deleted it.
# shellcheck disable=SC2120 # another file's callers pass it
outcomes_report() {
  local since="" rows meta="" slug text kind from src prs story_epic got asked finished built
  [[ -z "${1:-}" || ( "$1" == --since && "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ) ]] \
    || die "usage: swarm.sh outcomes [--since YYYY-MM-DD]"
  [[ -z "${1:-}" ]] || since="$2"
  [[ -f "${AGENTS_LOG}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  # date, slug, role, model, effort, cost_usd, tokens, tells_findings, tells_nudge, tells_resume, closes, attempts,
  # pulls (the github pull URLs its session log names, or - when there is no log to read), then the
  # columns the report prints after attempts as they are: started to drop_at, then subagent_cost_usd and
  # subagent_cost_by_model, which it prints last.
  rows="$(SWARM_ESCALATE_MODEL="$(policy escalate | cut -d' ' -f2)" python3 "${SWARM_HOME}/bin/lib/outcomes_rows.py" "${AGENTS_LOG}" "${EVENTS_LOG}" "${since:-0000-00-00}" \
    "${CLAUDE_PROJECTS}" "${BUILDER_ROLES}" "${SESSIONS_DIR}")" || die "outcomes: reading the logs failed"
  # Per slug: kind (an escalated story's kind: lead is its escalated_from:), risk, every PR of
  # story/<slug> (newest first, as `url state mergedAt createdAt main_merges checks commits closedAt` joined by commas, where
  # main_merges counts the commits whose headline merges the base into the PR: `Merge origin/main into
  # x`, `Merge branch 'main' into x`, `Merge remote-tracking branch 'origin/main' into x`, and checks is
  # its head's check runs as startedAt/completedAt joined by semicolons, commits the committedDate of
  # its commits but those base merges, joined by semicolons), its epic: and
  # whether gh answered (1, or empty), from the story (on the board, or its last version in git once a
  # merge deleted it) and gh. A gh that fails leaves no PR; it never fails the run. A story that is gone (its PRs may still show) or has no repo is unknown too.
  while IFS= read -r slug; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    text="$(story_text "${slug}")"; prs=""; asked=""
    # A story on the board: kind: and escalated_from: through fm, its state file first.
    if [[ -f "${BOARD}/stories/${slug}.md" ]]; then
      kind="$(fm "${BOARD}/stories/${slug}.md" kind)"; from="$(fm "${BOARD}/stories/${slug}.md" escalated_from)"
    else
      kind="$(sed -n 's/^kind: *//p' <<< "${text}" | head -1)"; from="$(sed -n 's/^escalated_from: *//p' <<< "${text}" | head -1)"
    fi
    [[ -z "${text}" ]] || kind="${kind:-code}"
    [[ "${kind}" != lead || -z "${from}" ]] || kind="${from% (default)}"
    story_epic="$(sed -n 's/^epic: *//p' <<< "${text}" | head -1)"
    finished=""; [[ -f "${BOARD}/stories/${slug}.md" || -z "${text}" ]] || finished=1
    # The cache's key: its newest build's agents.tsv day and the builds that day, `<day>/<count>`, so a
    # rebuild changes it, with or without a session log; --since never drops the newest day's builds.
    built="$(awk -F'\t' -v s="${slug}" '$2 == s { if ($1 > m) { m = $1; c = 0 } if ($1 == m) c++ } END { if (m != "") print m "/" c }' <<< "${rows}")"
    # shellcheck disable=SC2016 # $b is jq's
    if [[ -n "${finished}" && -n "${GH_CACHE}" && -z "${GH_FRESH}" ]] && prs="$(awk -F'\t' -v s="${slug}" -v k="${built}" '$1 == s && $2 == k { print $3; f = 1; exit } END { exit !f }' "${OUTCOMES_PRS_CACHE}" 2>/dev/null)"; then
      asked=1
    elif src="$(repo_dir "$(sed -n 's/^repo: *//p' <<< "${text}" | head -1)")" \
      && got="$( (cd "${src}" && gh pr list --head "story/${slug}" --state all \
        --json url,state,mergedAt,createdAt,baseRefName,commits,statusCheckRollup,closedAt --jq 'def base_merge($b): .messageHeadline | startswith("Merge ") and ((ltrimstr("Merge ")
          | ltrimstr("remote-tracking ") | ltrimstr("branch ") | split(" ")[0] | ltrimstr("\u0027") | rtrimstr("\u0027")
          | ltrimstr("origin/")) == $b);
        .[] | .baseRefName as $b | [.url, .state, .mergedAt // "", .createdAt, ([.commits[] | select(base_merge($b))] | length),
          ([.statusCheckRollup[]? | select(.startedAt and .completedAt) | .startedAt + "/" + .completedAt] | join(";")),
          ([.commits[] | select(base_merge($b) | not) | .committedDate] | join(";")), .closedAt // "",
          ([.statusCheckRollup[]? | select((.status != null and .status != "COMPLETED") or .state == "PENDING" or .state == "EXPECTED")] | length)] | @tsv') 2>/dev/null)"; then
      prs="$(cut -f1-8 <<< "${got}" | tr '\t' ' ' | paste -sd, -)"; asked="${text:+1}"
      # One short line, in place of the slug's last one (renamed over the file, so a parallel run never
      # reads half of it, and at worst drops a line that is read from gh again), once no PR is open and
      # no check runs (the 9th field): a human merge past a pending check, or a step-up closing mid-CI,
      # would keep the gap.
      if [[ -n "${finished}" && -n "${prs}" && -n "${GH_CACHE}" ]] && awk -F'\t' '$2 == "OPEN" || $9 > 0 { o = 1 } END { exit o }' <<< "${got}"; then
        # Best effort: a read-only report never fails on a write it does only to save a gh call.
        { mkdir -p "${OUTCOMES_PRS_CACHE%/*}" && [[ ! -d "${OUTCOMES_PRS_CACHE}" ]] \
          && { awk -F'\t' -v s="${slug}" '$1 != s' "${OUTCOMES_PRS_CACHE}" 2>/dev/null || true
               printf '%s\t%s\t%s\n' "${slug}" "${built}" "${prs}"; } > "${OUTCOMES_PRS_CACHE}.$$" \
          && mv -f "${OUTCOMES_PRS_CACHE}.$$" "${OUTCOMES_PRS_CACHE}" || { rm -f "${OUTCOMES_PRS_CACHE}.$$"; false; }; } 2>/dev/null \
          || echo "swarm: outcomes: cannot write ${OUTCOMES_PRS_CACHE}; ${slug}'s PRs are read from gh again next run" >&2
      fi
    fi
    meta+="${slug}"$'\t'"${kind}"$'\t'"$(sed -n 's/^risk: *//p' <<< "${text}" | head -1)"$'\t'"${prs}"
    meta+=$'\t'"${story_epic}"$'\t'"${asked}"$'\n'
  done <<< "$(cut -f2 <<< "${rows}" | sort -u)"
  # SWARM_REWORK_SINCE: flow's --since, which bounds rework's gh search (outcomes' own --since otherwise).
  SWARM_REWORK_SINCE="${SWARM_REWORK_SINCE:-${since}}" \
    SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" SWARM_META="${meta}" SWARM_ROWS="${rows}" SWARM_BACKLOG_CONDUCTOR="$(conductor_name backlog)" \
    SWARM_GH_CACHE="${GH_CACHE}" SWARM_GH_FRESH="${GH_FRESH}" python3 "${SWARM_HOME}/bin/lib/outcomes_join.py" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${BOARD}" "${EVENTS_LOG}"
}

# dataset — write .swarm/dataset.jsonl, one JSON line per finished story (a PR of story/<slug> merged),
# for scoring the planner (flow's predictions). inputs: the story as the board PR merged it (text, kind,
# risk, touches, depends_on, estimate_lines, easy) and planner_model, the model of the agents.tsv lead
# whose session log names .swarm/<epic>/lead.json. results, from gh, outcomes, events.tsv, findings.tsv
# and git: its newest merged PR and merged_at, diff_lines and diff_files of what that PR merged into the
# default branch (a squash, merge commit or rebase, from gh's merge commit; the story and epic files it
# deletes left out; null when git cannot find it), attempts (builds), findings_rounds (tells of findings),
# substantive_findings (fixed), rework (outcomes' rework column on any of its PRs, as model_fit reads
# it; null when outcomes could not judge one, or one merged in the last REWORK_DAYS),
# cost_usd (subagents included), minutes from the first build's start to the merge, models (each
# build's, in order) and escalations (each ok escalate line: its trigger, and step-up's from and to).
# was_easy (was_easy_rule 1): one build, at most one findings round, no rework and a diff under 100
# lines; null when an unknown diff or rework is all that could decide it. Model names, counts and the story text only: no environment and no
# transcript text. A story whose repo cannot be found is skipped (counted on stderr) and keeps its line
# from the last run; when outcomes or gh fails, it dies and leaves the file as it was.
dataset_report() {
  [[ $# -eq 0 ]] || die "usage: swarm.sh dataset"
  [[ -f "${AGENTS_LOG}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  local out="${PROJECT_DIR}/.swarm/dataset.jsonl" rows prs="" slug merged text src got line skipped=0 gh_up=""
  local down="dataset: gh is not answering (see gh auth status); ${out} is left as it was"
  # Into a variable first: a failure inside a pipeline's $(...) would be lost, and the file emptied.
  # shellcheck disable=SC2119 # takes no argument here
  rows="$(outcomes_report)" || die "dataset: outcomes failed; ${out} is left as it was"
  rows="$(sed '/^$/,$d' <<< "${rows}")"   # the rows, without the recurring kinds after them
  # Per slug, outcomes' story_merged: true or false when gh answered, empty when it did not or the
  # story's repo could not be found (told apart here, as repo_dir runs before gh). A story gh cannot
  # read (its GitHub repo deleted, archived or moved) is skipped like one with no repo, unless gh
  # itself is down (gh auth status fails, asked once): then the run stops.
  while IFS=$'\t' read -r slug merged; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    text="$(story_text "${slug}")"
    # No story to read (neither on the board nor in its history): counted, never dropped in silence.
    if [[ -z "${text}" ]]; then skipped=$((skipped + 1)); continue; fi
    if ! src="$(repo_dir "$(sed -n 's/^repo: *//p' <<< "${text}" | head -1)")"; then skipped=$((skipped + 1)); continue; fi
    if [[ -z "${merged}" ]]; then
      [[ -n "${gh_up}" ]] || { gh auth status >/dev/null 2>&1 && gh_up=yes || gh_up=no; }
      [[ "${gh_up}" == yes ]] || die "${down}"
      skipped=$((skipped + 1)); continue
    fi
    [[ "${merged}" == true ]] || continue
    # shellcheck disable=SC2016 # jq's
    if ! got="$( (cd "${src}" && gh pr list --head "story/${slug}" --state merged --json url,mergedAt,mergeCommit,commits \
      --jq '.[] | [.url, .mergedAt, .mergeCommit.oid // "", ([.commits[].messageHeadline | gsub("[\t\n\r]"; " ")] | join("\u0001"))] | @tsv') 2>/dev/null)"; then
      [[ -n "${gh_up}" ]] || { gh auth status >/dev/null 2>&1 && gh_up=yes || gh_up=no; }
      [[ "${gh_up}" == yes ]] || die "${down}"
      skipped=$((skipped + 1)); continue
    fi
    while IFS= read -r line; do
      [[ -z "${line}" ]] || prs+="${slug}"$'\t'"${src}"$'\t'"${line}"$'\n'
    done <<< "${got}"
  done <<< "$(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "story_merged") c = i; next } { m[$2] = $c } END { for (s in m) print s "\t" m[s] }' <<< "${rows}" | sort)"
  [[ ${skipped} -eq 0 ]] || echo "dataset: skipped ${skipped} stories whose story, repo or PRs could not be read; their lines from the last run stay" >&2
  mkdir -p "${PROJECT_DIR}/.swarm"
  SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" SWARM_ROWS="${rows}" SWARM_PRS="${prs}" python3 "${SWARM_HOME}/bin/lib/dataset.py" \
    "${BOARD}" "${AGENTS_LOG}" "${EVENTS_LOG}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${CLAUDE_PROJECTS}" "${SESSIONS_DIR}" "${out}"
}

# flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] — the project's numbers, one section
# per bin/lib/flow_<name>.py in name order, each under `## <name>` (flow_report.py runs them):
#   ci_health: one TSV row over the github.com PRs of the outcomes rows dated in the window (with
#     --epic, its own; without --since, the 30 days up to --until or today, said in a line above it):
#     the median minutes per head SHA from its first run created to its last updated, red runs
#     (failure, timed_out or startup_failure) per PR and flakes (a red run, then a green one of the
#     same workflow and event on that head, a rerun's earlier attempts read from gh api), from gh's
#     runs of each PR's branch whose head is one of its commits (all over REST, not GraphQL). A PR
#     a gh call fails on or takes over 10 s for (a reset connection or a 5xx tried 3 times; after an
#     hourly rate limit, no more calls) is left out, and a line says how many, then one each names
#     it, the call and gh's error. Then, per repo, a PR's CI time (its newest
#     head's longest run, from its last attempt's start, and that run's slowest job, from that
#     attempt's jobs listing less those a rerun carried over, its control characters dropped): its PRs, the median minutes, of the
#     jobs that were a PR's slowest the one with the highest median minutes and that median, the same
#     for the window of as many days before it (a PR built in both counts in the later), and the
#     change in minutes. A PR gh cannot read is left out, and a line says how many (and how many of
#     the window's own), then a line each names it and the error that dropped it. Last (after the CI
#     time table, so its reads never starve it), TSV test_file flaky_runs last_seen example_run, when any: the
#     test.sh FAIL or TIMEOUT tests/<file> lines of each flaky run's red attempts (a red attempt a green one on
#     the same head, workflow and event follows, as flakes counts them), from gh run view --log-failed
#     (a byte that is not UTF-8 read as U+FFFD), a file once per run, worst first, over the runs created in the window in the repos of the window's PRs
#     and the project's origin (one gh api call each, more when GitHub cuts a listing at its 1000; with the cache, only from 3 days before the newest cached run on, and the days a cut listing left out; with --epic, its PRs' runs), at most 100 gh
#     invocations (not REST requests) and none past the hourly rate limit, with flaky tests: lines for what was cut, left out or unparsed,
#     or that none was flaky. dash's ci line is its origin repo's row of the CI time table of
#     `flow --since <6 days ago>`, run with SWARM_CI_TIME_ONLY, which skips the health row and the
#     flaky tests.
#   cost: tokens and estimated cost per role, for every agent this project's swarm started in the
#     window, and as "lead" the calling session when run inside herdr plus every session in the
#     project's own Claude Code directory that agents.tsv does not name (by its first timestamp's
#     local day). Usage comes from Claude Code's own session logs (or close's copy, once Claude Code
#     deleted one), deduplicated by session and message id; codex agents are listed but not priced.
#   epic_totals: one TSV row per epic, then `all`, over the outcomes rows dated in the window; with
#     --epic, that epic's row alone. builds, cost_usd and start_to_pr_min summed over its builds, and
#     per PR (counted once): pr_to_merge_min summed, merged_prs (merged, with main_merges gh read), main_merged
#     (main_merges above 0) and main_merged_share, then a line with leaner-faster-swarm's 55% baseline.
#     cost_usd ends `(N not in the logs)` for builds with no cost, as cost's agents do.
#   features: the project's own docs/features.tsv (or SWARM_FEATURES; with neither, one line saying
#     there is no feature list) joined with this project's logs: per feature, its uses from --since
#     (default the 30 days up to --until, or up to today) to --until, its metric and its baseline, and `delete?` for a feature with no
#     metric, or with logged uses and none in the last 30 days. A feature still settling in is never
#     stale: one that landed within the last 30 days, or whose landed is an epic still on the board.
#     Both are read in the features file's own repo (the parent of its directory), where its PRs and
#     epics are: a #PR landed on the day of the oldest commit whose subject ends `(#N)`, and an epic is
#     on the board while <board_dir>/epics/<name>.md is there (board_dir from that repo's
#     .claude/swarm/config), and landed the day git log shows it deleted. An epic with neither, or a
#     landed that cannot be read (a warning on stderr), is judged by its uses. A use is an ok
#     events.tsv line (by its local day) of an `event:<command>` (or <command>:<anything>), an
#     agents.tsv line of a `role:<role>` or `agent:<name>`, or a findings.tsv row of a
#     `reviewer:<who>`. An `unlogged: <why>` feature (a read-only command leaves no events line)
#     shows `-` and is judged on its metric alone.
#   gh_calls: TSV hour api role runs many share, bin/gh-shim's .swarm/gh-calls.tsv lines per local hour
#     in the window and budget (graphql or rest), an all row then one per caller's agents.tsv role
#     (an unknown agent as itself, - outside any agent), most first, with the runs that paginate or
#     watch and the share of 5000; then, after a blank line, the same per subcommand (via swarm.sh
#     <command> when swarm.sh ran it). Runs, not requests, so the share is a floor. A line instead
#     when there is no log or none in the window. --epic does not narrow it.
#   holds: TSV story epic reason held_min, one row per hold of a ready story (its first hold line in
#     events.tsv to its next ok story line; dropped or removed (its story file deleted) when it
#     ended with no build; else open), then the built holds' minutes per reason class (clash or other), or a line
#     when there is no hold in the window.
#   incidents: TSV day kind incidents, the incident lines in events.tsv per local day in the window
#     and kind (the outcome before its first colon), whatever the kind; --epic does not narrow it.
#   lead_queue: TSV day items median_min max_min open, per local day an item entered the lead's queue
#     (an ok held, escalated, close:impossible or review line in events.tsv; with merge = agent, a
#     review only of a story whose costs: is not none, or that cannot be read) the minutes until its
#     slug's next ok finish, reset, drop or reconcile (finished or reopened), stopping at the local
#     midnight after --until (or now), where an item still waiting is listed under open as kind:slug. One with no
#     leaving line counts only while its story or epic is on the board in review, held or escalated.
#     --epic does not narrow it.
#   merge_ins: TSV cause merge_ins prs, why the PRs epic_totals counts under main_merged merged their
#     base in (without --since, the 30 days up to --until or today): each merge-in (a PR commit gh's
#     REST API lists whose headline merges the base in, by outcomes' main_merges rule) re-merged from
#     its parents with git merge-tree in its story's repo, fetching refs/pull/<n>/head once when it is
#     not there, as conflict (a conflict, or a tree that is not git's clean merge), behind (clean, and
#     the base had commits the branch lacked) or neither; unread for a PR gh cannot read, a merge-in gh
#     does not list, a commit git cannot find, a merge-in whose git log, merge-tree, diff or merge-base
#     fails, or a one-parent "merge", each named on a `merge ins: left out` line. Then, after a blank
#     line, TSV file conflicts: the top three files, or `none conflicted`.
#   reviewers: what review yields, for tuning the reviewers. Block 1 (TSV reviewer kind raised fixed
#     declined decline_rate rework): findings.tsv rows dated in the window, per reviewer (its `all` row, then
#     its kinds by declined, most first), per kind across reviewers (`all <kind>`), and last `all
#     all`; rework is the PRs a line raised findings on in the window that outcomes' rework marks. Block 2, after a blank line (TSV prs rounds rounds_per_pr max_rounds): the tells_findings
#     of every outcomes row with a PR dated in the window, summed per PR. A tell names no reviewer, so
#     rounds are not split by one. Once a row in the window has a round (log-finding --round), two
#     more blocks: TSV round reviewer fixed declined nit out-of-scope wrong share_fixed, per round
#     (0 a plan or board PR, unknown a row with none) each reviewer then all; and TSV story pr
#     stopped_round why, per story PR with a round from 1 on, its last logged round and why it stopped
#     there: pass (that round fixed nothing), merged-after-fixes or fixed-unmerged. --epic keeps only
#     the PRs of that epic (outcomes epic column) in every block, and a last block lists every PR
#     block 1 or 2 counted.
#   throughput: one TSV row per epic, then `all` for the project, over the outcomes rows dated in the
#     window and the ok events.tsv lines whose local day is in it; with --epic, that epic's row alone.
#     builds; builders_mean and builders_max, how many builds ran at once, time-weighted over the span
#     from the first build's start to the last one's end: a build runs from its outcomes started
#     (without one, 00:00 local on its agents.tsv day, or when its slug's previous build ended if
#     later) to its first close after that which no earlier build of its slug took, before its slug's
#     next build with a known start, else its session log's last entry, and never past --until's local
#     midnight; stories (its builds' slugs), the longest depends_on chain among them (read with
#     story_text, so merged stories count) and stories_per_chain; review_wait_min, the mean minutes
#     from each PR's createdAt (gh) to the first review-agent event for its slug (before the slug's
#     next PR, if a retry opened one); for a PR with none, proxy_review_wait_min, the same to its first
#     tell:findings or review, which marks a review's end, so the two are never averaged together; and
#     stacked, the stacked events for its slugs (all of them on the `all` row). A PR gh cannot read
#     counts in neither wait.
#   time_in_state: one TSV row per epic, then `all`, over the outcomes rows dated in the window with
#     phase minutes (a merged PR), each PR once by its first build; with --epic, that epic's row alone:
#     its PRs, the hours in all six states (the five phases, and held: each of those PRs' stories'
#     held_min once), and each state largest first as <state>:<hours>h/<share of those hours>%; then
#     ready_wait's median and p90 minutes over the first builds dated in the window, merged or not.
# A new section is a new flow_<name>.py; neither this nor flow_report.py changes. It writes nothing but
# its gh calls' lines in .swarm/gh-calls.tsv (bin/gh-shim's log), its cache of finished GitHub records
# (GH_CACHE, bin/lib/gh_cache.py; --no-cache reads them all from gh again and rewrites them), the PR heads merge_ins
# fetches and the trees and blobs its git merge-tree writes into each repo.
# SWARM_FLOW_SECTIONS (section names, space-separated) runs those alone: dash's ci line runs ci_health.
FLOW_USAGE="usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]"
flow_report() {
  local since="" until="" epic="" rows=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "${FLOW_USAGE}"; since="$2"; shift 2 ;;
      --until) [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "${FLOW_USAGE}"; until="$2"; shift 2 ;;
      --epic) [[ "${2:-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "${FLOW_USAGE}"; epic="$2"; shift 2 ;;
      --no-cache) GH_FRESH=1; shift ;;
      *) die "${FLOW_USAGE}" ;;
    esac
  done
  # Real dates, with a day after them: 2026-02-30 or 9999-12-31 would end in a traceback.
  python3 -c 'import datetime as d, sys; [d.date.fromisoformat(x) + d.timedelta(days=1) for x in sys.argv[1:]]' \
    "${since:-2000-01-01}" "${until:-2000-01-01}" 2>/dev/null || die "${FLOW_USAGE}"
  # Every row, unfiltered, so its rows line up one to one with agents.tsv's builder lines, and an epic
  # PR built before since still keeps its later findings.
  # shellcheck disable=SC2119 # takes no argument here
  [[ ! -f "${AGENTS_LOG}" ]] || rows="$(SWARM_REWORK_SINCE="${since}" outcomes_report)"
  local lead=""
  [[ "${HERDR_ENV:-}" == 1 ]] && lead="$(session_for_pane "${HERDR_PANE_ID:-}")"
  # shellcheck disable=SC2086 # one section name per word
  flow_sections "${since:-0000-00-00}" "${until:-9999-12-30}" "${epic}" "${rows}" "${lead}" ${SWARM_FLOW_SECTIONS:-}
}

# flow_sections <since> <until> <epic> <outcomes rows> <lead session> [section...] — run flow_report.py
# over the window, with each windowed slug's depends_on, and its estimate_lines and touches (read with
# story_text, so merged stories count); <lead session> (empty for none) is the calling session, counted as lead.
# SWARM_REPO_DIRS gives each windowed slug's repo, as repo_dir resolves its repo: (or `!<why>` when it
# cannot), for merge_ins.
flow_sections() {
  local since="$1" until="$2" epic="$3" rows="$4" lead="$5" deps="" stories="" repos="" dir slug text own="${CLAUDE_PROJECTS}/${PROJECT_DIR//[^A-Za-z0-9]/-}"
  shift 5
  while IFS= read -r slug; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    text="$(story_text "${slug}")"
    deps+="${slug}"$'\t'"$(sed -n 's/^depends_on: *\[\(.*\)\]$/\1/p' <<< "${text}" | head -1 | tr ',' ' ' | tr -d "\"'")"$'\n'
    stories+="${slug}"$'\t'"$(sed -n 's/^estimate_lines: *//p' <<< "${text}" | head -1)"
    stories+=$'\t'"$(sed -n 's/^touches: *\[\(.*\)\]$/\1/p' <<< "${text}" | head -1 | tr '\t' ' ')"$'\n'
    dir="$(repo_dir "$(sed -n 's/^repo: *//p' <<< "${text}" | head -1)")" || dir="!${dir}"
    repos+="${slug}"$'\t'"${dir//[$'\t\n']/ }"$'\n'
  done <<< "$(awk -F'\t' -v s="${since}" -v u="${until}" 'NR > 1 && $1 >= s && $1 <= u { print $2 }' <<< "${rows}" | sort -u)"
  SWARM_BOARD="${BOARD}" SWARM_BACKLOG_CONDUCTOR="$(conductor_name backlog)" SWARM_REPOS_DIR="${REPOS_DIR}" SWARM_AGENT_KINDS="${AGENT_KINDS}" SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" SWARM_ROWS="${rows}" SWARM_DEPS="${deps}" SWARM_STORIES="${stories}" SWARM_REPO_DIRS="${repos}" SWARM_GH_CACHE="${GH_CACHE}" SWARM_GH_FRESH="${GH_FRESH}" python3 "${SWARM_HOME}/bin/lib/flow_report.py" \
    "${since}" "${until}" "${epic}" "${AGENTS_LOG}" "${EVENTS_LOG}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" \
    "${SWARM_FEATURES:-${PROJECT_DIR}/docs/features.tsv}" "${BUILDER_ROLES}" "${CLAUDE_PROJECTS}" "${SESSIONS_DIR}" "${lead}" "${own}" "$@"
}

# moved <command> <where> <run> — a report folded into another (flow's sections, outcomes' recurring
# block): say where its numbers went, and the command, with the flags it reads, that prints them.
moved() {
  echo "swarm.sh $1 is now $2: swarm.sh $3"
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
  fail_lines "${full}" "$2"
}

# fail_lines <owner/repo> <pr> — a rules-unchecked line for each test named on a line the PR's diff
# adds (Go func TestX, Python def test_x, a check line in tests/*_test.sh, a JS it or test call) when
# no line of the PR body holds both FAIL and its name: the builder's proof that the test can fail.
fail_lines() {
  local pr diff
  pr="$(gh pr view "$2" --repo "$1" --json body,url)" || die "findings: cannot read the body of $1#$2"
  # GitHub refuses a diff over 20,000 lines or 300 files (HTTP 406); the notes above still stand.
  diff="$(gh pr diff "$2" --repo "$1")" \
    || { echo "  FAIL lines: not checked, gh pr diff failed on $1#$2 (a diff over 20,000 lines or 300 files is refused)"; return 0; }
  PR="${pr}" python3 -c '
import json, os, re, sys
pr = json.loads(os.environ["PR"])
body = [l for l in (pr.get("body") or "").splitlines() if "FAIL" in l]
tests = [  # (path pattern, pattern whose group n is the test name)
    (r"_test\.go$", r"func (?P<n>Test(?!Main\b)\w*)"),  # TestMain runs the tests; it is not one
    (r"(^|/)(test_[^/]*|[^/]*_test)\.py$", r"\s*(async\s+)?def (?P<n>test\w*)"),
    (r"(^|/)tests/[^/]*_test\.sh$", r"\s*check\s+\x22(?P<n>(\\.|[^\x22\\])*)\x22"),
    (r"\.(test|spec)\.[cm]?[jt]sx?$", r".*?\b(it|test)\(\s*(?P<q>[\x22\x27`])(?P<n>(\\.|(?!(?P=q))[^\\])*)(?P=q)"),
]
path, names, end = "", [], None
for line in sys.stdin.read().splitlines():
    if line.startswith("+++ "):
        path, end = line[4:], None  # b/<path>: each pattern ends at $ or starts at (^|/)
    elif line.startswith("@@"):
        end = None  # ponytail: a hunk that opens inside a heredoc reads its fixture as tests
    elif line[:1] in ("+", " "):
        # A heredoc in a shell file is a fixture, not tests: skip to its end word, on context
        # lines as on added ones.
        if end:
            end = None if line[1:].strip() == end else end
            continue
        if path.endswith(".sh"):
            h = re.search(r"(?<!<)<<(?!<)-?\s*[\x22\x27]?([A-Za-z_]\w*)", line[1:])  # not 1<<3
            end = h and h[1]
        if line[0] != "+":
            continue
        for p, t in tests:
            m = re.search(p, path) and re.match(t, line[1:])
            if m and m["n"] not in names:
                names.append(m["n"])
for n in names:
    # The whole name as the test prints it: each unescaped expansion (a dollar sign, \x24, then a
    # word, braces or parentheses) stands for what it expands to, maybe nothing, and the rest is
    # unescaped.
    parts = re.split(r"(?<!\\)\x24(?:\{[^}]*\}|\([^)]*\)|\w+)", n)
    parts = [re.escape(re.sub(r"\\(\W)", r"\1", x)) for x in parts]
    pat = r"(?<!\w)" + ".*".join(parts) + r"(?!\w)"
    if not any(re.search(pat, l) for l in body):
        print("  rules-unchecked: %s has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked %s …)" % (n, pr["url"]))' <<< "${diff}"
}
