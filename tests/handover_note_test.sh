#!/usr/bin/env bash
# handover_note_test.sh — swarm.sh review <slug> <PR URL> for a story under merge = human, or a costs:
# money story under merge = agent, notes the story's running conductor through its inbox: the story is
# in review and its PR now waits to be merged. A review held on an open parent, an epic's review, a
# story the swarm merges itself under merge = agent, and a review the conductor ran itself
# (SWARM_AGENT is its name) send none; with no conductor running no inbox is written. One a review
# agent runs does note it. A story with no epic notes the backlog conductor. A herdr that cannot list its agents, or a
# tell that fails, is a warning and the review still exits 0. On merge_fixture.sh, whose herdr stub
# lists conduct-e, and here the backlog conductor, in panes this project opened.
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

# The backlog conductor's name, as conductor_name makes it: conduct-backlog-<project dir>-<path hash>.
crc="$(printf '%s' "${P}" | cksum)"; BL="conduct-backlog-proj-$(printf '%06x' $((${crc%% *} % 16777216)))"
AGENTS="$(printf 'conduct-e w:c\nt w:b\n%s w:k' "${BL}")"
printf '%s\n' "${AGENTS}" > "${ROOT}/agents"; printf 'w:k %s\n' "${BL}" >> "${P}/.swarm/state/e"
INBOX="${P}/.swarm/inbox/conduct-e.md"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n' > "${P}/docs/epics/e.md"
notes() { grep -c '^From the lead' "${INBOX}" 2>/dev/null || true; }
noted() { grep -qF -- "$1" "${INBOX}" 2>/dev/null; }
no_inbox() { [[ ! -e "${INBOX}" ]]; }
no_inboxes() { ! compgen -G "${P}/.swarm/inbox/*.md" >/dev/null; }
# story [config line]... — fresh with merge = human (a line may override it), no inbox and no other
# story: s1 of epic e, built and ready for review.
story() {
  settle; rm -rf "${P}/.swarm/inbox"; fresh "merge = human" "$@"; rm -f "${P}"/docs/stories/*.md
  item s1 "status: building" "kind: code" "epic: e"
}
# review [VAR=value]... <args> — swarm.sh review outside herdr, with no SWARM_AGENT unless a VAR sets
# it; sets rc, output in ${ROOT}/out.
review() {
  local envs=()
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" review "$@" > "${ROOT}/out" 2>&1) || rc=$?
}

# --- merge = human: one note to conduct-e naming s1 and its PR.
story; review s1 "${URL}"
is "a story review: exits 0" 0 "${rc}"
check "a story review: says s1 is in review" said "review: s1 ${URL}"
is "a story review: one note to conduct-e" 1 "$(notes)"
check "a story review: the note names s1 and its PR" noted "Story s1 is in review: its PR ${URL} now waits to be merged."
check "a story review: says it noted conduct-e" said "noted conduct-e"

# --- conduct-e ran the review itself (its brief does under merge = human): no note to its own inbox.
# review-s1, the story's review agent, ran it: conduct-e is noted.
story; review SWARM_AGENT=conduct-e s1 "${URL}"
is "a story review conduct-e ran: exits 0" 0 "${rc}"
check "a story review conduct-e ran: no inbox" no_inboxes
story; review SWARM_AGENT=review-s1 s1 "${URL}"
is "a story review review-s1 ran: one note to conduct-e" 1 "$(notes)"

# --- Held on an open parent: the review dies with held:, and no note goes.
story; item p "status: review" "prs: https://github.com/o/r/pull/8" "epic: e"; item s1 "status: building" "epic: e" "depends_on: [p]"
review s1 "${URL}"
is "a review held on an open parent: exits non-zero" 1 "${rc}"
check "a review held on an open parent: says held" said "held: s1 waits for p to merge"
check "a review held on an open parent: no inbox" no_inboxes

# --- The epic's own review: no note, to conduct-e or to the backlog conductor.
story; review e "${URL}"
is "an epic review: exits 0" 0 "${rc}"
check "an epic review: says e is in review" said "review: e ${URL}"
check "an epic review: no inbox" no_inboxes

# --- No conductor runs: no inbox, and the review exits 0.
story; printf 't w:b\n' > "${ROOT}/agents"; review s1 "${URL}"; printf '%s\n' "${AGENTS}" > "${ROOT}/agents"
is "a story review with no conductor running: exits 0" 0 "${rc}"
check "a story review with no conductor running: no inbox" no_inboxes

# --- A story with no epic: one note to the backlog conductor, none to conduct-e.
story; item s1 "status: building" "kind: code"; review s1 "${URL}"
check "a story review with no epic: the backlog conductor's note names s1 and its PR" \
  grep -qF "Story s1 is in review: its PR ${URL} now waits to be merged." "${P}/.swarm/inbox/${BL}.md"
check "a story review with no epic: no note to conduct-e" no_inbox

# --- merge = agent: the swarm merges s1 itself, so no note; one that costs money waits on its merge.
story "merge = agent"; review s1 "${URL}"
is "a story review under merge = agent: exits 0" 0 "${rc}"
check "a story review under merge = agent: no inbox" no_inbox
story "merge = agent"; item s1 "status: building" "epic: e" "costs: money"; review s1 "${URL}"
is "a costs: money story review under merge = agent: one note to conduct-e" 1 "$(notes)"
check "a costs: money story review under merge = agent: the note names s1 and its PR" \
  noted "Story s1 is in review: its PR ${URL} now waits to be merged."

# --- Two PRs: the note names both.
story; review s1 "${URL}" https://github.com/o/r2/pull/9
check "a story review with two PRs: the note names both" \
  noted "Story s1 is in review: its PRs ${URL} https://github.com/o/r2/pull/9 now wait to be merged."

# --- herdr cannot list its agents, or the tell fails (the inbox cannot be made): a warning naming the
# review, never the merge, and the review still exits 0.
story; touch "${ROOT}/agents.fail"; review s1 "${URL}"; rm -f "${ROOT}/agents.fail"
is "a story review while herdr cannot list: exits 0" 0 "${rc}"
check "a story review while herdr cannot list: warns" said "warning: herdr cannot list its agents, so conduct-e was not told that s1 is in review"
story; : > "${P}/.swarm/inbox"; review s1 "${URL}"; rm -f "${P}/.swarm/inbox"
is "a story review whose tell fails: exits 0" 0 "${rc}"
check "a story review whose tell fails: warns" said "warning: could not note conduct-e that s1 is in review"

finish handover-note
