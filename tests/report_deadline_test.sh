#!/usr/bin/env bash
# report_deadline_test.sh — merge.sh's report deadline: report_start gives a report's reads
# REPORT_SECONDS, report_read runs each within the time left, and report_skipped names the reads cut
# off or never started. A read that finishes in time gives its output and status; one that sleeps past
# the time left is cut at the report's deadline, not REPORT_SECONDS from its own start; a read after
# the deadline is skipped at once. Each read runs in a $( ) subshell, as a report runs it, so a skipped
# name has to outlive the subshell. And a HUP, INT or TERM to within ends the read under it too.
# The timing checks hold on a loaded machine: a cut is never early (an alarm cannot fire before its
# time), and the first read takes 8 of the report's 20 s, so a read cut at the deadline can be up to
# 8 s late and still end before a per-read limit would have cut it.
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
# holds <name> <awk condition on a, b> <a> <b> — the condition holds for those two numbers.
holds() {
  if awk -v a="$3" -v b="$4" "BEGIN { exit !($2) }"; then echo "ok   $1"
  else echo "FAIL $1: $2 with a=$3, b=$4"; fails=$((fails + 1)); fi
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# files — the skip files left in TMPDIR, or nothing.
files() { find "${TMPDIR}" -name 'swarm-report.*' | sort | paste -sd' ' -; }

# shellcheck disable=SC2034 # merge.sh reads PROJECT_DIR as it loads
PROJECT_DIR="${ROOT}"
# shellcheck source=/dev/null
. "${REPO}/bin/lib/merge.sh"

# --- A read that finishes in time: its output and its own status, nothing named, and no file made.
REPORT_SECONDS=30
report_start
rc=0; out="$(report_read quick sh -c 'echo hello; exit 3')" || rc=$?
is "a read in time: its output" hello "${out}"
is "a read in time: its own status" 3 "${rc}"
is "report_start and a read in time make no skip file" "" "$(files)"
is "a read in time: report_skipped names nothing" "" "$(report_skipped)"

# --- A read past the time left is cut at the report's deadline, not REPORT_SECONDS from its own start.
REPORT_SECONDS=20
report_start
rc=0; out="$(report_read first sh -c 'sleep 8; echo done')" || rc=$?
is "a read that uses part of the time: its output" "done|0" "${out}|${rc}"
t1="$(now)"
rc=0; out="$(report_read slow perl -e '$| = 1; print "partial\n"; sleep 60; print "late\n"')" || rc=$?
t2="$(now)"
is "a cut read: 142, keeping what it printed" "partial|142" "${out}|${rc}"
holds "a cut read is never cut before the deadline" "a >= b - 0.05" "${t2}" "${REPORT_END}"
holds "a cut read ends before REPORT_SECONDS from its own start: the deadline is the report's" \
  "a < b + ${REPORT_SECONDS}" "${t2}" "${t1}"

# --- A read after the deadline is skipped at once, and never runs.
t3="$(now)"
rc=0; out="$(report_read late sh -c 'touch "$1"; sleep 10' sh "${ROOT}/ran")" || rc=$?
holds "a read after the deadline returns at once" "a - b < 5" "$(now)" "${t3}"
is "a read after the deadline: 142, never run" "142|no" "${rc}|$([[ -e "${ROOT}/ran" ]] && echo yes || echo no)"
rc=0; out="$(report_read slow sleep 5)" || rc=$?
is "report_skipped names each skipped read once, in order" "skipped (over 20 s): slow, late" "$(report_skipped)"
is "report_skipped leaves no file behind" "" "$(files)"

# --- report_skipped works in a $( ): it forgets what it printed, and a new report starts with none.
# REPORT_SECONDS=0 skips every read at once.
REPORT_SECONDS=0
report_start
report_read one true || true
is "a skip in a report is named" "skipped (over 0 s): one" "$(report_skipped)"
report_read two true || true
is "a read skipped after a \$(report_skipped) is named alone" "skipped (over 0 s): two" "$(report_skipped)"
is "a second \$(report_skipped) names nothing" "" "$(report_skipped)"
report_read three true || true
report_start
report_read four true || true
is "a new report names none of the last one's skips" "skipped (over 0 s): four" "$(report_skipped)"
is "no skip file is left once report_skipped ran" "" "$(files)"

# --- A read with no report started ends the shell it runs in rather than run unbounded.
rc=0; ( unset REPORT_END; report_read orphan true; echo "not reached" ) > "${ROOT}/orphan" 2>/dev/null || rc=$?
is "report_read with no report_start ends its shell" "1|" "${rc}|$(cat "${ROOT}/orphan")"

# --- A HUP, INT or TERM to within's perl KILLs the read under it, and within exits 128+N. The read
# writes its pid, and within's perl is its parent.
# signalled <signal> <exit> — a within read of 30 s, sent <signal> once it runs.
signalled() {
  local pidf="${ROOT}/child-$1" bg child parent rc=0 alive
  rm -f "${pidf}"
  within 30 sh -c 'echo $$ > "$1"; exec sleep 30' sh "${pidf}" &
  bg=$!
  for _ in $(seq 1 100); do [[ -s "${pidf}" ]] && break; sleep 0.1; done
  child="$(cat "${pidf}" 2>/dev/null)" || child=""
  parent="$(ps -o ppid= -p "${child:-0}" 2>/dev/null | tr -d ' ')" || parent=""
  [[ -z "${parent}" ]] || kill "-$1" "${parent}" 2>/dev/null || true
  wait "${bg}" || rc=$?
  # A KILLed read whose parent is gone is a zombie until it is reaped: give that a moment.
  for _ in $(seq 1 50); do kill -0 "${child:-0}" 2>/dev/null || break; sleep 0.1; done
  alive="$(kill -0 "${child:-0}" 2>/dev/null && echo yes || echo no)"
  [[ -z "${child}" ]] || kill -KILL "${child}" 2>/dev/null || true
  is "SIG$1 to within ends the read under it, exiting $2" "$2|no" "${rc}|${alive}"
}
signalled INT 130
signalled TERM 143
signalled HUP 129

if (( fails )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
