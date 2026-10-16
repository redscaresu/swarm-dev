#!/usr/bin/env bash
# dash_projects_test.sh — `swarm.sh dash --project <dir> --project <dir>` against two throwaway
# projects, alpha and bravo, each with an active epic of its own, run from a git repo with no board.
# Stub claude, herdr and gh on PATH; stty and tput fail, so nothing here is a terminal.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
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
lacks() { ! grep -qF -- "$1" <<< "$2"; }

project() { # <name> <epic>: a project with a board holding one active epic
  local p="${ROOT}/$1"
  mkdir -p "${p}/board/stories" "${p}/board/epics" "${p}/.claude/swarm"
  echo "# Stories" > "${p}/board/stories/README.md"
  echo "board_dir = board" > "${p}/.claude/swarm/config"
  printf -- '---\nstatus: active\n---\n\n# %s\n' "$2" > "${p}/board/epics/$2.md"
  git -C "${p}" init -q
}
project alpha epic-of-alpha
project bravo epic-of-bravo
A="${ROOT}/alpha"; B="${ROOT}/bravo"
# Enough lead stories that alpha's frame, drawn at no set height, runs past 20 lines.
for i in $(seq 1 15); do
  printf -- '---\nstatus: ready\nkind: lead\nepic: epic-of-alpha\n---\n\n# ask %s\n' "${i}" > "${A}/board/stories/ask-${i}.md"
done
# Where dash runs from: a git repo with no board.
G="${ROOT}/elsewhere"; mkdir -p "${G}"; git -C "${G}" init -q

mkdir -p "${ROOT}/bin" "${ROOT}/tmp" "${ROOT}/projects"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
for b in herdr gh stty tput; do printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/${b}"; done
chmod +x "${ROOT}/bin/"*
unset COLUMNS LINES DASH_COLOR DASH_W DASH_H NO_COLOR SWARM_PROJECT
export PATH="${ROOT}/bin:${PATH}" TMPDIR="${ROOT}/tmp" CLAUDE_PROJECTS_DIR="${ROOT}/projects" \
  CLAUDE_CONFIG_DIR="${ROOT}/config" CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
dash() { (cd "${G}" && env -u HERDR_ENV "${SWARM}" dash "$@"); }
# frame_of <name> <output>: the lines from <name>'s header line up to the next project's.
frame_of() { awk -v n="$1" '/^(alpha|bravo)  swarm-dev / { on = index($0, n "  ") == 1 } on' <<< "$2"; }

check "the calling repo has no board of its own" bash -c "! (cd '${G}' && env -u HERDR_ENV '${SWARM}' dash) 2>/dev/null"
out="$(dash --project "${A}" --project "${B}")"
check "alpha's frame is headed by its name" grep -q '^alpha  swarm-dev ' <<< "${out}"
check "bravo's frame is headed by its name" grep -q '^bravo  swarm-dev ' <<< "${out}"
check "alpha's frame comes first" bash -c "grep -n '^\(alpha\|bravo\)  swarm-dev ' <<< \"\$1\" | cut -d: -f2 | cut -c1-5 | tr '\n' ' ' | grep -qx 'alpha bravo '" _ "${out}"
fa="$(frame_of alpha "${out}")"; fb="$(frame_of bravo "${out}")"
check "with no height set, alpha's frame runs past 20 lines" test "$(wc -l <<< "${fa}")" -gt 20
check "alpha's frame lists alpha's epic" has epic-of-alpha "${fa}"
check "alpha's frame does not list bravo's" lacks epic-of-bravo "${fa}"
check "bravo's frame lists bravo's epic" has epic-of-bravo "${fb}"
check "bravo's frame does not list alpha's" lacks epic-of-alpha "${fb}"
check "the legend is drawn once, under the last project" test "$(grep -c '● working' <<< "${out}")" -eq 1
check "the legend is under bravo's frame" has "● working" "${fb}"

# A bad project stops dash before it draws anything, naming the project.
rc=0; out="$(dash --project "${A}" --project /nonexistent 2> "${ROOT}/err")" || rc=$?
check "a missing project exits non-zero" test "${rc}" -ne 0
check "the error names /nonexistent" grep -qF /nonexistent "${ROOT}/err"
check "no frame is drawn for alpha" test -z "${out}"
mkdir -p "${ROOT}/noboard/.claude/swarm"
rc=0; out="$(dash --project "${ROOT}/noboard" --project "${A}" 2> "${ROOT}/err")" || rc=$?
check "a project with no board exits non-zero, naming it" bash -c "[ ${rc} -ne 0 ] && grep -qF '${ROOT}/noboard' '${ROOT}/err'"
check "no frame is drawn after a project with no board" test -z "${out}"
# A board where the default board_dir puts it, but no .claude/swarm/config: not a swarm project.
mkdir -p "${ROOT}/noconfig/docs/stories"; echo "# Stories" > "${ROOT}/noconfig/docs/stories/README.md"
rc=0; out="$(dash --project "${A}" --project "${ROOT}/noconfig" 2> "${ROOT}/err")" || rc=$?
check "a project with no config exits non-zero, naming it" bash -c "[ ${rc} -ne 0 ] && grep -qF '${ROOT}/noconfig' '${ROOT}/err'"
check "no frame is drawn for a project with no config" test -z "${out}"

