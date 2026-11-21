#!/usr/bin/env bash
# publish_release_test.sh — scripts/publish-release.sh plan, run as a program in a fixture git repo, with
# gh a stub on PATH. The stub answers `gh api [--paginate] <path>` from ${FX}/<path, its / ? and = made _>:
# a .404 file answers as real gh does on a 404 (exit 1, `gh: Not Found (HTTP 404)` on stderr, the JSON
# body on stdout), a .502 file fails the read, and a .p2 file is a second page, which only --paginate
# gets, merged into one array as real gh merges them. It logs each call and fails any call it has no
# fixture for, which fails the case. A push with no bump writes steps=none and makes no gh call. A bump
# with no tag, no release and the branch behind writes draft attach publish move and tag=v<version>,
# with BEFORE all zeros or empty too; with the branch at the pushed commit or past it, the same without
# move. Every refusal prints exactly its one line, writes nothing and exits 1: with no gh call, a
# version that is not MAJOR.MINOR.PATCH (a newline at its end included), one not greater than BEFORE's,
# and an empty one with BEFORE all zeros (only a readable BEFORE can make a push no bump); then an
# annotated tag, a tag on another commit, a tag at the pushed commit, a release for the version (on the
# list's second page), a missing or diverged branch, a failed read of the tag, the branch, the compare
# or the releases, and a 404 on the releases.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO}/scripts/publish-release.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
G="${tmp}/repo"; FX="${tmp}/fx"; LOG="${tmp}/calls"; fails=0
ZEROS=0000000000000000000000000000000000000000

