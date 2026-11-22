#!/usr/bin/env bash
# binary_fetch_test.sh — an installed copy of the plugin (no .git) with no binary and SWARMDEV_BIN unset
# fetches its binary on the first swarm.sh call but update, checks it, installs it as
# <copy>/swarm and exports SWARMDEV_BIN naming it (binary_ensure and binary_fetch in bin/lib/binary.sh).
# Each case runs a no-.git copy's swarm.sh from a project, with the stubs of tests/binary_fetch_stubs.sh
# first on PATH, logging wrappers for sha256sum, shasum and git, and go a stub that logs and fails.
#   The first call: gh logs --version, then the release download (github.com, this version's tag, this
#     platform's asset and SHA256SUMS, into <copy>/.fetch-<pid>), then the attestation of that file with
#     release.yml as signer, and no other call. <copy>/swarm is executable and cmp-equal to the fake release, config's output follows, no
#     .fetch-* folder is left, and git, which find_project runs, sees SWARMDEV_BIN=<copy>/swarm.
#   A second call starts no gh, uname, shasum or sha256sum, and leaves <copy>/swarm's inode and mtime.
#   _wrapper-fixture fetches, then prints its two arguments and the frame's project.
#   A copy whose scripts/build.sh --list names another signer: the attestation call carries it.
#   A wrong checksum, and a failing attestation: exit 1, one stderr line, no stdout, no <copy>/swarm and
#     no .fetch-* folder, with bin/ported/config present.
#   Two calls whose gh downloads meet at a rendezvous before either publishes: both exit 0.
#   Two calls whose second mv onto <copy>/swarm is held: meanwhile <copy>/swarm runs, and the held mv's
#     source is an executable copy of the release in a .fetch-* folder.
#   This version's gh-shim and an older one first on PATH, each a failing stub: neither is run, and the
#     gh stub logs each call once. With real shims there, the fetch ends within TIME_BOUND.
#   A TERM to swarm.sh mid-download, and an INT to its whole group as Ctrl-C sends it: within 5 s no gh
#     process is left, no .fetch-* folder and no <copy>/swarm, and the call exits non-zero. A KILL to its
#     group then: no <copy>/swarm, a folder that holds no executable file, and the next call fetches.
#   update, with a claude stub: no gh call and no <copy>/swarm.
# Synchronisation is by fifos the test holds open read-write, so a stub's write never blocks, read with
# a timeout (WAIT_S); nothing sleeps to wait for a step. Only the 5 s deadlines poll.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/binary_fetch_stubs.sh
source "$(dirname "${BASH_SOURCE[0]}")/binary_fetch_stubs.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
  echo "FAIL SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
  exit 1
fi
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'stop_groups "${ROOT}/groups"; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

HOST=ghe.example.com   # GH_HOST, which the fetch must not follow
SUMS=SHA256SUMS
SIGNER_WANT="github.com/${FETCH_REPO}/${FETCH_SIGNER}"
WAIT_S=60       # how long a read on a fifo waits for a stub
TIME_BOUND=60   # how long a call through real gh-shims may take
VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${REPO}/.claude-plugin/plugin.json")"

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
lines() { # <text>: its number of lines, 0 for none
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}

case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[[ -n "${OS}" && -n "${ARCH}" ]] || { echo "FAIL this test runs on darwin or linux, amd64 or arm64"; exit 1; }
ASSET="swarm-${OS}-${ARCH}"

F="${ROOT}/fetch"; fetch_stubs "${F}" "${VERSION}" || exit 1
fetch_release "${F}" "${ASSET}" "${SUMS}" || exit 1
RELEASE="${F}/release/${ASSET}"
LOGS="${ROOT}/logs"; TOOLS="${ROOT}/tools"; mkdir -p "${LOGS}" "${TOOLS}"
# The sum programs and git: a wrapper that logs each start, then runs the real one. git's line is the
# SWARMDEV_BIN it sees. go: logs and fails, as no case here builds: each download works, or fails a
# check, which never builds.
for t in sha256sum shasum; do
  p="$(command -v "${t}")" || continue
  printf '#!/bin/sh\necho "%s $*" >> "%s/sum"\nexec "%s" "$@"\n' "${t}" "${LOGS}" "${p}" > "${TOOLS}/${t}"
