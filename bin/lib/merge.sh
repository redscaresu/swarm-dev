# shellcheck shell=bash

MERGE_CI_SECONDS=1800   # how long merge waits for CI on the merge commit (SWARM_MERGE_CI_SECONDS, for tests)
MERGE_POLL=20           # seconds between its reads of that CI (SWARM_MERGE_POLL; else scaled)
MERGE_CI_GRACE=60       # with no workflow expected there, how long checks get to appear (SWARM_MERGE_CI_GRACE)
MERGE_READS=5           # reads of the PR after gh pr merge before its state counts as unconfirmed
MERGE_READ_WAIT=3       # seconds between those reads (SWARM_MERGE_READ_WAIT)
WAIT_PR_GRACE=300       # how long wait-pr gives a head with no check runs for them to appear (SWARM_WAIT_PR_GRACE)
WAIT_PR_RETRY=60        # wait-pr's pause after a transient gh error, longer than a poll (SWARM_WAIT_PR_RETRY)
WAIT_PR_TRIES=3         # transient gh errors in a row wait-pr retries; the next one ends it
FIX_MAIN_LINES=20       # FAIL lines fix-main prints and puts in its story
FIX_MAIN_LOG_SECONDS=600  # how long fix_main waits for the failed runs to finish and give their logs (SWARM_FIX_MAIN_LOG_SECONDS)
# A gh error worth retrying: a dropped or unreachable network, a timeout, a rate limit, a 408 or 5xx. Matched as whole
# words against the error with every word holding a / (a URL, a repo path) taken out, so a repo
# named geofabrik or timeout does not make Bad credentials transient.
WAIT_PR_TRANSIENT='rate limit|timeout|timed out|connection reset|connection refused|EOF|TLS handshake|no such host|network is unreachable|stream error|HTTP (408|429|50[0234])'

# ci_gate head <owner/repo> <sha> — succeed when <sha> is green: at least one check run, every
# run completed as success, skipped or neutral, and every commit status success, printing each check.
# Else print which checks and fail (1 red, 2 pending; "no check runs" when there are none). It is the
# block-red-pr-merge hook's rule, which never sees a gh call made inside swarm.sh, and it fails
# closed: every page is read, and a gh error, unreadable JSON or fewer items than total_count is 3.
# ci_gate base <owner/repo> <sha> — as head, and every workflow run on <sha> green too, as main
# judges them: a run that failed to start has no check run of its own.
# ci_gate age <owner/repo> <sha> — head's rule; when green, print the whole minutes since its last check
# run or commit status finished (queued_line). Exits as head does.
# ci_gate main <owner/repo> <sha> <base> <pr> <changed> <seconds> <poll> <grace> — wait, reading every
# <poll> seconds, until the merge commit <sha> is green as above (with no check run needed of its own,
# though with no workflow expected not before <grace> seconds),
# every workflow whose `on: push` covers <base> and the files PR <pr> changes (read from
# .github/workflows at <sha>) has a run on <sha>, and every workflow run on <sha> is green. A failed
# read is a missed poll; three in a row end it. Prints ok (0), red <checks> (1), timeout (<what it
# waited on>) (2) or error <why> (3); YAML it does not read is an error, never a skipped workflow.
# ci_gate admin <owner/repo> <base> <sha> <method> — for merge_admin, since --admin skips every rule on
# <base>, not just the approving review: succeed when <sha> has every status check <base>'s rulesets
# and branch protection require, is up to date with <base> when they say strict, and <base> has no
# rule --admin would skip besides the review (merge queue, required workflows, signatures, the
# review's thread resolution, a merge method other than <method>, any classic field not known to be
# safe, ...). Else print why and fail (1); a read that fails is a failure too, and a 404 from branch
# protection is unprotected only when GitHub says "Branch not protected".
# ci_gate files <owner/repo> <pr> <changed> — every path the PR changes, a renamed file's old path
# too; fails (3) unless there are <changed> of them.
ci_gate() {
  python3 "${SWARM_HOME}/bin/lib/ci_gate.py" "$@"
}

