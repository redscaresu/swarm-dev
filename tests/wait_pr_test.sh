#!/usr/bin/env bash
# wait_pr_test.sh — swarm.sh wait-pr: it polls ci_gate head on a PR's head until nothing is pending,
# exits 0 green (printing the head SHA and each check), 1 red, and 2 on a gh error, retrying only a
# transient one, at most 3 in a row, on a head whose checks never appear within the grace, and past
# its deadline with a check still pending, and at once on a PR that conflicts with its base. gh is
# a stub on PATH: it logs every call to gh.log, answers pr view with ${H} and the nth check-runs
# read from ${FX}/checks.<n> (else ${FX}/checks); the nth read of either fails with ${FX}/head.<n>.err
# or ${FX}/checks.<n>.err as its stderr. With ${FX}/notice, pr view also prints a notice on stderr;
# pr view's nth answer has the mergeable state in ${FX}/mergeable.<n>, else MERGEABLE, and the PR's
# state in ${FX}/state, else OPEN;
# with ${FX}/head.hang or ${FX}/checks.hang, that read hangs 8s before it answers, ignoring SIGALRM
# as gh (a Go program) does with ${FX}/ignore-alrm;
# commit statuses come from ${FX}/status, else none; api rate_limit answers ${FX}/reset.<core|graphql>, for
# the budget asked about, else ${FX}/reset ("<epoch> <time>" of a spent budget's reset), else nothing,
# 8s late with ${FX}/reset.hang.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; URL=https://github.com/o/r/pull/7
H=1111111111111111111111111111111111111111
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${ROOT}/bin"; : > "${P}/.claude/swarm/config"
git -C "${P}" init -q

printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"; H="%s"\n' "${FX}" "${ROOT}/gh.log" "${H}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
# fail <key> — count this read of <key>; on the nth, fail with ${FX}/<key>.<n>.err as stderr if there is one.
fail() {
  n=$(( $(cat "${FX}/$1.n" 2>/dev/null || echo 0) + 1 )); echo "${n}" > "${FX}/$1.n"
  if [ -e "${FX}/$1.${n}.err" ]; then cat "${FX}/$1.${n}.err" >&2; exit 1; fi
}
case "$*" in
  "pr view"*) fail head; [ ! -e "${FX}/ignore-alrm" ] || trap '' ALRM; [ ! -e "${FX}/head.hang" ] || sleep 8
              [ ! -e "${FX}/notice" ] || cat "${FX}/notice" >&2
              echo "${H} $(cat "${FX}/mergeable.${n}" 2>/dev/null || echo MERGEABLE) main $(cat "${FX}/state" 2>/dev/null || echo OPEN)" ;;
  *check-runs*)
    fail checks; [ ! -e "${FX}/checks.hang" ] || sleep 8
    if [ -e "${FX}/checks.${n}" ]; then cat "${FX}/checks.${n}"; else cat "${FX}/checks"; fi ;;
  "api rate_limit"*) [ ! -e "${FX}/reset.hang" ] || sleep 8
    case "$*" in *resources.graphql*) b=graphql ;; *) b=core ;; esac
    cat "${FX}/reset.${b}" 2>/dev/null || cat "${FX}/reset" 2>/dev/null || true ;;
  */status*) cat "${FX}/status" 2>/dev/null || echo '{"total_count":0,"statuses":[]}' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
said() { grep -qF -- "$1" "${ROOT}/out"; }
reads() { grep -c check-runs "${ROOT}/gh.log" || true; }

# run <name> <status> [conclusion] — one check run.
run() { local c=null; [[ -z "${3:-}" ]] || c="\"$3\""; printf '{"name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "${c}"; }
# checks <file> <run>... — a page of check runs.
checks() { local f="$1" IFS=,; shift; printf '{"total_count":%s,"check_runs":[%s]}\n' "$#" "$*" > "${f}"; }
RATE="gh: API rate limit exceeded for user ID 1. (HTTP 403)"
fresh() { rm -rf "${FX}"; mkdir -p "${FX}"; : > "${ROOT}/gh.log"; checks "${FX}/checks" "$(run test completed success)" "$(run lint completed success)"; }
# wait_pr [VAR=value]... [arg]... — swarm.sh wait-pr [arg]... ${URL} with no pause unless VARs say
# otherwise; sets rc and took (seconds), output in ${ROOT}/out.
wait_pr() {
  local t0=${SECONDS} envs=(); rc=0
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_WAIT_PR_RETRY=0 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait-pr "$@" "${URL}" > "${ROOT}/out" 2>&1) || rc=$?
  took=$((SECONDS - t0))
}

