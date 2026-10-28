#!/usr/bin/env bash
# unmerged_conflict_test.sh — wait --lead's `unmerged:` and `conflict:` lines, read from every open story
# PR (open_story_prs, on the heads pass), not only the review items lead_heads reads. Under merge = agent and
# merge = human, with the PRs' stories building, in review, kept and with no build, it reads the queue once
# (`swarm.sh wait --lead 0`) over one repo's open PRs: one reviewed on its head, green, mergeable and old
# (unmerged:, except for a kept story or one with a merge: line), one whose review lists findings (unmerged:
# with a triage exit), one conflicting (conflict:), and ones that give neither: reviewed on an older head,
# not reviewed, opened under queue_minutes ago, reviewed under queue_minutes ago, a check failed, only a
# commit status with no check run, a lead story's, a done story's and a fork's. Then each line wakes the lead once,
# stands through a gh failure, a timeout and an UNKNOWN mergeable, wakes it again once it comes back, and
# comes on a run's first read; polls between heads passes make no gh call; a PR swarm.sh merge is merging
# gets no unmerged:; a failed read warns once it has failed SWARM_LEAD_PRS_WARN_AFTER passes in a row. Last,
# with two repos, a story/<slug> PR counts only in its story's own repo.
# gh is a stub whose repo view names the origin's owner/repo and whose pr list prints ${ROOT}/prs.json
# (failing while ${ROOT}/gh-fail exists, hanging while ${ROOT}/gh-slow does), logging each call; herdr a
# stub listing ${ROOT}/agents.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${HOME_DIR}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111; OLD=2222222222222222222222222222222222222222
# The PRs' owner, this run's own: wait --lead reads every process for a swarm.sh merge of a PR's URL, and
# the merge this test starts must not reach another run of it.
O="ucl-$$"
QM=600; OLD_MIN=1200   # queue_minutes, and the age of an old PR or review, in minutes
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin"
git -C "${P}" init -q
git -C "${P}" remote add origin https://github.com/${O}/ucl-repo.git
# A second repo beside the project, where repos_dir finds it: story x's (repo: other).
git -C "${ROOT}" init -q other
git -C "${ROOT}/other" remote add origin git@github.com:${O}/ucl-other.git

printf '#!/bin/sh\nR="%s"\nO="%s"\n' "${ROOT}" "${O}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${R}/gh.log"
case "$*" in
  "repo view "*ucl-other*) echo "${O}/ucl-other" ;;
  "repo view "*) echo "${O}/ucl-repo" ;;
  # open_story_prs' list, told apart by its fields from other reads of the open PRs (close_heads').
  "pr list -R ${O}/ucl-other "*"--json url,headRefName,headRefOid,"*) cat "${R}/prs-other.json" ;;
  "pr list"*"--json url,headRefName,headRefOid,"*)
    [ ! -e "${R}/gh-fail" ] || exit 1
    # One process, so a kill of the call ends it: a shell would outlive its killed sleep on macOS.
    [ ! -e "${R}/gh-slow" ] || exec perl -e 'sleep 20; open my $f, ">", shift' "${R}/slow-done"
    cat "${R}/prs.json" ;;
  "pr list"*) echo '[]' ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") printf '{"result":{"agents":[%s]}}\n' "$(cat "${R}/agents" 2>/dev/null)" ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

