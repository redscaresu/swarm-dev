#!/usr/bin/env bash
# epic_finish_test.sh — a conductor's note after a story's merge (swarm.sh merge) or handover (swarm.sh
# review, under merge = human) ends with `finish: epic <e> has no agent work left` only once no story of
# the epic is an agent's (agent_work_left): none ready, building or with its PR open and not yet in
# review, none blocked on an agent's work, none in review that its review agent merges next, and no
# fix-main story started. A story in review that is the user's, and one blocked on a kind: lead story,
# hold nothing up. The report is the lead's only finish sign, so a conductor told to finish early would
# leave a review agent's PR with nobody to act on its escalations. On merge_fixture.sh, with a herdr
# stub that also closes panes, so the last merge's reconcile can close review-s.
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

# herdr: its tabs, panes and agents in ${H} ("<tab> <label>", "<pane> <tab>", "<name> <pane> <status>"),
# enough for a note (agent list) and for reconcile's close of a merged story's review agent (pane close).
H="${ROOT}/h"; mkdir -p "${H}"
printf '#!/bin/sh\nH="%s"\n' "${H}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
drop() { awk -v k="$2" -v c="$3" '$c != k' "$H/$1" > "$H/$1.tmp" && mv "$H/$1.tmp" "$H/$1"; }
# list <file> <key>... — the file's lines as herdr's JSON list of that name, a key per field.
list() { f="$1"; shift; awk -v w="${f}" -v k="$*" 'BEGIN { n = split(k, key, " "); printf "{\"result\":{\"%s\":[", w }
  { printf "%s{", (NR > 1 ? "," : ""); for (i = 1; i <= n; i++) printf "%s\"%s\":\"%s\"", (i > 1 ? "," : ""), key[i], $i; printf "}" }
  END { print "]}}" }' "$H/${f}"; }
case "$1 $2" in
  "tab list") list tabs tab_id label ;;
  "pane list") list panes pane_id tab_id ;;
  "agent list") list agents name pane_id agent_status ;;
  "agent rename") awk -v p="$3" -v n="$4" '$2 == p { $1 = n } { print }' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "pane close") t="$(awk -v p="$3" '$1 == p { print $2 }' "$H/panes")"; [ -n "$t" ] || exit 1
                drop panes "$3" 1; drop agents "$3" 2
                if ! awk -v t="$t" '$2 == t { f = 1 } END { exit !f }' "$H/panes"; then drop tabs "$t" 1; fi ;;
  "tab close") for p in $(awk -v t="$3" '$2 == t { print $1 }' "$H/panes"); do drop agents "$p" 2; done
               drop panes "$3" 2; drop tabs "$3" 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/herdr"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"; chmod +x "${ROOT}/bin/claude"