# merge_caller — why the pane running this may not merge, or nothing when it may. Outside herdr it
# is the lead's own session, which merges for the user under merge = human too. Inside herdr the pane
# must be one this project did not start (the lead's), or, with merge = agent, a conductor's; when the
# pane cannot be identified (no HERDR_PANE_ID, an unreadable tab record, herdr cannot list its
# agents) it may not. start_agent's guard blocks only a bare `gh pr merge`, so this is what stops a
# builder merging through swarm.sh.
merge_caller() {
  local f agents panes
  [[ -n "${HERDR_ENV:-}" ]] || return 0
  [[ -n "${HERDR_PANE_ID:-}" ]] || { echo "inside herdr with no HERDR_PANE_ID, the pane running this is unknown"; return 0; }
  [[ ! -e "${STATE_DIR}" || ( -r "${STATE_DIR}" && -x "${STATE_DIR}" ) ]] || { echo "cannot read ${STATE_DIR}, so whose pane this is is unknown"; return 0; }
  for f in "${STATE_DIR}"/*; do
    [[ ! -f "${f}" || -r "${f}" ]] || { echo "cannot read ${f}, so whose pane this is is unknown"; return 0; }
  done
  agents="$(herdr agent list 2>/dev/null)" || { echo "herdr cannot list its agents, so whose pane this is is unknown"; return 0; }
  # A here-string, not a pipe: grep -q may exit before own_panes has written all of it, and pipefail
  # would then read a match as none.
  panes="$(own_panes)"
  grep -qxF -- "${HERDR_PANE_ID}" <<< "${panes}" || return 0
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge}" == agent ]] && [[ "$(SWARM_PANE="${HERDR_PANE_ID}" json "any(a.get('pane_id') == e['SWARM_PANE'] and a.get('name', '').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done') for a in d['result']['agents'])" <<< "${agents}" 2>/dev/null)" == True ]]; then
    return 0
  fi
  echo "pane ${HERDR_PANE_ID} is one this project started, and only a conductor with merge = agent merges from one"
}

# merged_state <pr> <owner/repo> — "<state> <merge commit>" once the PR reads MERGED with one, read up
# to MERGE_READS times, MERGE_READ_WAIT apart: GitHub may take a moment to say so, and a read may
# fail. The state is unreadable when no read succeeded.
merged_state() {
  local try info state="" oid=""
  for ((try = 1; try <= MERGE_READS; try++)); do
    info="$(gh pr view "$1" --repo "$2" --json state,mergeCommit | json "d['state'] + ' ' + ((d['mergeCommit'] or {}).get('oid') or '')")" || info=unreadable
    read -r state oid <<< "${info}"
    [[ "${state}" != MERGED || ! "${oid}" =~ ^[0-9a-f]{40}$ ]] || break
    [[ ${try} -eq ${MERGE_READS} ]] || sleep "${SWARM_MERGE_READ_WAIT:-${MERGE_READ_WAIT}}"
  done
  echo "${state:-unreadable} ${oid}"
}

# merge_fail <why> — merge's one line for a refusal, then stop. main logs nothing for merge.
merge_fail() { record_event merge "${MERGE_TARGET}" "$1"; die "merge: $1"; }

# merge [--board|--release] [--head <sha>] <pr-url> — merge a green, open PR with its head pinned:
# refuse unless merge_caller allows it, the head is <sha> (with --head), a story or epic in review
# lists the URL (with merge = agent, by any route, pr_held finds nothing: whoever calls it, a PR whose
# story or stacked parent costs money is the user's) (with --board instead: the PR is in the board's own repo and every path it changes,
# old or new, is on the board; with --release: the PR is in the project's own repo and every path it
# changes is .claude-plugin/plugin.json, release_check's), and ci_gate passes on the head.
# Merge with the repo's method (squash, else merge, else rebase), --match-head-commit and, only with
# merge_admin = on, --admin; never --auto. Then wait for CI on the merge commit and, without --board or --release, run
# reconcile, even after a red main, since the PR has merged. Each step is one events.tsv line, under
# the slug (or the URL with --board or --release): merge <why> for a refusal, merge unconfirmed (...) when gh pr
# merge ran but the PR never read as merged, else merge ok, main-ci ok|red|timeout|error (a red one
# then fix_main's main-red, an ok one main-green when it clears a red main), then reconcile's own. Fails on anything but a green main.
merge_pr() {
  local only="" clash="" whose want="" url repo n info state head base changed f="" any="" p rel origin own method oid why rc=0 rrc ran=1 admin
  while [[ $# -gt 1 ]]; do
    case "$1" in
      --board|--release) [[ -z "${only}" || "${only}" == "$1" ]] || clash=1; only="$1"; shift ;;
      --head) want="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  url="${1:-}"; MERGE_TARGET="${url:--}"
  [[ -z "${clash}" ]] || merge_fail "--board and --release do not go together"
  [[ $# -eq 1 ]] || merge_fail "usage: swarm.sh merge [--board|--release] [--head <sha>] <pr-url>"
  [[ "${url}" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] || merge_fail "not a PR URL: ${url}"
  repo="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
  [[ -z "${want}" || "${want}" =~ ^[0-9a-f]{40}$ ]] || merge_fail "--head takes a full 40-character SHA, not '${want}'"
  why="$(merge_caller)" || why="cannot tell whose pane this is"
  [[ -z "${why}" ]] || merge_fail "${why}"
  info="$(gh pr view "${n}" --repo "${repo}" --json state,headRefOid,baseRefName,changedFiles \
    | json "'%s %s %s %d' % (d['state'], d['headRefOid'], d['baseRefName'], d['changedFiles'])")" \
    || merge_fail "gh cannot read ${url}"
  read -r state head base changed <<< "${info}"
  [[ "${head}" =~ ^[0-9a-f]{40}$ && "${base}" =~ ^[A-Za-z0-9._/-]+$ && "${changed}" =~ ^[0-9]+$ ]] \
    || merge_fail "gh gave no head SHA, base branch or file count for ${url}"
  [[ "${state}" == OPEN ]] || merge_fail "${url} is ${state}, not open"
  [[ -z "${want}" || "${want}" == "${head}" ]] || merge_fail "the head of ${url} is ${head:0:7}, not ${want:0:7}: review the new head"
  # With merge = agent a PR whose story costs money is the user's, by any route (--board and --release too).
  if [[ "${CFG_merge}" == agent ]]; then
    why="$(pr_held "${url}")"
    [[ -z "${why}" ]] || { MERGE_TARGET="${why%% *}"; merge_fail "held: ${why}; the user merges it"; }
  fi
  if [[ -z "${only}" ]]; then
    # Any item listing the URL may be the one in review.
    while IFS= read -r p; do
      [[ " $(fm "${p}" prs) " == *" ${url} "* ]] || continue
      [[ -n "${any}" ]] || any="${p}"
      [[ "$(fm "${p}" status)" != review ]] || { f="${p}"; break; }
    done < <(board stories; board epics)
    [[ -n "${any}" ]] || merge_fail "no story or epic lists ${url} on its prs: line: run swarm.sh review <slug> ${url} first, or pass --board for a board-only PR"
    if [[ -z "${f}" ]]; then MERGE_TARGET="$(basename "${any}" .md)"; merge_fail "${MERGE_TARGET} is $(fm "${any}" status), not review"; fi
    MERGE_TARGET="$(basename "${f}" .md)"
  else
    whose="the project's"
    if [[ "${only}" == --board ]]; then
      [[ ${BOARD_IN_REPO} == 1 ]] || merge_fail "--board: the board is not in the project's repo"
      whose="the board's"
    fi
    origin="$(git -C "${PROJECT_DIR}" remote get-url origin 2>/dev/null)" || merge_fail "${only}: ${PROJECT_DIR}, ${whose} repo, has no origin"
    own="$(gh repo view "${origin}" --json nameWithOwner | json "d['nameWithOwner'].lower()")" \
      || merge_fail "${only}: gh cannot tell which GitHub repo ${origin} is"
    [[ "$(tr '[:upper:]' '[:lower:]' <<< "${repo}")" == "${own}" ]] || merge_fail "${only}: ${url} is not in ${own}, ${whose} repo"
    rel="${BOARD#"${PROJECT_DIR}"/}"
    # A renamed file's old path counts too: renaming bin/x to the board is not a board-only change.
    info="$(ci_gate files "${repo}" "${n}" "${changed}")" || merge_fail "${only}: cannot list every file ${url} changes: ${info}"
    while IFS= read -r p; do
      if [[ "${only}" == --board ]]; then
        [[ "${p}" == "${rel}/"* ]] || merge_fail "--board: ${url} changes ${p}, outside ${rel}/"
      else
        [[ "${p}" == .claude-plugin/plugin.json ]] || merge_fail "--release: ${url} changes ${p}, not only .claude-plugin/plugin.json"
      fi
    done <<< "${info}"
    if [[ "${only}" == --board && "${CFG_merge}" == agent ]]; then
      # A board PR could lift a hold (costs: money to none, or a story deleted) before the agent merges it.
      info="$(gh pr diff "${n}" --repo "${repo}" --color never)" || merge_fail "--board: gh cannot read the diff of ${url}, so whether it changes a costs: line is unknown"
      p="$(costs_diff <<< "${info}")"
      [[ -z "${p}" ]] || merge_fail "held: ${url} changes a costs: line in ${p}; with merge = agent the user merges it"
    fi
    [[ "${only}" == --board ]] || release_check "${repo}" "${base}" "${head}"
  fi
  why="$(ci_gate head "${repo}" "${head}")" || merge_fail "the head ${head:0:7} is not green: ${why}"
  method="$(gh repo view "${repo}" --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed \
    | json "'squash' if d['squashMergeAllowed'] else 'merge' if d['mergeCommitAllowed'] else 'rebase' if d['rebaseMergeAllowed'] else ''")" \
    || merge_fail "gh cannot read ${repo}'s merge methods"
  [[ -n "${method}" ]] || merge_fail "${repo} allows no merge method"
  # merge_admin = on: --admin skips every rule on the base, not only the review, so ci_gate admin
  # checks them first.
  admin=()
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge_admin}" == on ]]; then
    why="$(ci_gate admin "${repo}" "${base}" "${head}" "${method}")" || merge_fail "--admin may not merge ${head:0:7} into ${base}: ${why}"
    admin=(--admin)
  fi
  why="$(gh pr merge "${n}" --repo "${repo}" "--${method}" --match-head-commit "${head}" ${admin[@]+"${admin[@]}"} 2>&1)" || ran=""
  # Read the PR back either way: a 5xx or a dropped connection can follow a merge GitHub made.
  read -r state oid <<< "$(merged_state "${n}" "${repo}")"
  if [[ "${state}" != MERGED || ! "${oid}" =~ ^[0-9a-f]{40}$ ]]; then
    # A failed gh pr merge on a PR that still reads open or closed never reached a merge.
    [[ -n "${ran}" || "${state}" == unreadable ]] || merge_fail "gh pr merge failed: ${why##*$'\n'}"
    [[ "${state}" != MERGED ]] || state="MERGED, no merge commit"
    merge_fail "unconfirmed (${state}): gh pr merge ran, but ${url} does not read as merged; check it by hand"
  fi
  record_event merge "${MERGE_TARGET}" ok
  echo "merged: ${url} (${method}, head ${head:0:7}, merge commit ${oid:0:7}); waiting for CI on ${base}"
  if why="$(ci_gate main "${repo}" "${oid}" "${base}" "${n}" "${changed}" "${SWARM_MERGE_CI_SECONDS:-${MERGE_CI_SECONDS}}" \
      "${SWARM_MERGE_POLL:-$(scaled "${MERGE_POLL}")}" "${SWARM_MERGE_CI_GRACE:-${MERGE_CI_GRACE}}")"; then
    why=ok
  else
    rc=$?; why="${why:-error (exit ${rc})}"
  fi
  record_event main-ci "${MERGE_TARGET}" "${why}"
  echo "main-ci: ${why}"
  # A green main clears a red one of this repo and base only. fix_main's every gh call is bounded and
  # cannot fail merge, so reconcile below runs whatever it does.
  if [[ ${rc} -eq 0 ]]; then
    clear_red_main "$(main_key "${repo}" "${base}")" "${oid}" "CI on ${base} is green at ${oid:0:7}"
  elif [[ ${rc} -eq 1 ]]; then
    fix_main "${repo}" "${oid}" "${base}" "${why#red }" || echo "main red, and fix_main failed (exit $?)"
  fi
  if [[ -z "${only}" ]]; then
    # In the background, so set -e holds inside it; its die line is reconcile's, as main would log it.
    # shellcheck disable=SC2034 # read in another file
    ( DIE_LEVEL="${BASH_SUBSHELL}"; set -e; reconcile ) &
    wait $! || {
      rrc=$?; why="$(head -1 "${DIE_FILE:-/dev/null}" 2>/dev/null || true)"
      record_event reconcile - "${why:-failed (exit ${rrc})}"
      die "merge: reconcile failed after the merge; run swarm.sh reconcile"
    }
  fi
  [[ ${rc} -eq 0 ]] || die "merge: CI on ${base} at ${oid:0:7} is not green: ${why}"
}

# run_fail_lines <owner/repo> <run id> <end> — the FAIL lines of a run's failed jobs, ANSI colour and
# timestamps taken off, once the run has completed: gh gives no log for a run in progress. Every gh
# call runs within what is left before <end> (in SECONDS), so a stalled one cannot hang merge.
# Returns 1 when gh fails (no actions:read scope, a run it cannot find), 2 at <end>.
run_fail_lines() {
  local status="" esc left log rc
  esc="$(printf '\033')"
  while left=$(($3 - SECONDS)); (( left > 0 )); do
    rc=0; status="$(within "${left}" gh run view "$2" --repo "$1" --json status --jq .status 2>/dev/null)" || rc=$?
    if (( rc == 142 )); then return 2; elif (( rc != 0 )); then return 1; fi
    [[ "${status}" != completed ]] || break
    sleep "${SWARM_MERGE_POLL:-$(scaled "${MERGE_POLL}")}"
  done
  left=$(($3 - SECONDS))
  [[ "${status}" == completed ]] && (( left > 0 )) || return 2
  rc=0; log="$(within "${left}" gh run view "$2" --repo "$1" --log-failed 2>/dev/null)" || rc=$?
  if (( rc == 142 )); then return 2; elif (( rc != 0 )); then return 1; fi
  cut -f3- <<< "${log}" | sed -E "s/${esc}\[[0-9;]*[A-Za-z]//g; s/^[0-9]{4}-[0-9-]+T[0-9:.]+Z //" | grep -wF FAIL || true
}

# main_key <owner/repo> <base> — what a red main is logged and cleared under: the repo lowercased
# (GitHub's names ignore case, and a PR URL may not), then the base.
main_key() { printf '%s %s\n' "$(tr '[:upper:]' '[:lower:]' <<< "$1")" "$2"; }

# fix_main <owner/repo> <sha> <base> <red checks> — CI on <base> is red at <sha>, a commit merge
# merged: record main-red <sha> "<main_key> <checks>", retire the older fix-main stories of that repo
# and base that no one has started (retire_fixes), and write the one-off story fix-main-<short sha>
# (unless it is on the board already) in the merged story's repo:. It names the failed Actions runs,
# the runs whose log could not be read and why, and their FAIL lines (FIX_MAIN_LINES at most),
# indented. Reading the logs stops FIX_MAIN_LOG_SECONDS after it starts, however many runs failed.
# Only once the story is there does it print fix-main: <checks> on <short sha>, then those lines.
fix_main() {
  local repo="$1" sha="$2" base="$3" key checks runs id out rc fails="" unread="" rname="" nl=$'\n' end
  local none="no FAIL line in the failed runs' logs" item="${BOARD}/stories/${MERGE_TARGET}.md" f="${BOARD}/stories/fix-main-${2:0:7}.md"
  key="$(main_key "${repo}" "${base}")"; end=$((SECONDS + ${SWARM_FIX_MAIN_LOG_SECONDS:-${FIX_MAIN_LOG_SECONDS}}))
  checks="$(sed -E 's# (https?://[^;]*|None)(;|$)#\2#g' <<< "$4")"
  runs="$(grep -oE 'https://github\.com/[^ ;]+/actions/runs/[0-9]+' <<< "$4" | sort -u | paste -sd' ' - || true)"
  for id in ${runs}; do
    rc=0; out="$(run_fail_lines "${repo}" "${id##*/}" "${end}")" || rc=$?
    case ${rc} in
      0) fails+="${out}${nl}" ;;
      1) unread+="${unread:+, }${id} (gh could not read it)" ;;
      *) unread+="${unread:+, }${id} (not finished or read within ${SWARM_FIX_MAIN_LOG_SECONDS:-${FIX_MAIN_LOG_SECONDS}}s)" ;;
    esac
  done
  fails="$(grep -v '^$' <<< "${fails}" | sed -n "1,${FIX_MAIN_LINES}p" || true)"
  [[ -z "${unread}" ]] || none="no FAIL line read; logs not read: ${unread}"
  fails="${fails:-${none}}"; runs="${runs:-none, as no red check is a GitHub Actions run}"
  record_event main-red "${sha}" "${key} ${checks}"
  retire_fixes "${key}" "${sha}" "superseded by fix-main-${sha:0:7}"
  [[ ! -f "${item}" ]] || rname="$(fm "${item}" repo)"
  [[ -e "${f}" || ! -d "${BOARD}/stories" ]] || {
    echo ---; echo "kind: code"; echo "status: ready"; [[ -z "${rname}" ]] || echo "repo: ${rname}"
    echo "depends_on: []"; echo "touches: []"; echo ---
    cat <<EOF

# Fix main, red at ${sha:0:7}

\`swarm.sh merge\` merged ${MERGE_TARGET}, and CI on ${base} at ${sha} is red: ${checks}. Each PR
was green alone, so this merge and one before it break each other. Fix ${base}: merges stay frozen
until it is green.

The failed runs: ${runs}. \`gh run view <id> --repo ${repo} --log-failed\`
prints a run's failed jobs. The logs not read: ${unread:-none}. Their FAIL lines:

    ${fails//${nl}/${nl}    }

**Done when:**
- Every check above passes on this PR's head, with the test that failed kept, not skipped.
EOF
  } 2>/dev/null > "${f}" || true
  if [[ -e "${f}" ]]; then echo "fix-main: ${checks} on ${sha:0:7}"
  else echo "main red, and no fix-main story: cannot write ${f}; ${checks} on ${sha:0:7}"; fi
  echo "  ${fails//${nl}/${nl}  }"
  [[ ! -e "${f}" ]] || echo "story: ${f}"
}

# retire_fixes <key> <sha> <why> — take off the board each fix-main story that a main-red of <key>
# other than <sha>'s wrote and that is still ready with no build: a newer red main's story, or a
# green main, replaces it. One already building or in review is left to its builder.
retire_fixes() {
  local s f
  while read -r s; do
    f="${BOARD}/stories/fix-main-${s}.md"
    if [[ -z "${s}" || ! -f "${f}" || "$(fm "${f}" status)" != ready ]] || one_off_started "fix-main-${s}"; then continue; fi
    delete_item "${f}" > /dev/null; record_event fix-main "fix-main-${s}" "retired: $3"; echo "retired: fix-main-${s} ($3)"
  done <<< "$(awk -F'\t' -v k="$1 " -v keep="$2" '$2 == "main-red" && $3 != keep && index($5, k) == 1 { print substr($3, 1, 7) }' \
    "${EVENTS_LOG}" 2>/dev/null | sort -u)"
}

# red_mains — "<sha> <owner/repo> <base> <checks>" for each main_key whose last main-red in
# events.tsv has no main-green after it, oldest first.
red_mains() {
  awk -F'\t' '$2 == "main-red" { split($5, w, " "); k = w[1] " " w[2]; red[k] = $3 " " $5; ord[k] = NR }
    $2 == "main-green" { delete red[$5] }
    END { for (k in red) print ord[k] "\t" red[k] }' "${EVENTS_LOG}" 2>/dev/null | sort -n | cut -f2- || true
}

# clear_red_main <key> <sha> <why> — main is green at <sha> for <key>: when red_mains holds that key
# (matched as text, never a pattern), log main-green <sha> <key> and retire its unstarted fixes.
clear_red_main() {
  red_mains | awk -v k="$1" '$2 " " $3 == k { found = 1 } END { exit !found }' || return 0
  record_event main-green "$2" "$1"
  retire_fixes "$1" - "$3"
}

# base_green <owner/repo> <base> — print the base's head and succeed when CI there is green now
# (ci_gate base), however it got green: a revert, a re-run, a merge swarm.sh did not make. Each gh
# read is bounded, and any failure reads as not green.
base_green() {
  local head
  head="$(within 30 gh api --jq .sha "repos/$1/commits/$2" 2>/dev/null </dev/null)" || return 1
  [[ "${head}" =~ ^[0-9a-f]{40}$ ]] && within 60 python3 "${SWARM_HOME}/bin/lib/ci_gate.py" base "$1" "${head}" >/dev/null 2>&1 </dev/null || return 1
  echo "${head}"
}

# green_mains — reconcile's: clear each red main whose base is green now (base_green).
green_mains() {
  local sha repo base checks head
  while read -r sha repo base checks; do
    [[ -n "${sha}" ]] || continue
    head="$(base_green "${repo}" "${base}")" || continue
    clear_red_main "${repo} ${base}" "${head}" "CI on ${base} is green at ${head:0:7}"
  done <<< "$(red_mains)"
}

# main_red — "<sha> <owner/repo> <base> <checks>" for the newest red main (red_mains) whose
# fix-main story is ready with no build and whose base is not green now (base_green); nothing when
# no red main of any repo and base has such a fix.
main_red() {
  local line pick="" sha repo base
  while read -r line; do
    read -r sha repo base _ <<< "${line}"
    [[ -n "${sha}" && "$(fm "${BOARD}/stories/fix-main-${sha:0:7}.md" status)" == ready ]] || continue
    ! one_off_started "fix-main-${sha:0:7}" && ! base_green "${repo}" "${base}" > /dev/null && pick="${line}"
  done <<< "$(red_mains)"
  [[ -z "${pick}" ]] || echo "${pick}"
}

# within <seconds> <command>... — the command in its own process group, the group KILLed after
# <seconds> (at least 1) with exit 142: gh, a Go program, ignores SIGALRM, and ci_gate's gh calls are
# its children. Else the command's own status (128+N for a signal).
within() {
  perl -e 'my $t = shift; $t = 1 if $t < 1;
    defined(my $p = fork) or exit 127;
    if (!$p) { setpgrp; exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; exit 142 };
    alarm $t; waitpid $p, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$@"
}

# wait_pr_fail <why> — wait-pr's end for anything but green or red: exit 2, so a caller tells it from red.
wait_pr_fail() { echo "swarm: wait-pr: $1" >&2; exit 2; }

# wait-pr [--timeout <seconds>] <pr-url> — print the PR's head SHA, then read ci_gate head on it every
# MERGE_POLL seconds (SWARM_MERGE_POLL) until nothing is pending, printing what it waits on whenever
# that changes. Exits 0 when all are green, printing each check; 1 on red; 2 on anything else, since a
# gh error is never pending: a transient one (WAIT_PR_TRANSIENT) is retried after WAIT_PR_RETRY,
# WAIT_PR_TRIES in a row at most, any other ends it at once. A new head has no check runs for a few
# minutes; none WAIT_PR_GRACE after the first read that found none ends it, pending statuses or not.
# At <seconds> (default MERGE_CI_SECONDS) it ends naming what it still waits on, with no read after
# it: no pause runs past it, and each read runs within the time left, so one that hangs ends it too.
# A check queued with no runner never settles. Exit 1 is only red (WAIT_PR_RED): swarm.sh's trap
# turns any other failure into 2. It reads the head once, with the same retries: a later push is not followed.
# That read also takes the PR's mergeable state: CONFLICTING ends it at once (exit 2, naming the base),
# and UNKNOWN on an open PR (GitHub still computing it) is read again every poll, beside the checks.
wait_pr() {
  local url limit="${SWARM_MERGE_CI_SECONDS:-${MERGE_CI_SECONDS}}" grace="${SWARM_WAIT_PR_GRACE:-${WAIT_PR_GRACE}}"
  local poll="${SWARM_MERGE_POLL:-${MERGE_POLL}}" retry="${SWARM_WAIT_PR_RETRY:-${WAIT_PR_RETRY}}" v
  local repo n head="" why what="" err rc pause left missed=0 last="" empty="" start=${SECONDS} oid mergeable base state unknown=""
  # Whole seconds, checked here: sleep failing on 20s or 1m would exit 1, which reads as red.
  for v in SWARM_MERGE_CI_SECONDS SWARM_WAIT_PR_GRACE SWARM_MERGE_POLL SWARM_WAIT_PR_RETRY; do
    [[ -z "${!v:-}" || "${!v}" =~ ^[0-9]+$ ]] || wait_pr_fail "${v} is '${!v}', not whole seconds"
  done
  if [[ "${1:-}" == --timeout ]]; then limit="${2:-}"; shift 2 || shift; fi
  url="${1:-}"
  [[ "${limit}" =~ ^[0-9]+$ && $# -eq 1 && "${url}" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] \
    || wait_pr_fail "usage: swarm.sh wait-pr [--timeout <seconds>] <pr-url>"
  repo="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
  # Base 10: in (( )) a leading 0 is octal, so 09 fails and 010 is 8.
  limit=$((10#${limit})); grace=$((10#${grace})); poll=$((10#${poll})); retry=$((10#${retry}))
  WAIT_PR_TMP="$(mktemp "${TMPDIR:-/tmp}/swarm-wait-pr.XXXXXX")" || wait_pr_fail "mktemp failed"
  while :; do
    rc=0; left=$((limit - (SECONDS - start)))
    if [[ -z "${head}" || -n "${unknown}" ]]; then
      # The head read is retried like a check read: a transient error is as likely here. Its stderr
      # is only the error: a notice beside a good answer (a gh update) is not one.
      # A conflicted PR runs no checks, so it ends here. UNKNOWN on an open PR is GitHub still
      # computing: the PR is read again each poll, its checks read beside it, so a red or green
      # check still ends the wait. A merged or closed PR stays UNKNOWN, so it is not read again.
      why="$(within "${left}" gh pr view "${n}" --repo "${repo}" --json headRefOid,mergeable,baseRefName,state \
        -q '[.headRefOid, .mergeable, .baseRefName, .state] | join(" ")' 2> "${WAIT_PR_TMP}")" || rc=$?
      read -r oid mergeable base state <<< "${why}"
      if [[ ${rc} -eq 0 && "${oid}" =~ ^[0-9a-f]{40}$ ]]; then
        [[ "${mergeable}" != CONFLICTING ]] || wait_pr_fail "conflicts with ${base}: merge origin/${base} in, then push"
        unknown=""; [[ "${mergeable}/${state}" != UNKNOWN/OPEN ]] || unknown=1
        [[ -n "${head}" ]] || { head="${oid}"; missed=0; echo "head ${head}"; }
        [[ -n "${unknown}" ]] || continue
      elif [[ ${rc} -ne 142 ]]; then
        rc=3; why="gh cannot read the head of ${url}: $(tail -1 "${WAIT_PR_TMP}")"
      fi
    fi
    if [[ ${rc} -eq 0 ]]; then
      why="$(within "$((limit - (SECONDS - start)))" python3 "${SWARM_HOME}/bin/lib/ci_gate.py" head "${repo}" "${head}")" || rc=$?
      [[ ${rc} -ne 2 || -z "${unknown}" ]] || why="${why}; mergeable state UNKNOWN"
    fi
    case ${rc} in
      0) echo "green:"; printf '  %s\n' "${why//; /$'\n'  }"; return 0 ;;
      1) echo "red: ${why}"
         # shellcheck disable=SC2034 # read by swarm.sh's EXIT trap
         WAIT_PR_RED=1; return 1 ;;
      2) missed=0
         if [[ "; ${why}; " == *"; no check runs; "* ]]; then
           empty="${empty:-${SECONDS}}"
           (( SECONDS - empty < grace )) \
             || wait_pr_fail "no check runs on ${head:0:7} after $((SECONDS - empty))s (${why})"
         fi
         [[ "${why}" == "${last}" ]] || echo "pending: ${why}"
         last="${why}"; what="still pending: ${why}"; pause=${poll} ;;
      142) wait_pr_fail "timed out after $((SECONDS - start))s: a read of ${head:-the head of ${url}} did not return${what:+; ${what}}" ;;
      *) err="$(sed -E 's#[^[:space:]]*/[^[:space:]]*##g' <<< "${why}")"
         if ! grep -qiwE "${WAIT_PR_TRANSIENT}" <<< "${err}" || ((++missed > WAIT_PR_TRIES)); then
           wait_pr_fail "${why:-ci_gate failed (exit ${rc})}"
         fi
         echo "retrying after ${why}"
         what="last error: ${why}"; pause=${retry} ;;
    esac
    # A pause that would reach the deadline is cut to it, and the wait ends there with no more reads:
    # a read after it could be green and exit 0 past the deadline.
    left=$((limit - (SECONDS - start)))
    if (( pause >= left )); then
      (( left <= 0 )) || sleep "${left}"
      wait_pr_fail "timed out after $((SECONDS - start))s, ${what}"
    fi
    sleep "${pause}"
  done
}

# release_check <owner/repo> <base> <head> — merge --release's checks past the file list: the PR goes
# into the project's base, its plugin.json differs from the base's only in "version" (compared as
# sorted JSON text, so true and 1 differ), since hooks, mcpServers and command paths there run code,
# and that version is MAJOR.MINOR.PATCH and greater than the base's.
release_check() {
  local want old new why
  want="$(base_for "${PROJECT_DIR}")" || merge_fail "--release: cannot tell the project's base branch"
  [[ "$2" == "${want}" ]] || merge_fail "--release: ${MERGE_TARGET} goes into $2, not ${want}, the project's base"
  old="$(gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/.claude-plugin/plugin.json?ref=$2")" \
    || merge_fail "--release: gh cannot read .claude-plugin/plugin.json on $2"
  new="$(gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/.claude-plugin/plugin.json?ref=$3")" \
    || merge_fail "--release: gh cannot read .claude-plugin/plugin.json at ${3:0:7}"
  why="$(OLD="${old}" NEW="${new}" BASE="$2" python3 -c 'import json,os,re
e = os.environ
o, n = json.loads(e["OLD"]), json.loads(e["NEW"])
v, w = n.pop("version", None), o.pop("version", None)
semver = lambda x: tuple(map(int, x.split("."))) if isinstance(x, str) and re.fullmatch(r"\d+\.\d+\.\d+", x) else None
if semver(v) is None:
    print("its version %r is not MAJOR.MINOR.PATCH" % (v,))
elif semver(w) is None or semver(v) <= semver(w):
    print("its version %s is not greater than %r on %s" % (v, w, e["BASE"]))
elif json.dumps(o, sort_keys=True) != json.dumps(n, sort_keys=True):
    print("it changes more of .claude-plugin/plugin.json than its version; if %s changed plugin.json after the release branch was cut, merge origin/%s into it and retry" % (e["BASE"], e["BASE"]))' 2>/dev/null)" \
    || why="cannot read .claude-plugin/plugin.json as JSON"
  [[ -z "${why}" ]] || merge_fail "--release: ${MERGE_TARGET}: ${why}"
}

# watch_scope [--epic <slug>|--backlog] [repo...] — set WATCH_HEADS and WATCH_NAMES for watch. With
# --epic, only that epic's stories' story/<slug> heads count, and with --backlog only those of stories
# with no epic (WATCH_HEADS empty: every story/* head); the default repos are then those stories'
# repos: a conductor must not wake for another epic's PR on the same board. WATCH_NAMES holds each
# repo as the board names it (repo_slug resolves one). Dies with no repo to watch.
watch_scope() {
  local epic="" stories=("${BOARD}"/stories/*.md) f
  WATCH_HEADS=""
  if [[ "${1:-}" == --epic || "${1:-}" == --backlog ]]; then
    # The backlog's stories are those whose epic: is empty; heads stays non-empty, so no other PR counts.
    if [[ "$1" == --epic ]]; then
      epic="${2:?watch --epic needs an epic slug}"; shift 2
      [[ -f "${BOARD}/epics/${epic}.md" ]] || die "watch: no epic ${BOARD}/epics/${epic}.md"
    else shift; fi
    stories=(); WATCH_HEADS="-"
    for f in "${BOARD}"/stories/*.md; do
      [[ -f "${f}" && "$(basename "${f}")" != README.md && "$(fm "${f}" epic)" == "${epic}" ]] || continue
      stories+=("${f}"); WATCH_HEADS="${WATCH_HEADS} story/$(basename "${f}" .md)"
    done
  fi
  WATCH_NAMES=("$@")
  # Default: the project (when it is a repo) plus every repo a story names, so a new repo needs no edit here.
  if [[ ${#WATCH_NAMES[@]} -eq 0 ]]; then
    local own=""; [[ ${PROJECT_IS_GIT} == 1 ]] && own="$(basename "${PROJECT_DIR}")"
    read -r -a WATCH_NAMES <<< "${own} $( (( ${#stories[@]} )) && sed -n 's/^repo: *//p' "${stories[@]}" 2>/dev/null | sort -u | tr '\n' ' ')"
  fi
  # With nothing to poll, watch's loop would sleep forever.
  [[ ${#WATCH_NAMES[@]} -gt 0 ]] || die "watch: no repo to watch${epic:+ for epic ${epic}}"
}

# repo_slug <name> — the repo's owner/name, from its own origin: repos on one board need not share an
# owner. Prints why and fails when there is no such repo or it has no GitHub origin.
repo_slug() {
  local src
  src="$(repo_dir "$1")" || { echo "watch $1: ${src}"; return 1; }
  gh repo view "$(git -C "${src}" remote get-url origin)" --json nameWithOwner -q .nameWithOwner \
    || { echo "no GitHub origin for ${src}"; return 1; }
}

# watch_repos die|warn — set WATCH_REPOS to WATCH_NAMES resolved (repo_slug), each owner/name once: a
# story's repo: can name the project's own repo. One that cannot be resolved stops watch (die), or for
# next (warn) is warned of on stderr and left out.
watch_repos() {
  local name r
  WATCH_REPOS=()
  for name in "${WATCH_NAMES[@]}"; do
    if [[ "$1" == die ]]; then
      r="$(repo_slug "${name}")" || die "${r}"
    elif ! r="$(repo_slug "${name}" 2>/dev/null)"; then
      echo "warning: ${r}, so its PRs waiting for a review are unknown" >&2; continue
    fi
    [[ " ${WATCH_REPOS[*]-} " == *" ${r} "* ]] || WATCH_REPOS+=("${r}")
  done
}

# queued_line <owner/repo> <n> <sha> <branch> — "queued: <repo> #<n> <branch> green <m>m with no review
# on <sha7>" for an open, mergeable PR (the caller's to check; an open PR has not merged) whose story an
# agent builds (agent_kind: a lead story's PR is the lead's), with no review agent's review on <sha>
# (review_on_head), and green by ci_gate's rule for queue_minutes or more (ci_gate age). The file
# checks come first, so a reviewed head costs no gh call. Nothing otherwise, or when gh cannot tell.
queued_line() {
  local slug="${4#story/}" m
  if [[ -f "${BOARD}/stories/${slug}.md" ]] && ! agent_kind "$(fm "${BOARD}/stories/${slug}.md" kind)"; then return 0; fi
  if review_on_head "${slug}" "$3"; then return 0; fi
  m="$(ci_gate age "$1" "$3" 2>/dev/null)" || return 0
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${m}" =~ ^[0-9]+$ ]] && (( m >= CFG_queue_minutes )); then echo "queued: $1 #$2 $4 green ${m}m with no review on ${3:0:7}"; fi
}

# queued_prs <owner/repo> <heads> — queued_line for each open, mergeable story/* PR in <heads> (empty:
# every one), leaving out heads already sent to their conductor (watch-seen's queued <sha7>, from
# watch or queued_sent). next's lines; warns on stderr when gh cannot list the PRs.
queued_prs() {
  local rows n sha br
  rows="$(gh pr list -R "$1" --state open --json number,headRefOid,headRefName,mergeable \
    -q '.[] | select((.headRefName | startswith("story/")) and .mergeable == "MERGEABLE") | "\(.number) \(.headRefOid) \(.headRefName)"')" \
    || { echo "warning: gh cannot list $1's open PRs, so which of them wait for a review is unknown" >&2; return 0; }
  while read -r n sha br; do
    [[ -n "${n}" && ( -z "$2" || " $2 " == *" ${br} "* ) ]] || continue
    if grep -qx "queued ${sha:0:7}" "${STATE_DIR}/watch-seen" 2>/dev/null; then continue; fi
    queued_line "$1" "${n}" "${sha}" "${br}"
  done <<< "${rows}"
}

# queued_sent <file> — when the lead sends a conductor queued: lines (tell note), record each line's
# head in watch-seen as watch records one it reports (queued <sha7>, the line's own), so neither watch
# nor next sends that head's line again.
queued_sent() {
  local seen="${STATE_DIR}/watch-seen" s
  mkdir -p "${STATE_DIR}"; touch "${seen}"
  sed -n 's/^queued: .* with no review on \([^ (]*\).*/\1/p' "$1" | while IFS= read -r s; do
    grep -qx "queued ${s}" "${seen}" || echo "queued ${s}" >> "${seen}"
  done
}

# watch [--epic <slug>|--backlog] [repo...] — block until a story/* PR in these repos (watch_scope)
# needs the lead, print one line saying which and why, and exit 0. A PR needs the lead when its checks on a new head have all finished,
# when it conflicts with its base (a conflicted PR runs no checks, so waiting on checks never ends),
# when its head has had no check at all for WATCH_STALL_SECS (default 600), or when its head, its
# checks reported finished, has waited green for a review (queued_line). An agent of this
# project whose session is waiting (herdr's blocked, for an agent herdr answers for) also needs the
# lead, named with what it waits for. Each head is reported once, and each agent's wait once, until a
# poll finds that agent no longer waiting (state in .swarm/state).
watch_prs() {
  local WATCH_HEADS WATCH_NAMES WATCH_REPOS repo
  watch_scope "$@"; watch_repos die
  local heads="${WATCH_HEADS}" repos=("${WATCH_REPOS[@]}") seen="${STATE_DIR}/watch-seen" stall="${WATCH_STALL_SECS:-600}" n sha br mergeable age total pending q
  mkdir -p "${STATE_DIR}"; touch "${seen}"
  while :; do
    for repo in "${repos[@]}"; do
      while read -r n sha br mergeable age; do
        [[ -n "${n}" ]] || continue
        [[ -z "${heads}" || " ${heads} " == *" ${br} "* ]] || continue
        if [[ "${mergeable}" == CONFLICTING ]] && ! grep -qx "conflict ${sha}" "${seen}"; then
          echo "conflict ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} CONFLICTS with its base"; return 0
        fi
        if grep -qx "done ${sha}" "${seen}"; then
          # Its finished checks are reported: once, a head left green with no review is queued.
          if [[ "${mergeable}" == MERGEABLE ]] && ! grep -qx "queued ${sha:0:7}" "${seen}"; then
            q="$(queued_line "${repo}" "${n}" "${sha}" "${br}")"
            if [[ -n "${q}" ]]; then echo "queued ${sha:0:7}" >> "${seen}"; echo "${q}"; return 0; fi
          fi
          continue
        fi
        read -r total pending < <(gh api "repos/${repo}/commits/${sha}/check-runs" \
          -q '"\(.check_runs|length) \([.check_runs[]|select(.status!="completed")]|length)"')
        if [[ "${total:-0}" -gt 0 && "${pending}" == 0 ]]; then
          echo "done ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} checks finished on ${sha:0:7}"; return 0
        fi
        if [[ "${total:-0}" == 0 && "${age}" -gt "${stall}" ]] && ! grep -qx "stall ${sha}" "${seen}"; then
          echo "stall ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} has had no checks for ${age}s"; return 0
        fi
      done < <(gh pr list -R "${repo}" --state open --json number,headRefName,headRefOid,mergeable,updatedAt \
        -q '.[]|select(.headRefName|startswith("story/"))|"\(.number) \(.headRefOid) \(.headRefName) \(.mergeable) \((now - (.updatedAt|fromdateiso8601))|floor)"')
    done
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
      local agents sessions now e news="" tmp
      # Only agents in panes this project opened: herdr lists every project's. Each one's state is
      # panes.py's agent_state: its session's, else herdr's (codex, or no session recorded). One line
      # per agent waiting, "<name> (<what it waits for>)". A read that fails (herdr's list, Claude
      # Code's, or the reader) changes nothing: a failed Claude list would read every session unknown.
      if agents="$(herdr agent list 2>/dev/null)" && sessions="$(claude_agents)" \
        && now="$(printf '%s' "${agents}" | SWARM_OWN="$(own_panes)" SWARM_SESSIONS="${sessions}" \
        SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *
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
    nap 60
  done
}

# ref_in <repo-dir> <ref> <branch> — 0 when <ref>'s head is in <branch>, 1 when it is not, 2 when
# git cannot tell (a missing ref).
ref_in() { local rc=0; git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null || rc=$?; (( rc <= 1 )) || rc=2; return "${rc}"; }

# fetch_branch <repo-dir> <branch> — fetch origin's <branch> into origin/<branch>; returns 2 when
# origin answered and has no such branch, 1 for any other failure.
fetch_branch() {
  local rc=0
  git -C "$1" fetch -q origin "+refs/heads/$2:refs/remotes/origin/$2" 2>/dev/null && return 0
  git -C "$1" ls-remote --exit-code -q origin "refs/heads/$2" >/dev/null 2>&1 || rc=$?
  [[ ${rc} == 2 ]] && return 2
  return 1
}

# stacked_parents <child> — the parents the child's current build stacked on: the `stacked <child>`
# event just before its last ok `story <child>` (main logs story once the build is done), or one
# with no story after it yet (a build still starting). A later ok build with no stacked event
# (rebuilt from the base) has none. A stacked event a story that failed, a close or a reset
# follows belongs to no build: a failed or abandoned start.
stacked_parents() {
  awk -F'\t' -v s="$1" '$3 != s { next }
    $2 == "stacked" && index($5, "ok (on ") == 1 { pend = substr($5, 8, length($5) - 8) }
    $2 == "story" && index($5, "ok") == 1 { cur = pend; pend = ""; next }
    $2 == "story" || $2 ~ /^(close|reset)(:|$)/ { pend = "" }
    END { print (pend != "" ? pend : cur) }' "${EVENTS_LOG}" 2>/dev/null || true
}

# stacked_parent <repo-dir> <child-ref> <p> — what the child must do about parent p: `merge
# origin/story/<p>` when p's PR is open (or p, on the board, has none) and its head is not in
# <child-ref>; `merged` when p's PR merged, or p's file is gone and it has no PR; `lost story/<p>`
# when p's only PRs closed unmerged (a dropped p too), or its branch is gone while its PR is open or
# it is on the board. Nothing when the child has it. A gh or git call that fails returns 1.
stacked_parent() {
  local src="$1" have="$2" p="$3" state rc=0
  state="$( (cd "${src}" && gh pr list --head "story/${p}" --state all --json state) 2>/dev/null \
    | json "next((s for s in ('OPEN', 'MERGED', 'CLOSED') if any(x['state'] == s for x in d)), '')" 2>/dev/null)" || return 1
  [[ -n "${state}" || -f "${BOARD}/stories/${p}.md" ]] || state=MERGED   # finished with no PR
  case "${state}" in
    CLOSED) echo "lost story/${p}" ;;
    MERGED) echo merged ;;
    *)
      fetch_branch "${src}" "story/${p}" || rc=$?
      case ${rc} in 0) ;; 2) echo "lost story/${p}"; return ;; *) return 1 ;; esac
      rc=0; ref_in "${src}" "origin/story/${p}" "${have}" || rc=$?
      case ${rc} in 0) ;; 1) echo "merge origin/story/${p}" ;; *) return 1 ;; esac ;;
  esac
}

