#!/usr/bin/env bash
# binary_attest_test.sh — bin/lib/binary.sh's binary_attest verifies a downloaded binary's build
# attestation as release v<version>'s. It reads the commit v<version>'s tag is at with one call,
# `gh api --hostname github.com repos/<repo>/git/ref/tags/v<version> --jq <BINARY_TAG_JQ>`, then verifies
# with one call, `gh attestation verify <file> --hostname github.com --repo <repo> --signer-workflow
# github.com/<repo>/<signer> --source-digest <that commit> --source-ref refs/heads/main`, and prints none
# of gh's output. When the verify fails, one more call, the same with no --source-digest and with
# --format json --jq <BINARY_ATTESTED_JQ>, lists the commits the file is attested at. When they are all
# other commits, the one line names them and the tag's commit: the file is another release's binary.
# Every other failure (gh fails, bytes that are not the release's, a build from another branch, a tag
# read that fails or is no commit) returns 1 with one line. When gh hangs, binary_within stops it once
# BINARY_ATTEST_SECONDS pass, and the one line names the bound. An empty argument, or a version that is
# not a plain name, stops it in one line before any gh call.
# Each case runs in a new bash whose PATH holds only a gh stub and perl, which binary_within runs. The
# stub logs every call and prints a line on stderr. It plays gh for one release: its tag reads as the
# line in ${ROOT}/tag, and its asset is attested at the commits in ${ROOT}/attested, built from the ref
# in ${ROOT}/ref. A verify passes only for a file named as the asset whose bytes are cmp-equal to the
# fixture, with the exact host, repo and signer; with --source-digest, only when an attestation is at
# that commit; with --source-ref, only when that is the build's ref. As in gh, a flag not given checks
# nothing. With --format json --jq it prints the attested commits; with neither, a line on stdout.
# Anything else exits 1. With ${ROOT}/gate-fails, a verify with --source-digest exits 1. Told to hang,
# it ignores SIGALRM as gh, a Go program, does (a control below shows it outlives a plain alarm), then
# sleeps.
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
# The repo (binary_repo's), the signer and an asset name as fetch-ensure passes them, from
# scripts/build.sh --list, and a version.
GH_REPO=redscaresu/swarm-dev
SIGNER=.github/workflows/release.yml
ASSET=swarm-linux-amd64
VERSION=0.31.91
# Copied from bin/lib/binary.sh's BINARY_SOURCE_REF, BINARY_TAG_JQ and BINARY_ATTESTED_JQ, so a change
# there is a change to this test too.
SOURCE_REF=refs/heads/main
TAG_JQ='.object.type + " " + .object.sha'
ATTESTED_JQ='[.[].verificationResult.signature.certificate.sourceRepositoryDigest] | unique | .[]'
# Three commits: B is the release's, where its tag is; A and C are other releases'.
A=e8ffb92e936e0b82d23fd821f88a6a7889ceed04
B=1366655d122831b7f3c404a933541bc144d52efb
C=097c6ca7ed0f8b4e5f091046fd916fc19fc33bb6
STUBS="${ROOT}/stubs"; LOGS="${ROOT}/logs"; FAILS_FLAG="${ROOT}/gh-fails"; TAG_FAILS_FLAG="${ROOT}/tag-fails"
GATE_FAILS_FLAG="${ROOT}/gate-fails"   # only a verify with --source-digest fails, as a dropped connection would
HANG_FLAG="${ROOT}/gh-hangs"; RELEASE="${ROOT}/release/${ASSET}"; DL="${ROOT}/download"
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
# release <tag line> <ref> <commit>...: what the stub's release is. Its tag reads <tag line>, and its
# asset is attested at each <commit>, built from <ref>.
release() {
  printf '%s\n' "$1" > "${ROOT}/tag"; printf '%s\n' "$2" > "${ROOT}/ref"; shift 2
  printf '%s\n' "$@" > "${ROOT}/attested"
}
release "commit ${B}" "${SOURCE_REF}" "${B}"