LISTS='^pr list .*--json url,headRefName,headRefOid,'   # open_story_prs' gh pr list in gh.log
fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
ago() { perl -MPOSIX -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - 60 * shift))' "$1"; }
url() { echo "https://github.com/${O}/ucl-repo/pull/$1"; }
# findings <slug> <head> <minutes ago> [finding] — a findings file that passes on <head>, written that long
# ago, its findings none or the one given.
findings() {
  printf 'head: %s\n\n## Findings\n\n%s\n\n## Out of scope\n\nnone\n' "$2" "${4:-none}" > "${P}/.swarm/reviews/$1.md"
  perl -e 'my $t = time - 60 * shift; utime $t, $t, shift' "$3" "${P}/.swarm/reviews/$1.md"
}
# pr <n> <slug> <head> <mergeable> <conclusion> <minutes open> — one PR of gh pr list's JSON: a check run
# with that conclusion and a passed commit status; with conclusion -, the status alone.
pr() {
  local run='{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"'"$5"'"},'   # vacuous-test: ok, a fragment pr's printf completes
  [[ "$5" != - ]] || run=""
  printf '{"url":"%s","headRefName":"story/%s","headRefOid":"%s","mergeable":"%s","createdAt":"%s","statusCheckRollup":[%s{"__typename":"StatusContext","context":"ci","state":"SUCCESS"}]}' \
    "$(url "$1")" "$2" "$3" "$4" "$(ago "$6")" "${run}"
}
# The PRs: a (reviewed, old: unmerged), c (conflicting, not reviewed, so quiet once it clears),
# o (reviewed on an older head), n (not reviewed),
# y (opened 5 minutes ago), r (reviewed 5 minutes ago), f (a check failed), s (a status, no check run),
# one whose story is not on the board, one on a branch that is no story's, l (a lead story's, conflicting),
# d (a done story's, conflicting), t (reviewed and old, its review listing a finding) and a fork's PR on
# story/n, conflicting.
prs() {
  printf '[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s]\n' "$(pr 14 n "${H}" CONFLICTING SUCCESS "${OLD_MIN}" | sed 's/^{/{"isCrossRepository":true,/')" "$(pr 11 l "${H}" CONFLICTING SUCCESS "${OLD_MIN}")" \
    "$(pr 12 d "${H}" CONFLICTING SUCCESS "${OLD_MIN}")" "$(pr 13 t "${H}" MERGEABLE SUCCESS "${OLD_MIN}")" "$(pr 7 f "${H}" MERGEABLE FAILURE "${OLD_MIN}")" "$(pr 8 s "${H}" MERGEABLE - "${OLD_MIN}")" \
    "$(pr 1 a "${H}" MERGEABLE SUCCESS "${OLD_MIN}")" "$(pr 2 c "${H}" "${1:-CONFLICTING}" SUCCESS "${OLD_MIN}")" \
    "$(pr 3 o "${H}" MERGEABLE SUCCESS "${OLD_MIN}")" "$(pr 4 n "${H}" MERGEABLE SUCCESS "${OLD_MIN}")" "$(pr 5 y "${H}" MERGEABLE SUCCESS 5)" \
    "$(pr 6 r "${H}" MERGEABLE SUCCESS "${OLD_MIN}")" "$(pr 9 gone "${H}" CONFLICTING SUCCESS "${OLD_MIN}")" \
    '{"url":"'"$(url 10)"'","headRefName":"fix/x","headRefOid":"'"${H}"'","mergeable":"CONFLICTING","createdAt":"'"$(ago "${OLD_MIN}")"'","statusCheckRollup":[]}' \
    > "${ROOT}/prs.json"
}

# board <merge> <state> — stories a c o n y r f s t, each in <state>: building (ready, its builder working),
# review, kept, or nobuild (ready, never started); l, a lead story, and d, a done one, beside them.
board() {
  local e s n
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/lead" "${P}/.swarm/reviews" "${ROOT}/agents" \
    "${P}/.swarm/state/tab" "${ROOT}/gh-fail" "${ROOT}/gh-slow" "${ROOT}/slow-done" "${ROOT}/gh.log"
  mkdir -p "${P}/.swarm/lead" "${P}/.swarm/reviews"; : > "${P}/.swarm/lead/seen"
  # queue_minutes far above any run's length: on a loaded machine a young PR here must not age past it.
  printf 'merge = %s\nqueue_minutes = %s\n' "$1" "${QM}" > "${P}/.claude/swarm/config"
  for e in a:1 c:2 o:3 n:4 y:5 r:6 f:7 s:8 t:13; do
    s="${e%%:*}"; n="${e#*:}"
    { echo ---; echo "kind: code"
      case "$2" in
        building|nobuild) echo "status: ready" ;;
        review) echo "status: review"; echo "prs: $(url "${n}")" ;;
        kept) echo "status: review"; echo "prs: $(url "${n}")"; echo "kept: 2026-10-25 close stalled (not reviewed)" ;;
      esac
      echo ---; echo; echo "# ${s}"; } > "${B}/${s}.md"
    if [[ "$2" == building ]]; then
      printf '%s\tstory\t%s\t-\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${s}" >> "${P}/.swarm/events.tsv"
      echo "w:p${n} ${s}" >> "${P}/.swarm/state/tab"
      printf '%s{"name":"%s","agent_status":"working","pane_id":"w:p%s"}' "$([[ ${n} -gt 1 ]] && echo ,)" "${s}" "${n}" >> "${ROOT}/agents"
    fi
  done
  printf -- '---\nkind: lead\nstatus: ready\n---\n\n# l\n' > "${B}/l.md"
  printf -- '---\nkind: code\nstatus: done\n---\n\n# d\n' > "${B}/d.md"
  findings a "${H}" "${OLD_MIN}"; findings o "${OLD}" "${OLD_MIN}"; findings y "${H}" "${OLD_MIN}"; findings r "${H}" 5
  findings f "${H}" "${OLD_MIN}"; findings s "${H}" "${OLD_MIN}"; findings t "${H}" "${OLD_MIN}" "- codex, a.sh:1: a bug"
  prs
}

