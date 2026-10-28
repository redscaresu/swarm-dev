#!/usr/bin/env bash
# review_handoff_gaps_test.sh — every way a review agent stops reaches an owner, and a new head is never
# left unreviewed (bin/lib/build.sh's review_rule, review_handoff, review_brief, review_agent,
# review_at_head, story_conductor and build_story; bin/lib/lifecycle.sh's stop_lines):
# 1. a stop on a moved head sends the conductor a stop note, and the conductor starts a new review on it;
# 2. review-agent's worktree refusal names a base-merged head, and the conductor has the builder pull
#    the PR's head on a second refusal with no such line;
# 3. review-agent refuses a head its findings file passes;
# 4. a held: stop note (review held a stacked story) waits for the parent's merge;
# 5. a fix-main story's stop note goes to the conductor that started its build;
# 6. wait --lead prints a stopped: line for a stop note no running conductor has.
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
git -C "${SRC}" update-ref refs/remotes/origin/main "${A}"
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
check "1 the stop note goes to s1's epic conductor" yes "$(has 'note '"${F%.md}"'.stop.md`' "${brief}")"
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
check "2 a second refusal with no base-merged line has the builder pull the PR's head" yes \
  "$(has 'builder idle and no such line, the builder'"'"'s worktree is behind the PR: nudge it once, with a file telling it to pull the PR'"'"'s head (`git pull --ff-only origin story/<slug>`), as `swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>` in the background' "${rule}")"

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

# --- 4. A held: stop note waits for the parent's merge.
check "4 a held: stop note nudges no builder and starts no review" yes \
  "$(has 'A why that starts `held: <slug> waits for <p> to merge` is a stacked story `swarm.sh review` held until its parents merge: nudge no builder and start no review agent' "${rule}")"
check "4 the new head after the parent's merge gets its review" yes \
  "$(has 'once <p> merges, the Stacked rule above has its builder merge it in, and that new head gets its review agent then' "${rule}")"

# --- 5. A fix-main story's stop note goes to the conductor that started its build.
check "5 with no build record, a story with no epic goes to the backlog conductor" yes \
  "$(lib 'c="$(story_conductor fix-main-abc1234)"; [[ "${c}" == "$(conductor_name backlog)" ]] && echo yes || echo "no: ${c}"')"
# build_story, run by the epic's conductor (SWARM_AGENT), with what it calls past the worktree stubbed.
build='touches_overlap() { :; }; story_role() { echo build; }; story_env() { :; }; policy() { :; }; require_trusted() { :; }
  goal_preflight() { PREFLIGHT_GOAL=""; }; base_for() { echo main; }; build_exists() { return 1; }; open_parents() { :; }
  story_brief() { echo brief; }; start_agent() { :; }; worktree_for() { echo "'"${ROOT}"'/fix-wt"; }
  build_story fix-main-abc1234'
# unbuild — remove the build build_story made, so it can start again.
unbuild() { git -C "${SRC}" worktree remove --force "${ROOT}/fix-wt"; git -C "${SRC}" branch -q -D story/fix-main-abc1234; }
mkdir -p "${P}/.swarm/briefs"; echo conduct-old > "${P}/.swarm/briefs/fix-main-abc1234.conductor"
lib "${build}"
check "5 a lead-started build records no conductor, an earlier build's record gone" no "$( [[ -e "${P}/.swarm/briefs/fix-main-abc1234.conductor" ]] && echo yes || echo no)"
unbuild
SWARM_AGENT=conduct-e lib "${build}"
check "5 swarm.sh story records the conductor that started the build" conduct-e "$(cat "${P}/.swarm/briefs/fix-main-abc1234.conductor" 2>/dev/null)"
check "5 story_conductor names that conductor" conduct-e "$(lib 'story_conductor fix-main-abc1234')"
fbrief="$(flat "$(lib 'review_brief fix-main-abc1234 '"${URL}"' main '"${P}"'/.swarm/reviews/fix-main-abc1234.md '"${HB}"' 1')")"
check "5 the review brief tells that conductor its stop note" yes \
  "$(has 'tell conduct-e note '"${P}"'/.swarm/reviews/fix-main-abc1234.stop.md`' "${fbrief}")"
check "5 an epic story's stop note still goes to its epic's conductor" conduct-e "$(lib 'story_conductor s1')"

# --- 6. wait --lead: a stopped: line for a stop note no running conductor has.
# herdr lists the agents in ${ROOT}/agents; each poll is one `swarm.sh wait --lead 0`, which reads the queue once.
printf '#!/bin/sh\ncase "$1 $2" in\n  "agent list") printf '"'"'{"result":{"agents":[%%s]}}\\n'"'"' "$(cat "%s/agents" 2>/dev/null)" ;;\n  *) echo '"'"'{"result":{}}'"'"' ;;\nesac\n' "${ROOT}" > "${ROOT}/bin/herdr"
chmod +x "${ROOT}/bin/herdr"
: > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"
poll() {
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:lead \
    bash "${SWARM}" wait --lead 0 2>/dev/null) || true
}
NOTE="review-s1 stopped on ${HB}: no fix pushed: the builder declined nothing"
STOP="${P}/.swarm/reviews/s1.stop.md"
LINE="stopped: s1 (${NOTE}), exit: act on its why as conduct-e's review rule says, or start a conductor for the story and send it the note with swarm.sh tell <conductor> note ${STOP}"
fresh_lead() { rm -rf "${P}/.swarm/lead"; mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"; }
echo "${HB}" > "${P}/.swarm/reviews/s1.head"; touch -t 202610280900 "${P}/.swarm/reviews/s1.head"
echo "${NOTE}" > "${STOP}"; touch -t 202610281000 "${STOP}"
fresh_lead
check "6 a stop note with no conductor running wakes the lead" "${LINE}" "$(poll)"
check "6 it wakes the lead once" "" "$(poll)"
rm -rf "${P}/.swarm/lead"
check "6 it is an alert: a run's first read prints it" "${LINE}" "$(poll)"
fresh_lead
printf '{"name":"conduct-e","agent_status":"working","pane_id":"w:p1"}' > "${ROOT}/agents"; echo "w:p1 conduct-e" > "${P}/.swarm/state/tab"
check "6 a running conductor has the note: no line" "" "$(poll)"
mkdir -p "${P}/.swarm"; echo report > "${P}/.swarm/conduct-e.report.md"
fresh_lead
check "6 a conductor that wrote its report has stopped: the line comes" "${LINE}" "$(poll)"
rm -f "${P}/.swarm/conduct-e.report.md"; : > "${ROOT}/agents"; : > "${P}/.swarm/state/tab"
touch -t 202610281100 "${P}/.swarm/reviews/s1.head"
fresh_lead
check "6 a review agent started since the note: no line" "" "$(poll)"
touch -t 202610280900 "${P}/.swarm/reviews/s1.head"
sed -i.bak 's/^status: ready/status: done/' "${B}/stories/s1.md"
fresh_lead
check "6 a story that is done: no line" "" "$(poll)"
sed -i.bak 's/^status: done/status: ready/' "${B}/stories/s1.md"; rm -f "${B}/stories/s1.md.bak"
rm -f "${STOP}"
fresh_lead
check "6 no stop note: no line" "" "$(poll)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
