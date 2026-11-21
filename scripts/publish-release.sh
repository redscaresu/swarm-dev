#!/usr/bin/env bash
# publish-release.sh — what release.yml does for a push to main.
#
#   scripts/publish-release.sh plan
#
# Env, as scripts/board-only.sh takes it: REPO (owner/name), SHA (the pushed commit), BEFORE (the push's
# previous tip, github.event.before), REF (the branch a release moves, default prerelease) and
# GITHUB_OUTPUT; gh reads GH_TOKEN. Run it in a checkout that holds SHA and BEFORE: it reads the version
# in .claude-plugin/plugin.json at each with git show and jq.
#
# plan writes, on success, exactly one steps= line to GITHUB_OUTPUT, either none or the steps to take in
# this order, a subset of draft attach publish move, and, unless none, one tag=v<version> line. It prints
# one line saying why. On a refusal it prints one `publish-release: <why>` line, writes nothing to
# GITHUB_OUTPUT and exits 1, so a step is never printed on an error. It decides, in this order:
# - No bump: the version at SHA is BEFORE's. steps=none, with no gh call. That is every push but a
#   release's, so a gh blip never turns main red there, and a later push never trips over a half-done
#   release of an earlier commit. A BEFORE that git cannot read (a new branch's all zeros), or whose
#   version is no MAJOR.MINOR.PATCH to compare with, counts as a bump, so the checks below still run.
# - A bump refuses a version at SHA that is not MAJOR.MINOR.PATCH, or that is not greater than BEFORE's.
# - REF (ref_move): it must exist, as plan never creates it. Its commit is compared with SHA (by its SHA,
#   so both reads see the same commit): REF behind SHA keeps move; REF at SHA or past it drops move; a
#   REF that has diverged refuses. It is read before the tag and the releases, so a release that cannot
#   move is never drafted.
# - The tag v<version>: no tag is the only state plan publishes from. An annotated tag refuses, and so
#   does a tag on another commit (that version was released elsewhere) and a tag at SHA (the release
#   exists).
# - The releases, every page, matched by exact tag_name: none for v<version> gives draft attach publish,
#   and move when ref_move keeps it. Any release for v<version> exists already and refuses, naming it.
# A draft has no tag yet, and only a token with write access sees drafts in the releases list. So a
# plan run with a read-only token cannot see one: the publish job's plan, run with its write token, is
# the one the workflow acts on.
# Every gh read goes through gh_read. A 404 is an answer only on the tag and REF reads; any other
# failure refuses, and a re-run of the job, once the failure has passed, plans again. plan sets no
# timeout on a gh call, so the calling job's timeout bounds it. plan only reads, so two runs at once do
# not disturb each other, but both can plan draft for the same version: the workflow that calls plan
# must run one publish at a time.
set -euo pipefail

PLUGIN=.claude-plugin/plugin.json
SEMVER='^"[0-9]+\.[0-9]+\.[0-9]+"$'   # a version as version_at prints it
SHA_RE='^[0-9a-f]{40}$'
NEW_RELEASE="draft attach publish"
MOVE_STEP=move

usage() { echo "usage: scripts/publish-release.sh plan" >&2; exit 2; }

# refuse <why> — say why on one line and stop, having written nothing to GITHUB_OUTPUT.
refuse() {
  local why="$1"
  echo "publish-release: ${why//$'\n'/ }"
  exit 1
}

# answer <steps> <why> — write the plan to GITHUB_OUTPUT, say why on one line, and stop.
answer() {
  local out="${GITHUB_OUTPUT:-/dev/null}" lines="steps=$1"
  [ "$1" = none ] || lines+=$'\n'"tag=${TAG}"
  printf '%s\n' "${lines}" >> "${out}" || refuse "cannot write the plan to GITHUB_OUTPUT"
  local why="$2"
  echo "publish-release: steps=$1 (${why//$'\n'/ })"
  exit 0
}

# gh_read <what> <404|-> <gh api argument>... — every gh call plan makes. It sets BODY to gh's output and
# returns 0. When the second argument is 404 and gh found nothing there, it returns 1: real gh then exits
# 1 with `HTTP 404` on stderr (it prints `gh: Not Found (HTTP 404)`). Any other failure refuses, naming
# <what>.
gh_read() {
  local what="$1" on404="$2" rc=0 err
  shift 2
  BODY="$(gh api "$@" 2> "${TMP}/gh.err")" || rc=$?
  [ "${rc}" -ne 0 ] || return 0
  if [ "${on404}" = 404 ] && [ "${rc}" -eq 1 ] && grep -q 'HTTP 404' "${TMP}/gh.err"; then return 1; fi
  err="$(head -n 1 "${TMP}/gh.err" | tr -d '\r')"
  refuse "gh cannot read ${what}: exit ${rc}${err:+, ${err}}"
}

# version_at <commit> — print the version string in plugin.json at <commit> as JSON, quotes and escapes
# kept, so $(...) strips no newline off its end and a refusal stays one line; fail when git cannot read
# the file, it is not JSON or its version is not a string.
version_at() {
  git show "$1:${PLUGIN}" 2> /dev/null | jq -er '.version | strings | @json' 2> /dev/null
}

