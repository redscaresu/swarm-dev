#!/usr/bin/env bash
# dash_time_limit_test.sh — dash under the report deadline (dash_deadline, report_read): with every
# herdr, claude and gh read sleeping far past the limit, a one-shot dash still exits, draws its frame
# and names the reads it cut or skipped on its last line, and dash --watch draws its first frame.
# A throwaway project with one active epic, a story in review with three PRs and a ready one; stub
# herdr, claude and gh on PATH that answer at once, or with SLOW set sleep that many seconds (gh logs
# its pid first, to show none outlives the frame); with SLOW_READ set only herdr's read of an agent's
# pane sleeps, the read dash_render.py makes (panes.py's pane_text); with SLOW_GH only gh sleeps; with
# SLOW_IN naming a project, the stubs sleep only under that project (SWARM_PROJECT, a --project child's).
# The limit is SWARM_REPORT_SECONDS.
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
P2="${ROOT}/proj2"; cp -R "${P}" "${P2}"   # a second project for --project, the same board

# The stubs: exec, so a read cut at the deadline is the sleep itself, in report_read's process group.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
[ -z "${SLOW:-}" ] || exec sleep "${SLOW}"
[ -z "${SLOW_IN:-}" ] || [ "${SWARM_PROJECT:-}" != "${SLOW_IN}" ] || exec sleep "${SLOW_IN_FOR}"
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"s-two","agent_status":"working","pane_id":"w1:p1"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"e1"}]}}' ;;
  "agent read") [ -z "${SLOW_READ:-}" ] || exec sleep "${SLOW_READ}"; exit 1 ;;
  *) exit 1 ;;
esac
STUB
cat > "${ROOT}/bin/claude" <<'STUB'
#!/bin/sh
[ -z "${SLOW:-}" ] || exec sleep "${SLOW}"
[ -z "${SLOW_IN:-}" ] || [ "${SWARM_PROJECT:-}" != "${SLOW_IN}" ] || exec sleep "${SLOW_IN_FOR}"
[ "$*" = "agents --json" ] && echo '[]'
STUB
cat > "${ROOT}/bin/gh" <<'STUB'
#!/bin/sh
[ -z "${SLOW:-}${SLOW_GH:-}" ] || { echo "$$" >> "${GH_PIDS}"; date +%s >> "${GH_STARTS}"; exec sleep "${SLOW:-${SLOW_GH}}"; }
[ -z "${SLOW_IN:-}" ] || [ "${SWARM_PROJECT:-}" != "${SLOW_IN}" ] || exec sleep "${SLOW_IN_FOR}"
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
  SWARM_REPORT_SECONDS="${LIMIT}" GH_PIDS="${ROOT}/gh.pids" GH_STARTS="${ROOT}/gh.starts"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks gh again.
fresh() { rm -rf "${TMPDIR}"/swarm-dash-*; }

