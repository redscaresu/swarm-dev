#!/usr/bin/env bash
# review_handoff_gaps_test.sh — every way a review agent stops reaches an owner, and a new head is never
# left unreviewed (bin/lib/build.sh's review_rule, review_handoff, review_brief, review_agent,
# review_at_head and story_conductor; bin/lib/lifecycle.sh's stop_lines):
# 1. a stop on a moved head sends the conductor a stop note, and the conductor starts a new review on it;
# 2. review-agent's worktree refusal names a base-merged head, and the conductor has the builder pull
#    the PR's head on a second refusal with no such line;
# 3. review-agent refuses a head its findings file passes;
# 4. a held: stop note (review held a stacked story) waits for the parent's merge;
# 5. a fix-main story's stop note goes to the conductor that started its build;
# 6. wait --lead prints a stopped: line for a stop note no running conductor has;
# 7. review-agent starts again, up to 3 starts, when a start ran nothing;
# 8. a round whose dropped-lines finding went to the builder wakes no no-review: line;
# 9. review_verify: round 1 may run tests only under full, and later rounds (review-agent --next) trust CI;
# 10. codex-review runs with the PR (SWARM_PR), and a decline the builder gave a reason for is logged with --because;
# 11. the round cap: from round 3 (CAP_ROUND) the brief and review-agent --next send only regressions and
#     false lines and defer the rest, and finding_rule logs a deferred finding proved real as escaped.
# shellcheck disable=SC2016 # the backticks in the briefs' text are literal
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo no; fi; }
flat() { tr -s '[:space:]' ' ' <<< "$1"; }

# A project whose board holds the epic e, its story s1, and fix-main-abc1234 with no epic; and a repo
# svc with two commits, A and B, whose clone wt (s1's worktree) is at A.
P="${ROOT}/proj"; B="${P}/docs"
mkdir -p "${P}/.claude/swarm" "${B}/stories" "${B}/epics" "${P}/.swarm/state" "${ROOT}/bin"
printf -- '---\nstatus: active\n---\n\n# e\n' > "${B}/epics/e.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e\ntouches: [x.sh]\n---\n\n# s1\n\n**Done when:**\n- it holds\n' > "${B}/stories/s1.md"
printf -- '---\nstatus: ready\nkind: code\ntouches: [x.sh]\n---\n\n# fix-main-abc1234\n\n**Done when:**\n- main is green\n' > "${B}/stories/fix-main-abc1234.md"
"${GIT[@]}" -C "${P}" init -q
SRC="${ROOT}/svc"; WT="${ROOT}/wt"
"${GIT[@]}" init -q "${SRC}"
"${GIT[@]}" -C "${SRC}" commit -q --allow-empty -m a; A="$(git -C "${SRC}" rev-parse HEAD)"
"${GIT[@]}" -C "${SRC}" commit -q --allow-empty -m b; HB="$(git -C "${SRC}" rev-parse HEAD)"
git clone -q "${SRC}" "${WT}"; git -C "${WT}" checkout -q "${A}"
URL=https://github.com/o/svc/pull/7
mkdir -p "${P}/.swarm/reviews"
F="${P}/.swarm/reviews/s1.md"

# lib <code> — <code> run with swarm.sh's libraries loaded for the project; die as swarm.sh's, and the
# PR's head, the story's repo and its worktree stubbed: gh answers HB, the repo is svc, the worktree wt.
lib() {
  # shellcheck disable=SC1090,SC1091 # the libraries, from the repo under test
  PROJECT_DIR="${P}" BOARD="${B}" SWARM_HOME="${REPO}" STATE_DIR="${P}/.swarm/state" HB="${HB}" SRC="${SRC}" WT="${WT}" bash -c '
    CFG_merge=agent; CFG_goal=off; CFG_codex_minutes=10
    die() { echo "swarm: $*" >&2; exit 1; }
    agent_name() { printf "%s" "$1"; }
    story_items() { sed -n "/^\*\*$2:\*\*/,/^\$/p" "$1"; }
    for f in agents reports build board merge lifecycle dash; do . "${SWARM_HOME}/bin/lib/${f}.sh"; done
    gh() { echo "${HB}"; }
    repo_dir() { echo "${SRC}"; }
    worktree_for() { echo "${WT}"; }
    eval "$1"' _ "$1" 2>&1
}

# --- 1. A stop on a moved head sends the conductor a stop note, which starts a new review.
brief="$(flat "$(lib 'review_brief s1 '"${URL}"' main '"${F}"' '"${HB}"' 1')")"
check "1 the brief sends the stop note on every moved-head stop" yes \
  "$(has 'A stop on a moved head, wherever this brief or `review-agent --next` has you write '"${F}"' with a `head moved:` line, sends the conductor the same stop note' "${brief}")"
lbrief="$(flat "$(lib 'CFG_escalate_ladder=sonnet,opus; review_brief s1 '"${URL}"' main '"${F}"' '"${HB}"' 1')")"
check "1 with the ladder on, a stepped up: stop, whose head did not move, sends no stop note" yes \
  "$(has 'line, unless that line names a `stepped up:` build, whose head has not moved' "${lbrief}")"
check "1 with the ladder off, the brief names no step-up" no "$(has 'stepped up' "${brief}")"
check "1 the pass step's moved head sends the stop note before it stops" yes \
  "$(has 'then send the conductor the stop note, as below, naming that `head moved:` line, and stop' "${brief}")"