done
REAL_GIT="$(command -v git)"
# shellcheck disable=SC2016 # the stub expands it
printf '#!/bin/sh\necho "SWARMDEV_BIN=${SWARMDEV_BIN-unset}" >> "%s/git"\nexec "%s" "$@"\n' "${LOGS}" "${REAL_GIT}" > "${TOOLS}/git"
printf '#!/bin/sh\necho "$*" >> "%s/go"\nexit 1\n' "${LOGS}" > "${TOOLS}/go"
chmod +x "${TOOLS}"/*
RUN_PATH="${F}/bin:${TOOLS}:${PATH}"
REAL_MV="$(command -v mv)"

# The project: not a git repo.
P="${ROOT}/proj"; mkdir -p "${P}/.claude/swarm"
printf 'board_dir = board\n' > "${P}/.claude/swarm/config"

# copy <dir> [marker...] — a copy of the plugin as an install leaves it: bin/, scripts/build.sh,
# .claude-plugin/, go.mod, cmd/ and internal/, with no .git; each marker an empty bin/ported/<name>.
copy() {
  local d="$1" m; shift
  mkdir -p "${d}/scripts"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "${REPO}/cmd" "${REPO}/internal" "${d}/"
  cp "${REPO}/scripts/build.sh" "${d}/scripts/"
  mkdir -p "${d}/bin/ported"
  for m in "$@"; do : > "${d}/bin/ported/${m}"; done
}
# sw <copy> [NAME=value...] -- <swarm args...> — run <copy>'s swarm.sh from the project, with PATH
# RUN_PATH (or a PATH= among the names), GH_HOST set and SWARMDEV_BIN unset. Sets out, err and rc.
sw() {
  local c="$1" envs=(); shift
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done; shift
  rc=0
  (cd "${P}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN GH_HOST="${HOST}" PATH="${RUN_PATH}" ${envs[@]+"${envs[@]}"} \
     bash "${c}/bin/swarm.sh" "$@") < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
# start <copy> <tag> [NAME=value...] -- <swarm args...> — sw in the background, as the leader of a group
# of its own (recorded for the EXIT trap), its output in ${ROOT}/<tag>.out, .err and, once it ends, .rc.
# A background job starts with INT and QUIT ignored, which swarm.sh could then not trap, so perl puts
# them back first, as a terminal's foreground job has them. Sets started_pid.
start() {
  local c="$1" tag="$2" envs=(); shift 2
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done; shift
  # shellcheck disable=SC2016 # perl's own variables
  (cd "${P}" || exit 1
   in_new_group perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec { $ARGV[0] } @ARGV or exit 127' -- \
     env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN GH_HOST="${HOST}" PATH="${RUN_PATH}" ${envs[@]+"${envs[@]}"} \
     bash "${c}/bin/swarm.sh" "$@") < /dev/null > "${ROOT}/${tag}.out" 2> "${ROOT}/${tag}.err" &
  started_pid=$!
  group_record "${started_pid}" "${ROOT}/groups"
}
# finish <pid> <tag> — wait for a start's call, and write its exit code to ${ROOT}/<tag>.rc.
finish() { local r=0; { wait "$1"; } 2>/dev/null || r=$?; echo "${r}" > "${ROOT}/$2.rc"; }
# log <name> — a stub's log since the last read, then emptied.
log() { local f="${LOGS}/$1"; [[ "$1" != gh && "$1" != uname ]] || f="${F}/log/$1"; cat "${f}" 2>/dev/null || true; rm -f "${f}"; }
clear_logs() { local n; for n in gh uname sum git go; do log "${n}" > /dev/null; done; }
# stamp <file> — its inode and its mtime to the nanosecond, or "none" when there is no file.
stamp() { if [[ -e "$1" ]]; then perl -MTime::HiRes=stat -e '@s = stat($ARGV[0]); printf "%d %.9f\n", $s[1], $s[9]' "$1"; else echo none; fi; }
# temps <copy> — the .fetch-* folders in <copy>, one a line.
temps() { (cd "$1" && find . -maxdepth 1 -name '.fetch-*' | sort); }
# installed <copy> — "executable, same" when <copy>/swarm is an executable file cmp-equal to the release.
installed() {
  local b="$1/swarm" x=not-executable s=differs
  [[ -e "${b}" ]] || { echo none; return; }
  [[ -f "${b}" && -x "${b}" ]] && x=executable
  cmp -s "${b}" "${RELEASE}" && s=same
  echo "${x}, ${s}"
}
# fetch_dir <gh log> — the folder of its release download line, when that is <copy>/.fetch-<digits>; else "".
fetch_dir() {
  local d
  d="$(sed -n 's/^.* release download .* --dir \(.*\)$/\1/p' <<< "$1" | head -1)"
  [[ "${d##*/.fetch-}" =~ ^[0-9]+$ && "${d}" == */.fetch-* ]] && echo "${d}"
}
# want_calls <dir> [signer] — the three gh lines a good fetch into <dir> logs.
want_calls() {
  printf 'GH_HOST=%s --version\n' "${HOST}"
  printf 'GH_HOST=%s release download v%s --repo github.com/%s --pattern %s --pattern %s --dir %s\n' \
    "${HOST}" "${VERSION}" "${FETCH_REPO}" "${ASSET}" "${SUMS}" "$1"
  printf 'GH_HOST=%s attestation verify %s/%s --hostname github.com --repo %s --signer-workflow %s' \
    "${HOST}" "$1" "${ASSET}" "${FETCH_REPO}" "${2:-${SIGNER_WANT}}"
}
# fifo <name> <fd> — a new fifo ${ROOT}/sync/<name>, held open read-write on <fd> by this shell.
mkdir -p "${ROOT}/sync"
fifo() { mkfifo "${ROOT}/sync/$1" && eval "exec $2<>\"\${ROOT}/sync/\$1\""; }

