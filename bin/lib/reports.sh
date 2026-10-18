# shellcheck shell=bash

# The outer loop: every review finding someone fixed is logged by kind, so a kind that keeps coming
# back across PRs can become a standing rule in the project's brief. Rules are proposed, never written.
FINDINGS_LOG_NAME="findings.tsv"
LESSON_MIN_PRS=3           # the rule of three: a kind in this many distinct PRs is a candidate rule
LESSON_RECENT_DAYS=90      # a candidate's kind must have been fixed this recently: an old pattern is not news
BRIEF_MAX_BYTES=4096       # past this, the brief every agent reads is too long to stay read; prune by hand
# Who can raise a finding (log-finding --reviewer); ci is a PR review bot, check-run notes or
# code-scanning alerts (swarm.sh findings). skeptic and critic are the plan reviewers, logging on a
# board PR; escaped is a defect a later fix found in merged work, logged against the original PR. A
# row logged without --reviewer says unknown. The reports read this list as SWARM_FINDING_REVIEWERS.
# A new reviewer a conductor logs also needs its line in finding_rule's mapping and in the story arm
# of commands/swarm.md, which tell whoever logs a finding which value names which reviewer.
FINDING_REVIEWERS="codex code-review ci conductor lead skeptic critic escaped"
# Why a finding was declined (log-finding --declined <reason>).
FINDING_REASONS="out-of-scope nit wrong"