# greater <a> <b> — 0 when MAJOR.MINOR.PATCH <a> is greater than <b>, comparing each part as a number.
greater() {
  jq -en --arg a "$1" --arg b "$2" '[$a, $b] | map(split(".") | map(tonumber)) | .[0] > .[1]' > /dev/null 2>&1
}

# ref_move — set MOVE to move when REF's commit is behind SHA, and to nothing when REF is at SHA or past
# it, and REF_WHY to a phrase saying which. Refuses when REF is missing or has diverged from SHA.
ref_move() {
  local status ref_at
  gh_read "the branch ${REF}" 404 "repos/${REPO}/git/ref/heads/${REF}" \
    || refuse "the branch ${REF} does not exist, and a release never creates it"
  ref_at="$(jq -r --arg r "refs/heads/${REF}" 'select(.ref == $r and .object.type == "commit") | .object.sha' \
    <<< "${BODY}" 2> /dev/null)" || ref_at=""
  [[ "${ref_at}" =~ ${SHA_RE} ]] || refuse "gh's answer for the branch ${REF} names no commit"
  gh_read "${REF} compared with ${SHA:0:7}" - "repos/${REPO}/compare/${ref_at}...${SHA}"
  status="$(jq -r '.status | strings' <<< "${BODY}" 2> /dev/null)" || status=""
  case "${status}" in
    ahead) MOVE="${MOVE_STEP}" REF_WHY="${REF} at ${ref_at:0:7} is behind it" ;;
    identical) MOVE="" REF_WHY="${REF} is at it already" ;;
    behind) MOVE="" REF_WHY="${REF} at ${ref_at:0:7} is past it" ;;
    diverged) refuse "the branch ${REF} at ${ref_at:0:7} has diverged from ${SHA:0:7}, and a release only moves it forward" ;;
    *) refuse "gh's compare of ${REF} with ${SHA:0:7} has no status a release knows: '${status}'" ;;
  esac
}

# no_tag — return when the tag v<version> does not exist; refuse, naming it, when it does.
no_tag() {
  local at kind sha
  gh_read "the tag ${TAG}" 404 "repos/${REPO}/git/ref/tags/${TAG}" || return 0
  at="$(jq -r --arg r "refs/tags/${TAG}" 'select(.ref == $r) | "\(.object.type) \(.object.sha)"' \
    <<< "${BODY}" 2> /dev/null)" || at=""
  [[ "${at}" == *" "* ]] || refuse "gh's answer for the tag ${TAG} names no object"
  kind="${at%% *}" sha="${at#* }"
  [ "${kind}" = commit ] \
    || refuse "the tag ${TAG} is an annotated tag (its object is a ${kind}), and a release tags the commit itself"
  [ "${sha}" != "${SHA}" ] \
    || refuse "the tag ${TAG} is already at ${SHA:0:7}: its release exists, and plan does not finish one"
  refuse "the tag ${TAG} is on ${sha:0:7}, not ${SHA:0:7}: that version was released from another commit"
}

# no_release — return when no release, draft or published, has the tag_name v<version>; refuse,
# naming each, when one does.
no_release() {
  local found
  gh_read "the releases" - --paginate "repos/${REPO}/releases?per_page=100"
  found="$(jq -rs --arg t "${TAG}" '
    if length > 0 and all(.[]; type == "array") then
      [.[][] | select(type == "object" and .tag_name == $t) | if .draft then "a draft" else "a published release" end]
      | join(", ")
    else error("not a list") end' <<< "${BODY}" 2> /dev/null)" \
    || refuse "gh's answer for the releases is not a list of releases"
  [ -z "${found}" ] || refuse "${TAG} already has ${found}: its release exists, and plan does not finish one"
}

plan() {
  local new old=""
  [[ "${SHA:-}" =~ ${SHA_RE} ]] || refuse "SHA '${SHA:-}' is not a commit SHA"
  [[ "${REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || refuse "REPO '${REPO:-}' is not owner/name"
  REF="${REF:-prerelease}"
  [[ "${REF}" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] || refuse "REF '${REF}' is not a branch name"
  command -v jq > /dev/null || refuse "jq is not installed"
  new="$(version_at "${SHA}")" || refuse "cannot read the version in ${PLUGIN} at ${SHA:0:7}"
  if [[ "${BEFORE:-}" =~ ${SHA_RE} ]] && old="$(version_at "${BEFORE}")"; then
    [ "${new}" != "${old}" ] || answer none "the version ${new} at ${SHA:0:7} is BEFORE's: no bump"
  else
    old=""
  fi
  [[ "${new}" =~ ${SEMVER} ]] || refuse "the version ${new} at ${SHA:0:7} is not MAJOR.MINOR.PATCH"
  new="${new//\"/}"
  TAG="v${new}"
  if [[ "${old}" =~ ${SEMVER} ]] && ! greater "${new}" "${old//\"/}"; then
    refuse "the version ${new} at ${SHA:0:7} is not greater than BEFORE's ${old//\"/}"
  fi
  TMP="$(mktemp -d)" || refuse "mktemp -d failed"
  trap 'rm -rf "${TMP}"' EXIT
  ref_move
  no_tag
  no_release
  answer "${NEW_RELEASE}${MOVE:+ ${MOVE}}" "${TAG} at ${SHA:0:7} has no tag and no release; ${REF_WHY}"
}

[ "$#" -eq 1 ] && [ "$1" = plan ] || usage
plan