# lead [VAR=value...] — one wait --lead run with those settings, its timeout LEAD_MS (0: one read). Each gh
# read may take 600 s unless a setting says otherwise: a loaded machine can take 30 s to start the stub.
lead() { (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 SWARM_LEAD_PRS_WAIT=600 "$@" bash "${SWARM}" wait --lead "${LEAD_MS:-0}" 2>&1) || true; }
has() { grep -qxF "$1" <<< "$2"; }
# silent <name> — read the queue once; the check passes when it prints nothing, and shows what it printed.
silent() { local got; got="$(lead "${@:2}")"; check "$1" test -z "${got}"; [[ -z "${got}" ]] || printf '       got: %s\n' "${got//$'\n'/$'\n'       got: }"; }
none() { ! grep -q "^$1" <<< "$2"; }

UA="unmerged: a $(url 1), exit: swarm.sh merge --head ${H} $(url 1)"
UT="unmerged: t $(url 13), exit: triage .swarm/reviews/t.md, then swarm.sh merge --head ${H} $(url 13) once every finding is declined"
CC="conflict: c $(url 2), exit: tell its builder to merge the base in"
for mode in agent human; do
  for state in building review kept nobuild; do
    board "${mode}" "${state}"
    out="$(lead)"
    at="(merge = ${mode}, ${state})"
    if [[ "${state}" == kept ]]; then
      check "no unmerged: for a kept story's PR, whose kept: line comes first ${at}" none "unmerged: a " "${out}"
    elif [[ "${state}" == review && "${mode}" == human ]]; then
      check "no unmerged: for a PR that already has a merge: line ${at}" none "unmerged: a " "${out}"
    else
      check "unmerged: names a PR reviewed on its head, green, mergeable and open past queue_minutes ${at}" has "${UA}" "${out}"
      check "unmerged: for a review that lists findings says to triage them first ${at}" has "${UT}" "${out}"
    fi
    check "conflict: names a PR conflicting with its base ${at}" has "${CC}" "${out}"
    check "no conflict: for a MERGEABLE PR ${at}" none "conflict: a " "${out}"
    check "no unmerged: for a PR reviewed on an older head ${at}" none "unmerged: o " "${out}"
    check "no unmerged: for a mergeable PR not reviewed ${at}" none "unmerged: n " "${out}"
    check "no unmerged: for a PR opened under queue_minutes ago ${at}" none "unmerged: y " "${out}"
    check "no unmerged: for a PR reviewed under queue_minutes ago ${at}" none "unmerged: r " "${out}"
    check "no unmerged: for a PR whose check failed ${at}" none "unmerged: f " "${out}"
    check "no unmerged: for a PR with a passed status but no check run ${at}" none "unmerged: s " "${out}"
    check "no line for a story/ PR whose story is not on the board ${at}" none "conflict: gone " "${out}"
    check "no line for a lead story's PR ${at}" none "conflict: l " "${out}"
    check "no line for a done story's PR ${at}" none "conflict: d " "${out}"
    check "no line for a fork's PR on a story's branch ${at}" none "conflict: n " "${out}"
    check "one gh repo view and one gh pr list per repo a heads pass ${at}" \
      test "$(grep -c '^repo view' "${ROOT}/gh.log") $(grep -c "${LISTS}" "${ROOT}/gh.log")" == "1 1"
  done