# --- Pending, then green: exit 0, the head SHA and each check with its state.
fresh; checks "${FX}/checks.1" "$(run test in_progress)" "$(run lint completed success)"; wait_pr
is "pending then green: exits 0" 0 "${rc}"
is "pending then green: two reads" 2 "$(reads)"
check "pending then green: prints the head SHA" said "head ${H}"
check "pending then green: prints what it waits on" said "pending: test (in_progress)"
check "pending then green: prints each check with its state" grep -qxF "  test (success)" "${ROOT}/out"
check "pending then green: prints lint too" grep -qxF "  lint (success)" "${ROOT}/out"

# --- Red: exit 1, naming the check.
fresh; checks "${FX}/checks" "$(run test completed failure)" "$(run lint completed success)"; wait_pr
is "red: exits 1" 1 "${rc}"
check "red: names the red check" said "red: test (failure)"

# --- A gh error that is not transient ends it at once, within one poll, never read as pending.
fresh; echo "gh: Bad credentials (HTTP 401)" > "${FX}/checks.1.err"; wait_pr SWARM_MERGE_POLL=30 SWARM_WAIT_PR_RETRY=30
is "a failing gh: exits 2" 2 "${rc}"
is "a failing gh: one read" 1 "$(reads)"
check "a failing gh: returns within one poll" test "${took}" -lt 10
check "a failing gh: says why" said "Bad credentials"

# --- A rate limit is retried: twice (or three times) then green exits 0; a fourth in a row ends it.
fresh; echo "${RATE}" > "${FX}/checks.1.err"; cp "${FX}/checks.1.err" "${FX}/checks.2.err"; wait_pr
is "rate limit twice then green: exits 0" 0 "${rc}"
is "rate limit twice then green: three reads" 3 "$(reads)"
fresh; for n in 1 2 3; do echo "${RATE}" > "${FX}/checks.${n}.err"; done; wait_pr
is "rate limit three times then green: exits 0" 0 "${rc}"
fresh; for n in 1 2 3 4; do echo "${RATE}" > "${FX}/checks.${n}.err"; done; wait_pr
is "rate limit four times: exits 2" 2 "${rc}"
is "rate limit four times: four reads" 4 "$(reads)"
check "rate limit four times: says why" grep -q "^swarm: wait-pr: .*rate limit" "${ROOT}/out"