check "1 the stop note goes to s1's epic conductor" yes "$(has 'tell conduct-e note '"${F%.md}"'.stop.md`' "${brief}")"
rule="$(flat "$(lib review_rule)")"
check "1 the conductor starts a new review on a head moved: note" yes \
  "$(has 'A why that starts `head moved:` names a head that review agent never reviewed: start the review agent again on the PR at once' "${rule}")"
check "1 a still-working refusal on that note waits on the review agent once" yes \
  "$(has 'start it again once `swarm.sh wait review-<slug>` returns, in the background, the one wait on a review agent you run' "${rule}")"

# --- 2. The worktree refusal names a base-merged head; with none, a second refusal has the builder pull.
: > "${P}/.swarm/events.tsv"
out="$(lib 'review_at_head s1 '"${URL}"'' || true)"
check "2 a worktree behind a head with no base-merged line: wait for the builder" yes \
  "$(has "review-agent: s1's worktree is at ${A}, not the PR's head ${HB}; nothing was started: wait for its builder, then start the review again" "${out}")"
printf '2026-10-28T10:00:00Z\tmerge\ts1\tw:1\tbase-merged %s from %s\n' "${HB}" "${A}" > "${P}/.swarm/events.tsv"
out="$(lib 'review_at_head s1 '"${URL}"'' || true)"
check "2 a worktree behind a base-merged head: the refusal says start no review" yes \
  "$(has "which is GitHub's merge of the base into the PR (events.tsv's base-merged ${HB}); nothing was started: the swarm.sh merge that made it waits on it and merges it, so start no review for it" "${out}")"
out="$(lib 'review_at_head s1 '"${URL}"' next' || true)"
check "2 review-agent --next's refusal is its own, base-merged or not" yes \
  "$(has "review-agent --next: s1's worktree is at ${A}, not the PR's head ${HB}; no round was started: wait for its builder" "${out}")"
: > "${P}/.swarm/events.tsv"
check "2 the conductor starts nothing for a head the refusal calls a base merge" yes \
  "$(has 'When the refusal says the PR'"'"'s head is GitHub'"'"'s merge of the base (events.tsv'"'"'s `base-merged <sha>`), start nothing for that head' "${rule}")"
check "2 a second refusal with no base-merged line has the builder pull for a worktree behind the PR, and commit, push or set aside uncommitted changes" yes \
  "$(has 'builder idle and no such line, nudge the builder once, with a file telling it, when the refusal says its worktree is at another commit (behind the PR), to pull the PR'"'"'s head (`git pull --ff-only origin story/<slug>`), or, when it says the worktree has uncommitted changes, to commit and push them, or discard each by copying its file aside, as `swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>` in the background' "${rule}")"

# --- 3. review-agent refuses a head its findings file passes; the start goes on otherwise.
start='review_at_head() { REVIEW_SRC="${SRC}"; REVIEW_WT="${WT}"; REVIEW_HEAD="${HB}"; }
  agent_field() { :; }; require_trusted() { echo "start went on"; exit 0; }
  review_agent s1 '"${URL}"
printf 'head: %s\n## Findings\nnone\n## Handled by the review agent\nnone\n' "${HB}" > "${F}"
check "3 a pass of the PR's head on a story still ready (its hand-off failed): the start goes on" "start went on" "$(lib "${start}" || true)"
sed -i.bak 's/^status: ready/status: review/' "${B}/stories/s1.md"
out="$(lib "${start}" || true)"
check "3 a pass of the PR's head, the story in review: review-agent refuses" yes \
  "$(has "review-agent: ${F} is a pass of ${HB}, the PR's head, and s1 is no longer ready, so its hand-off (review, then merge or the user's merge) has the PR; nothing was started" "${out}")"
check "3 the refused start touched no file" "head: ${HB}" "$(head -1 "${F}")"
printf 'head: %s\n## Findings\nnone\n' "${A}" > "${F}"
check "3 a pass of an older head: the start goes on" "start went on" "$(lib "${start}" || true)"
printf 'head: %s\nhead moved: %s\n' "${HB}" "${A}" > "${F}"
check "3 a head moved: file on the head: the start goes on" "start went on" "$(lib "${start}" || true)"
printf 'head: %s\nstopped: no fix pushed\n' "${HB}" > "${F}"
check "3 a stopped: file on the head: the start goes on" "start went on" "$(lib "${start}" || true)"
rm -f "${F}"; mv "${B}/stories/s1.md.bak" "${B}/stories/s1.md"
check "3 the conductor starts nothing on a pass refusal" yes \
  "$(has 'When review-agent refuses because its findings file is a pass of that head and the story is no longer ready, the review passed and its hand-off has the PR: start nothing for that head' "${rule}")"

