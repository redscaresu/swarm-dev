#!/usr/bin/env bash
# codex_retry_test.sh — codex-review runs codex once more after codex's rate limit, within the one
# codex_minutes budget. A rate limit then a review exits 0 with the review, after two codex calls, one
# codex-retry line and one codex-limit incident. A rate limit on both calls goes on to the fallback after
# the second call, still with one incident. A usage limit is never retried. With less time than the wait
# plus the fallback's least time, codex runs once. A late rate limit, then a retry that hangs, ends within
# the first budget, with the hung codex and its child gone. codex is a stub on PATH that runs
# codex.<call> for each call (codex.1 when there is none), so each call can behave differently.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
cleanup() {
  # A hung stub this test left (a failed check) is killed by the pid it wrote.
  local f
  for f in "${ROOT}"/pid.*; do [[ ! -f "${f}" ]] || kill -KILL "$(cat "${f}")" 2>/dev/null || true; done
  rm -rf "${ROOT}"
}
trap cleanup EXIT
BIN="${ROOT}/stub-bin"; mkdir -p "${BIN}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

RATE_MSG="ERROR: rate limit exceeded: Your requests to gpt-6.1-sol for gpt-6.1-sol in swedencentral have exceeded token rate limit."
USAGE_MSG="ERROR: You’ve hit your usage limit. Upgrade to Pro or try again at 9:41 PM."
# codex: counts its calls in calls, then runs codex.<n>, or codex.1 when there is none.
cat > "${BIN}/codex" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${BIN}/codex" <<'EOF'
n=$(($(cat "$H/calls" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/calls"
f="$H/codex.$n"; [ -f "$f" ] || f="$H/codex.1"
exec /bin/sh "$f"
EOF
chmod +x "${BIN}/codex"
# says <call> <exit> <line>... — codex's call <call> prints the lines on stderr and exits so.
says() { { printf 'echo "%s" >&2\n' "${@:3}"; printf 'exit %s\n' "$2"; } > "${ROOT}/codex.$1"; }
# stubs — no call behaviour left from the last case, and the call count back to 0.
stubs() { rm -f "${ROOT}"/codex.* "${ROOT}/calls" "${ROOT}"/pid.* "${ROOT}"/t.*; }
calls() { cat "${ROOT}/calls" 2>/dev/null || echo 0; }

p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/stories"
git -c init.defaultBranch=main init -q "${p}"
printf '%s\n' --- "status: ready" "kind: code" "touches: [x.sh]" --- "" "# s1" "" "**Done when:**" "- it holds" > "${p}/docs/stories/s1.md"
# review <codex seconds> [config line] — codex-review main for SWARM_STORY=s1 outside herdr, with that
# much of codex's time, a 1 s retry wait (RETRY overrides it), a 1 s grace and a fallback's least
# time of 1 s: sets out and rc. A run past 30 s is KILLed, failing
# the checks instead of hanging the test.
review() {
  local pid i
  printf '%s\n' "${@:2}" > "${p}/.claude/swarm/config"
  (cd "${p}" && exec env -u SWARM_PROJECT -u SWARM_PR -u HERDR_ENV SWARM_STORY=s1 SWARM_FALLBACK_MIN_SECONDS=1 \
    SWARM_CODEX_RETRY_SECONDS="${RETRY:-1}" SWARM_CODEX_GRACE=1 SWARM_CODEX_SECONDS="$1" PATH="${BIN}:${PATH}" \
    bash "${SWARM}" codex-review main > "${ROOT}/out" 2>&1) &
  pid=$!
  for ((i = 0; i < 150; i++)); do kill -0 "${pid}" 2>/dev/null || break; sleep 0.2; done
  kill -0 "${pid}" 2>/dev/null && kill -KILL "${pid}"
  rc=0; wait "${pid}" || rc=$?
  out="$(cat "${ROOT}/out")"
}
# lines <command> — events.tsv's <command> lines as "target|outcome" (events_outcome's, without the tail).
lines() {
  [[ -f "${p}/.swarm/events.tsv" ]] || return 0
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1])
from events_outcome import outcome
for r in (l.rstrip("\n").split("\t") for l in open(sys.argv[2])):
    if r[1] == sys.argv[3]:
        print(r[2] + "|" + outcome(r))' "${SWARM%/*}/lib" "${p}/.swarm/events.tsv" "$1"
}
count() { lines "$1" | wc -l | tr -d ' '; }

# --- A rate limit, then a review: codex runs twice and codex-review exits 0 with the review.
stubs; says 1 1 "${RATE_MSG}"; says 2 0 "review: no findings"
ni="$(count incident)"; nr="$(count codex-retry)"
review 60
check "a rate limit then a review: exit 0 with the review, after two codex calls" "0|yes|yes|2" \
  "${rc}|$(has "review: no findings" "${out}")|$(has "codex rate limit: retrying in 1 s" "${out}")|$(calls)"
check "it logs one codex-retry line, with codex-s1 as its target and the slug tail" \
  "$((nr + 1))|codex-s1|rate limit: retrying in 1 s|yes" \
  "$(count codex-retry)|$(lines codex-retry | tail -1)|$(grep -q $'\tcodex-retry\tcodex-s1\t.*slug=s1' "${p}/.swarm/events.tsv" && echo yes || echo no)"
check "a rate limit then a retry logs exactly one codex-limit incident" "$((ni + 1))|codex-s1|codex-limit: rate limit" \
  "$(count incident)|$(lines incident | tail -1)"

# --- A rate limit on both calls: codex runs exactly twice, then the fallback (here outside herdr, so
# it says codex was skipped), and still one incident.
stubs; says 1 1 "${RATE_MSG}"
ni="$(count incident)"; nr="$(count codex-retry)"
review 60 "fallback_reviewer = sonnet"
check "a rate limit on both calls: codex runs twice, then the fallback" "1|2|yes" \
  "${rc}|$(calls)|$(has "codex skipped: rate limit (fallback did not start: not in a herdr pane" "${out}")"
check "two rate limits in one run log one incident and one retry line" "$((ni + 1))|$((nr + 1))" "$(count incident)|$(count codex-retry)"
stubs; says 1 1 "${RATE_MSG}"
review 60
check "with fallback_reviewer empty, two rate limits exit as codex did after two calls" "1|2" "${rc}|$(calls)"

# --- A usage limit is not retried.
stubs; says 1 1 "${USAGE_MSG}"
nr="$(count codex-retry)"
review 60
check "a usage limit: codex runs once, with no retry line" "1|1|${nr}|no" \
  "${rc}|$(calls)|$(count codex-retry)|$(grep -q 'retrying' <<< "${out}" && echo yes || echo no)"

# STAMP: a stub's command that writes the time to the file after it (perl starts in milliseconds).
STAMP="perl -MTime::HiRes=time -e 'print time, qq(\\n)' >"
# since <file> — seconds from the time in <file> to now, to a tenth; "none" with no file.
since() { [[ -f "$1" ]] && python3 -c 'import sys, time; print("%.1f" % (time.time() - float(open(sys.argv[1]).read())))' "$1" || echo none; }
# under <seconds> <got> — yes when <got> (seconds) is at most <seconds>.
under() { python3 -c 'import sys; print("yes" if sys.argv[2] != "none" and float(sys.argv[2]) <= float(sys.argv[1]) else "no, took " + sys.argv[2] + " s")' "$1" "$2"; }

# --- Less of codex's time than the wait plus the fallback's least time: no retry, and the run ends
# within that time plus the grace, counted from codex's first call (swarm.sh's own start is not codex's
# time). The 20 s wait a retry would add is far past it.
stubs; { echo "${STAMP} '${ROOT}/t.first'"; echo 'sleep 1'; echo "echo \"${RATE_MSG}\" >&2"; echo 'exit 1'; } > "${ROOT}/codex.1"
nr="$(count codex-retry)"
RETRY=20 review 8
check "with 8 s of codex's time and a 20 s retry wait, codex runs once and the run ends within 8 s plus the grace" \
  "1|1|${nr}|yes" "${rc}|$(calls)|$(count codex-retry)|$(under 9 "$(since "${ROOT}/t.first")")"

# --- A late rate limit, then a retry that hangs: the hung codex is stopped within the first budget,
# counted from codex's first call to its last sign of life (it writes the time every 0.2 s until it is
# killed), and it and its child are gone.
stubs
{ echo "${STAMP} '${ROOT}/t.first'"; echo 'sleep 3'; echo "echo \"${RATE_MSG}\" >&2"; echo 'exit 1'; } > "${ROOT}/codex.1"
cat > "${ROOT}/codex.2" <<EOF
echo \$\$ > '${ROOT}/pid.codex'
sleep 600 &
echo \$! > '${ROOT}/pid.child'
while :; do ${STAMP} '${ROOT}/t.last.tmp' && mv '${ROOT}/t.last.tmp' '${ROOT}/t.last'; sleep 0.2; done
EOF
nreap="$(count reap)"
RETRY=2 review 10
gone() { if [[ -f "$1" ]] && ! kill -0 "$(cat "$1")" 2>/dev/null; then echo yes; else echo no; fi; }
ran="$(python3 -c 'import sys; print("%.1f" % (float(open(sys.argv[2]).read()) - float(open(sys.argv[1]).read())))' "${ROOT}/t.first" "${ROOT}/t.last" 2>/dev/null || echo none)"
check "a late rate limit then a hung retry: two calls, the retry stopped within the 10 s budget (2 s allowed: the whole-second clock and a poll), as a timeout" \
  "2|yes|yes|$((nreap + 1))" \
  "$(calls)|$(under 12 "${ran}")|$(has "codex skipped: timed out" "${out}")|$(count reap)"
check "the hung retry and its child are stopped" "yes|yes" "$(gone "${ROOT}/pid.codex")|$(gone "${ROOT}/pid.child")"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
