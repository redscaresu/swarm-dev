#!/usr/bin/env bash
# incidents_test.sh — the incident events, their helpers stubbed: wait_agent's timeout writes one
# wait-timeout line (not for an agent still working: a busy session, or herdr's route timing out with
# nothing printed and read_state saying herdr:working; nor for a conductor's hour slice, nor for
# herdr's wait failing early); an expired
# login one login line however often it is waited on, and one more after a resume (matched through
# agent_name, so a long slug's counts) or a new start, but not after a note, a failed tell or a stalled,
# sign-blocked or sign-clear incident; a close
# that ends a stuck builder's build with no open or merged PR one idle-no-pr line (its waits none), and
# none for a stalled, paused, cleared-on-error or impossible close or a build with an open PR. The
# close's and the login's lines carry the builder's slug= and role= (agent_fields, whose cases come
# next: a review agent, a conductor, a retired -done2 name, a name with no agents.tsv line and one cut
# at 32 characters). Then flow's incidents section over a fixture events.tsv holding six kinds on two
# days prints the per-day count of each. Over the same fixture, with intervene lines of two causes and
# stalled incidents added, it counts per kind and cause, lists each stalled incident's bg, test and sign
# (- when not measured) and counts the false stalls.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# As swarm.sh sets them, for the libraries sourced alone below.
export AGENT_NAME_MAX=32 BUILDER_ROLES="code code-risky code-sonnet docs chore escalate verify"
# swarm.sh's agent_name, for the same.
agent_name() { local n; n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-'); [[ "${n}" =~ ^[a-z] ]] || n="s${n}"; printf '%s' "${n:0:32}"; }
# sites <case> [status] — run one case in a fresh project, in a subshell with agents.sh and lifecycle.sh
# sourced and their helpers stubbed, and print the incident lines' command, target and outcome (without
# its tail). Agent a is a code builder in agents.tsv.
sites() (
  PROJECT_DIR="${ROOT}/p-$1${2:+-$2}"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_goal=off; CFG_step_up_findings=3; CFG_top_rung_rounds=2
  mkdir -p "${PROJECT_DIR}/.swarm"
  printf '2026-10-30\tcode\ta\tclaude\topus\thigh\t-\n' > "${PROJECT_DIR}/.swarm/agents.tsv"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  impossible_refused() { return 1; }
  impossible_story() { :; }
  json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
  own_target() { echo w:1; }
  session_state() { echo idle; }
  login_expired() { return 1; }
  nudge_reason() { echo "you are idle and story/a has no PR"; }
  herdr() { :; }
  archive_session() { :; }
  close_panes() { :; }
  clear_build() { :; }
  held_story() { :; }
  escalate_story() { :; }
  get_fm() { :; }
  set_fm() { :; }
  stub_prs='[{"state":"CLOSED"}]'
  failed_build() { echo "${stub_prs}"; }
  st="${2:-busy}"   # the status settle times out on
  slow_timeout() { sleep 1; echo "${st}"; return 1; }
  case "$1" in
    timeout) settle() { slow_timeout; }; wait_agent a 1000 ;;
    herdr-timeout) settle() { sleep 1; return 1; }; read_state() { echo "${st}"; }; wait_agent a 1000 ;;
    slice) settle() { slow_timeout; }; SWARM_WAIT_SLICE=1 wait_agent conduct-e 1000 ;;
    herdr-fails) settle() { echo "${st}"; return 1; }; wait_agent a 60000 ;;
    login) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; wait_agent a 1000; record_event tell:resume a; wait_agent a 1000 ;;
    stuck) settle() { echo idle; }; wait_agent a 1000; wait_agent a 1000; close_agent a met ;;
    login-long) settle() { echo idle; }; login_expired() { return 0; }; slug=Story-With-A-Name-Longer-Than-32-Chars
      wait_agent "$(agent_name "${slug}")" 1000; record_event tell:resume "${slug}"; wait_agent "$(agent_name "${slug}")" 1000 ;;
    login-no-prompt) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event tell:note a; record_event tell:resume a "tell: a is busy"; wait_agent a 1000 ;;
    login-restart) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event story a; wait_agent a 1000 ;;
    login-stalled) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event incident a "stalled: working 40 min; longest-running: pid 1, 40 min: sleep 9"; wait_agent a 1000 ;;
    login-signing) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event incident a "sign-blocked: a (unsigned work since 2026-10-29T10:00:00Z)"
      record_event incident a "sign-clear: a"; wait_agent a 1000 ;;
    stalled-cut) long="story-with-a-name-longer-than-32-chars"; n="$(agent_name "${long}")"
      printf '2026-10-30\tcode\t%s\tclaude\topus\thigh\t-\n' "${n}" >> "${AGENTS_LOG}"
      story_rows() { printf '%s\t%s\tready\t-\n' "${long}" "${n}"; }   # the board's row, as board.sh reads it
      settle() { echo "stalled: working 40 min with no commit"; }; longest_child() { :; }; ladder_step() { return 1; }
      wait_agent "${n}" 1000 --stall ;;
    stalled|paused|cleared-on-error|impossible) close_agent a "$1" ;;
    open-pr) stub_prs='[{"state":"OPEN"}]'; close_agent a ;;
  esac >/dev/null 2>&1 || true
  awk -F'\t' -v OFS='\t' "${EVENT_OUTCOME_AWK}"'$2 == "incident" { print $2, $3, outcome($5) }' "${EVENTS_LOG}" 2>/dev/null || true
)
# site_fields <case> — the fields() of each incident line sites <case> wrote, as `<outcome kind> <k=v>...`
# (keys sorted), one line each.
site_fields() {
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1])
from events_outcome import fields, outcome
for line in open(sys.argv[2]):
    row = line.rstrip("\n").split("\t")
    if row[1] == "incident":
        print(" ".join([outcome(row).split(":")[0]] + ["%s=%s" % kv for kv in sorted(fields(row).items())]))' \
    "${REPO}/bin/lib" "${ROOT}/p-$1/.swarm/events.tsv"
}

