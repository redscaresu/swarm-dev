#!/usr/bin/env bash
# report_deadline_test.sh — merge.sh's report deadline: report_start gives a report's reads
# REPORT_SECONDS, report_read runs each within the time left, and report_skipped names the reads cut
# off or never started. A read that finishes in time gives its output and status; one that sleeps past
# the time left is cut within a second of it; a read after the deadline is skipped at once. Each read
# runs in a $( ) subshell, as a report runs it, so a skipped name has to outlive the subshell.
# shellcheck disable=SC2034,SC2016 # merge.sh's functions read REPORT_SECONDS; the sh -c scripts are literal
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home" TMPDIR="${ROOT}/tmp"   # under its own root, so parallel runs share no ~
mkdir -p "${HOME}" "${TMPDIR}"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
# near <name> <want> <got> — <got> seconds is within a second of <want>.
near() {
  if awk -v w="$2" -v g="$3" 'BEGIN { d = g - w; exit !(d > -1 && d < 1) }'; then echo "ok   $1"
  else echo "FAIL $1: want ${2}s within a second, got ${3}s"; fails=$((fails + 1)); fi
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.3f\n", b - a }'; }

# shellcheck disable=SC2034 # merge.sh reads PROJECT_DIR as it loads
PROJECT_DIR="${ROOT}"
# shellcheck source=/dev/null
. "${REPO}/bin/lib/merge.sh"

# --- A read that finishes in time: its output and its own status, and nothing named.
REPORT_SECONDS=5
report_start
rc=0; out="$(report_read quick sh -c 'echo hello; exit 3')" || rc=$?
is "a read in time: its output" hello "${out}"
is "a read in time: its own status" 3 "${rc}"
is "a read in time: report_skipped names nothing" "" "$(report_skipped)"

# --- A read past the time left is cut there, not at REPORT_SECONDS from its own start: a first read
# spends 2 of the 6 seconds, so the second, which sleeps 20, is cut about 6 s after the report began.
REPORT_SECONDS=6
t0="$(now)"; report_start
rc=0; out="$(report_read first sh -c 'sleep 2; echo done')" || rc=$?
is "a read that uses part of the time: its output" "done|0" "${out}|${rc}"
rc=0; out="$(report_read slow perl -e '$| = 1; print "partial\n"; sleep 20; print "late\n"')" || rc=$?
near "a read past the deadline is cut within a second of it" 6 "$(since "${t0}")"
is "a cut read: 142, keeping what it printed" "partial|142" "${out}|${rc}"

# --- A read after the deadline is skipped at once, and never runs.
t1="$(now)"
rc=0; out="$(report_read late sh -c 'touch "$1"; sleep 5' sh "${ROOT}/ran")" || rc=$?
near "a read after the deadline returns at once" 0 "$(since "${t1}")"
is "a read after the deadline: 142, never run" "142|no" "${rc}|$([[ -e "${ROOT}/ran" ]] && echo yes || echo no)"
rc=0; out="$(report_read slow sleep 5)" || rc=$?
is "report_skipped names each skipped read once, in order" "skipped (over 6 s): slow, late" "$(report_skipped)"
is "report_skipped ends the report: a second call names nothing" "" "$(report_skipped)"
is "report_skipped leaves no file behind" "" "$(find "${TMPDIR}" -name 'swarm-report.*' | head -1)"

# --- A read with no report started fails rather than run unbounded.
rc=0; ( unset REPORT_END; report_read orphan true ) 2>/dev/null || rc=$?
is "report_read with no report_start fails" 1 "${rc}"

if (( fails )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