# The stub. It ignores SIGALRM first thing, as gh does. Each call appends one line to the log, its
# arguments each followed by a tab. With HANG_FLAG there, holding `<first argument> <seconds>`, a call
# with that first argument writes its pid to stub.pid and sleeps for the seconds.
printf "#!/bin/sh\nL='%s' ROOT='%s' CMP='%s' SLEEP='%s'\nREPO='%s' SIGNER='%s' ASSET='%s' VERSION='%s'\nTJQ='%s'\nAJQ='%s'\n" \
  "${LOGS}" "${ROOT}" "${CMP}" "${SLEEP}" "${GH_REPO}" "${SIGNER}" "${ASSET}" "${VERSION}" "${TAG_JQ}" \
  "${ATTESTED_JQ}" > "${STUBS}/gh"
cat >> "${STUBS}/gh" <<'STUB'
trap '' ALRM
for a in "$@"; do printf '%s\t' "$a"; done >> "$L/gh"
printf '\n' >> "$L/gh"
echo "stub-err: gh wrote this to stderr" >&2
if [ -e "$ROOT/gh-hangs" ]; then
  read -r form secs < "$ROOT/gh-hangs"
  if [ "$1" = "$form" ]; then echo "$$" > "$ROOT/stub.pid"; exec "$SLEEP" "$secs"; fi
fi
if [ "$1" = api ]; then
  [ ! -e "$ROOT/tag-fails" ] || exit 1
  [ "$#" -eq 6 ] && [ "$2" = --hostname ] && [ "$3" = github.com ] &&
    [ "$4" = "repos/$REPO/git/ref/tags/v$VERSION" ] && [ "$5" = --jq ] && [ "$6" = "$TJQ" ] || exit 1
  read -r t < "$ROOT/tag" || exit 1
  printf '%s\n' "$t"; exit 0
fi
[ "$#" -ge 3 ] && [ "$1" = attestation ] && [ "$2" = verify ] || exit 1
[ ! -e "$ROOT/gh-fails" ] || exit 1
file=$3; shift 3
gate=
host= repo= wf= digest= sref= fmt= jq=
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || exit 1
  case "$1" in
    --hostname) host=$2 ;;
    --repo) repo=$2 ;;
    --signer-workflow) wf=$2 ;;
    --source-digest) digest=$2; gate=1 ;;
    --source-ref) sref=$2 ;;
    --format) fmt=$2 ;;
    --jq) jq=$2 ;;
    *) exit 1 ;;
  esac
  shift 2
done
case "$file" in */"$ASSET") ;; *) exit 1 ;; esac
[ -f "$file" ] && "$CMP" -s "$file" "$ROOT/release/$ASSET" || exit 1
[ "$host" = github.com ] && [ "$repo" = "$REPO" ] && [ "$wf" = "github.com/$REPO/$SIGNER" ] || exit 1
read -r ref < "$ROOT/ref" || exit 1
[ -z "$sref" ] || [ "$sref" = "$ref" ] || exit 1
matched=
while IFS= read -r c; do
  [ -n "$c" ] || continue
  [ -z "$digest" ] || [ "$c" = "$digest" ] || continue
  matched="$matched$c
"
done < "$ROOT/attested"
[ -n "$matched" ] || exit 1
[ -z "$gate" ] || [ ! -e "$ROOT/gate-fails" ] || exit 1
if [ -n "$fmt$jq" ]; then
  [ "$fmt" = json ] && [ "$jq" = "$AJQ" ] || exit 1
  printf '%s' "$matched"; exit 0
fi
echo "stub-out: gh wrote this to stdout"
exit 0
STUB
chmod +x "${STUBS}/gh"

