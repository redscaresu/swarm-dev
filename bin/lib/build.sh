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
# wait_pr_rule <then> <report> — how every agent waits on a PR's CI: <then>, what it does on red or a
# conflict, and what it does on wait-pr's other exit 2s, the last of which is <report>. wait-pr exits
# on red, on a conflict and on a deadline, where a loop of its own can sit for hours.
wait_pr_rule() {
  echo "Wait on a PR's CI only with \`${SWARM_HOME}/bin/swarm.sh wait-pr <PR URL>\` (in the background), never a loop of your own: $1" \
    "Its other exit 2s print why: on a timeout or no check runs, read the checks once (\`gh pr checks <PR URL>\`), fix a workflow that never started, else run wait-pr again; on a gh error, run it again." \
    "If it ends the same way twice, stop and $2."
}
# stop_rule <epic> — when a conductor stops. With merge = agent it merges its own PRs, so it also
# waits out every running build. The backlog conductor has no Done when: it stops once its stories
# are all started and finished.
stop_rule() {
  if [[ "$1" == backlog ]]; then
    printf '%s' "Stop when no ready story with no \`epic:\` that you may start is left and none is running"
    if [[ "${CFG_merge}" == human ]]; then echo "."; else echo ", or when $(base_stop)."; fi
  elif [[ "${CFG_merge}" == human ]]; then echo "Stop when the epic's **Done when** holds or when nothing ready is left."
  else echo "Stop when the epic's **Done when** holds, when no story of this epic that is yours to start is ready and none is running $(fix_running), or when $(base_stop)."; fi
}
# fix_running — a merging epic conductor's fix-main story has no epic, yet it is the conductor's own to
# review and merge: until it merges, the epic's stop and report rules count it as running.
fix_running() { printf '%s' "(a fix-main story you started counts as running until its PR merges)"; }
# base_stop — the broken base a merging conductor stops on: a red one has a fix-main story to build.
base_stop() { printf '%s' "CI on the base timed out, or is red with no \`fix-main:\` line"; }
# The review every story's PR passes before its builder is closed. The builder keeps its context
# until then, so findings go back to it rather than to a fresh agent that has none. Each PR gets its
# own review agent (review_agent) as soon as it is green, so PRs that land together are reviewed at
# once; the agent runs codex, so the conductor runs it only in codex's place when it was skipped.
review_rule() {
  local sw="${SWARM_HOME}/bin/swarm.sh"
  cat <<EOF
A story is reviewed only when its latest head has passed a review agent's review. The moment a
story's PR head is green and mergeable, start one with \`${sw} review-agent <slug> <PR URL>\`.
Never wait for other PRs or reviews to gather first: run one review agent for every green PR at
once, with no cap below the number of green PRs. When \`swarm.sh watch\` prints, or the lead sends
you, \`queued: <repo> #<n> <branch> green <m>m with no review on <sha>\`, that PR has waited: start its review agent now. It returns at once. It refuses when the story's worktree is not at the PR's head,
or has uncommitted changes: wait for the builder, then start it again. The review agent, review-<slug>, is read-only and runs in
the story's worktree: it runs codex-review with the story's slug and, when the PR changes code (not
only docs, board files or a dependency bump), \`/code-review <PR>\`, judges only the story's touches
and **Done when**, and writes ${PROJECT_DIR}/.swarm/reviews/<slug>.md: a \`head: <SHA>\` line
naming the commit it reviewed, its findings, and an out-of-scope section. Wait on each with
\`swarm.sh wait review-<slug>\` in the background, triage that story's file, then close the review
agent (\`swarm.sh close review-<slug>\`) whatever it found. A file with a \`head moved:\` line, or
with no \`## Findings\` section, is not a pass: start the review again. When the wait returns with
no findings file (it timed out, or the agent waits on a prompt, is gone or needs a login), close the
review agent, never answering its prompt, and start the review again, or read the
diff yourself as for a skipped codex. Send the real findings to the story's
builder with \`${sw} tell <slug> findings <file>\` (a file holding the findings and what to
decline). Log each item of the out-of-scope section with
\`log-finding --declined out-of-scope --reviewer <who>\`, as below.
When a review agent reports \`codex skipped: <why>\` (its file's second line says so too), read the diff yourself in codex's place.
Wait for the builder, then start a new review agent on its new head. Stop at the first pass on the latest head
with nothing substantive: one that finds only nits, edge cases outside the story, or points already
declined is such a pass, even if it is not empty. Rebut what it found in the PR with a reason.
A round is one review whose findings you sent to the builder (\`swarm.sh tell <slug> findings\`); a
review started again (head moved, no \`## Findings\` section, a review agent that timed out or
crashed) is not one. Review stops after round 3: from round 4 on, only a real bug (wrong behaviour,
data loss, a security hole) sends the PR back. Decline anything
smaller with a reason in the PR, and log it with \`log-finding --declined <reason> --reviewer <who>\`
as below: nit for a nit or an edge case, out-of-scope or wrong where they apply.
Before a story merges or goes to review, compare the file's \`head:\` line with the PR's head
(\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`): if they differ, the latest head has
not passed, so review the new head. Never merge a story, and never run \`swarm.sh close <slug>\` on its builder, before
its latest head has passed. Act on each review the moment it finishes: once a PR's latest head has
passed, merge it (or hand it over, as below) at once, and never hold a finished review result back
while other reviews run.

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
  printf '%s' 'Wait for codex-review to exit, and act on what it prints last: a usage limit it prints early may be followed by a fallback'"'"'s review. If it ends on codex'"'"'s usage limit or on "codex skipped: ...", do not run it again: a builder carries on without it, a conductor or the lead reviews the diff itself, and the PR (or a reply, where there is none) says "codex skipped: usage limit" or "codex skipped: timed out".'
  printf ' %s' 'When codex-review prints "reviewed by fallback <model>: codex usage limit", a fallback agent reviewed in codex'"'"'s place: its findings are codex'"'"'s to act on, logged with --reviewer fallback, and the PR says "reviewed by fallback <model>: codex usage limit" in place of codex skipped.'
}
# finding_rule — every fixed finding feeds the outer loop (outcomes' recurring block); declined ones
# are logged too, with their reason, and never count toward it.
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
\`swarm.sh codex-review\` (fallback when it printed "reviewed by fallback"), code-review for /code-review's, ci for the PR review bot's or a
\`swarm.sh findings\` note's, conductor for one from your own reading of the diff, and lead only for
one from the lead's own reading.
When a fix finds a defect in work that already merged, log it as \`--reviewer escaped\` against the
PR that merged it, not the PR that fixes it.
The kind is a short kebab-case name for the class of mistake, not this instance (vacuous-test,
denylist, docs-misstate-code, fails-open); reuse one that
\`awk -F'\\t' 'NF < 5 || \$5 == "fixed" || \$5 == "escaped" { print \$2 }' ${proj}/.swarm/${FINDINGS_LOG_NAME} 2>/dev/null | sort -u\`
already lists when it fits.
EOF
}
# conduct_merge_rule <epic>|backlog — how a conductor hands over or merges a reviewed PR: an epic's, or
# with backlog the backlog conductor's, whose stories have no epic to review or finish.
conduct_merge_rule() {
  local scope="of this epic" epic_end="" backlog=""
  [[ "$1" != backlog ]] || { backlog=1; scope="with no epic"; }
  if [[ "${CFG_merge}" == human ]]; then
    [[ -n "${backlog}" ]] || epic_end=" When every story left
in the epic is in review and the epic's **Done when** will hold once they merge, run
\`swarm.sh review <epic> <every PR URL still waiting>\`: the epic leaves the board once they all merge.
A story \`swarm.sh status\` lists as \`kept:\` is not in review for this: a close kept its PR unreviewed,
so review it (and run \`swarm.sh review <slug> <PR URL>\` once it passes) first."
    cat <<EOF
Never merge a PR, by any route: not \`gh pr merge\`, not \`gh api\`, not the web page. A human merges.
When a story's PR is green and reviewed, run \`swarm.sh review <slug> <PR URL>\` and
\`swarm.sh close <slug>\`. Then $(startable_rule "$1")
$(stacked_start_rule) When \`swarm.sh review\` holds a stacked story instead (\`held: <slug> waits for <p>
to merge\`), the story is blocked again with its build kept: close its builder with a bare
\`swarm.sh close <slug>\`, which counts nothing for a blocked story and keeps its build, and go on.
$(held_ready_rule)${epic_end}
EOF
  else
    [[ -n "${backlog}" ]] || epic_end=" On a board in the project's repo,
the epic leaves the board with its last story's PR, whose brief deletes the epic file. Run
\`swarm.sh finish <epic>\` only on a board outside the repo, or when the epic file is still there after
the last story merged and the epic's **Done when** holds; on a board in the repo it opens a board PR,
which you land with the \`swarm.sh merge --board\` line it prints. Never finish the epic while a story
of it is still in review (a \`costs: money\` one waits for the user's merge): once the Done when will
hold when they merge, run \`swarm.sh review <epic> <every PR URL still waiting>\` instead, and the
epic leaves the board once they all merge. A story \`swarm.sh status\` lists as \`kept:\` does not count
as in review: a close kept its PR unreviewed, so review it first."
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

Then, in this run, $(startable_rule "$1")
$(stacked_start_rule) When \`swarm.sh review\` holds a stacked story instead (\`held: <slug> waits for <p>
to merge\`), the story is blocked again and nothing merges: leave its builder open, unless that line
says \`(costs money)\`. The user merges that parent, maybe days later, so close its builder with a
bare \`swarm.sh close <slug>\`, which counts nothing for a blocked story and keeps its build, as with
merge = human.
$(held_ready_rule) After a
cleared-on-error close or a give-up, start nothing more in this wave. Write your report only when no
story ${scope} that is yours to start is ready and none is running $(fix_running), or $(base_stop).${epic_end}
EOF
  fi
}

# startable_rule <epic>|backlog — after a merge, and after each wait's inbox pass, start every ready story
# in scope with no build, not only the ones this unblock readied: a board PR can add one already ready.
startable_rule() {
  local arg="$1" which="story of this epic"
  [[ "$1" != backlog ]] || { arg=--backlog; which="backlog story"; }
  printf '%s' "run \`swarm.sh unblock --startable ${arg}\`, and start each story it prints as \`startable:\` (every ready ${which} whose build has not started, whether or not this unblock readied it) that clashes with no running one, with \`swarm.sh story --strict <slug>\`. It reads the board as reconcile last left it, and never pulls. Skip a story you closed in this wave (the give-up rule starts it again in a later one), one the give-up rule says not to start again, and one a \`not held:\` line left \`ready\` for the lead. Never start a line that ends \`(its PR <url> was closed unmerged)\`: list it in your report for the lead."
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
# item in review, then swarm.sh merge pinned to the head it reviewed, which reconciles: all at once on a
# base with a merge queue, so the queue batches them, else one at a time.
pinned_merge_rule() {
  cat <<EOF
Merge a PR only when it is green and reviewed, and only through \`swarm.sh merge\`: run
\`swarm.sh review $1\`, then \`swarm.sh merge --head <the SHA on the findings file's head: line> <PR URL>\`, never
\`gh pr merge\` or \`gh api\`. It merges by the literal PR number with \`--match-head-commit <sha>\` and the
repo's merge method, squash when allowed
(\`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed\`), with no --auto
where the base has no merge queue, and only once every check on that head has completed and passed, which it checks itself. On a base
with a merge queue it enqueues that head with \`--auto --match-head-commit\` instead and waits for the
queue, which tests it on top of the base and the PRs ahead of it. A PR the queue drops prints
\`dequeued (<reason>): <checks>\` and merged nothing: handle it like a red check. Send the failing
checks to the builder with \`swarm.sh tell <slug> findings <file>\`, telling it to merge
origin/<base> in, fix what broke and push; then review the new head and merge it again. The first
\`swarm.sh merge\` shows whether the base has a merge queue. Where it prints \`merge queue: <base> has
one\`, start \`swarm.sh merge\` for every PR whose latest head passed review as soon as it passes,
without waiting for the ones before it to merge, so the queue tests them together and merges them in
batches. Where it prints \`merged: <PR URL> (...); waiting for CI on <base>\`, or before any merge has
printed either, run one \`swarm.sh merge\` at a time: start the next only after the previous one has
exited, its base CI and reconcile done. Run each in the background (Bash \`run_in_background\`)
and wait for it: it waits up to $((MERGE_CI_SECONDS / 60)) minutes for CI on the merge commit on the
base, then runs \`swarm.sh reconcile\`, never a plain \`git pull\`, which pulls the board and finishes the item. If
it exits non-zero, read why: a refusal before \`gh pr merge\` ran merged nothing; \`unconfirmed\`
means \`gh pr merge\` ran but the PR never read as merged (a merge queue may hold it), so check it by
hand. A red or timed-out CI on the base means the PR merged and the base is broken: merge nothing
more until it is green, and say so in your report. $(fix_main_rule)
EOF
}

# fix_main_rule — what a merging conductor does when swarm.sh merge finds the base red (fix_main).
fix_main_rule() {
  cat <<EOF
On a red base \`swarm.sh merge\` prints \`fix-main: <checks> on <short sha>\` with the failed jobs'
FAIL lines, and writes the one-off story fix-main-<short sha> (kind code, no epic, those lines in
its body). On \`fix-main\`, start its builder at once with \`swarm.sh story --strict fix-main-<short sha>\`,
ahead of every other story and whatever your scope, and review and merge its PR as any story's: it
is the one merge allowed while the base is red. Never wait on an unrelated PR to fix it. With no
\`fix-main:\` line (CI on the base timed out, or merge says it could not write the story), find the
PR pair that broke it (this PR and one merged before it, each green alone), open the fix or list it
for the lead, and say so in your report.
EOF
}

# A test that passes with its fix removed proves nothing; a builder shows each one can fail, and
# findings names each new test whose FAIL line the PR body lacks.
mutation_rule() {
  printf '%s' "For a code change, prove each new or changed test can fail: back up the file you fixed with cp, break the fix, see the test fail, then restore it with cp (never git checkout, which drops uncommitted work), and paste each test's FAIL line (the line the run printed, with FAIL and the test's name) into the PR body."
}

# load_rule <slug> — a builder's cap on load it starts on purpose: 4 CPUs, gone when the check ends.
load_rule() {
  local slug="$1"
  printf '%s' "If you load the machine on purpose (stress loops, parallel test repeats, containers), use at most 4 CPUs in all, across everything you run at once (\`docker run --cpus 4\`, or that many loops). Cap your test runner's parallelism at 4 (its jobs or workers setting) too; it counts toward the same 4. Start each load process itself, with no wrapper that forks, record each \`\$!\`, and give it a marker in its command line (an argument \`${slug}-load\`), or wrap each in \`timeout <seconds>\`. Never start load with run_in_background, which outlives the step so its trap never fires, unless it is wrapped in \`timeout <seconds>\` no longer than the check and you kill it when the check ends. Remove leftovers from an earlier step first (\`docker rm -f \$(docker ps -aq --filter label=swarm=${slug})\`). Name and label every container (\`--name ${slug}-load-<n> --label swarm=${slug}\`), and remove them by that label in the trap, or use \`--rm\` and still remove them by name: killing the \`docker run\` client leaves the container running. Stop and remove what you started as soon as the check ends, with a trap that kills each recorded PID on EXIT, INT and TERM, and never leave it running between steps. Before you end any turn, check that none of it is still running, orphaned children too, which a load script that forks and exits leaves behind (\`ps -p <pids>\`, \`pgrep -f ${slug}-load\`, killing what it finds by PID, \`docker ps --filter label=swarm=${slug}\`). Say in the PR how you loaded the machine."
}

# reply_sentence — what a builder replies, and when: the brief's rule on finishing, and what its goal
# condition waits for. One sentence, so the two cannot drift.
reply_sentence() {
  printf '%s' "When CI is green, reply with the PR URL, what changed in three lines, and the codex findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR."
}

# story_path <slug> <src> — the story file as its builder names it: relative to the worktree when the
# board is in the repo it builds and git tracks the story (the copy it reads, and its PR deletes),
# else the board's own: an untracked one (fix_main's) is not in the worktree.
story_path() {
  if [[ ${BOARD_IN_REPO} == 1 && "$2" == "${PROJECT_DIR}" ]] \
    && git -C "${PROJECT_DIR}" ls-files --error-unmatch -- "${BOARD}/stories/$1.md" >/dev/null 2>&1; then
    echo "${BOARD#"${PROJECT_DIR}/"}/stories/$1.md"
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
  while state="$(session_state "${name}")"; [[ "${state}" != busy && "${state}" != waiting* && ${SECONDS} -lt ${deadline} ]]; do nap 1; done
  case "${state}" in
    busy) ;;
    waiting*) die "${pre} its builder is waiting on $(waiting_for "${state}"), so no /goal was sent; answer it (herdr agent read ${name})${post}" ;;
    *) die "${pre} its session did not read busy within $((PROMPT_TIMEOUT_MS / 1000))s (${state}), so no /goal was sent${post}" ;;
  esac
  deliver_prompt "${name}" <(goal_message "$(cat "${goal}")") "" once   # read once, so a pipe will do
  deadline=$((SECONDS + PROMPT_TIMEOUT_MS / 1000))
  # A queued paste waits out the deadline: a goal_status may still follow it.
  while entry="$(goal_entry "${name}" "${since}" "${goal}")"; [[ ( -z "${entry}" || "${entry}" == pasted ) && ${SECONDS} -lt ${deadline} ]]; do nap 1; done
  case "${entry}" in
    pasted) die "${pre} its /goal was pasted as text, not run: its session log shows it queued as a prompt and no goal set; its builder is still open${post}" ;;
    refused:*) die "${pre} Claude Code refused its /goal (${entry#refused: }); its builder is still open${post}" ;;
    "") die "${pre} its session log shows no goal set for its condition $((PROMPT_TIMEOUT_MS / 1000))s after the /goal; its builder is still open${post}" ;;
  esac
}

# The brief every story builder gets. The story file is the task; these are the rules.
story_brief() {
  local slug="$1" src="$2" base="$3" story_ref cleanup rel epic check rules trailers
  story_ref="$(story_path "${slug}" "${src}")"
  epic="$(fm "${BOARD}/stories/${slug}.md" epic)"
  if [[ "${story_ref}" != /* ]]; then
    # The board is in this repo: the PR takes the story off it, and the epic with its last story.
    rel="${BOARD#"${PROJECT_DIR}/"}"
    if [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && ! epic_has_stories "${epic}" "${slug}"; then
      cleanup="Delete ${rel}/stories/${slug}.md and ${rel}/epics/${epic}.md (its epic's last story) in your PR, and nothing else under ${rel}/stories/ or ${rel}/epics/."
    else
      cleanup="Delete ${rel}/stories/${slug}.md in your PR, and nothing else under ${rel}/stories/."
    fi
  else
    # The board is elsewhere, or git does not track the story: read it there, and leave it for the
    # lead (reconcile deletes an untracked one once its PR merges).
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
the tests and push: a conflicted PR runs no checks and waits forever. $(wait_pr_rule "on exit 1 fix the red check; on a conflict, do as above." "say so in your reply") $(mutation_rule) Record it
in the PR body. $(load_rule "${slug}") $(reply_sentence)
EOF
  check=""; [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || printf '%s\n' "Before you open the PR, also run the epic's check from the worktree root, and make it pass: \`${check}\`"
  trailers="$(config_trailers)"
  [[ -z "${trailers}" ]] || printf '%s\n%s\n' "End every commit message with these trailers, one per line:" "${trailers}"
  rules="$(project_rules)"
  [[ -z "${rules}" ]] || printf '\n%s\n' "${rules}"
}

# project_rules — the brief, then only the tagged rule lines (the grep below) of the project's
# AGENTS.md, CLAUDE.md and .claude/CLAUDE.md, those it has: a builder in another repo's worktree
# never reads them. These are the files the removed lessons_file could name, so its rules still land.
project_rules() {
  local f
  [[ ! -f "${PROJECT_BRIEF}" ]] || { cat "${PROJECT_BRIEF}"; echo; }   # a brief may lack its final newline
  for f in AGENTS.md CLAUDE.md .claude/CLAUDE.md; do
    grep -hE -- '<!--[[:space:]]*lesson:[[:space:]]*[a-z0-9-]+[[:space:]]*-->' "${PROJECT_DIR}/${f}" 2>/dev/null || true
  done | awk '!seen[$0]++'   # once each, as when CLAUDE.md links to AGENTS.md
}

# agent_kind — true for a kind a swarm agent may build (AGENT_KINDS); an empty kind means code.
# Anything else, lead or a typo, stays with the lead, so an unknown kind can never reach an agent.
# touches_rows.py --idle reads AGENT_KINDS as SWARM_AGENT_KINDS.
AGENT_KINDS="code docs chore"
agent_kind() {
  local k
  [[ -n "$1" ]] || return 0
  for k in ${AGENT_KINDS}; do [[ "$1" == "${k}" ]] && return 0; done
  return 1
}

# story_role <slug> — the role a story is built as: escalate for a kind an agent builds once its
# attempts: reaches escalate_after (> 0), else its kind, code-risky for code with risk: high, and with
# sonnet_share = N, code-sonnet for the other code stories marked easy: true whose slug's cksum mod N
# is 0, so a slug always lands in the same arm. Only a first attempt is sampled: a slug with an
# agents.tsv line already goes back to code. A missing story or a bad attempts: prints the reason and returns 1.
story_role() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind risk attempts easy sum
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
  # Trailing spaces and a CRLF line's \r are trimmed; any value but true stays on code.
  easy="$(get_fm "${story}" easy)"; easy="${easy%"${easy##*[![:space:]]}"}"
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${easy}" != true || ${CFG_sonnet_share} -eq 0 ]]; then echo code; return; fi
  sum="$(printf '%s' "${slug}" | cksum)"; sum="${sum%% *}"
  if (( sum % CFG_sonnet_share == 0 )) \
     && ! awk -F'\t' -v n="$(agent_name "${slug}")" '$3 == n { f = 1 } END { exit !f }' "${AGENTS_LOG}" 2>/dev/null; then
    echo code-sonnet
  else
    echo code
  fi
}

# goal_preflight <slug> <src> — before a builder starts: with goal off, require_claude and an empty
# PREFLIGHT_GOAL; else PREFLIGHT_GOAL is the story's goal condition, refused when its /goal message is
# over GOAL_SEND_MAX or Claude Code is older than GOAL_MIN_CLAUDE. Run in the caller's shell, so a die
# is the command's own.
goal_preflight() {
  local msg
  PREFLIGHT_GOAL=""
  if [[ "${CFG_goal}" == off ]]; then require_claude; return; fi
  PREFLIGHT_GOAL="$(goal_condition "$1" "$2")" || die "${PREFLIGHT_GOAL}"
  msg="$(goal_message "${PREFLIGHT_GOAL}")"
  (( ${#msg} <= GOAL_SEND_MAX )) \
    || die "$1: its /goal message is ${#msg} characters, over GOAL_SEND_MAX (${GOAL_SEND_MAX}), past which Claude Code pastes it as text and never runs it; shorten its board path or slug"
  require_claude "${GOAL_MIN_CLAUDE}"
}

build_story() {
  local slug="$1" strict="${2:-}" story="${BOARD}/stories/$1.md" kind repo src role wt branch prompt base epic goal="" parents names
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
  names="$(story_env "${story}")" || die "${names}"
  policy "${role}" >/dev/null
  src="$(repo_dir "${repo}")" || die "${slug}: ${src}"
  # Before the worktree exists, so a refusal leaves nothing to clean up.
  require_trusted "${src}"
  goal_preflight "${slug}" "${src}"; goal="${PREFLIGHT_GOAL}"
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
  start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}" "${slug}" "${names}"
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
# started (kept aside until then), so the conductor reads only this head's. Once started, the head
# goes in .swarm/reviews/<slug>.head, which review_on_head reads.
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
  echo "${head}" > "${out%.md}.head"
}

# review_pass <slug> <sha> — true when <slug>'s findings file is a pass on <sha>: its head: line is
# <sha>, and it has a ## Findings section and no head moved: line (review_rule's test).
review_pass() {
  local f="${PROJECT_DIR}/.swarm/reviews/$1.md"
  grep -qx "head: $2" "${f}" 2>/dev/null && grep -q '^## Findings' "${f}" && ! grep -q '^head moved:' "${f}"
}

# review_on_head <slug> <sha> — true while <sha> has a review agent's review, for watch and next
# (queued_line): its findings file for <sha> is a pass, or, with no file for <sha> yet, a review agent
# started on it (.swarm/reviews/<slug>.head) and review-<slug> is still open in a pane this project
# opened. One that crashed, was closed or tidied, or that herdr cannot list, is no review.
review_on_head() {
  local f="${PROJECT_DIR}/.swarm/reviews/$1.md"
  if grep -qx "head: $2" "${f}" 2>/dev/null; then review_pass "$1" "$2"; return; fi
  [[ "$(cat "${f%.md}.head" 2>/dev/null)" == "$2" && -n "$(agent_field "$(agent_name "review-$1")" pane_id)" ]]
}

# review_stack_note <slug> <base> — for a story stacked on parents (stacked_parents), that their
# commits are in its diff against <base> but are not its own; nothing for any other story.
review_stack_note() {
  local parents b="" p
  parents="$(stacked_parents "$1")"; [[ -n "${parents}" ]] || return 0
  for p in ${parents//,/ }; do b+="${b:+, }origin/story/${p}"; done
  printf '\n%s\n' "This story is stacked on ${parents}: their branches (${b}) are in its diff against origin/$2, but their code is not this story's. Leave it out of everything you write: it is neither a finding nor out of scope."
}

# SCOPE_RULE: what a reviewer holds out of scope, in the review agent's brief and codex's story prompt
# (so the fallback reviewer's too), the same words in each.
SCOPE_RULE="A point that only a change to a file outside the touches can fix is out of scope, not a finding. A gap in the PR's own code is a finding, even where the touches and Done when do not name it."

# DECISION_MAX_BYTES: the most of one marked line a review brief carries; a longer one is cut on a
# character boundary, with "…". DECISIONS_MAX_BYTES: the most all of them take together; a line past
# it is left out, and the brief says how many were and in which files they are.
DECISION_MAX_BYTES=1500
DECISIONS_MAX_BYTES=2000

# user_decisions <file>... — each line of the files that holds a `(user, <date>` mark, verbatim, as
# `- <path>:<line>: <text>` (the path relative to the project), while they fit in DECISIONS_MAX_BYTES. A mark inside a fenced block (a
# ``` line toggles it), an inline code span or the first file's (the story's) **Done when** section,
# which the brief already quotes, is not a decision; an epic's decisions sit in its Done when.
user_decisions() {
  LC_ALL=C awk -v max="${DECISION_MAX_BYTES}" -v all="${DECISIONS_MAX_BYTES}" -v story="$1" -v root="${PROJECT_DIR}/" '
    function rel(f) { return index(f, root) == 1 ? substr(f, length(root) + 1) : f }
    function marked(s) { gsub(/`[^`]*`/, "", s); return s ~ /\(user, [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ }
    FNR == 1 { fence = 0; dw = 0 }
    /^ *```/ { fence = !fence; next }
    fence { next }
    /^\*\*|^#/ { dw = FILENAME == story && index($0, "**Done when") == 1 }
    dw || !marked($0) { next }
    {
      d = $0
      if (length(d) > max) {
        # Back off while the byte after the cut is a UTF-8 continuation byte (10xxxxxx).
        for (n = max; n > 0 && substr(d, n + 1, 1) >= "\200" && substr(d, n + 1, 1) < "\300"; n--) ;
        d = substr(d, 1, n) "…"
      }
      d = (out == "" ? "" : "\n") "- " rel(FILENAME) ":" FNR ": " d
      if (length(out) + length(d) <= all) out = out d
      else { left++; if (!(FILENAME in named)) { named[FILENAME]; where = where (where == "" ? "" : ", ") rel(FILENAME) } }
    }
    END {
      if (out != "") print out
      if (left) printf "\n%d more decision%s left out of this brief (past %d bytes): read %s.\n", left, (left > 1 ? "s are" : " is"), all, where
    }' "$@"
}

# review_checklist [story file] — the checks the lead learned by hand, one line each, for the review
# agent's and the fallback reviewer's briefs. With a story file, also the check on the user's
# decisions and each decision its story and its epic mark (user_decisions).
review_checklist() {
  local epic decisions files
  cat <<'EOF'
Hold the PR to these as well:
- A claim checked against a stand-in (a mock, a sibling API, a narrower sample) is unverified.
- An audit or test scoped to one file, when the defect class spans many, is a finding.
- A new code path must enforce every rule the existing paths enforce.
- A zero or empty value shown to a person must say what it means.
- A repair path that changes something must say what it did.
EOF
  [[ -f "${1:-}" ]] || return 0
  # shellcheck disable=SC2016 # the backticks are for the reader
  echo '- A change that contradicts a decision marked `(user, <date>)` in the epic or story is a finding, even when it is stricter.'
  files=("$1"); epic="$(fm "$1" epic)"
  [[ -z "${epic}" || ! -f "${BOARD}/epics/${epic}.md" ]] || files+=("${BOARD}/epics/${epic}.md")
  decisions="$(user_decisions "${files[@]}")"
  [[ -z "${decisions}" ]] || printf '\n%s\n%s\n%s\n' "The user's decisions, from the story and its epic:" "${decisions}" \
    "Read each decision in full at that line (it may continue on the following lines or list items) before you judge the PR against it."
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

Judge the PR against these touches and items. ${SCOPE_RULE}
$(review_stack_note "$1" "$3")
Run \`$(codex_review_cmd "$3" "$1")\` in the background (Bash run_in_background) and wait for it to
finish: it can run for ${CFG_codex_minutes} minutes, longer than a foreground Bash call may last.
Wait for it to exit, and act on what it prints last: a usage limit it prints early may be followed by
a fallback's review. If it ends on codex's usage limit or on "codex skipped: ...", do not run it
again: you report \`codex skipped: usage limit\` or \`codex skipped: timed out\`. When it prints
\`reviewed by fallback <model>: codex usage limit\`, a fallback agent reviewed in codex's place: report
its findings as codex's, under that line. When the PR
changes code (not only docs, board files or a dependency bump), state the touches and Done when
above, then run \`/code-review $2\`.

$(review_checklist "${story}")

When both are done, check that \`git rev-parse HEAD\` still prints $5 and \`git status --porcelain\`
prints nothing. If not, the worktree moved under you: write ${4} with the Write tool holding two
lines, \`head: $5\` and \`head moved: <what changed>\`, then stop.

Otherwise, write ${4} with the Write tool, in one go (the conductor's wait ends once it exists).
Its first line is \`head: $5\`; when codex was skipped, its second is \`codex skipped: <why>\`.
Under a \`## Findings\` heading,
one line per finding: its reviewer (codex or code-review), file:line, and the finding; with none, say
so. Under a \`## Out of scope\` heading, the same for each point a reviewer raised that only a
change to a file outside the touches can fix, so the conductor can decline it; with none, say so. Then reply with
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

# board_pr_merge_rule — who lands a conductor's board PR: the conductor with merge = agent, the user
# with merge = human.
board_pr_merge_rule() {
  if [[ "${CFG_merge}" == human ]]; then
    echo "With merge = human you cannot land that PR: list it in your report for the user."
  else
    echo "Land it with \`swarm.sh merge --board <url>\` once its checks are green."
  fi
}

# The brief a conductor gets: one epic, from a fresh session, so its context holds only that epic.
# The epic backlog is the backlog conductor's: the ready stories with no epic.
conduct_brief() {
  local epic="$1" inbox scope="Stay inside this epic: start no story outside it, and leave the HLD and other epics alone."
  inbox="$(conductor_inbox "$(conductor_name "$1")")"
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

When the board is in the project's repo, make a scope or body edit to a story in a board PR
(\`swarm.sh board-pr\`), as the lead does, never in the main checkout. $(board_pr_merge_rule) A builder
starts from origin's base, so it reads the old story text until that PR merges: do not start, or
start again, a story whose edit is still in a board PR.

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
read the moved copy, act on it, and delete it. Do this before that wait's \`swarm.sh unblock --startable\`
run (above), so one run starts what the notes made ready too. Do all this once more just before you
write your report, so a note left after your last wait is not lost. If that last pass read a note,
then $(startable_rule "${epic}") If that starts a builder, do not write the report: go back to waiting.
EOF
  # shellcheck disable=SC2154 # assigned in another file
  [[ -z "${CFG_escalate_ladder:-}" ]] || cat <<EOF

swarm.sh steps a build up the escalation ladder (${CFG_escalate_ladder}) itself when its builder
stops with no PR (close), stalls (\`wait --stall\`), is sent findings round ${STEP_UP_FINDINGS} of its build
(tell), or its PR's checks go red on ${STEP_UP_RED_HEADS} heads of its build (\`watch --epic\` or
\`--backlog\`). That command then prints \`stepped up: <slug>\` (wait prints it in place of
\`stalled:\`): the next model carries on in the same worktree and branch. Do not close, retry or
tell that story for it; wait on its builder again. A \`step-up failed: <slug>\` line means the
step-up stopped after closing the builder: leave that story alone and list it for the lead.
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
never dismiss an alert. $(wait_pr_rule "on exit 1 or a conflict, send the story's builder a nudge with \`${SWARM_HOME}/bin/swarm.sh tell <slug> nudge <file>\` (never findings, which count as a review round) naming the red check, or the base to merge in." "report it to the lead")
EOF
}

# auth_rule — what a conductor does when `wait` on a builder prints auth, or a stuck: line.
auth_rule() {
  cat <<EOF
A builder whose \`swarm.sh wait\` prints \`auth\` stopped on an expired login, which only the user's
/login clears: do not tell it, nudge it or wait on it again. Note it, and once you are told your
login is renewed, tell each such builder to resume (\`swarm.sh tell <slug> resume <file>\`) and wait on it
again with \`swarm.sh wait <slug>\` in the background.

A \`wait\` that prints a line starting \`stuck:\` (exit 4) is not a stall: never close the builder as
stalled for it. \`stuck: api error\` is a turn that stopped on an API error after wait told it to carry
on three times: read the pane (\`herdr agent read <pane>\`), then tell it to resume once more and
wait on it again, or list it for the lead. \`stuck: no output for <N>m (<pane>)\` is a busy session
whose pane has not changed that long with no background task running; \`tell\` refuses a busy
session, so do not tell it: read the pane and list it for the lead. With goal on, wait never tells a
builder to carry on: its \`stuck: api error\` is the goal rule's to read, and the goal rule's close
for it stands.
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
  Run \`swarm.sh close <slug> impossible --drop\`, which makes the story \`kind: lead\`, and list it for the lead.
- stalled: \`wait --stall\` returned stalled.$([[ -z "${CFG_escalate_ladder:-}" ]] || echo " (With escalate_ladder set, a stall it steps up prints \`stepped up:\` instead: wait on the builder again, and close nothing.)")
  When its line names a hung command (\`longest-running: pid ...\`), stop it as the give-up rule
  below says and wait on the builder again. When nothing is named, or it stalls again after that,
  close it: Run \`swarm.sh close <slug> stalled --drop\` and start the story again in a later wave.
- bound: the reply is not there, and the met entry's reason says the stop-after clause applied.
  Run \`swarm.sh close <slug> bound --drop\` and start the story again in a later wave.
- paused: the goal is still set, with no met entry since, and the builder is idle.
  Send it one \`swarm.sh tell <slug> resume <file>\` and wait on it again.
  If it stops paused again, run \`swarm.sh close <slug> paused --drop\`. It counts nothing and holds the
  story for the lead (\`kind: lead\`, \`held_for: paused\`): list it for the lead, as for cleared-on-error.
- cleared-on-error: the transcript holds a \`/goal\` refusal (a \`system\` \`local_command\` entry whose
  stdout refuses \`/goal\`, with no \`goal_status\` after it), or the goal is gone and the transcript
  ends on an API error (wait prints \`stuck: api error\` for it); or \`swarm.sh story\` failed on a refused goal.
  Run \`swarm.sh close <slug> cleared-on-error --drop\`, start nothing more in this wave, and list it for
  the lead, who decides whether to build it again. The close holds the story for the lead
  (\`kind: lead\`, \`held_for: cleared-on-error\`), so no wave builds it until the lead lifts the hold.
  If either close prints no \`held:\` line (it prints \`not held:\` instead), the story stays \`ready\`
  with nothing on it to say so: do not start it again in a later wave. It waits for the lead.
- none of the above fits (no reply, no refusal, no stall, and no goal entry, or a met entry whose
  reason is not the stop-after clause): run \`swarm.sh close <slug> stalled --drop\`, which counts the
  attempt so escalate_after bounds the retries, and start the story again in a later wave.
EOF
}

# give_up_rule — when a conductor stops waiting on a builder and builds the story again, and how it
# answers Fable's usage-credits consent, which is not giving up. With goal on, an idle builder is the
# goal rule's, and the stall close names its cause.
give_up_rule() {
  local retry idle="when it is idle with no PR after wait's nudges, " close="\`swarm.sh close <slug> --drop\`" one="That is the one close before a review passes." goal=""
  if [[ "${CFG_goal}" != off ]]; then
    idle=""
    close="\`swarm.sh close <slug> stalled --drop\` for a stall, or \`swarm.sh close <slug> met --drop\` when review has not converged"
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
Give up on a builder when \`swarm.sh wait --stall <slug>\` returns stalled with no hung command to
stop (below), or stalls again after you stopped one, ${idle}or when review has not converged in the
rounds you allow. Run ${close}: on a code, docs or chore story still \`ready\` it
counts the attempt and clears its worktree, branch and PR (a bare close keeps an open PR). ${one} Start the story again in a later
wave with \`swarm.sh story --strict <slug>\`, and never choose a model: ${retry}${goal}
A stalled line ends \`; longest-running: ...\`, and after \`stepped up:\` the same text is a line of
its own. \`pid <PID>, <N> min: <program> (under <parents>)\` names what the builder's foreground Bash
call runs, the leaf of its chain of parents, by program name only. It may still be wrong (a server
the builder started on purpose, or gone once a step-up closed the pane). Read the chain, and check
the PID with \`ps -o pid,ppid,etime,command -p <PID>\` before you stop anything. Stop only a hung
leaf, by its PID (\`kill <PID>\`, never pkill or killall), then tell the builder what you killed and
why (\`swarm.sh tell <slug> nudge <file>\` once it is idle), and wait on it again instead of closing.
\`none named (<why>)\` leaves nothing to stop. A stepped-up build's next rung works in the same
worktree, so a hung command there is still yours to stop.
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
# unblock --startable after each wait, watch and new PR, then act on status's Stacked lines (stacked_lines),
# which cover the whole board, for its own stories only.
stacked_rule() {
  local mine="a story with \`epic: $1\`"
  [[ "$1" != backlog ]] || mine="a story with no \`epic:\`"
  cat <<EOF
After each \`swarm.sh wait\` or \`swarm.sh watch\` returns (after its inbox pass, below), and after a
builder opens a PR, $(startable_rule "$1") Yours is ${mine}; a ready story whose worktree exists has
started: never run \`swarm.sh story\` for it. Then run \`swarm.sh status\` and read its Stacked lines.
Unblock's \`ready:\` lines and the Stacked lines cover the whole board: act only on a line whose
<child> is yours, and leave the rest to their own conductor.
- \`<child>: merge <ref>\`: write a file saying to merge <ref> into its branch, re-run the tests and
  push, and send it with \`swarm.sh tell <child> nudge <file>\` (not findings: those count review rounds). On a line that ends \`(no builder)\`,
  first start a builder in the child's worktree (\`<repo>-wt/<child>\` beside its repo) with
  \`swarm.sh agent <tab> <child> <worktree> <role> <brief>\`, where <tab> is the child's \`epic:\` (its
  slug when it has none), <role> is what \`swarm.sh _role <child>\` prints, and the brief says the
  same and to reply with the PR URL. Any review of the child from before that merge is stale: review
  the new head. The line stays until the child pushes the merge, so send each merge once: until the
  child's builder replies to that tell (or brief), skip a line for the same child and ref.
- \`<child>: lost story/<p>\`: on a ready child whose builder is open, run \`swarm.sh close <child>
  paused --drop\`, which holds it for the lead. If the line ends \`(no builder)\`, or close prints
  \`not held:\`, the child stays ready on a dead parent: do not start it, and list it in your report
  for the lead. A lost line on a held (blocked) child goes in your report too.
- \`<child>: could not check <what>\`: a gh or git call failed, so nothing is known: read status
  again after your next wait, and if the line stays, list it in your report.
EOF
}

# clash_rule — when two stories may build at once, and what a conflict with the base costs. Git merges
# edits to different parts of one file, so only a shared symbol or a bare file holds a story back.
clash_rule() {
  cat <<EOF
Two stories clash only when their \`touches\` name the same \`file:symbol\` in the same repo, or
when either names the bare file (no \`:symbol\`) of a file the other also names in the same repo.
Otherwise both build at once, even in the same file. A builder whose PR conflicts with its base
merges the base in, resolves it, re-runs the tests and pushes. A conflict never sends a story back
to \`ready\`: never close a builder over one. When \`swarm.sh watch\` says a PR CONFLICTS, write a
file saying to merge origin/<base> into its branch, resolve it, re-run the tests and push, and to
stop waiting on CI until then (a conflicting PR runs none). Send it with \`swarm.sh tell <slug> nudge
<file>\`, never as findings, which would count as a review round. Watch reports each conflict once,
so do not drop it: if the builder is working, run \`swarm.sh wait <slug>\` in the background and send
it once the wait returns. If the story has no builder (closed after \`swarm.sh review\`), start one
in its worktree with \`swarm.sh agent <tab> <slug> <worktree> <role> <brief>\`, as the Stacked rule
below does for \`(no builder)\`, with a brief that says the same and to reply with the PR URL. If its
worktree is gone too, list the PR in your report for the lead.
EOF
}

# A PR per story.
conduct_story_mode() {
  local epic="$1"
  cat <<EOF
Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) to merge, as reference.md
§ Building describes: pick waves of \`ready\` stories that do not clash,
start each with \`${SWARM_HOME}/bin/swarm.sh story --strict <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch --epic ${epic}\` in the background, and review each PR. Each story's base branch is in its brief,
.swarm/briefs/<slug>.md.

$(clash_rule)

$(stacked_rule "${epic}")

$(auth_rule)$(goal_rule_if_on)

$(give_up_rule)

$(green_rule)

$(review_rule)

$(conduct_merge_rule "${epic}")
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
§ Building describes: pick waves of them that do not clash, start each with
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

$(clash_rule)

$(stacked_rule backlog)

$(auth_rule)$(goal_rule_if_on)

$(give_up_rule)

$(green_rule)

$(review_rule)

$(conduct_merge_rule backlog)
EOF
}

# epic_workspace <label> — the herdr workspace labelled <label>, created if there is none. A conductor's
# label is its epic's parent: (so the child epics of a split one share a workspace), else the epic's own
# slug. A new workspace's placeholder tab is closed once the caller has added its own.
epic_workspace() {
  local label="$1" ws
  ws=$(herdr workspace list | json "next((w['workspace_id'] for w in d['result']['workspaces'] if w.get('label')=='${label}'),'')")
  if [[ -z "${ws}" ]]; then
    ws=$(herdr workspace create --label "${label}" --cwd "${PROJECT_DIR}" --no-focus \
      | json "d['result']['workspace']['workspace_id']+' '+d['result']['tab']['tab_id']")
  fi
  echo "${ws}"
}

# conductor_name <epic>|backlog — a conductor's agent name. herdr's names span projects and every
# project has a backlog, so the backlog conductor's is conduct-backlog-<the dir's name, cut to 9>-<6 hex
# of the project's path>: 32 characters at most, distinct for two dirs of one name, and never ending
# like a retired agent's (-done).
conductor_name() {
  local n crc
  [[ "$1" == backlog ]] || { agent_name "conduct-$1"; return; }
  # Sanitized before the cut: a multibyte character can become several dashes.
  n="$(agent_name "conduct-backlog-$(basename "${PROJECT_DIR}")")"; crc="$(printf '%s' "${PROJECT_DIR}" | cksum)"
  printf '%s-%06x' "${n:0:25}" $((${crc%% *} % 16777216))
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
  [[ "${want}" != "$(conductor_name backlog)" ]] || { echo backlog; return; }   # even with no brief
  # shellcheck disable=SC2012 # newest first; brief names are epic slugs, [a-z0-9-]
  while IFS= read -r f; do
    e="$(basename "${f}" .md)"; e="${e#conduct-}"
    [[ "$(conductor_name "${e}")" == "${want}" ]] && { echo "${e}"; return; }
  done < <(ls -t "${PROJECT_DIR}/.swarm/briefs"/conduct-*.md 2>/dev/null)
  echo "${want#conduct-}"
}

# epic_env <epic> — the env: names of the stories in <epic> (empty: the stories with no epic) that a
# builder may still get: open (ready, blocked, or review, whose PR may close unmerged and send it back
# to ready) and of a kind an agent builds. A lead story's names stay with the lead, and a done one's
# never stop a conductor. Each is checked as story_env does; a refused one prints the reason and
# returns 1.
epic_env() {
  local s n out=""
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] || continue
    case "$(fm "${s}" status)" in ready|blocked|review) ;; *) continue ;; esac
    agent_kind "$(fm "${s}" kind)" || continue
    n="$(story_env "${s}")" || { echo "${n}"; return 1; }
    out+=" ${n}"
  done < <(board stories)
  printf '%s' "${out# }"
}

# start_conductor <epic>|--backlog — a conductor for one epic, or with --backlog for the ready
# stories with no epic: conduct-backlog-<project dir> (conductor_name), in a workspace named backlog, needing no epic file.
start_conductor() {
  local epic="$1" epic_file="${BOARD}/epics/$1.md" label prompt ws placeholder inbox err names tab name report
  if [[ "${epic}" == --backlog ]]; then
    epic=backlog; label=backlog; epic_file="${BOARD}/epics/backlog.md"
    # conduct-backlog would be both conductors' name, brief and report.
    [[ ! -e "${epic_file}" ]] || die "conduct --backlog: ${epic_file} is an epic named backlog; rename it first"
  else
    [[ "${epic}" =~ ^[a-z0-9-]+$ ]] || die "bad epic '${epic}'"
    # An epic whose conductor would take this project's backlog conductor's name.
    [[ "${epic}" != backlog && "$(conductor_name "${epic}")" != "$(conductor_name backlog)" ]] \
      || die "conduct: ${epic} would take the backlog conductor's name; run conduct --backlog, or rename ${epic_file}"
    [[ -f "${epic_file}" ]] || die "no epic ${epic_file}"
    label="$(fm_list "${epic_file}" parent)"; label="${label:-${epic}}"
    [[ "${label}" =~ ^[a-z0-9-]+$ ]] || die "${epic}: bad parent '${label}'"
  fi
  # Before the brief, the old report's removal and the workspace, so a refusal changes nothing.
  require_claude
  if [[ "$1" == --backlog ]]; then names="$(epic_env "")"; else names="$(epic_env "${epic}")"; fi || die "${names}"
  name="$(conductor_name "${epic}")"; free_agent_name "${name}"   # a name held elsewhere leaves the report be
  prompt="${PROJECT_DIR}/.swarm/briefs/conduct-${epic}.md"; mkdir -p "$(dirname "${prompt}")"
  conduct_brief "${epic}" > "${prompt}"
  report="${PROJECT_DIR}/.swarm/conduct-${epic}.report.md"
  # A report left by an earlier run is not this one's. Its time, when that run ended, goes to
  # events.tsv first: outcomes' held_min ends the run there.
  [[ ! -f "${report}" ]] || record_event report "${epic}" "ok ($(date -u -r "${report}" +%Y-%m-%dT%H:%M:%SZ))"
  rm -f "${report}"
  read -r ws placeholder <<< "$(epic_workspace "${label}")"
  # On exit, not after start_agent: a conductor that fails to start dies, and left the tab empty.
  # shellcheck disable=SC2064 # expand now; the tab id is herdr's, [a-zA-Z0-9:]
  [[ -z "${placeholder}" ]] || trap "herdr tab close '${placeholder}' >/dev/null 2>&1 || true" EXIT
  # The backlog's tab takes the conductor's name too: every project's backlog tab shares the workspace
  # named backlog, and close shuts every tab with its label there.
  tab="${epic}"; [[ "${epic}" != backlog ]] || tab="${name}"
  HERDR_WORKSPACE_ID="${ws}" start_agent "${tab}" "${name}" "${PROJECT_DIR}" conduct "${prompt}" conductor "${names}"
  # Notes left for an earlier run are not this one's. Only once it started: a refused second conduct
  # must leave a live conductor's notes; this one reads its inbox only after its first wait.
  inbox="$(conductor_inbox "${name}")"; rm -f "${inbox}.md" "${inbox}.reading.md" "${inbox}.woke" "${inbox}.later" "${inbox}.upgrade"; rmdir "${inbox}.lock" 2>/dev/null || true
  echo "workspace ${label} (${ws})"
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
