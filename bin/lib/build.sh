# shellcheck shell=bash

# findings_goal <slug> <since> <goal-file> — send the builder a fresh /goal mid-turn, once its findings
# are taken up, so the goal drives the fix (sent after the turn, the judge would find it met at once): the
# findings addressed, the reply its brief asks for in its mode, and the turn bound. Mid-turn it sets at
# once and costs one extra short turn, as build_story's does. send_goal confirms it from entries newer
# than the tell, so the build-time goal never counts; a refusal or no entry fails naming the story.
findings_goal() {
  # shellcheck disable=SC2154 # assigned in another file
  printf '%s %s %s\n' "The goal: the conductor's review findings, sent to you just before this goal, are addressed (each fixed, or declined with a reason in your reply) and you have replied." \
    "$(reply_sentence)" "It is met once both hold, or stop after ${CFG_goal} more turns." > "$3"
  send_goal "$1" "$3" findings "$2"
}

# The merge and review rules, shared by the briefs.
merge_rule() {
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge}" == human ]]; then echo "Never merge, by any route (a human merges)."
  else echo "Never merge, by any route (the conductor or the lead merges, with swarm.sh merge)."; fi
}
# stop_rule <epic> — when a conductor stops. With merge = agent it merges its own PRs, so it also
# waits out every running build. The backlog conductor has no Done when: it stops once its stories
# are all started and finished.
stop_rule() {
  if [[ "$1" == backlog ]]; then
    printf '%s' "Stop when no ready story with no \`epic:\` that you may start is left and none is running"
    if [[ "${CFG_merge}" == human ]]; then echo "."; else echo ", or when CI on the base is red or timed out."; fi
  elif [[ "${CFG_merge}" == human ]]; then echo "Stop when the epic's **Done when** holds or when nothing ready is left."
  else echo "Stop when the epic's **Done when** holds, when no story of this epic that is yours to start is ready and none is running, or when CI on the base is red or timed out."; fi
}
# The review every story's PR passes before its builder is closed. The builder keeps its context
# until then, so findings go back to it rather than to a fresh agent that has none. Each PR gets its
# own review agent (review_agent) as soon as it is green, so PRs that land together are reviewed at
# once; the agent runs codex, so the conductor runs it only in codex's place when it was skipped.
review_rule() {
  local sw="${SWARM_HOME}/bin/swarm.sh"
  cat <<EOF
A story is reviewed only when its latest head has passed a review agent's review. As soon as a
story's PR is green, start one with \`${sw} review-agent <slug> <PR URL>\`.
Do not wait for other PRs or reviews: start one for each green PR, so PRs that land together are
reviewed at once. It returns at once. It refuses when the story's worktree is not at the PR's head,
or has uncommitted changes: wait for the builder, then start it again. The review agent, review-<slug>, is read-only and runs in
the story's worktree: it runs codex-review with the story's slug and, when the PR changes code (not
only docs, board files or a dependency bump), \`/code-review <PR>\`, judges only the story's touches
and **Done when**, and writes ${PROJECT_DIR}/.swarm/reviews/<slug>.md: a \`head: <SHA>\` line
naming the commit it reviewed, its findings, and an out-of-scope section. Wait on each with
\`swarm.sh wait review-<slug>\` in the background, triage that story's file, then close the review
agent (\`swarm.sh close review-<slug>\`) whatever it found. A file with a \`head moved:\` line, or
with no \`## Findings\` section, is not a pass: start the review again. When the wait returns with
no findings file (it timed out, or the agent waits on a prompt, is gone or needs a login), close the
review agent, never answering its prompt, and start the review again in a later round, or read the
diff yourself as for a skipped codex. Send the real findings to the story's
builder with \`${sw} tell <slug> findings <file>\` (a file holding the findings and what to
decline). Log each item of the out-of-scope section with
\`log-finding --declined out-of-scope --reviewer <who>\`, as below.
When a review agent reports \`codex skipped: <why>\` (its file's second line says so too), read the diff yourself in codex's place.
Wait for the builder, then start a new review agent on its new head. Stop at the first pass on the latest head
with nothing substantive: one that finds only nits, edge cases outside the story, or points already
declined is such a pass, even if it is not empty. Rebut what it found in the PR with a reason.
Before a story merges or goes to review, compare the file's \`head:\` line with the PR's head
(\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`): if they differ, the latest head has
not passed, so review the new head. Never merge a story, and never run \`swarm.sh close <slug>\` on its builder, before
its latest head has passed.$(rules_review_rule)

$(finding_rule)
EOF
}

# codex_review_cmd <base> [slug] — how a brief runs codex: through codex-review, which stops it after
# codex_minutes. SWARM_PROJECT, as in finding_rule, so a sibling repo's worktree reads this config;
# SWARM_STORY, given a slug, so codex reviews against that story.
codex_review_cmd() {
  [[ -z "${2:-}" ]] || printf 'SWARM_STORY=%q ' "$2"
  printf 'SWARM_PROJECT=%q %q codex-review %s' "${PROJECT_DIR}" "${SWARM_HOME}/bin/swarm.sh" "$1"
}
# codex_rule — how to run codex-review, and what a usage limit or a timeout means, for a builder, a
# conductor and the lead alike. In the background, because a foreground Bash call ends sooner (Claude
# Code stops one at 2 minutes by default, 10 at most) and the tool's kill would preempt the timeout.
codex_rule() {
  # shellcheck disable=SC2154 # assigned in another file
  printf '%s ' "Run codex-review in the background (Bash run_in_background) and wait for it to finish: it can run for ${CFG_codex_minutes} minutes, longer than a foreground Bash call may last."
  printf '%s' 'If codex reports a usage limit, or codex-review stops it and prints "codex skipped: timed out", do not wait or run it again: a builder carries on without it, a conductor or the lead reviews the diff itself, and the PR (or a reply, where there is none) says "codex skipped: usage limit" or "codex skipped: timed out".'
}
# finding_rule — every fixed finding feeds the outer loop (swarm.sh lessons); declined ones are
# logged too, with their reason, and never count as lessons.
finding_rule() {
  local proj sw
  proj="$(printf '%q' "${PROJECT_DIR}")"; sw="$(printf '%q' "${SWARM_HOME}/bin/swarm.sh")"
  cat <<EOF
Log each finding that was fixed, and each one declined (rebutted with a reason), from any directory, with:

    SWARM_PROJECT=${proj} ${sw} log-finding --reviewer <who> <kind> <PR URL> "<one line>"
    SWARM_PROJECT=${proj} ${sw} log-finding --declined <reason> --reviewer <who> <kind> <PR URL> "<the finding, and why it was declined>"

<reason> is out-of-scope when the finding is outside the story's touches and **Done when**, nit when
it is real but not worth the change, and wrong when it is mistaken.
<who> is the reviewer that first raised it, whoever passed it on: codex for a finding from
\`swarm.sh codex-review\`, code-review for /code-review's, ci for the PR review bot's or a
\`swarm.sh findings\` note's, conductor for one from your own reading of the diff, and lead only for
one from the lead's own reading.
When a fix finds a defect in work that already merged, log it as \`--reviewer escaped\` against the
PR that merged it, not the PR that fixes it.
The kind is a short kebab-case name for the class of mistake, not this instance (vacuous-test,
denylist, docs-misstate-code, fails-open); reuse one that
\`SWARM_PROJECT=${proj} ${sw} lessons --all\` already lists when it fits.
EOF
}
# conduct_merge_rule [backlog] — how a conductor hands over or merges a reviewed PR: an epic's, or
# with backlog the backlog conductor's, whose stories have no epic to review or finish.
conduct_merge_rule() {
  local scope="of this epic" epic_end="" backlog=""
  [[ "${1:-}" != backlog ]] || { backlog=1; scope="with no epic"; }
  if [[ "${CFG_merge}" == human ]]; then
    [[ -n "${backlog}" ]] || epic_end=" When every story left
in the epic is in review and the epic's **Done when** will hold once they merge, run
\`swarm.sh review <epic> <every PR URL still waiting>\`: the epic leaves the board once they all merge."
    cat <<EOF
Never merge a PR, by any route: not \`gh pr merge\`, not \`gh api\`, not the web page. A human merges.
When a story's PR is green and reviewed, run \`swarm.sh review <slug> <PR URL>\` and
\`swarm.sh close <slug>\`. Then run \`swarm.sh unblock\`, and start each story ${scope} it prints as
\`ready:\` whose \`touches\` do not overlap a running one, with \`swarm.sh story --strict <slug>\`.
$(stacked_start_rule) When \`swarm.sh review\` holds a stacked story instead (\`held: <slug> waits for <p>
to merge\`), the story is blocked again with its build kept: close its builder with a bare
\`swarm.sh close <slug>\`, which counts nothing for a blocked story and keeps its build, and go on.
$(held_ready_rule)${epic_end}
EOF
  else
    [[ -n "${backlog}" ]] || epic_end=" When the
epic's **Done when** holds, take the epic off the board with \`swarm.sh finish <epic>\`, but never
while a story of it is still in review (a \`costs: money\` one waits for the user's merge): once the
Done when will hold when they merge, run \`swarm.sh review <epic> <every PR URL still waiting>\`
instead, and the epic leaves the board once they all merge."
    cat <<EOF
A story whose front matter says \`costs: money\` (merging it can spend money) is the user's to merge,
as with merge = human. When its PR is green and reviewed,
run \`swarm.sh review <slug> <PR URL>\` and \`swarm.sh close <slug>\`, never \`swarm.sh merge\`, which
refuses it (\`held: <slug> costs money\`). Leave the PR for the user, and list it in your report
under Waits on the user. When \`swarm.sh merge\` refuses any other PR with \`held: ... the user merges
it\` (a parent it stacks on costs money, or another \`costs:\` value), do the same: close its builder,
leave the PR for the user and list it.

$(pin_rule) $(pinned_merge_rule '<slug> <PR URL>') Reconcile has closed the builder, so leave it, unless it
printed \`build cleared: <slug>\`: then run \`swarm.sh close <slug>\` as it says.

Then run \`swarm.sh unblock\`, and in this run start each story ${scope} it prints as \`ready:\`
whose \`touches\` do not overlap a running one, with \`swarm.sh story --strict <slug>\`.
$(stacked_start_rule) When \`swarm.sh review\` holds a stacked story instead (\`held: <slug> waits for <p>
to merge\`), the story is blocked again and nothing merges: leave its builder open, unless that line
says \`(costs money)\`. The user merges that parent, maybe days later, so close its builder with a
bare \`swarm.sh close <slug>\`, which counts nothing for a blocked story and keeps its build, as with
merge = human.
$(held_ready_rule) After a
cleared-on-error close or a give-up, start nothing more in this wave. Write your report only when no
story ${scope} that is yours to start is ready and none is running, or CI on the base is red or
timed out.${epic_end}
EOF
  fi
}

# costs_wait_rule — with merge = agent, a story --strict refusal that ends (costs money) (touches_overlap):
# only the user merges the named story, so the conductor reports instead of waiting.
costs_wait_rule() {
  [[ "${CFG_merge}" == agent ]] || return 0
  printf '%s' " If the refusal ends \`(costs money)\`, only the user merges the named story, maybe days later: do not wait for it, and report yours as \`not started: <slug> (waits on <other>'s merge)\`."
}

# held_ready_rule — what to do when unblock readies a child review held, for both merge modes: its
# build is kept, so story would refuse it.
held_ready_rule() {
  cat <<EOF
When \`swarm.sh unblock\` prints \`ready: <slug> (held: merge origin/<base>, review again)\`, the
story's parents have merged and its build is kept: never run \`swarm.sh story\` for it. Its merge
of the base is the Stacked line \`<slug>: merge origin/<base> (<parents> merged)\` that
\`swarm.sh status\` prints for it: the same instruction, so act on that line alone, as the Stacked
rule above says, and start at most one builder for it. A \`<slug>: could not check ...\` line in its
place means nothing is known: read status again after your next wait. Only with no Stacked line for
it at all does its branch have the base already. Then review its new head as any other story's PR.
EOF
}

# stacked_start_rule — what unblock's (stacked on <parents>) means, for both merge modes.
stacked_start_rule() {
  printf '%s' "A story printed \`(stacked on <parents>)\` starts on its parents' branches while their PRs are still open, and its PR says \`Merge after\` theirs. A \`not stacked: <slug>\` line names a story whose old build is in the way: list it in your report for the lead."
}

# pin_rule — with merge = agent and a PR per story, the head a review passed is its findings file's
# head: line (review_agent pins it), checked against the PR's head before the merge.
pin_rule() {
  cat <<EOF
The head a review passed is the \`head:\` line of the story's findings file
(${PROJECT_DIR}/.swarm/reviews/<slug>.md). Once the review passes, read the PR's head
(\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`); if it is not that SHA, the head
moved: review the new head.
EOF
}