check "wait_agent's timeout on a blocked agent writes one wait-timeout line" "$(sites timeout blocked)" $'incident\ta\twait-timeout: blocked'
check "wait_agent's timeout on a busy agent writes none" "$(sites timeout busy)" ""
check "herdr's wait timing out on an agent herdr says is working writes none" "$(sites herdr-timeout herdr:working)" ""
check "herdr's wait timing out on an agent herdr says is blocked writes its state" "$(sites herdr-timeout herdr:blocked)" \
  $'incident\ta\twait-timeout: herdr:blocked'
check "a conductor's hour slice running out (SWARM_WAIT_SLICE) writes none" "$(sites slice blocked)" ""
check "herdr's wait failing before the timeout writes none" "$(sites herdr-fails blocked)" ""
check "an expired login waited on twice writes one login line, and a resume then another" "$(sites login)" \
  "$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tlogin: Login expired')"
check "a stuck builder, waited on twice (nudged) and closed, writes one idle-no-pr line, the close's" "$(sites stuck)" \
  $'incident\ta\tidle-no-pr: closed (met) with no open or merged PR on story/a'
check "the close's idle-no-pr line carries the story's slug and the builder's role" "$(site_fields stuck)" "idle-no-pr role=code slug=a"
check "a stalled incident on a builder's name cut at 32 characters carries its story's whole slug, from the board" \
  "$(sites stalled-cut >/dev/null; site_fields stalled-cut)" "stalled role=code slug=story-with-a-name-longer-than-32-chars"
check "each login line carries the builder's slug and role" "$(site_fields login)" "$(printf '%s\n' 'login role=code slug=a' 'login role=code slug=a')"
login2="$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tlogin: Login expired')"
check "a resume for a slug over 32 characters ends its agent's login episode" "$(sites login-long)" \
  "$(printf '%s\n' $'incident\tstory-with-a-name-longer-than-32\tlogin: Login expired' $'incident\tstory-with-a-name-longer-than-32\tlogin: Login expired')"
check "a note or a failed tell does not end a login episode" "$(sites login-no-prompt)" $'incident\ta\tlogin: Login expired'
check "the agent's start line ends a login episode" "$(sites login-restart)" "${login2}"
check "a stalled incident between two waits does not end a login episode" "$(sites login-stalled)" \
  "$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tstalled: working 40 min; longest-running: pid 1, 40 min: sleep 9')"
check "a sign-blocked then a sign-clear incident between two waits do not end a login episode" "$(sites login-signing)" \
  "$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tsign-blocked: a (unsigned work since 2026-10-29T10:00:00Z)' $'incident\ta\tsign-clear: a')"

