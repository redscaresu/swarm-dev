#!/usr/bin/env bash
# events_tail_test.sh — whole commands read events.tsv the same with a key=value tail on every row. Two
# stand-in projects (events_tail_helpers.sh) hold the v0.29.1 fixture plus a few synthetic rows, the second
# with ` ~~ k=v` on every row, and the same board; same_output compares, over the two:
#   - `swarm.sh dash --check`, at a fixed now near the fixture's end: it exits 0 and prints the same, so the
#     frame's figures agree with status, next and flow's sections in both.
#   - lead_queue, the function wait --lead reads, after lead_agents, as lead_wake runs them. It runs from a
#     copy of swarm.sh whose last line calls the two in place of main, so the queue is read with every
#     setting and file swarm.sh sets and nothing else: wait --lead itself blocks, asks gh and writes.
# herdr lists two builders working in this project's panes; gh, stty and tput fail; claude is the stub.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
pids=()
cleanup() { for p in "${pids[@]+"${pids[@]}"}"; do kill "${p}" 2>/dev/null || true; done; rm -rf "${ROOT}"; }
trap cleanup EXIT
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
lacks() { ! grep -qF -- "$1" <<< "$2"; }

STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp" "${ROOT}/projects"
cp "${HERE}/claude_stub.sh" "${STUB_BIN}/claude"
for c in stty tput gh; do printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/${c}"; done
cat > "${STUB_BIN}/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"zzlqa","agent_status":"working","pane_id":"w1:p1"},{"name":"zzlqb","agent_status":"working","pane_id":"w1:p2"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"}]}}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${STUB_BIN}"/*
echo '[]' > "${ROOT}/claude.json"
unset COLUMNS LINES DASH_COLOR DASH_W DASH_H NO_COLOR
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json" CLAUDE_PROJECTS_DIR="${ROOT}/projects" \
  CLAUDE_CONFIG_DIR="${ROOT}/claude-config" TMPDIR="${ROOT}/tmp"

# The fixture, then two builders at work whose review agents' starts failed after their briefs: zzlqa's
# review is owed (a no-review: line), and zzlqb's is under way again, a findings tell having followed.
EVENTS="${ROOT}/events.tsv"
cp "${EVENTS_FIXTURE}" "${EVENTS}"
printf '2026-10-29T02:00:%02dZ\t%s\t%s\twa:pa\t%s\n' \
  1 story zzlqa ok 2 review-agent zzlqa 'review-agent: review-zzlqa did not start' \
  3 story zzlqb ok 4 review-agent zzlqb 'review-agent: review-zzlqb did not start' 5 tell:findings zzlqb ok >> "${EVENTS}"

story() { # <project> <slug> <front-matter line>...
  local f="$1/docs/stories/$2.md"; shift 2
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${f##*/}"; } > "${f}"
}
# setup <project> [<tail>] — the project, its board: zzcl and zzep, started and closed in the fixture with
# their builds left (a no-agent: line each), and zzlqa and zzlqb in the panes herdr lists.
setup() {
  local p="$1" s
  events_project "${p}" "${EVENTS}" "${2:-}" || return 1
  touch "${p}/docs/stories/README.md"
  for s in zzcl zzep; do story "${p}" "${s}" 'status: ready' 'kind: code'; mkdir -p "${p}-wt/${s}"; done
  story "${p}" zzlqa 'status: ready' 'kind: code' 'prs: [https://github.com/o/r/pull/40]'
  story "${p}" zzlqb 'status: ready' 'kind: code' 'prs: [https://github.com/o/r/pull/41]'
  mkdir -p "${p}/.swarm/state" && printf 'w1:p1 zzlqa\nw1:p2 zzlqb\n' > "${p}/.swarm/state/tab"
}
PLAIN="${ROOT}/plain/proj"; TAILED="${ROOT}/tailed/proj"
if ! setup "${PLAIN}" || ! setup "${TAILED}" ' ~~ k=v'; then echo "FAIL could not set up the stand-in projects"; exit 1; fi

# lead_queue's runner: swarm.sh with its own home pinned to this checkout and its last line, main's call,
# swapped for the read.
LQ="${ROOT}/lead-queue.sh"
sed -e "s#^SWARM_HOME=.*#SWARM_HOME='${REPO}'#" -e 's/^main "\$@"; exit$/lead_agents; lead_queue; exit/' "${SWARM}" > "${LQ}"
if [[ "$(grep -cxE "SWARM_HOME='.*'|lead_agents; lead_queue; exit" "${LQ}")" != 2 ]]; then
  echo "FAIL the lead_queue runner: swarm.sh's SWARM_HOME line or its last line changed; update the sed above"; exit 1
fi
# dash --check at 2026-10-29 12:00 UTC, the fixture's day, so its 7-day figures count the fixture's merges.
NOW="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 10, 29, 12, tzinfo=datetime.timezone.utc).timestamp()))')"
# Each project's queue and dash --check run once, the two projects side by side, each into a file in the
# directory above it with its exit status beside it; queue and dash_check print that file and return that status.
for p in "${PLAIN}" "${TAILED}"; do
  (cd "${p}" || exit 1; rc=0; HERDR_ENV=1 bash "${LQ}" > ../queue 2>/dev/null || rc=$?; echo "${rc}" > ../queue.rc
   rc=0; env -u HERDR_ENV SWARM_DASH_NOW="${NOW}" bash "${SWARM}" dash --check > ../check 2>/dev/null || rc=$?; echo "${rc}" > ../check.rc) &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "${p}" || true; done
queue() { cat ../queue; return "$(cat ../queue.rc)"; }
dash_check() { cat ../check; return "$(cat ../check.rc)"; }

check "lead_queue prints the same lines with a tail" same_output "${PLAIN}" "${TAILED}" queue
out="$(cd "${PLAIN}" && queue)" || true
check "lead_queue untailed: no-agent: for zzcl and zzep, closed with their builds left" \
  test "$(grep -oE '^no-agent: zz[a-z]+' <<< "${out}" | paste -sd' ' -)" = "no-agent: zzcl no-agent: zzep"
check "lead_queue untailed: no-review: for zzlqa, whose review start failed" \
  grep -qxF 'no-review: zzlqa https://github.com/o/r/pull/40, exit: swarm.sh review-agent zzlqa https://github.com/o/r/pull/40, or the fallback reviewer' <<< "${out}"
check "lead_queue untailed: none for zzlqb, a findings tell after its failed start" lacks zzlqb "${out}"

check "dash --check prints the same with a tail" same_output "${PLAIN}" "${TAILED}" dash_check
check "dash --check exits 0 with a tail: every figure agrees" test "$(cat "${ROOT}/tailed/check.rc")" -eq 0
check "dash --check says so with a tail" grep -qxF 'proj: every dash figure agrees with the command that owns it' "${ROOT}/tailed/check"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
