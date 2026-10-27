#!/usr/bin/env bash
# flow_run_times_test.sh — flow's run_times section, on a fixture run-times.tsv: per command, its
# runs, median and p90 (nearest rank) seconds and the share over 60 s in the window, torn rows and
# rows outside it left out; a line with no row in the window, and one with no log. Then status, next
# and dash each append one row to .swarm/run-times.tsv (start, command, seconds, load) and no
# events.tsv line, in a small fixture project A (one active epic, one ready story; herdr and gh
# stubbed to fail). _step and wait --lead 0 append none. dash --project B, run from A, runs swarm.sh
# dash again in B, and only the outer run is timed, in A; run from a folder that is no project but
# holds a .swarm/, it writes no row there. A run whose clock (now_ms) fails still exits as it would,
# with no row. dash --watch times its first frame only. TZ is UTC.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
watcher=""
# tree <pid> — the process and everything under it, children first.
tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do tree "${c}"; done; echo "$1"; }
# shellcheck disable=SC2046 # one pid per word
stop_watch() { [[ -z "${watcher}" ]] || kill $(tree "${watcher}") 2>/dev/null || true; wait 2>/dev/null || true; watcher=""; }
trap 'stop_watch; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# The claude stub goes first on PATH, so no run here reaches the real claude; herdr and gh fail, and
# so do stty and tput, so dash measures no terminal. No global or system git config (hooksPath,
# signing): the same git here and in CI.
mkdir -p "${ROOT}/stub-bin" "${ROOT}/tmp"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/stub-bin/claude"
for b in herdr gh stty tput; do printf '#!/bin/sh\nexit 1\n' > "${ROOT}/stub-bin/${b}"; done
chmod +x "${ROOT}/stub-bin/"*
export PATH="${ROOT}/stub-bin:${PATH}" TMPDIR="${ROOT}/tmp" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset COLUMNS LINES HERDR_ENV HERDR_PANE_ID

# The section, on a fixture log: next takes 1 to 10 s, status 30, 61 and 90 s; a dash row the day
# before the window, a torn row (no newline) and rows that do not parse count nowhere.
P="${ROOT}/flow"
mkdir -p "${P}/.swarm"
git -C "${P}" init -q
section() { (cd "${P}" && env -u SWARM_PROJECT SWARM_FLOW_SECTIONS=run_times bash "${SWARM}" flow "$@" | grep -v '^## run_times$'); }
check "with no log it says so" "$(section)" "no run times logged: no ${P}/.swarm/run-times.tsv yet (status, next and dash write it)"
{
  for s in 7 1 10 3 5 2 9 4 8 6; do printf '2026-10-02T09:00:00Z\tnext\t%s.000\t1.50\n' "${s}"; done
  printf '2026-10-02T10:00:00Z\tstatus\t%s\t-\n' 30.000 61.000 90.000
  printf '2026-10-01T23:59:59Z\tdash\t500.000\t2.00\n'
  printf '2026-10-02T11:00:00Z\tdash\t%s\t2.00\n' slow nan inf -5.000
  printf '2026-10-02T11:00:00Z\tstatus \t1.000\t2.00\n'
  printf '2026-10-02T11:00:00Z\tdash\t1.000\n'
  printf 'yesterday\tdash\t1.000\t2.00\n'
  printf '2026-10-02T12:00:00Z\tdash\t2.000\t2.00'
} > "${P}/.swarm/run-times.tsv"
check "per command: runs, median and p90 seconds, the share over 60 s" "$(section --since 2026-10-02)" \
  "$(printf 'command\truns\tmedian_s\tp90_s\tover_60s\nnext\t10\t5.50\t9.00\t0%%\nstatus\t3\t61.00\t90.00\t67%%')"
check "a row the day before the window counts once the window holds it" "$(section --since 2026-10-01 | grep '^dash')" \
  "$(printf 'dash\t1\t500.00\t500.00\t100%%')"
check "with no row in the window it says so" "$(section --since 2026-10-03)" "no run times logged in the window (2026-10-03 to 9999-12-30)"

