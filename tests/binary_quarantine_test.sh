#!/usr/bin/env bash
# binary_quarantine_test.sh — macOS's quarantine mark (com.apple.quarantine) on the swarm binary stops the
# call in one line and runs nothing: binary_quarantined in bin/lib/binary.sh, which binary_download runs on
# the asset after its checksum, and binary_present on <root>/swarm on every call on macOS.
# The lib cases source binary.sh in a new bash, with BINARY_XATTR set after sourcing to a stub that logs
# each start and lists attribute names as `xattr <file>` does: the mark among others (marked), others
# only, one a longer name that starts with the mark's (unmarked), or exits 1 as a failed read does
# (failing); or to a path with no file (missing):
#   binary_download, with the uname stub of tests/binary_fetch_stubs.sh reporting Darwin: marked returns 1
#     with one line naming the mark; unmarked returns 0 and says nothing; failing and missing return 1
#     with one line saying the mark cannot be checked. Each stub starts once, on the downloaded asset.
#     Reporting Linux, marked returns 0 and starts no xattr.
#   binary_present, with OSTYPE set in the inner bash: darwin and marked returns 2 with one line; unmarked
#     0; failing and missing 2 with one line. linux-gnu and marked returns 0, and no file returns 1,
#     neither starting xattr.
#   binary_ensure on a present marked file, OSTYPE darwin: returns 1 with one line, exports no SWARMDEV_BIN,
#     and the gh stub logs no call.
# The real-mark cases run a no-.git copy's swarm.sh config from a project, with the stubs first on PATH,
# and a real `xattr -w com.apple.quarantine`. They run on macOS, and on any other platform say they are
# skipped. On macOS they always run, so this file passing there means they passed:
#   the download marked by a gh wrapper ahead of the stub, which runs the stub and then marks the file it
#     wrote, with bin/ported/config present: exit 1, one stderr line naming the mark, no stdout, no
#     <copy>/swarm, no .fetch-* folder and no attestation asked for;
#   a present <copy>/swarm with the mark: exit 1, one stderr line naming the mark, no gh call; an
#     unmarked one, the real binary, which is never marked: config runs and prints the project's board.
# No marked file is ever a program, and the gh wrapper refuses to attest a marked file, so even with the
# check broken no marked file runs: macOS would hold its exec behind a Gatekeeper dialog.
# shellcheck disable=SC2016 # the inner bash and the stubs expand their own
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/binary_fetch_stubs.sh
source "$(dirname "${BASH_SOURCE[0]}")/binary_fetch_stubs.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${REPO}/bin/lib/binary.sh"
if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
  echo "FAIL SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
  exit 1
fi
BUILT="${SWARMDEV_BIN}"   # make test's build, copied to stand in for a fetched <copy>/swarm
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

MARK=com.apple.quarantine         # BINARY_QUARANTINE, copied so a change to it is a change to this test
REAL_XATTR=/usr/bin/xattr         # BINARY_XATTR's value
MARK_VALUE='0081;00000000;Safari;' # what a browser writes: flags, time, the app
VERSION=9.8.7; HOST=ghe.example.com; SUMS=SHA256SUMS
CALL_BOUND=60   # seconds a real-mark swarm.sh call may take

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
lines() { # <text>: its number of lines, 0 for none
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}
has() { [[ "$2" == *"$1"* ]] && echo yes || echo "no: $2"; }   # <text> <in>: yes when <in> holds <text>

F="${ROOT}/fetch"; fetch_stubs "${F}" "${VERSION}" || exit 1
STUBS="${F}/bin"
TOOLS="${ROOT}/tools"; mkdir -p "${TOOLS}"
for t in dirname uname sha256sum shasum; do
  p="$(command -v "${t}")" || continue
  ln -s "${p}" "${TOOLS}/${t}"
done
# The xattr stubs: each logs its arguments to XLOG, then answers as `xattr <file>` does.
XLOG="${ROOT}/xattr.log"; X="${ROOT}/xattr"; mkdir -p "${X}"
printf '#!/bin/sh\necho "$*" >> "%s"\nprintf "com.apple.provenance\\n%s\\n"\n' "${XLOG}" "${MARK}" > "${X}/marked"
printf '#!/bin/sh\necho "$*" >> "%s"\nprintf "com.apple.provenance\\n%sx\\n"\n' "${XLOG}" "${MARK}" > "${X}/unmarked"
printf '#!/bin/sh\necho "$*" >> "%s"\necho "xattr: [Errno 1] Operation not permitted: $1" >&2\nexit 1\n' "${XLOG}" > "${X}/failing"
chmod +x "${X}/marked" "${X}/unmarked" "${X}/failing"
MISSING="${X}/missing"
xlog() { cat "${XLOG}" 2>/dev/null || true; rm -f "${XLOG}"; }