# run_dash <out> <stop after> <slow> <args>... — dash in the background with its pid recorded, stopped
# (TERM) once it has run <stop after> seconds; prints the seconds it ran and its exit status.
run_dash() {
  local out="$1" stop="$2" slow="$3" start pid rc=0
  shift 3
  start="$(now)"
  (cd "${RUN_IN:-${P}}" && exec env -u HERDR_ENV SLOW="${slow}" SLOW_READ="${SLOW_READ:-}" SLOW_GH="${SLOW_GH:-}" SLOW_IN="${SLOW_IN:-}" SLOW_IN_FOR="${SLOW_SECONDS}" \
    "${SWARM}" dash "$@") > "${out}" 2>&1 &
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
# wide: the limit for the cases whose fast reads must finish before the deadline while one slow read is
# cut at it: LIMIT plus the local work before those reads, taken as the fast run's time, doubled as above.
wide=$((LIMIT * 2 + fast * 2)); wide_bound=$((wide + fast * 2 + 10))
echo "     fast dash took ${fast} s: the bound is ${bound} s; the wide limit ${wide} s, its bound ${wide_bound} s"

# --- A run cut before its gh reads keeps the cache it had (dash_cache_merge): the fast run's PR states
# and a head line added here stay, and the run's own cost line replaces the old one. With a 1 s limit
# gh's share (half: 0 s) ends before its first call, so gh is never asked, and every read is named.
cache="$(find "${TMPDIR}" -maxdepth 1 -name "swarm-dash-3-*" | head -1)"
printf 'head\ts-two\thttps://github.com/o/r/pull/9\n' >> "${cache}"
python3 -c 'import os, sys, time; t = time.time() - 120; os.utime(sys.argv[1], (t, t))' "${cache}"   # stale: dash asks again
: > "${GH_STARTS}"
SWARM_REPORT_SECONDS=1 run_dash "${ROOT}/cut.out" $((bound + 5)) "${SLOW_SECONDS}" > /dev/null
check "a run cut before gh asked gh nothing" test ! -s "${GH_STARTS}"
check "a run cut before gh keeps the cache's PR states" test "$(grep -c $'^https://github.com/o/r/pull/[0-9]*\t.*OPEN' "${cache}")" = "${PRS}"
check "a run cut before gh keeps the cache's head line" grep -qx $'head\ts-two\thttps://github.com/o/r/pull/9' "${cache}"
check "a run cut before gh writes its own cost line, once" test "$(grep -c $'^cost\t' "${cache}")" = 1
is "a run cut before gh names gh PR states" "skipped (over 1 s): gh PR states, herdr agent list" "$(tail -n 1 "${ROOT}/cut.out")"

# --- gh's share of the deadline (the wide limit): a project with more PRs than half the limit holds
# (dash_slow.py gives each gh call 5 s), gh alone slow. dash_slow.py stops asking at half the limit, so
# gh's calls (GH_STARTS, the stub's start times) span at most half of it from the first, and the frame
# names gh PR states, cut. Without the share they would go on to a second short of the whole limit.
P3="${ROOT}/proj3"; cp -R "${P}" "${P3}"; prs3=$((wide / 5 + 2))
printf -- '---\nstatus: review\nepic: e1\nprs: [%s]\n---\n\n# s-one\n' \
  "$(for i in $(seq 1 "${prs3}"); do printf 'https://github.com/o/r/pull/%s\n' "${i}"; done | paste -sd, - | sed 's/,/, /g')" > "${P3}/board/stories/s-one.md"
fresh; : > "${GH_STARTS}"
RUN_IN="${P3}" SLOW_GH="${SLOW_SECONDS}" SWARM_REPORT_SECONDS="${wide}" run_dash "${ROOT}/share.out" $((wide_bound + 5)) "" > /dev/null
span="$(python3 -c 'import sys; t = [int(l) for l in open(sys.argv[1]) if l.strip()]; print(max(t) - min(t) if t else "none")' "${GH_STARTS}")"
share_ok() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 <= $2 )); }   # <span> <at most>
check "with gh alone slow and ${prs3} PRs, gh's calls span at most half the limit (${span} s, at most $((wide / 2 + 1)))" share_ok "${span}" $((wide / 2 + 1))
check "with gh alone slow, gh was asked more than once" test "$(grep -c . "${GH_STARTS}")" -gt 1
check "with gh alone slow, the frame names gh PR states" has "gh PR states" "$(tail -n 1 "${ROOT}/share.out")"

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

# --- Only the read of an agent's pane sleeps past the limit (the wide one); herdr's lists, claude and
# gh answer at once. The frame still shows the agent (s-two, working in its pane), ends within the
# bound, and names that read, which dash_render.py makes under SWARM_REPORT_END (panes.py's pane_text):
# the only skip of the frame, so dash draws the frame again a line shorter to make room for the line.
fresh
read -r took rc <<< "$(SLOW_READ="${SLOW_SECONDS}" SWARM_REPORT_SECONDS="${wide}" run_dash "${ROOT}/read.out" $((wide_bound + 5)) "")"
out="$(cat "${ROOT}/read.out")"
check "with only the pane read past the limit, dash exits 0" test "${rc}" = 0
check "with only the pane read past the limit, dash exits within the limit plus a few seconds (${took} s, bound ${wide_bound} s)" test "${took}" -le "${wide_bound}"
check "with only the pane read past the limit, the frame still shows the agent working" grep -qE 's-two .*working' <<< "${out}"
is "with only the pane read past the limit, dash names that read, last" \
  "skipped (over ${wide} s): herdr agent read" "$(tail -n 1 <<< "${out}")"

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

# --- A frame two lines high (DASH_H=2) gives its second line to the skipped reads: its header, then the line.
fresh
DASH_H=2 run_dash "${ROOT}/two.out" $((bound + 5)) "${SLOW_SECONDS}" > /dev/null
check "a two-line frame with reads past the limit is its header and the skipped line" \
  test "$(wc -l < "${ROOT}/two.out" | tr -d ' ')|$(sed -n 1p "${ROOT}/two.out" | grep -c 'swarm-dev')|$(sed -n 2p "${ROOT}/two.out" | grep -c '^skipped (over ')" = "2|1|1"

# --- --project: each project's frame has a deadline of its own. With proj's reads past the limit and
# proj2's answering at once, proj's frame names its reads, and proj2's, drawn after it, names none and
# shows its agent: with one deadline shared it would start past it, every read skipped at once.
fresh
SLOW_IN="${P}" SWARM_REPORT_SECONDS="${wide}" run_dash "${ROOT}/projects.out" $((wide_bound + fast * 2 + 5)) "" --project "${P}" --project "${P2}" > /dev/null
after="$(awk '/^proj2 /{p=1} p' "${ROOT}/projects.out")"
check "--project: the slow project's frame names its reads, once in all" test "$(grep -c '^skipped (over ' "${ROOT}/projects.out")" = 1
check "--project: the fast project drawn after it is headed" test -n "${after}"
check "--project: the fast project drawn after it names no skipped read" lacks "skipped (over " "${after}"
check "--project: the fast project drawn after it shows its agent working" grep -qE 's-two .*working' <<< "${after}"

if (( fails )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
