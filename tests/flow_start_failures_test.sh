#!/usr/bin/env bash
# flow_start_failures_test.sh — `swarm.sh flow`'s start_failures section against a fixture events.tsv.
# On 2026-10-01: s-a did not start and started ok 9 minutes later: restarted. s-b's start was unclear
# and its ok start came 11 minutes later: not restarted. s-c never started again, and s-x's ok start
# after it is another slug's. s-d failed twice, at 11:00 and 11:03, and started ok at 11:12: the
# first not restarted (12 minutes), the second restarted (9). s-e's unclear start was followed within
# 10 minutes. s-f's ok start came before its failed one, so counts for nothing. s-g's refusal is no
# failed start. s-l took its brief and stopped on an expired login, and never started again. s-h failed on 2026-10-02 and s-z on 2026-09-30, outside a one-day window. TZ is UTC.
# start_agent's start-retry lines: on 2026-10-01 conduct-a's fresh pane saved its start and ok-b's did
# not (a name that starts with ok is no ok outcome); conduct-c's, saved, is on 2026-10-02 and
# conduct-z's on 2026-09-30.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"
mkdir -p "${P}/.swarm"
git -C "${P}" init -q
ev() { printf '%s\treview-agent\t%s\t-\t%s\n' "$1" "$2" "$3" >> "${P}/.swarm/events.tsv"; }
nostart() { ev "$1" "$2" "review-agent: review-$2 did not start (its pane w1-3 is closed)${3:-}"; }
unclear() { ev "$1" "$2" "review-agent: review-$2's start was unclear: it reads idle and may have its brief"; }
retry() { printf '%s\tstart-retry\t%s\t-\t%s\n' "$1" "$2" "$3" >> "${P}/.swarm/events.tsv"; }
NOENV="the pane's shell did not take the agent's environment: timeout"
retry 2026-09-30T23:30:00Z conduct-z "ok (conduct-z: ${NOENV})"
retry 2026-10-01T09:00:00Z conduct-a "ok (conduct-a: ${NOENV})"
retry 2026-10-01T09:30:00Z ok-b "ok-b: ${NOENV}"
retry 2026-10-02T08:00:00Z conduct-c "ok (conduct-c: ${NOENV})"
nostart 2026-09-30T23:00:00Z s-z
nostart 2026-10-01T10:00:00Z s-a
ev 2026-10-01T10:09:00Z s-a "ok (https://github.com/o/r/pull/1)"
unclear 2026-10-01T10:00:00Z s-b
ev 2026-10-01T10:11:00Z s-b "ok (https://github.com/o/r/pull/2)"
nostart 2026-10-01T10:20:00Z s-c
ev 2026-10-01T10:22:00Z s-x ok
nostart 2026-10-01T11:00:00Z s-d "; it ran nothing: no-pane (try 1)"
nostart 2026-10-01T11:03:00Z s-d "; it ran nothing: no-pane (try 2)"
ev 2026-10-01T11:12:00Z s-d ok
unclear 2026-10-01T12:00:00Z s-e
ev 2026-10-01T12:05:00Z s-e ok
ev 2026-10-01T12:30:00Z s-f ok
nostart 2026-10-01T12:35:00Z s-f
ev 2026-10-01T12:40:00Z s-g "review-agent: x is not a PR URL"
ev 2026-10-01T13:00:00Z s-l "review-agent: review-s-l took its brief and stopped on an expired login; no head is on record"
nostart 2026-10-02T09:00:00Z s-h
ev 2026-10-02T09:05:00Z s-h ok

sf() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=start_failures bash "${SWARM}" flow "$@" | grep -v '^## start_failures$'); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
day1="$(printf '%s\n' $'day\tfailed\trestarted_10m\tnot_restarted' $'2026-10-01\t8\t3\t5' '' $'slug\tfailed_at' \
  $'s-b\t2026-10-01T10:00:00Z' $'s-c\t2026-10-01T10:20:00Z' $'s-d\t2026-10-01T11:00:00Z' $'s-f\t2026-10-01T12:35:00Z' $'s-l\t2026-10-01T13:00:00Z' \
  '' $'day\tretried\tsaved' $'2026-10-01\t2\t1')"
out="$(sf --since 2026-10-01 --until 2026-10-01)"
check "one day: an ok start of the slug within 10 minutes restarts it, at 11 minutes, never, before or another slug's does not" "${out}" "${day1}"
check "each day in the window has its row, the failures outside it none" "$(sf --since 2026-10-01 | sed -n 1,3p)" \
  "$(printf '%s\n' $'day\tfailed\trestarted_10m\tnot_restarted' $'2026-10-01\t8\t3\t5' $'2026-10-02\t1\t1\t0')"
check "the retries: each day in the window has its row, saved counting the ok lines only" "$(sf --since 2026-10-01 | awk '/^day\tretried/ { f = 1 } f')" \
  "$(printf '%s\n' $'day\tretried\tsaved' $'2026-10-01\t2\t1' $'2026-10-02\t1\t1')"
check "with no failed start and no retry in the window, a line for each" "$(sf --since 2026-10-03)" \
  "$(printf '%s\n' 'no failed review-agent start in the window' '' 'no start retried in a fresh pane in the window')"

sed 's/$/ ~~ round=2 by=lead/' "${P}/.swarm/events.tsv" > "${dir}/tailed.tsv"
mv "${dir}/tailed.tsv" "${P}/.swarm/events.tsv"
check "a key=value tail on every row prints the same" "$(sf --since 2026-10-01 --until 2026-10-01)" "${day1}"

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
