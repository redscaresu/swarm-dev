#!/usr/bin/env bash
# protected_hold_queue_test.sh — with merge = agent, a PR swarm.sh merge holds for changing a protected
# path, or whose files it cannot read, is recorded on its item (board-state protected:, keyed to the PR's
# URL and head), and status and wait --lead show it as the user's merge: status on a row of its own,
# tagged (protected path), the item's other PRs on the untagged row; wait --lead as `merge: <slug> <URL>
# (held: changes <path>; exit: the user merges it)`, once when a story and its epic both list it, the
# epic's line left with its other held PRs. A review item with no hold gets no merge: line, a hold stops
# tagging a PR the item no longer lists or that a heads pass saw at another head, and a later merge that
# passes the hold drops it. A PR held because its merge of the base dropped base lines gets its own row,
# tagged (dropped base lines), and its wait --lead line names the lines and its own exit.
# status and lead_queue read files only: the gh calls are the heads pass's. On merge_fixture.sh for the
# merges; then gh is a stub of the reads wait --lead makes, logging each to gh.log.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

U8="${URL%/*}/8"; U9="${URL%/*}/9"; U10="${URL%/*}/10"
HELD="merge: s ${URL} (held: changes hooks/x.sh; exit: the user merges it)"
cp "${ROOT}/bin/gh" "${ROOT}/merge-gh"
# changes <path> — the PR's one file.
changes() { echo "[{\"filename\":\"$1\",\"status\":\"modified\"}]" > "${FX}/files"; echo 1 > "${FX}/nfiles"; }
# reads_stub — gh as wait --lead reads it: PR <n>'s head is ${ROOT}/head.<n>, else ${H1}, its one check run
# green, no status; the project's repo is o/r with no open PR. Anything else fails. With ${ROOT}/hang.<n>
# the next read of PR <n>'s head first removes it and sleeps 200 s: one gh that hangs.
reads_stub() {
  printf '#!/bin/sh\nLOG="%s"; H="%s"; D="%s"\n' "${ROOT}/gh.log" "${H1}" "${ROOT}" > "${ROOT}/bin/gh"
  cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
case "$1 $2" in
  "pr view") [ ! -e "${D}/hang.$3" ] || { rm "${D}/hang.$3"; sleep 200; }
             cat "${D}/head.$3" 2>/dev/null || echo "${H}" ;;
  "repo view") echo o/r ;;
  "pr list") echo '[]' ;;
  api*) case "$*" in
          *check-runs*) echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"success","html_url":"u"}]}' ;;
          */status*) echo '{"total_count":0,"statuses":[]}' ;;
          *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
        esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
  chmod +x "${ROOT}/bin/gh"; : > "${ROOT}/gh.log"
}
# held_board — merge = agent; story s lists PRs 7 and 8, story r (no hold) PR 9, both in review. swarm.sh
# merge holds PR 7, which changes hooks/x.sh, and merges PR 8, which changes bin/x.sh. Then gh is reads_stub.
held_board() {
  cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"
  fresh; item s "status: review" "prs: ${URL} ${U8}"; item r "status: review" "prs: ${U9}"
  rm -rf "${P}/docs/epics" "${P}/.swarm/lead" "${ROOT}"/head.*
  changes hooks/x.sh; merge "${URL}"
  refused "PR 7, changing hooks/x.sh" "held: s changes hooks/x.sh, which only the user merges"
  # The stub reads every PR merged once one is: PRs 7 and 9 stay open, so reconcile keeps s and r in review.
  echo OPEN > "${FX}/state.7"; echo OPEN > "${FX}/state.9"; changes bin/x.sh; merge "${U8}"
  is "PR 8, changing bin/x.sh, is not held: it merges" 0 "${rc}"
  reads_stub
}
st() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status 2>&1); }
merge_rows() { st | sed -n '/^Waiting on you$/,/^$/p' | grep '^  awaiting your merge' || true; }
# lead [VAR=value]... <timeout-ms> — one swarm.sh wait --lead inside herdr, a poll a second, a heads pass a
# poll unless VARs say otherwise; its output in ${ROOT}/out, its exit code in rc. With no seen file it
# starts from an empty one, so its first read wakes it.
lead() {
  local envs=()
  while [[ "$1" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  [[ -f "${P}/.swarm/lead/seen" ]] || { mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"; }
  rc=0
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_LEAD_POLL=1 SWARM_LEAD_HEADS_EVERY=1 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait --lead "$1" > "${ROOT}/out" 2>&1) || rc=$?
}
merge_out() { grep '^merge: ' "${ROOT}/out" || true; }
gh_count() { grep -c -- "$1" "${ROOT}/gh.log" || true; }
# gh_calls — gh.log's calls by kind, joined with |. The heads pass's base read (lead_bases) asks for the repo's
# default branch, which reads_stub refuses, so it reads nothing more.
gh_calls() {
  sed -E 's/^(pr view [0-9]+|repo view|pr list) .*/\1/; s/^api .*check-runs.*/check-runs/; s/^api .*\/status.*/status/; s/^api --jq \.default_branch .*/default branch/' "${ROOT}/gh.log" | paste -sd'|' -
}

# --- status: the held PR on its own tagged row, the story's other PR on the untagged row; no gh call.
held_board
is "status lists the held PR alone on a (protected path) row, and the others untagged" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge (protected path): s ${URL}"$'\n'"  awaiting your merge: s ${U8}" "$(merge_rows)"
is "status makes no gh call" "" "$(cat "${ROOT}/gh.log")"

# --- wait --lead: one merge: line, the held URL alone with its path and exit; r's untagged PR gets none.
lead 20000
is "wait --lead wakes on the held PR" 0 "${rc}"
is "it prints merge: for the held PR alone, with its path and the user's exit" "${HELD}" "$(merge_out)"
is "it reads no head of a PR that waits on no one: PR 8 or 9" 0 "$(gh_count '^pr view [89] ')"
is "its gh calls are the heads pass's: PR 7's head, its checks, the repo, its open PRs and its base" \
  "pr view 7|check-runs|status|repo view|pr list|default branch" "$(gh_calls)"

# --- A story and its epic both list the held PR: wait --lead reports it once, reading its head once, and
# status tags it on both rows.
held_board; mkdir -p "${P}/docs/epics"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
check "status tags the epic's row too" grep -qxF "  awaiting your merge (protected path): epic e ${URL}" <(merge_rows)
lead 20000
is "with its epic listing it too, it prints the held PR once, under the story" "${HELD}" "$(merge_out)"
is "with its epic listing it too, it reads PR 7's head once" 1 "$(gh_count '^pr view 7 ')"
# The next run's later polls make no gh call, and the line it saw, as printed, is no news: no fresh re-read.
: > "${ROOT}/gh.log"
lead SWARM_LEAD_HEADS_EVERY=3600 3000
is "a run that has seen the line times out with its timeout: line alone" \
  "1|timeout: nothing new in 1 min, exit: swarm.sh wait --lead" "${rc}|$(cat "${ROOT}/out")"
is "over its three polls it reads PR 7's head once, on its heads pass, and no check run" "1|0" \
  "$(gh_count '^pr view 7 ')|$(gh_count 'check-runs')"
is "over its three polls its only gh calls are that heads pass's" "pr view 7|repo view|pr list|default branch" "$(gh_calls)"

# --- The epic lists the story's held PR 7 and a held PR 11 of its own: its line names PR 11 alone, and
# PR 7's head is read once.
U11="${URL%/*}/11"
held_board; mkdir -p "${P}/docs/epics"; cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"
printf -- '---\nstatus: review\nprs: %s %s\n---\n\n# e\n' "${URL}" "${U11}" > "${P}/docs/epics/e.md"
echo OPEN > "${FX}/state.11"; rm "${P}/.swarm/events.tsv"; changes hooks/x.sh; merge "${U11}"
refused "PR 11, the epic's, changing hooks/x.sh" "held: e changes hooks/x.sh"
reads_stub; lead 20000
is "the story's line names PR 7, the epic's PR 11 alone" \
  "${HELD}"$'\n'"merge: e ${U11} (held: changes hooks/x.sh; exit: the user merges it)" "$(merge_out)"
is "PR 7's head is read once, PR 11's once" "1|1" "$(gh_count '^pr view 7 ')|$(gh_count '^pr view 11 ')"

# --- A hold names the head it was read at: a heads pass that reads PR 7 at that head keeps it, one that
# reads it at another head (the builder pushed) makes it stale, so it is no longer the user's merge. The
# second second keeps the pass after the hold, as a real push is.
held_board; sleep 1; lead 20000
is "PR 7 read at the held head: wait --lead still prints its line" "${HELD}" "$(merge_out)"
echo "${H2}" > "${ROOT}/head.7"; rm -rf "${P}/.swarm/lead"; lead 3000
is "PR 7 read at a new head: wait --lead prints no merge: line" "1|" "${rc}|$(merge_out)"
is "PR 7 read at a new head: status lists it untagged" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge: s ${URL} ${U8}" "$(merge_rows)"
# The epic's held PR 11 is no story PR (gh lists only story/* branches as open story PRs): its new head
# makes its hold stale too.
held_board; mkdir -p "${P}/docs/epics"; cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${U11}" > "${P}/docs/epics/e.md"
echo OPEN > "${FX}/state.11"; changes hooks/x.sh; merge "${U11}"
reads_stub; echo "${H2}" > "${ROOT}/head.11"; sleep 1; lead 20000
is "the epic's PR 11, read at a new head: no merge: line for it, only PR 7's" "${HELD}" "$(merge_out)"
check "the epic's PR 11, read at a new head: status lists it untagged" grep -qxF "  awaiting your merge: epic e ${U11}" <(merge_rows)
# A hold made after the last pass read the old head stands, though the pass saw another head than its own:
# swarm.sh merge read PR 7 again at ${H2} and held it.
held_board; sleep 1; lead 20000
cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"; echo "${H2}" > "${FX}/head"; sleep 1
checks "${FX}/${H2}.checks" "$(run test completed success)"; statuses "${FX}/${H2}.status"
rm "${P}/.swarm/events.tsv"; changes hooks/x.sh; merge "${URL}"
refused "PR 7 at ${H2:0:7}, changing hooks/x.sh" "held: s changes hooks/x.sh"
reads_stub
is "a hold newer than the last pass, at another head than it read: status still tags it" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge (protected path): s ${URL}"$'\n'"  awaiting your merge: s ${U8}" "$(merge_rows)"

# --- A PR whose files cannot be read is held too, and recorded: status tags it, and wait --lead says why.
held_board; cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"; rm "${P}/.swarm/events.tsv"; changes hooks/x.sh; echo 301 > "${FX}/nfiles"
merge "${URL}"
refused "PR 7 of 301 files" "held: s (its files at ${H1:0:7} could not be read"
reads_stub
is "status lists the unreadable PR on the (protected path) row" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge (protected path): s ${URL}"$'\n'"  awaiting your merge: s ${U8}" "$(merge_rows)"
lead 20000
is "wait --lead says its files could not be read, and why" \
  "merge: s ${URL} (held: its files could not be read: the compare of main with ${H1:0:7} lists at most 300 files, and the PR changes 301, so it cannot list them all; exit: the user merges it)" "$(merge_out)"

# --- A review item with no hold gets no merge: line under merge = agent, as before.
held_board; rm -f "${P}/docs/stories/s.md" "${P}/.swarm/board-state/stories/s"
lead 3000
is "with only an unheld review story, wait --lead times out" 1 "${rc}"
is "with only an unheld review story, it prints no merge: line" "" "$(merge_out)"

# --- The story's prs: swaps the held PR for a new one: the old hold tags nothing.
held_board; sed -i.bak "s|^prs: .*|prs: ${U10} ${U8}|" "${P}/docs/stories/s.md"
is "after the swap status lists the story's PRs untagged" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge: s ${U10} ${U8}" "$(merge_rows)"
lead 3000
is "after the swap wait --lead prints no merge: line" "" "$(merge_out)"

# --- A head read that hangs is cut off after SWARM_LEAD_PRS_WAIT seconds, and the poll goes on: the hold
# stands, its head unread, and the pass reads PR 7 again for its verdict, which answers this time.
held_board; touch "${ROOT}/hang.7"; t0=${SECONDS}
lead SWARM_LEAD_PRS_WAIT=1 20000
is "a head read that hangs is cut off: wait --lead still wakes on the held PR" "0|${HELD}" "${rc}|$(merge_out)"
is "it reads PR 7's head twice: the read that was cut off, then the one for its verdict" 2 "$(gh_count '^pr view 7 ')"
check "the run ends well inside the stub's 200 s" [ $((SECONDS - t0)) -lt 100 ]

# --- Both of a story's PRs held: the second hold keeps the first's record, and the line names each PR,
# the path once.
held_board; cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"; echo OPEN > "${FX}/state"; rm "${P}/.swarm/events.tsv"; changes hooks/x.sh; merge "${U8}"
refused "PR 8, changing hooks/x.sh too" "held: s changes hooks/x.sh"
reads_stub
is "status lists both held PRs on the (protected path) row" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge (protected path): s ${URL} ${U8}" "$(merge_rows)"
lead 20000
is "wait --lead names both held PRs and the path once" \
  "merge: s ${URL} ${U8} (held: changes hooks/x.sh; exit: the user merges it)" "$(merge_out)"

# --- A later merge of the held PR that passes the hold (its head no longer changes hooks/x.sh) drops the
# record, though the merge then stops: the repo allows no merge method.
held_board; cp "${ROOT}/merge-gh" "${ROOT}/bin/gh"; changes bin/x.sh
echo '{"squashMergeAllowed":false,"mergeCommitAllowed":false,"rebaseMergeAllowed":false}' > "${FX}/repo"
merge "${URL}"
check "PR 7, no longer changing hooks/x.sh, gets past the hold" said "allows no merge method"
is "the hold no longer tags PR 7" "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge: s ${URL} ${U8}" "$(merge_rows)"

# --- A PR held for dropped base lines (dropped-lines-hold's protected: entry): status gives it a row of its
# own, tagged (dropped base lines), apart from the item's protected-path PR, and wait --lead prints its
# count, first file and text with the builder's exit. The entries are written by hand, as merge records them.
# dropped_board <what> [front-matter line]... — merge = agent; story s (with the lines) lists PRs 7 and
# 8, story r PR 9, both in review; s's protected: state holds PR 7 for <what> and PR 8 for hooks/x.sh,
# both at ${H1}. Then gh is reads_stub.
dropped_board() {
  fresh; item s "status: review" "prs: ${URL} ${U8}" "${@:2}"; item r "status: review" "prs: ${U9}"
  rm -rf "${P}/docs/epics" "${P}/.swarm/lead" "${ROOT}"/head.*
  mkdir -p "${P}/.swarm/board-state/stories"
  printf 'protected: %s %s %s %s | %s %s %s hooks/x.sh\n' "${URL}" "${H1}" "$(date +%s)" "$1" "${U8}" "${H1}" "$(date +%s)" \
    > "${P}/.swarm/board-state/stories/s"
  reads_stub
}
dropped_board "dropped base lines: 2, first docs/x.md: row"
is "status lists the dropped-lines PR on a (dropped base lines) row, the path one on its (protected path) row" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge (protected path): s ${U8}"$'\n'"  awaiting your merge (dropped base lines): s ${URL}" "$(merge_rows)"
lead 20000
is "wait --lead prints the path PR's line, then the dropped-lines PR's with its count, first file, text and exit" \
  "merge: s ${U8} (held: changes hooks/x.sh; exit: the user merges it)"$'\n'"merge: s ${URL} (held: dropped base lines: 2, first docs/x.md: row; exit: the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand)" "$(merge_out)"
# An unchecked one, on a costs: money story: both tags, its why and its own exit.
dropped_board "dropped base lines unchecked: git 2.37 has no merge-tree --write-tree" "costs: money"
is "status tags an unchecked dropped-lines PR of a costs: money story with both tags" \
  "  awaiting your merge: r ${U9}"$'\n'"  awaiting your merge (costs money) (protected path): s ${U8}"$'\n'"  awaiting your merge (costs money) (dropped base lines): s ${URL}" "$(merge_rows)"
lead 20000
is "wait --lead prints the unchecked PR's why and the exit that the user checks the merge by hand" \
  "merge: s ${U8} (held: changes hooks/x.sh; exit: the user merges it)"$'\n'"merge: s ${URL} (held: dropped base lines unchecked: git 2.37 has no merge-tree --write-tree; exit: the user checks the merge by hand and merges it, or runs swarm.sh merge again)" "$(merge_out)"

finish "protected hold queue"