# fields_for <name> [slug] — agent_fields over a fixture agents.tsv and a board holding stories b9 and 7-fix, with
# build.sh's conductor_name loaded; fields_for --backlog prints the backlog conductor's name instead.
fields_for() (
  PROJECT_DIR="${ROOT}/p-fields"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_goal=off
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/build.sh
  source "${REPO}/bin/lib/build.sh"
  if [[ "$1" == --backlog ]]; then conductor_name backlog; else agent_fields "$@"; fi
)
mkdir -p "${ROOT}/p-fields/.swarm" "${ROOT}/p-fields/board/stories"; : > "${ROOT}/p-fields/board/stories/b9.md"; : > "${ROOT}/p-fields/board/stories/7-fix.md"
cut32="a-story-slug-that-is-cut-at-32ch"  # 32 characters: agent_name's cut of a longer slug
backlog="$(fields_for --backlog)"
for l in "review review-s1" "conduct conduct-e1" "code b2" "code s7-fix" "code s123-fix" "code ${cut32}" "critic critic-e1" "conduct ${backlog}" "code mark-done" \
    "code review-event-fields" "conduct conduct-backlog-cleanup" "code add-retry-to-the-github-pager" "docs add-retry-to-the-github-pag"; do
  printf '2026-10-30\t%s\t%s\tclaude\topus\thigh\t-\n' "${l% *}" "${l#* }" >> "${ROOT}/p-fields/.swarm/agents.tsv"
done
check "a review agent gives its story's slug and role review" "$(fields_for review-s1)" "slug=s1 role=review"
check "a conductor gives its epic's slug and role conduct" "$(fields_for conduct-e1)" "slug=e1 role=conduct"
check "a retired -done2 name reads as the name before it" "$(fields_for b2-done2)" "slug=b2 role=code"
check "a retired name of 32 characters, its stem a cut that another agent's whole name equals, gives neither field" \
  "$(fields_for add-retry-to-the-github-pag-done)" ""
check "a builder whose slug ends in -done is not taken for a retired name" "$(fields_for mark-done)" "slug=mark-done role=code"
check "a name with no agents.tsv line gives no role=" "$(fields_for review-s7)" "slug=s7"
check "a bare name with no line gives its slug only when a story on the board holds it" "$(fields_for b9)|$(fields_for b8)" "slug=b9|"
check "a slug that starts with a digit finds its role under agent_name's s<slug>" "$(fields_for 123-fix 123-fix)" "slug=123-fix role=code"
check "an s<digit> builder name gives the board's story without the s, or no slug when the board does not say" \
  "$(fields_for s7-fix)|$(fields_for s123-fix)" "slug=7-fix role=code|role=code"
check "a 32-character name, which may be cut, gives no slug=" "$(fields_for "${cut32}")" "role=code"
check "an agent of no building role (a critic) gives no slug=" "$(fields_for critic-e1)" "role=critic"
check "the backlog's conductor gives no slug=, under 32 characters as its name is here" "${#backlog} $(fields_for "${backlog}")" "${#backlog} role=conduct"
check "a conductor of an epic whose slug starts backlog- gives that slug" "$(fields_for conduct-backlog-cleanup)" "slug=backlog-cleanup role=conduct"
check "a builder whose slug starts review- keeps it whole" "$(fields_for review-event-fields)" "slug=review-event-fields role=code"
check "a slug the call site has wins, and target - is no agent" "$(fields_for critic-e1 x)|$(fields_for - e)" "slug=x role=critic|slug=e"

# With escalate_ladder set, a stall stepped up prints step-up's line, then the longest-running one.
ladder() (
  PROJECT_DIR="${ROOT}/p-ladder"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_goal=off; CFG_step_up_findings=3; CFG_top_rung_rounds=2
  mkdir -p "${PROJECT_DIR}"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  own_target() { echo w:1; }
  stall_py() { echo a; }
  settle() { echo "stalled: working 40 min with no commit"; }
  longest_child() { echo "longest-running: pid 400, 45 min: sleep"; }
  ladder_step() { echo "stepped up: a: sonnet -> opus"; return "${LADDER_RC}"; }
  LADDER_RC="$1" wait_agent a 1000 --stall 2>/dev/null; echo "exit $?"
)
check "another step-up still running prints the longest-running line as read" "$(ladder 5)" \
  "$(printf '%s\n' 'stepping up: a: another step-up or a restart of it is running; wait on its builder again' 'longest-running: pid 400, 45 min: sleep' 'exit 0')"
check "a stall stepped up prints the longest-running line after stepped up" "$(ladder 0)" \
  "$(printf '%s\n' 'stepped up: a: sonnet -> opus' 'longest-running: pid 400, 45 min: sleep; read before the step-up closed its pane, so the PID may be gone: check it with ps first' 'exit 0')"
for cause in stalled paused cleared-on-error impossible; do
  check "a close with cause ${cause} and no PR writes none" "$(sites "${cause}")" ""
done
check "a close that ends a build with an open PR writes none" "$(sites open-pr)" ""