# stub <args>: the stub's exit code, then a space and its stdout when it printed any, for one call with
# only the stubs on PATH.
stub() {
  local r=0 o
  o="$(env PATH="${STUBS}" "${STUBS}/gh" "$@" 2> /dev/null)" || r=$?
  rm -f "${LOGS}/gh"; echo "${r}${o:+ ${o}}"
}
WANT_SIGNER="github.com/${GH_REPO}/${SIGNER}"
# The calls binary_attest makes, as the log holds them.
TAG_ARGS=(api --hostname github.com "repos/${GH_REPO}/git/ref/tags/v${VERSION}" --jq "${TAG_JQ}")
verify_args() { # <file> [<flag> <value>]...: the attestation verify arguments for <file>, then the flags
  local f="$1"; shift
  VERIFY_ARGS=(attestation verify "${f}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "${WANT_SIGNER}" "$@")
}
gate_call() { # <file> <commit>: the verify that binary_attest's answer rests on
  verify_args "$1" --source-digest "$2" --source-ref "${SOURCE_REF}"; printf '%s\t' "${VERIFY_ARGS[@]}"
}
list_call() { # <file>: binary_attested_at's verify, which lists the commits <file> is attested at
  verify_args "$1" --source-ref "${SOURCE_REF}" --format json --jq "${ATTESTED_JQ}"; printf '%s\t' "${VERIFY_ARGS[@]}"
}
tag_call() { printf '%s\t' "${TAG_ARGS[@]}"; }

# The stub plays gh for the forms the cases below make, and refuses each change a mutation makes.
check "the stub reads the tag's commit" "0 commit ${B}" "$(stub "${TAG_ARGS[@]}")"
check "the stub refuses another version's tag" 1 \
  "$(stub api --hostname github.com "repos/${GH_REPO}/git/ref/tags/v0.31.90" --jq "${TAG_JQ}")"
verify_args "${DL}/${ASSET}" --source-digest "${B}" --source-ref "${SOURCE_REF}"
check "the stub verifies the release at its own commit and ref" "0 stub-out: gh wrote this to stdout" "$(stub "${VERIFY_ARGS[@]}")"
verify_args "${DL}/${ASSET}" --source-digest "${A}" --source-ref "${SOURCE_REF}"
check "the stub refuses the release at another commit" 1 "$(stub "${VERIFY_ARGS[@]}")"
verify_args "${DL}/${ASSET}" --source-digest "${B}" --source-ref "refs/tags/v${VERSION}"
check "the stub refuses the release's tag as its source ref, as gh does for release.yml's builds" 1 "$(stub "${VERIFY_ARGS[@]}")"
release "commit ${B}" "${SOURCE_REF}" "${A}"
verify_args "${DL}/${ASSET}"
check "the stub, as gh, checks no commit when none is asked for" "0 stub-out: gh wrote this to stdout" "$(stub "${VERIFY_ARGS[@]}")"
verify_args "${DL}/${ASSET}" --source-ref "${SOURCE_REF}" --format json --jq "${ATTESTED_JQ}"
check "the stub lists the commits the release is attested at" "0 ${A}" "$(stub "${VERIFY_ARGS[@]}")"
release "commit ${B}" "${SOURCE_REF}" "${B}"
check "the stub refuses the folder in place of the file" 1 \
  "$(stub attestation verify "${DL}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "${WANT_SIGNER}")"
check "the stub refuses another signer" 1 \
  "$(stub attestation verify "${DL}/${ASSET}" --hostname github.com --repo "${GH_REPO}" --signer-workflow "github.com/${GH_REPO}/")"
check "the stub refuses the call without --signer-workflow" 1 \
  "$(stub attestation verify "${DL}/${ASSET}" --hostname github.com --repo "${GH_REPO}")"
# Told to hang, the stub outlives a plain alarm, as gh does: an alarm alone bounds nothing.
echo "attestation 4" > "${HANG_FLAG}"; start=${SECONDS}
r=0; env PATH="${STUBS}" perl -e 'alarm 2; exec @ARGV or exit 127' "${STUBS}/gh" attestation > /dev/null 2>&1 || r=$?
check "a hanging stub outlives a plain 2 s alarm and ends on its own" "0 yes" \
  "${r} $([[ $((SECONDS - start)) -ge 4 ]] && echo yes || echo "no: $((SECONDS - start)) s")"
rm -f "${HANG_FLAG}" "${ROOT}/stub.pid" "${LOGS}/gh"

