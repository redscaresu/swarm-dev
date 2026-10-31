#!/usr/bin/env bash
# events_tail_lead_test.sh — lifecycle.sh's events.tsv readers read the outcome without its key=value tail
# (EVENT_OUTCOME_AWK's outcome, events_outcome.outcome, or a cut at EVENT_SEP), so a tail on every row changes
# nothing they decide. Each reader runs with bin/lib sourced over a stand-in project (events_project) and over
# its copy with ` ~~ k=v` on every row, and same_output compares the two:
#   - over the v0.29.1 fixture plus four synthetic merge and review rows, for every target of a line these
#     readers read (story, escalate, agent, reset*, review, merge; any other target reads as none): build_started
#     and top_rung_since by what they print, stepped_up_since and user_merges by exit status. Untailed, each
#     text reader prints a time for some target, and each predicate succeeds for one target and fails for another.
#   - over rows no live log holds: no_agent_events (a reconcile `ok (reopened)`), no_review_events (a reopen,
#     a findings tell, the exact mktemp failure), review_restart_try (`(try N of M) started`, `started (try N
#     of M)`, a reopen) and sign_blocked_lines (sign-blocked: and sign-clear: incidents).
#   - a tell ok row: stuck_lines counts it as a findings tell, resend_pass as a delivery.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
TAIL=" ~~ k=v"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# with_lib — source bin/lib over the project in the cwd, as swarm.sh does. Run it in a subshell: the readers
# below are each one, through same_output's $(...). Its agent_name is swarm.sh's with no forks, for the
# lower-case names these rows hold: build_started calls it once a target.
with_lib() {
  PROJECT_DIR="$(pwd -P)"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/docs"; AGENT_NAME_MAX=32
  CFG_goal=off; CFG_step_up_findings=3; CFG_top_rung_rounds=2; CFG_stall_minutes=30
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/board.sh
  source "${REPO}/bin/lib/board.sh"
  # shellcheck source=bin/lib/build.sh
  source "${REPO}/bin/lib/build.sh"
  # shellcheck source=bin/lib/merge.sh
  source "${REPO}/bin/lib/merge.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  agent_name() { local n="${1//[^a-z0-9_-]/-}"; [[ "${n}" =~ ^[a-z] ]] || n="s${n}"; printf '%s' "${n:0:32}"; }
}

# pair <name> <events file> — the projects ${ROOT}/plain/<name> and ${ROOT}/tailed/<name>, the second with the
# tail on every row; sets PLAIN and TAILED.
pair() {
  PLAIN="${ROOT}/plain/$1"; TAILED="${ROOT}/tailed/$1"
  events_project "${PLAIN}" "$2" && events_project "${TAILED}" "$2" "${TAIL}"
}

# --- the fixture, every target.
# The fixture holds no merge line for a slug that waits on the user: zzsa's held merge does, and zzsb's review
# after its held merge clears it.
FX="${ROOT}/fixture.tsv"
cp "${EVENTS_FIXTURE}" "${FX}"
printf '%s\n' $'2026-10-29T02:00:00Z\treview\tzzsa\twa:pa\tok (https://github.com/o/r/pull/30)' \
  $'2026-10-29T02:05:00Z\tmerge\tzzsa\twa:pa\theld: https://github.com/o/r/pull/30 costs money, so the user merges it' \
  $'2026-10-29T02:10:00Z\tmerge\tzzsb\twa:pa\theld: https://github.com/o/r/pull/31 costs money, so the user merges it' \
  $'2026-10-29T02:15:00Z\treview\tzzsb\twa:pa\tok (https://github.com/o/r/pull/31)' >> "${FX}"

# fixture_reads — `<reader>\t<target>\t<result>` for each reader and every target of a line it reads in the
# project's events.tsv: a text reader's output, a predicate's exit status. Each target costs some ten forks, so
# a target no such line names, for which every reader gives nothing or fails whatever the tail, is skipped.
# user_merges runs under merge = agent with no story fields and no cost, so only the events decide it.
fixture_reads() (
  with_lib
  CFG_merge=agent; get_fm() { :; }; costs_tag() { :; }
  local t rc
  while IFS= read -r t; do
    printf 'build_started\t%s\t%s\n' "${t}" "$(build_started "${t}")"
    printf 'top_rung_since\t%s\t%s\n' "${t}" "$(top_rung_since "${t}")"
    rc=0; stepped_up_since "${t}" 2000-01-01T00:00:00Z || rc=$?
    printf 'stepped_up_since\t%s\t%s\n' "${t}" "${rc}"
    rc=0; user_merges "docs/stories/${t}.md" || rc=$?
    printf 'user_merges\t%s\t%s\n' "${t}" "${rc}"
  done < <(awk -F'\t' '$2 ~ /^(story|escalate|agent|reset.*|review|merge)$/ { print $3 }' .swarm/events.tsv | LC_ALL=C sort -u)
)

# Each project's reads run once, the two side by side, into reads.tsv, which same_output compares and the
# checks after it read.
pair fixture "${FX}"
(cd "${PLAIN}" && fixture_reads > reads.tsv) & plain_pid=$!
(cd "${TAILED}" && fixture_reads > reads.tsv) & tailed_pid=$!
wait "${plain_pid}"; wait "${tailed_pid}"
check "build_started, top_rung_since, stepped_up_since and user_merges give the same result for every target with a tail" \
  same_output "${PLAIN}" "${TAILED}" cat reads.tsv
out="$(cat "${PLAIN}/reads.tsv")"
# results <reader> — the distinct results <reader> gave untailed, one a line.
results() { awk -F'\t' -v r="$1" '$1 == r { print $3 }' <<< "${out}" | LC_ALL=C sort -u | paste -sd' ' -; }
for r in build_started top_rung_since; do
  check "${r} prints a time for at least one fixture target" grep -qE "^${r}"$'\t[^\t]+\t''20[0-9-]+T' <<< "${out}"
done
for r in stepped_up_since user_merges; do
  check "${r} succeeds for one fixture target and fails for another" test "$(results "${r}")" = "0 1"
done
check "user_merges succeeds for zzsa, held for the user, and fails for zzsb, reviewed since" \
  test "$(grep -E $'^user_merges\tzzs[ab]\t' <<< "${out}" | cut -f3 | paste -sd' ' -)" = "0 1"
# step_status <slug> <time> — stepped_up_since's exit status.
step_status() ( with_lib; local rc=0; stepped_up_since "$1" "$2" || rc=$?; echo "${rc}" )
check "stepped_up_since succeeds for zzak, stepped up, before its escalate line and fails after it" \
  test "$(cd "${PLAIN}" && step_status zzak 2000-01-01T00:00:00Z) $(cd "${PLAIN}" && step_status zzak 2099-01-01T00:00:00Z)" = "0 1"

# --- inline rows: forms no live log holds.
IN="${ROOT}/inline.tsv"
{
  # no_agent_events: zzna's builder closed, then its PR closed unmerged (reopened), so it is left out; zznb's closed.
  printf '2026-10-01T00:00:%02dZ\t%s\t%s\twa:pa\t%s\n' \
    1 story zzna ok 2 close zzna ok 3 reconcile zzna 'ok (reopened)' 4 story zznb ok 5 close zznb ok
  # no_review_events: zzra's review start before a reopen is no review; zzrb's failed start names its PR and a
  # findings tell came after; zzrc's start failed on mktemp, after its brief.
  printf '2026-10-02T00:00:%02dZ\t%s\t%s\twa:pa\t%s\n' \
    1 story zzra ok 2 review-agent zzra ok 3 reconcile zzra 'ok (reopened)' \
    4 story zzrb ok 5 review-agent zzrb 'review-agent: https://github.com/o/r/pull/7 is not green' 6 tell zzrb ok \
    7 story zzrc ok 8 review-agent zzrc 'review-agent: mktemp failed; nothing was started'
  # review_restart_try: zzta's try 1 began with no outcome; zztb's restart ran try 1; zztc's try ran nothing,
  # then an interrupt; zztd's try 2 began, then its PR closed unmerged.
  printf '2026-10-03T00:00:%02dZ\t%s\t%s\twa:pa\t%s\n' \
    1 story zzta ok 2 review-agent:try zzta '(try 1 of 3) started' \
    3 story zztb ok 4 review-agent:restart zztb 'started (try 1 of 3)' \
    5 story zztc ok 6 review-agent zztc 'review-agent: review-zztc did not start; it ran nothing: no pane (try 1 of 3)' \
    7 review-agent zztc interrupted \
    8 story zztd ok 9 review-agent:try zztd '(try 2 of 3) started' 10 reconcile zztd 'ok (reopened)'
  # sign_blocked_lines: zzsg's builder is blocked; zzsh's was, then cleared.
  printf '2026-10-04T00:00:%02dZ\tincident\t%s\t-\t%s\n' \
    1 zzsg 'sign-blocked: zzsg (unsigned work since 2026-10-04T00:00:00Z)' \
    2 zzsh 'sign-blocked: zzsh (unsigned work since 2026-10-04T00:00:00Z)' 3 zzsh 'sign-clear: zzsh'
} > "${IN}"

inline_no_agent() ( with_lib; no_agent_events zzna zzna review-zzna - zznb zznb review-zznb - )
inline_no_review() ( with_lib; no_review_events zzra review-zzra zzrb review-zzrb zzrc review-zzrc )
inline_restart_try() (
  with_lib
  local s
  for s in zzta zztb zztc zztd; do echo "${s}: $(review_restart_try "${s}")"; done
)
# A worktree for zzsg and zzsh with a commit at the incidents' time and a change since: unsigned work.
WT="${ROOT}/wt"
git init -q "${WT}"
echo a > "${WT}/a"
git -C "${WT}" add a
GIT_COMMITTER_DATE=2026-10-04T00:00:00Z git -C "${WT}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm a
echo b > "${WT}/a"
inline_sign() (
  with_lib
  LEAD_AGENTS_READ=1; LEAD_AGENTS_OK=1; LEAD_AGENTS=listed
  list_field() { echo w:p1; }; fm() { echo r; }; repo_dir() { echo "${WT}"; }; worktree_for() { echo "${WT}"; }
  sign_blocked_lines
)

pair inline "${IN}"
check "no_agent_events leaves out the reopened story with a tail as without" \
  same_output "${PLAIN}" "${TAILED}" inline_no_agent
check "no_agent_events lists zznb alone untailed" \
  test "$(cd "${PLAIN}" && inline_no_agent)" = "zznb 0 2026-10-01T00:00:05Z zznb review-zznb"
check "no_review_events gives the same rows with a tail as without" \
  same_output "${PLAIN}" "${TAILED}" inline_no_review
check "no_review_events untailed: no zzra, zzrb's PR and findings round, zzrc's brief" \
  test "$(cd "${PLAIN}" && inline_no_review)" = $'zzrb 0 https://github.com/o/r/pull/7 1 0\nzzrc 0 - 0 1'
check "review_restart_try gives the same with a tail as without" \
  same_output "${PLAIN}" "${TAILED}" inline_restart_try
check "review_restart_try untailed: unclear 1, restart 2, restart 2, nothing after a reopen" \
  test "$(cd "${PLAIN}" && inline_restart_try)" = $'zzta: unclear 1\nzztb: restart 2\nzztc: restart 2\nzztd: '
check "sign_blocked_lines gives the same line with a tail as without" \
  same_output "${PLAIN}" "${TAILED}" inline_sign
check "sign_blocked_lines names zzsg alone untailed" \
  grep -q '^sign-blocked: zzsg (their signing key is locked' <<< "$(cd "${PLAIN}" && inline_sign)"

# --- a tell ok row: a findings tell for stuck_lines, a delivery for resend_pass.
TELL="${ROOT}/tell.tsv"
printf '2026-02-02T00:00:00Z\ttell\tzzst\twa:pa\tok\n' > "${TELL}"
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\necho "an idle box"\n' > "${ROOT}/bin/herdr"
chmod +x "${ROOT}/bin/herdr"

# tell_stuck — stuck_lines over one open PR of zzst, its head first seen before the tell, the builder idle.
tell_stuck() (
  with_lib
  mkdir -p "${LEAD_DIR}"; echo listed > "${LEAD_PRS}"; echo "zzst abc 1700000000 -" > "${LEAD_PR_HEADS}"
  story_pr_rows() { echo "zzst https://github.com/o/r/pull/9 abc MERGEABLE - - -"; }
  review_pass() { return 1; }; LEAD_AGENTS_READ=1; LEAD_AGENTS_OK=1; LEAD_AGENTS=listed
  list_field() { echo w:p1; }; within() { return 1; }; session_state() { echo idle; }
  bg_running() { return 1; }; stuck_test_run() { return 1; }
  stuck_lines
)
# tell_resend — resend_pass for zzst, idle in w:p1 with a clear box; prints what it recorded in LEAD_RESENT.
tell_resend() (
  with_lib
  PATH="${ROOT}/bin:${PATH}"
  LEAD_AGENTS_OK=1; LEAD_AGENTS='{"result":{"agents":[{"name":"zzst","pane_id":"w:p1","agent_status":"idle"}]}}'
  own_panes() { echo w:p1; }; conductor_name() { echo conduct-backlog; }; resend_busy() { return 1; }
  resend_pass
  cat "${LEAD_RESENT}"
)

pair tell "${TELL}"
check "stuck_lines counts a tailed tell ok row as told, as the untailed one" \
  same_output "${PLAIN}" "${TAILED}" tell_stuck
check "stuck_lines untailed gives zzst's findings stuck: line" \
  grep -q '^stuck: zzst https://github.com/o/r/pull/9 (findings pending ' <<< "$(cd "${PLAIN}" && tell_stuck)"
check "resend_pass counts a tailed tell ok row as delivered, as the untailed one" \
  same_output "${PLAIN}" "${TAILED}" tell_resend
check "resend_pass untailed records the tell's delivery" \
  test "$(cd "${PLAIN}" && tell_resend)" = $'zzst\t2026-02-02T00:00:00Z\ttell\t1'

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