# Each frame gets its share of the height; colour follows DASH_COLOR off a terminal.
out="$(DASH_H=40 dash --project "${A}" --project "${B}")"
check "with DASH_H=40, alpha's frame is at most 20 lines" test "$(frame_of alpha "${out}" | wc -l)" -le 20
check "with DASH_H=40, bravo's frame is at most 20 lines" test "$(frame_of bravo "${out}" | wc -l)" -le 20
check "both frames are drawn with DASH_H=40" bash -c "[ -n \"\$1\" ] && [ -n \"\$2\" ]" _ "$(frame_of alpha "${out}")" "$(frame_of bravo "${out}")"
out="$(DASH_H=1 dash --project "${A}" --project "${B}")"
check "with fewer lines than projects (DASH_H=1), the frames fit the 1 line" test "$(wc -l <<< "${out}")" -le 1
check "with DASH_H=1, the line drawn is alpha's header" grep -q '^alpha  swarm-dev ' <<< "${out}"
# Three lines each: every share starts with its project's header, and the legend shows once.
out="$(DASH_H=6 dash --project "${A}" --project "${B}")"
check "with DASH_H=6, the frames fit 6 lines" test "$(wc -l <<< "${out}")" -le 6
check "with DASH_H=6, alpha's share starts with its header" grep -q '^alpha  swarm-dev ' <<< "$(sed -n 1p <<< "${out}")"
check "with DASH_H=6, bravo's share starts with its header" grep -q '^bravo  swarm-dev ' <<< "$(sed -n 4p <<< "${out}")"
check "with DASH_H=6, the legend shows at most once" test "$(grep -c '● working' <<< "${out}")" -le 1
# Two lines each: bravo's legend alone would fill its share, and its header still comes first.
out="$(DASH_H=4 dash --project "${A}" --project "${B}")"
check "with DASH_H=4, bravo's share starts with its header, ahead of the legend" grep -q '^bravo  swarm-dev ' <<< "$(sed -n 3p <<< "${out}")"
# A height measured off a terminal (LINES here; /dev/tty for a real one) is not shared out: a
# one-shot dash into a file or a pager is never cut.
out="$(LINES=10 dash --project "${A}" --project "${B}")"
check "off a terminal, a measured height does not cut alpha's frame" test "$(frame_of alpha "${out}" | wc -l)" -gt 20
check "off a terminal, a measured height still draws bravo's frame" grep -q '^bravo  swarm-dev ' <<< "${out}"
esc=$'\033['
out="$(DASH_COLOR=1 dash --project "${A}" --project "${B}")"
check "with DASH_COLOR set, the frames carry colour codes" has "${esc}" "${out}"
out="$(dash --project "${A}" --project "${B}")"
check "without DASH_COLOR, no colour codes" lacks "${esc}" "${out}"

# --watch off a terminal: a change to bravo's board prints both projects' frames on that tick.
(cd "${G}" && exec env -u HERDR_ENV "${SWARM}" dash --watch 1 --project "${A}" --project "${B}" > "${ROOT}/watch.out" 2>&1) &
pids+=("$!")
within() { # <seconds> <test...>: true once the test passes, checked every 0.2 seconds
  local n=$(($1 * 5)); shift
  while ((n-- > 0)); do "$@" && return 0; sleep 0.2; done
  return 1
}
check "the watch draws its first tick" within 15 grep -q '^bravo  swarm-dev ' "${ROOT}/watch.out"
printf -- '---\nstatus: active\n---\n\n# %s\n' late-epic-of-bravo > "${B}/board/epics/late-epic-of-bravo.md"
check "bravo's change shows within 15s" within 15 grep -qF late-epic-of-bravo "${ROOT}/watch.out"
sleep 1
last="$(awk '/^alpha  swarm-dev / { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "${ROOT}/watch.out")"
check "the changed tick draws alpha's frame" test "$(grep -c '^alpha  swarm-dev ' "${ROOT}/watch.out")" -ge 2
check "the changed tick draws bravo's frame after alpha's" grep -q '^bravo  swarm-dev ' <<< "${last}"
check "the changed tick's bravo frame shows the change" has late-epic-of-bravo "${last}"
check "the changed tick's alpha frame lists alpha's epic" has epic-of-alpha "${last}"

if [ "${fails}" -gt 0 ]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