# --- 4. A held: stop note waits for the parent's merge. The note is the one an agent writes from what
# swarm.sh review prints when it holds a stacked story (its die, so after `swarm: `), as review_handoff
# says, matched against the pattern the rule gives, with its placeholders filled.
held="$(lib 'review_state() { REVIEW_HELD=p; }; money_walk() { :; }; mark_review s1 '"${URL}" || true)"
check "4 swarm.sh review's hold is printed after swarm: " yes "$(has 'swarm: held: s1 waits for p to merge' "${held}")"
note="review-s1 stopped on ${HB}: ${held%%$'\n'*}"
pat="$(sed -n 's/.*A why that holds `\(held: <slug> waits for <p> to merge\)` (swarm\.sh review.s refusal, which it prints after `swarm: `) is a stacked story `swarm\.sh review` held until its parents merge: nudge no builder and start no review agent.*/\1/p' <<< "${rule}")"
pat="${pat//<slug>/s1}"; pat="${pat//<p>/p}"
check "4 the rule's held: pattern matches the note an agent writes, and nudges no builder and starts no review" yes \
  "$([[ -n "${pat}" && "${note}" == *"${pat}"* ]] && echo yes || echo "no: pattern '${pat}', note '${note}'")"
check "4 the new head after the parent's merge gets its review" yes \
  "$(has 'once <p> merges, the Stacked rule above has its builder merge it in, and that new head gets its review agent then' "${rule}")"

# --- 5. A fix-main story's stop note goes to the conductor that started its build.
: > "${P}/.swarm/events.tsv"
check "5 with no start on record, a story with no epic goes to the backlog conductor" yes \
  "$(lib 'c="$(story_conductor fix-main-abc1234)"; [[ "${c}" == "$(conductor_name backlog)" ]] && echo yes || echo "no: ${c}"')"
# The epic's conductor, in pane w:p3 by its tab record, ran swarm.sh story for it.
echo "w:p3 conduct-e" > "${P}/.swarm/state/conduct-tab"
printf '2026-10-28T10:00:00Z\tstory\tfix-main-abc1234\tw:p3\tok\n' > "${P}/.swarm/events.tsv"
check "5 story_conductor names the conductor that started the build" conduct-e "$(lib 'story_conductor fix-main-abc1234')"
fbrief="$(flat "$(lib 'review_brief fix-main-abc1234 '"${URL}"' main '"${P}"'/.swarm/reviews/fix-main-abc1234.md '"${HB}"' 1')")"
check "5 the review brief tells that conductor its stop note" yes \
  "$(has 'tell conduct-e note '"${P}"'/.swarm/reviews/fix-main-abc1234.stop.md`' "${fbrief}")"
check "5 an epic story's stop note still goes to its epic's conductor" conduct-e "$(lib 'story_conductor s1')"
rm -f "${P}/.swarm/state/conduct-tab"; : > "${P}/.swarm/events.tsv"

# --- 6. wait --lead: a stopped: line for a stop note no running conductor has.
# herdr lists the agents in ${ROOT}/agents; each poll is one `swarm.sh wait --lead 0`, which reads the queue once.
printf '#!/bin/sh\ncase "$1 $2" in\n  "agent list") printf '"'"'{"result":{"agents":[%%s]}}\\n'"'"' "$(cat "%s/agents" 2>/dev/null)" ;;\n  *) echo '"'"'{"result":{}}'"'"' ;;\nesac\n' "${ROOT}" > "${ROOT}/bin/herdr"
# ps: the real one, except that a process list (-A) holds only this run's processes, which start no
# swarm.sh of their own. The poll reads the machine's whole list for a process that answers for s1 (a
# `swarm.sh tell s1`, `step-up s1` or `wait-pr` on its PR), and another test running one at the same
# time (step_up_slow_start_test.sh's `swarm.sh step-up s1 stalled`, in the same CI shard) would make s1
# busy here and the no-review: case below quiet.
# shellcheck disable=SC2016 # the stub's own shell expands $*
printf '#!/bin/sh\ncase " $* " in *" -A "*) %s "$@" | grep -F "%s"; exit 0 ;; esac\nexec %s "$@"\n' \
  "$(command -v ps)" "${ROOT}" "$(command -v ps)" > "${ROOT}/bin/ps"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/ps"
: > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"
# poll [grace] — with no grace given, a stop note is reported at any age (SWARM_STOP_GRACE=0).
poll() {
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:lead SWARM_STOP_GRACE="${1:-0}" \
    bash "${SWARM}" wait --lead 0 2>/dev/null) || true
}
NOTE="review-s1 stopped on ${HB}: no fix pushed: the builder declined nothing"
STOP="${P}/.swarm/reviews/s1.stop.md"
LINE="stopped: s1 (${NOTE}), exit: act on its why as conduct-e's review rule says, or start a conductor for the story and send it the note with swarm.sh tell <conductor> note ${STOP}"
fresh_lead() { rm -rf "${P}/.swarm/lead"; mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"; }
echo "${NOTE}" > "${STOP}"
fresh_lead
# A note just written may be a model turn from its tell: it waits out the grace period first.
check "6 a stop note younger than the grace period waits for its tell: no line" "" "$(poll 120)"
touch -t 202610010900 "${STOP}"
fresh_lead
check "6 a stop note older than the grace period with no conductor running wakes the lead" "${LINE}" "$(poll 120)"
fresh_lead
check "6 a stop note with no conductor running wakes the lead" "${LINE}" "$(poll)"
check "6 it wakes the lead once" "" "$(poll)"
rm -rf "${P}/.swarm/lead"
check "6 it is an alert: a run's first read prints it" "${LINE}" "$(poll)"
# A conductor has the note only when the tell reached it (tell's .told marker) and it still runs.
running() { printf '{"name":"conduct-e","agent_status":"working","pane_id":"w:p1"}' > "${ROOT}/agents"; echo "w:p1 conduct-e" > "${P}/.swarm/state/tab"; }
fresh_lead; running
check "6 a conductor started after a failed tell never got the note: the line comes" "${LINE}" "$(poll)"
mkdir -p "${P}/.swarm/briefs"; echo brief > "${P}/.swarm/briefs/conduct-e.md"; touch -t 202610010900 "${P}/.swarm/briefs/conduct-e.md"
told() { echo conduct-e > "${STOP%.md}.told"; touch -t "$1" "${STOP%.md}.told"; }
touch -t 202610011000 "${STOP}"; told 202610011000
fresh_lead
check "6 a running conductor the tell reached has the note: no line" "" "$(poll)"
touch -t 202610011100 "${P}/.swarm/briefs/conduct-e.md"
fresh_lead
check "6 that conductor started again since (its inbox cleared): the line comes" "${LINE}" "$(poll)"
touch -t 202610010900 "${P}/.swarm/briefs/conduct-e.md"
touch -t 202610011200 "${STOP}"
fresh_lead
check "6 a newer note than the tell's marker: the line comes" "${LINE}" "$(poll)"
touch -t 202610011000 "${STOP}"
echo report > "${P}/.swarm/conduct-e.report.md"
fresh_lead
# s1 is still an agent's, so the report gives a reported: line after it (wait_lead_test.sh).
check "6 a conductor that wrote its report has stopped: the line comes" \
  "${LINE}"$'\n'"reported: e (1 stories still an agent's), exit: swarm.sh conduct e" "$(poll)"
rm -f "${P}/.swarm/conduct-e.report.md" "${STOP%.md}.told" "${P}/.swarm/briefs/conduct-e.md"; : > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"
# The tell itself leaves the marker: swarm.sh tell <conductor> note <stop note>, to conduct-e in its pane.
running
(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:p9 \
  bash "${SWARM}" tell conduct-e note "${STOP}" > /dev/null 2>&1) || true
check "6 a stop note told to a conductor leaves a marker naming it" conduct-e "$(cat "${STOP%.md}.told" 2>/dev/null)"
rm -f "${STOP%.md}.told" "${P}/.swarm/inbox/conduct-e.md"; : > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"

# A story in review is shown only while a review agent still acts on it: not once merge held it for the user.
sed -i.bak 's/^status: ready/status: review/' "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"
echo "merge = agent" > "${P}/.claude/swarm/config"
fresh_lead
check "6 a story in review its review agent still merges (merge = agent): the line comes" "${LINE}" "$(poll)"
printf '2026-10-28T11:00:00Z\tmerge\ts1\tw:1\tunconfirmed: the merge of %s was not confirmed\n' "${URL}" > "${P}/.swarm/events.tsv"
fresh_lead
check "6 a story in review whose merge went unconfirmed goes to the lead: the line comes" "${LINE}" "$(poll)"
printf '2026-10-28T11:00:00Z\tmerge\ts1\tw:1\theld: s1 costs money; the user merges it\n' > "${P}/.swarm/events.tsv"
fresh_lead
check "6 a story in review that merge held for the user's merge: no line" "" "$(poll)"
: > "${P}/.swarm/events.tsv"; rm -f "${P}/.claude/swarm/config"
fresh_lead
check "6 a story in review under merge = human, the user's: no line" "" "$(poll)"
sed -i.bak 's/^status: review/status: ready/' "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"

# review-agent's start removes the earlier agent's note, so the line goes; a refused start, or a failed one
# with no agent running, keeps it; an unclear start whose agent runs drops it.
stubs='review_at_head() { REVIEW_SRC="${SRC}"; REVIEW_WT="${WT}"; REVIEW_HEAD="${HB}"; }
  require_trusted() { :; }; require_claude() { :; }; free_agent_name() { :; }; base_for() { echo main; }'
# review-<slug> still open with no findings file: review-agent refuses before it touches a file.
lib "${stubs}; agent_field() { echo w:p7; }; start_agent() { :; }; review_agent s1 ${URL}" > /dev/null || true
check "6 a refused review-agent start keeps the note" "${NOTE}" "$(cat "${STOP}" 2>/dev/null)"
# herdr surely sent nothing and no pane is listed: review_start_failed dies.
lib "set -o pipefail; ${stubs}; agent_field() { :; }; herdr() { :; }; start_agent() { echo no pane >&2; return 1; }; review_agent s1 ${URL}" > "${ROOT}/failed" 2>&1 || true
check "6 a review-agent start that fails with no agent running puts the note back" "yes|${NOTE}" \
  "$(has 'review-agent: review-s1 did not start' "$(cat "${ROOT}/failed")")|$(cat "${STOP}" 2>/dev/null)"
# The brief may have gone out, and the agent the start left runs (busy): review_start_failed returns.
lib "set -o pipefail; ${stubs}; agent_field() { [[ ! -e '${ROOT}/began' ]] || echo w:p7; }; read_state() { echo busy; }
  start_agent() { touch '${ROOT}/began'; echo herdr sent it the brief >&2; return 1; }; review_agent s1 ${URL}" > "${ROOT}/failed" 2>&1 || true
rm -f "${ROOT}/began"
check "6 an unclear start whose agent runs drops the earlier agent's note" "yes|no|no" \
  "$(has 'but the agent is running' "$(cat "${ROOT}/failed")")|$( [[ -f "${STOP}" ]] && echo yes || echo no)|$( [[ -f "${STOP}.prev" ]] && echo yes || echo no)"
echo "${NOTE}" > "${STOP}"
lib "${stubs}; agent_field() { :; }; start_agent() { :; }; review_agent s1 ${URL}" > /dev/null
check "6 a review-agent start removes the earlier agent's note" "no|no" "$( [[ -f "${STOP}" ]] && echo yes || echo no)|$( [[ -f "${STOP}.prev" ]] && echo yes || echo no)"
fresh_lead
check "6 a review agent started since the note: no line" "" "$(poll)"
echo "${NOTE}" > "${STOP}"
sed -i.bak 's/^status: ready/status: done/' "${B}/stories/s1.md"
fresh_lead
check "6 a story that is done: no line" "" "$(poll)"
sed -i.bak 's/^status: done/status: ready/' "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"
rm -f "${STOP}"
fresh_lead
check "6 no stop note: no line" "" "$(poll)"

# --- 1 (wait --lead). A pass refusal changes nothing for no-review: under merge = agent, after a pass of
# HB, review --head and a merge held for the user, the conductor's restart on that head is refused; the
# story's no-review: line stays quiet, since its exit would be refused the same way. A failed start in
# its place does fire, so the setup can. gh fails here, offline; s1's builder is listed (no no-agent:).
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
echo "merge = agent" > "${P}/.claude/swarm/config"
sed -i.bak 's/^status: ready/status: review/' "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"
printf 'prs: [%s]\n' "${URL}" > "${ROOT}/prs"; sed -i.bak "/^status: review/r ${ROOT}/prs" "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"
mkdir -p "${ROOT}/proj-wt/s1"
printf 'head: %s\n## Findings\nnone\n## Handled by the review agent\nnone\n' "${HB}" > "${F}"; echo "${HB}" > "${F%.md}.head"
printf '{"name":"s1","agent_status":"idle","pane_id":"w:p2"}' > "${ROOT}/agents"; echo "w:p2 s1" > "${P}/.swarm/state/tab"
pass_refused="review-agent: ${F} is a pass of ${HB}, the PR's head, and s1 is no longer ready, so its hand-off (review, then merge or the user's merge) has the PR; nothing was started: a conductor starts nothing for this head, and the lead moves ${F} aside first to review it again"
ev() { printf '2026-10-28T1%s:00:00Z\t%s\ts1\tw:1\t%s\n' "$1" "$2" "$3" >> "${P}/.swarm/events.tsv"; }
: > "${P}/.swarm/events.tsv"; ev 0 story ok; ev 1 review-agent ok; ev 2 review "ok (${URL})"; ev 3 merge "held: s1 costs money; the user merges it"
ev 4 review-agent "review-agent: review-s1 did not start (its pane w:p9 is closed)"
fresh_lead
check "1 a failed review-agent start after the pass fires no-review: (the setup can fire it)" yes "$(has 'no-review: s1' "$(poll)")"
: > "${P}/.swarm/events.tsv"; ev 0 story ok; ev 1 review-agent ok; ev 2 review "ok (${URL})"; ev 3 merge "held: s1 costs money; the user merges it"
ev 4 review-agent "${pass_refused}"
fresh_lead
check "1 a review-agent refused on a passed head fires no no-review:" no "$(has 'no-review:' "$(poll)")"
printf '2026-10-28T15:00:00Z\tclose\treview-s1\tw:1\tok\n' >> "${P}/.swarm/events.tsv"
fresh_lead
check "1 nor once review-s1 is closed" no "$(has 'no-review:' "$(poll)")"
rm -f "${F}" "${F%.md}.head" "${P}/.claude/swarm/config" "${ROOT}/bin/gh"; rm -rf "${ROOT}/proj-wt"; : > "${P}/.swarm/events.tsv"; : > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"
sed -i.bak -e 's/^status: review/status: ready/' -e '/^prs: /d' "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"

# --- 7. review-agent starts again, up to 3 starts, when a start ran nothing: herdr's texts
# (docs/lead-by-hand.md, #688) and review_start_failed's yes:none, yes:gone and yes:herdr:. An unclear
# start whose agent runs or cannot be listed makes one start, as before.
# retry <fails> <err> [state] — review_agent s1 as swarm.sh's main runs it, in a subshell under set -e and
# pipefail, out of any condition (its die line, or ok, is the command's own review-agent event), where start_agent fails its first <fails> tries with <err>; with
# [state], a failed start leaves pane w:p7, which read_state reads as [state] (unlisted: herdr cannot
# list agents). herdr's pane list lists RETRY_LIVE's panes, and each pane close goes in ${ROOT}/closed. Prints "<starts>|<naps>|<exit>" and then each review-agent outcome in events.tsv, one a line.
retry() {
  rm -f "${ROOT}/starts" "${ROOT}/naps" "${ROOT}/began" "${ROOT}/closed" "${F}.prev" "${F%.md}.head" "${STOP}.prev"
  echo "head: OLD" > "${F}"; echo "${NOTE}" > "${STOP}"; : > "${P}/.swarm/events.tsv"
  RETRY_FAILS="$1" RETRY_ERR="$2" RETRY_STATE="${3:-}" RETRY_ROOT="${ROOT}" lib "set -o pipefail; ${stubs}
    nap() { echo nap >> \"\${RETRY_ROOT}/naps\"; }
    json() { python3 -c \"import json,os,sys; d=json.load(sys.stdin); e=os.environ; print(\$1)\"; }   # swarm.sh's
    herdr() {
      case \"\$1 \$2\" in
        'pane list') [[ -z \"\${RETRY_LIVE:-}\" ]] || printf '{\"result\":{\"panes\":[{\"pane_id\":\"%s\"}]}}\n' \"\${RETRY_LIVE}\" ;;
        'pane close') echo \"\$3\" >> \"\${RETRY_ROOT}/closed\" ;;
        'agent list') [[ \"\${RETRY_STATE}\" != unlisted ]] ;;
      esac
    }
    agent_field() { [[ -z \"\${RETRY_STATE}\" || \"\${RETRY_STATE}\" == unlisted || ! -e \"\${RETRY_ROOT}/began\" ]] || echo w:p7; }
    read_state() { echo \"\${RETRY_STATE}\"; }; session_took() { :; }; login_expired() { return 1; }
    start_agent() {
      local n; n=\$(( \$(cat \"\${RETRY_ROOT}/starts\" 2>/dev/null || echo 0) + 1 )); echo \"\${n}\" > \"\${RETRY_ROOT}/starts\"
      [[ \${n} -le \${RETRY_FAILS} ]] || return 0
      touch \"\${RETRY_ROOT}/began\"; printf '%s\n' \"\${RETRY_ERR}\" >&2; return 1
    }
    (set -e; review_agent s1 ${URL}) 2> \"\${RETRY_ROOT}/err\"; rc=\$?
    if [[ \${rc} -eq 0 ]]; then record_event review-agent s1 ok
    else record_event review-agent s1 \"\$(sed -n 's/^swarm: //p' \"\${RETRY_ROOT}/err\" | tail -1)\"; fi
    echo \"\$(cat \"\${RETRY_ROOT}/starts\")|\$(cat \"\${RETRY_ROOT}/naps\" 2>/dev/null | wc -l | tr -d ' ')|\${rc}\"" | tail -1
  awk -F'\t' '$2 == "review-agent" && $3 == "s1" { print $5 }' "${P}/.swarm/events.tsv"
}
put_back="; ${F} is put back"
pnf=$'pane w:p9 not found\nswarm: herdr could not open a pane in tab e'
noenv="swarm: review-s1: the pane's shell did not take the agent's environment: timeout waiting for output"
anf="swarm: review-s1: herdr did not send it the brief (agent_not_found); see herdr agent read review-s1"
unclear="swarm: review-s1: it may or may not have the brief: herdr's reply to the brief could not be read once, then agent_prompt_stalled; it was not sent again, see herdr agent read review-s1"
check "7 pane ... not found on the first start: a second start, one event ending (try 1 of 3), then ok" \
  "2|1|0
review-agent: review-s1 did not start${put_back}; it ran nothing: pane not found (try 1 of 3)
ok" "$(retry 1 "${pnf}")"
check "7 the pane's shell did not take the agent's environment: started on the second try" \
  "2|1|0
review-agent: review-s1 did not start${put_back}; it ran nothing: the pane's shell did not take the agent's environment (try 1 of 3)
ok" "$(retry 1 "${noenv}")"
check "7 agent_not_found with nothing sent: started on the second try" \
  "2|1|0
review-agent: review-s1 did not start${put_back}; it ran nothing: agent_not_found with nothing sent (try 1 of 3)
ok" "$(retry 1 "${anf}")"
# agent_not_found: herdr lists no agent, but the pane the start opened is in the tab's record, and still
# open, so it is closed before the next try.
echo "w:p8 review-s1" > "${P}/.swarm/state/e"
check "7 agent_not_found with the start's pane still open: the pane its tab records is closed, then a second start" \
  "2|1|0
review-agent: review-s1 did not start (its pane w:p8 is closed)${put_back}; it ran nothing: agent_not_found with nothing sent (try 1 of 3)
ok|w:p8" "$(RETRY_LIVE=w:p8 retry 1 "${anf}")|$(cat "${ROOT}/closed" 2>/dev/null)"
rm -f "${P}/.swarm/state/e"
check "7 an unclear start with no pane (yes:none): started on the second try" \
  "2|1|0
review-agent: review-s1 did not start${put_back}; it ran nothing: an unclear start with no agent running (none) (try 1 of 3)
ok" "$(retry 1 "${unclear}")"
check "7 an unclear start whose session is gone (yes:gone): started on the second try" \
  "2|1|0
review-agent: review-s1 did not start (its pane w:p7 is closed)${put_back}; it ran nothing: an unclear start with no agent running (gone) (try 1 of 3)
ok" "$(retry 1 "${unclear}" gone)"
check "7 an unclear start herdr has no status for (yes:herdr:): started on the second try" \
  "2|1|0
review-agent: review-s1 did not start (its pane w:p7 is closed)${put_back}; it ran nothing: an unclear start with no agent running (herdr:) (try 1 of 3)
ok" "$(retry 1 "${unclear}" herdr:)"
check "7 three failures in a row: three starts, two naps, the last try's die is the command's event (try 3 of 3)" \
  "3|2|1
review-agent: review-s1 did not start${put_back}; it ran nothing: pane not found (try 1 of 3)
review-agent: review-s1 did not start${put_back}; it ran nothing: pane not found (try 2 of 3)
review-agent: review-s1 did not start${put_back}; it ran nothing: pane not found (try 3 of 3)" "$(retry 3 "${pnf}")"
check "7 and after them the findings file and the stop note are back in place, with nothing left aside" \
  "head: OLD|${NOTE}|no|no|no" \
  "$(cat "${F}")|$(cat "${STOP}")|$([[ -e "${F}.prev" ]] && echo yes || echo no)|$([[ -e "${STOP}.prev" ]] && echo yes || echo no)|$([[ -e "${F%.md}.head" ]] && echo yes || echo no)"
# next_pane's warning, then another failure: the words "pane" and "not found" sit on two lines, which is
# none of herdr's texts.
twoline=$'swarm: herdr would not open a pane at /x in the lead-agents workspace ahead of this one, outside the project; the agent opens in this workspace instead\nswarm: review-s1: python3: command not found'
check "7 not retried: a pane warning, then a failure on another line, makes one start and logs as today with no (try suffix" \
  "1|0|1
review-agent: review-s1 did not start${put_back}" "$(retry 1 "${twoline}")"
check "7 not retried: an unclear start whose agent reads idle with the brief makes one start and logs ok" \
  "1|0|0
ok" "$(retry 1 "${unclear}" idle)"
check "7 not retried: an unclear start herdr cannot list makes one start and logs its die with no (try suffix" \
  "1|0|1
review-agent: review-s1's start was unclear and herdr could not list its agents, so its state is unknown; the last review is kept aside in ${F}.prev; no head is on record. A conductor starts nothing; once herdr answers, the lead looks at it (herdr agent read review-s1) and, to review again, closes it and runs swarm.sh review-agent s1 <PR URL>" \
  "$(retry 1 "${unclear}" unlisted)"
rm -f "${F}" "${F}.prev" "${F%.md}.head" "${STOP}" "${STOP}.prev" "${ROOT}/starts" "${ROOT}/naps" "${ROOT}/began" "${ROOT}/err"; : > "${P}/.swarm/events.tsv"

# --- 8 (wait --lead). A round whose dropped-lines finding went to the builder is a review under way: an
# ok review-agent start on HB (its .head on record, no pass), its log-finding dropped-lines row and an ok
# findings tell wake no no-review:. A guard, not a mutation proof. The control fails that start instead,
# as the newest line: a failed start before the tell would read as a round under way too.
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
printf '{"name":"s1","agent_status":"idle","pane_id":"w:p2"}' > "${ROOT}/agents"; echo "w:p2 s1" > "${P}/.swarm/state/tab"
mkdir -p "${ROOT}/proj-wt/s1"; rm -f "${F}"; echo "${HB}" > "${F%.md}.head"
dropped_round() { # <the review-agent start's outcome> — an ok one starts the round, a failed one ends the log
  : > "${P}/.swarm/events.tsv"; ev 0 story ok
  [[ "$1" != ok ]] || ev 1 review-agent ok
  printf '2026-10-28T12:00:00Z\tlog-finding\tdropped-lines %s\tw:1\tok\n' "${URL}" >> "${P}/.swarm/events.tsv"
  ev 3 tell:findings ok
  [[ "$1" == ok ]] || ev 4 review-agent "$1"
}
dropped_round ok
fresh_lead
check "8 an ok start, a log-finding dropped-lines row and an ok findings tell: no no-review: for s1" no "$(has 'no-review: s1' "$(poll)")"
dropped_round "review-agent: review-s1 did not start (its pane w:p9 is closed)"
fresh_lead
check "8 the same rows with the start failed: a no-review: line for s1 (the control)" yes "$(has 'no-review: s1' "$(poll)")"
rm -f "${ROOT}/bin/gh" "${F%.md}.head"; rm -rf "${ROOT}/proj-wt"; : > "${P}/.swarm/events.tsv"; : > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"

# --- 9. review_verify: only round 1 under full may run tests; every other round trusts CI.
TRUST='read the diff and trust CI for the tests; run no local test suite and no mutation run.'
CI_LINE="Tests (review_verify = ci): ${TRUST}"
LATER_LINE="Tests (review_verify = full, round 2): from round 2 on, ${TRUST}"
FULL_LINE='Tests (review_verify = full): on this round, round 1, you may run the project'"'"'s tests for the files the PR changes'
LATER_CI='Rounds 2 and later run no tests of their own.'
CLEAN='Leave this worktree as you found it: delete any file the tests wrote, so `git status --porcelain` prints nothing at the end-of-review check.'
vbrief() { flat "$(lib "${1:+CFG_review_verify=$1; }"'review_brief s1 '"${URL}"' main '"${F}"' '"${HB}"' '"$2")"; }
b="$(vbrief "" 1)"
check "9 round 1's brief with no review_verify set carries the ci line, not the full one" "yes|no" "$(has "${CI_LINE}" "${b}")|$(has "${FULL_LINE}" "${b}")"
b="$(vbrief ci 1)"
check "9 round 1's brief with review_verify = ci carries the ci line, not the full one" "yes|no" "$(has "${CI_LINE}" "${b}")|$(has "${FULL_LINE}" "${b}")"
b="$(vbrief full 1)"
check "9 round 1's brief with review_verify = full carries the full line, says later rounds run no tests, and has no ci line" "yes|yes|no" \
  "$(has "${FULL_LINE}" "${b}")|$(has "${LATER_CI}" "${b}")|$(has "${CI_LINE}" "${b}")"
check "9 round 1's full line has the agent leave the worktree clean for the end-of-review check" yes "$(has "${CLEAN}" "${b}")"
b="$(vbrief full 2)"
check "9 a brief started on round 2 under review_verify = full trusts CI under its own label, with no ci-labelled or full line" "yes|no|no" \
  "$(has "${LATER_LINE}" "${b}")|$(has "${CI_LINE}" "${b}")|$(has "${FULL_LINE}" "${b}")"
# review-agent --next's round 2 under full, from review-s1's own pane, with the worktree at the PR's head.
next2='CFG_review_verify=full; HERDR_PANE_ID=w:rv
  agent_field() { echo w:rv; }; review_rounds() { echo "2 1"; }; base_for() { echo main; }
  review_at_head() { REVIEW_SRC="${SRC}"; REVIEW_WT="${WT}"; REVIEW_HEAD="${HB}"; }
  review_next s1 '"${URL}"
o="$(flat "$(lib "${next2}")")"
check "9 review-agent --next's round 2 under review_verify = full trusts CI under its own label, with no ci-labelled or full line" "yes|yes|no|no" \
  "$(has "Review round 2 of story s1" "${o}")|$(has "${LATER_LINE}" "${o}")|$(has "${CI_LINE}" "${o}")|$(has "${FULL_LINE}" "${o}")"
rm -f "${F}" "${F}.prev" "${F%.md}.head"

# --- 10. codex sees the PR's earlier declines: review_brief's codex command names the PR, and each line
# that logs a finding the builder declined passes the builder's reason with --because.
b="$(vbrief "" 1)"
check "10 review_brief's codex command carries SWARM_STORY and SWARM_PR=<the PR URL>" yes \
  "$(has "SWARM_STORY=s1 SWARM_PR=${URL} SWARM_PROJECT=" "${b}")"
check "10 both builder-decline logging lines carry --because with the builder's reason" "yes|yes" \
  "$(has 'log each as declined, with `--because "<the builder'"'"'s reason, one line>"`' "${b}")|$(has 'as declined, with the reason that fits and `--because "<the builder'"'"'s reason, one line>"`, when the builder declined it' "${b}")"

# --- 11. The round cap: from round 3 the round line, and so the brief and review-agent --next, sends the
# builder only a regression or a false line and defers the rest; rounds 1 and 2 carry none of it.
CAP='Round cap (from round 3): of the findings that are real and inside the story, send the builder only a regression this PR introduces or a line now false about the code; this replaces the rule that each of them is to fix. Decline the rest as deferred: rebut them in the PR with the other declined ones, and log each with `--declined deferred` and no `--because`, since holding it back is your call, not the builder'"'"'s.'
FIX_ALL='One that is real and inside the story is to fix: the builder fixes it, never you.'
FIX_CAP='Under the round cap above, only a regression this PR introduces or a line now false about the code is to fix: the builder fixes it, never you.'
DEFER='deferred for a real one inside the story that the round cap holds back (from round 3),'
for r in 1 2; do
  b="$(vbrief "" "${r}")"
  check "11 round ${r}'s brief has no cap line, no regression rule and no --declined deferred, fixes every real finding in the story, and names deferred among the reasons" \
    "no|no|no|yes|yes" "$(has "${CAP}" "${b}")|$(has 'a regression this PR introduces' "${b}")|$(has '--declined deferred' "${b}")|$(has "${FIX_ALL}" "${b}")|$(has "${DEFER}" "${b}")"
done
for r in 3 4; do
  b="$(vbrief "" "${r}")"
  check "11 round ${r}'s brief carries the cap line and the capped fix rule, not the fix-every-finding line" "yes|yes|no" \
    "$(has "${CAP}" "${b}")|$(has "${FIX_CAP}" "${b}")|$(has "${FIX_ALL}" "${b}")"
done
check "11 finding_rule has a deferred finding proved real logged as escaped against its PR, its line copied exactly from the deferred row" yes \
  "$(has 'A finding declined as deferred that a later round or a fix finds real, and fixes, is logged as escaped too, against the PR it was deferred on, never as declined (an escaped row is always fixed), and its one line copied exactly from the deferred row'"'"'s text, so the two rows match:' "$(vbrief "" 1)")"
# nextr <round> — review-agent --next's output on round <round>, from review-s1's own pane.
nextr() {
  flat "$(lib 'HERDR_PANE_ID=w:rv
  agent_field() { echo w:rv; }; review_rounds() { echo "'"$1"' 1"; }; base_for() { echo main; }
  review_at_head() { REVIEW_SRC="${SRC}"; REVIEW_WT="${WT}"; REVIEW_HEAD="${HB}"; }
  review_next s1 '"${URL}")"
}
o="$(nextr 2)"
check "11 review-agent --next's round 2 carries no cap line" "yes|no" "$(has 'Review round 2 of story s1' "${o}")|$(has "${CAP}" "${o}")"
o="$(nextr 3)"
check "11 review-agent --next's round 3 carries the cap line, exactly as review_round_line sets it" "yes|yes|yes" \
  "$(has 'Review round 3 of story s1' "${o}")|$(has "${CAP}" "${o}")|$(has "$(flat "$(lib 'review_round_line 3 '"${URL}")")" "${o}")"
rm -f "${F}" "${F}.prev" "${F%.md}.head"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
