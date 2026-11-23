#!/usr/bin/env bash
# binary_attest_test.sh — bin/lib/binary.sh's binary_attest verifies a downloaded binary's build
# attestation with exactly one call, `gh attestation verify <file> --hostname github.com --repo <repo>
# --signer-workflow github.com/<repo>/<signer>`, and prints none of gh's output. When gh fails, or the
# file's bytes are not the release's, it returns 1 and says one line. When gh hangs, binary_within stops
# it once BINARY_ATTEST_SECONDS pass, and it returns 1 and says one line naming the bound. An empty
# argument stops it in one line before any gh call. Each case runs in a new bash whose PATH holds only a
# gh stub and perl, which binary_within runs. The stub logs every call and prints a line on stdout and on
# stderr. It exits 0 only for that exact call, on a file named as the release asset whose bytes are
# cmp-equal to the fixture. Anything else exits 1. Told to hang, it ignores SIGALRM as gh, a Go program,
# does (a control below shows it outlives a plain alarm), then sleeps.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${REPO}/bin/lib/binary.sh"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${ROOT}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
# The hanging stub runs in binary_within's process group, which stop_test_group does not reach, so the
# trap KILLs it by the pid it wrote too.
cleanup() {
  local p=""
  [[ ! -s "${ROOT}/stub.pid" ]] || p="$(cat "${ROOT}/stub.pid")"
  [[ -z "${p}" ]] || kill -KILL "${p}" 2>/dev/null || true
  stop_test_group || true
  rm -rf "${ROOT}"
}
trap cleanup EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file
# The repo, the signer and an asset name as fetch-ensure will pass them, from scripts/build.sh --list.
GH_REPO=redscaresu/swarm-dev
SIGNER=.github/workflows/release.yml
ASSET=swarm-linux-amd64
STUBS="${ROOT}/stubs"; LOGS="${ROOT}/logs"; FAILS_FLAG="${ROOT}/gh-fails"; HANG_FLAG="${ROOT}/gh-hangs"
RELEASE="${ROOT}/release/${ASSET}"; DL="${ROOT}/download"
mkdir -p "${STUBS}" "${LOGS}" "${ROOT}/release" "${DL}" "${ROOT}/tampered"
CMP="$(command -v cmp)" || { echo "no cmp on PATH" >&2; exit 1; }
SLEEP="$(command -v sleep)" || { echo "no sleep on PATH" >&2; exit 1; }
PERL="$(command -v perl)" || { echo "no perl on PATH" >&2; exit 1; }
ln -s "${PERL}" "${STUBS}/perl"

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
lines() { # <text>: its number of lines, 0 for none
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}

# The release's bytes, and the downloaded copy binary_attest checks.
printf 'swarm release fixture\n\001\002\003\n' > "${RELEASE}"
cp "${RELEASE}" "${DL}/${ASSET}"

# The stub. It ignores SIGALRM first thing, as gh does. Each call appends one line to the log, its
# arguments each followed by a tab. With HANG_FLAG there, it writes its pid to stub.pid and sleeps for
# the seconds the flag holds.
cat > "${STUBS}/gh" <<STUB
#!/bin/sh
trap '' ALRM
for a in "\$@"; do printf '%s\t' "\$a"; done >> "${LOGS}/gh"
printf '\n' >> "${LOGS}/gh"
echo "stub-out: gh wrote this to stdout"
echo "stub-err: gh wrote this to stderr" >&2
if [ -e "${HANG_FLAG}" ]; then
  echo "\$\$" > "${ROOT}/stub.pid"
  read -r secs < "${HANG_FLAG}"
  exec "${SLEEP}" "\$secs"
fi
[ ! -e "${FAILS_FLAG}" ] || exit 1
[ "\$#" -eq 9 ] || exit 1
[ "\$1" = attestation ] && [ "\$2" = verify ] || exit 1
case "\$3" in */${ASSET}) ;; *) exit 1 ;; esac
[ -f "\$3" ] && "${CMP}" -s "\$3" "${RELEASE}" || exit 1
[ "\$4" = --hostname ] && [ "\$5" = github.com ] || exit 1
[ "\$6" = --repo ] && [ "\$7" = "${GH_REPO}" ] || exit 1
[ "\$8" = --signer-workflow ] && [ "\$9" = "github.com/${GH_REPO}/${SIGNER}" ] || exit 1
exit 0
STUB
chmod +x "${STUBS}/gh"

# stub <args>: the stub's exit code for one call, with only the stubs on PATH.
stub() {
  local r=0
  env PATH="${STUBS}" "${STUBS}/gh" "$@" > /dev/null 2>&1 || r=$?
  rm -f "${LOGS}/gh"; echo "${r}"
}
# The stub accepts the exact call, and refuses each change the mutations below make, so case 1 passing
# means binary_attest made that call.
WANT_SIGNER="github.com/${GH_REPO}/${SIGNER}"
check "the stub accepts the exact call" 0 \
  "$(stub attestation verify "${DL}/${ASSET}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "${WANT_SIGNER}")"
check "the stub refuses the call without --signer-workflow" 1 \
  "$(stub attestation verify "${DL}/${ASSET}" --hostname github.com --repo "${GH_REPO}")"
check "the stub refuses the folder in place of the file" 1 \
  "$(stub attestation verify "${DL}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "${WANT_SIGNER}")"
check "the stub refuses another signer" 1 \
  "$(stub attestation verify "${DL}/${ASSET}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "github.com/${GH_REPO}/")"
