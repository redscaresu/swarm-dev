#!/usr/bin/env bash
# merge_note_test.sh — swarm.sh merge of a story's PR notes the story's running conductor through its
# inbox: the PR merged, and the stories of its epic it made ready (blocked ones whose depends_on names
# it and has nothing open left), a held child review among them named apart, never to start. When
# reconcile fails after the merge (its lock held), the note still goes, naming the failure, and the
# merge still exits non-zero; after a --board merge too, whose running conductors each get it. When
# reconcile leaves the story in review (it held the pull), CI on main is red, or the merge queue
# merged a head nobody checked, the note says so and names no story to start. Each herdr call the
# note makes once the PR has merged is cut off after SWARM_NOTE_HERDR_WAIT, so a herdr that hangs,
# at once or after one answer, never hangs merge. A list herdr gives that does not parse is a warning,
# never read as no conductor running. With no conductor running, or one that has
# written its report, no inbox is written and the ready now: line says no conductor runs. A failed
# tell is a warning. On merge_fixture.sh, whose herdr stub lists conduct-e in a pane this project
# opened.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# settle — wait (10 s at most) for the deferred wake check a note leaves (note_wake_later) to finish.
settle() { local i; for ((i = 0; i < 50; i++)); do compgen -G "${ROOT}/proj/.swarm/inbox/*.later" >/dev/null || return 0; sleep 0.2; done; }
trap 'settle; chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" SWARM_NOTE_WAKE_SECS=1
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

# herdr: the fixture's, except that while ${ROOT}/herdr.hang exists `agent list` first sleeps 20 s,
# once ${ROOT}/herdr.pass1 has let one call through (it is removed by that call).
mv "${ROOT}/bin/herdr" "${ROOT}/bin/herdr-fixture"
cat > "${ROOT}/bin/herdr" <<STUB
#!/bin/sh
if [ "\$1 \$2" = "agent list" ] && [ -e "${ROOT}/herdr.hang" ]; then
  if [ -e "${ROOT}/herdr.pass1" ]; then rm -f "${ROOT}/herdr.pass1"; else sleep 20; fi