project() { # <dir> — a swarm project: config, board, one active epic, one ready story, one event, a commit
  mkdir -p "$1/.claude/swarm" "$1/.swarm" "$1/board/stories" "$1/board/epics"
  echo "board_dir = board" > "$1/.claude/swarm/config"
  echo "# Stories" > "$1/board/stories/README.md"
  printf -- '---\nstatus: active\n---\n\n# Core\n' > "$1/board/epics/core.md"
  printf -- '---\nstatus: ready\nkind: code\nepic: core\n---\n\n# Add the cache\n' > "$1/board/stories/s-a.md"
  printf '2026-10-01T00:00:00Z\tinit\t-\t-\tok\n' > "$1/.swarm/events.tsv"
  git -C "$1" init -q -b main
  git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.com commit -qm board
}
A="${ROOT}/alpha"; B="${ROOT}/bravo"
project "${A}"; project "${B}"
sw() { (cd "${A}" && rm -rf "${TMPDIR}"/swarm-dash-* && bash "${SWARM}" "$@" > /dev/null 2>&1) || true; }
times_a="${A}/.swarm/run-times.tsv"
rows() { if [[ -f "$1" ]]; then cut -f2 "$1" | tr '\n' ' '; fi; }
events_before="$(cat "${A}/.swarm/events.tsv")"

sw status
sw next
sw dash
check "status, next and dash each leave one row, in that order" "$(rows "${times_a}")" "status next dash "
check "they leave no events.tsv line" "$(cat "${A}/.swarm/events.tsv")" "${events_before}"
iso='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
IFS=$'\t' read -r at cmd secs load <<< "$(head -1 "${times_a}")"
dash_s="$(awk -F'\t' '$2 == "dash" { print int($3) + 1; exit }' "${times_a}")"   # one frame's seconds here, for the watch's wait
check "a row is a UTC start, the command, seconds to the millisecond and the load" \
  "$([[ ${at} =~ ${iso} && ${cmd} == status && ${secs} =~ ^[0-9]+\.[0-9]{3}$ && ${load} =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo yes)" yes

: > "${times_a}"
sw _step
sw wait --lead 0
check "_step and wait --lead 0 leave no row" "$(rows "${times_a}")" ""

sw dash --project "${B}"
check "dash --project is one row, in the project it ran from" "$(rows "${times_a}")" "dash "
check "the project it draws gets none" "$(rows "${B}/.swarm/run-times.tsv")" ""
# From a folder in no project (no git repo, no config above it) that holds a .swarm/, as HOME does
# once ~/.swarm/test-cap is used: the cwd only stands in, so no row lands there.
O="${ROOT}/elsewhere"; mkdir -p "${O}/.swarm"
(cd "${O}" && env -u SWARM_PROJECT bash "${SWARM}" dash --project "${B}" > /dev/null 2>&1) || true
check "dash --project from outside a project writes no row in the cwd's .swarm/" "$(ls -A "${O}/.swarm")|$(rows "${B}/.swarm/run-times.tsv")" "|"

# A python3 whose clock call (now_ms's) fails: next still exits 0 with its step, and logs no row.
mkdir -p "${ROOT}/noclock"
printf '#!/bin/sh\ncase "$*" in *time.time*) exit 1 ;; esac\nexec %q "$@"\n' "$(command -v python3)" > "${ROOT}/noclock/python3"
chmod +x "${ROOT}/noclock/python3"
: > "${times_a}"
rc=0; out="$(cd "${A}" && PATH="${ROOT}/noclock:${PATH}" bash "${SWARM}" next 2>&1)" || rc=$?
check "with a clock that fails, next exits 0, prints its step and logs no row" "${rc}|$([[ -n "${out}" ]] && echo step)|$(rows "${times_a}")" "0|step|"

# A watch never returns: its row comes after its first frame, and no later frame adds one. Off a
# terminal, dash_watch runs `sleep 1` after each frame and its row, so a sleep stub on the watch's
# PATH counts finished frames: at two, frame 2 has written any row it would. The wait is by the
# clock (SECONDS), however slow the polls: 60 s and four times what the one-shot dash above took, as
# a frame takes seconds in CI and minutes on a loaded machine.
mkdir -p "${ROOT}/sleep-bin"
printf '#!/bin/sh\n[ "$*" = 1 ] && echo frame >> %q\nexec %q "$@"\n' "${ROOT}/frames" "$(command -v sleep)" > "${ROOT}/sleep-bin/sleep"
chmod +x "${ROOT}/sleep-bin/sleep"
: > "${times_a}"; : > "${ROOT}/frames"
(cd "${A}" && PATH="${ROOT}/sleep-bin:${PATH}" exec bash "${SWARM}" dash --watch 1 > /dev/null 2>&1) &
watcher=$!
frames() { wc -l < "${ROOT}/frames" | tr -d ' '; }
until_by=$((SECONDS + 60 + 4 * ${dash_s:-60}))
until (( $(frames) >= 2 || SECONDS > until_by )); do sleep 0.1; done
check "dash --watch leaves one row, for its first frame, once its second has ended, while it still runs" \
  "$(rows "${times_a}")$( (( $(frames) >= 2 )) && echo past-frame-2)$(kill -0 "${watcher}" 2>/dev/null && echo running)" "dash past-frame-2running"
stop_watch

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