# flow's incidents section over two days (noon UTC, flow run with TZ=UTC so the local day is UTC's),
# with an ok line and a malformed one that count nothing, and a day outside --since.
P="${ROOT}/repo"; mkdir -p "${P}/.swarm"; git -C "${P}" init -q
ev() { printf '%s\tincident\ts\tw:1\t%s\n' "$1T12:00:00Z" "$2" >> "${P}/.swarm/events.tsv"; }
ev 2026-10-01 "wait-timeout: busy"
ev 2026-10-02 "wait-timeout: busy"
ev 2026-10-02 "wait-timeout: unknown"
ev 2026-10-02 "login: Login expired"
ev 2026-10-03 "login: Login expired"
ev 2026-10-02 "idle-no-pr: you are idle and story/s has no PR"
ev 2026-10-03 "idle-no-pr: closed (met) with no PR on story/s"
ev 2026-10-03 "pull-failed: docs/stories/s.md"
ev 2026-10-03 "merge-blocked: gh pr merge"
ev 2026-10-02 "codex-limit: usage limit"
ev 2026-10-03 "codex-limit: usage limit"
ev 2026-10-03 "codex-limit: usage limit"
printf '%s\n' $'2026-10-03T12:00:00Z\tmerge\ts\tw:1\tok' $'bad\tincident\ts\tw:1\tlogin: x' >> "${P}/.swarm/events.tsv"
mkdir -p "${ROOT}/bin"; printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT TZ=UTC PATH="${ROOT}/bin:${PATH}" bash "${REPO}/bin/swarm.sh" flow --since 2026-10-02)"
check "flow counts every kind's incidents per day" "$(sed -n '/^## incidents$/,/^$/p' <<< "${out}" | sed '/^$/d')" "$(printf '%s\n' \
  "## incidents" $'day\tkind\tincidents' \
  $'2026-10-02\tcodex-limit\t1' $'2026-10-02\tidle-no-pr\t1' $'2026-10-02\tlogin\t1' $'2026-10-02\twait-timeout\t2' \
  $'2026-10-03\tcodex-limit\t2' $'2026-10-03\tidle-no-pr\t1' $'2026-10-03\tlogin\t1' $'2026-10-03\tmerge-blocked\t1' \
  $'2026-10-03\tpull-failed\t1')"

# The same fixture, then intervene lines that `swarm.sh intervene` writes (today) with two causes, an
# incident of another kind with cause=false-stall, and three stalled incidents: one input at 1, all 0,
# and none of the fields. part <n> prints the incidents section's n-th blank-line-separated part.
sw() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT TZ=UTC PATH="${ROOT}/bin:${PATH}" bash "${REPO}/bin/swarm.sh" "$@"); }
sw intervene lead-hand false-stall "a builder was stepped up while its tests ran" >/dev/null
sw intervene user-caught false-stall "the user saw the stalled builder was working" >/dev/null
sw intervene user-caught review-rounds "the user stopped a fifth review round" >/dev/null
ev 2026-10-02 "wait-timeout: busy ~~ cause=false-stall"
ev 2026-10-02 "stalled: working 40 min with no commit ~~ bg=1 test=0 sign=0"
ev 2026-10-03 "stalled: working 40 min with no commit ~~ bg=0 test=0 sign=0"
ev 2026-10-03 "stalled: working 40 min with no commit"
out="$(sw flow --since 2026-10-02)"
part() { sed -n '/^## incidents$/,/^## /p' <<< "${out}" | sed '1d;/^## /d' | awk -v RS= -v n="$1" 'NR == n'; }
check "flow counts incidents per kind and cause, - for a line with no cause" "$(part 3)" "$(printf '%s\n' \
  $'kind\tcause\tincidents' $'codex-limit\t-\t3' $'idle-no-pr\t-\t2' $'lead-hand\tfalse-stall\t1' $'login\t-\t2' \
  $'merge-blocked\t-\t1' $'pull-failed\t-\t1' $'stalled\t-\t3' $'user-caught\tfalse-stall\t1' \
  $'user-caught\treview-rounds\t1' $'wait-timeout\t-\t2' $'wait-timeout\tfalse-stall\t1')"
check "flow lists each stalled incident with its inputs as written, - for one not measured" "$(part 4)" "$(printf '%s\n' \
  $'time\tagent\tbg\ttest\tsign' $'2026-10-02T12:00:00Z\ts\t1\t0\t0' $'2026-10-03T12:00:00Z\ts\t0\t0\t0' \
  $'2026-10-03T12:00:00Z\ts\t-\t-\t-')"
check "false stalls count stalled incidents with an input at 1 and lead-hand or user-caught lines with cause=false-stall" \
  "$(part 5)" "false stalls: 3 (1 stalled with an input at 1, 2 lead-hand or user-caught with cause=false-stall)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
