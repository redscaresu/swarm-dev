#!/usr/bin/env bash
# wait_pr_test.sh — swarm.sh wait-pr: it polls ci_gate head on a PR's head until nothing is pending,
# exits 0 green (printing the head SHA and each check), 1 red, and 2 on a gh error, retrying only a
# transient one, at most 3 in a row, and on a head whose checks never appear within the grace. gh is
# a stub on PATH: it logs every call to gh.log, answers pr view with ${H} and the nth check-runs
# read from ${FX}/checks.<n> (else ${FX}/checks); the nth read of either fails with ${FX}/head.<n>.err
# or ${FX}/checks.<n>.err as its stderr.
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
  "pr view"*) fail head; echo "${H}" ;;
  *check-runs*)
    fail checks
    if [ -e "${FX}/checks.${n}" ]; then cat "${FX}/checks.${n}"; else cat "${FX}/checks"; fi ;;
  */status*) echo '{"total_count":0,"statuses":[]}' ;;
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
# wait_pr [VAR=value]... — swarm.sh wait-pr ${URL} with no pause unless VARs say otherwise; sets rc
# and took (seconds), output in ${ROOT}/out.
wait_pr() {
  local t0=${SECONDS}; rc=0
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_WAIT_PR_RETRY=0 \
    "$@" bash "${SWARM}" wait-pr "${URL}" > "${ROOT}/out" 2>&1) || rc=$?
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
check "rate limit four times: says why" said "rate limit"

# --- The head read is retried the same way: a rate limit twice then a head goes on; any other error ends it.
fresh; echo "${RATE}" > "${FX}/head.1.err"; cp "${FX}/head.1.err" "${FX}/head.2.err"; wait_pr
is "head read rate-limited twice: exits 0" 0 "${rc}"
check "head read rate-limited twice: prints the head SHA" said "head ${H}"
fresh; echo "GraphQL: Could not resolve to a PullRequest with the number of 7." > "${FX}/head.1.err"; wait_pr
is "head read fails: exits 2" 2 "${rc}"
check "head read fails: says why" said "Could not resolve"
is "head read fails: no check read" 0 "$(reads)"

# --- No checks yet: past the grace exits 2; filled in within it, it goes on waiting.
# Red from the 6th read, so a grace that never ends shows as exit 1, not a hang.
fresh; checks "${FX}/checks"; checks "${FX}/checks.6" "$(run test completed failure)"; wait_pr SWARM_WAIT_PR_GRACE=0
is "no checks past the grace: exits 2" 2 "${rc}"
is "no checks past the grace: one read" 1 "$(reads)"
check "no checks past the grace: says so" said "no checks on ${H:0:7}"
fresh; checks "${FX}/checks.1"; checks "${FX}/checks.2" "$(run test queued)"; wait_pr SWARM_WAIT_PR_GRACE=60
is "checks that appear within the grace: exits 0" 0 "${rc}"
is "checks that appear within the grace: three reads" 3 "$(reads)"

# --- Read-only: no events.tsv line.
check "wait-pr logs nothing" test ! -s "${P}/.swarm/events.tsv"

if [[ ${fails} -eq 0 ]]; then echo "all wait-pr tests passed"; else echo "${fails} wait-pr test(s) failed"; exit 1; fi
