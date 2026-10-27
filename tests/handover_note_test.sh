#!/usr/bin/env bash
# handover_note_test.sh — swarm.sh review <slug> <PR URL> for a story the user merges (merge = human, or
# a costs: money story under merge = agent) notes the story's running conductor through its inbox: the
# story and its PR now wait for the user. A review held on an open parent, an epic's review and, under
# merge = agent, a story the swarm merges itself send none; with no conductor running no inbox is
# written. A herdr that cannot list its agents, or a tell that fails, is a warning and the review still
# exits 0. On merge_fixture.sh, whose herdr stub lists conduct-e in a pane this project opened.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# settle — wait (10 s at most) for the deferred wake check a note leaves (note_wake_later) to finish.
settle() { local i; for ((i = 0; i < 50; i++)); do compgen -G "${ROOT}/proj/.swarm/inbox/*.later" >/dev/null || return 0; sleep 0.2; done; }
trap 'settle; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" SWARM_NOTE_WAKE_SECS=1
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

INBOX="${P}/.swarm/inbox/conduct-e.md"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n' > "${P}/docs/epics/e.md"
notes() { grep -c '^From the lead' "${INBOX}" 2>/dev/null || true; }
noted() { grep -qF -- "$1" "${INBOX}" 2>/dev/null; }
no_inbox() { [[ ! -e "${INBOX}" ]]; }
# story [config line]... — fresh with merge = human (a line may override it), no inbox and no other
# story: s1 of epic e, built and ready for review.
story() {
  settle; rm -rf "${P}/.swarm/inbox"; fresh "merge = human" "$@"; rm -f "${P}"/docs/stories/*.md
  item s1 "status: building" "kind: code" "epic: e"
}
# review <args> — swarm.sh review outside herdr; sets rc, output in ${ROOT}/out.
review() {
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" \
    bash "${SWARM}" review "$@" > "${ROOT}/out" 2>&1) || rc=$?
}

# --- merge = human: one note to conduct-e naming s1 and its PR.
story; review s1 "${URL}"
is "a story review: exits 0" 0 "${rc}"
check "a story review: says s1 is in review" said "review: s1 ${URL}"
is "a story review: one note to conduct-e" 1 "$(notes)"
check "a story review: the note names s1 and its PR" noted "Story s1 is in review: its PR ${URL} now waits for the user to merge."
check "a story review: says it noted conduct-e" said "noted conduct-e"

# --- Held on an open parent: the review dies with held:, and no note goes.
story; item p "status: review" "prs: https://github.com/o/r/pull/8" "epic: e"; item s1 "status: building" "epic: e" "depends_on: [p]"
review s1 "${URL}"
is "a review held on an open parent: exits non-zero" 1 "${rc}"
check "a review held on an open parent: says held" said "held: s1 waits for p to merge"
check "a review held on an open parent: no inbox" no_inbox

# --- The epic's own review: no note.
story; review e "${URL}"
is "an epic review: exits 0" 0 "${rc}"
check "an epic review: says e is in review" said "review: e ${URL}"
check "an epic review: no inbox" no_inbox

# --- No conductor runs: no inbox, and the review exits 0.
story; printf 't w:b\n' > "${ROOT}/agents"; review s1 "${URL}"; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"
is "a story review with no conductor running: exits 0" 0 "${rc}"
check "a story review with no conductor running: no inbox" no_inbox

# --- merge = agent: the swarm merges s1 itself, so no note; one that costs money waits for the user.
story "merge = agent"; review s1 "${URL}"
is "a story review under merge = agent: exits 0" 0 "${rc}"
check "a story review under merge = agent: no inbox" no_inbox
story "merge = agent"; item s1 "status: building" "epic: e" "costs: money"; review s1 "${URL}"
is "a costs: money story review under merge = agent: one note to conduct-e" 1 "$(notes)"
check "a costs: money story review under merge = agent: the note names s1 and its PR" \
  noted "Story s1 is in review: its PR ${URL} now waits for the user to merge."

# --- Two PRs: the note names both.
story; review s1 "${URL}" https://github.com/o/r2/pull/9
check "a story review with two PRs: the note names both" \
  noted "Story s1 is in review: its PRs ${URL} https://github.com/o/r2/pull/9 now wait for the user to merge."

# --- herdr cannot list its agents, or the tell fails (the inbox cannot be made): a warning naming the
# review, never the merge, and the review still exits 0.
story; touch "${ROOT}/agents.fail"; review s1 "${URL}"; rm -f "${ROOT}/agents.fail"
is "a story review while herdr cannot list: exits 0" 0 "${rc}"
check "a story review while herdr cannot list: warns" said "warning: herdr cannot list its agents, so conduct-e was not told that s1 waits for the user"
story; : > "${P}/.swarm/inbox"; review s1 "${URL}"; rm -f "${P}/.swarm/inbox"
is "a story review whose tell fails: exits 0" 0 "${rc}"
check "a story review whose tell fails: warns" said "warning: could not note conduct-e that s1 waits for the user"

finish handover-note
