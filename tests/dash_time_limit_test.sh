#!/usr/bin/env bash
# dash_time_limit_test.sh — dash under the report deadline (dash_deadline, report_read): with every
# herdr, claude and gh read sleeping far past the limit, a one-shot dash still exits, draws its frame
# and names the reads it cut or skipped on its last line, and dash --watch draws its first frame.
# A throwaway project with one active epic, a story in review with three PRs and a ready one; stub
# herdr, claude and gh on PATH that answer at once, or with SLOW set sleep that many seconds (gh logs
# its pid first, to show none outlives the frame). The limit is SWARM_REPORT_SECONDS.
# Each bound is the limit, plus twice the same dash's time with fast stubs (its local work, which the
# deadline does not cover, doubled for a machine whose load moves between runs), plus 10 seconds. With
# report_read taken out the slow reads add 10 minutes, so each run is stopped 5 seconds past its bound.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
pids=()
cleanup() { for p in "${pids[@]+"${pids[@]}"}"; do kill "${p}" 2>/dev/null || true; done; rm -rf "${ROOT}"; }
trap cleanup EXIT
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
lacks() { ! grep -qF -- "$1" <<< "$2"; }
now() { date +%s; }

LIMIT=10
SLOW_SECONDS=300
PRS=3
P="${ROOT}/proj"
mkdir -p "${P}/board/stories" "${P}/board/epics" "${P}/.claude/swarm" "${P}/.swarm/state" "${ROOT}/bin" "${ROOT}/tmp" "${ROOT}/projects"
echo "# Stories" > "${P}/board/stories/README.md"
echo "board_dir = board" > "${P}/.claude/swarm/config"
printf -- '---\nstatus: active\n---\n\n# e1\n' > "${P}/board/epics/e1.md"
printf -- '---\nstatus: review\nepic: e1\nprs: [%s]\n---\n\n# s-one\n' \
  "$(for i in $(seq 1 "${PRS}"); do printf 'https://github.com/o/r/pull/%s\n' "${i}"; done | paste -sd, - | sed 's/,/, /g')" > "${P}/board/stories/s-one.md"
printf -- '---\nstatus: ready\nepic: e1\n---\n\n# s-two\n' > "${P}/board/stories/s-two.md"
printf 'w1:p1 s-two\n' > "${P}/.swarm/state/s-two"
git -C "${P}" init -q

# The stubs: exec, so a read cut at the deadline is the sleep itself, in report_read's process group.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
[ -z "${SLOW:-}" ] || exec sleep "${SLOW}"
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"s-two","agent_status":"working","pane_id":"w1:p1"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"e1"}]}}' ;;
  *) exit 1 ;;
esac
STUB
cat > "${ROOT}/bin/claude" <<'STUB'
#!/bin/sh
[ -z "${SLOW:-}" ] || exec sleep "${SLOW}"
[ "$*" = "agents --json" ] && echo '[]'
STUB
cat > "${ROOT}/bin/gh" <<'STUB'
#!/bin/sh
[ -z "${SLOW:-}" ] || { echo "$$" >> "${GH_PIDS}"; exec sleep "${SLOW}"; }
case "$1 $2" in
  "pr view") echo '{"state":"OPEN","mergeStateStatus":"CLEAN","statusCheckRollup":[]}' ;;
  *) exit 1 ;;
esac
STUB
for b in stty tput; do printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/${b}"; done
chmod +x "${ROOT}/bin/"*
unset COLUMNS LINES DASH_COLOR DASH_W DASH_H NO_COLOR
export CLAUDE_CONFIG_DIR="${ROOT}/config"   # under its own root, so parallel runs share no ~/.claude
export PATH="${ROOT}/bin:${PATH}" TMPDIR="${ROOT}/tmp" CLAUDE_PROJECTS_DIR="${ROOT}/projects" \
  SWARM_REPORT_SECONDS="${LIMIT}" GH_PIDS="${ROOT}/gh.pids"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks gh again.
fresh() { rm -rf "${TMPDIR}"/swarm-dash-*; }

# run_dash <out> <stop after> <slow> <args>... — dash in the background with its pid recorded, stopped
# (TERM) once it has run <stop after> seconds; prints the seconds it ran and its exit status.
run_dash() {
  local out="$1" stop="$2" slow="$3" start pid rc=0
  shift 3
  start="$(now)"
  (cd "${P}" && exec env -u HERDR_ENV SLOW="${slow}" "${SWARM}" dash "$@") > "${out}" 2>&1 &
  pid=$!; pids+=("${pid}")
  while kill -0 "${pid}" 2>/dev/null && (( $(now) - start < stop )); do sleep 0.2; done
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || rc=$?
  echo "$(($(now) - start)) ${rc}"
}
# alive <pid file> — the pids in the file that still run, on one line.
alive() { local p; while read -r p; do if kill -0 "${p}" 2>/dev/null; then printf '%s ' "${p}"; fi; done < "$1"; }