C="${ROOT}/copy"; mkdir -p "${C}/scripts"; cp "${REPO}/scripts/build.sh" "${C}/scripts/"
fetch_release "${F}" swarm-darwin-arm64 "${SUMS}" || exit 1

# lib <xattr> <script> [args] — <script> in a new bash from <copy>, after sourcing the lib and setting
# BINARY_XATTR to <xattr>, with PATH the stubs and TOOLS. Sets rc, out and err.
lib() {
  local x="$1" s="$2"; shift 2
  rc=0
  (cd "${C}" || exit 1
   env GH_HOST="${HOST}" PATH="${STUBS}:${TOOLS}" "${BASH}" -c 'source "$1" && BINARY_XATTR="$2" && shift 2 && '"${s}" _ \
     "${LIB}" "${x}" "$@") > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
# download <name> <xattr> — binary_download <copy> VERSION into a new folder, D.
n=0
download() {
  n=$((n + 1)); D="${ROOT}/dl-${n}"; mkdir -p "${D}"
  lib "$2" 'binary_download "$@"' "${C}" "${VERSION}" "${D}"
}
# one_line <name> <rc> <text> — the last case returned <rc>, said nothing on stdout and one stderr
# line, a binary: line holding <text>.
one_line() {
  check "$1: returns $2" "$2" "${rc}"
  check "$1: nothing on stdout" "" "${out}"
  check "$1: one stderr line" 1 "$(lines "${err}")"
  check "$1: a binary: line" yes "$([[ "${err}" == "binary: "* ]] && echo yes || echo "no: ${err}")"
  check "$1: the line says $3" yes "$(has "$3" "${err}")"
}

# A positive control: the stubs answer as xattr does.
rc=0; got="$("${X}/marked" /x | paste -sd '|' -)" || rc=$?
check "the marked stub exits 0 and lists the mark" "0|com.apple.provenance|${MARK}" "${rc}|${got}"
rc=0; got="$("${X}/unmarked" /x | paste -sd '|' -)" || rc=$?
check "the unmarked stub exits 0 and lists a longer name" "0|com.apple.provenance|${MARK}x" "${rc}|${got}"
rc=0; got="$("${X}/failing" /x 2>/dev/null)" || rc=$?
check "the failing stub exits 1 and lists nothing" "1|" "${rc}|${got}"
xlog > /dev/null

# --- binary_download, uname reporting Darwin.
fetch_uname "${F}" Darwin arm64
download "Darwin, marked" "${X}/marked"
one_line "binary_download, Darwin, marked" 1 "${D}/swarm-darwin-arm64 carries macOS's quarantine mark (${MARK}), so swarm.sh did not run it: it was not installed"
check "binary_download, Darwin, marked: xattr ran once, on the asset" "${D}/swarm-darwin-arm64" "$(xlog)"
download "Darwin, unmarked" "${X}/unmarked"
check "binary_download, Darwin, unmarked: returns 0 and says nothing" "0||" "${rc}|${out}|${err}"
check "binary_download, Darwin, unmarked: xattr ran once, on the asset" "${D}/swarm-darwin-arm64" "$(xlog)"
download "Darwin, failing" "${X}/failing"
one_line "binary_download, Darwin, xattr fails" 1 "${X}/failing could not list the extended attributes of ${D}/swarm-darwin-arm64, so whether it carries macOS's quarantine mark cannot be checked, and swarm.sh did not run it: it was not installed"
check "binary_download, Darwin, failing: xattr ran once, on the asset" "${D}/swarm-darwin-arm64" "$(xlog)"
download "Darwin, missing" "${MISSING}"
one_line "binary_download, Darwin, no xattr" 1 "${MISSING} is not an executable file, so whether ${D}/swarm-darwin-arm64 carries macOS's quarantine mark cannot be checked"
# --- uname reporting Linux: no xattr starts, whatever BINARY_XATTR names.
fetch_release "${F}" swarm-linux-amd64 "${SUMS}" || exit 1
fetch_uname "${F}" Linux x86_64
download "Linux, marked" "${X}/marked"
check "binary_download, Linux, marked: returns 0 and says nothing" "0||" "${rc}|${out}|${err}"
check "binary_download, Linux: no xattr start" "" "$(xlog)"
fetch_uname "${F}"
rm -f "${F}/log/gh" "${F}/log/uname"

# --- binary_present and binary_ensure, with OSTYPE set as bash sets it on each platform.
B="${ROOT}/present"; mkdir -p "${B}"; cp "${BUILT}" "${B}/swarm"
lib "${X}/marked" 'OSTYPE=darwin24; binary_present "$1"' "${B}"
one_line "binary_present, darwin, marked: refused" 2 "${B}/swarm carries macOS's quarantine mark (${MARK}), so swarm.sh did not run it: delete it and run the command again"
check "binary_present, darwin: xattr ran once, on <root>/swarm" "${B}/swarm" "$(xlog)"
lib "${X}/unmarked" 'OSTYPE=darwin24; binary_present "$1"' "${B}"
check "binary_present, darwin, unmarked: returns 0 and says nothing" "0||" "${rc}|${out}|${err}"
xlog > /dev/null
lib "${X}/failing" 'OSTYPE=darwin24; binary_present "$1"' "${B}"
one_line "binary_present, darwin, xattr fails: refused" 2 "${X}/failing could not list the extended attributes of ${B}/swarm"
xlog > /dev/null
lib "${MISSING}" 'OSTYPE=darwin24; binary_present "$1"' "${B}"
one_line "binary_present, darwin, no xattr: refused" 2 "${MISSING} is not an executable file"
lib "${X}/marked" 'OSTYPE=linux-gnu; binary_present "$1"' "${B}"
check "binary_present, linux, marked: returns 0 and says nothing" "0||" "${rc}|${out}|${err}"
check "binary_present, linux: no xattr start" "" "$(xlog)"
lib "${X}/marked" 'OSTYPE=darwin24; binary_present "$1"' "${ROOT}/no-copy"
check "binary_present, no file: returns 1 and says nothing" "1||" "${rc}|${out}|${err}"
check "binary_present, no file: no xattr start" "" "$(xlog)"
lib "${X}/marked" 'OSTYPE=darwin24; unset SWARMDEV_BIN; rc=0; binary_ensure "$1" || rc=$?; echo "SWARMDEV_BIN=${SWARMDEV_BIN-unset}"; exit "${rc}"' "${B}"
check "binary_ensure, darwin, a marked present file: returns 1 and exports no SWARMDEV_BIN" "1|SWARMDEV_BIN=unset" "${rc}|${out}"
check "binary_ensure, darwin, a marked present file: one stderr line naming the mark" "1|yes" "$(lines "${err}")|$(has "quarantine mark (${MARK})" "${err}")"
check "binary_ensure, darwin, a marked present file: the gh stub logs no call" "" "$(cat "${F}/log/gh" 2>/dev/null || true)"
xlog > /dev/null

# --- The real mark, through swarm.sh, on macOS only.
if [[ "$(uname -s)" != Darwin ]]; then
  echo "skip the real-mark cases: they need macOS's xattr, and this is $(uname -s)"
else
  [[ -x "${REAL_XATTR}" ]] || { echo "FAIL macOS has no ${REAL_XATTR}"; exit 1; }
  case "$(uname -m)" in x86_64) ARCH=amd64 ;; *) ARCH=arm64 ;; esac
  ASSET="swarm-darwin-${ARCH}"
  fetch_release "${F}" "${ASSET}" "${SUMS}" || exit 1
  # No file this section marks is ever a program, so even with the check broken no marked file can run:
  # macOS holds the exec of a marked program behind a Gatekeeper dialog, which blocks an unattended run.
  # The fake release's asset is INERT, a NUL byte and no #!, which the kernel refuses to exec as any kind
  # of program; and the gh wrapper below refuses to attest a marked file, so a broken check stops there.
  inert() { printf 'swarm-dev binary_quarantine_test: not a program\0\n' > "$1"; }
  is_inert() { [[ "$(head -c 47 "$1")" == "swarm-dev binary_quarantine_test: not a program" ]] && echo yes || echo no; }
  inert "${F}/release/${ASSET}"
  printf '%s  %s\n' "$(fetch_sum "${F}/release/${ASSET}")" "${ASSET}" > "${F}/release/${SUMS}"
  VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${REPO}/.claude-plugin/plugin.json")"
  printf '%s\n' "${VERSION}" > "${F}/stub/version"
  P="${ROOT}/proj"; mkdir -p "${P}/.claude/swarm"; printf 'board_dir = board\n' > "${P}/.claude/swarm/config"
  # copy <dir> [marker...] — an installed copy: no .git; each marker an empty bin/ported/<name>.
  copy() {
    local d="$1" m; shift
    mkdir -p "${d}/scripts"
    cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "${REPO}/cmd" "${REPO}/internal" "${d}/"
    cp "${REPO}/scripts/build.sh" "${d}/scripts/"
    mkdir -p "${d}/bin/ported"
    for m in "$@"; do : > "${d}/bin/ported/${m}"; done
  }
  # sw <copy> <path> — <copy>'s swarm.sh config from the project, PATH <path>, KILLed with its whole group
  # after CALL_BOUND seconds (exit 142) by the lib's binary_within, so no call can hang the file. Sets rc,
  # out and err.
  sw() {
    rc=0
    (cd "${P}" || exit 1
     # shellcheck source=bin/lib/binary.sh
     source "${LIB}" || exit 1
     binary_within "${CALL_BOUND}" env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN GH_HOST="${HOST}" PATH="$2" \
       bash "$1/bin/swarm.sh" config) < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
    out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
  }
  temps() { (cd "$1" && find . -maxdepth 1 -name '.fetch-*' | sort); }
  # The gh wrapper: an attestation of a file that carries the mark is logged to ${ROOT}/marked-attest and
  # fails, so a check that let the mark through stops before the install. Any other call runs the stub;
  # after a release download it marks the asset the stub wrote, as a browser would.
  W="${ROOT}/mark-gh"; mkdir -p "${W}"
  printf "#!/bin/sh\nS='%s' F='%s' X='%s' M='%s' V='%s' L='%s'\n" \
    "${STUBS}" "${F}" "${REAL_XATTR}" "${MARK}" "${MARK_VALUE}" "${ROOT}/marked-attest" > "${W}/gh"
  cat >> "${W}/gh" <<'MARK_GH'