# --- With a budget spent, a rate limit waits once until it resets, printing when, then reads again;
# a second waits no more, as a transient error.
LIMIT="GraphQL: API rate limit already exceeded for user ID 1."
fresh; echo "${LIMIT}" > "${FX}/head.1.err"; echo "$(($(date +%s) + 2)) 2030-01-01T00:00:02Z" > "${FX}/reset"
wait_pr SWARM_WAIT_PR_RETRY=30
is "rate limit with a spent budget: exits 0" 0 "${rc}"
check "rate limit with a spent budget: prints the reset time" said "rate limited: GitHub's API budget resets at 2030-01-01T00:00:02Z; waiting until then"
check "rate limit with a spent budget: waits until the reset" test "${took}" -ge 2 -a "${took}" -lt 10
is "rate limit with a spent budget: reads the head again" 2 "$(grep -c "^pr view" "${ROOT}/gh.log")"
fresh; for n in 1 2; do echo "${LIMIT}" > "${FX}/checks.${n}.err"; done; echo "$(date +%s) 2030-01-01T00:00:00Z" > "${FX}/reset"
wait_pr
is "two rate limits with a spent budget: exits 0" 0 "${rc}"
is "two rate limits with a spent budget: one wait" 1 "$(grep -c "^rate limited" "${ROOT}/out")"
check "two rate limits with a spent budget: the second is retried" said "retrying after"
is "two rate limits with a spent budget: three reads" 3 "$(reads)"
is "two rate limits with a spent budget: the budget is read once" 1 "$(grep -c "^api rate_limit" "${ROOT}/gh.log")"
# The budget read is the failing call's own: a REST limit with GraphQL's spent, or a GraphQL limit with
# REST's spent, is retried, with no reset wait.
fresh; echo "${RATE}" > "${FX}/checks.1.err"; echo "$(($(date +%s) + 30)) 2030-01-01T00:00:30Z" > "${FX}/reset.graphql"
wait_pr SWARM_WAIT_PR_RETRY=1
is "a REST rate limit with GraphQL's budget spent: exits 0" 0 "${rc}"
check "a REST rate limit with GraphQL's budget spent: no reset wait" test "${took}" -lt 10 -a "$(grep -c "^rate limited" "${ROOT}/out")" -eq 0
fresh; echo "${LIMIT}" > "${FX}/head.1.err"; echo "$(($(date +%s) + 30)) 2030-01-01T00:00:30Z" > "${FX}/reset.core"
wait_pr SWARM_WAIT_PR_RETRY=1
is "a GraphQL rate limit with REST's budget spent: exits 0" 0 "${rc}"
check "a GraphQL rate limit with REST's budget spent: no reset wait" test "${took}" -lt 10 -a "$(grep -c "^rate limited" "${ROOT}/out")" -eq 0
# The reset wait starts the transient-error count over: two errors, the wait, then two more go on.
fresh; for n in 1 2 4 5; do echo "gh: read: connection reset by peer" > "${FX}/checks.${n}.err"; done
echo "${LIMIT}" > "${FX}/checks.3.err"; echo "$(($(date +%s) + 1)) 2030-01-01T00:00:01Z" > "${FX}/reset"; wait_pr
is "transient errors either side of a reset wait: exits 0" 0 "${rc}"
is "transient errors either side of a reset wait: six reads" 6 "$(reads)"
# The grace for a head with no check runs pauses with the reset wait: a wait longer than the grace,
# then a read still with none, goes on.
fresh; checks "${FX}/checks.1"; echo "${LIMIT}" > "${FX}/checks.2.err"; checks "${FX}/checks.3"
echo "$(($(date +%s) + 3)) 2030-01-01T00:00:03Z" > "${FX}/reset"; wait_pr SWARM_WAIT_PR_GRACE=2
is "a reset wait longer than the no-check grace: exits 0" 0 "${rc}"
is "a reset wait longer than the no-check grace: four reads" 4 "$(reads)"
# The wait moves the default deadline: a reset past it is still waited for.
fresh; echo "${LIMIT}" > "${FX}/checks.1.err"; echo "$(($(date +%s) + 3)) 2030-01-01T00:00:03Z" > "${FX}/reset"
wait_pr SWARM_MERGE_CI_SECONDS=2
is "rate limit resetting past the default deadline: exits 0" 0 "${rc}"
# An explicit --timeout bounds it: a reset past that ends the wait at once, naming the reset time.
fresh; echo "${LIMIT}" > "${FX}/checks.1.err"; echo "$(($(date +%s) + 30)) 2030-01-01T00:00:30Z" > "${FX}/reset"
wait_pr --timeout 5
is "rate limit resetting past --timeout: exits 2" 2 "${rc}"
check "rate limit resetting past --timeout: names the reset time" said "resets at 2030-01-01T00:00:30Z, past --timeout 5s"
check "rate limit resetting past --timeout: ends at once" test "${took}" -lt 3
# With the budget left, the same words are GitHub's secondary limit: no wait for the reset, but the
# retry pause and up to half again.
fresh; echo "${LIMIT}" > "${FX}/checks.1.err"; wait_pr SWARM_WAIT_PR_RETRY=2
is "rate limit with the budget left: exits 0" 0 "${rc}"
check "rate limit with the budget left: backs off the retry pause, plus at most half again" test "${took}" -ge 2 -a "${took}" -le 4
check "rate limit with the budget left: is retried, with no reset wait" said "retrying after"
# A secondary limit in its own words is retried the same way, with no read of the budget.
fresh; echo "gh: You have exceeded a secondary rate limit. Please wait a few minutes before you try again. (HTTP 403)" > "${FX}/checks.1.err"
echo "$(($(date +%s) + 30)) 2030-01-01T00:00:30Z" > "${FX}/reset"; wait_pr SWARM_WAIT_PR_RETRY=2
is "secondary rate limit: exits 0" 0 "${rc}"
is "secondary rate limit: does not read the budget" 0 "$(grep -c "^api rate_limit" "${ROOT}/gh.log")"
check "secondary rate limit: backs off the retry pause, plus at most half again" test "${took}" -ge 2 -a "${took}" -le 4
# The read of the reset time is bounded by the deadline too: one that hangs ends the wait there.
fresh; echo "${LIMIT}" > "${FX}/head.1.err"; : > "${FX}/reset.hang"; wait_pr SWARM_WAIT_PR_RETRY=30 --timeout 2
is "a reset read hanging past --timeout: exits 2" 2 "${rc}"
check "a reset read hanging past --timeout: returns at the deadline" test "${took}" -lt 5