done

# Once per occurrence: the same queue again wakes no one; a gh failure or an UNKNOWN mergeable keeps
# the lines; a conflict that clears and comes back wakes the lead again.
board agent review; lead >/dev/null
silent "a second read of the same queue prints neither line again"
rm -f "${ROOT}/gh.log"; LEAD_MS=3500 lead SWARM_LEAD_POLL=1 SWARM_LEAD_HEADS_EVERY=3600 >/dev/null
check "polls between heads passes make no gh pr list" test "$(grep -c "${LISTS}" "${ROOT}/gh.log")" -eq 1
# A swarm.sh merge at work on a's PR, as one waiting in a merge queue is: no unmerged: for it.
grep -vxF "${UA}" "${P}/.swarm/lead/seen" > "${ROOT}/seen" || true; cp "${ROOT}/seen" "${P}/.swarm/lead/seen"
perl -e 'sleep 600' 'swarm.sh merge' "$(url 1)" & mpid=$!
out="$(lead)"; kill "${mpid}" 2>/dev/null || true; wait "${mpid}" 2>/dev/null || true
check "no unmerged: for a PR a swarm.sh merge is merging" none "unmerged: a " "${out}"
lead >/dev/null
touch "${ROOT}/gh-fail"
silent "a repo gh cannot list wakes no one"
check "its lines stand in the queue through the failure" has "${UA}" "$(cat "${P}/.swarm/lead/seen")"
check "a read that has failed SWARM_LEAD_PRS_WARN_AFTER passes in a row warns" \
  grep -q "^warning: wait --lead could not read the open PRs of the project's repo on 1 heads passes in a row" <<< "$(lead SWARM_LEAD_PRS_WARN_AFTER=1)"
rm "${ROOT}/gh-fail"
silent "once gh answers again, neither line wakes the lead again"
touch "${ROOT}/gh-slow"
silent "a gh pr list past SWARM_LEAD_PRS_WAIT wakes no one" SWARM_LEAD_PRS_WAIT=1
check "it is cut off there, not waited for" test ! -e "${ROOT}/slow-done"
check "and the lines stand" has "${CC}" "$(cat "${P}/.swarm/lead/seen")"
rm -f "${ROOT}/gh-slow"
prs UNKNOWN
silent "a conflict: line whose mergeable state reads UNKNOWN wakes no one"
check "and stands in the queue" has "${CC}" "$(cat "${P}/.swarm/lead/seen")"
prs MERGEABLE
silent "a conflict that clears wakes no one"
prs CONFLICTING
check "a conflict that comes back wakes the lead again" has "${CC}" "$(lead)"
rm "${P}/.swarm/lead/seen"; out="$(lead)"
check "a run's first read, with no seen file, prints an unmerged: line" has "${UA}" "${out}"
check "and a conflict: line" has "${CC}" "${out}"

# Story x lives in repo other: its PR there conflicts, and so does a story/a PR there, which is not a's.
board agent building
{ echo ---; echo "kind: code"; echo "status: ready"; echo "repo: other"; echo ---; } > "${B}/x.md"
printf '[%s,%s]\n' "$(pr 1 x "${H}" CONFLICTING SUCCESS "${OLD_MIN}")" "$(pr 2 a "${H}" CONFLICTING SUCCESS "${OLD_MIN}")" \
  | sed 's|/ucl-repo/|/ucl-other/|g' > "${ROOT}/prs-other.json"
out="$(lead)"
check "conflict: names a PR in its story's own repo, not the project's" \
  has "conflict: x https://github.com/${O}/ucl-other/pull/1, exit: tell its builder to merge the base in" "${out}"
check "a story/<slug> PR in another repo than its story's gives no line" none "conflict: a https://github.com/${O}/ucl-other/" "${out}"
check "the project's repo still gives its lines" has "${UA}" "${out}"
check "one gh pr list per repo a heads pass, for two repos" test "$(grep -c "${LISTS}" "${ROOT}/gh.log")" -eq 2

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