if [ "$1 $2" = "attestation verify" ]; then
  for n in $("$X" "$3" 2>/dev/null); do
    if [ "$n" = "$M" ]; then echo "$3" >> "$L"; exit 1; fi
  done
fi
"$S/gh" "$@" || exit $?
[ "$1 $2" = "release download" ] || exit 0
read -r a < "$F/stub/asset" && "$X" -w "$M" "$V" "${11}/$a"
MARK_GH
  chmod +x "${W}/gh"
  RUN_PATH="${STUBS}:${PATH}"

  C1="${ROOT}/c1"; copy "${C1}" config
  sw "${C1}" "${W}:${RUN_PATH}"
  calls="$(cat "${F}/log/gh" 2>/dev/null || true)"; rm -f "${F}/log/gh"
  check "real mark, download: exits 1" 1 "${rc}"
  check "real mark, download: exactly one stderr line" 1 "$(lines "${err}")"
  check "real mark, download: the line names the mark" yes "$(has "carries macOS's quarantine mark (${MARK}), so swarm.sh did not run it: it was not installed" "${err}")"
  check "real mark, download: nothing on stdout" "" "${out}"
  check "real mark, download: no <copy>/swarm" none "$([[ -e "${C1}/swarm" ]] && echo there || echo none)"
  check "real mark, download: no .fetch-* folder" "" "$(temps "${C1}")"
  check "real mark, download: gh downloaded, and no attestation was asked for" "1|0" \
    "$(grep -c ' release download ' <<< "${calls}" || true)|$(grep -c ' attestation ' <<< "${calls}" || true)"
  check "real mark, download: no marked file reached the attestation" "" "$(cat "${ROOT}/marked-attest" 2>/dev/null || true)"

  # A present <copy>/swarm that carries the mark: INERT, made executable, so binary_present takes it for
  # the binary, and its refusal is the one thing that stops the call.
  C2="${ROOT}/c2"; copy "${C2}"; inert "${C2}/swarm"; chmod +x "${C2}/swarm"
  "${REAL_XATTR}" -w "${MARK}" "${MARK_VALUE}" "${C2}/swarm"
  check "real mark, present: the file carries it, and is no program" "${MARK_VALUE}|yes" \
    "$("${REAL_XATTR}" -p "${MARK}" "${C2}/swarm")|$(is_inert "${C2}/swarm")"
  sw "${C2}" "${RUN_PATH}"
  check "real mark, present: exits 1" 1 "${rc}"
  check "real mark, present: exactly one stderr line" 1 "$(lines "${err}")"
  check "real mark, present: the line names the mark" yes "$(has "${C2}/swarm carries macOS's quarantine mark (${MARK})" "${err}")"
  check "real mark, present: nothing on stdout" "" "${out}"
  check "real mark, present: no gh call" "" "$(cat "${F}/log/gh" 2>/dev/null || true)"
  # An unmarked present <copy>/swarm, the real binary, which nothing here ever marks: config runs.
  C3="${ROOT}/c3"; copy "${C3}"; cp "${BUILT}" "${C3}/swarm"
  sw "${C3}" "${RUN_PATH}"
  check "real mark, present, unmarked: config runs" "0|" "${rc}|${err}"
  check "real mark, present, unmarked: config prints the project's board" yes \
    "$(grep -q "^board_dir = ${P}/board " <<< "${out}" && echo yes || echo "no: ${out}")"
  check "real mark, present, unmarked: no gh call" "" "$(cat "${F}/log/gh" 2>/dev/null || true)"
fi

if [[ "${fails}" -gt 0 ]]; then echo "${fails} check(s) failed"; exit 1; fi
echo "all checks passed"
