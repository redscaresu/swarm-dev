#!/usr/bin/env bash
# live_logs_test.sh — no test writes a project's live .swarm logs. events_test.sh once logged its
# fixtures (o/r/pull/9) into the real .swarm/findings.tsv and events.tsv, which outcomes counted: run
# on its own from a herdr pane (bash tests/<file>), a test inherits the lead's SWARM_PROJECT, which
# names the real project, and swarm.sh takes that before the directory the test cd'd into. make test
# drops SWARM_PROJECT; a direct run does not. So every test file that runs swarm.sh unsets it or sets
# it itself; and events_test.sh, run both ways, adds no line to the checkout's logs or another
# project's: make test TESTS=tests/events_test.sh, where a call left in the checkout would reach its
# own .swarm, and a direct run with SWARM_PROJECT naming another project. A copy of this repo stands
# in for the main checkout, and a bare directory for the other project: a conductor appends to the
# real logs while the suite runs, and a guard that fails by writing fixtures into the log it guards
# is none.
set -euo pipefail
unset SWARM_PROJECT   # from a pane it names the real project, whose .swarm logs a direct run of this test would write (live_logs_test.sh)
export SWARM_SLEEP_SCALE="${SWARM_SLEEP_SCALE:-0.01}"   # as make test runs them, so a direct run of this file takes as long

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# Every test file that runs swarm.sh unsets SWARM_PROJECT (unset, or env -u) or sets it per call.
unpinned=""
for t in "${REPO}"/tests/*_test.sh; do
  grep -qE 'swarm\.sh|\$\{SWARM\}' "${t}" || continue
  grep -qE 'unset SWARM_PROJECT|-u SWARM_PROJECT|SWARM_PROJECT=' "${t}" || unpinned+="${t##*/} "
done
check "every tests/*_test.sh that runs swarm.sh unsets SWARM_PROJECT or sets it" "" "${unpinned}"

# The checkout: this repo but its .git and .swarm, a git repo and a swarm project of its own (its
# .claude/swarm/config comes along, as in the real one). The other project: a bare directory. Each
# holds a findings.tsv and an events.tsv of one line.
COPY="${ROOT}/repo"; mkdir -p "${COPY}"
cp -R "${REPO}/." "${COPY}"; rm -rf "${COPY}/.git" "${COPY}/.swarm"; git -C "${COPY}" init -q
LIVE="${ROOT}/live"; mkdir -p "${LIVE}/.claude/swarm"; : > "${LIVE}/.claude/swarm/config"
seed() { # <project> — its two logs, a line each
  mkdir -p "$1/.swarm"
  printf '2026-10-25\tseed\thttps://github.com/o/r/pull/1\ta line\tfixed\tlead\n' > "$1/.swarm/findings.tsv"
  printf '2026-10-25T00:00:00Z\tseed\t-\tw:0\tok\n' > "$1/.swarm/events.tsv"
}
seed "${COPY}"; seed "${LIVE}"
lines() { wc -l < "$1" | tr -d ' '; }
logs() { echo "findings $(lines "$1/.swarm/findings.tsv")|events $(lines "$1/.swarm/events.tsv")"; }
added() { # <project> — the lines its logs gained
  tail -n +2 "$1/.swarm/findings.tsv"; tail -n +2 "$1/.swarm/events.tsv" | head -n 20
}

# events_test.sh both ways, from the copy, one after the other (its own timing checks have seconds of
# room): under make test, and directly as a pane runs it, with SWARM_PROJECT naming the other project.
(cd "${COPY}" || exit 1; rc=0; make -s test TESTS=tests/events_test.sh JOBS=1 > "${ROOT}/make.out" 2>&1 || rc=$?; echo "${rc}" > "${ROOT}/make.rc")
(cd "${COPY}" || exit 1; rc=0; SWARM_PROJECT="${LIVE}" bash tests/events_test.sh > "${ROOT}/direct.out" 2>&1 || rc=$?; echo "${rc}" > "${ROOT}/direct.rc")
check "make test TESTS=tests/events_test.sh passes" "exit 0" "exit $(cat "${ROOT}/make.rc")"
check "events_test.sh, run directly with SWARM_PROJECT naming another project, passes" "exit 0" "exit $(cat "${ROOT}/direct.rc")"
check "neither run adds a line to the checkout's .swarm/findings.tsv or events.tsv" "findings 1|events 1" "$(logs "${COPY}")"
check "the direct run adds no line to the other project's findings.tsv or events.tsv" "findings 1|events 1" "$(logs "${LIVE}")"
[[ "$(cat "${ROOT}/make.rc")" == 0 ]] || { echo "---- make test: its first FAIL lines"; grep "^FAIL" "${ROOT}/make.out" | head -n 10 || tail -n 20 "${ROOT}/make.out"; }
[[ "$(cat "${ROOT}/direct.rc")" == 0 ]] || { echo "---- the direct run: its first FAIL lines"; grep "^FAIL" "${ROOT}/direct.out" | head -n 10 || tail -n 20 "${ROOT}/direct.out"; }
[[ "$(logs "${COPY}")" == "findings 1|events 1" ]] || { echo "---- lines added to the checkout's logs"; added "${COPY}"; }
[[ "$(logs "${LIVE}")" == "findings 1|events 1" ]] || { echo "---- lines added to the other project's logs"; added "${LIVE}"; }

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