# --- The same dash with fast stubs and an hour's limit: its local work, and the frame it draws with
# every read answered. Stopped only after 30 minutes: a guard for a direct run on a loaded machine
# (make test stops it sooner).
fresh
read -r fast rc <<< "$(SWARM_REPORT_SECONDS=3600 run_dash "${ROOT}/fast.out" 1800 "")"
out="$(cat "${ROOT}/fast.out")"
check "with fast reads, dash exits 0" test "${rc}" = 0
check "with fast reads, dash draws its frame" has "swarm-dev" "${out}"
check "with fast reads, dash names no skipped read" lacks "skipped (over " "${out}"
bound=$((fast * 2 + LIMIT + 10))
echo "     fast dash took ${fast} s: the bound is ${bound} s"

# --- Every read sleeps past the limit: dash exits within the bound, draws its frame from what it has,
# and names the reads it cut or skipped: gh PR states (dash_slow.py's, cut at the deadline, stopped by
# dash_slow.py a second short of it, or never started) and herdr agent list (after it).
fresh
read -r took rc <<< "$(run_dash "${ROOT}/slow.out" $((bound + 5)) "${SLOW_SECONDS}")"
out="$(cat "${ROOT}/slow.out")"
check "with reads past the limit, dash exits 0" test "${rc}" = 0
check "with reads past the limit, dash exits within the limit plus a few seconds (${took} s, bound ${bound} s)" test "${took}" -le "${bound}"
check "with reads past the limit, dash still draws its frame" has "swarm-dev" "${out}"
is "with reads past the limit, dash names the reads it skipped, last" \
  "skipped (over ${LIMIT} s): gh PR states, herdr agent list" "$(tail -n 1 <<< "${out}")"

# --- dash_slow.py as dash runs it, with its deadline (DASH_READ_END) 10 s away and every gh call
# sleeping past it: it stops its own gh calls (each in a session of its own, which report_read's KILL
# of the group would miss) a second short of the deadline and exits 142 itself, so none outlives it.
# Stopped (TERM, 143) after 30 s, so a 142 is its own exit.
: > "${GH_PIDS}"
urls=(); for i in $(seq 1 "${PRS}"); do urls+=("https://github.com/o/r/pull/${i}"); done
start="$(now)"
(exec env SLOW="${SLOW_SECONDS}" SWARM_PAIRS="" SWARM_NO_CI_REFRESH=1 DASH_READ_END="$(perl -MTime::HiRes=time -e 'printf "%.3f", time + 10')" \
  python3 -u "${REPO}/bin/lib/dash_slow.py" "${urls[@]}") > "${ROOT}/py.out" 2>&1 &
pid=$!; pids+=("${pid}")
while kill -0 "${pid}" 2>/dev/null && (( $(now) - start < 30 )); do sleep 0.2; done
kill "${pid}" 2>/dev/null || true
rc=0; wait "${pid}" 2>/dev/null || rc=$?
took=$(($(now) - start))
check "dash_slow.py asked gh before its deadline" test -s "${GH_PIDS}"
is "dash_slow.py stops at its deadline and exits 142, report_read's cut (${took} s)" 142 "${rc}"
is "no gh call dash_slow.py stopped at its deadline outlives it" "" "$(alive "${GH_PIDS}")"

# --- dash --watch with every read past the limit: its first frame appears within the bound, naming
# the skipped reads under it, cut to its 45 columns so the line never wraps. Off a terminal each frame
# is printed whole.
fresh
start="$(now)"
(cd "${P}" && exec env -u HERDR_ENV COLUMNS=45 SLOW="${SLOW_SECONDS}" "${SWARM}" dash --watch 1) > "${ROOT}/watch.out" 2>&1 &
pid=$!; pids+=("${pid}")
first=""
while (( $(now) - start <= bound + 5 )); do
  if grep -q '^skipped (over ' "${ROOT}/watch.out" 2>/dev/null; then first=$(($(now) - start)); break; fi
  sleep 0.2
done
kill "${pid}" 2>/dev/null || true
wait "${pid}" 2>/dev/null || true
check "dash --watch's first frame appears within the limit plus a few seconds (${first:-none} s, bound ${bound} s)" \
  test -n "${first}" -a "${first:-0}" -le "${bound}"
# Under 100 columns the header drops the version, so the frame is known by its project's name.
check "dash --watch's first frame is drawn, headed by the project" grep -q '^proj  ' "${ROOT}/watch.out"
check "the skipped line is cut to the frame's 45 columns, ending in …" test \
  "$(grep -m 1 '^skipped (over ' "${ROOT}/watch.out" | python3 -c 'import sys; l = sys.stdin.read().rstrip("\n"); print(len(l), l[-1:])')" = "45 …"

# --- A frame one line high (DASH_H=1, a --project share) with a read past the limit stays one line:
# its header, with no room for the skipped line.
fresh
DASH_H=1 run_dash "${ROOT}/one.out" $((bound + 5)) "${SLOW_SECONDS}" > /dev/null
out="$(cat "${ROOT}/one.out")"
check "a one-line frame with reads past the limit is one line, its header" \
  test "$(wc -l < "${ROOT}/one.out" | tr -d ' ')|$(grep -c 'swarm-dev' <<< "${out}")" = "1|1"

if (( fails )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