check() { # <name> <got> <exact expected>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

mkdir -p "${tmp}/bin" "${FX}"
cat > "${tmp}/bin/gh" <<STUB
#!/usr/bin/env bash
FX="${FX}"; LOG="${LOG}"
STUB
cat >> "${tmp}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
none() { echo "stub: no fixture for gh $*" >&2; echo "gh $*" >> "${LOG}.unexpected"; exit 1; }
[ "${1:-}" = api ] || none "$@"
paginate=""
if [ "${2:-}" = --paginate ]; then paginate=1; set -- "$1" "$3" "${@:4}"; fi
[ "$#" -eq 2 ] || none "$@"
f="${FX}/$(printf '%s' "$2" | tr '/?=' '___')"
if [ -e "${f}.404" ]; then
  echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest/git/refs#get-a-reference","status":"404"}'
  echo 'gh: Not Found (HTTP 404)' >&2; exit 1
fi
if [ -e "${f}.502" ]; then echo 'gh: Bad Gateway (HTTP 502)' >&2; exit 1; fi
[ -e "${f}" ] || none "$@"
if [ -n "${paginate}" ] && [ -e "${f}.p2" ]; then jq -s add "${f}" "${f}.p2"; else cat "${f}"; fi
STUB
chmod +x "${tmp}/bin/gh"

# The fixture: BASE holds 1.0.0, BUMP (the pushed commit of a release) 1.1.0, and NOBUMP, SHORT, LOWER,
# EMPTY and NEWLINE, each off BASE, hold 1.0.0 with another change, 1.2, 0.9.0, an empty version and
# 1.1.0 with a newline at its end, which $(...) would strip.
git init -q -b main "${G}"
git -C "${G}" config commit.gpgsign false   # a fixture commit never reaches the user's signer
mkdir -p "${G}/.claude-plugin"
version() { echo "{\"name\": \"p\", \"version\": \"$1\"}" > "${G}/.claude-plugin/plugin.json"; }
commit() { git -C "${G}" add -A; git -C "${G}" commit -qm "$1"; git -C "${G}" rev-parse HEAD; }
version 1.0.0; BASE="$(commit base)"
version 1.1.0; BUMP="$(commit bump)"
git -C "${G}" checkout -q "${BASE}"; echo more > "${G}/x"; NOBUMP="$(commit nobump)"
git -C "${G}" checkout -q "${BASE}"; version 1.2; SHORT="$(commit short)"
git -C "${G}" checkout -q "${BASE}"; version 0.9.0; LOWER="$(commit lower)"
git -C "${G}" checkout -q "${BASE}"; version ""; EMPTY="$(commit empty)"
git -C "${G}" checkout -q "${BASE}"; version '1.1.0\n'; NEWLINE="$(commit newline)"

# fx <path> [suffix] — the stub's file for <path> (and its .404, .502 or .p2 file).
fx() { echo "${FX}/$(printf '%s' "$1" | tr '/?=' '___')${2:+.$2}"; }
TAG_PATH=repos/o/r/git/ref/tags/v1.1.0
REF_PATH=repos/o/r/git/ref/heads/prerelease
CMP_PATH="repos/o/r/compare/${BASE}...${BUMP}"
REL_PATH='repos/o/r/releases?per_page=100'
release() { echo "{\"tag_name\": \"$1\", \"draft\": $2}"; }
# fixtures — the state of a new release: no tag, prerelease at BASE and behind BUMP, and two pages of
# releases with none for v1.1.0, only tags that a loose match would take for it.
fixtures() {
  rm -rf "${FX}"; mkdir -p "${FX}"
  : > "$(fx "${TAG_PATH}" 404)"
  echo "{\"ref\": \"refs/heads/prerelease\", \"object\": {\"type\": \"commit\", \"sha\": \"${BASE}\"}}" > "$(fx "${REF_PATH}")"
  echo '{"status": "ahead"}' > "$(fx "${CMP_PATH}")"
  echo "[$(release v1.1.0-rc1 true), $(release v1.0.0 false)]" > "$(fx "${REL_PATH}")"
  echo "[$(release v1.1.00 false), $(release v1.1 false)]" > "$(fx "${REL_PATH}" p2)"
}
tag_at() { # <type> <sha> — the tag v1.1.0 exists, its object of <type> at <sha>
  rm -f "$(fx "${TAG_PATH}" 404)"
  echo "{\"ref\": \"refs/tags/v1.1.0\", \"object\": {\"type\": \"$1\", \"sha\": \"$2\"}}" > "$(fx "${TAG_PATH}")"
}

# plan <sha> [VAR=value]... — run plan in the fixture at <sha> (checked out there, as release.yml checks
# out the pushed commit) with BEFORE=BASE and REF unset unless a VAR says otherwise. It sets RC, OUT (what
# it wrote to GITHUB_OUTPUT), SAID (what it printed, both streams), CALLS (the stub's log) and UNEXPECTED
# (the calls the stub had no fixture for).
plan() {
  local sha="$1"; shift
  : > "${tmp}/out"; : > "${LOG}"; : > "${LOG}.unexpected"
  git -C "${G}" checkout -q --detach "${sha}"
  RC=0
  (cd "${G}" && env -u REF PATH="${tmp}/bin:${PATH}" REPO=o/r SHA="${sha}" BEFORE="${BASE}" \
    GITHUB_OUTPUT="${tmp}/out" "$@" "${SCRIPT}" plan > "${tmp}/said" 2>&1) || RC=$?
  OUT="$(cat "${tmp}/out")"; SAID="$(cat "${tmp}/said")"; CALLS="$(cat "${LOG}")"; UNEXPECTED="$(cat "${LOG}.unexpected")"
}
# planned <name> <steps> — plan exited 0, wrote steps=<steps> and, unless none, tag=v1.1.0, and said why
# on one line, with no call the stub had no fixture for.
planned() {
  local want="steps=$2"
  [ "$2" = none ] || want+=$'\n'"tag=v1.1.0"
  local said="${SAID%%$'\n'*}"
  [[ "${SAID}" != *$'\n'* && "${said}" == "publish-release: steps=$2 ("*")" ]] || said="said: ${SAID}"
  check "$1" "exit ${RC}|${OUT}|${said%% (*}|${UNEXPECTED}" "exit 0|${want}|publish-release: steps=$2|"
}
# refused <name> <why> — plan exited 1, said exactly `publish-release: <why>` and wrote nothing, with no
# call the stub had no fixture for.
refused() {
  check "$1" "exit ${RC}|${OUT}|${SAID}|${UNEXPECTED}" "exit 1||publish-release: $2|"
}

fixtures
plan "${NOBUMP}"
planned "a push whose version is BEFORE's plans none" none
check "a push with no bump makes no gh call" "${CALLS}" ""

plan "${BUMP}"
planned "a bump with no tag, no release and the branch behind plans every step" "draft attach publish move"
check "the plan reads the branch, the compare, the tag and every page of the releases, in that order" "${CALLS}" \
  "api ${REF_PATH}
api ${CMP_PATH}
api ${TAG_PATH}
api --paginate ${REL_PATH}"
plan "${BUMP}" BEFORE="${ZEROS}"
planned "a bump whose BEFORE is all zeros plans every step" "draft attach publish move"
plan "${BUMP}" BEFORE=
planned "a bump with an empty BEFORE plans every step" "draft attach publish move"

echo '{"status": "identical"}' > "$(fx "${CMP_PATH}")"
plan "${BUMP}"
planned "a bump with the branch at the pushed commit drops move" "draft attach publish"
echo '{"status": "behind"}' > "$(fx "${CMP_PATH}")"
plan "${BUMP}"
planned "a bump with the branch past the pushed commit drops move" "draft attach publish"

fixtures
plan "${SHORT}"
refused "a version that is not MAJOR.MINOR.PATCH refuses" "the version \"1.2\" at ${SHORT:0:7} is not MAJOR.MINOR.PATCH"
check "a version that is not MAJOR.MINOR.PATCH makes no gh call" "${CALLS}" ""
plan "${LOWER}"
refused "a version lower than BEFORE's refuses" "the version 0.9.0 at ${LOWER:0:7} is not greater than BEFORE's 1.0.0"
check "a version lower than BEFORE's makes no gh call" "${CALLS}" ""
plan "${NEWLINE}"
refused "a version with a newline at its end refuses" "the version \"1.1.0\\n\" at ${NEWLINE:0:7} is not MAJOR.MINOR.PATCH"
plan "${EMPTY}" BEFORE="${ZEROS}"
refused "an empty version with BEFORE all zeros is a bump, and refuses" "the version \"\" at ${EMPTY:0:7} is not MAJOR.MINOR.PATCH"

tag_at tag "${BUMP}"
plan "${BUMP}"
refused "an annotated tag refuses" "the tag v1.1.0 is an annotated tag (its object is a tag), and a release tags the commit itself"
tag_at commit "${BASE}"
plan "${BUMP}"
refused "a tag on another commit refuses" "the tag v1.1.0 is on ${BASE:0:7}, not ${BUMP:0:7}: that version was released from another commit"
tag_at commit "${BUMP}"
plan "${BUMP}"
refused "a tag at the pushed commit refuses" "the tag v1.1.0 is already at ${BUMP:0:7}: its release exists, and plan does not finish one"

fixtures
echo "[$(release v1.1.00 false), $(release v1.1.0 true)]" > "$(fx "${REL_PATH}" p2)"
plan "${BUMP}"
refused "a release for the version, on the list's second page, refuses" "v1.1.0 already has a draft: its release exists, and plan does not finish one"

fixtures
rm "$(fx "${REF_PATH}")"; : > "$(fx "${REF_PATH}" 404)"
plan "${BUMP}"
refused "a missing branch, with no tag and no release, refuses" "the branch prerelease does not exist, and a release never creates it"
fixtures
echo '{"status": "diverged"}' > "$(fx "${CMP_PATH}")"
plan "${BUMP}"
refused "a diverged branch, with no tag and no release, refuses" \
  "the branch prerelease at ${BASE:0:7} has diverged from ${BUMP:0:7}, and a release only moves it forward"

fixtures
rm "$(fx "${TAG_PATH}" 404)"; : > "$(fx "${TAG_PATH}" 502)"
plan "${BUMP}"
refused "a failed read of the tag refuses" "gh cannot read the tag v1.1.0: exit 1, gh: Bad Gateway (HTTP 502)"
fixtures
: > "$(fx "${REF_PATH}" 502)"
plan "${BUMP}"
refused "a failed read of the branch refuses" "gh cannot read the branch prerelease: exit 1, gh: Bad Gateway (HTTP 502)"
fixtures
: > "$(fx "${CMP_PATH}" 502)"
plan "${BUMP}"
refused "a failed read of the compare refuses" "gh cannot read prerelease compared with ${BUMP:0:7}: exit 1, gh: Bad Gateway (HTTP 502)"
fixtures
: > "$(fx "${REL_PATH}" 502)"
plan "${BUMP}"
refused "a failed read of the releases refuses" "gh cannot read the releases: exit 1, gh: Bad Gateway (HTTP 502)"
fixtures
: > "$(fx "${REL_PATH}" 404)"
plan "${BUMP}"
refused "a 404 on the releases refuses, as only the tag and branch reads take a 404 as an answer" \
  "gh cannot read the releases: exit 1, gh: Not Found (HTTP 404)"

[ "${fails}" -eq 0 ] || { echo "${fails} failed"; exit 1; }
echo "all passed"
