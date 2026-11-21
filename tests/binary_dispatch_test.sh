#!/usr/bin/env bash
# binary_dispatch_test.sh — bin/swarm.sh's dispatch runs the binary for a command with a marker
# bin/ported/<name> (is_ported, binary_run in bin/lib/binary.sh), inside the bash frame. It runs swarm.sh
# from a copy of the plugin with no .git, holding the marker bin/ported/wrapper-fixture, with SWARMDEV_BIN
# naming a wrapper that logs each start and then runs make test's binary, and gh and go stubs first on
# PATH that log any call and exit 1. From a project whose config sets board_dir and two other keys,
# wrapper-fixture prints the project and the board, stdin, and each key's value and source as
# `swarm.sh config` gives them. Its failure line and exit code, or with no line 'failed (exit <n>)', and
# the fields it writes reach the command's events.tsv line, as a bash command's die and event_fields do.
# SWARM_FORBID_PROJECT naming the project refuses it before the binary starts. A name holding / or a
# leading ., and a name with no marker, never start the binary. A caller's SWARMDEV_DIE_FILE,
# SWARMDEV_FIELDS_FILE and SWARMDEV_CFG_ names never reach it, a logged command's or a read-only one's
# (a second copy whose READ_ONLY_COMMANDS names wrapper-fixture). SWARMDEV_BIN a bare name runs the file
# of that name in the cwd, as binary_find checked it, not one found on PATH. Both stub logs stay empty.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
  echo "FAIL SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
  exit 1
fi
REAL_BIN="${SWARMDEV_BIN}"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

STUBS="${ROOT}/stubs"; LOGS="${ROOT}/logs"; mkdir -p "${STUBS}" "${LOGS}"
for s in gh go; do
  printf '#!/bin/sh\necho "$*" >> "%s/%s"\nexit 1\n' "${LOGS}" "${s}" > "${STUBS}/${s}"
  chmod +x "${STUBS}/${s}"
done
# The binary every run is handed: a wrapper that logs a start, then runs make test's binary.
WRAP="${ROOT}/wrap/swarm"; mkdir -p "${ROOT}/wrap"
printf '#!/bin/sh\necho start >> "%s/wrap"\nexec "%s" "$@"\n' "${LOGS}" "${REAL_BIN}" > "${WRAP}"; chmod +x "${WRAP}"

# The plugin copy, with no .git, and the fixture's marker. A file bin/ported/sub/wrapper-fixture and a
# marker .hidden, which a name holding / or a leading . would reach were it not refused.
T="${ROOT}/tree"; mkdir -p "${T}"
cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${T}/"
mkdir -p "${T}/bin/ported/sub"
: > "${T}/bin/ported/wrapper-fixture"; : > "${T}/bin/ported/sub/wrapper-fixture"; : > "${T}/bin/ported/.hidden"
check "the copy has no .git" no "$([[ -e "${T}/.git" ]] && echo yes || echo no)"
# The same copy, but with wrapper-fixture read-only, so main runs it with no die file of its own.
T2="${ROOT}/tree-ro"; cp -R "${T}" "${T2}"
perl -pi -e 's/^READ_ONLY_COMMANDS="/READ_ONLY_COMMANDS="wrapper-fixture /' "${T2}/bin/swarm.sh"
check "the read-only copy's READ_ONLY_COMMANDS names wrapper-fixture" 1 \
  "$(grep -c '^READ_ONLY_COMMANDS="wrapper-fixture ' "${T2}/bin/swarm.sh" || true)"

# The project: not a git repo, with board_dir and two other keys set.
P="${ROOT}/proj"; mkdir -p "${P}/.claude/swarm" "${P}/board"
printf 'board_dir = board\nmerge = agent\nstall_minutes = 45\n' > "${P}/.claude/swarm/config"
EVENTS="${P}/.swarm/events.tsv"

