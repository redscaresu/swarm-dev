#!/usr/bin/env bash
# status_time_limit_test.sh — `swarm.sh status` keeps to the report deadline: its herdr and gh reads,
# its own and those of the functions it calls (pane_check's herdr agent read, stacked_lines' gh pr
# list, next's herdr agent list), share REPORT_SECONDS through report_read. With herdr and gh stubs
# that sleep three times that long, status exits within the deadline of the time it takes with fast
# stubs, and its last line names the reads it skipped. With fast stubs its output is what it was.
# The stubs: herdr lists one agent, child, in this project's pane w:1 and reads its pane; gh answers
# pr list with an open PR, so child, stacked on p, shows a Stacked line. herdr sleeps $HERDR_SLEEP
# seconds first, gh $GH_SLEEP; each is slowed in a run of its own.
# The bound is relative to the fast run, not absolute, so it holds on a loaded machine, where status's
# own work, not its reads, takes most of the time.
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
SLACK=15   # seconds a slow run may take past the fast run plus the deadline: the cut, and the noise

# shellcheck disable=SC2034 # merge.sh reads PROJECT_DIR as it loads
PROJECT_DIR="${ROOT}"
# shellcheck source=/dev/null
. "${REPO}/bin/lib/merge.sh"   # REPORT_SECONDS, and within to cap a status that ignores the deadline

mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
# shellcheck disable=SC2016 # the stubs' lines are literal: each reads its sleep when it runs
for t in herdr gh; do printf '#!/bin/sh\nsleep "${%s_SLEEP:-0}"\n' "$(tr '[:lower:]' '[:upper:]' <<< "${t}")" > "${ROOT}/bin/${t}"; done
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"child","agent_status":"idle","pane_id":"w:1"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:1"}]}}' ;;
  "agent read") echo 'child is working' ;;
esac
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$1 $2" in "pr list") echo '[{"state":"OPEN"}]' ;; esac
exit 0
STUB
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh" "${ROOT}/bin/claude"
echo "w:1 child" > "${P}/.swarm/state/child"

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
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# status <cap> — status's output, cut after <cap> seconds (within) so a
# status that ignores the deadline fails the check rather than the file's time limit.
status() {
  (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" \
    within "$1" bash "${SWARM}" status 2>&1) || true
}

want="Agents: 0 need a look or are working, 1 idle or done
  (swarm.sh status --all lists them all)

Stacked
  child: merge origin/story/p

Waiting on you
  awaiting your merge: p https://github.com/o/r/pull/1
  1 blocked stories wait on others (swarm.sh status --all lists them)

Next
  gate
  only you can move the board now:
    blocked: child (by p)
    awaiting your merge: p https://github.com/o/r/pull/1"

t0="$(now)"; fast="$(status 1800)"; t1="$(now)"
is "with fast stubs status's output is as before the deadline, with no skipped line" "${want}" "${fast}"
spent="$(awk -v a="${t0}" -v b="${t1}" 'BEGIN { print b - a }')"
bound="$(awk -v s="${spent}" -v r="${REPORT_SECONDS}" -v k="${SLACK}" 'BEGIN { printf "%d\n", s + r + k + 1 }')"

# slow <herdr|gh> <read> — with that stub sleeping three times the deadline, status ends within the
# deadline of the fast run's time, names <read>, the one cut at the deadline, first on its last line
# (every read after it is skipped at once and named after it), and still prints its sections.
slow() {
  local out t0 t1 last var=HERDR_SLEEP
  [[ "$1" == herdr ]] || var=GH_SLEEP
  t0="$(now)"; out="$(export "${var}=$((3 * REPORT_SECONDS))"; status "$((bound + 5))")"; t1="$(now)"
  holds "$1 sleeping past the deadline: status ends within it of a fast run's time" "b - a <= ${bound}" "${t0}" "${t1}"
  last="$(tail -n 1 <<< "${out}")"
  is "$1 sleeping past the deadline: the last line names the read cut first" \
    "skipped (over ${REPORT_SECONDS} s): $2" "${last%%,*}"
  is "$1 sleeping past the deadline: status still prints its sections" 1 "$(grep -cx 'Waiting on you' <<< "${out}" || true)"
}
slow herdr "herdr agent list"
slow gh "gh pr list"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
