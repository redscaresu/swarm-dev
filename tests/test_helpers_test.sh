#!/usr/bin/env bash
# test_helpers_test.sh — tests/test_helpers.sh's stop_test_group, which the EXIT trap of every test
# that starts a background process runs before its rm -rf. A fixture test, started as the leader of a
# process group of its own as make test starts each file, leaves a sleeping child and a sleeping
# grandchild re-parented to init behind it; once its EXIT trap has run, its group has no process
# left, and the trap has run to its end. Run from a shell that leads no group, it stops
# nothing, and run by hand at the head of a pipe, it spares the pipe's other end, which is the caller's.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# Every group a case starts is recorded, so a failed case leaves none running.
trap 'stop_groups "${ROOT}/groups"; stop_test_group; rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# The fixture <dir>: what a test that starts background processes does. It writes its pid, then each
# process's, into <dir>, says whether the grandchild has left it (re-parented), and exits; its EXIT
# trap stops its group and says it ran.
FX="${ROOT}/fixture_test.sh"
cat > "${FX}" <<FIXTURE
set -euo pipefail
source "${REPO}/tests/test_helpers.sh"
d="\$1"; echo "\$\$" > "\${d}/self"
trap 'stop_test_group; echo trap-done' EXIT
sleep 300 > /dev/null 2>&1 & echo "\$!" > "\${d}/child"
( sleep 300 > /dev/null 2>&1 & echo "\$!" > "\${d}/orphan" )
[[ "\$(ps -o ppid= -p "\$(cat "\${d}/orphan")" | tr -d ' ')" != "\$\$" ]] && echo reparented > "\${d}/state"
FIXTURE

# running <pid> — <pid> runs and is no zombie.
running() { local st; st="$(ps -o stat= -p "$1" 2>/dev/null || true)"; st="${st// /}"; [[ -n "${st}" && "${st}" != Z* ]]; }
# alive <file>... — the pid in each file that still runs, or nothing.
alive() { local f p; for f in "$@"; do p="$(cat "${f}" 2>/dev/null)" || continue; ! running "${p}" || echo "${p}"; done; }
# members <pgid> — the processes in group <pgid> that still run, or nothing.
members() { local p; for p in $(pgrep -g "$1" || true); do ! running "${p}" || echo "${p}"; done; }
# reap <pid> — wait for this shell's child <pid> for up to 30 s, so a case that hangs fails, not the file.
reap() {
  local i
  for ((i = 0; i < 300; i++)); do kill -0 "$1" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$1" 2>/dev/null; then echo "still running after 30 s"; return 0; fi
  { wait "$1"; } 2>/dev/null || true
}

# --- The fixture leads a group of its own, as under make test: once its trap has run, nothing of its
# group is left, the re-parented grandchild among them, and the trap, which spared its own shell, ran on.
A="${ROOT}/a"; mkdir -p "${A}"
(in_new_group bash "${FX}" "${A}" > "${A}/out" 2>&1) &
g=$!; group_record "${g}" "${ROOT}/groups"
check "the fixture ends" "$(reap "${g}")" ""
check "the fixture's grandchild was re-parented before the trap ran" "$(cat "${A}/state" 2>/dev/null)" "reparented"
check "a test leading its own group leaves no process in it after its EXIT trap" "$(members "${g}")" ""
check "and neither its sleeping child nor its re-parented grandchild runs" "$(alive "${A}/child" "${A}/orphan")" ""
check "and the trap ran to its end" "$(cat "${A}/out")" "trap-done"
stop_group "${g}" "${ROOT}/groups" || true

# --- Run from a shell whose group it does not lead, the fixture's group is $$, which has no member:
# it stops nothing, so its own child, the group's leader (the caller) and the caller's sleep run on.
B="${ROOT}/b"; mkdir -p "${B}"
# shellcheck disable=SC2016 # expanded by the inner bash
(in_new_group bash -c 'sleep 300 & s=$!; bash "$1" "$2" > "$2/out" 2>&1; kill -0 "${s}" && echo caller-alive' _ "${FX}" "${B}" > "${B}/caller" 2>&1) &
g=$!; group_record "${g}" "${ROOT}/groups"
check "the caller ends" "$(reap "${g}")" ""
check "a test that leads no group stops nothing: its own sleeping child runs on" "$(alive "${B}/child")" "$(cat "${B}/child" 2>/dev/null)"
check "and neither does its caller, the group's leader, nor the caller's sleep" "$(cat "${B}/caller")" "caller-alive"
stop_group "${g}" "${ROOT}/groups" || true

# --- Run by hand at the head of a pipe (bash tests/x.sh | cat), the cat is in the fixture's group,
# with the fixture's parent as its parent: it is spared, and reads the trap's last line.
C="${ROOT}/c"; mkdir -p "${C}"
# A job of a set -m shell leads a group of its own, the pipe's first process its leader; in the
# background, so it never asks for the terminal.
# shellcheck disable=SC2030,SC2031 # c is the subshell's own
(set -m; bash "${FX}" "${C}" 2>&1 | cat > "${C}/out" & c=$!; r=0; wait "${c}" || r=$?; echo "cat=${r}" > "${C}/rc") &
s=$!
for ((i = 0; i < 100; i++)); do [[ ! -s "${C}/self" ]] || break; sleep 0.05; done
[[ ! -s "${C}/self" ]] || group_record "$(cat "${C}/self")" "${ROOT}/groups" || true
check "the pipe ends" "$(reap "${s}")" ""
check "a test at the head of a pipe spares the pipe's other end, which reads the trap's last line" "$(cat "${C}/out" 2>/dev/null)|$(cat "${C}/rc" 2>/dev/null)" "trap-done|cat=0"
check "and leaves no process of its own" "$(alive "${C}/child" "${C}/orphan")" ""

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