# attest <file> <signer> <version> [<seconds>]: source the lib and run binary_attest in a new bash with
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
# refused <name> <text>: the last attest returned 1, printed nothing on stdout and one binary: line on
# stderr holding <text>, with none of the stub's output.
refused() {
  check "$1: returns 1" 1 "${rc}"
  check "$1: prints nothing on stdout" "" "${out}"
  check "$1: says one line" 1 "$(lines "${err}")"
  check "$1: the line is binary's and says ${2}" yes \
    "$([[ "${err}" == "binary: "* && "${err}" == *"$2"* ]] && echo yes || echo "no: ${err}")"
  check "$1: none of gh's output" no "$([[ "${out}${err}" == *stub-* ]] && echo yes || echo no)"
}
# FAILED: what the line says when the verify fails for the downloaded file, at the release's commit.
FAILED="gh attestation verify failed for ${DL}/${ASSET}"
AT_B="from ${GH_REPO}'s ${SIGNER} at commit ${B}, v${VERSION}'s tag, is not proven"

# 1. The downloaded release binary, attested at its tag's commit: the tag read, then the verify, each
# exactly the form above, and nothing printed.
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
check "release binary: returns 0" 0 "${rc}"
check "release binary: prints nothing on stdout" "" "${out}"
check "release binary: prints nothing on stderr" "" "${err}"
check "release binary: the tag read, then the verify at its commit and main" \
  "$(tag_call)"$'\n'"$(gate_call "${DL}/${ASSET}" "${B}")" "${calls}"

# 2. The release-commit cases: the asset is attested at commit A, and the tag is at B. binary_attest
# refuses in one line naming the version and both commits; the caller installs nothing (binary_fetch_test.sh
# checks no <copy>/swarm). With the attestation at B it passes.
release "commit ${B}" "${SOURCE_REF}" "${A}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
refused "attested at another commit" "is attested at commit ${A}"
check "attested at another commit: the line names the version and both commits" \
  "binary: ${DL}/${ASSET} is attested at commit ${A}, but v${VERSION}'s tag is at commit ${B}, so it is not v${VERSION}'s binary and it was not run: report it at https://github.com/${GH_REPO}/issues" \
  "${err}"
check "attested at another commit: the tag read, the verify at B, then the list of commits" \
  "$(tag_call)"$'\n'"$(gate_call "${DL}/${ASSET}" "${B}")"$'\n'"$(list_call "${DL}/${ASSET}")" "${calls}"
release "commit ${B}" "${SOURCE_REF}" "${A}" "${C}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
refused "attested at two other commits" "is attested at commit ${A}, ${C}, but v${VERSION}'s tag is at commit ${B}"
release "commit ${B}" "${SOURCE_REF}" "${B}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
check "attested at the tag's commit: returns 0, nothing said" "0|" "${rc}|${err}"
# The same commit, but built from another branch: a release.yml edited there signs with the same path.
release "commit ${B}" refs/heads/other "${B}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
refused "built at the tag's commit from another branch" "${FAILED}, so its build attestation ${AT_B}"
release "commit ${B}" "${SOURCE_REF}" "${B}"

# 3. gh's verify fails: one line, return 1, and one more call to list the commits, which fails too.
: > "${FAILS_FLAG}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
rm -f "${FAILS_FLAG}"
refused "gh fails" "${FAILED}, so its build attestation ${AT_B}"
check "gh fails: the tag read, the verify, then the list" \
  "$(tag_call)"$'\n'"$(gate_call "${DL}/${ASSET}" "${B}")"$'\n'"$(list_call "${DL}/${ASSET}")" "${calls}"

# The verify at B fails, but the list names B: the line says the verify failed, never that the file is
# attested elsewhere.
: > "${GATE_FAILS_FLAG}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
rm -f "${GATE_FAILS_FLAG}"
refused "the verify fails but the list names the tag's commit" "${FAILED}, so its build attestation ${AT_B}"
check "the verify fails but the list names the tag's commit: all three calls ran" 3 "$(lines "${calls}")"

# 4. A file named as the asset whose bytes are not the release's.
cp "${RELEASE}" "${ROOT}/tampered/${ASSET}"; printf 'x' >> "${ROOT}/tampered/${ASSET}"
attest "${ROOT}/tampered/${ASSET}" "${SIGNER}" "${VERSION}"
refused "bytes not the release's" "gh attestation verify failed for ${ROOT}/tampered/${ASSET}"