# stacked_child <story> — stacked_lines' lines for one story. The child's branch is origin's (fetched),
# so a merge not yet pushed still shows; its local branch only while origin has none. Parents that
# merged give one base line; the base is looked up once per repo in a row (STACKED_SRC).
stacked_child() {
  local child src parents p line have builder="" done_ps="" rc=0
  child="$(basename "$1" .md)"
  src="$(repo_dir "$(fm "$1" repo)")" || return 0
  [[ -d "$(worktree_for "${src}" "${child}")" ]] || return 0
  parents="$(stacked_parents "${child}")"; [[ -n "${parents}" ]] || return 0
  # Outside herdr the agents cannot be read, so no line claims the builder is gone.
  [[ "${HERDR_ENV:-}" != 1 || "$(builder_state "${child}")" != none ]] || builder=" (no builder)"
  fetch_branch "${src}" "story/${child}" || rc=$?
  case ${rc} in
    0) have="origin/story/${child}" ;;
    2) have="story/${child}" ;;
    *) echo "${child}: could not check story/${child} on origin${builder}"; return 0 ;;
  esac
  for p in ${parents//,/ }; do
    if [[ ! "${p}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then echo "${child}: could not check ${p}${builder}"; continue; fi
    line="$(stacked_parent "${src}" "${have}" "${p}")" || line="could not check ${p}"
    case "${line}" in merged) done_ps+="${done_ps:+, }${p}" ;; ?*) echo "${child}: ${line}${builder}" ;; esac
  done
  [[ -n "${done_ps}" ]] || return 0
  # ponytail: caches the last repo's base only; boards span few repos, so a miss is one more fetch.
  [[ "${STACKED_SRC}" == "${src}" ]] || { STACKED_BASE="$(base_for "${src}" 2>/dev/null)" || STACKED_BASE=""; STACKED_SRC="${src}"; }
  rc=2; [[ -z "${STACKED_BASE}" ]] || { rc=0; ref_in "${src}" "origin/${STACKED_BASE}" "${have}" || rc=$?; }
  case ${rc} in
    0) ;;
    1) echo "${child}: merge origin/${STACKED_BASE} (${done_ps} merged)${builder}" ;;
    *) echo "${child}: could not check the base for ${done_ps}${builder}" ;;
  esac
}