# finding_flags <args...> — log-finding's flags, which come before the kind in either order: sets
# FINDING_OUTCOME (fixed, or declined with --declined), FINDING_REASON to --declined's reason (empty
# when the next word is a flag or missing), FINDING_REVIEWER to --reviewer's value (unset without
# one) and FINDING_SKIP to how many words the flags took. It checks nothing and never dies, so main
# reads the events target with it before the command runs.
finding_flags() {
  local n
  FINDING_OUTCOME=fixed; FINDING_REASON=""; unset FINDING_REVIEWER; FINDING_SKIP=0
  while [[ "${1:-}" == --declined || "${1:-}" == --reviewer ]]; do
    n=1
    # shellcheck disable=SC2034 # read in another file
    if [[ "$1" == --declined ]]; then
      FINDING_OUTCOME=declined
      [[ $# -lt 2 || "$2" == --* ]] || { FINDING_REASON="$2"; n=2; }
    else FINDING_REVIEWER="${2:-}"; [[ $# -lt 2 ]] || n=2; fi
    shift "${n}"; FINDING_SKIP=$((FINDING_SKIP + n))
  done
}

# record_finding <kind> <pr-url> <text> <fixed|declined> [reviewer] — log one finding, what became of
# it and who raised it: one of FINDING_REVIEWERS, or unknown when it is left out. A declined one's
# reason (one of FINDING_REASONS) comes from finding_flags' FINDING_REASON. A row is date, kind, PR,
# text, outcome, reviewer, and a declined row adds the reason; rows from before the outcome column
# have four fields and were all fixed, and rows from before the reviewer column have five. An
# escaped defect's outcome is escaped, so outcomes and flow's reviewers, which count what review raised,
# leave it out; lessons and dash count fixed and escaped rows, never declined ones.
record_finding() {
  local kind="$1" pr="$2" text="$3" outcome="$4" reviewer="${5-unknown}" reason=""
  [[ -n "${kind}" && -n "${pr}" && -n "${text//[[:space:]]/}" ]] \
    || die "usage: swarm.sh log-finding [--declined <reason>] [--reviewer <who>] <kind> <pr-url> <one line>"
  # A defect review missed is no finding review raised: its own outcome keeps it out of their counts.
  if [[ "${reviewer}" == escaped ]]; then
    [[ "${outcome}" == fixed ]] || die "an escaped defect is fixed, never declined: drop --declined"
    outcome=escaped
  fi
  if [[ "${outcome}" == declined ]]; then
    [[ "${FINDING_REASON:-}" =~ ^[a-z-]+$ && " ${FINDING_REASONS} " == *" ${FINDING_REASON} "* ]] \
      || die "--declined needs a reason, one of: ${FINDING_REASONS}"
    reason=$'\t'"${FINDING_REASON}"
  fi
  [[ $# -lt 5 || ( "${reviewer}" =~ ^[a-z-]+$ && " ${FINDING_REVIEWERS} " == *" ${reviewer} "* ) ]] \
    || die "reviewer '${reviewer}' must be one of: ${FINDING_REVIEWERS}"
  [[ "${kind}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#kind} -le 32 ]] \
    || die "kind '${kind}' must be short kebab-case (32 characters at most), like vacuous-test"
  text="${text:0:200}"
  [[ "${pr}" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+(/[^[:space:]]*)?$ || "${pr}" =~ ^[^/#[:space:]]+/[^/#[:space:]]+#[0-9]+$ ]] \
    || die "pr '${pr}' must be a PR URL or owner/repo#N, so the same PR always counts once"
  mkdir -p "${PROJECT_DIR}/.swarm"
  printf '%s\t%s\t%s\t%s\t%s\t%s%s\n' "$(date +%F)" "${kind}" "${pr//[$'\t\n\r']/ }" "${text//[$'\t\n\r']/ }" "${outcome}" "${reviewer}" "${reason}" \
    >> "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}"
  echo "recorded ${kind} (${outcome})"
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
#   reads findings passes) or unknown. Fields past the sixth (a declined row's reason) are ignored, so
#   a column appended later drops no row. fixed_rows(path) is the first four fields of the fixed and
#   escaped ones: both are a mistake someone fixed, so both are lessons.
#   session_usage(path, seen) is one session's (input, cache write, cache read, output) tokens, est.
#   USD and models, from Claude Code's own log, skipping (and adding to seen) message ids already counted.
#   rework_of(pr, merged_at, commits, escaped) is whether a later PR fixed a merged one within
#   REWORK_DAYS: a later commit on the default branch names it on a line that says it fixes it (never a
#   stacked PR's Merge after, Depends on or Stacked on line), or an escaped finding points at it.

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
  SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" python3 "${SWARM_HOME}/bin/lib/lessons_report.py" "${PROJECT_DIR}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${LESSONS_FILE}" \
    "${LESSON_MIN_PRS}" "${LESSON_RECENT_DAYS}" "${BRIEF_MAX_BYTES}" "${1:-}" "${memory}" "${PROJECT_BRIEF}"
}

# cost_report <YYYY-MM-DD> — flow's cost section alone, since that day, for dash's cost of the day.
cost_report() {
  flow_sections "$1" 9999-12-30 "" "" cost
}

# outcomes [--since YYYY-MM-DD] — one TSV row per builder agent in agents.tsv, joining what the logs
# already hold: the story it built (slug, kind, risk), its model and effort, its cost, the tells it
# took by kind (findings, nudge, resume; a refused tell never reached it, so is not counted), the closes, the findings fixed on its PR, how the PR ended, and which attempt at the slug it was.
# Then when it started (its session log's first timestamp, UTC), its tokens by type, its last close's
# cause, the times of its escalation steps (escalate, dialog with its answer, escalated, reset,
# drop), and last its story's epic:, when its PR merged, whether any PR of the story merged (empty when
# unknown), the findings declined, both counts by reviewer, when its PR was created, the minutes from
# its start to that and from that to the merge, and the commits on the PR that merge the base into it. A finding goes to the latest build on
# its PR that started on or before its day, so builds sharing a PR never count it twice. Each events.tsv line goes to one build: an escalation step to the escalate build whose cycle
# was open when it was logged (by event order), any other to the build that started last at or before
# it. A build with no session log starts at 00:00 local time on its agents.tsv day.
# A build's PR is the last of the slug's PRs its session log names, so each attempt keeps its own;
# with no log, the slug's PR when it has exactly one.
# agents.tsv cuts names at 32 characters, so the slug is the session's worktree (its cwd's last part),
# read from close's copy of the session log once Claude Code deleted it.
# shellcheck disable=SC2120 # another file's callers pass it
outcomes_report() {
  local since="" rows meta="" slug text kind from src prs story_epic got asked
  [[ -z "${1:-}" || ( "$1" == --since && "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ) ]] \
    || die "usage: swarm.sh outcomes [--since YYYY-MM-DD]"
  [[ -z "${1:-}" ]] || since="$2"
  [[ -f "${AGENTS_LOG}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  # date, slug, role, model, effort, cost_usd, tokens, tells_findings, tells_nudge, tells_resume, closes, attempts,
  # pulls (the github pull URLs its session log names, or - when there is no log to read), then the
  # columns the report prints after attempts as they are: started to drop_at.
  rows="$(python3 "${SWARM_HOME}/bin/lib/outcomes_rows.py" "${AGENTS_LOG}" "${EVENTS_LOG}" "${since:-0000-00-00}" \
    "${CLAUDE_PROJECTS}" "${BUILDER_ROLES}" "${SESSIONS_DIR}")"
  # Per slug: kind (an escalated story's kind: lead is its escalated_from:), risk, every PR of
  # story/<slug> (newest first, as `url state mergedAt createdAt main_merges` joined by commas, where
  # main_merges counts the commits whose headline merges the base into the PR: `Merge origin/main into
  # x`, `Merge branch 'main' into x`, `Merge remote-tracking branch 'origin/main' into x`), its epic: and
  # whether gh answered (1, or empty), from the story (on the board, or its last version in git once a
  # merge deleted it) and gh. A gh that fails leaves no PR; it never fails the run. A story that is gone (its PRs may still show) or has no repo is unknown too.
  while IFS= read -r slug; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    text="$(story_text "${slug}")"; prs=""; asked=""
    kind="$(sed -n 's/^kind: *//p' <<< "${text}" | head -1)"; [[ -z "${text}" ]] || kind="${kind:-code}"
    from="$(sed -n 's/^escalated_from: *//p' <<< "${text}" | head -1)"
    [[ "${kind}" != lead || -z "${from}" ]] || kind="${from% (default)}"
    story_epic="$(sed -n 's/^epic: *//p' <<< "${text}" | head -1)"
    # shellcheck disable=SC2016 # $b is jq's
    if src="$(repo_dir "$(sed -n 's/^repo: *//p' <<< "${text}" | head -1)")" \
      && got="$( (cd "${src}" && gh pr list --head "story/${slug}" --state all \
        --json url,state,mergedAt,createdAt,baseRefName,commits --jq '.[] | [.url, .state, .mergedAt // "",
          .createdAt, (.baseRefName as $b | [.commits[].messageHeadline | select(startswith("Merge "))
          | ltrimstr("Merge ") | ltrimstr("remote-tracking ") | ltrimstr("branch ") | split(" ")[0]
          | ltrimstr("\u0027") | rtrimstr("\u0027") | ltrimstr("origin/") | select(. == $b)] | length)] | @tsv') 2>/dev/null)"; then
      prs="$(tr '\t' ' ' <<< "${got}" | paste -sd, -)"; asked="${text:+1}"
    fi
    meta+="${slug}"$'\t'"${kind}"$'\t'"$(sed -n 's/^risk: *//p' <<< "${text}" | head -1)"$'\t'"${prs}"
    meta+=$'\t'"${story_epic}"$'\t'"${asked}"$'\n'
  done <<< "$(cut -f2 <<< "${rows}" | sort -u)"
  SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" SWARM_META="${meta}" SWARM_ROWS="${rows}" python3 "${SWARM_HOME}/bin/lib/outcomes_join.py" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${BOARD}"
}

# dataset — write .swarm/dataset.jsonl, one JSON line per finished story (one of its PRs merged), for
# prediction-scores to score the planner against. inputs: the story as planned, read from git at the
# newest commit that added it (text, kind, risk, touches, depends_on, estimate_lines, easy), and
# planner_model, the model of the last agents.tsv lead started by then whose session log scopes its
# epic. results: diff_lines and diff_files of its PR from gh (less the story's and its epic's files),
# attempts, findings_rounds (tells:findings), findings_fixed, rework (rework_of), cost_usd, minutes
# from its first build's start to the merge, every model that built it, and each escalate event as
# its trigger (attempt N, or step-up's trigger) with from and to. was_easy: merged on the first
# attempt, at most one findings round, no rework and a diff under 100 lines, under was_easy_rule 1.
# Nothing from the environment or a session log's text is written. Each run rewrites the file whole
# through a temporary file, and a story gh could not read stops it before it writes.
dataset_report() {
  local rows repos="" slug src
  [[ $# -eq 0 ]] || die "usage: swarm.sh dataset"
  [[ -f "${AGENTS_LOG}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  # shellcheck disable=SC2119 # takes no argument here
  rows="$(outcomes_report | sed '/^$/,$d')"
  # Each merged story's repo (its repo:, as outcomes reads it), whose history holds the fixes that name its PR.
  while IFS= read -r slug; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    src="$(repo_dir "$(story_text "${slug}" | sed -n 's/^repo: *//p' | head -1)")" && repos+="${slug}"$'\t'"${src}"$'\n'
  done <<< "$(awk -F'\t' 'NR > 1 && $31 != "" { print $2 }' <<< "${rows}" | sort -u)"
  SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" SWARM_ROWS="${rows}" SWARM_REPOS="${repos}" python3 "${SWARM_HOME}/bin/lib/dataset.py" \
    "${AGENTS_LOG}" "${EVENTS_LOG}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" "${BOARD}" "${CLAUDE_PROJECTS}" "${SESSIONS_DIR}" \
    "${PROJECT_DIR}/.swarm/dataset.jsonl"
}

# flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] — the project's numbers, one section
# per bin/lib/flow_<name>.py in name order, each under `## <name>` (flow_report.py runs them):
#   ci_health: one TSV row over the github.com PRs of the outcomes rows dated in the window (with
#     --epic, its own; without --since, the 30 days up to --until or today, said in a line above it):
#     the median minutes per head SHA from its first run created to its last updated, red runs
#     (failure, timed_out or startup_failure) per PR and flakes (a red run, then a green one of the
#     same workflow and event on that head, a rerun's earlier attempts read from gh api), from gh's
#     runs of each PR's branch whose head is one of its commits. A gh call that fails or takes over
#     10 s prints `ci health: gh failed` and no numbers.
#   cost: tokens and estimated cost per role, for every agent this project's swarm started in the
#     window, and as "lead" the calling session when run inside herdr plus every session in the
#     project's own Claude Code directory that agents.tsv does not name (by its first timestamp's
#     local day). Usage comes from Claude Code's own session logs (or close's copy, once Claude Code
#     deleted one), deduplicated by session and message id; codex agents are listed but not priced.
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
#   reviewers: what review yields, for tuning the reviewers. Block 1 (TSV reviewer kind raised fixed
#     declined decline_rate): findings.tsv rows dated in the window, per reviewer (its `all` row, then
#     its kinds by declined, most first), per kind across reviewers (`all <kind>`), and last `all
#     all`. Block 2, after a blank line (TSV prs rounds rounds_per_pr max_rounds): the tells_findings
#     of every outcomes row with a PR dated in the window, summed per PR. A tell names no reviewer, so
#     rounds are not split by one. --epic keeps only the PRs of that epic (outcomes epic column) in
#     both blocks, and a third block lists every PR either block counted.
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
# A new section is a new flow_<name>.py; neither this nor flow_report.py changes. It writes nothing.
FLOW_USAGE="usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]"
flow_report() {
  local since="" until="" epic="" rows=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "${FLOW_USAGE}"; since="$2"; shift 2 ;;
      --until) [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "${FLOW_USAGE}"; until="$2"; shift 2 ;;
      --epic) [[ "${2:-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "${FLOW_USAGE}"; epic="$2"; shift 2 ;;
      *) die "${FLOW_USAGE}" ;;
    esac
  done
  # Real dates, with a day after them: 2026-02-30 or 9999-12-31 would end in a traceback.
  python3 -c 'import datetime as d, sys; [d.date.fromisoformat(x) + d.timedelta(days=1) for x in sys.argv[1:]]' \
    "${since:-2000-01-01}" "${until:-2000-01-01}" 2>/dev/null || die "${FLOW_USAGE}"
  # Every row, unfiltered, so its rows line up one to one with agents.tsv's builder lines, and an epic
  # PR built before since still keeps its later findings.
  # shellcheck disable=SC2119 # takes no argument here
  [[ ! -f "${AGENTS_LOG}" ]] || rows="$(outcomes_report)"
  flow_sections "${since:-0000-00-00}" "${until:-9999-12-30}" "${epic}" "${rows}"
}

# flow_sections <since> <until> <epic> <outcomes rows> [section...] — run flow_report.py over the
# window, with each windowed slug's depends_on (read with story_text, so merged stories count).
flow_sections() {
  local since="$1" until="$2" epic="$3" rows="$4" deps="" lead="" slug own="${CLAUDE_PROJECTS}/${PROJECT_DIR//[^A-Za-z0-9]/-}"
  shift 4
  while IFS= read -r slug; do
    [[ "${slug}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    deps+="${slug}"$'\t'"$(story_text "${slug}" | sed -n 's/^depends_on: *\[\(.*\)\]$/\1/p' | head -1 | tr ',' ' ' | tr -d "\"'")"$'\n'
  done <<< "$(awk -F'\t' -v s="${since}" -v u="${until}" 'NR > 1 && $1 >= s && $1 <= u { print $2 }' <<< "${rows}" | sort -u)"
  [[ "${HERDR_ENV:-}" == 1 ]] && lead="$(session_for_pane "${HERDR_PANE_ID:-}")"
  SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" SWARM_ROWS="${rows}" SWARM_DEPS="${deps}" python3 "${SWARM_HOME}/bin/lib/flow_report.py" \
    "${since}" "${until}" "${epic}" "${AGENTS_LOG}" "${EVENTS_LOG}" "${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" \
    "${SWARM_FEATURES:-${PROJECT_DIR}/docs/features.tsv}" "${BUILDER_ROLES}" "${CLAUDE_PROJECTS}" "${SESSIONS_DIR}" "${lead}" "${own}" "$@"
}

# moved <command> <section> <flags> — a report folded into flow: say where its numbers went, and the
# flags that section reads, for one release.
moved() {
  echo "swarm.sh $1 is now flow's $2 section: swarm.sh flow $3"
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