# pinned_merge_rule <review args> — with merge = agent, how a conductor merges a reviewed PR: put the
# item in review, then swarm.sh merge pinned to the head it reviewed, one at a time, which reconciles.
pinned_merge_rule() {
  cat <<EOF
Merge a PR only when it is green and reviewed, and only through \`swarm.sh merge\`: run
\`swarm.sh review $1\`, then \`swarm.sh merge --head <the SHA on the findings file's head: line> <PR URL>\`, never
\`gh pr merge\` or \`gh api\`. It merges by the literal PR number with \`--match-head-commit <sha>\` and the
repo's merge method, squash when allowed
(\`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed\`), never --auto,
and only once every check on that head has completed and passed, which it checks itself. Run one
\`swarm.sh merge\` at a time: start the next only after the previous one has exited, its base CI and
reconcile done. Run it in the background (Bash \`run_in_background\`)
and wait for it: it waits up to $((MERGE_CI_SECONDS / 60)) minutes for CI on the merge commit on the
base, then runs \`swarm.sh reconcile\`, never a plain \`git pull\`, which pulls the board and finishes the item. If
it exits non-zero, read why: a refusal before \`gh pr merge\` ran merged nothing; \`unconfirmed\`
means \`gh pr merge\` ran but the PR never read as merged (a merge queue may hold it), so check it by
hand. A red or timed-out CI on the base means the PR merged and the base is broken: merge nothing
more, find the PR pair that broke it (this PR and one merged before it, each green alone), open the
fix or list it for the lead, and say so in your report.
EOF
}

# A test that passes with its fix removed proves nothing; a builder shows each one can fail, and
# findings names each new test whose FAIL line the PR body lacks.
mutation_rule() {
  printf '%s' "For a code change, prove each new or changed test can fail: back up the file you fixed with cp, break the fix, see the test fail, then restore it with cp (never git checkout, which drops uncommitted work), and paste each test's FAIL line (the line the run printed, with FAIL and the test's name) into the PR body."
}

# reply_sentence — what a builder replies, and when: the brief's rule on finishing, and what its goal
# condition waits for. One sentence, so the two cannot drift.
reply_sentence() {
  printf '%s' "When CI is green, reply with the PR URL, what changed in three lines, and the codex findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR."
}

# story_path <slug> <src> — the story file as its builder names it: relative to the worktree when the
# board is in the repo it builds (the copy it reads, and its PR deletes), else the board's own.
story_path() {
  if [[ ${BOARD_IN_REPO} == 1 && "$2" == "${PROJECT_DIR}" ]]; then echo "${BOARD#"${PROJECT_DIR}/"}/stories/$1.md"
  else echo "${BOARD}/stories/$1.md"; fi
}

# goal_condition <slug> <src> — the builder's /goal, on one line: the story's **Done when**
# and **From review** items named by the path its brief gives (story_path; inlined, a long Done when
# made the /goal arrive as pasted text), the reply its brief asks for, an escape for a
# story that cannot be done, and the goal's turn bound. Fails, printing why, with no Done when or no
# item under it: a blank line under the heading is skipped, and a bold line before any item ends it.
goal_condition() {
  local f="${BOARD}/stories/$1.md"
  awk '/^\*\*Done when/ { on = 1; rest = $0; sub(/^\*\*[^*]*\*\*[[:space:]]*/, "", rest); if (rest != "") { found = 1; exit }; next }
    on && /^\*\*/ { on = 0; next }
    on && /[^[:space:]]/ { found = 1; exit }
    END { exit !found }' "${f}" \
    || { echo "$1 has no **Done when** with an item under it, so its goal would have nothing to meet"; return 1; }
  printf '%s %s %s\n' "Every item under **Done when:** and **From review**, if any, in $(story_path "$1" "$2") (your brief's story, already in this session) holds and is shown in this session." \
    "$(reply_sentence)" \
    "If the story cannot be done, reply \`IMPOSSIBLE: <why>\` and stop; that reply meets this goal. The goal is met once all of the above holds and you have replied, or stop after ${CFG_goal} more turns."
}
# goal_message <condition> — the line send_goal types: /goal and the condition, whitespace squeezed.
goal_message() { local c; c="$(tr -s '[:space:]' ' ' <<< "$1")"; c="${c# }"; printf '/goal %s' "${c% }"; }
# GOAL_SEND_MAX: the longest /goal message story sends. Claude Code collapses a longer paste into a
# "[Pasted text]" block and queues it as a prompt, so the /goal never runs.
GOAL_SEND_MAX=700   # Claude Code 2.1.301, measured in a herdr pane: 800 ran, 801 pasted

# goal_entry <name> <since-epoch> [<goal-file>] — the kind of the newest goal entry written at or
# after <since> in <name>'s session log (its agents.tsv session id, report.py's session_log under
# CLAUDE_PROJECTS), or nothing. Never the pane. The kinds, as the goal spike (Claude Code 2.1.299)
# found them: set (goal_status with sentinel:true), continuing (the judge's met:false), met (the
# judge's met:true, which is also how a turn bound and an IMPOSSIBLE escape are written), and
# `refused: <Claude Code's reason>` (a system/local_command whose stdout is a /goal refusal, as with
# hooks restricted or an untrusted folder; no goal_status follows). The spike saw no entry for a
# stalled, paused or errored goal, so none is read. With <goal-file>, a goal_status for another
# condition (whitespace aside) is skipped, and with no goal entry, `pasted` when a queued_command
# attachment's prompt, its <pasted_content> tags aside, starts with that /goal: Claude Code collapsed
# the paste and queued it as a prompt, as it did on 2026-10-16.
goal_entry() {
  python3 "${SWARM_HOME}/bin/lib/goal_entry.py" "${AGENTS_LOG}" "$1" "${CLAUDE_PROJECTS}" "$2" "${3:-}"
}

# send_goal <slug> <goal-file> <brief|findings> [<since-epoch>] — send <slug>'s builder `/goal <condition>` once (deliver_prompt's
# once mode) and confirm it set from its session log (goal_entry, for this condition), polling up to
# PROMPT_TIMEOUT_MS. The condition goes on one line: the spike only saw a one-line /goal set, and a
# multi-line paste could be split or become a "[Pasted text]" placeholder; goal_entry compares it
# whitespace aside. Any goal_status newer than the send means it set: the judge may already have
# written its own after the sentinel. A refusal, or no entry, fails naming the story and why (a /goal
# Claude Code queued as pasted text, when goal_entry finds one), and leaves the builder open for the
# lead to read. <since> defaults to now. The /goal goes only into a
# turn that has started: herdr can say working while the session is still idle, and deliver_prompt
# takes blocked as taken up, so it waits up to PROMPT_TIMEOUT_MS for the session (session_state) to
# read busy, and fails with nothing sent if it reads waiting (a dialog, where Enter could approve
# what auto mode flagged) or never reads busy. Each failure says the brief or the findings were
# delivered, so they are not sent again.
send_goal() {
  local slug="$1" goal="$2" name since="${4:-$(date +%s)}" entry deadline state pre post
  name="$(agent_name "${slug}")"
  pre="${slug}: the brief was delivered, but"; post="; do not send it again"
  [[ "$3" != findings ]] || { pre="${slug}: the findings were delivered, but"; post="; do not send them again"; }
  deadline=$((SECONDS + PROMPT_TIMEOUT_MS / 1000))
  while state="$(session_state "${name}")"; [[ "${state}" != busy && "${state}" != waiting* && ${SECONDS} -lt ${deadline} ]]; do sleep 1; done
  case "${state}" in
    busy) ;;
    waiting*) die "${pre} its builder is waiting on $(waiting_for "${state}"), so no /goal was sent; answer it (herdr agent read ${name})${post}" ;;
    *) die "${pre} its session did not read busy within $((PROMPT_TIMEOUT_MS / 1000))s (${state}), so no /goal was sent${post}" ;;
  esac
  deliver_prompt "${name}" <(goal_message "$(cat "${goal}")") "" once   # read once, so a pipe will do
  deadline=$((SECONDS + PROMPT_TIMEOUT_MS / 1000))
  # A queued paste waits out the deadline: a goal_status may still follow it.
  while entry="$(goal_entry "${name}" "${since}" "${goal}")"; [[ ( -z "${entry}" || "${entry}" == pasted ) && ${SECONDS} -lt ${deadline} ]]; do sleep 1; done
  case "${entry}" in
    pasted) die "${pre} its /goal was pasted as text, not run: its session log shows it queued as a prompt and no goal set; its builder is still open${post}" ;;
    refused:*) die "${pre} Claude Code refused its /goal (${entry#refused: }); its builder is still open${post}" ;;
    "") die "${pre} its session log shows no goal set for its condition $((PROMPT_TIMEOUT_MS / 1000))s after the /goal; its builder is still open${post}" ;;
  esac
}

