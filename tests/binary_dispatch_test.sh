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
# of that name in the cwd, as binary_find checked it, not one found on PATH. With no binary to run, the
# command dies with binary_find's line, which is its events.tsv outcome too. Both stub logs stay empty.
# Two forms: wrapper-fixture's Go form gets exactly its arguments, and its bash forms (a first argument
# name or board-rel) reach the _name and _board-rel arms through the bridge (cmd/swarm/bridge.go), from
# a binary run in a cwd outside the project, and print and exit as those arms do run directly, usage
# errors included. Bash runs the binary's _wrapper-fixture entry as it runs its own _ arms, with its
# arguments, and with herdr's socket and a herdr stub present it labels no workspace, which
# wrapper-fixture does.
# The installed copy: with SWARMDEV_BIN unset, the copy's own <copy>/swarm (BINARY_BUILD_PATH), a wrapper
# that logs its arguments and then runs make test's binary, is what binary_ensure exports. swarm.sh
# _trusted <plain folder>, a command with no marker, then starts the binary once per call as
# `_require-trusted <folder> <CLAUDE_CONFIG_DIR>/.claude.json ''` (require_trusted's helper entry), and
# prints trusted for a folder .claude.json trusts and require_trusted's die line for one it does not.
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
# A Unix socket path has a short limit (104 bytes on macOS), so herdr's stand-in socket gets a short dir.
sock_dir="$(mktemp -d /tmp/swarm-bd.XXXXXX)" || { echo "mktemp -d failed" >&2; rm -rf "${ROOT}"; exit 1; }
trap 'rm -rf "${ROOT}" "${sock_dir}"' EXIT
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
# hooks/ too: lead-session.sh's lead_project is what lets a command label the lead's workspace.
cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/hooks" "${T}/"
mkdir -p "${T}/bin/ported/sub"
: > "${T}/bin/ported/wrapper-fixture"; : > "${T}/bin/ported/sub/wrapper-fixture"; : > "${T}/bin/ported/.hidden"
: > "${T}/bin/ported/_wrapper-fixture"
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
     "${BASH}" "${tree}/bin/swarm.sh" "$@") < "${ROOT}/stdin" > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
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

# No binary to run: the command dies with binary_find's line, on stderr and as its events.tsv outcome.
n="$(events)"
sw "${T}" "SWARMDEV_BIN=${ROOT}/none" -- wrapper-fixture t8
check "no binary: fails" 1 "${rc}"
check "no binary: says binary_find's line" "swarm: binary: SWARMDEV_BIN names '${ROOT}/none', which is not a file" "${err}"
check "no binary: the line is the outcome" "$((n + 1))|t8|binary: SWARMDEV_BIN names '${ROOT}/none', which is not a file" \
  "$(events)|$(last_event 3)|$(last_event out)"

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

# Two forms. The Go form gets exactly its arguments, an empty last one too.
sw "${T}" -- wrapper-fixture a 'b c' ''
check "the Go form: exits 0" 0 "${rc}"
check "the Go form: exactly its arguments, in order" "arg = a|arg = b c|arg = " "$(grep '^arg = ' <<< "${out}" | paste -sd '|' -)"
# The bash forms run from a binary whose cwd is outside the project, so only the bridge's SWARM_PROJECT
# finds it.
AWAY="${ROOT}/away"; mkdir -p "${AWAY}"
WRAP_AWAY="${ROOT}/wrap/swarm-away"
printf '#!/bin/sh
cd "%s" || exit 1
exec "%s" "$@"
' "${AWAY}" "${REAL_BIN}" > "${WRAP_AWAY}"; chmod +x "${WRAP_AWAY}"
# bash_form <name> <label> [args] — run wrapper-fixture's <name> form through the bridge and the _<name>
# arm directly with the same args, and check both print and exit alike.
bash_form() {
  local name="$1" label="$2" via_out via_err via_rc; shift 2
  sw "${T}" "SWARMDEV_BIN=${WRAP_AWAY}" -- wrapper-fixture "${name}" "$@"
  via_out="${out}"; via_err="${err}"; via_rc="${rc}"
  sw "${T}" -- "_${name}" "$@"
  check "the bash form ${label}: prints what _${name} prints" "${out}" "${via_out}"
  check "the bash form ${label}: says what _${name} says on stderr" "${err}" "${via_err}"
  check "the bash form ${label}: exits as _${name} does" "${rc}" "${via_rc}"
}
bash_form name "name 'Some Slug!'" 'Some Slug!'
check "_name 'Some Slug!' run directly: the agent name, exit 0" "some-slug-|0" "${out}|${rc}"
bash_form board-rel "board-rel x 'y z'" x 'y z'
check "_board-rel run directly: the board's path from the project, exit 0" "board/|0" "${out}|${rc}"
# Usage errors: the Go form's line and exit 2, and the bash arm's message and code, unchanged.
sw "${T}" -- wrapper-fixture --fail
check "the Go form's usage error: its line and exit 2" "swarm: wrapper-fixture: --fail takes a value|2" "${err}|${rc}"
bash_form name "name with no slug"
check "_name with no slug run directly: bash's message for \${1:?slug}, exit 1" "yes|1" \
  "$([[ "${err}" == *"${T}/bin/swarm.sh: line "*": 1: slug" ]] && echo yes || echo "no: ${err}")|${rc}"

