#!/usr/bin/env bash
# merge_note_test.sh — swarm.sh merge of a story's PR notes the story's running conductor through its
# inbox: the PR merged, and the stories of its epic it made ready (blocked ones whose depends_on names
# it and has nothing open left). When reconcile fails after the merge (its lock held), the note still
# goes, naming the failure, and the merge still exits non-zero; after a --board merge too, whose
# running conductors each get it. With no conductor running, or one that has written its report, no
# inbox is written and the ready now: line says no conductor runs. A failed tell is a warning. On
# merge_fixture.sh, whose herdr stub lists conduct-e in a pane this project opened.
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

INBOX="${P}/.swarm/inbox/conduct-e.md"; LOCK="${P}/.swarm/reconcile.lock"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n' > "${P}/docs/epics/e.md"
notes() { grep -c '^From the lead' "${INBOX}" 2>/dev/null || true; }
noted() { grep -qF -- "$1" "${INBOX}" 2>/dev/null; }
no_inbox() { [[ ! -e "${INBOX}" ]]; }
# story_pr [epic] — fresh, with no inbox and no other story: s, the PR's story, in review in [epic]
# (e, or none for -); s2 blocked on s alone; s3 blocked on s and x, which is still ready; s4 of
# another epic, blocked on s.
story_pr() {
  local e="${1:-e}"
  settle; rm -rf "${P}/.swarm/inbox"; fresh; rm -f "${P}"/docs/stories/*.md
  if [[ "${e}" == - ]]; then item s "status: review" "prs: ${URL}"; else item s "status: review" "prs: ${URL}" "epic: ${e}"; fi
  if [[ "${e}" == - ]]; then item s2 "status: blocked" "depends_on: [s]"; else item s2 "status: blocked" "depends_on: [s]" "epic: ${e}"; fi
  item s3 "status: blocked" "depends_on: [s, x]" "epic: e"; item x "status: ready" "kind: code" "epic: e"
  item s4 "status: blocked" "depends_on: [s]" "epic: f"
}

# --- A story merge that readies s2: one note to conduct-e naming the PR and s2 alone.
story_pr; merge "${URL}"
is "a story merge that readies s2: exits 0" 0 "${rc}"
is "a story merge: merge, main-ci, reconcile, as before" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
is "a story merge that readies s2: one note to conduct-e" 1 "$(notes)"
check "a story merge that readies s2: the note names the PR and s2" \
  noted "The PR ${URL} of story s just merged, and these stories of epic e are ready now: s2. Start them now"
check "a story merge that readies s2: not s3, still blocked on x, nor s4, of epic f" bash -c "! grep -qE 's3|s4' '${INBOX}'"
check "a story merge that readies s2: says it noted conduct-e" said "noted conduct-e"

# --- One that readies nothing: the note says the PR merged and made nothing ready.
story_pr; rm "${P}/docs/stories/s2.md"; merge "${URL}"
is "a story merge that readies nothing: exits 0" 0 "${rc}"
check "a story merge that readies nothing: the note says so" noted "The PR ${URL} of story s just merged; it made no story of epic e ready."

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
check "a story merge with no epic: no note to conduct-e" no_inbox

# --- A tell that fails (the inbox cannot be made) is a warning, and the merge still exits 0.
story_pr; : > "${P}/.swarm/inbox"; merge "${URL}"; rm -f "${P}/.swarm/inbox"
is "a story merge whose tell fails: exits 0" 0 "${rc}"
check "a story merge whose tell fails: warns" said "warning: could not note conduct-e that s2 are ready"

# --- merge --board with an upstream: its reconcile fails (the lock held), and conduct-e, running,
# still gets a note naming the PR and the failure; the merge exits 0, as before.
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "${P}" push -q origin HEAD:refs/heads/main; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" fetch -q origin; git -C "${P}" branch -q -u origin/main
story_pr; rm -f "${P}"/docs/stories/*.md; mkdir "${LOCK}"; merge SWARM_RECONCILE_WAIT=0 --board "${URL}"; rmdir "${LOCK}"
is "a board merge whose reconcile fails: exits 0" 0 "${rc}"
check "a board merge whose reconcile fails: warns" said "warning: reconcile failed after the merge (board state:"
is "a board merge whose reconcile fails: one note to conduct-e" 1 "$(notes)"
check "a board merge whose reconcile fails: the note names the PR and the failure" \
  noted "The board PR ${URL} just merged, but reconcile failed after it (board state: ${P}/.swarm/reconcile is locked"

finish merge-note