# sw <tree> [NAME=value...] -- <swarm args...> — run <tree>'s swarm.sh from the project, stdin from
# ${ROOT}/stdin, with the stubs first on PATH and SWARMDEV_BIN the wrapper. Sets out, err and rc.
sw() {
  local tree="$1" envs=(); shift
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done; shift
  rc=0
  (cd "${P}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT PATH="${STUBS}:${PATH}" SWARMDEV_BIN="${WRAP}" ${envs[@]+"${envs[@]}"} \
     bash "${tree}/bin/swarm.sh" "$@") < "${ROOT}/stdin" > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
# starts, events — how many starts the wrapper logged, and how many events.tsv lines; 0 when no file yet.
starts() { if [[ -f "${LOGS}/wrap" ]]; then grep -c '' "${LOGS}/wrap"; else echo 0; fi; }
events() { if [[ -f "${EVENTS}" ]]; then grep -c '' "${EVENTS}"; else echo 0; fi; }
# last_event <field> — the last events.tsv line's command (2), target (3), or its outcome's text (out)
# and tail (tail), split at agents.sh's EVENT_SEP.
last_event() {
  local c t o
  IFS=$'\t' read -r _ c t _ o <<< "$(tail -1 "${EVENTS}")"
  case "$1" in 2) echo "${c}" ;; 3) echo "${t}" ;; out) echo "${o%% ~~ *}" ;; tail) echo "${o#* ~~ }" ;; esac
}
: > "${ROOT}/stdin"

# The frame, as swarm.sh config gives it.
sw "${T}" -- config; config="${out}"
sw "${T}" -- config board_dir; board="${out}"
check "config reads the project's board" "${P}/board" "${board}"
printf 'one\ntwo words\n' > "${ROOT}/stdin"
sw "${T}" -- wrapper-fixture t1
: > "${ROOT}/stdin"
check "wrapper-fixture: exits 0" 0 "${rc}"
check "wrapper-fixture: says nothing on stderr" "" "${err}"
check "wrapper-fixture: the wrapper logged one start" 1 "$(starts)"
check "wrapper-fixture: the project, as config gives it" "$(grep '^project = ' <<< "${config}")" "$(grep '^project = ' <<< "${out}")"
check "wrapper-fixture: the board, as config board_dir gives it" "board = ${board}" "$(grep '^board = ' <<< "${out}")"
check "wrapper-fixture: the plugin root it runs from" "home = ${T}" "$(grep '^home = ' <<< "${out}")"
check "wrapper-fixture: its argument" "arg = t1" "$(grep '^arg = ' <<< "${out}")"
check "wrapper-fixture: stdin, line by line" "stdin = one|stdin = two words" "$(grep '^stdin = ' <<< "${out}" | paste -sd '|' -)"
settings="$(grep -Ev '^(project|board|home|arg|stdin) = ' <<< "${out}")"
check "wrapper-fixture: each key's value and source, as config gives them" \
  "$(grep -v '^project = ' <<< "${config}" | LC_ALL=C sort)" "$(LC_ALL=C sort <<< "${settings}")"
check "wrapper-fixture: the config's own lines are among them" 3 "$(grep -c "(${P}/.claude/swarm/config:[123])\$" <<< "${settings}" || true)"
check "wrapper-fixture: logged as a command, ok" "wrapper-fixture|t1|ok" "$(last_event 2)|$(last_event 3)|$(last_event out)"

# A failure with a line, and fields: the line is the outcome, and the fields follow it.
n="$(events)"
sw "${T}" -- wrapper-fixture t2 --field k=v --field two=a_b --fail 3 --line "it broke here"
check "a failure with a line: exits 3" 3 "${rc}"
check "a failure with a line: one events.tsv line" $((n + 1)) "$(events)"
check "a failure with a line: the line is the outcome" "wrapper-fixture|t2|it broke here" "$(last_event 2)|$(last_event 3)|$(last_event out)"
check "a failure with a line: the fields reach the line" "k=v two=a_b" "$(last_event tail | sed 's/ version=.*//')"
sw "${T}" -- wrapper-fixture t3 --fail 3
check "a failure with no line: exits 3" 3 "${rc}"
check "a failure with no line: the outcome says the exit code" "t3|failed (exit 3)" "$(last_event 3)|$(last_event out)"

# SWARM_FORBID_PROJECT naming the project: refused before the binary starts.
was="$(starts)"
sw "${T}" "SWARM_FORBID_PROJECT=${P}" -- wrapper-fixture t4
check "forbidden project: fails" 1 "${rc}"
check "forbidden project: says the refusal" yes "$([[ "${err}" == "swarm: SWARM_FORBID_PROJECT: ${P} is the checkout the tests run from"* ]] && echo yes || echo "no: ${err}")"
check "forbidden project: the binary never started" "${was}" "$(starts)"