INBOX="${P}/.swarm/inbox/conduct-e.md"; U2=https://github.com/o/r/pull/8
FIN="finish: epic e has no agent work left"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n' > "${P}/docs/epics/e.md"
# lay — the lead in w:lead (tab t0), and in epic e's tab t1 conduct-e (w:c), s's builder (w:b) and its
# idle review agent review-s (w:r), as the project's tab record and agents.tsv name them.
lay() {
  printf 't0 lead\nt1 e\n' > "${H}/tabs"
  printf 'lead w:lead idle\nconduct-e w:c idle\ns w:b idle\nreview-s w:r idle\n' > "${H}/agents"
  printf 'w:lead t0\nw:c t1\nw:b t1\nw:r t1\n' > "${H}/panes"
  rm -f "${P}"/.swarm/state/*; printf 'w:c conduct-e\nw:b s\nw:r review-s\n' > "${P}/.swarm/state/e"
  printf '2026-10-26\treview\treview-s\tclaude\tsonnet\thigh\t-\n' > "${P}/.swarm/agents.tsv"
}
# epic_pr [config line]... — fresh, with no inbox, no report and no other story: s of epic e in review
# with prs: ${URL}, the PR merge lands, and herdr laid out as lay leaves it.
epic_pr() {
  settle; rm -rf "${P}/.swarm/inbox" "${P}/.swarm/conduct-e.report.md" "${ROOT}/proj-wt"; fresh "$@"; rm -f "${P}"/docs/stories/*.md
  item s "status: review" "prs: ${URL}" "epic: e"; lay
}
noted() { grep -qF -- "$1" "${INBOX}" 2>/dev/null; }
finished() { if grep -qxF -- "${FIN}" "${INBOX}" 2>/dev/null; then echo finish; else echo hold; fi; }
# review <args> — swarm.sh review outside herdr (its note still reads herdr's list); sets rc, output in ${ROOT}/out.
review() {
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" review "$@" > "${ROOT}/out" 2>&1) || rc=$?
}
# panes_in — herdr's panes now, as "<agent, else pane>@<tab label>", sorted, space-separated.
panes_in() {
  awk 'FILENAME ~ /tabs$/ { l[$1] = $2; next } FILENAME ~ /agents$/ { n[$2] = $1; next }
       { print (($1 in n) ? n[$1] : $1) "@" l[$2] }' "${H}/tabs" "${H}/agents" "${H}/panes" | sort | paste -sd' ' -
}

# --- The hold: s merges while s2 of e is ready with its PR open, not yet in review. The note goes,
# with no finish: line.
epic_pr; item s2 "status: ready" "prs: ${U2}" "epic: e"; merge "${URL}"
is "a merge while s2 of e has an open PR not in review: exits 0" 0 "${rc}"
check "a merge while s2 of e has an open PR not in review: the note goes" noted "The PR ${URL} of story s just merged"
is "a merge while s2 of e has an open PR not in review: no finish: line" hold "$(finished)"

# --- The last agent-owned story of e merges, from the lead's pane, with b still on the board, blocked
# on l, a kind: lead story: b is the user's to clear, so the note ends with the finish: line. Its
# reconcile closes review-s, and once the conductor has written its report next collects it.
epic_pr; item l "status: ready" "kind: lead" "epic: e"; item b "status: blocked" "depends_on: [l]" "epic: e"
merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"
is "the last merge of e, b blocked on kind: lead l: exits 0" 0 "${rc}"
# The inbox ends each note with a blank line: the note's last line is its last one with text.
is "the last merge of e, b blocked on kind: lead l: the note ends with the finish: line" "${FIN}" "$(sed '/^$/d' "${INBOX}" | tail -1)"
is "the last merge of e: herdr lists no review-<slug> pane of e, the conductor's left" "conduct-e@e lead@lead" "$(panes_in)"
echo report > "${P}/.swarm/conduct-e.report.md"
out="$(cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID=w:lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" next 2>&1 | sed -n 1p)" || true
is "the last merge of e, with the report written: next collects conduct-e" "collect conduct-e" "${out}"

# --- merge = human: the review agent hands s2 over with swarm.sh review. While s3 is still ready the
# handover note has no finish: line; once s3 is handed over too, every agent-owned story of e is in
# review, and its note ends with it.
epic_pr "merge = human"; item s2 "status: ready" "prs: ${U2}" "epic: e"; item s3 "status: ready" "prs: https://github.com/o/r/pull/9" "epic: e"
review s2 "${U2}"
is "merge = human, s2 handed over while s3 is still ready: exits 0" 0 "${rc}"
check "merge = human, s2 handed over while s3 is still ready: the handover note goes" noted "Story s2 is in review: its PR ${U2} now waits to be merged."
is "merge = human, s2 handed over while s3 is still ready: no finish: line" hold "$(finished)"
settle; rm -rf "${P}/.swarm/inbox"; review s3 https://github.com/o/r/pull/9
is "merge = human, s3 handed over, every story of e in review: exits 0" 0 "${rc}"
is "merge = human, s3 handed over, every story of e in review: the finish: line" finish "$(finished)"
# The same handover, s2's, with other work of e left: s3 blocked on x, a story of e an agent builds,
# holds it; so does a fix-main story the conductor started (its worktree is there), until its PR merges,
# in review under merge = human too.
epic_pr "merge = human"; item s2 "status: ready" "prs: ${U2}" "epic: e"; item x "status: ready" "kind: code" "epic: e"
item s3 "status: blocked" "depends_on: [x]" "epic: e"; review s2 "${U2}"
is "merge = human, s2 handed over while s3 waits on x, an agent's story of e: no finish: line" hold "$(finished)"
epic_pr "merge = human"; item s2 "status: ready" "prs: ${U2}" "epic: e"; item fix-main-abc1234 "status: review" "kind: code" "prs: https://github.com/o/r/pull/11"
mkdir -p "${ROOT}/proj-wt/fix-main-abc1234"; review s2 "${U2}"
is "merge = human, s2 handed over while a started fix-main story is in review: no finish: line" hold "$(finished)"
# s3 blocked by hand (no depends_on) is the lead's to ready, as is one blocked on a kind: lead story:
# it holds nothing up.
epic_pr "merge = human"; item s2 "status: ready" "prs: ${U2}" "epic: e"; item s3 "status: blocked" "epic: e"; review s2 "${U2}"
is "merge = human, s2 handed over while s3 is blocked by hand: the finish: line" finish "$(finished)"
# s4 waits on s3, an agent's story that waits on l, a kind: lead story: neither can move until the lead
# acts, so neither holds anything up.
epic_pr "merge = human"; item s2 "status: ready" "prs: ${U2}" "epic: e"; item l "status: ready" "kind: lead" "epic: e"
item s3 "status: blocked" "depends_on: [l]" "epic: e"; item s4 "status: blocked" "depends_on: [s3]" "epic: e"; review s2 "${U2}"
is "merge = human, s2 handed over while s4 waits on s3, which waits on kind: lead l: the finish: line" finish "$(finished)"

# --- merge = agent: s2, which costs money, is handed to the user with swarm.sh review. s3 in review is
# its review agent's to merge next, so still agent work; once s3 costs money too, only the user merges
# it, and it holds nothing up. s, epic_pr's, is gone: in review at no cost it would count too.
epic_pr; rm "${S}"; item s2 "status: ready" "prs: ${U2}" "epic: e" "costs: money"; item s3 "status: review" "prs: https://github.com/o/r/pull/9" "epic: e"
review s2 "${U2}"
is "merge = agent, s2 handed over while s3 is in review for its review agent to merge: exits 0" 0 "${rc}"
is "merge = agent, s2 handed over while s3 is in review for its review agent to merge: no finish: line" hold "$(finished)"
epic_pr; rm "${S}"; item s2 "status: ready" "prs: ${U2}" "epic: e" "costs: money"
item s3 "status: review" "prs: https://github.com/o/r/pull/9" "epic: e" "costs: money"; review s2 "${U2}"
is "merge = agent, s2 handed over while s3 in review costs money, so waits on the user: the finish: line" finish "$(finished)"

finish epic-finish