# The config output a call with nothing to fetch gives: SWARMDEV_BIN set, so binary_ensure does nothing.
C1="${ROOT}/c1"; copy "${C1}"
sw "${C1}" SWARMDEV_BIN="${SWARMDEV_BIN}" -- config; config="${out}"
check "the reference config: exits 0, says nothing on stderr" "0|" "${rc}|${err}"
check "the reference config: prints the project's board" yes "$(grep -q "^board_dir = ${P}/board " <<< "${config}" && echo yes || echo no)"
check "the reference config, SWARMDEV_BIN set: no gh call and no <copy>/swarm" "|none" "$(log gh)|$(installed "${C1}")"
clear_logs

# --- The first call.
sw "${C1}" -- config
calls="$(log gh)"; dir="$(fetch_dir "${calls}")" || dir=""
check "first call: exits 0 with config's output, nothing on stderr" "0|${config}|" "${rc}|${out}|${err}"
check "first call: the download went into <copy>/.fetch-<pid>" yes "$([[ -n "${dir}" && "${dir%/*}" == "${C1}" ]] && echo yes || echo "no: ${calls}")"
check "first call: gh logged --version, the download, then the attestation of that file with release.yml as signer" \
  "$(want_calls "${dir}")" "${calls}"
check "first call: <copy>/swarm is the release, executable" "executable, same" "$(installed "${C1}")"
check "first call: no .fetch-* folder is left" "" "$(temps "${C1}")"
git_seen="$(log git)"
check "first call: git, run after the fetch, sees SWARMDEV_BIN=<copy>/swarm on each of its calls" \
  "SWARMDEV_BIN=${C1}/swarm" "$(sort -u <<< "${git_seen}")"
check "first call: go was never run" "" "$(log go)"
log uname > /dev/null; log sum > /dev/null

# --- A second call checks nothing again.
before="$(stamp "${C1}/swarm")"
sw "${C1}" -- config
check "second call: exits 0 with config's output" "0|${config}|" "${rc}|${out}|${err}"
check "second call: no gh, uname, shasum or sha256sum start" "|||" "$(log gh)|$(log uname)|$(log sum)|"
check "second call: <copy>/swarm's inode and mtime are as they were" "${before}" "$(stamp "${C1}/swarm")"
check "second call: git still sees SWARMDEV_BIN=<copy>/swarm" "SWARMDEV_BIN=${C1}/swarm" "$(log git | sort -u)"

# --- A ported _ entry: fetched first, then run with the frame.
C2="${ROOT}/c2"; copy "${C2}" _wrapper-fixture
sw "${C2}" -- _wrapper-fixture a 'b c'
check "_wrapper-fixture: exits 0, nothing on stderr" "0|" "${rc}|${err}"
check "_wrapper-fixture: fetched first" yes "$([[ "$(log gh)" == *" release download "* ]] && echo yes || echo no)"
check "_wrapper-fixture: its two arguments" "arg = a|arg = b c" "$(grep '^arg = ' <<< "${out}" | paste -sd '|' -)"
check "_wrapper-fixture: the frame's project" "project = ${P}" "$(grep '^project = ' <<< "${out}")"
check "_wrapper-fixture: <copy>/swarm is the release" "executable, same" "$(installed "${C2}")"
clear_logs

# --- Another signer, as the copy's --list names it.
C3="${ROOT}/c3"; copy "${C3}"
OTHER=.github/workflows/other-release.yml
perl -pi -e 's{^SIGNER=.*}{SIGNER='"${OTHER}"'}' "${C3}/scripts/build.sh"
check "the signer copy's --list names the other signer" "signer	${OTHER}" "$(bash "${C3}/scripts/build.sh" --list | grep '^signer')"
printf '%s\n' "${OTHER}" > "${F}/stub/signer"
sw "${C3}" -- config
calls="$(log gh)"; dir="$(fetch_dir "${calls}")" || dir=""
check "another signer: exits 0 with config's output" "0|${config}|" "${rc}|${out}|${err}"
check "another signer: the attestation call carries it" "$(want_calls "${dir}" "github.com/${FETCH_REPO}/${OTHER}")" "${calls}"
printf '%s\n' "${FETCH_SIGNER}" > "${F}/stub/signer"
clear_logs

# fails_closed <name> <copy> — the checks a refused fetch must pass, config's marker present.
fails_closed() {
  check "$1: exits 1" 1 "${rc}"
  check "$1: exactly one stderr line" 1 "$(lines "${err}")"
  check "$1: nothing on stdout" "" "${out}"
  check "$1: no <copy>/swarm" none "$(installed "$2")"
  check "$1: no .fetch-* folder" "" "$(temps "$2")"
}
# --- A wrong checksum.
C4="${ROOT}/c4"; copy "${C4}" config
printf '%064d  %s\n' 0 "${ASSET}" > "${F}/release/${SUMS}"
sw "${C4}" -- config
fails_closed "a wrong checksum" "${C4}"
check "a wrong checksum: the line says so" yes "$([[ "${err}" == "binary: the SHA-256 of v${VERSION}'s ${ASSET} does not match"* ]] && echo yes || echo "no: ${err}")"
check "a wrong checksum: no attestation was asked for" 0 "$(grep -c ' attestation ' <<< "$(log gh)" || true)"
fetch_release "${F}" "${ASSET}" "${SUMS}"
# --- A failing attestation.
C5="${ROOT}/c5"; copy "${C5}" config
: > "${F}/stub/attest.fail"
sw "${C5}" -- config
fails_closed "a failing attestation" "${C5}"
check "a failing attestation: the line is binary_attest's" yes "$([[ "${err}" == "binary: gh attestation verify failed for ${C5}/.fetch-"*"/${ASSET}, so"* ]] && echo yes || echo "no: ${err}")"
check "a failing attestation: gh was asked for it" 1 "$(grep -c ' attestation verify ' <<< "$(log gh)" || true)"
rm -f "${F}/stub/attest.fail"
clear_logs

# --- Two calls whose downloads meet before either publishes. The gh wrapper serves the download, then
# announces itself on sync/arrive and waits on its own fifo until the test lets both go.
RV="${ROOT}/rv"; mkdir -p "${RV}"
# shellcheck disable=SC2016 # the stub expands its own
printf '#!/bin/sh\n"%s/bin/gh" "$@" || exit $?\n[ "$1 $2" = "release download" ] || exit 0\nmkfifo "%s/sync/go-$$" || exit 1\necho "$$" > "%s/sync/arrive"\nread -r _ < "%s/sync/go-$$"\n' \
  "${F}" "${ROOT}" "${ROOT}" "${ROOT}" > "${RV}/gh"; chmod +x "${RV}/gh"
fifo arrive 9
# wait_both — read two arrivals on sync/arrive (fd 9), each within WAIT_S, and set met to how many came.
# let_go — let each arrived download go on.
wait_both() {
  local g k; met=0; arrived=()
  for k in 1 2; do
    if read -r -t "${WAIT_S}" -u 9 g; then met=$((met + 1)); arrived+=("${g}"); fi
  done
}
let_go() { local g; for g in ${arrived[@]+"${arrived[@]}"}; do printf 'go\n' > "${ROOT}/sync/go-${g}"; done; }
C6="${ROOT}/c6"; copy "${C6}"
for k in 1 2; do start "${C6}" "rv${k}" PATH="${RV}:${RUN_PATH}" -- config; eval "rv_pid${k}=${started_pid}"; done
wait_both
check "rendezvous: both downloads arrived before either went on" 2 "${met}"
check "rendezvous: nothing is installed while both wait" none "$(installed "${C6}")"
let_go
for k in 1 2; do
  p="rv_pid${k}"
  [[ "${met}" -eq 2 ]] || stop_group "${!p}" "${ROOT}/groups" || true   # a call that never arrived is stuck
  finish "${!p}" "rv${k}"
done
for k in 1 2; do
  check "rendezvous, call ${k}: exits 0 with config's output" "0|${config}|" \
    "$(cat "${ROOT}/rv${k}.rc")|$(cat "${ROOT}/rv${k}.out")|$(cat "${ROOT}/rv${k}.err")"
done
check "rendezvous: <copy>/swarm is the release" "executable, same" "$(installed "${C6}")"
check "rendezvous: no .fetch-* folder is left" "" "$(temps "${C6}")"
clear_logs

# --- Two calls whose second mv onto <copy>/swarm is held. Both downloads meet first, as above, so both
# calls are past binary_present before either can publish. The stub holds every mv onto <copy>/swarm: it
# says its pid and source on sync/held, then waits on its own fifo, sync/mv-<pid>, until the test writes
# go there; once its mv has run, it says its pid on sync/moved. The test sets the order, so no step races:
# it lets one download go and releases that call's mv, and lets the other download go only once that mv
# has gone through. The second mv is then held for as long as the test holds it.
C7="${ROOT}/c7"; copy "${C7}"
MVS="${ROOT}/mvs"; mkdir -p "${MVS}"
cat > "${MVS}/mv" <<MV_STUB
#!/bin/sh
src= last=
for a in "\$@"; do src="\${last}"; last="\${a}"; done
[ "\${last}" = "${C7}/swarm" ] || exec "${REAL_MV}" "\$@"
echo "\$*" >> "${LOGS}/mv"
mkfifo "${ROOT}/sync/mv-\$\$" || exit 1
echo "\$\$ \${src}" > "${ROOT}/sync/held"
g=
read -r g < "${ROOT}/sync/mv-\$\$" || exit 1
[ "\${g}" = go ] || exit 1
"${REAL_MV}" "\$@" || exit \$?
echo "\$\$" > "${ROOT}/sync/moved"
MV_STUB
chmod +x "${MVS}/mv"
fifo moved 7; fifo held 8
# hold_next — read the next held mv's "<pid> <source>" on sync/held (fd 8) within WAIT_S, into
# hold_pid and hold_src; both are empty when none comes. release <pid> — let that held mv run.
hold_next() { local l=""; read -r -t "${WAIT_S}" -u 8 l || l=""; hold_pid="${l%% *}"; hold_src="${l#* }"; [[ "${l}" == *" "* ]] || hold_src=""; }
release() { printf 'go\n' > "${ROOT}/sync/mv-$1"; }
for k in 1 2; do start "${C7}" "mv${k}" PATH="${MVS}:${RV}:${RUN_PATH}" -- config; eval "mv_pid${k}=${started_pid}"; done
moved="" first="" held="" second=""
wait_both
check "held mv: both downloads arrived before either went on" 2 "${met}"
if [[ "${met}" -eq 2 ]]; then
  printf 'go\n' > "${ROOT}/sync/go-${arrived[0]}"
  hold_next; first="${hold_pid}"
  if [[ -n "${first}" ]]; then
    release "${first}"
    read -r -t "${WAIT_S}" -u 7 moved || moved=""
  fi
fi
check "held mv: the first writer's mv went through" yes "$([[ -n "${first}" && "${moved}" == "${first}" ]] && echo yes || echo "no: held '${first}', moved '${moved}'")"
check "held mv: <copy>/swarm is the first writer's release" "executable, same" "$(installed "${C7}")"
if [[ -n "${moved}" ]]; then
  printf 'go\n' > "${ROOT}/sync/go-${arrived[1]}"
  hold_next; second="${hold_pid}"; held="${hold_src}"
fi
check "held mv: the second writer's mv is held" yes "$([[ -n "${second}" && "${second}" != "${first}" && -n "${held}" ]] && echo yes || echo no)"
check "held mv: its source is in a .fetch-* folder of the copy" yes \
  "$([[ "${held}" == "${C7}/.fetch-"*"/${ASSET}" ]] && echo yes || echo "no: '${held}'")"
check "held mv: its source is executable and the release" "executable, same" \
  "$([[ -f "${held}" && -x "${held}" ]] && echo executable || echo not-executable), $(cmp -s "${held}" "${RELEASE}" && echo same || echo differs)"
held_out="$(cd "${P}" && SWARMDEV_PROJECT="${P}" "${C7}/swarm" _wrapper-fixture held 2>&1)" || held_out="exit $?: ${held_out}"
check "held mv: meanwhile <copy>/swarm runs _wrapper-fixture" "project = ${P}|arg = held" \
  "$(grep -E '^(project|arg) = ' <<< "${held_out}" | paste -sd '|' -)"
if [[ -n "${second}" ]]; then release "${second}"; read -r -t "${WAIT_S}" -u 7 _ || true; fi   # its moved line
exec 7>&- 8>&- 9>&-
for k in 1 2; do
  p="mv_pid${k}"
  [[ -n "${second}" ]] || stop_group "${!p}" "${ROOT}/groups" || true   # stuck without them
  finish "${!p}" "mv${k}"
done
for k in 1 2; do
  check "held mv, call ${k}: exits 0 with config's output" "0|${config}|" \
    "$(cat "${ROOT}/mv${k}.rc")|$(cat "${ROOT}/mv${k}.out")|$(cat "${ROOT}/mv${k}.err")"
done
check "held mv: the stub held two mv calls onto <copy>/swarm" 2 "$(lines "$(log mv)")"
check "held mv: <copy>/swarm is the release, and no .fetch-* folder is left" "executable, same|" "$(installed "${C7}")|$(temps "${C7}")"
clear_logs

# --- gh-shim folders first on PATH. A failing stub as this copy's shim and as an older version's: the
# download skips both, and the gh stub logs each call once.
C8="${ROOT}/c8"; copy "${C8}"
OLD="${ROOT}/old/swarm-dev/0.30.0"; mkdir -p "${OLD}/bin/gh-shim"
for n in new old; do
  s="${C8}/bin/gh-shim"; [[ "${n}" == new ]] || s="${OLD}/bin/gh-shim"
  : > "${LOGS}/shim-${n}"
  printf '#!/bin/sh\necho "$*" >> "%s/shim-%s"\nexit 1\n' "${LOGS}" "${n}" > "${s}/gh"; chmod +x "${s}/gh"
done
sw "${C8}" PATH="${C8}/bin/gh-shim:${OLD}/bin/gh-shim:${RUN_PATH}" -- config
calls="$(log gh)"; dir="$(fetch_dir "${calls}")" || dir=""
check "shim stubs first: exits 0 with config's output" "0|${config}|" "${rc}|${out}|${err}"
check "shim stubs first: neither shim was run" "|" "$(cat "${LOGS}/shim-new")|$(cat "${LOGS}/shim-old")"
check "shim stubs first: the gh stub logged each call once" "$(want_calls "${dir}")" "${calls}"
check "shim stubs first: <copy>/swarm is the release" "executable, same" "$(installed "${C8}")"
# The positive control: a gh call on that PATH reaches the copy's shim stub.
(PATH="${C8}/bin/gh-shim:${OLD}/bin/gh-shim:${RUN_PATH}" gh control > /dev/null 2>&1) || true
check "the control: gh on that PATH runs the copy's shim stub" control "$(cat "${LOGS}/shim-new")"
# The real shims: this copy's and an older one's, under an alarm of TIME_BOUND, which a call that loops
# between them would reach (exit 142).
C9="${ROOT}/c9"; copy "${C9}"
OLD2="${ROOT}/old2/swarm-dev/0.30.0"; mkdir -p "${OLD2}/bin/gh-shim"; cp "${REPO}/bin/gh-shim/gh" "${OLD2}/bin/gh-shim/gh"
rc=0
# shellcheck disable=SC2016 # perl's own variables
(cd "${P}" || exit 1
 env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN GH_HOST="${HOST}" PATH="${C9}/bin/gh-shim:${OLD2}/bin/gh-shim:${RUN_PATH}" \
   perl -e 'alarm shift; exec { $ARGV[0] } @ARGV or exit 127' "${TIME_BOUND}" bash "${C9}/bin/swarm.sh" config) \
  < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
calls="$(log gh)"; dir="$(fetch_dir "${calls}")" || dir=""
check "real shims first: exits 0 within ${TIME_BOUND} s, with config's output" "0|${config}|" "${rc}|$(cat "${ROOT}/out")|$(cat "${ROOT}/err")"
check "real shims first: the gh stub logged each call once" "$(want_calls "${dir}")" "${calls}"
check "real shims first: <copy>/swarm is the release" "executable, same" "$(installed "${C9}")"
clear_logs

# A gh wrapper that serves the download, then holds mid-download: it writes its pid and its sleep's pid,
# says so on sync/started, and waits on the sleep.
SL="${ROOT}/sl"; mkdir -p "${SL}"
# shellcheck disable=SC2016 # the stub expands its own
printf '#!/bin/sh\n"%s/bin/gh" "$@" || exit $?\n[ "$1 $2" = "release download" ] || exit 0\necho "$$" > "%s/sync/gh.pid"\nsleep 300 &\necho "$!" > "%s/sync/sleep.pid"\necho started > "%s/sync/started"\nwait\n' \
  "${F}" "${ROOT}" "${ROOT}" "${ROOT}" > "${SL}/gh"; chmod +x "${SL}/gh"
# The same, but it holds as one process, as gh does: it execs the sleep. An INT to the whole group
# reaches the stub itself where bash's $( ) child has INT back at its default (bash 5); a child it had
# started in the background would ignore the INT, outlive it, leave the process tree and hold
# binary_download's stderr pipe open, which no real gh does.
SL1="${ROOT}/sl1"; mkdir -p "${SL1}"
# shellcheck disable=SC2016 # the stub expands its own
printf '#!/bin/sh\n"%s/bin/gh" "$@" || exit $?\n[ "$1 $2" = "release download" ] || exit 0\necho "$$" > "%s/sync/gh.pid"\necho started > "%s/sync/started"\nexec sleep 300\n' \
  "${F}" "${ROOT}" "${ROOT}" > "${SL1}/gh"; chmod +x "${SL1}/gh"
# settled <copy> <swarm pid> <pid>... — within 5 s from now: swarm.sh has exited (a zombie, as this shell
# has not reaped it yet), none of the other pids runs, and <copy> has no .fetch-* folder. Prints what is
# left at the end, or nothing.
settled() {
  # shellcheck disable=SC2016 # perl's own variables
  perl -e 'my ($copy, $sw, @pids) = @ARGV; my @left;
    for (1 .. 50) {
      my $st = `ps -o stat= -p $sw 2>/dev/null`; $st =~ s/\s+//g;
      opendir(my $d, $copy) or die "opendir $copy: $!";
      @left = ((($st ne "" && $st !~ /^Z/) ? ("swarm.sh") : ()), (grep { kill 0, $_ } @pids),
        (grep { /^\.fetch-/ } readdir $d));
      closedir $d;
      last unless @left;
      select undef, undef, undef, 0.1;
    }
    print "@left"' "$@"
}

# cut <name> <signal> <to> <stub dir> — a call whose download holds, through the gh stub in <stub dir>,
# sent <signal> once it does: to swarm.sh alone (<to> pid), or to its whole group (<to> group), as a
# terminal's Ctrl-C reaches every process of the job. Within 5 s of the signal swarm.sh has exited, no gh
# process is left, nor a child it waits on, and no .fetch-* folder; the call exits non-zero and leaves no
# <copy>/swarm.
cut() {
  local name="$1" sig="$2" to="$3" stubs="$4" c="${ROOT}/cut-$1" pid ghs left
  copy "${c}"
  fifo started 7
  start "${c}" "cut-${name}" PATH="${stubs}:${RUN_PATH}" -- config
  pid="${started_pid}"
  if read -r -t "${WAIT_S}" -u 7 _; then
    check "${name}: the download holds, its files in a .fetch-* folder" yes "$([[ -n "$(temps "${c}")" ]] && echo yes || echo no)"
    ghs="$(cat "${ROOT}/sync/gh.pid" "${ROOT}/sync/sleep.pid" 2>/dev/null | tr '\n' ' ' || true)"
    if [[ "${to}" == group ]]; then kill "-${sig}" -- "-${pid}"; else kill "-${sig}" "${pid}"; fi
    # shellcheck disable=SC2086 # two pids
    left="$(settled "${c}" "${pid}" ${ghs})"
    check "${name}: within 5 s swarm.sh exits, and no gh process, its child or .fetch-* folder is left" "" "${left}"
    [[ -z "${left}" ]] || stop_group "${pid}" "${ROOT}/groups" || true   # so the wait below ends
    finish "${pid}" "cut-${name}"
    check "${name}: exits non-zero" yes "$([[ "$(cat "${ROOT}/cut-${name}.rc")" != 0 ]] && echo yes || echo no)"
    check "${name}: no <copy>/swarm" none "$(installed "${c}")"
  else
    check "${name}: the download started" yes no
  fi
  stop_group "${pid}" "${ROOT}/groups" || true
  exec 7>&-; rm -f "${ROOT}/sync/started" "${ROOT}/sync/gh.pid" "${ROOT}/sync/sleep.pid"
  clear_logs
}
cut "TERM to swarm.sh" TERM pid "${SL}"
cut "INT to the call's group" INT group "${SL1}"

# --- A KILL to the call's group while the download holds, then a call that fetches again.
C11="${ROOT}/c11"; copy "${C11}"
fifo started 7
start "${C11}" kill PATH="${SL}:${RUN_PATH}" -- config
kill_pid="${started_pid}"
if read -r -t "${WAIT_S}" -u 7 _; then
  stop_group "${kill_pid}" "${ROOT}/groups"
  left="$(temps "${C11}")"
  check "KILL: no <copy>/swarm" none "$(installed "${C11}")"
  check "KILL: one .fetch-* folder is left, holding the downloaded files" "1|2" \
    "$(lines "${left}")|$(find "${C11}"/.fetch-* -type f 2>/dev/null | wc -l | tr -d ' ')"
  check "KILL: the folder holds no executable file" "" "$(find "${C11}"/.fetch-* -type f -perm -u+x 2>/dev/null)"
  sw "${C11}" -- config
  check "KILL, the next call: fetches and exits 0 with config's output" "0|${config}|executable, same" "${rc}|${out}|$(installed "${C11}")"
  check "KILL, the next call: it fetched into a folder of its own" yes "$([[ "$(log gh)" == *" release download "* ]] && echo yes || echo no)"
else
  check "KILL: the download started" yes no
  stop_group "${kill_pid}" "${ROOT}/groups" || true
fi
exec 7>&-
clear_logs

# --- update, with a claude stub: it needs no binary, and fetches none.
C12="${ROOT}/c12"; copy "${C12}"
CL="${ROOT}/claude-stub"; mkdir -p "${CL}"
printf '#!/bin/sh\necho "$*" >> "%s/claude"\nexit 0\n' "${LOGS}" > "${CL}/claude"; chmod +x "${CL}/claude"
sw "${C12}" PATH="${CL}:${RUN_PATH}" -- update
check "update: exits 0 and ran claude twice" "0|2" "${rc}|$(lines "$(log claude)")"
check "update: no gh call and no <copy>/swarm" "|none" "$(log gh)|$(installed "${C12}")"

# The positive controls: each logging wrapper logs a start made through RUN_PATH.
(PATH="${RUN_PATH}" git --version > /dev/null 2>&1; PATH="${RUN_PATH}" uname -s > /dev/null) || true
check "the control: the git and uname wrappers log a start" "1|1" "$(lines "$(log git)")|$(lines "$(log uname)")"
(PATH="${RUN_PATH}" bash -c 'command -v sha256sum > /dev/null && sha256sum /dev/null; command -v shasum > /dev/null && shasum -a 256 /dev/null' > /dev/null 2>&1) || true
check "the control: the sum wrappers log a start" yes "$([[ -n "$(log sum)" ]] && echo yes || echo no)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all binary_fetch checks passed"