fi
exec "${ROOT}/bin/herdr-fixture" "\$@"
STUB
chmod +x "${ROOT}/bin/herdr"
INBOX="${P}/.swarm/inbox/conduct-e.md"; LOCK="${P}/.swarm/reconcile.lock"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n' > "${P}/docs/epics/e.md"
notes() { grep -c '^From the lead' "${INBOX}" 2>/dev/null || true; }
noted() { grep -qF -- "$1" "${INBOX}" 2>/dev/null; }
no_inbox() { [[ ! -e "${INBOX}" ]]; }
# story_pr [epic] — fresh, with no inbox and no other story: s, the PR's story, in review in [epic]
# (e, or none for -); s2 blocked on s alone; s3 blocked on s and x, which is still ready; s4 of
# another epic, blocked on s; l, the lead's (kind: lead), blocked on s.
story_pr() {
  local e="${1:-e}"
  settle; rm -rf "${P}/.swarm/inbox"; fresh; rm -f "${P}"/docs/stories/*.md
  if [[ "${e}" == - ]]; then item s "status: review" "prs: ${URL}"; else item s "status: review" "prs: ${URL}" "epic: ${e}"; fi
  if [[ "${e}" == - ]]; then item s2 "status: blocked" "depends_on: [s]"; else item s2 "status: blocked" "depends_on: [s]" "epic: ${e}"; fi
  item s3 "status: blocked" "depends_on: [s, x]" "epic: e"; item x "status: ready" "kind: code" "epic: e"
  item s4 "status: blocked" "depends_on: [s]" "epic: f"; item l "status: blocked" "depends_on: [s]" "epic: e" "kind: lead"
}

# --- A story merge that readies s2: one note to conduct-e naming the PR and s2 alone.
story_pr; merge "${URL}"
is "a story merge that readies s2: exits 0" 0 "${rc}"
is "a story merge: merge, main-ci, reconcile, as before" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
is "a story merge that readies s2: one note to conduct-e" 1 "$(notes)"
check "a story merge that readies s2: the note names the PR and s2" \
  noted "The PR ${URL} of story s just merged, and these stories of epic e are ready now: s2. Start them now"
check "a story merge that readies s2: not s3, still blocked on x, nor s4, of epic f" bash -c "! grep -qE 's3|s4' '${INBOX}'"
check "a story merge that readies s2: not l, the lead's" bash -c "! grep -qw l '${INBOX}'"
check "a story merge that readies s2: says it noted conduct-e" said "noted conduct-e"

# --- One that readies nothing: the note says the PR merged and made nothing ready.
story_pr; rm "${P}/docs/stories/s2.md"; merge "${URL}"
is "a story merge that readies nothing: exits 0" 0 "${rc}"
check "a story merge that readies nothing: the note says so" noted "The PR ${URL} of story s just merged; it made no story of epic e ready to start."

# --- h, a child review held on s with its build kept, is named apart: unblock readies it as held. w,
# blocked on s with a build already there, is not to start: unblock --startable leaves it out.
story_pr; item h "status: blocked" "depends_on: [s]" "epic: e" "held_by: s" "prs: https://github.com/o/r/pull/8"
item w "status: blocked" "depends_on: [s]" "epic: e"
mkdir -p "${ROOT}/proj-wt/h" "${ROOT}/proj-wt/w"; merge "${URL}"; rm -rf "${ROOT}/proj-wt"
is "a story merge that readies s2 and held h: exits 0" 0 "${rc}"
check "a story merge that readies s2 and held h: s2 alone is to start" noted "these stories of epic e are ready now: s2. Start them now"
check "a story merge that readies s2 and held h: h is named as held, never to start" \
  noted "These held child reviews waited on it: h. Unblock readies each as held: merge its base in and review it again, and never run swarm.sh story for it."

# --- The merge queue merges another head than the one checked: merge fails, and the note names that
# and asks for no start.
story_pr; echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}' > "${FX}/mq"
printf '{"data":{"repository":{"pullRequest":{"id":"PR_7","state":"MERGED","headRefOid":"%s","isInMergeQueue":false,"autoMergeRequest":null,"mergeCommit":{"oid":"%s"},"mergeQueueEntry":null,"timelineItems":{"nodes":[]}}}}}\n' "${H2}" "${M}" > "${FX}/queue"
merge "${URL}"
is "a queue merge of another head: exits non-zero" 1 "${rc}"
check "a queue merge of another head: the note names it" \
  noted "The PR ${URL} of story s just merged, but the merge queue merged a head nobody checked (#7 merged at head 2222222"
check "a queue merge of another head: the note starts nothing" bash -c "! grep -q 'ready now' '${INBOX}'"
check "a queue merge of another head: the note overrides the startable pass" \
  noted "This overrides the startable pass after this note: do not start any story whose depends_on names s."

# --- CI on main is red at the merge commit: merge fails as before, and the note names the red main
# and asks for no start.
story_pr; checks "${FX}/${M}.checks" "$(run test completed success)" "$(run e2e completed failure)"; merge "${URL}"
is "a story merge onto a red main: exits non-zero" 1 "${rc}"
check "a story merge onto a red main: the note names it" \
  noted "The PR ${URL} of story s just merged, but CI on main at ${M:0:7} is not green (red), so start none of the stories waiting on it until it is."
check "a story merge onto a red main: the note starts nothing" bash -c "! grep -q 'Start them now' '${INBOX}'"
check "a story merge onto a red main: the note overrides the startable pass" \
  noted "This overrides the startable pass after this note: do not start any story whose depends_on names s."

# --- herdr hangs once the PR has merged: the note's first list is cut off after
# SWARM_NOTE_HERDR_WAIT, which is a warning, and merge still exits 0.
story_pr; echo "touch '${ROOT}/herdr.hang'" > "${FX}/on-merge"; merge SWARM_NOTE_HERDR_WAIT=1 "${URL}"; rm -f "${ROOT}/herdr.hang"
is "a story merge while herdr hangs: exits 0" 0 "${rc}"
check "a story merge while herdr hangs: warns that conduct-e was not told" said "warning: herdr cannot list its agents, so conduct-e was not told that s2 are ready"
# herdr answers that first list, then hangs: the conductor is found in that list, the tell's own read
# is cut off, so no note goes, merge warns, and it still exits 0 (left to hang, herdr would answer
# after 20 s and the note would go).
story_pr; echo "touch '${ROOT}/herdr.pass1' '${ROOT}/herdr.hang'" > "${FX}/on-merge"; merge SWARM_NOTE_HERDR_WAIT=1 "${URL}"
rm -f "${ROOT}/herdr.hang" "${ROOT}/herdr.pass1"
is "a story merge while herdr hangs after one answer: exits 0" 0 "${rc}"
check "a story merge while herdr hangs after one answer: no note goes" no_inbox
check "a story merge while herdr hangs after one answer: warns that the note failed, not that no conductor runs" \
  said "warning: could not note conduct-e that s2 are ready"

# --- herdr's list does not parse once the PR has merged (it prints "not json" and exits 0): a
# warning, not a conductor taken for gone, and merge still exits 0.
story_pr; echo "touch '${ROOT}/agents.garbage'" > "${FX}/on-merge"; merge "${URL}"; rm -f "${ROOT}/agents.garbage"
is "a story merge whose herdr list does not parse: exits 0" 0 "${rc}"
check "a story merge whose herdr list does not parse: warns that conduct-e was not told, not that none runs" \
  said "warning: herdr cannot list its agents, so conduct-e was not told that s2 are ready"

# --- reconcile fails after the merge (its lock held): the note still goes, naming the PR and the
# failure, and merge still exits non-zero.
story_pr; mkdir "${LOCK}"; merge SWARM_RECONCILE_WAIT=0 "${URL}"; rmdir "${LOCK}"
is "a story merge whose reconcile fails: exits non-zero" 1 "${rc}"
check "a story merge whose reconcile fails: says so" said "merge: reconcile failed after the merge; run swarm.sh reconcile"
check "a story merge whose reconcile fails: logs reconcile's die line" logged "^reconcile - board state: .* is locked"
is "a story merge whose reconcile fails: one note to conduct-e" 1 "$(notes)"
check "a story merge whose reconcile fails: the note names the PR and the failure" \
  noted "The PR ${URL} of story s just merged, but reconcile failed after it (board state: ${P}/.swarm/reconcile is locked"
check "a story merge whose reconcile fails: the note names no story as ready" bash -c "! grep -q 'ready now' '${INBOX}'"

# --- No conductor runs, or the one there has written its report: no inbox, and a ready now: line.
story_pr; printf 't w:b\n' > "${ROOT}/agents"; merge "${URL}"; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"
is "a story merge with no conductor running: exits 0" 0 "${rc}"
check "a story merge with no conductor running: no inbox" no_inbox
check "a story merge with no conductor running: says none runs" said "ready now: s2 (of epic e); no conductor runs for it yet"
story_pr; touch "${P}/.swarm/conduct-e.report.md"; merge "${URL}"; rm "${P}/.swarm/conduct-e.report.md"
is "a story merge whose conductor has reported: exits 0" 0 "${rc}"
check "a story merge whose conductor has reported: no inbox" no_inbox
check "a story merge whose conductor has reported: says none runs" said "ready now: s2 (of epic e); no conductor runs for it yet"
# A story with no epic: its group is the backlog's, whose conductor is not running.
story_pr -; merge "${URL}"
check "a story merge with no epic: says the backlog's s2 has no conductor" said "ready now: s2 (with no epic); no conductor runs for it yet"
# Only held h is freed, and no conductor runs: the ready now: line still names it, marked held.
story_pr; rm "${P}/docs/stories/s2.md"; item h "status: blocked" "depends_on: [s]" "epic: e" "held_by: s" "prs: https://github.com/o/r/pull/8"
mkdir -p "${ROOT}/proj-wt/h"; printf 't w:b\n' > "${ROOT}/agents"; merge "${URL}"
printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"; rm -rf "${ROOT}/proj-wt"
check "a story merge that frees only held h, with no conductor running: says so, marked held" said "ready now: h (held) (of epic e); no conductor runs for it yet"

# --- A tell that fails (the inbox cannot be made) is a warning, and the merge still exits 0.
story_pr; : > "${P}/.swarm/inbox"; merge "${URL}"; rm -f "${P}/.swarm/inbox"
is "a story merge whose tell fails: exits 0" 0 "${rc}"
check "a story merge whose tell fails: warns" said "warning: could not note conduct-e that s2 are ready"

# --- From here the main checkout has an upstream, origin's main.
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "${P}" push -q origin HEAD:refs/heads/main; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" fetch -q origin; git -C "${P}" branch -q -u origin/main

# --- reconcile holds the pull (q's PR cannot be read), so s, tracked here, stays in review: the note
# says what it made ready is not known yet, in place of any story to start.
story_pr; item q "status: review" "prs: https://github.com/o/r/pull/9"; echo 'x"' > "${FX}/state.9"
git -C "${P}" add docs/stories/s.md; git -C "${P}" -c user.name=t -c user.email=t@t commit -q -m s
merge "${URL}"
is "a story merge whose reconcile holds the pull: exits 0" 0 "${rc}"
check "a story merge whose reconcile holds the pull: the note says it is not known yet" \
  noted "The PR ${URL} of story s just merged, but reconcile has not finished s yet (it is still in review)"

# --- merge --board with an upstream: its reconcile fails (the lock held), and conduct-e, running,
# still gets a note naming the PR and the failure; the merge exits 0, as before.
story_pr; rm -f "${P}"/docs/stories/*.md; mkdir "${LOCK}"; merge SWARM_RECONCILE_WAIT=0 --board "${URL}"; rmdir "${LOCK}"
is "a board merge whose reconcile fails: exits 0" 0 "${rc}"
check "a board merge whose reconcile fails: warns" said "warning: reconcile failed after the merge (board state:"
is "a board merge whose reconcile fails: one note to conduct-e" 1 "$(notes)"
check "a board merge whose reconcile fails: the note names the PR and the failure" \
  noted "The board PR ${URL} just merged, but reconcile failed after it (board state: ${P}/.swarm/reconcile is locked"
# The same while herdr hangs once the PR has merged: the list of running conductors is cut off after
# SWARM_NOTE_HERDR_WAIT, a warning, and merge still exits 0.
story_pr; rm -f "${P}"/docs/stories/*.md; mkdir "${LOCK}"; echo "touch '${ROOT}/herdr.hang'" > "${FX}/on-merge"
merge SWARM_RECONCILE_WAIT=0 SWARM_NOTE_HERDR_WAIT=1 --board "${URL}"; rmdir "${LOCK}"; rm -f "${ROOT}/herdr.hang"
is "a board merge whose reconcile fails while herdr hangs: exits 0" 0 "${rc}"
check "a board merge whose reconcile fails while herdr hangs: warns that no conductor was told" \
  said "warning: herdr cannot list its agents, so no conductor was told that ${URL} merged"
# The same when herdr's list does not parse: a warning, not a board with no conductor running.
story_pr; rm -f "${P}"/docs/stories/*.md; mkdir "${LOCK}"; echo "touch '${ROOT}/agents.garbage'" > "${FX}/on-merge"
merge SWARM_RECONCILE_WAIT=0 --board "${URL}"; rmdir "${LOCK}"; rm -f "${ROOT}/agents.garbage"
is "a board merge whose reconcile fails and herdr list does not parse: exits 0" 0 "${rc}"
check "a board merge whose reconcile fails and herdr list does not parse: warns that no conductor was told" \
  said "warning: herdr cannot list its agents, so no conductor was told that ${URL} merged"

finish merge-note