# --- The head read is retried the same way: a rate limit twice then a head goes on; any other error ends it.
fresh; echo "${RATE}" > "${FX}/head.1.err"; cp "${FX}/head.1.err" "${FX}/head.2.err"; wait_pr
is "head read rate-limited twice: exits 0" 0 "${rc}"
check "head read rate-limited twice: prints the head SHA" said "head ${H}"
fresh; echo "GraphQL: Could not resolve to a PullRequest with the number of 7." > "${FX}/head.1.err"; wait_pr
is "head read fails: exits 2" 2 "${rc}"
check "head read fails: says why" said "Could not resolve"
is "head read fails: no check read" 0 "$(reads)"

# --- A PR that conflicts with its base runs no checks: exit 2 on the first read, naming the base.
# UNKNOWN (GitHub still computing) is read again each poll, the checks beside it, until MERGEABLE.
fresh; echo CONFLICTING > "${FX}/mergeable.1"; wait_pr SWARM_WAIT_PR_GRACE=300
is "conflicting: exits 2" 2 "${rc}"
is "conflicting: one head read" 1 "$(grep -c "^pr view" "${ROOT}/gh.log")"
is "conflicting: no check read" 0 "$(reads)"
check "conflicting: prints the conflict line" said "conflicts with main: merge origin/main in, then push"
# The checks are read beside each UNKNOWN read, so a red one ends the wait at once.
fresh; echo UNKNOWN > "${FX}/mergeable.1"; checks "${FX}/checks.1" "$(run test queued)"; wait_pr
is "unknown then mergeable: exits 0" 0 "${rc}"
is "unknown then mergeable: two head reads" 2 "$(grep -c "^pr view" "${ROOT}/gh.log")"
is "unknown then mergeable: two check reads" 2 "$(reads)"
check "unknown then mergeable: prints the head SHA" said "head ${H}"
check "unknown then mergeable: says it waits on the mergeable state" said "pending: test (queued); mergeable state UNKNOWN"
fresh; for n in 1 2 3; do echo UNKNOWN > "${FX}/mergeable.${n}"; done; checks "${FX}/checks" "$(run test completed failure)"; wait_pr
is "unknown with a red check: exits 1" 1 "${rc}"
is "unknown with a red check: one head read" 1 "$(grep -c "^pr view" "${ROOT}/gh.log")"
check "unknown with a red check: names it" said "red: test (failure)"
# A merged or closed PR stays UNKNOWN: its checks are read at once, not polled to the deadline.
fresh; echo UNKNOWN > "${FX}/mergeable.1"; echo UNKNOWN > "${FX}/mergeable.2"; echo MERGED > "${FX}/state"; wait_pr --timeout 5
is "unknown on a merged PR: exits 0" 0 "${rc}"
is "unknown on a merged PR: one head read" 1 "$(grep -c "^pr view" "${ROOT}/gh.log")"

# --- No checks yet: past the grace exits 2; filled in within it, it goes on waiting.
# Red from the 6th read, so a grace that never ends shows as exit 1, not a hang.
fresh; checks "${FX}/checks"; checks "${FX}/checks.6" "$(run test completed failure)"; wait_pr SWARM_WAIT_PR_GRACE=0
is "no checks past the grace: exits 2" 2 "${rc}"
is "no checks past the grace: one read" 1 "$(reads)"
check "no checks past the grace: says so" said "no check runs on ${H:0:7}"
fresh; checks "${FX}/checks.1"; checks "${FX}/checks.2" "$(run test queued)"; wait_pr SWARM_WAIT_PR_GRACE=60
is "checks that appear within the grace: exits 0" 0 "${rc}"
is "checks that appear within the grace: three reads" 3 "$(reads)"