# Told to hang, the stub outlives a plain alarm, as gh does: an alarm alone bounds nothing.
echo 4 > "${HANG_FLAG}"; start=${SECONDS}
r=0; env PATH="${STUBS}" perl -e 'alarm 2; exec @ARGV or exit 127' "${STUBS}/gh" > /dev/null 2>&1 || r=$?
check "a hanging stub outlives a plain 2 s alarm and ends on its own" "0 yes" \
  "${r} $([[ $((SECONDS - start)) -ge 4 ]] && echo yes || echo "no: $((SECONDS - start)) s")"
rm -f "${HANG_FLAG}" "${ROOT}/stub.pid" "${LOGS}/gh"

# attest <file> <repo> <signer> [<seconds>]: source the lib and run binary_attest in a new bash with
# only the stubs on PATH, BINARY_ATTEST_SECONDS set to <seconds> when given. Sets out, err, rc and calls
# (the stub's log, one line per call).
attest() {
  rm -f "${LOGS}/gh"; rc=0
  # shellcheck disable=SC2016 # the inner bash expands its own arguments
  env PATH="${STUBS}" "${BASH}" -c 'source "$1" && BINARY_ATTEST_SECONDS="${5:-${BINARY_ATTEST_SECONDS}}" &&
    binary_attest "$2" "$3" "$4"' _ "${LIB}" "$@" > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
  calls="$(cat "${LOGS}/gh" 2>/dev/null || true)"
}
# stopped <name> <path>: the last attest returned 1, printed nothing on stdout and one binary: line on
# stderr naming <path> and saying gh attestation verify failed, with none of the stub's output.
stopped() {
  check "$1: returns 1" 1 "${rc}"
  check "$1: prints nothing on stdout" "" "${out}"
  check "$1: says one line" 1 "$(lines "${err}")"
  check "$1: the line is binary's and says gh attestation verify failed, naming the file" yes \
    "$([[ "${err}" == "binary: "* && "${err}" == *"gh attestation verify failed"* && "${err}" == *"$2"* ]] && echo yes || echo "no: ${err}")"
  check "$1: none of gh's output" no "$([[ "${out}${err}" == *stub-* ]] && echo yes || echo no)"
}

# 1. The downloaded release binary: one call, exactly the form above, and nothing printed.
attest "${DL}/${ASSET}" "${GH_REPO}" "${SIGNER}"
check "release binary: returns 0" 0 "${rc}"
check "release binary: prints nothing on stdout" "" "${out}"
check "release binary: prints nothing on stderr" "" "${err}"
check "release binary: one gh call" 1 "$(lines "${calls}")"
check "release binary: the call is the exact form" \
  "$(printf '%s\t' attestation verify "${DL}/${ASSET}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "${WANT_SIGNER}")" \
  "${calls}"

# 2. gh fails: one line, return 1, one call and no other try.
: > "${FAILS_FLAG}"
attest "${DL}/${ASSET}" "${GH_REPO}" "${SIGNER}"
rm -f "${FAILS_FLAG}"
stopped "gh fails" "${DL}/${ASSET}"
check "gh fails: one gh call" 1 "$(lines "${calls}")"

# 3. A file named as the asset whose bytes are not the release's.
cp "${RELEASE}" "${ROOT}/tampered/${ASSET}"; printf 'x' >> "${ROOT}/tampered/${ASSET}"
attest "${ROOT}/tampered/${ASSET}" "${GH_REPO}" "${SIGNER}"
stopped "bytes not the release's" "${ROOT}/tampered/${ASSET}"

# 4. gh hangs: binary_within stops it at the bound, here 1 s, well before the stub's 60 s sleep ends.
echo 60 > "${HANG_FLAG}"; start=${SECONDS}
attest "${DL}/${ASSET}" "${GH_REPO}" "${SIGNER}" 1
took=$((SECONDS - start)); rm -f "${HANG_FLAG}"
stopped "gh hangs" "${DL}/${ASSET}"
check "gh hangs: the line names the bound" yes \
  "$([[ "${err}" == *"no answer within 1 s"* ]] && echo yes || echo "no: ${err}")"
check "gh hangs: returns well before the stub's sleep ends" yes \
  "$([[ "${took}" -lt 30 ]] && echo yes || echo "no: ${took} s")"
check "gh hangs: one gh call" 1 "$(lines "${calls}")"
check "gh hangs: the stub ran and is gone" gone \
  "$(p="$(cat "${ROOT}/stub.pid" 2>/dev/null)"
    if [[ -z "${p}" ]]; then echo "no pid written"; elif kill -0 "${p}" 2>/dev/null; then echo alive; else echo gone; fi)"
rm -f "${ROOT}/stub.pid"

# 5. An empty argument stops before gh. An empty signer matters most: an older gh would take
# github.com/<repo>/ as a prefix that every workflow in the repo matches.
for c in file repo signer; do
  case "${c}" in
    file) attest "" "${GH_REPO}" "${SIGNER}" ;;
    repo) attest "${DL}/${ASSET}" "" "${SIGNER}" ;;
    signer) attest "${DL}/${ASSET}" "${GH_REPO}" "" ;;
  esac
  check "empty ${c}: returns 1" 1 "${rc}"
  check "empty ${c}: prints nothing on stdout" "" "${out}"
  check "empty ${c}: says one binary: line" "1 yes" "$(lines "${err}") $([[ "${err}" == "binary: "* ]] && echo yes || echo no)"
  check "empty ${c}: no gh call" "" "${calls}"
done

[[ "${fails}" -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all binary_attest checks passed"
