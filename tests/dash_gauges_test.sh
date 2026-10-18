#!/usr/bin/env bash
# dash_gauges_test.sh — the lines under dash's speedometer, on the two-project fixture
# (tests/fixtures/dash/two_projects.sh) with alpha's events.tsv replaced by 14 days of finishes: the
# sparkline with today's count and the 7-day average from 60 columns, the rate and running gauges
# with the best 7 days and the 7-day peak from 100, the text line alone at 59, and a running count
# that is the one `swarm.sh status` gives.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }
lacks() { ! grep -qF -- "$1" <<< "$2"; }

# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${ROOT}"
A="${FIXTURE_A}"; B="${FIXTURE_B}"
frame() { rm -f "${TMPDIR}"/swarm-dash-*; (cd "$1" && DASH_W="$2" "${FIXTURE_SWARM}" dash); }

# 14 days of finishes, oldest first (days 13 to 0 ago, each at 10:00): 9 in the last 7 days, 11 in
# the best 7. A slug finished and then reconciled the same day counts once. One more finish 7 days
# ago at 20:00 is inside the speedometer's 168 hours but on the 8th bar, so the bars' average leaves
# it out (9, not 10) and the best 7 days are 12.
counts=(1 0 2 4 3 0 1 0 1 2 0 1 3 2)
: > "${A}/.swarm/events.tsv"
for i in "${!counts[@]}"; do
  d=$((13 - i))
  for ((n = 0; n < counts[i]; n++)); do printf '%s\tfinish\ts-%s-%s\tw1:p1\tok\n' "$(at $((d * 1440 + 120)))" "${d}" "${n}" >> "${A}/.swarm/events.tsv"; done
done
printf '%s\treconcile\ts-0-0\tw1:p1\tok (finished by its PR)\n' "$(at 60)" >> "${A}/.swarm/events.tsv"
printf '%s\tfinish\ts-7-late\tw1:p1\tok\n' "$(at $((7 * 1440 - 480)))" >> "${A}/.swarm/events.tsv"

out="$(frame "${A}" 100)"
check "the speedometer's 168 hours count the late finish: 10 is 1.4" has "1.4 merged/day over 7 days" "$(sed -n 2p <<< "${out}")"
check "the sparkline draws the 14 days, oldest first, the busiest day highest, and averages its last 7 bars" \
  has "14 days ▂▁▃▇▅▁▃▁▂▃▁▂▅▃  today 2  7-day avg 1.3" "$(sed -n 3p <<< "${out}")"
check "the rate gauge is the last 7 bars' 9 of the best 12" has "rate █████████··· 1.3 of best 1.7/day" "$(sed -n 4p <<< "${out}")"

# Four sessions busy at once 3 days ago, and five 9 days ago (past the 7 days, so not the peak).
for s in 1 2 3 4; do
  session alpha "pk-${s}" $((4320 + 120)) claude-opus-5-5 1 1 Bash; touch_ago 4320 "${ROOT}/projects/alpha/pk-${s}.jsonl"
  printf '2026-10-07\tcode\tpk-%s\tclaude\topus\thigh\tpk-%s\n' "${s}" "${s}" >> "${A}/.swarm/agents.tsv"
done
for s in 1 2 3 4 5; do
  session alpha "old-${s}" $((12960 + 120)) claude-opus-5-5 1 1 Bash; touch_ago 12960 "${ROOT}/projects/alpha/old-${s}.jsonl"
  printf '2026-10-01\tcode\told-%s\tclaude\topus\thigh\told-%s\n' "${s}" "${s}" >> "${A}/.swarm/agents.tsv"
done
out="$(frame "${A}" 100)"
check "the running gauge: a builder and a conductor now, of the peak of 4 in 7 days" \
  has "running ███▓▓▓······ 2 of peak 4 in 7 days" "$(sed -n 4p <<< "${out}")"

# 20 more at once then make the peak 24: the one builder and the one conductor keep a cell each.
for s in $(seq 5 24); do
  session alpha "pk-${s}" $((4320 + 120)) claude-opus-5-5 1 1 Bash; touch_ago 4320 "${ROOT}/projects/alpha/pk-${s}.jsonl"
  printf '2026-10-07\tcode\tpk-%s\tclaude\topus\thigh\tpk-%s\n' "${s}" "${s}" >> "${A}/.swarm/agents.tsv"
done
check "at a peak of 24 a builder and a conductor still show a cell each" \
  has "running █▓·········· 2 of peak 24 in 7 days" "$(sed -n 4p <<< "$(frame "${A}" 100)")"
# A session whose last write (6 days ago) is before its first timestamp (an hour ago) is skipped: it never lowers the peak.
session alpha pk-bad 60 claude-opus-5-5 1 1 Bash; touch_ago 9000 "${ROOT}/projects/alpha/pk-bad.jsonl"
printf '2026-10-07\tcode\tpk-bad\tclaude\topus\thigh\tpk-bad\n' >> "${A}/.swarm/agents.tsv"
check "an inverted session leaves the peak at 24" has "2 of peak 24 in 7 days" "$(frame "${A}" 100)"

# With no agent list from herdr, the running gauge is left out, never shown as 0; the rate stays.
mkdir -p "${ROOT}/noherdr"; printf '#!/bin/sh\nexit 1\n' > "${ROOT}/noherdr/herdr"; chmod +x "${ROOT}/noherdr/herdr"
out="$(PATH="${ROOT}/noherdr:${PATH}" frame "${A}" 100)"
check "with no agent list the running gauge is left out" lacks "of peak" "${out}"
check "with no agent list the rate gauge still shows" has "rate █████████··· 1.3 of best 1.7/day" "${out}"

# The running count is status's, in both projects (bravo's stalled b-page counts too).
status_working() { HERDR_ENV=1 SWARM_PROJECT="$1" "${FIXTURE_SWARM}" status | grep -c '^  [^ ]*  *working  \[' || true; }
for p in "${A}" "${B}"; do
  n="$(status_working "${p}")"
  check "$(basename "${p}"): the running gauge counts the ${n} agents status lists as working" \
    grep -qE "running [^ ]+ ${n} of peak" <<< "$(frame "${p}" 100)"
done

out="$(frame "${A}" 60)"
check "at 60 columns the sparkline shows" has "14 days ▂▁▃▇▅" "${out}"
check "at 60 columns the gauges do not" lacks "of best" "${out}"
out="$(frame "${A}" 59)"
check "at 59 columns only the text line: no sparkline" lacks "14 days" "${out}"
check "at 59 columns only the text line: no gauges" lacks "of best" "${out}"
check "at 59 columns the speedometer's text line is still there" has "1.4 merged/day" "$(sed -n 2p <<< "${out}")"
check "at 59 columns the line under the speedometer is the summary, no blank line" has "epics active" "$(sed -n 3p <<< "${out}")"

if [ "${fails}" -gt 0 ]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