# --- No check runs beside a pending commit status is still no checks: the grace applies.
fresh; checks "${FX}/checks"; checks "${FX}/checks.6" "$(run test completed failure)"
echo '{"total_count":1,"statuses":[{"context":"external-ci","state":"pending"}]}' > "${FX}/status"
wait_pr SWARM_WAIT_PR_GRACE=0
is "no check runs beside a pending status past the grace: exits 2" 2 "${rc}"
check "no check runs beside a pending status past the grace: says so" said "no check runs on ${H:0:7}"

# --- The grace starts at the first read that finds no check runs: a head read retried for 2s first
# leaves a 1s grace whole.
fresh; echo "${RATE}" > "${FX}/head.1.err"; checks "${FX}/checks.1"; wait_pr SWARM_WAIT_PR_RETRY=2 SWARM_WAIT_PR_GRACE=1
is "grace after a retried head read: exits 0" 0 "${rc}"
is "grace after a retried head read: two check reads" 2 "$(reads)"

# --- A check that stays pending ends at the deadline, naming it (red from the 6th read, so no
# deadline shows as exit 1, not a hang); --timeout sets it, else SWARM_MERGE_CI_SECONDS.
fresh; checks "${FX}/checks" "$(run test queued)"; checks "${FX}/checks.6" "$(run test completed failure)"; wait_pr --timeout 0
is "stays pending past --timeout: exits 2" 2 "${rc}"
check "stays pending past --timeout: names what is pending" said "still pending: test (queued)"
is "stays pending past --timeout: one read" 1 "$(reads)"
fresh; checks "${FX}/checks" "$(run test queued)"; checks "${FX}/checks.6" "$(run test completed failure)"; wait_pr SWARM_MERGE_CI_SECONDS=0
is "stays pending past the default deadline: exits 2" 2 "${rc}"
fresh; wait_pr --timeout soon
is "a --timeout that is not seconds: exits 2" 2 "${rc}"
check "a --timeout that is not seconds: prints usage" said "usage: swarm.sh wait-pr"

# --- Seconds are base 10: a leading 0 is not octal (09 would fail in (( )), 010 would be 8).
fresh; checks "${FX}/checks.1" "$(run test queued)"; wait_pr --timeout 09
is "--timeout 09 with a pending read: exits 0" 0 "${rc}"
fresh; checks "${FX}/checks.1"; wait_pr SWARM_WAIT_PR_GRACE=09
is "SWARM_WAIT_PR_GRACE=09: exits 0" 0 "${rc}"
fresh; wait_pr SWARM_WAIT_PR_GRACE=soon
is "SWARM_WAIT_PR_GRACE that is not seconds: exits 2" 2 "${rc}"
check "SWARM_WAIT_PR_GRACE that is not seconds: says so" said "SWARM_WAIT_PR_GRACE is 'soon'"

# --- The deadline holds on the retry paths too: past it, no pause before another read. Three rate
# limits, then green: with no deadline there, the retries would reach green.
fresh; for n in 1 2 3; do echo "${RATE}" > "${FX}/checks.${n}.err"; done; wait_pr SWARM_WAIT_PR_RETRY=1 --timeout 0
is "check reads retried past --timeout: exits 2" 2 "${rc}"
is "check reads retried past --timeout: one read" 1 "$(reads)"
check "check reads retried past --timeout: says so" grep -qE "timed out after [0-9]+s, last error: .*rate limit" "${ROOT}/out"
fresh; for n in 1 2 3; do echo "${RATE}" > "${FX}/head.${n}.err"; done; wait_pr SWARM_WAIT_PR_RETRY=1 --timeout 0
is "head reads retried past --timeout: exits 2" 2 "${rc}"
is "head reads retried past --timeout: one head read" 1 "$(grep -c "^pr view" "${ROOT}/gh.log")"

