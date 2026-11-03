#!/usr/bin/env bash
# status_section_times_test.sh — with SWARM_REPORT_TIMES=1, `swarm.sh status` writes one
# `time: <section> <s.mmm>` line per section to stderr (status_time, bin/lib/merge.sh), in the order
# no-agent, agents, stacked, waiting, next, idle, then total. Unset, or set to 0, it writes none, and
# its stdout is byte-identical to the timed run's. The board is status_time_limit_test.sh's, run outside
# herdr: child is stacked on p, which moved, and the gh stub answers pr list with an open PR, so the
# Stacked section reads it. With that stub sleeping 1 s on pr list (stacked_child's read, the only one
# status makes), the stacked line reads at least 1.000 and total at least as much.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/child"; UP="${ROOT}/upstream"
GIT=(git -c user.name=t -c user.email=t@t)
SECTIONS="no-agent agents stacked waiting next idle total"

mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
# shellcheck disable=SC2016 # the stub's line is literal: it logs its own arguments when it runs
printf '#!/bin/sh\necho "$1 $2" >> "%s"\n' "${ROOT}/gh-calls" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$1 $2" in "pr list") sleep "${PR_LIST_SLEEP:-0}"; echo '[{"state":"OPEN"}]' ;; esac
exit 0
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/claude"

item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; }
git init -q --bare "${ROOT}/origin.git" && git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" init -q && git -C "${P}" remote add origin "${ROOT}/origin.git"
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init && git -C "${P}" push -q origin HEAD:refs/heads/main
git clone -q "${ROOT}/origin.git" "${UP}"
"${GIT[@]}" -C "${UP}" checkout -q -b story/p && "${GIT[@]}" -C "${UP}" commit -q --allow-empty -m p1
git -C "${UP}" push -q origin story/p
git -C "${P}" fetch -q origin
git -C "${P}" worktree add -q -b story/child "${WT}" origin/story/p
"${GIT[@]}" -C "${UP}" commit -q --allow-empty -m p2 && git -C "${UP}" push -q origin story/p   # p moved
item p 'status: review' 'kind: code' 'prs: https://github.com/o/r/pull/1'
item child 'status: blocked' 'kind: code' 'depends_on: [p]'
printf '2026-10-01T00:00:00Z\tstacked\tchild\tw:9\tok (on p)\n' > "${P}/.swarm/events.tsv"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
holds() {
  if awk -v a="$3" -v b="$4" "BEGIN { exit !($2) }"; then echo "ok   $1"
  else echo "FAIL $1: $2 with a=$3, b=$4"; fails=$((fails + 1)); fi
}
# status <name> [VAR=value...] — run status outside herdr with those settings, its stdout in
# ${ROOT}/<name>.out and its stderr in ${ROOT}/<name>.err. A run here takes some seconds of status's own
# work, so its report deadline is an hour (SWARM_REPORT_SECONDS): on a loaded host no read is cut, which
# would empty Stacked or make one run's stdout differ from another's.
status() {
  local name="$1"; shift
  : > "${ROOT}/gh-calls"
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID PATH="${ROOT}/bin:${PATH}" SWARM_REPORT_SECONDS=3600 "$@" \
    bash "${SWARM}" status > "${ROOT}/${name}.out" 2> "${ROOT}/${name}.err") || true
}
# times <name> — the run's time: lines.
times() { grep '^time: ' "${ROOT}/$1.err" || true; }
# value <name> <section> — the seconds the run's time: line for <section> gives.
value() { times "$1" | awk -v s="$2" '$2 == s { print $3 }'; }

# Each run takes status's own time on this board (some seconds), so the timed run is the slow one too:
# every run's pr list sleeps 1 s, which changes no output.
status timed SWARM_REPORT_TIMES=1 PR_LIST_SLEEP=1
is "the timed run reads pr list once, stacked_child's, so a slow pr list slows Stacked alone" "pr list" "$(cat "${ROOT}/gh-calls")"
is "SWARM_REPORT_TIMES=1: one time: line per section, in order" "${SECTIONS}" "$(times timed | awk '{ print $2 }' | paste -sd' ' -)"
is "SWARM_REPORT_TIMES=1: every time: line is time: <section> <s.mmm>" 7 \
  "$(times timed | grep -cE '^time: [a-z-]+ [0-9]+\.[0-9]{3}$' || true)"
is "SWARM_REPORT_TIMES=1: status still prints its Stacked section" 1 "$(grep -cx 'Stacked' "${ROOT}/timed.out" || true)"
stacked="$(value timed stacked)"; total="$(value timed total)"
holds "pr list sleeping 1 s: the stacked line reads at least 1.000" "a >= 1.000" "${stacked:-0}" 0
holds "pr list sleeping 1 s: total includes it" "a >= b && b >= 1.000" "${total:-0}" "${stacked:-0}"
holds "total is at least the sum of the sections" "a >= b" "${total:-0}" \
  "$(times timed | awk '$2 != "total" { s += $3 } END { printf "%.3f\n", s }')"

status unset PR_LIST_SLEEP=1
status zero SWARM_REPORT_TIMES=0 PR_LIST_SLEEP=1
for run in unset zero; do
  is "SWARM_REPORT_TIMES ${run}: no time: line on stderr" "" "$(times "${run}")"
  if cmp -s "${ROOT}/timed.out" "${ROOT}/${run}.out"; then echo "ok   SWARM_REPORT_TIMES ${run}: stdout is byte-identical to the timed run's"
  else echo "FAIL SWARM_REPORT_TIMES ${run}: stdout differs from the timed run's"; diff "${ROOT}/timed.out" "${ROOT}/${run}.out" || true; fails=$((fails + 1)); fi
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