# 5. The verify hangs: binary_within stops it at the bound, here 1 s, well before the stub's 60 s
# sleep ends, and no list call follows.
echo "attestation 60" > "${HANG_FLAG}"; start=${SECONDS}
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}" 1
took=$((SECONDS - start)); rm -f "${HANG_FLAG}"
refused "verify hangs" "${FAILED} (no answer within 1 s), so"
check "verify hangs: returns well before the stub's sleep ends" yes \
  "$([[ "${took}" -lt 30 ]] && echo yes || echo "no: ${took} s")"
check "verify hangs: the tag read, then the verify, and no list" \
  "$(tag_call)"$'\n'"$(gate_call "${DL}/${ASSET}" "${B}")" "${calls}"
check "verify hangs: the stub ran and is gone" gone \
  "$(p="$(cat "${ROOT}/stub.pid" 2>/dev/null)"
    if [[ -z "${p}" ]]; then echo "no pid written"; elif kill -0 "${p}" 2>/dev/null; then echo alive; else echo gone; fi)"
rm -f "${ROOT}/stub.pid"

# 6. The tag read: it fails, reads as no commit, or hangs. Each is one line, and no verify follows.
TAG_AT="v${VERSION}'s tag at github.com/${GH_REPO}"
: > "${TAG_FAILS_FLAG}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
rm -f "${TAG_FAILS_FLAG}"
refused "tag read fails" "gh api could not read ${TAG_AT} (exit 1), so the commit the binary must be built at is not known"
check "tag read fails: the line names the read to run" yes \
  "$([[ "${err}" == *"run gh api --hostname github.com repos/${GH_REPO}/git/ref/tags/v${VERSION} to see why"* ]] && echo yes || echo "no: ${err}")"
check "tag read fails: only the tag read" "$(tag_call)" "${calls}"
release "tag ${B}" "${SOURCE_REF}" "${B}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
refused "an annotated tag" "${TAG_AT} reads 'tag ${B}', not 'commit <sha>'"
check "an annotated tag: only the tag read" "$(tag_call)" "${calls}"
release "commit ${B:0:12}" "${SOURCE_REF}" "${B}"
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}"
refused "a short commit" "${TAG_AT} reads 'commit ${B:0:12}', not 'commit <sha>'"
release "commit ${B}" "${SOURCE_REF}" "${B}"
echo "api 60" > "${HANG_FLAG}"; start=${SECONDS}
attest "${DL}/${ASSET}" "${SIGNER}" "${VERSION}" 1
took=$((SECONDS - start)); rm -f "${HANG_FLAG}"
refused "tag read hangs" "gh api gave no answer within 1 s for ${TAG_AT}"
check "tag read hangs: returns well before the stub's sleep ends" yes \
  "$([[ "${took}" -lt 30 ]] && echo yes || echo "no: ${took} s")"
check "tag read hangs: only the tag read" "$(tag_call)" "${calls}"
check "tag read hangs: the stub ran and is gone" gone \
  "$(p="$(cat "${ROOT}/stub.pid" 2>/dev/null)"
    if [[ -z "${p}" ]]; then echo "no pid written"; elif kill -0 "${p}" 2>/dev/null; then echo alive; else echo gone; fi)"
rm -f "${ROOT}/stub.pid"

# 7. An empty argument, or a version that is not a plain name, stops before gh. An empty signer matters
# most: an older gh would take github.com/<repo>/ as a prefix that every workflow in the repo matches.
for c in file signer version slash; do
  case "${c}" in
    file) attest "" "${SIGNER}" "${VERSION}" ;;
    signer) attest "${DL}/${ASSET}" "" "${VERSION}" ;;
    version) attest "${DL}/${ASSET}" "${SIGNER}" "" ;;
    slash) attest "${DL}/${ASSET}" "${SIGNER}" "0.31.91/../../x" ;;
  esac
  check "bad ${c}: returns 1" 1 "${rc}"
  check "bad ${c}: prints nothing on stdout" "" "${out}"
  check "bad ${c}: says one binary: line" "1 yes" "$(lines "${err}") $([[ "${err}" == "binary: "* ]] && echo yes || echo no)"
  check "bad ${c}: no gh call" "" "${calls}"
done

[[ "${fails}" -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all binary_attest checks passed"