# --- A pause is cut at the deadline, and the wait ends there: no read after it, even one that would
# be green. 3s, so time is left when the first pause starts ($SECONDS ticks whole seconds).
fresh; checks "${FX}/checks.1" "$(run test queued)"; wait_pr SWARM_MERGE_POLL=5 --timeout 3
is "a poll past a small --timeout, then green: exits 2" 2 "${rc}"
is "a poll past a small --timeout, then green: one read" 1 "$(reads)"
check "a poll past a small --timeout, then green: returns at the deadline" test "${took}" -lt 5
check "a poll past a small --timeout, then green: says timed out" grep -qE "timed out after [34]s, still pending: test \(queued\)" "${ROOT}/out"
fresh; echo "${RATE}" > "${FX}/checks.1.err"; wait_pr SWARM_WAIT_PR_RETRY=5 --timeout 3
is "a retry past a small --timeout, then green: exits 2" 2 "${rc}"
is "a retry past a small --timeout, then green: one read" 1 "$(reads)"

# --- Pauses and the deadline must be whole seconds, refused up front (exit 2): sleep failing on 20s
# would exit 1, which reads as red. A bad SWARM_MERGE_CI_SECONDS exited 2 as a usage error before,
# so only its message is new.
for v in SWARM_MERGE_POLL=20s SWARM_WAIT_PR_RETRY=1m SWARM_MERGE_CI_SECONDS=soon; do
  fresh; checks "${FX}/checks.1" "$(run test queued)"; echo "${RATE}" > "${FX}/head.1.err"; wait_pr "${v}"
  [[ "${v}" == SWARM_MERGE_CI_SECONDS=* ]] || is "${v}: exits 2" 2 "${rc}"
  check "${v}: names the variable" said "${v%%=*} is '${v#*=}', not whole seconds"
done

# --- Other network blips are transient too.
for e in "dial tcp: lookup api.github.com: no such host" "dial tcp 1.2.3.4:443: connect: network is unreachable" \
         "stream error: stream ID 3; INTERNAL_ERROR" "gh: HTTP 408"; do
  fresh; echo "${e}" > "${FX}/checks.1.err"; wait_pr
  is "${e##*: } then green: exits 0" 0 "${rc}"
done

# --- Only gh's own words count as transient, not a repo path or URL in the error.
fresh; echo "gh: Bad credentials (HTTP 401)" > "${FX}/checks.1.err"
URL=https://github.com/o/geofabrik/pull/7 wait_pr SWARM_WAIT_PR_RETRY=30
is "Bad credentials on repo geofabrik: exits 2" 2 "${rc}"
is "Bad credentials on repo geofabrik: one read" 1 "$(reads)"
fresh; printf 'Get "https://api.github.com/repos/o/r/commits/%s/check-runs": read tcp 10.0.0.1:1->10.0.0.2:443: read: connection reset by peer\n' "${H}" > "${FX}/checks.1.err"
wait_pr
is "connection reset beside a URL: exits 0" 0 "${rc}"
is "connection reset beside a URL: two reads" 2 "$(reads)"

# --- A notice on stderr beside a good head read is not an error.
fresh; echo "A new release of gh is available: 2.80.0 → 2.81.0" > "${FX}/notice"; wait_pr
is "a gh notice beside the head: exits 0" 0 "${rc}"
check "a gh notice beside the head: prints the head SHA" said "head ${H}"

# --- A read that hangs ends at the deadline (the stub answers green 8s on, too late).
for k in checks head; do
  fresh; : > "${FX}/${k}.hang"; wait_pr --timeout 2
  is "a ${k} read hanging past --timeout: exits 2" 2 "${rc}"
  check "a ${k} read hanging past --timeout: returns at the deadline" test "${took}" -lt 5
  check "a ${k} read hanging past --timeout: says so" said "did not return"
done

fresh; : > "${FX}/head.hang"; : > "${FX}/ignore-alrm"; wait_pr --timeout 2
is "a head read ignoring SIGALRM, as gh does: exits 2" 2 "${rc}"
check "a head read ignoring SIGALRM, as gh does: returns at the deadline" test "${took}" -lt 5

# --- Exit 1 is only red: a die inside wait-pr (here a bad config line) exits 2.
fresh; echo "bogus = 1" > "${P}/.claude/swarm/config"; wait_pr
is "a die inside wait-pr: exits 2" 2 "${rc}"
: > "${P}/.claude/swarm/config"

# --- Read-only: no events.tsv line.
check "wait-pr logs nothing" test ! -s "${P}/.swarm/events.tsv"

if [[ ${fails} -eq 0 ]]; then echo "all wait-pr tests passed"; else echo "${fails} wait-pr test(s) failed"; exit 1; fi