# Bash runs the binary's _ entry as it runs its own _ arms. herdr's socket and a herdr stub that logs
# each call are there, so a command that labels the lead's workspace calls herdr; _wrapper-fixture must not.
SOCK="${sock_dir}/h.sock"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "${SOCK}"
printf '#!/bin/sh
echo "$*" >> "%s/herdr"
exit 1
' "${LOGS}" > "${STUBS}/herdr"; chmod +x "${STUBS}/herdr"
herdr_env=(HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t0 "HERDR_SOCKET_PATH=${SOCK}")
sw "${T}" "${herdr_env[@]}" -- _wrapper-fixture a 'b c'
check "_wrapper-fixture: exits 0" 0 "${rc}"
check "_wrapper-fixture: the binary got exactly its two arguments" "arg = a|arg = b c" "$(grep '^arg = ' <<< "${out}" | paste -sd '|' -)"
check "_wrapper-fixture: no herdr call, so no workspace label" "" "$(cat "${LOGS}/herdr" 2>/dev/null || true)"
# The positive control: wrapper-fixture, with no _, labels the workspace, which calls herdr.
sw "${T}" "${herdr_env[@]}" -- wrapper-fixture c1
check "the control: wrapper-fixture calls herdr to label the workspace" yes \
  "$([[ -s "${LOGS}/herdr" ]] && echo yes || echo no)"
rm -f "${STUBS}/herdr"

# The installed copy: SWARMDEV_BIN unset, so binary_ensure finds the copy's own binary at <copy>/swarm,
# here a wrapper that logs its arguments, one start a line, then runs make test's binary. _trusted has
# no marker: its bash runs require_trusted, which starts the binary's _require-trusted entry.
# shellcheck disable=SC2016 # the $ names are the wrapper script's own
printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done >> "%s/installed"\necho >> "%s/installed"\nexec "%s" "$@"\n' \
  "${LOGS}" "${LOGS}" "${REAL_BIN}" > "${T}/swarm"; chmod +x "${T}/swarm"
check "the installed copy: _trusted has no marker" no "$([[ -e "${T}/bin/ported/_trusted" ]] && echo yes || echo no)"
PLAIN="${ROOT}/plain"; mkdir -p "${PLAIN}" "${ROOT}/trust-config"
TRUST_CFG="${ROOT}/trust-config/.claude.json"
check "the installed copy: the plain folder is outside git" no \
  "$(git -C "${PLAIN}" rev-parse --show-toplevel >/dev/null 2>&1 && echo yes || echo no)"
# installed <folder> — run the copy's swarm.sh _trusted <folder> from the project, with SWARMDEV_BIN unset.
installed() {
  rc=0
  (cd "${P}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN PATH="${STUBS}:${PATH}" CLAUDE_CONFIG_DIR="${ROOT}/trust-config" \
     "${BASH}" "${T}/bin/swarm.sh" _trusted "$1") < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}' "${PLAIN}" > "${TRUST_CFG}"
installed "${PLAIN}"
check "the installed copy, a trusted folder: prints trusted, exit 0, nothing on stderr" "trusted|0|" "${out}|${rc}|${err}"
printf '{"projects": {}}' > "${TRUST_CFG}"
installed "${PLAIN}"
check "the installed copy, an untrusted folder: require_trusted's die line, exit 1" \
  "|1|swarm: Claude Code does not trust ${PLAIN} yet, so the agent would stall on its trust prompt. Run claude in ${PLAIN} once, accept the prompt, then try again." \
  "${out}|${rc}|${err}"
check "the installed copy: one _require-trusted start per call, with the folder, the config and an empty third argument" \
  "[_require-trusted][${PLAIN}][${TRUST_CFG}][]|[_require-trusted][${PLAIN}][${TRUST_CFG}][]" \
  "$(paste -sd '|' - < "${LOGS}/installed" 2>/dev/null || true)"
rm -f "${T}/swarm"

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