# stacked_lines — one line per parent of a stacked build that needs action (stacked_child): a ready
# or blocked story with a worktree whose current build stacked on parents. A line ends (no builder)
# when herdr shows no builder open for the child; a gh or git call that fails gives a `could not
# check` line. herdr, gh and git read no stdin, which feeds the loop, and git never prompts for a
# credential or an ssh passphrase on the terminal: status must not hang, so such a fetch fails into
# a could-not-check line.
stacked_lines() {
  local story
  STACKED_SRC=""; STACKED_BASE=""
  while IFS= read -r story; do
    case "$(fm "${story}" status)" in
      ready|blocked)
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" stacked_child "${story}" </dev/null ;;
    esac
  done < <(board stories)
}

# status [--all] — one summary for the user: the agents that need a look or are working, the stacked
# builds whose parent moved or merged (stacked_lines; no section when there are none), what is
# waiting on them, and what `next` would do; idle agents and blocked stories are only counted unless
# --all. A pane with no agent in it is shown as empty: a start that failed. Panes closed by hand are
# left out. A Claude agent's state is its session's (one claude_agents call per run); herdr's word
# only for codex, an agent with no session recorded, and a retired one.
status_report() {
  local all="${1:-}" agents panes waiting sessions
  if [[ "${HERDR_ENV:-}" == 1 ]] && agents=$(herdr agent list 2>/dev/null) && panes=$(herdr pane list 2>/dev/null); then
    sessions="$(claude_agents)" || sessions=""   # a failed call reads as unknown, as an empty one does
    SWARM_OWN="$(own_panes)" SWARM_SESSIONS="${sessions}" \
      python3 "${SWARM_HOME}/bin/lib/status_report.py" "${STATE_DIR}" "${agents}" "${panes}" "${all}" "${AGENTS_LOG}" "${CLAUDE_PROJECTS}"
  else
    echo "Agents: not inside herdr, so their states are not available"
  fi
  local stacked; stacked="$(stacked_lines)" || true
  [[ -z "${stacked}" ]] || printf '\nStacked\n  %s\n' "${stacked//$'\n'/$'\n'  }"
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

# stacked_on <story> <open slugs> — print <open slugs> when a blocked story with no build yet can
# start on them: each is a story in its own repo, ready or in review, with an open PR (review's prs:
# line, else gh's on story/<p>). Fails otherwise, a gh failure too, and a child review held
# (held_by:) waits until its parents finish. Fails with 2 when only a build already there (its
# worktree or story/<slug>) is in the way.
stacked_on() {
  local story="$1" p f src
  [[ -z "$(get_fm "${story}" held_by)" ]] || return 1
  src="$(repo_dir "$(fm "${story}" repo)")" || return 1
  for p in $2; do
    f="${BOARD}/stories/${p}.md"
    [[ -f "${f}" && "$(repo_dir "$(fm "${f}" repo)")" == "${src}" ]] || return 1
    case "$(fm "${f}" status)" in
      review) [[ -z "$(fm "${f}" prs)" ]] || continue ;;
      ready) ;;
      *) return 1 ;;
    esac
    open_pr "${src}" "${p}" >/dev/null || return 1
  done
  ! build_exists "${src}" "$(basename "${story}" .md)" || return 2
  echo "$2"
}