# A name that reaches a marker only through a / or a leading ., or that has no marker, never starts it.
check "../ported/wrapper-fixture reaches a marker file" yes "$([[ -f "${T}/bin/ported/../ported/wrapper-fixture" ]] && echo yes)"
for name in ../ported/wrapper-fixture sub/wrapper-fixture .hidden no-marker; do
  was="$(starts)"
  sw "${T}" -- "${name}"
  check "name ${name}: the binary never started" "${was}" "$(starts)"
  check "name ${name}: falls to the usage text and exit 2" 2 "${rc}"
done

# SWARMDEV_BIN a bare name: the file binary_find checked in the cwd runs, not a namesake on PATH.
printf '#!/bin/sh\necho start >> "%s/local"\nexec "%s" "$@"\n' "${LOGS}" "${REAL_BIN}" > "${P}/swarm"; chmod +x "${P}/swarm"
printf '#!/bin/sh\necho start >> "%s/decoy"\nexit 1\n' "${LOGS}" > "${STUBS}/swarm"; chmod +x "${STUBS}/swarm"
sw "${T}" SWARMDEV_BIN=swarm -- wrapper-fixture t7
check "SWARMDEV_BIN a bare name: exits 0" 0 "${rc}"
check "SWARMDEV_BIN a bare name: the cwd's file ran, and the PATH one did not" "start|" \
  "$(cat "${LOGS}/local" 2>/dev/null || true)|$(cat "${LOGS}/decoy" 2>/dev/null || true)"
rm -f "${P}/swarm" "${STUBS}/swarm"

# A caller's SWARMDEV_ names: its die file and fields file stay as they were, and its settings never
# reach the binary, whether main logs the command or not.
printf 'kept\n' > "${ROOT}/die"; printf 'kept=1\n' > "${ROOT}/fields"
inherited=("SWARMDEV_DIE_FILE=${ROOT}/die" "SWARMDEV_FIELDS_FILE=${ROOT}/fields" SWARMDEV_CFG_stray=x SWARMDEV_SRC_stray=x
  SWARMDEV_CFG_merge=stale SWARMDEV_SRC_merge=stale)
n="$(events)"
sw "${T}" "${inherited[@]}" -- wrapper-fixture t5 --field k=v --fail 3 --line "logged line"
check "inherited, logged: exits 3" 3 "${rc}"
check "inherited, logged: the line goes to events.tsv" "$((n + 1))|t5|logged line" "$(events)|$(last_event 3)|$(last_event out)"
check "inherited, logged: the caller's die file is as it was" kept "$(cat "${ROOT}/die")"
check "inherited, logged: the caller's fields file is as it was" kept=1 "$(cat "${ROOT}/fields")"
check "inherited, logged: no stray setting reaches the binary" "" "$(grep 'stray' <<< "${out}" || true)"
check "inherited, logged: merge is the config's" "$(grep '^merge = ' <<< "${config}")" "$(grep '^merge = ' <<< "${out}")"
n="$(events)"
sw "${T2}" "${inherited[@]}" -- wrapper-fixture t6 --field k=v --fail 3 --line "read-only line"
check "inherited, read-only: exits 3" 3 "${rc}"
check "inherited, read-only: nothing logged" "${n}" "$(events)"
check "inherited, read-only: the caller's die file is as it was" kept "$(cat "${ROOT}/die")"
check "inherited, read-only: the caller's fields file is as it was" kept=1 "$(cat "${ROOT}/fields")"

# Every run above had only the stubs for gh and go.
for s in gh go; do
  check "no run called ${s}" "" "$(cat "${LOGS}/${s}" 2>/dev/null || true)"
done
# A positive control: the stubs log a call made through the PATH the runs had.
for s in gh go; do
  PATH="${STUBS}:${PATH}" "${s}" control >/dev/null 2>&1 || true
  check "the ${s} stub logs a call" control "$(cat "${LOGS}/${s}" 2>/dev/null || true)"
done

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