# The brief every story builder gets. The story file is the task; these are the rules.
story_brief() {
  local slug="$1" src="$2" base="$3" story_ref cleanup rel epic check rules
  story_ref="$(story_path "${slug}" "${src}")"
  if [[ "${src}" == "${PROJECT_DIR}" && ${BOARD_IN_REPO} == 1 ]]; then
    # The board is in this repo: the PR takes the story off it.
    rel="${BOARD#"${PROJECT_DIR}/"}/stories"
    cleanup="Delete ${rel}/${slug}.md in your PR, and nothing else under ${rel}/."
  else
    # The board is elsewhere: read the story there, and leave it for the lead.
    story_ref="${story_ref} (this worktree is $(basename "${src}"))"
    cleanup="Do not touch the story file; the lead takes it off the board after your PR merges."
  fi
  cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit and PR with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} $(merge_rule) Never touch real cloud or
credentials. Open the PR against \`${base}\`. Run \`$(codex_review_cmd "${base}" "${slug}")\` before
committing; fix real findings, decline nits with a reason, converge on one clean pass, and record the
loop in the PR body. $(codex_rule) If \`gh pr view --json mergeable\` says
CONFLICTING, merge origin/${base} into your branch, resolve it (keep both sides of any list), re-run
the tests and push: a conflicted PR runs no checks and waits forever. $(mutation_rule) Record it
in the PR body. $(reply_sentence)
EOF
  epic="$(fm "${BOARD}/stories/${slug}.md" epic)"
  check=""; [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || printf '%s\n' "Before you open the PR, also run the epic's check from the worktree root, and make it pass: \`${check}\`"
  rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\n%s\n' "${rules}"
  rules_check_step "open the PR" "${rules}"
}

# rule_kinds — the kinds of the tagged rules (<!-- lesson: <kind> -->) on stdin, one per line.
rule_kinds() {
  grep -oE -- '<!--[[:space:]]*lesson:[[:space:]]*[a-z0-9-]+[[:space:]]*-->' | sed -E 's/.*lesson:[[:space:]]*([a-z0-9-]+).*/\1/' | sort -u || true
}

# rules_check_step <before> <rules> — a rule pasted into the brief does not stop the mistake, so a
# builder walks its diff against each tagged rule and says what it checked. Nothing without one.
rules_check_step() {
  local kinds where="the PR body"; kinds="$(rule_kinds <<< "$2")"
  [[ -n "${kinds}" ]] || return 0
  [[ "$1" == "open the PR" ]] || where="your reply"
  cat <<EOF

Before you $1, walk your diff against each rule tagged \`<!-- lesson: <kind> -->\` above. Then give
${where} a \`Rules checked:\` section with one line per kind: what in the diff you checked (file:line),
or \`n/a: <why>\`:

Rules checked:
EOF
  sed 's/^/- /; s/$/: <file:line>, or n\/a: <why>/' <<< "${kinds}"
}

# rules_review_rule — the conductor's half of rules_check_step, while the project has tagged rules.
rules_review_rule() {
  [[ -n "$(project_rules | rule_kinds)" ]] || return 0
  printf '\n\n%s' "A builder's PR body (its reply, when it opens no PR) must carry a \`Rules checked:\` section with a line per tagged rule's kind, each naming what it checked (file:line) or \`n/a: <why>\`. A missing section, a missing kind, or a line that names nothing is a finding of kind \`rules-unchecked\`: send it back like any other."
}

# project_rules — the brief, then, when lessons_file is another file, only its tagged rule lines: a
# builder in another repo's worktree never reads this project's AGENTS.md.
project_rules() {
  [[ ! -f "${PROJECT_BRIEF}" ]] || { cat "${PROJECT_BRIEF}"; echo; }   # a brief may lack its final newline
  [[ "${LESSONS_FILE}" == "${PROJECT_BRIEF}" ]] || grep -hE -- '<!--[[:space:]]*lesson:[[:space:]]*[a-z0-9-]+[[:space:]]*-->' "${LESSONS_FILE}" 2>/dev/null || true
}

# agent_kind — true for a kind a swarm agent may build; an empty kind means code. Anything else,
# lead or a typo, stays with the lead, so an unknown kind can never reach an agent.
agent_kind() {
  case "$1" in ""|code|docs|chore) return 0 ;; *) return 1 ;; esac
}

# story_role <slug> — the role a story is built as: escalate for a kind an agent builds once its
# attempts: reaches escalate_after (> 0), else its kind, code-risky for code with risk: high, and with
# sonnet_share = N, code-sonnet for the other code stories whose slug's cksum mod N is 0, so a slug
# always lands in the same arm. Only a first attempt is sampled: a slug with an agents.tsv line
# already goes back to code. A missing story or a bad attempts: prints the reason and returns 1.
story_role() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind risk attempts sum
  [[ -f "${story}" ]] || { echo "no story ${story}"; return 1; }
  kind="$(fm "${story}" kind)"; kind="${kind:-code}"; risk="$(fm "${story}" risk)"
  attempts="$(get_fm "${story}" attempts)"; attempts="${attempts:-0}"
  # Checked before any arithmetic, which would evaluate it.
  [[ "${attempts}" =~ ^(0|[1-9][0-9]*)$ ]] \
    || { echo "${story}: attempts must be a non-negative whole number, not '${attempts}'"; return 1; }
  # shellcheck disable=SC2154 # assigned in another file
  if agent_kind "${kind}" && (( CFG_escalate_after > 0 && attempts >= CFG_escalate_after )); then echo escalate; return; fi
  if [[ "${kind}" != code ]]; then echo "${kind}"; return; fi
  if [[ "${risk}" == high ]]; then echo code-risky; return; fi
  sum="$(printf '%s' "${slug}" | cksum)"; sum="${sum%% *}"
  # shellcheck disable=SC2154 # assigned in another file
  if [[ ${CFG_sonnet_share} -gt 0 && $((sum % CFG_sonnet_share)) -eq 0 ]] \
     && ! awk -F'\t' -v n="$(agent_name "${slug}")" '$3 == n { f = 1 } END { exit !f }' "${AGENTS_LOG}" 2>/dev/null; then
    echo code-sonnet
  else
    echo code
  fi
}

build_story() {
  local slug="$1" strict="${2:-}" story="${BOARD}/stories/$1.md" kind repo src role wt branch prompt base epic goal="" msg parents
  [[ -f "${story}" ]] || die "no story ${story}"
  [[ "$(fm "${story}" status)" == ready ]] || die "${slug} is not status: ready"
  kind="$(fm "${story}" kind)"; kind="${kind:-code}"
  case "${kind}" in
    code|docs|chore) ;;
    lead) die "${slug} is kind: lead — real cloud, credentials or a human step; the lead runs it, not a swarm agent" ;;
    operator) die "${slug} is kind: operator, which is now kind: lead: change it, and mark the user's step **You:**" ;;
    *) die "${slug} has kind: ${kind}; an agent builds only code, docs or chore" ;;
  esac
  touches_overlap "${slug}" "${strict}"   # before anything is made, so --strict leaves nothing behind
  repo=$(sed -n 's/^repo: *//p' "${story}" | head -1)   # a repo in repos_dir; empty is the project's own
  role="$(story_role "${slug}")" || die "${role}"
  policy "${role}" >/dev/null
  src="$(repo_dir "${repo}")" || die "${slug}: ${src}"
  # Before the worktree exists, so a refusal leaves nothing to clean up.
  require_trusted "${src}"
  if [[ "${CFG_goal}" == off ]]; then require_claude; else
    goal="$(goal_condition "${slug}" "${src}")" || die "${goal}"
    msg="$(goal_message "${goal}")"
    (( ${#msg} <= GOAL_SEND_MAX )) \
      || die "${slug}: its /goal message is ${#msg} characters, over GOAL_SEND_MAX (${GOAL_SEND_MAX}), past which Claude Code pastes it as text and never runs it; shorten its board path or slug"
    require_claude "${GOAL_MIN_CLAUDE}"
  fi
  base="$(base_for "${src}")"
  branch="story/${slug}"; wt="$(worktree_for "${src}" "${slug}")"
  if build_exists "${src}" "${slug}"; then
    [[ -z "$(get_fm "${story}" held_by)" ]] \
      || die "${slug} was held until its parents merged, and its build is kept in ${wt}: never start it again. Act on the Stacked line swarm.sh status prints for ${slug}, then review it again and run swarm.sh review ${slug} <PR URL>"
    die "${slug} has a build already (${branch} or ${wt} exists in ${src}): it has started, so wait on its builder, and to build it again from scratch remove that worktree and branch first"
  fi
  parents="$(open_parents "${story}")"
  if [[ -n "${parents}" ]]; then stack_start "${story}" "${src}" "${wt}" "${parents}"
  else git -C "${src}" worktree add -q -b "${branch}" "${wt}" "origin/${base}"; fi
  prompt="${PROJECT_DIR}/.swarm/briefs/${slug}.md"; mkdir -p "$(dirname "${prompt}")"
  rm -f "${prompt%.md}.goal.md"   # an earlier build's, which a goal-off retry must not keep
  story_brief "${slug}" "${src}" "${base}" > "${prompt}"
  [[ -z "${parents}" ]] || printf '%s\n' "This story is stacked: your branch starts on the branches of ${parents}, whose PRs are still open. Open your PR against \`${base}\` all the same, with \`Merge after ${STACK_PRS}\` in its body." >> "${prompt}"
  [[ -z "${goal}" ]] || printf '%s\n' "${goal}" > "${prompt%.md}.goal.md"
  # An epic's story gets a pane in the epic's tab; a one-off gets a tab of its own.
  epic="$(fm "${story}" epic)"
  start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}"
  # story_role has checked attempts: is a whole number. The build is attempt attempts + 1.
  [[ "${role}" != escalate ]] || record_event escalate "${slug}" "ok (attempt $(( $(get_fm "${story}" attempts) + 1 )))"
  # Once the brief is taken up, mid-turn: the goal sets at once and costs one extra short turn.
  [[ -z "${goal}" ]] || send_goal "${slug}" "${prompt%.md}.goal.md" brief
}

# review_agent <slug> <PR URL> — start review-<slug> on a story's PR in the story's worktree and tab,
# with role review and review_brief, and return at once: the conductor waits on it with `swarm.sh
# wait review-<slug>`, which returns once the agent has written its findings file. It reviews the
# PR's head, and only when the worktree is at it with nothing uncommitted; the file's head: line
# names that commit. Refused, starting nothing and touching no file, when
# the board has a story named review-<slug> (its builder would hold the same agent name), or when
# review-<slug> cannot start (still working). Its earlier findings file goes once the agent has
# started (kept aside until then), so the conductor reads only this head's.
review_agent() {
  local slug="$1" pr="$2" story="${BOARD}/stories/$1.md" src wt base prompt out epic head at
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "review-agent: bad slug '${slug}' (swarm.sh review-agent <slug> <PR URL>)"
  [[ "${pr}" =~ ^https://[^[:space:]]+/pull/[0-9]+$ ]] || die "review-agent: '${pr}' is not a PR URL (swarm.sh review-agent <slug> <PR URL>)"
  [[ -f "${story}" ]] || die "no story ${story}"
  [[ ! -f "${BOARD}/stories/review-${slug}.md" ]] \
    || die "review-agent: the board has a story named review-${slug}, whose builder's agent name would be the same; nothing was started"
  [[ -n "$(story_items "${story}" 'Done when')" ]] || die "${slug}: ${story} has no **Done when** with an item under it"
  src="$(repo_dir "$(fm "${story}" repo)")" || die "${slug}: ${src}"
  wt="$(worktree_for "${src}" "${slug}")"
  [[ -d "${wt}" ]] || die "${slug}: no worktree at ${wt}: review-agent reviews a story built here"
  head="$(gh pr view "${pr}" --json headRefOid --jq .headRefOid 2>/dev/null)" || head=""
  [[ "${head}" =~ ^[0-9a-f]{40}$ ]] || die "review-agent: could not read ${pr}'s head (gh pr view --json headRefOid)"
  at="$(git -C "${wt}" rev-parse HEAD)"
  [[ "${at}" == "${head}" ]] \
    || die "review-agent: ${slug}'s worktree is at ${at}, not the PR's head ${head}; nothing was started: wait for its builder, then start the review again"
  # Uncommitted work would be reviewed with the head (codex's story prompt includes it).
  [[ -z "$(git -C "${wt}" status --porcelain)" ]] \
    || die "review-agent: ${slug}'s worktree has uncommitted changes, so it is not the PR's head ${head}; nothing was started: wait for its builder to commit and push, then start the review again"
  out="${PROJECT_DIR}/.swarm/reviews/${slug}.md"
  # An open review-<slug> with no findings file is still reviewing (idle while its codex runs), and
  # free_agent_name would retire it as finished.
  [[ -f "${out}" || -z "$(agent_field "$(agent_name "review-${slug}")" pane_id)" ]] \
    || die "review-agent: review-${slug} is still reviewing (no ${out} yet); nothing was started: wait for it with swarm.sh wait review-${slug}, close it, then start the review again"
  # What start_agent would refuse on, before any file is touched.
  require_trusted "${wt}"; require_claude; free_agent_name "$(agent_name "review-${slug}")"
  base="$(base_for "${src}")"
  mkdir -p "${out%/*}"
  prompt="${PROJECT_DIR}/.swarm/briefs/review-${slug}.md"; mkdir -p "${prompt%/*}"
  review_brief "${slug}" "${pr}" "${base}" "${out}" "${head}" > "${prompt}"
  # The story's tab: its epic's, or a one-off's own.
  epic="$(fm "${story}" epic)"
  # The last review's file is moved aside before the brief goes (a quick agent's new file must not be
  # the one removed), put back when the start fails, and dropped once it has started.
  [[ ! -f "${out}" ]] || mv "${out}" "${out}.prev"
  if ! (start_agent "${epic:-${slug}}" "review-${slug}" "${wt}" review "${prompt}"); then
    [[ ! -f "${out}.prev" ]] || mv "${out}.prev" "${out}"
    die "review-agent: review-${slug} did not start; ${out} is as it was"
  fi
  rm -f "${out}.prev"
}

# review_stack_note <slug> <base> — for a story stacked on parents (stacked_parents), that their
# commits are in its diff against <base> but are not its own; nothing for any other story.
review_stack_note() {
  local parents b="" p
  parents="$(stacked_parents "$1")"; [[ -n "${parents}" ]] || return 0
  for p in ${parents//,/ }; do b+="${b:+, }origin/story/${p}"; done
  printf '\n%s\n' "This story is stacked on ${parents}: their branches (${b}) are in its diff against origin/$2, but their code is not this story's. Leave it out of everything you write: it is neither a finding nor out of scope."
}

# review_brief <slug> <PR URL> <base> <findings file> <head> — a review agent's brief: read-only, the
# story's touches and Done when, codex-review with the slug, /code-review when the PR changes code, the
# project's rules, and each finding written to the absolute <findings file> (the agent's cwd is the
# worktree) under its head: line, with work outside the story listed apart for the conductor to decline.
review_brief() {
  local story="${BOARD}/stories/$1.md" rules
  cat <<EOF
Review $2, the PR of story $1, at its head $5, in this worktree. You are read-only: never edit,
commit or push here, and never merge, by any route. The one file you write is ${4}.

The story touches: $(fm "${story}" touches)

Its **Done when:**
$(story_items "${story}" 'Done when')

Judge the PR against these touches and items alone: work outside them is not a finding.
$(review_stack_note "$1" "$3")
Run \`$(codex_review_cmd "$3" "$1")\` in the background (Bash run_in_background) and wait for it to
finish: it can run for ${CFG_codex_minutes} minutes, longer than a foreground Bash call may last. If
codex reports a usage limit, or codex-review prints "codex skipped: timed out", do not wait or run
it again: you report \`codex skipped: usage limit\` or \`codex skipped: timed out\`. When the PR
changes code (not only docs, board files or a dependency bump), state the touches and Done when
above, then run \`/code-review $2\`.

When both are done, check that \`git rev-parse HEAD\` still prints $5 and \`git status --porcelain\`
prints nothing. If not, the worktree moved under you: write ${4} with the Write tool holding two
lines, \`head: $5\` and \`head moved: <what changed>\`, then stop.

Otherwise, write ${4} with the Write tool, in one go (the conductor's wait ends once it exists).
Its first line is \`head: $5\`; when codex was skipped, its second is \`codex skipped: <why>\`.
Under a \`## Findings\` heading,
one line per finding: its reviewer (codex or code-review), file:line, and the finding; with none, say
so. Under a \`## Out of scope\` heading, the same for each point a reviewer raised outside the
story's touches and Done when, so the conductor can decline it; with none, say so. Then reply with
${4}, and with \`codex skipped: <why>\` when codex was.
EOF
  rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\n%s\n' "${rules}"
}

# stack_start <story> <repo-dir> <worktree> <parents> — a stacked story's worktree, on story/<slug> at
# origin/story/<first parent>, with each other parent's branch merged in. Each parent's branch is
# fetched first and its PR must still be open; when one is not, the story goes back to blocked (in
# BOARD_STATE_DIR, as unblock's) and nothing is made. A merge that fails leaves no worktree or
# branch, and names the two branches that conflict and their files (merge_clash). Sets STACK_PRS to the
# parents' PR URLs, for the brief.
stack_start() {
  local story="$1" src="$2" wt="$3" slug p pr first="${4%% *}" why merged
  slug="$(basename "${story}" .md)"; STACK_PRS=""
  for p in $4; do
    if ! git -C "${src}" fetch -q origin "+refs/heads/story/${p}:refs/remotes/origin/story/${p}" 2>/dev/null \
       || ! pr="$(open_pr "${src}" "${p}")"; then
      set_status "${story}" blocked
      die "${slug}: ${p} has no open PR on story/${p} (or git or gh cannot reach it), so ${slug} is blocked again and nothing was made"
    fi
    STACK_PRS+="${STACK_PRS:+ }${pr}"
  done
  # No upstream: a plain push must never reach the parent's branch.
  git -C "${src}" worktree add -q --no-track -b "story/${slug}" "${wt}" "origin/story/${first}"
  merged="origin/story/${first}"
  for p in ${4#"${first}"}; do
    if why="$(git -C "${wt}" merge -q --no-edit "origin/story/${p}" 2>&1)"; then merged+=" origin/story/${p}"; continue; fi
    why="$(merge_clash "${wt}" "origin/story/${p}" "${merged}" "${why##*$'\n'}")"
    git -C "${src}" worktree remove --force "${wt}"; git -C "${src}" branch -q -D "story/${slug}"
    die "${slug}: ${why}; no worktree or branch was made"
  done
  record_event stacked "${slug}" "ok (on $4)"
}

# merge_clash <worktree> <ref> <merged refs> <git's last line> — why merging <ref> failed in
# <worktree>: the first of <merged refs> that changes a file the merge left unmerged, and those files;
# with none unmerged, what it was merged into and git's line.
merge_clash() {
  local r files other=""
  files="$(git -C "$1" diff --name-only --diff-filter=U)"
  [[ -n "${files}" ]] || { echo "cannot merge $2 into ${3// / + } (${4})"; return; }
  for r in $3; do
    # A here-string, not a pipe: grep -q can exit first, and pipefail would read that as no match.
    if grep -qFx -f <(printf '%s\n' "${files}") <<< "$(git -C "$1" diff --name-only "$(git -C "$1" merge-base "${r}" "$2")" "${r}")"; then
      other="${r}"; break
    fi
  done
  echo "$2 and ${other:-${3%% *}} conflict in ${files//$'\n'/, }"
}

# touches_overlap <slug> [strict] — warn on stderr for each story of another epic (no epic counts as
# another) that is open, in review, held (held_by:, its PR open) or with its builder open, and whose
# touches overlap <slug>'s; with
# strict, die naming it. builder_state runs only for overlapping ready stories (touches_rows finds
# them; no other status can have a builder). When it is unknown, or touches_rows fails, strict
# refuses and plain mode warns that it cannot tell.
touches_overlap() {
  local slug="$1" strict="${2:-}" rows other epic status entry state msg
  if ! rows="$(touches_rows "${slug}")"; then
    msg="cannot read the board's touches, so cannot tell whether another epic's open story overlaps ${slug}; retry ${slug} once they can be read"
    [[ -z "${strict}" ]] || die "${slug}: ${msg}"
    echo "warning: ${msg}" >&2; return 0
  fi
  while IFS=$'\t' read -r other epic status entry; do
    case "${status}" in
      review|held) state=open ;;
      ready) state="$(builder_state "${other}" </dev/null)" ;;
      *) continue ;;
    esac
    case "${state}" in
      open) msg="${other} (epic ${epic}) is open and touches ${entry}; start ${slug} after it merges"
            # Its merge waits on the user (money_walk), maybe for days.
            [[ -z "$(money_walk "${other}")" ]] || msg+=" (costs money)" ;;
      unknown) msg="cannot tell whether the builder of ${other} (epic ${epic}), which touches ${entry}, is open (herdr cannot list its agents); retry ${slug}" ;;
      *) continue ;;
    esac
    [[ -z "${strict}" ]] || die "${slug}: ${msg}"
    echo "warning: ${msg}" >&2
  done <<< "${rows}"
}

# touches_rows <slug> — a line per story of another epic whose touches overlap <slug>'s: slug, epic
# (none for no epic), status (held for a story with held_by:; both read from its state file first)
# and its overlapping entries. <slug>'s
# depends_on parents, and the stories that name <slug> in theirs, are left out: a stacked story starts
# on its parents' branches. Touches are a bracketed list split on commas
# outside parentheses, parentheticals dropped. An entry is [<repo>: ]<file>[:<fn>]. One with no / or .
# before its : is a fn of the previous entry's file and repo, unless that head is a file in its own
# repo's checkout (Makefile, Makefile:lint). (repo, file, fn) are compared: fn exactly, and a file-only entry
# overlaps the whole file. An empty status prints as -. Its own function, not inside a <(...):
# bash 3.2 misreads the parentheses in a heredoc there.
touches_rows() {
  python3 "${SWARM_HOME}/bin/lib/touches_rows.py" "${BOARD}/stories" "$1" "${PROJECT_DIR}" "${REPOS_DIR}" "${BOARD_STATE_DIR}/stories"
}

# The brief a conductor gets: one epic, from a fresh session, so its context holds only that epic.
# The epic backlog is the backlog conductor's: the ready stories with no epic.
conduct_brief() {
  local epic="$1" inbox scope="Stay inside this epic: start no story outside it, and leave the HLD and other epics alone."
  inbox="$(conductor_inbox "$(agent_name "conduct-$1")")"
  if [[ "${epic}" == backlog ]]; then
    scope="Start only stories with no \`epic:\`, and leave every epic and its stories alone."
    cat <<EOF
You are the backlog conductor: you build the ready stories on the board with no \`epic:\`. Read
AGENTS.md (and STATUS.md if there is one), ${SWARM_HOME}/docs/method.md and ${SWARM_HOME}/docs/reference.md § Building first.

EOF
    conduct_backlog_mode
  else
    cat <<EOF
You are the conductor for the epic ${BOARD}/epics/${epic}.md. Read AGENTS.md (and STATUS.md if there
is one), ${SWARM_HOME}/docs/method.md, ${SWARM_HOME}/docs/reference.md § Building and the epic first.

EOF
    conduct_story_mode "${epic}"
  fi
  cat <<EOF

${scope} A
story whose \`kind\` is set and is not code, docs or chore (a \`lead\` story: real cloud, credentials, a human step) is not yours to run; list it
for the user, unless it has \`escalated_from:\`: that one is the lead's, as above. $(stop_rule "${epic}")

Start every story, a retry too, with \`swarm.sh story --strict <slug>\`. It refuses when an open story
of another epic (in review, or with its builder open) touches the same function or file. On a refusal
that says the named story \`is open\`, start yours in a later wave, after the named story merges.$(costs_wait_rule) On
one that says it \`cannot tell\` (herdr could not list its agents, or the board's touches could not
be read), nothing is known to be open: retry the story in a later wave. Without --strict, story only
warns and starts it as the epic says.

The lead may leave you notes while you work, in ${inbox}.md. After each
\`swarm.sh wait\` or \`swarm.sh watch\` returns: if ${inbox}.reading.md is there (a read
cut off before its delete), read it, act on it and delete it first. Then, if the inbox exists, \`mv\`
it to ${inbox}.reading.md (atomic, so a note the lead adds meanwhile starts a new file),
read the moved copy, act on it, and delete it. Do all this once more just before you write your report,
so a note left after your last wait is not lost.
EOF
  local rules; rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\nThe project'"'"'s rules, which every builder also gets:\n\n%s\n' "${rules}"
  cat <<EOF

Your last act, after everything else: write your report (what merged, what is left, what waits on
the user) to ${PROJECT_DIR}/.swarm/conduct-${epic}.report.md, then reply with the same. The lead
treats that file as the only sign you have finished: being idle while you wait on your own
background work is not.
EOF
}

# The green rule every conductor follows, whatever it opens PRs for.
green_rule() {
  cat <<EOF
A PR is green only when every check on its head has passed and you have triaged the output of
\`${SWARM_HOME}/bin/swarm.sh findings <repo> <pr>\`: the notes on every check run, whatever its
conclusion, and open code-scanning alerts. Fix each real one; rebut the rest with a reason in the
PR (scanners often flag a name, not a value). Never change code only to silence a scanner, and
never dismiss an alert.
EOF
}

# auth_rule — what a conductor does when `wait` on a builder prints auth.
auth_rule() {
  cat <<EOF
A builder whose \`swarm.sh wait\` prints \`auth\` stopped on an expired login, which only the user's
/login clears: do not tell it, nudge it or wait on it again. Note it, and once you are told your
login is renewed, tell each such builder to resume (\`swarm.sh tell <slug> resume <file>\`) and wait on it
again with \`swarm.sh wait <slug>\` in the background.
EOF
}

# goal_rule — with goal on, how a conductor reads why a builder stopped short of its reply, and the
# close that cause takes. The causes are close_agent's; reading them is the goal spike's.
goal_rule() {
  cat <<EOF
Each builder works to a goal (goal = ${CFG_goal}). When \`swarm.sh wait\` returns idle for a builder
short of its reply, read why it stopped from its reply and its transcript, never its pane. The
transcript is \`${CLAUDE_PROJECTS}/*/<session>.jsonl\`, where <session> is field 7 of the last line in
.swarm/agents.tsv whose name (field 3) is the builder's agent name: its slug lowercased, each
character outside a-z, 0-9, _ and - made -, an s in front unless it starts with a letter, then cut
to 32 characters. That line is the current build. Read the reply first: \`IMPOSSIBLE:\` or the story's reply. Then read
the \`reason\` of the last \`goal_status\` entry with \`met:true\`. Act on the cause:
- met: the story's reply is there. Review it as below; the closes after review or merge stay bare.
- impossible: the reply starts \`IMPOSSIBLE:\`.
  Run \`swarm.sh close <slug> impossible\`, which makes the story \`kind: lead\`, and list it for the lead.
- stalled: \`wait --stall\` returned stalled.
  Run \`swarm.sh close <slug> stalled\` and start the story again in a later wave.
- bound: the reply is not there, and the met entry's reason says the stop-after clause applied.
  Run \`swarm.sh close <slug> bound\` and start the story again in a later wave.
- paused: the goal is still set, with no met entry since, and the builder is idle.
  Send it one \`swarm.sh tell <slug> resume <file>\` and wait on it again.
  If it stops paused again, run \`swarm.sh close <slug> paused\`. It counts nothing and holds the
  story for the lead (\`kind: lead\`, \`held_for: paused\`): list it for the lead, as for cleared-on-error.
- cleared-on-error: the transcript holds a \`/goal\` refusal (a \`system\` \`local_command\` entry whose
  stdout refuses \`/goal\`, with no \`goal_status\` after it), or the goal is gone and the transcript
  ends on an API error; or \`swarm.sh story\` failed on a refused goal.
  Run \`swarm.sh close <slug> cleared-on-error\`, start nothing more in this wave, and list it for
  the lead, who decides whether to build it again. The close holds the story for the lead
  (\`kind: lead\`, \`held_for: cleared-on-error\`), so no wave builds it until the lead lifts the hold.
  If either close prints no \`held:\` line (it prints \`not held:\` instead), the story stays \`ready\`
  with nothing on it to say so: do not start it again in a later wave. It waits for the lead.
- none of the above fits (no reply, no refusal, no stall, and no goal entry, or a met entry whose
  reason is not the stop-after clause): run \`swarm.sh close <slug> stalled\`, which counts the
  attempt so escalate_after bounds the retries, and start the story again in a later wave.
EOF
}

# give_up_rule — when a conductor stops waiting on a builder and builds the story again, and how it
# answers Fable's usage-credits consent, which is not giving up. With goal on, an idle builder is the
# goal rule's, and the stall close names its cause.
give_up_rule() {
  local retry idle="when it is idle with no PR after wait's nudges, " close="\`swarm.sh close <slug>\`" one="That is the one close before a review passes." goal=""
  if [[ "${CFG_goal}" != off ]]; then
    idle=""
    close="\`swarm.sh close <slug> stalled\` for a stall, or \`swarm.sh close <slug> met\` when review has not converged"
    one="Those and the goal rule's closes are the only ones before a review passes."
    goal="
A builder idle short of its reply is not one to give up on here: it is the goal rule's, which picks
its close and whether the story is started again."
  fi
  if (( CFG_escalate_after > 0 )); then
    retry="swarm.sh picks Fable for build $((CFG_escalate_after + 1)) (escalate_after = ${CFG_escalate_after})."
  else
    retry="escalation is off (escalate_after = 0), so once a story has failed twice
(\`attempts: 2\`), do not start it again: report it to the lead."
  fi
  cat <<EOF
Give up on a builder when \`swarm.sh wait --stall <slug>\` returns stalled, ${idle}or when review has
not converged in the rounds you allow. Run ${close}: on a code, docs or chore story still \`ready\` it
counts the attempt and clears its worktree, branch and PR. ${one} Start the story again in a later
wave with \`swarm.sh story --strict <slug>\`, and never choose a model: ${retry}${goal}
A story that comes back \`kind: lead\` with \`escalated_from:\` is the lead's to decide: report it
to the lead, and do not count it as waiting on the user.

A builder whose wait prints \`waiting: dialog open\` may be on Fable's usage-credits consent. Answer it
only when it is an escalate build (\`swarm.sh _role <slug>\` prints \`escalate\`) and its pane
(\`swarm.sh _target <slug>\` prints it) shows that consent in \`herdr agent read <pane>\`. Then accept it
with \`herdr pane send-keys <pane> <key>...\`, run \`swarm.sh dialog <slug> accepted\` (or \`dismissed\`
if it would not accept, and tell the lead), and wait on it again. Never close or tell it over a
dialog: a dialog is not an attempt. Any other dialog, and every permission or tool prompt, is not
yours to answer: never send keys to it; leave it for the lead.
EOF
}

# goal_rule_if_on — goal_rule after a blank line, or nothing with goal off.
goal_rule_if_on() { [[ "${CFG_goal}" == off ]] || printf '\n\n%s' "$(goal_rule)"; }

# stacked_rule <epic>|backlog — how a conductor keeps its own stacked builds on their parents:
# unblock after each wait, watch and new PR, then act on status's Stacked lines (stacked_lines),
# which cover the whole board, for its own stories only.
stacked_rule() {
  local mine="a story with \`epic: $1\`"
  [[ "$1" != backlog ]] || mine="a story with no \`epic:\`"
  cat <<EOF
After each \`swarm.sh wait\` or \`swarm.sh watch\` returns, and after a builder opens a PR, run
\`swarm.sh unblock\` and start what it readies that is yours (${mine}; a ready story whose
worktree exists has started: never run \`swarm.sh story\` for it), then run \`swarm.sh status\` and
read its Stacked lines. Both cover the whole board: act only on a line whose <child> is yours, and
leave the rest to their own conductor.
- \`<child>: merge <ref>\`: write a file saying to merge <ref> into its branch, re-run the tests and
  push, and send it with \`swarm.sh tell <child> findings <file>\`. On a line that ends \`(no builder)\`,
  first start a builder in the child's worktree (\`<repo>-wt/<child>\` beside its repo) with
  \`swarm.sh agent <tab> <child> <worktree> <role> <brief>\`, where <tab> is the child's \`epic:\` (its
  slug when it has none), <role> is what \`swarm.sh _role <child>\` prints, and the brief says the
  same and to reply with the PR URL. Any review of the child from before that merge is stale: review
  the new head. The line stays until the child pushes the merge, so send each merge once: until the
  child's builder replies to that tell (or brief), skip a line for the same child and ref.
- \`<child>: lost story/<p>\`: on a ready child whose builder is open, run \`swarm.sh close <child>
  paused\`, which holds it for the lead. If the line ends \`(no builder)\`, or close prints
  \`not held:\`, the child stays ready on a dead parent: do not start it, and list it in your report
  for the lead. A lost line on a held (blocked) child goes in your report too.
- \`<child>: could not check <what>\`: a gh or git call failed, so nothing is known: read status
  again after your next wait, and if the line stays, list it in your report.
EOF
}

# A PR per story.
conduct_story_mode() {
  local epic="$1"
  cat <<EOF
Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) to merge, as reference.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap,
start each with \`${SWARM_HOME}/bin/swarm.sh story --strict <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch --epic ${epic}\` in the background, and review each PR. Each story's base branch is in its brief,
.swarm/briefs/<slug>.md.

$(stacked_rule "${epic}")

$(auth_rule)$(goal_rule_if_on)

$(give_up_rule)

$(green_rule)

$(review_rule)

$(conduct_merge_rule)
EOF
}

# The backlog conductor: every ready story with no epic, a PR per story, reviewed as an epic's are.
# With merge = human its own one-off in review leaves review only once /swarm-dev:swarm reconciles, after this
# conductor reports, so a refusal naming one is reported, never waited on.
conduct_backlog_mode() {
  local own
  if [[ "${CFG_merge}" == human ]]; then own="

A \`swarm.sh story --strict\` refusal that names another story with no epic (\`(epic none) is open\`)
names one of yours in review, and it cannot merge while you run: do not wait for it. Report the
refused story as \`not started: <slug> (waits on <other>'s merge)\`."
  else own=""
  fi
  cat <<EOF
Drive every \`ready\` story with no \`epic:\` (${BOARD}/stories/*.md) to merge, as reference.md
§ Building describes: pick waves of them whose \`touches\` do not overlap, start each with
\`${SWARM_HOME}/bin/swarm.sh story --strict <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch --backlog\` in the background, and review each PR. Each story's base branch is in
its brief, .swarm/briefs/<slug>.md.

A ready story whose worktree exists (\`<repo>-wt/<slug>\` beside its repo) has already started: never
run \`swarm.sh story\` for it again. Wait on its builder with \`swarm.sh wait <slug>\` in the
background, then review its PR as below. If it has no builder and no PR, the build died: do not
start it, and report it as not started, with the reason \`build died\`. A held child unblock readied
(\`(held: ...)\`, with \`held_by:\` in its front matter) is the exception: follow the rule for
\`(held: ...)\` below instead.

List each ready story with no \`epic:\` that you could not start in your report, one line each:
\`not started: <slug> (<the refusal's first line>)\`.${own}

$(stacked_rule backlog)

$(auth_rule)$(goal_rule_if_on)

$(give_up_rule)

$(green_rule)

$(review_rule)

$(conduct_merge_rule backlog)
EOF
}

# hld_workspace <label> — the herdr workspace labelled <label>, created if there is none. Every epic
# of one HLD shares it; a new workspace's placeholder tab is closed once the caller has added its own.
hld_workspace() {
  local label="$1" ws
  ws=$(herdr workspace list | json "next((w['workspace_id'] for w in d['result']['workspaces'] if w.get('label')=='${label}'),'')")
  if [[ -z "${ws}" ]]; then
    ws=$(herdr workspace create --label "${label}" --cwd "${PROJECT_DIR}" --no-focus \
      | json "d['result']['workspace']['workspace_id']+' '+d['result']['tab']['tab_id']")
  fi
  echo "${ws}"
}

# conductor_report <agent> — where a conductor writes its report as its last act.
conductor_report() { echo "${PROJECT_DIR}/.swarm/conduct-$(conduct_epic "$1").report.md"; }
# conductor_inbox <name> — the conductor's inbox, without its .md: notes are <it>.md, a read in progress <it>.reading.md.
conductor_inbox() { echo "${PROJECT_DIR}/.swarm/inbox/$1"; }

# conduct_epic <agent> — the epic a conductor's agent name is for. The name may be cut at 32
# characters, so it is matched against the conductors started here (their briefs), which outlive
# the epic's own file. Two long epics can share a cut name; the newest brief is the one running.
conduct_epic() {
  local f e want
  want="$(agent_name "$1")"
  # shellcheck disable=SC2012 # newest first; brief names are epic slugs, [a-z0-9-]
  while IFS= read -r f; do
    e="$(basename "${f}" .md)"; e="${e#conduct-}"
    [[ "$(agent_name "conduct-${e}")" == "${want}" ]] && { echo "${e}"; return; }
  done < <(ls -t "${PROJECT_DIR}/.swarm/briefs"/conduct-*.md 2>/dev/null)
  echo "${want#conduct-}"
}

# start_conductor <epic>|--backlog — a conductor for one epic, or with --backlog for the ready
# stories with no epic: conduct-backlog, in a workspace named backlog, needing no epic file.
start_conductor() {
  local epic="$1" epic_file="${BOARD}/epics/$1.md" hld prompt ws placeholder inbox err
  if [[ "${epic}" == --backlog ]]; then
    epic=backlog; hld=backlog; epic_file="${BOARD}/epics/backlog.md"
    # conduct-backlog would be both conductors' name, brief and report.
    [[ ! -e "${epic_file}" ]] || die "conduct --backlog: ${epic_file} is an epic named backlog; rename it first"
  else
    [[ "${epic}" =~ ^[a-z0-9-]+$ ]] || die "bad epic '${epic}'"
    [[ "${epic}" != backlog ]] || die "conduct: backlog is the backlog conductor's name; run conduct --backlog, or rename ${epic_file}"
    [[ -f "${epic_file}" ]] || die "no epic ${epic_file}"
    hld=$(sed -n 's/^hld: *//p' "${epic_file}" | head -1); hld="${hld:-${epic}}"
    [[ "${hld}" =~ ^[a-z0-9-]+$ ]] || die "${epic}: bad hld '${hld}'"
  fi
  # Before the brief, the old report's removal and the workspace, so a refusal changes nothing.
  require_claude
  prompt="${PROJECT_DIR}/.swarm/briefs/conduct-${epic}.md"; mkdir -p "$(dirname "${prompt}")"
  conduct_brief "${epic}" > "${prompt}"
  rm -f "$(conductor_report "conduct-${epic}")"   # a report left by an earlier run is not this one's
  read -r ws placeholder <<< "$(hld_workspace "${hld}")"
  # On exit, not after start_agent: a conductor that fails to start dies, and left the tab empty.
  # shellcheck disable=SC2064 # expand now; the tab id is herdr's, [a-zA-Z0-9:]
  [[ -z "${placeholder}" ]] || trap "herdr tab close '${placeholder}' >/dev/null 2>&1 || true" EXIT
  HERDR_WORKSPACE_ID="${ws}" start_agent "${epic}" "conduct-${epic}" "${PROJECT_DIR}" conduct "${prompt}" conductor
  # Notes left for an earlier run are not this one's. Only once it started: a refused second conduct
  # must leave a live conductor's notes; this one reads its inbox only after its first wait.
  inbox="$(conductor_inbox "$(agent_name "conduct-${epic}")")"; rm -f "${inbox}.md" "${inbox}.reading.md"
  echo "workspace ${hld} (${ws})"
  # An epic being built is active, or status and next list it as a later epic waiting on the user.
  # In BOARD_STATE_DIR, as unblock's is (set_fm), never the epic file; any other status is left as it is.
  # The conductor is already running, so a state file that cannot be written is reported, never
  # fatal: a failed conduct would invite a second conductor. set_fm dies, so it runs in a subshell.
  [[ -f "${epic_file}" && "$(get_fm "${epic_file}" status)" == later ]] || return 0
  if err="$(set_fm "${epic_file}" status active 2>&1)"; then
    echo "epic ${epic}: status later -> active (in .swarm/board-state)"
  else
    echo "epic ${epic}: could not write its state in ${BOARD_STATE_DIR}/epics, so it is still later; set status: active by hand (${err#swarm: })" >&2
  fi
}
