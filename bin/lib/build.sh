# shellcheck shell=bash

# findings_goal <slug> <since> <goal-file> <from> — send the builder a fresh /goal mid-turn, once its findings
# are taken up, so the goal drives the fix (sent after the turn, the judge would find it met at once): the
# findings addressed, the reply its brief asks for in its mode, and the turn bound. Mid-turn it sets at
# once and costs one extra short turn, as build_story's does. send_goal confirms it from entries newer
# than the tell, so the build-time goal never counts; a refusal or no entry fails naming the story.
# <from> is who sent the tell, review or conductor, as tell_agent read it (tell_from) for the header:
# the goal names the review agent's findings, or the conductor's review findings, to match.
findings_goal() {
  local what="the conductor's review findings"
  [[ "$4" != review ]] || what="the review agent's findings"
  # shellcheck disable=SC2154 # assigned in another file
  printf '%s %s %s\n' "The goal: ${what}, sent to you just before this goal, are addressed (each fixed, or declined with a reason in your reply) and you have replied." \
    "$(reply_sentence)" "It is met once both hold, or stop after ${CFG_goal} more turns." > "$3"
  send_goal "$1" "$3" findings "$2"
}

# The merge and review rules, shared by the briefs.
merge_rule() {
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge}" == human ]]; then echo "Never merge, by any route (a human merges)."
  else echo "Never merge, by any route (the conductor or the lead merges, with swarm.sh merge)."; fi
}
# wait_pr_rule <then> <report> <head> — how every agent waits on a PR's CI: on <head> (wait-pr's --head:
# right after a push GitHub can still report the old head), <then>, what it does on red, a conflict or a head the PR never got,
# and what it does on wait-pr's other exit 2s, the last of which is <report>. wait-pr exits on red, on
# a conflict and on a deadline, where a loop of its own can sit for hours.
wait_pr_rule() {
  echo "Wait on a PR's CI only with \`${SWARM_HOME}/bin/swarm.sh wait-pr --head $3 <PR URL>\` (in the background), never a loop of your own: $1" \
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
or has uncommitted changes: wait for the builder, then start it again. The review agent, review-<slug>, never edits the PR's code and runs in
the story's worktree: it runs codex-review with the story's slug and, on the story's first round
only, when the PR changes code (not only docs, board files or a dependency bump),
\`/code-review <PR>\` (review-agent counts the rounds itself), judges only the story's touches
and **Done when**, and writes ${PROJECT_DIR}/.swarm/reviews/<slug>.md only when a round passes or
it stops: a \`head: <SHA>\` line naming the commit it reviewed, then on a pass a \`## Findings\`
section with none to fix and a \`## Handled by the review agent\` section of the points it declined
or found out of scope, logged and rebutted already, or on a stop a \`stopped: <why>\` line; the
findings it sends the builder itself are in <slug>.round.md beside it. On a pass it runs
\`swarm.sh review <slug> --head <SHA> <PR URL>\` itself, then merges the PR (merge = agent, or an HLD that
grants merge) or leaves it for the user. Wait on each with
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
Wait for the builder, then start a new review agent on its new head.
A round is one review whose findings you sent to the builder (\`swarm.sh tell <slug> findings\`); a
review started again (head moved, no \`## Findings\` section, a review agent that timed out or
crashed) is not one. A review on the latest head whose findings you fix none of is a pass: one with
no findings, or whose every finding you decline (a nit, low value, out of scope, wrong, or a point
already declined). Never send such a review to the builder. Rebut each declined finding in the PR
with a reason, log it with \`log-finding --declined <reason> --reviewer <who>\` as below: nit for
a nit, an edge case or a low-value point, out-of-scope or wrong where they apply, and a point
already declined with the reason it was first declined with.
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

    SWARM_PROJECT=${proj} ${sw} log-finding --reviewer <who> --round <n> <kind> <PR URL> "<one line>"
    SWARM_PROJECT=${proj} ${sw} log-finding --declined <reason> --reviewer <who> --round <n> <kind> <PR URL> "<the finding, and why it was declined>"

<n> is the review round the finding came from on a story PR: the n-th review of the PR is round n,
the one that passes included, so a nit the passing review raised and you declined is logged under its
own round. A review started again (head moved, no \`## Findings\` section, timed out or crashed) is
no new round. <n> is 0 for a finding on a plan or a board PR.

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

When \`swarm.sh merge\` prints \`base merged: <PR URL> is now <new> (<old> with <base> merged in)\`,
code landed on <base> after <old>'s CI ran, so it had GitHub merge <base> into the PR's branch and
checked that the new head's only new content is <base>'s. That head needs no new review: where you
compare heads, a head events.tsv records as \`merge <slug> base-merged <sha> from <head>\` counts as
reviewed when <head> was, and \`swarm.sh watch\` prints no line that sends it to review. Merge
then waits for that head's CI, checks <base> again (merging it in again if it moved, ${MERGE_BASE_ROUNDS}
rounds at most) and merges the new head itself, so it can run up to $((MERGE_CI_SECONDS / 60)) minutes
longer for each round: leave it to finish. If it prints \`already merged:\`, the PR
merged while it waited (another \`swarm.sh merge\`, or by hand), and merge reconciled the board. If it refuses
with \`base merged, <cause>:\`, it merged nothing, and the PR's head is GitHub's merge commit, which
the builder's worktree does not have. Any nudge you send the builder for it tells it to pull its branch
first (\`git pull --ff-only origin story/<slug>\`, naming the branch: its worktree tracks origin/<base>,
or nothing when stacked). Handle a \`red\` as a red check, a \`conflict\` as the refusal below that ends
\`merge origin/<base> in, push, and merge the new head\`, and a \`head moved\` (a push while merge
waited) by reviewing the new head as for any new head. On any other cause (\`no check runs\`,
\`no workflow run\`, \`timed out\`, \`unread\`, \`still moving\`), and when merge cannot take its lock
again after the wait, run the \`swarm.sh wait-pr --head <new head> <PR URL>\` the line names in the
background and, once it exits 0, the \`swarm.sh merge --head <new head> <PR URL>\` it names, in place of
the findings file's head: line.
When \`swarm.sh merge\` refuses with a line that ends \`merge origin/<base> in, push, and merge the new
head\` (\`the base <base> moved past <sha>'s CI\` when GitHub could not merge it in, or a compare that
cannot list what the base gained), it merged nothing: code may have landed on <base> after that head's
CI ran, so the two were never tested together. This refusal is yours to handle, not the lead's. Send
the builder a nudge with \`swarm.sh tell <slug> nudge <file>\` (never findings, which count as a review
round) telling it to pull its branch (\`git pull --ff-only origin story/<slug>\`), merge origin/<base>
in, re-run the tests and push; with no
builder, start one as the clash rule says for a conflict. Wait for the new
head's CI with \`swarm.sh wait-pr <PR URL>\` in the background, review the new head as for any new
head, and merge the head that review passed with \`swarm.sh merge --head <sha> <PR URL>\`, as below.
When it refuses with \`base merge unchecked:\`, the PR's head moved and merge could not show that its
only new content is <base>'s: a builder's push, a merge someone made by hand, or GitHub's own merge of
<base> that touches a file the PR changed too. Review the new head as for any new head. If that review
sends findings, tell the builder to pull its branch first (\`git pull --ff-only origin story/<slug>\`):
the new head may be a merge commit its worktree does not have, and its push would be refused.

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
  printf '%s' "run \`swarm.sh unblock --startable ${arg}\`, and start each story it prints as \`startable:\` (every ready ${which} whose build has not started, whether or not this unblock readied it) that clashes with no running one, with \`swarm.sh story --strict <slug>\`. It reads the board as reconcile last left it, and never pulls. Skip a story you closed in this wave (the give-up rule starts it again in a later one), one the give-up rule says not to start again, and one a \`not held:\` line left \`ready\` for the lead. Never start a line that ends \`(its PR <url> was closed unmerged)\`: list it in your report for the lead. For each \`startable:\` story you do not start, other than a closed-unmerged one, run \`swarm.sh hold <slug> '<why>'\`, naming what it clashes with (the story or PR) and the shared files, or the other reason (the give-up rule, closed this wave, \`not held:\`). Run it at most once per wave for a story, and in a later wave only when the reason changed."
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
  printf '%s' "If you load the machine on purpose (stress loops, parallel test repeats, containers), use at most 4 CPUs in all, across everything you run at once (\`docker run --cpus 4\`, or that many loops). Cap your test runner's parallelism at 4 (its jobs or workers setting) too; it counts toward the same 4. Start each load process itself, with no wrapper that forks, record each \`\$!\`, and give it a marker in its command line (an argument \`${slug}-load\`), or wrap each in \`timeout <seconds>\`. Never start load with run_in_background, which outlives the step so its trap never fires, unless it is wrapped in \`timeout <seconds>\` no longer than the check and you kill it when the check ends. Remove leftovers from an earlier step first (\`docker rm -f \$(docker ps -aq --filter label=swarm=${slug})\`). Name and label every container (\`--name ${slug}-load-<n> --label swarm=${slug}\`), and remove them by that label in the trap, or use \`--rm\` and still remove them by name: killing the \`docker run\` client leaves the container running. Stop and remove what you started as soon as the check ends, with a trap that kills each recorded PID on EXIT, INT and TERM, and never leave it running between steps. Before you end any turn, check that none of it is still running, orphaned children too, which a load script that forks and exits leaves behind (\`ps -p <pids>\`, \`pgrep -f '[${slug:0:1}]${slug:1}-load'\`, killing what it finds by PID, \`docker ps --filter label=swarm=${slug}\`). Say in the PR how you loaded the machine. Never poll with a \`pgrep -f\` pattern that matches the poll's own command line or another poll's: such a loop finds itself or its twin and never ends. Poll the PIDs you recorded with \`ps -p <pids>\` (a later step's shell cannot \`wait\` on them), and find load by its \`${slug}-load\` marker with the bracketed pattern above, keeping the bare marker out of the poll's own command."
}

# review_tests_rule <dir> — what a builder runs after review fixes: only the tests for the change, as
# a full local run is slow and CI shards the full suite. It names
# scripts/select-tests.sh only when <dir>, the tree the builder works in, has it.
review_tests_rule() {
  if [[ -f "$1/scripts/select-tests.sh" ]]; then
    printf '%s' "After review fixes, run only the tests mapped to the change (\`scripts/select-tests.sh --run\`) and let CI run the full suite."
  else
    printf '%s' "After review fixes, run only the project's own tests for the change and let CI run the full suite."
  fi
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
# whitespace aside. Any goal_status newer than <since> means it set: the judge may already have
# written its own after the sentinel. A refusal, or no entry, fails naming the story and why (a /goal
# Claude Code queued as pasted text, when goal_entry finds one), and leaves the builder open for the
# lead to read. <since> defaults to now. The /goal goes only into a
# turn that has started: herdr can say working while the session is still idle, and deliver_prompt
# takes blocked as taken up, so it waits up to PROMPT_TIMEOUT_MS for the session (session_state) to
# read busy, or, for the brief, idle with own work (session_mtime) at or after <since>: a short first
# turn that ended before this read took the brief. Findings get no such shortcut: their /goal must go
# mid-turn (findings_goal). It fails with nothing sent if it reads waiting (a dialog, where Enter could
# approve what auto mode flagged) or neither. Each failure says the brief or the findings were
# delivered, so they are not sent again.
send_goal() {
  local slug="$1" goal="$2" name since="${4:-$(date +%s)}" entry deadline state pre post t want="read busy, or idle with work since the brief,"
  name="$(agent_name "${slug}")"
  pre="${slug}: the brief was delivered, but"; post="; do not send it again"
  [[ "$3" != findings ]] || { pre="${slug}: the findings were delivered, but"; post="; do not send them again"; want="read busy"; }
  deadline=$((SECONDS + PROMPT_TIMEOUT_MS / 1000))
  while state="$(session_state "${name}")"
    if [[ "${state}" == idle && "$3" == brief ]]; then t="$(session_mtime "${name}")"; [[ -n "${t}" && "${t}" -ge "${since}" ]] && state=ran; fi
    [[ "${state}" != busy && "${state}" != ran && "${state}" != waiting* && ${SECONDS} -lt ${deadline} ]]; do nap 1; done
  case "${state}" in
    busy|ran) ;;
    waiting*) die "${pre} its builder is waiting on $(waiting_for "${state}"), so no /goal was sent; answer it (herdr agent read ${name})${post}" ;;
    *) die "${pre} its session did not ${want} within $((PROMPT_TIMEOUT_MS / 1000))s (${state}), so no /goal was sent${post}" ;;
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

# sign_rule — with sign_commits = true, the rule every builder's and conductor's brief gives; nothing
# when it is off. swarm.sh's own commits and merges (board-pr, a stacked start) pass -S then too.
sign_rule() {
  # shellcheck disable=SC2154 # assigned in another file
  [[ "${CFG_sign_commits}" != true ]] || echo "Sign every commit and merge with -S. If signing fails, stop and report that you are blocked; never commit unsigned."
}

# The brief every story builder gets. The story file is the task; these are the rules.
story_brief() {
  local slug="$1" src="$2" base="$3" story_ref cleanup rel epic check rules trailers tree
  story_ref="$(story_path "${slug}" "${src}")"
  # The builder's worktree, cut from the base, which src's own checkout need not match; src before one exists.
  tree="$(worktree_for "${src}" "${slug}")"; [[ -d "${tree}" ]] || tree="${src}"
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
credentials. Open the PR against \`${base}\`. Before you push, for each function, command-line flag
or error message the diff changes, re-read its header comment, error text and every README, doc, command
or skill line that names it, and fix each one that no longer matches. Run \`$(codex_review_cmd "${base}" "${slug}")\` before
committing; fix real findings, decline nits with a reason, converge on one clean pass, and record the
loop in the PR body. $(codex_rule) $(review_tests_rule "${tree}") If \`gh pr view --json mergeable\` says
CONFLICTING, merge origin/${base} into your branch, resolve it (keep both sides of any list), re-run
the tests and push: a conflicted PR runs no checks and waits forever. $(wait_pr_rule "on exit 1 fix the red check; on a conflict, do as above. When it exits 2 with \`the PR's head is <X>, not <sha>\`, the PR's branch is past your checkout (a merge GitHub made, or a push that did not land): pull it (\`git pull --ff-only origin story/${slug}\`), merge origin/${base} in if it asks, push, and wait again on the new HEAD." "say so in your reply" "\"\$(git rev-parse HEAD)\"") $(mutation_rule) Record it
in the PR body. $(load_rule "${slug}") $(reply_sentence)
EOF
  check=""; [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || printf '%s\n' "Before you open the PR, also run the epic's check from the worktree root, and make it pass: \`${check}\`"
  trailers="$(config_trailers)"
  [[ -z "${trailers}" ]] || printf '%s\n%s\n' "End every commit message with these trailers, one per line:" "${trailers}"
  sign_rule
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
  local slug="$1" strict="${2:-}" story="${BOARD}/stories/$1.md" kind repo src role wt branch prompt base epic goal="" parents names since
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
  since="$(date +%s)"   # before the brief: send_goal counts a turn that ran since as having taken it
  start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}" "${slug}" "${names}"
  # story_role has checked attempts: is a whole number. The build is attempt attempts + 1.
  [[ "${role}" != escalate ]] || record_event escalate "${slug}" "ok (attempt $(( $(get_fm "${story}" attempts) + 1 )))"
  # Once the brief is taken up: mid-turn the goal sets at once and costs one extra short turn; after a
  # short first turn that already ended, it starts a turn of its own.
  [[ -z "${goal}" ]] || send_goal "${slug}" "${prompt%.md}.goal.md" brief "${since}"
}

# review_agent <slug> <PR URL> — start review-<slug> on a story's PR in the story's worktree and tab,
# with role review and review_brief, and return at once: the conductor waits on it with `swarm.sh
# wait review-<slug>`, which returns once the agent has written its findings file. It reviews the
# PR's head, and only when the worktree is at it with nothing uncommitted; the file's head: line
# names that commit. Refused, starting nothing and touching no file, when
# the board has a story named review-<slug> (its builder would hold the same agent name), or when
# review-<slug> cannot start (still working). Its earlier findings file goes once the agent has
# started (kept aside until then, and left aside when the start is unclear: review_start_failed), so
# the conductor reads only this head's. Once started, the head goes in .swarm/reviews/<slug>.head,
# which review_on_head reads. Its later rounds run in the same session, through review_next.
review_agent() {
  local slug="$1" pr="$2" story="${BOARD}/stories/$1.md" src wt base prompt out epic head moved errf err round
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "review-agent: bad slug '${slug}' (swarm.sh review-agent <slug> <PR URL>)"
  [[ "${pr}" =~ ^https://[^[:space:]]+/pull/[0-9]+$ ]] || die "review-agent: '${pr}' is not a PR URL (swarm.sh review-agent <slug> <PR URL>)"
  [[ -f "${story}" ]] || die "no story ${story}"
  [[ ! -f "${BOARD}/stories/review-${slug}.md" ]] \
    || die "review-agent: the board has a story named review-${slug}, whose builder's agent name would be the same; nothing was started"
  [[ -n "$(story_items "${story}" 'Done when')" ]] || die "${slug}: ${story} has no **Done when** with an item under it"
  review_at_head "${slug}" "${pr}"; src="${REVIEW_SRC}"; wt="${REVIEW_WT}"; head="${REVIEW_HEAD}"
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
  round="$(review_round "${slug}")"
  review_brief "${slug}" "${pr}" "${base}" "${out}" "${head}" "${round}" > "${prompt}"
  # The story's tab: its epic's, or a one-off's own.
  epic="$(fm "${story}" epic)"
  # The last review's file is moved aside before the brief goes (a quick agent's new file must not be
  # the one removed), and dropped once the agent has started. A .prev an earlier unclear start left,
  # with no findings file since, stays: it is the last real review. The head on record is written
  # again only for an agent this start leaves running. start_agent's stderr goes out as it comes; a
  # copy tells an unclear start from a no-send. A failing tee drains the rest, so the start's own
  # status decides.
  errf="$(mktemp)" || die "review-agent: mktemp failed; nothing was started"
  rm -f "${out%.md}.head"; moved=""
  if [[ -f "${out}" ]]; then mv "${out}" "${out}.prev"; moved=yes; fi
  if { start_agent "${epic:-${slug}}" "review-${slug}" "${wt}" review "${prompt}" 2>&1 1>&3 \
      | { tee "${errf}" >&2 || cat >/dev/null; }; } 3>&1; then
    rm -f "${out}.prev" "${errf}"
  else
    err="$(cat "${errf}")"; rm -f "${errf}"
    review_start_failed "${slug}" "${moved}" "${err}"
  fi
  echo "${head}" > "${out%.md}.head"
}

# review_round <slug> — the review round a story's PR is on: one more than the findings rounds of its
# build since the story's last build start (its `story` event), counted as the ladder counts them: a
# findings tell that is ok or that herdr sent (findings_told), and a findings step-up (escalate's
# `ok (findings-N: ...)`), whose brief carried the findings in place of a tell, and, which the ladder does
# not count, a wording recheck refused with a full round due (review_rounds). A step-up or a
# restarted builder (escalate, agent) keeps the same PR, so neither starts the count again.
review_round() {
  review_rounds "$1" | cut -d' ' -f1
}

# review_rounds <slug> — "<round> <started>": review_round's round, and the round the newest review start
# since the story's last build start began (an ok review-agent or review-agent:next line, each on the round
# review_round gave then), or 0 with none. A review-agent:recheck refused with a full round due counts as
# the findings round its wording nudge was not, once per round started (none counted since that start), so
# the brief's --next after it runs.
review_rounds() {
  awk -F'\t' -v s="$1" '$3 != s { next } $2 == "story" && $5 ~ /^ok/ { n = 0; at = 0 }
    ($2 == "tell" || $2 == "tell:findings") && ($5 == "ok" || $5 ~ /herdr sent it the brief/) { n++ }
    $2 == "escalate" && $5 ~ /^ok \(findings-[0-9]+:/ { n++ }
    $2 == "review-agent:recheck" && $5 ~ /a full round is due/ && at == n + 1 { n++ }
    ($2 == "review-agent" || $2 == "review-agent:next") && $5 ~ /^ok/ { at = n + 1 }
    END { print n + 1, at + 0 }' "${EVENTS_LOG}" 2>/dev/null || echo "1 0"
}

# review_words <slug> [next|recheck] — for review-agent's refusals (its start, --next's or --recheck's):
# the command, what the refusal left undone and how to try again, in REVIEW_CMD, REVIEW_UNDONE and REVIEW_AGAIN.
review_words() {
  case "${2:-}" in
    next) REVIEW_CMD="review-agent --next"; REVIEW_UNDONE="no round was started"; REVIEW_AGAIN="run swarm.sh review-agent --next $1 <PR URL> again" ;;
    recheck) REVIEW_CMD="review-agent --recheck"; REVIEW_UNDONE="nothing was written"
             REVIEW_AGAIN="run swarm.sh review-agent --recheck $1 <PR URL> <old head> <file:line>... again" ;;
    *) REVIEW_CMD=review-agent; REVIEW_UNDONE="nothing was started"; REVIEW_AGAIN="start the review again" ;;
  esac
}

# review_at_head <slug> <PR URL> [next|recheck] — the story's repo, worktree and PR head, in REVIEW_SRC,
# REVIEW_WT and REVIEW_HEAD, once the worktree is at the PR's head with nothing uncommitted; dies
# otherwise, as review-agent, or as review-agent --next or --recheck (review_words). Not for $(...): main
# logs its die's message, which no_review_events reads.
review_at_head() {
  local at
  review_words "$1" "${3:-}"
  REVIEW_SRC="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo)")" || die "$1: ${REVIEW_SRC}"
  REVIEW_WT="$(worktree_for "${REVIEW_SRC}" "$1")"
  [[ -d "${REVIEW_WT}" ]] || die "$1: no worktree at ${REVIEW_WT}: review-agent reviews a story built here"
  REVIEW_HEAD="$(gh pr view "$2" --json headRefOid --jq .headRefOid 2>/dev/null)" || REVIEW_HEAD=""
  [[ "${REVIEW_HEAD}" =~ ^[0-9a-f]{40}$ ]] || die "${REVIEW_CMD}: could not read $2's head (gh pr view --json headRefOid)"
  at="$(git -C "${REVIEW_WT}" rev-parse HEAD)"
  [[ "${at}" == "${REVIEW_HEAD}" ]] \
    || die "${REVIEW_CMD}: $1's worktree is at ${at}, not the PR's head ${REVIEW_HEAD}; ${REVIEW_UNDONE}: wait for its builder, then ${REVIEW_AGAIN}"
  # Uncommitted work would be reviewed with the head (codex's story prompt includes it).
  [[ -z "$(git -C "${REVIEW_WT}" status --porcelain)" ]] \
    || die "${REVIEW_CMD}: $1's worktree has uncommitted changes, so it is not the PR's head ${REVIEW_HEAD}; ${REVIEW_UNDONE}: wait for its builder to commit and push, then ${REVIEW_AGAIN}"
}

# review_own_pane <slug> — dies, as review-agent --recheck, unless this pane is review-<slug>'s, checked as
# review_next checks it for --next: no story named review-<slug> on the board, herdr answers and lists a
# review-<slug> this project started, and HERDR_PANE_ID is its pane.
review_own_pane() {
  local pane
  review_words "$1" recheck
  [[ ! -f "${BOARD}/stories/review-$1.md" ]] \
    || die "${REVIEW_CMD}: the board has a story named review-$1, whose builder's agent name would be the same; ${REVIEW_UNDONE}"
  pane="$(agent_field "$(agent_name "review-$1")" pane_id)"
  if [[ -z "${pane}" ]]; then
    # agent_field is empty too when herdr's list fails: that is no answer, not no review agent.
    herdr agent list >/dev/null 2>&1 \
      || die "${REVIEW_CMD}: herdr could not list its agents, so whether review-$1 runs is unknown; ${REVIEW_UNDONE}: ${REVIEW_AGAIN} once herdr answers"
    die "${REVIEW_CMD}: herdr lists no review-$1 this project started, so ${REVIEW_UNDONE}: start one with swarm.sh review-agent $1 <PR URL>"
  fi
  [[ "${HERDR_PANE_ID:-}" == "${pane}" ]] \
    || die "${REVIEW_CMD}: only review-$1, in its pane ${pane}, runs its wording recheck, not pane ${HERDR_PANE_ID:-(none: HERDR_PANE_ID is not set)}; ${REVIEW_UNDONE}"
}

# review_next <slug> <PR URL> — review-agent --next: the next review round of review-<slug>, run from its
# own pane, in the same session; it starts no agent. Once the worktree is at the PR's head with nothing
# uncommitted (review_at_head), the last findings file goes aside to <slug>.md.prev (so the conductor's
# wait ends only on this round's), the head goes in .swarm/reviews/<slug>.head, and it prints the round
# (review_round) and that round's instruction (review_round_line). Refused, touching no file under
# .swarm/reviews, from any other pane, when the board has a story named review-<slug>, when herdr lists no
# review-<slug> this project started (or cannot list its agents), when the round would be 1 (no findings
# round since the build started: a findings tell or step-up, or a --recheck refused with a full round due),
# when this build has no ok review-agent start (review-<slug> is an earlier build's), or while that round
# has started already (review_rounds): no findings round since, so its review would be lost.
# review_agent's refusal while review-<slug> is live stays for every other caller.
review_next() {
  local slug="$1" pr="$2" out pane round rounds
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "review-agent --next: bad slug '${slug}' (swarm.sh review-agent --next <slug> <PR URL>)"
  [[ "${pr}" =~ ^https://[^[:space:]]+/pull/[0-9]+$ ]] || die "review-agent --next: '${pr}' is not a PR URL (swarm.sh review-agent --next <slug> <PR URL>)"
  [[ -f "${BOARD}/stories/${slug}.md" ]] || die "no story ${BOARD}/stories/${slug}.md"
  [[ ! -f "${BOARD}/stories/review-${slug}.md" ]] \
    || die "review-agent --next: the board has a story named review-${slug}, whose builder's agent name would be the same; no round was started"
  pane="$(agent_field "$(agent_name "review-${slug}")" pane_id)"
  if [[ -z "${pane}" ]]; then
    # agent_field is empty too when herdr's list fails: that is no answer, not no review agent.
    herdr agent list >/dev/null 2>&1 \
      || die "review-agent --next: herdr could not list its agents, so whether review-${slug} runs is unknown; no round was started: run swarm.sh review-agent --next ${slug} <PR URL> again once herdr answers, and start no new review agent"
    die "review-agent --next: herdr lists no review-${slug} this project started, so no round was started: start one with swarm.sh review-agent ${slug} <PR URL>"
  fi
  [[ "${HERDR_PANE_ID:-}" == "${pane}" ]] \
    || die "review-agent --next: only review-${slug}, in its pane ${pane}, runs its next round, not pane ${HERDR_PANE_ID:-(none: HERDR_PANE_ID is not set)}; no round was started"
  rounds="$(review_rounds "${slug}")"; round="${rounds% *}"
  # Round 1 is always a plain review-agent start: with no findings sent since the build started (a new
  # build's story event resets the count), there is no next round.
  [[ "${round}" -gt 1 ]] \
    || die "review-agent --next: no findings went to ${slug}'s builder since its build started, so there is no next round (round 1 is a plain review-agent start); no round was started"
  # A review-<slug> left from an earlier build has no start in this one: its next round is not this build's.
  [[ "${rounds#* }" -gt 0 ]] \
    || die "review-agent --next: no review-agent start of ${slug} is on record since its build started, so review-${slug} is from an earlier build; no round was started: close it, then start one with swarm.sh review-agent ${slug} <PR URL>"
  [[ "${rounds#* }" -lt "${round}" ]] \
    || die "review-agent --next: round ${round} of ${slug} has started already, and no findings went to its builder since; no round was started: send this round's findings with swarm.sh tell ${slug} findings <file> first, then run it again"
  review_at_head "${slug}" "${pr}" next
  out="${PROJECT_DIR}/.swarm/reviews/${slug}.md"
  if [[ -f "${out}" ]]; then mv "${out}" "${out}.prev"; fi
  echo "${REVIEW_HEAD}" > "${out%.md}.head"
  # The brief pins the head of the round it started: this round's head replaces it there.
  echo "Review round ${round} of story ${slug}: review ${pr} at its new head ${REVIEW_HEAD}, as your brief says, but with ${REVIEW_HEAD} in place of every head the brief names: when the review is done, check that \`git rev-parse HEAD\` still prints ${REVIEW_HEAD}; write this round's findings to fix to ${out%.md}.round.md, and ${out} only on a pass or a stop, each afresh with \`head: ${REVIEW_HEAD}\` as its first line (or, if the worktree moved, \`head moved: <what changed>\` under it)."
  review_round_line "${round}" "${pr}"
}

RECHECK_CI_SECONDS=60   # how long --recheck's read of the new head's CI may take (SWARM_RECHECK_CI_SECONDS)

# review_recheck <slug> <PR URL> <old head> <file:line>... — review-agent --recheck: the wording recheck,
# run by review-<slug> from its own pane (review_own_pane) once its builder has pushed a wording fix. <old head>
# is the head review-<slug> last reviewed, as .swarm/reviews/<slug>.head records it, with that round's
# findings to fix written to <slug>.round.md (review_pass on it), and each file:line a point its ## Findings
# name, every finding there naming one (recheck_named), its line as at <old head>. With the worktree at the PR's new head
# (review_at_head), it passes when `git diff <old head>..<new head>` rewrites each named line and nothing
# else (recheck_hunks) and the new head is green (ci_gate head, within RECHECK_CI_SECONDS). A pass writes
# the new head's findings file, a pass whose ## Handled by the review agent carries the round file's, any
# file there before kept as <slug>.md.prev, and .head; main logs
# it as review-agent:recheck <slug> ok, which counts no round (review_rounds). A refusal writes nothing
# under .swarm/reviews. One on the old head, its findings, the diff or a red head names --next, a full
# round, and counts as that round (review_rounds); one on CI still running or unread says to run --recheck
# again, and the rest say what to fix first.
review_recheck() {
  local slug="$1" pr="$2" old="$3" usage="swarm.sh review-agent --recheck <slug> <PR URL> <old head> <file:line>..."
  local out round handled repo why rc point secs="${SWARM_RECHECK_CI_SECONDS:-${RECHECK_CI_SECONDS}}" full="a full round is due: swarm.sh review-agent --next $1 $2"
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "review-agent --recheck: bad slug '${slug}' (${usage})"
  [[ "${pr}" =~ ^https://[^/[:space:]]+/([^/[:space:]]+/[^/[:space:]]+)/pull/[0-9]+$ ]] \
    || die "review-agent --recheck: '${pr}' is not a PR URL (${usage})"
  repo="${BASH_REMATCH[1]}"
  [[ "${old}" =~ ^[0-9a-f]{40}$ ]] || die "review-agent --recheck: '${old}' is not a full commit SHA (${usage})"
  shift 3
  [[ $# -gt 0 ]] || die "review-agent --recheck: no file:line point named (${usage})"
  for point in "$@"; do
    [[ "${point}" =~ ^[^[:space:]]+:[0-9]+$ ]] || die "review-agent --recheck: '${point}' is not a file:line point (${usage})"
  done
  [[ -f "${BOARD}/stories/${slug}.md" ]] || die "no story ${BOARD}/stories/${slug}.md"
  review_own_pane "${slug}"
  review_at_head "${slug}" "${pr}" recheck
  out="${PROJECT_DIR}/.swarm/reviews/${slug}.md"; round="${out%.md}.round.md"
  [[ "$(cat "${out%.md}.head" 2>/dev/null)" == "${old}" ]] \
    || die "review-agent --recheck: ${old} is not the head review-${slug} last reviewed (${out%.md}.head); nothing was written: ${full}"
  # .head is written as a round starts: the round on the old head must have written its findings to fix, or
  # there is no review to recheck.
  review_pass "${slug}" "${old}" "${round}" \
    || die "review-agent --recheck: ${round} holds no finished review of ${old} (its head: line and a ## Findings section); nothing was written: ${full}"
  why="$(recheck_named "${round}" "${REVIEW_WT}" "$@")" || die "review-agent --recheck: ${why}; nothing was written: ${full}"
  why="$(recheck_hunks "${REVIEW_WT}" "${old}" "${REVIEW_HEAD}" "$@")" \
    || die "review-agent --recheck: ${old:0:7}..${REVIEW_HEAD:0:7} ${why}; nothing was written: ${full}"
  rc=0; why="$(within "${secs}" python3 "${SWARM_HOME}/bin/lib/ci_gate.py" head "${repo}" "${REVIEW_HEAD}" </dev/null 2>&1)" || rc=$?
  case "${rc}" in
    0) ;;
    1) die "review-agent --recheck: the head ${REVIEW_HEAD:0:7} is not green: ${why}; nothing was written: ${full}" ;;
    2) die "review-agent --recheck: CI on ${REVIEW_HEAD:0:7} has not finished: ${why}; nothing was written: wait for it (swarm.sh wait-pr ${pr}), then ${REVIEW_AGAIN}" ;;
    *) die "review-agent --recheck: could not read CI on ${REVIEW_HEAD:0:7}: ${why:-no answer within ${secs}s}; nothing was written: ${REVIEW_AGAIN}" ;;
  esac
  # The round's declined and out-of-scope points, which the agent logged and rebutted before its nudge.
  handled="$(awk '/^## / { in_h = ($0 ~ /^## Handled by the review agent/); next }
    in_h && /[^[:space:]]/ && tolower($0) !~ /^[-* ]*none\.?$/' "${round}")"
  if [[ -n "${handled}" ]]; then handled="Carried from the round on ${old:0:7}, each logged and rebutted then:"$'\n'"${handled}"
  else handled="None."; fi
  if [[ -f "${out}" ]]; then mv "${out}" "${out}.prev"; fi
  printf '%s\n' "head: ${REVIEW_HEAD}" "" "## Findings" "" \
    "None: the wording recheck passed. ${old:0:7}..${REVIEW_HEAD:0:7} changes only the lines the last findings named, and the head is green." \
    "" "## Handled by the review agent" "" "${handled}" > "${out}"
  echo "${REVIEW_HEAD}" > "${out%.md}.head"
  echo "wording recheck passed: ${out} holds the findings for ${REVIEW_HEAD}"
}

# recheck_named <findings file> <worktree> <file:line>... — nothing when the file's ## Findings section names
# each point, every finding there (each non-blank line) cites one, and every file:line a finding cites is
# a given point; else why not, failing. A citation is a whole path (<worktree>/ dropped from it) and a
# line, with any lines listed or ranged after it (3-8, 3,8, 3/8, 3–8) or a bare :<line> later in the
# finding, which no single point matches; anything that reads as one (a time, say) refuses too, which only
# costs a full round. A pass's own findings cite no point, so no recheck follows one.
recheck_named() {
  awk -v pts="${*:3}" -v wt="$2/" -v f="$1" '
    BEGIN { n = split(pts, w, " "); for (i = 1; i <= n; i++) given[w[i]] = i }
    /^## / { in_f = ($0 ~ /^## Findings/); next }
    !in_f || $0 !~ /[^[:space:]]/ { next }
    {
      s = $0; while ((k = index(s, wt))) s = substr(s, 1, k - 1) substr(s, k + length(wt))
      hit = 0; rest = ""
      while (match(s, /[A-Za-z0-9_.\/-]+:[0-9]+(-[0-9]+)?/)) {
        c = substr(s, RSTART, RLENGTH); rest = rest substr(s, 1, RSTART - 1) " "; s = substr(s, RSTART + RLENGTH)
        # Lines listed or ranged right after it (3,8  3/8  3–8) are cited too, and no single point names them.
        t = s; more = ""
        if (match(t, /^[,\/][0-9]+/)) more = substr(t, 1, RLENGTH)
        else if (sub(/^(–|—)/, "", t) && match(t, /^[0-9]+/)) more = substr(s, 1, length(s) - length(t) + RLENGTH)
        s = substr(s, length(more) + 1)
        if (c in given) seen[given[c]] = hit = 1
        if ((!(c in given) || more != "") && miss == "") { miss = c more; missed = $0 }
      }
      # A bare :<line> left over (doc.md:3 (and :8)) cites a line of some file no point names.
      if (match(rest s, /:[0-9]+/) && miss == "") { miss = substr(rest s, RSTART, RLENGTH); missed = $0 }
      if (!hit && left == "") left = $0
    }
    END {
      for (i = 1; i <= n; i++) if (!seen[i]) { print w[i] " is no point the ## Findings of " f " name"; exit 1 }
      if (miss != "") { print "the ## Findings of " f " cite " miss ", which is no point given, so a pass would drop it: " missed; exit 1 }
      if (left != "") { print "the ## Findings of " f " hold a finding that names no point given, which a pass would drop: " left; exit 1 }
    }' "$1"
}

# recheck_hunks <worktree> <old> <new> <file:line>... — nothing when the diff from <old> to <new> rewrites
# each named line, as at <old>, and nothing else: every line a hunk removes or rewrites is named, and no hunk
# adds more lines than it removes; else why not, failing. A file it adds, deletes, renames, changes the
# mode of or that is binary has no named line, and an empty diff fails too.
recheck_hunks() {
  local wt="$1" old="$2" new="$3"; shift 3
  git -C "${wt}" -c core.quotePath=false diff -U0 --no-color --no-ext-diff --no-textconv --no-renames \
      --src-prefix=a/ --dst-prefix=b/ "${old}" "${new}" 2>/dev/null \
    | awk -v pts="$*" '
      function bad(m) { print m; failed = 1; exit 1 }
      # A file header past: the file must be named, with only line changes (---/+++, then hunks).
      function header_done() { if (st == "head" && !(file in want)) bad("changes " (file == "" ? name : file) ", which no file:line point names") }
      BEGIN {
        n = split(pts, w, " ")
        for (i = 1; i <= n; i++) { f = w[i]; sub(/:[0-9]+$/, "", f); l[i] = f ":" (substr(w[i], length(f) + 2) + 0); want[f] = want[f] " " (substr(w[i], length(f) + 2) + 0) " " }
      }
      st == "body" && /^[-+]/ { if (--rem == 0) st = "hunks"; next }
      /^\\/ && st != "head" { next }   # \ No newline at end of file, after the line it marks
      /^diff --git / { header_done(); st = "head"; file = ""; name = substr($0, 12); files++; next }
      st == "head" && /^--- / { if ($0 != "--- /dev/null") file = substr($0, 7); next }
      st == "head" && /^\+\+\+ / { if ($0 != "+++ /dev/null" && file != substr($0, 7)) file = ""; next }
      st == "head" && /^index / { next }
      /^@@ / {
        header_done(); st = "hunks"
        o = $2; sub(/^-/, "", o); c = split(o, a, ","); lo = a[1] + 0; cnt = (c > 1 ? a[2] + 0 : 1)
        nw = $3; sub(/^\+/, "", nw); c = split(nw, a, ","); nc = (c > 1 ? a[2] + 0 : 1); rem = cnt + nc
        # A wording fix rewrites lines; more lines than it removes is new text no one reviewed.
        if (nc > cnt) bad("adds " (nc - cnt) " line(s) to " file " at line " lo ", more than it removes")
        # Every old line the hunk changes must be named; git joins adjacent edits into one hunk.
        for (k = lo; k < lo + cnt; k++) { if (!index(want[file], " " k " ")) bad("changes " file " at line " k ", which no file:line point names"); changed[file ":" k] = 1 }
        if (rem > 0) st = "body"
        next
      }
      st == "head" { bad("changes more than lines of " name " (" $0 ")") }
      { bad("has a line recheck cannot read: " $0) }
      END {
        if (failed) exit 1
        header_done(); if (!files) { print "changes nothing"; exit 1 }
        for (i = 1; i <= n; i++) if (!(l[i] in changed)) { print "does not change " w[i] ", a named point"; exit 1 }
      }'
}

# review_round_line <round> <PR URL> — what review round <round> runs, for review_brief and review_next:
# codex and, when the PR changes code, /code-review on round 1; codex alone after it.
review_round_line() {
  if [[ "$1" == 1 ]]; then
    echo "This is review round 1 of the story. When the PR
changes code (not only docs, board files or a dependency bump), state the touches and Done when
above, then run \`/code-review $2\`."
  else
    echo "This is review round $1 of the story: run codex alone, not \`/code-review\`, which runs on round 1 only."
  fi
}

# review_start_failed <slug> <moved> <err> — after review_agent's start of review-<slug> failed with
# <err> (its stderr), the last findings file moved aside to <slug>.md.prev when <moved> is non-empty.
# Returns, so review_agent records the head, only when the start was unclear and the agent runs: <err>
# says the brief may have gone out (deliver_prompt's sent or unread tries) and read_state calls it busy
# or waiting (herdr's working or blocked for codex), or idle with its session log showing the brief
# (a review agent sits idle while its codex runs) and no expired login after it. The file stays
# aside. Dies otherwise. When the
# brief may have reached an agent that is not running, or herdr cannot list its agents, the file stays
# aside and the message says what to do. In any other case (herdr surely sent nothing, no pane, a
# session that is gone or that herdr has no status for), it closes the pane and puts back the file
# this start moved, unless a findings file is there again (a quick agent's, which stays).
review_start_failed() {
  local name f="${PROJECT_DIR}/.swarm/reviews/$1.md" state=none pane unclear="" kept="" note="" back=""
  name="$(agent_name "review-$1")"; pane="$(agent_field "${name}" pane_id)"
  # agent_field is empty too when herdr's list fails: that is no answer, not no pane.
  if [[ -n "${pane}" ]]; then state="$(read_state "${name}")"
  elif ! herdr agent list >/dev/null 2>&1; then state=unlisted; fi
  [[ ! -f "${f}.prev" ]] || kept="; the last review is kept aside in ${f}.prev"
  case "$3" in
    *"may or may not have the brief"*|*"herdr sent it the brief"*|*"could not be read"*) unclear=yes ;;
  esac
  # Idle is no sign of a brief that was not taken: its session log has the brief when it was. An
  # agent that took it and then stopped on an expired login is idle too, and runs nothing.
  if [[ "${unclear}:${state}" == yes:idle ]] \
    && session_took "${name}" 0 "$(awk 'NF { print; exit }' "${PROJECT_DIR}/.swarm/briefs/review-$1.md" 2>/dev/null)" logonly; then
    if login_expired "${name}"; then state=auth; else state=running; fi
  fi
  case "${unclear}:${state}" in
    yes:unlisted)
      die "review-agent: review-$1's start was unclear and herdr could not list its agents, so its state is unknown${kept}; no head is on record. Once herdr answers, look at it (herdr agent read ${name}); to review again, close it and run swarm.sh review-agent $1 <PR URL>" ;;
    yes:none|yes:gone|yes:herdr:) ;;   # nothing runs to have the brief
    yes:busy|yes:running|yes:waiting*|yes:herdr:working|yes:herdr:blocked)
      echo "review-agent: review-$1's start was unclear, but the agent is running${kept}: wait for it with swarm.sh wait review-$1"
      return 0 ;;
    yes:auth)
      die "review-agent: review-$1 took its brief and stopped on an expired login${kept}; no head is on record. Only your /login clears it; then close it (herdr pane close ${pane}) and run swarm.sh review-agent $1 <PR URL>" ;;
    yes:*)
      die "review-agent: review-$1's start was unclear: it reads ${state} and may have its brief${kept}; no head is on record. Look at it (herdr agent read ${name}); to review again, close it (herdr pane close ${pane}) and run swarm.sh review-agent $1 <PR URL>" ;;
  esac
  if [[ -n "${pane}" ]]; then
    note=" (its pane ${pane} is closed)"
    herdr pane close "${pane}" >/dev/null 2>&1 || note=" (its pane ${pane} could not be closed: close it by hand)"
  fi
  if [[ -n "$2" && ! -f "${f}" ]]; then mv "${f}.prev" "${f}"; back="; ${f} is put back"; fi
  [[ ! -f "${f}.prev" ]] || back+="; the last review is kept aside in ${f}.prev"
  die "review-agent: review-$1 did not start${note}${back}"
}

# BASE_MERGED_LINKS: how many base-merged heads review_pass follows back from a head to a reviewed one.
BASE_MERGED_LINKS=10

# review_pass <slug> <sha> [file] [links] — true when <slug>'s findings file (or <file>, as review_recheck's
# round file) is a pass on <sha>: its head: line is <sha>, and it has a ## Findings section and no head
# moved: line (review_rule's test). A head that merge made by merging the base into the PR (events.tsv's
# `base-merged <sha> from <head>`, base_merged_from) passes when the head it was made from does, since
# its only new content is the base's; <links> counts the heads followed so far, BASE_MERGED_LINKS at most.
review_pass() {
  local f="${3:-${PROJECT_DIR}/.swarm/reviews/$1.md}" from
  if grep -qx "head: $2" "${f}" 2>/dev/null && grep -q '^## Findings' "${f}" && ! grep -q '^head moved:' "${f}"; then return 0; fi
  (( ${4:-0} < BASE_MERGED_LINKS )) || return 1
  from="$(base_merged_from "$1" "$2")"
  [[ -n "${from}" && "${from}" != "$2" ]] && review_pass "$1" "${from}" "${3:-}" $(( ${4:-0} + 1 ))
}

# review_on_head <slug> <sha> — true while <sha> has a review agent's review, for watch and next
# (queued_line): its findings file for <sha> is a pass, <sha> is a head merge made from a head that
# passed (review_pass), or, with no file for <sha> yet, a review agent
# started on it (.swarm/reviews/<slug>.head) and review-<slug> is still open in a pane this project
# opened. One that crashed, was closed or tidied, or that herdr cannot list, is no review.
review_on_head() {
  local f="${PROJECT_DIR}/.swarm/reviews/$1.md"
  if grep -qx "head: $2" "${f}" 2>/dev/null; then review_pass "$1" "$2"; return; fi
  # A head merge made from a reviewed head by merging the base in (review_pass) is reviewed too.
  if review_pass "$1" "$2"; then return 0; fi
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
- An exception to the scope rule above: a comment, doc or error-text line the changed code no longer matches is a finding at its file:line, even when that file is outside the touches.
- For each wait, external call (gh, herdr, curl) and status the diff adds, name its timeout, its failure, what clears it and what a second concurrent run does; a missing answer is a finding.
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

# review_handoff <slug> <PR URL> <findings file> <head> <swarm.sh> — the review brief's pass step. A round
# with nothing to fix writes its review file first: the conductor's wait ends on it, and once the PR
# merges, the merge's reconcile, run from this pane, retires the agent and removes its worktree, so a
# file written after would never come. Then it puts the story in review pinned to <head>, the head it
# reviewed (swarm.sh review --head, which refuses a moved head), and, under merge = agent or when
# swarm.sh grants names merge for the PR, merges that head, pinned as pinned_merge_rule pins a
# conductor's (swarm.sh merge --head); otherwise the review is the handoff to the user. A moved head
# turns the file into a head moved: one, and whoever started the agent starts a new one on it.
# <swarm.sh> is the brief's swarm.sh with SWARM_PROJECT, as every call in it.
review_handoff() {
  local merge next
  merge="run \`$5 merge --head $4 $2\` in the background (Bash run_in_background) and wait for it to exit. When the base gained code since $4's CI ran, it first has GitHub merge the base into the PR's branch and waits up to $((MERGE_CI_SECONDS / 60)) minutes for that new head's CI, ${MERGE_BASE_ROUNDS} rounds at most; after the merge it waits up to $((MERGE_CI_SECONDS / 60)) minutes for CI on the base, then reconciles. It merges only that head, or the head it made by merging the base in, by the literal PR number with \`--match-head-commit\`, once every check on it has passed."
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge}" == agent ]]; then
    next="Then merge the PR: ${merge}"
  else
    next="Then run \`$5 grants $2\`. When a line it prints is \`merge\`, the agreed HLD over the PR grants merge: ${merge} When it exits 0 with no \`merge\` line, the review is the handoff: the PR waits on the user's merge, so merge nothing. When it fails, run it once more; a second failure hands the PR to the user too, and your reply says grants failed."
  fi
  cat <<EOF
A round with nothing to fix is a pass, of $4, the head on ${3}'s \`head:\` line. Write the review to
${3} first: the conductor's wait ends on it, and once the PR merges, the merge's reconcile retires you
and removes this worktree, so a file written after would never come. Then hand the PR on: run
\`$5 review $1 --head $4 $2\`, which puts the story in review. ${next}
When review or merge refuses because the PR's head is no longer $4 (a push since your review), that
head has had no review, and you do not review it in this session. Write ${3} again with the Write tool,
holding two lines, \`head: $4\` and
\`head moved: <the head review or merge named>\`, then stop: whoever started you (the conductor, or the
lead for a kept story) starts a new review agent on the new head. When it was merge that refused,
review had already put the story in review: your reply's first line says \`$1 is in review on
<the new head>, which nobody reviewed\`.
When merge prints \`base merged: <PR URL> is now ...\`, GitHub merged the base into the PR's branch:
that head needs no new review, and merge goes on to wait for its CI and merge it, so leave it running
until it exits. When it prints \`already merged:\`, the PR merged elsewhere while it waited,
and merge reconciled the board. A \`base merged, <cause>:\` refusal is one of the other refusals below.
When merge refuses with \`held:\`, the user merges the PR: the review is the handoff.
Once the last of these commands has exited, run nothing more in this worktree (a merge removes it):
reply with ${3}, what the last command printed, and \`codex skipped: <why>\` when codex was, then
stop. On any other refusal or failure
(a story held until its parents merge, a story with a PR you did not review, a red base),
reply the same way: the conductor or the lead acts on it.
EOF
}

# review_brief <slug> <PR URL> <base> <findings file> <head> <round> — a review agent's brief: it never
# edits the code, the story's touches and Done when, the green step first (wait-pr, then triage of the PR's check-run notes
# and code-scanning alerts as green_rule's, each real one, red check or conflict sent to the builder as a
# nudge, and wait-pr again on the head it pushes; bounded at two nudges and two red heads, past which,
# or when the builder stops pushing, it writes a findings file with the red check as its one finding,
# sent to the builder as any finding), codex-review with the slug, /code-review on round 1 when the PR
# changes code, and the project's rules. After each review it fixes or declines each finding, logs each
# with log-finding --round (finding_rule), and writes the absolute <findings file> (the agent's cwd is
# the worktree) under its head: line, with the declined and out-of-scope points apart: on a pass, just
# before review_handoff hands the PR on (review --head, then merge --head where it may) and ends it,
# since that file is read as a finished review of its head the moment it exists (review_pass,
# wait review-<slug>); with findings to fix, to the .round.md beside it, which it tells the builder (tell
# counts the round, and may step the build up or hold it) after waiting for it, then waits for its push,
# runs the green step on the new head, then review-agent --next (review_next) and the round that prints,
# in the same session. Findings that are all wording go as a nudge instead, no round, and the head it pushes
# is checked with review-agent --recheck (review_recheck), whose pass writes <findings file>, then review_handoff; its
# refusal naming --next counts the round (review_rounds), and --next runs the full round. A stop before a
# pass (a wait that ends other than idle, a refused tell, no fix pushed) writes <findings file> with head:
# and stopped: lines and no ## Findings: no pass.
# Its swarm.sh calls name the project (SWARM_PROJECT), as codex_review_cmd's.
review_brief() {
  local story="${BOARD}/stories/$1.md" rules cr sw nudge="${4%.md}.nudge.md" round="${4%.md}.round.md" repo ladder="" stepped="" agent
  cr="$(review_round_line "$6" "$2")"
  sw="$(printf 'SWARM_PROJECT=%q %q' "${PROJECT_DIR}" "${SWARM_HOME}/bin/swarm.sh")"
  # findings takes the story's repo by name; a story with no repo: is in the project's own.
  repo="$(fm "${story}" repo)"; [[ -n "${repo}" ]] || repo="$(basename "${PROJECT_DIR}")"
  agent="$(agent_name "$1")"   # the builder's herdr name, which herdr agent read takes
  # Only with the ladder on does a wait-pr from this pane step the build up (review_red_scan), or a
  # wait --stall step up a stalled build.
  [[ -z "${CFG_escalate_ladder:-}" ]] || ladder="
  When it also prints \`stepped up: $1\`, the build's red heads handed it to the next model on the
  escalation ladder, and the head it waited on is gone: send no nudge; write ${4} with the Write tool
  holding two lines, \`head: <the head wait-pr waited on>\` and \`head moved: <that stepped up: line>\`,
  then stop. When it prints \`step-up failed: $1\` instead, the builder was closed and no new one runs,
  so no nudge can reach it: write ${4} with the Write tool holding \`head: <the head wait-pr waited
  on>\`, a \`## Findings\` heading with that \`step-up failed:\` line as its one item, and a
  \`## Handled by the review agent\` heading with \`none\`, then stop."
  [[ -z "${CFG_escalate_ladder:-}" ]] || stepped=" When it prints \`stepped up: $1\`, the stalled build went to
the next model on the escalation ladder, and when it prints \`stepping up: $1\`, another step-up or a
restart of it is running: in both cases, wait on it the same way. A build stepped up after this
round's findings were told has none of them in its handover brief (that brief pastes ${4}, which
holds no findings to fix): once the new builder is idle, send it ${round} as a nudge, which is no
round (write ${nudge} as below holding what ${round} holds, then \`${sw} tell $1 nudge ${nudge}\`),
and wait on it again."
  cat <<EOF
Review $2, the PR of story $1, at its head $5, in this worktree. Never edit, commit or push here:
the builder changes the code. Merge only as the pass step below says. The files you write are
${4}, ${round} and, to nudge the builder, ${nudge}.

The story touches: $(fm "${story}" touches)

Its **Done when:**
$(story_items "${story}" 'Done when')

Judge the PR against these touches and items. ${SCOPE_RULE}
$(review_stack_note "$1" "$3")
To wait for the builder, run \`${sw} wait --stall $1\` in the background and wait for it to exit,
never a loop of your own. It prints \`idle\`, or \`done\` for a builder with no Claude session, once
the builder's turn has ended.${stepped} When it ends any other way (\`stalled:\`, \`stuck:\`, a timeout
or an error), stop with what it printed, as below: the builder is then the conductor's or the lead's
to act on.

A tell to a busy builder is queued, not refused: it prints \`queued: ${agent} (busy); delivered when
its turn ends, so do not tell it again\` and exits 0, and its queue's check sends it once the
builder's turn has ended (a findings tell counts its round then, not before). After a queued tell,
wait for the builder as above, then for the delivery, with this one command in the background
(Bash run_in_background), waiting for it to exit, never a loop of your own:
\`for i in \$(seq 90); do ls ${PROJECT_DIR}/.swarm/tells/${agent}.findings* 2>/dev/null | grep -qv -e '\.sent\$' -e undelivered || break; [ -e ${PROJECT_DIR}/.swarm/tells/${agent}.findings.undelivered.md ] && break; sleep 10; done; ls ${PROJECT_DIR}/.swarm/tells/\`
(for a queued nudge, \`nudge\` in place of \`findings\`, in both places). The tell is
${PROJECT_DIR}/.swarm/tells/${agent}.<kind> while queued, then a \`.sending.<token>\` and a
\`.claimed.<token>\` mark of that name while on its way (the check looks once a minute). The
command ends once only its \`.sent\` mark is left, which means the builder has it; when
\`${agent}.<kind>.undelivered.md\` appears, which means the check dropped the tell, which
\`wait --lead\` tells the lead: stop with that, as below; or after 15 minutes with the marks still
there: a check that has not looked for 10 minutes counts as stopped, and \`wait --lead\` then hands
its tells to the lead: stop with \`stopped: the queued <kind> tell was not delivered in 15 minutes\`,
as below. Once only \`.sent\` is left, see what the
delivery did before you wait on the builder, since a delivery of findings that holds the story for
the lead or steps the build up leaves \`.sent\` too: when ${story} now has a \`held_for:\` line, stop
with \`held for the lead: <that line>\`, as below; when ${PROJECT_DIR}/.swarm/events.tsv gained an
\`escalate\` line for $1 since your tell whose outcome starts \`ok (findings-\`, the delivery stepped
the build up with the findings in its handover brief: tell it nothing, and wait on the new builder
as above. Otherwise wait for the builder once more, as above: that turn is the one that has it.

${4} is read as a finished review of the head on its \`head:\` line the moment it exists, so write it
only when a round passes, or when you stop. To stop before a round passes, write ${4} with the Write
tool holding two lines, \`head: <the PR's head as you last saw it>\` and \`stopped: <why: what tell or
wait printed, or that no fix was pushed>\`, reply with the same, and stop: with no \`## Findings\`
heading it is no pass, and the conductor takes the story from there.

Before you review, wait for the PR's checks to go green. Run \`${sw} wait-pr $2\` in the
background and wait for it to exit, never a loop of your own; it prints the head it waits on first.
- Exit 0: the head counts green only once you have triaged what \`${sw} findings ${repo} ${2##*/}\`
  prints: the notes on every check run, whatever its conclusion, and the PR's open code-scanning
  alerts. Nudge the builder with each real one. Rebut the rest with a reason in the PR
  (\`gh pr comment $2 --body '<the reason>'\`), unless a comment there already rebuts it: scanners
  often flag a name, not a value. Never dismiss an alert.
- Exit 1 (a red check) or a conflict: nudge the builder, naming the red check or the base to merge in.${ladder}
- Its other exit 2s print why. On a timeout or no check runs, read the checks once (\`gh pr checks $2\`):
  nudge the builder when a workflow never started, else run wait-pr again. On a gh error, run it again.
To nudge the builder, first remove any earlier nudge file (\`rm -f ${nudge}\`: the Write tool refuses
to overwrite a file this session has not read), then write ${nudge} with the Write tool, naming what
to fix, and run \`${sw} tell $1 nudge ${nudge}\` (never findings, which count as a review round).
When tell prints \`queued:\`, the nudge goes when the builder's turn ends: do as above. After each
nudge, wait for the builder the same way, then wait for green again on the head it pushed. A wait on a
head the builder has just pushed is \`${sw} wait-pr --head <that head, from git rev-parse HEAD> $2\`:
right after a push GitHub can still report the old head, which the plain wait-pr would call green.
That HEAD is this worktree's commit, pushed or not: when wait-pr exits 2 with \`the PR's head is
<X>, not <sha>\`, the PR never got the head you named (a push that did not land): never wait on
<X> instead; nudge the builder naming both shas, so it pushes again, then wait for it and run
wait-pr --head again on its HEAD, which a push alone does not change. The green step runs once per
round: on the first head, then on the head the builder pushes after each findings tell. Each run is
bounded: at most two nudges, and at most two heads that wait-pr calls red. Write the not-green
file, which ends the green step, when the builder goes idle without a commit (\`git rev-parse HEAD\`
is still the head you waited on) after a nudge that asked for a fix (after one that asked for a
push, run wait-pr --head on that HEAD first, as above, and only a second miss ends the step), when
wait-pr ends the same way twice, when the second red head would need a nudge, or when the head
after your second nudge is not green. The not-green file is ${round}, written
with the Write tool after \`rm -f ${round}\`: \`head: <the head wait-pr waited on last>\`, then a
\`## Findings\` heading with one line for the builder, \`wait-pr: not green: <the red check, the
conflict, or what wait-pr printed last>\`, then a \`## Handled by the review agent\` heading with
\`none\`. Its one finding is to fix, from ci: send it to the builder as findings, as below, and log it as any finding
to fix. Once a head is green and
triaged with nothing to nudge, review it as below when it is $5. When the builder pushed past $5
before any findings or wording nudge went to it, write ${4} with the Write tool holding two lines,
\`head: $5\` and \`head moved: <the green head>\`, then stop; once findings went to it, run
\`review-agent --next\` on the green head, and once a wording nudge did, \`review-agent --recheck\`
first, as below.

Run \`$(codex_review_cmd "$3" "$1")\` in the background (Bash run_in_background) and wait for it to
finish: it can run for ${CFG_codex_minutes} minutes, longer than a foreground Bash call may last.
Wait for it to exit, and act on what it prints last: a usage limit it prints early may be followed by
a fallback's review. If it ends on codex's usage limit or on "codex skipped: ...", do not run it
again: you report \`codex skipped: usage limit\` or \`codex skipped: timed out\`. When it prints
\`reviewed by fallback <model>: codex usage limit\`, a fallback agent reviewed in codex's place: report
its findings as codex's, under that line, and log each with \`--reviewer fallback\`, as below. ${cr}

$(review_checklist "${story}")

When the review is done, check that \`git rev-parse HEAD\` still prints $5 and \`git status --porcelain\`
prints nothing. If not, the worktree moved under you: write ${4} with the Write tool holding two
lines, \`head: $5\` and \`head moved: <what changed>\`, then stop.

Otherwise, fix or decline each finding. One that is real and inside the story is to fix: the builder
fixes it, never you. Decline the rest, each with its reason: nit for a nit, an edge case or a
low-value point, wrong for a mistaken one, out-of-scope for a point only a change to a file outside
the touches can fix, and, for a point declined in an earlier round, the reason it was declined with
then. Rebut the declined ones in the PR, in one comment:
\`gh pr comment $2 --body '<each declined finding and its reason>'\`. Log each declined one now, as
below; log each one to fix only once the builder has pushed, as below. A finding's round is $6 on
this first review, then the round \`review-agent --next\` prints.

Then write the review with the Write tool, in one go.
Its first line is \`head: $5\`; when codex was skipped, its second is \`codex skipped: <why>\`.
Under a \`## Findings\` heading,
one line per finding to fix: its reviewer (codex, fallback or code-review), file:line, and the finding; with
none, say so. Under a \`## Handled by the review agent\` heading, the same for each finding you
declined, with its reason, and for each point a reviewer raised that only a change to a file
outside the touches can fix, marked out of scope; with none, say so. Use no \`## Declined\` or
\`## Out of scope\` heading: the conductor's rules log and rebut what they find under those, and
you have done both already.

$(review_handoff "$1" "$2" "$4" "$5" "${sw}")

With findings to fix, write it to ${round} instead, after \`rm -f ${round}\` (the Write tool refuses
to overwrite a file this session has not read), and never to ${4}, which would end the round as a
finished review. When every finding to fix is wording (a comment, doc or error-text line that
misstates the code) and each cites the one file:line it rewrites, send them as a wording nudge in
place of the findings tell below: a nudge is no round, so the ladder does not move. Write ${nudge} as
above holding what ${round} holds, wait for the builder as above, run \`${sw} tell $1 nudge ${nudge}\`,
and from there go on as below for a findings tell, a \`queued:\` one included. Otherwise wait
before you tell, so the findings go at once and count their round now:
wait for the builder as above, then run \`${sw} tell $1 findings ${round}\`. When tell prints
\`queued:\` (the builder took a turn meanwhile), do as above, and tell it nothing more. When tell
says another step-up or a restart of it is running, wait the same way, then tell it again. When tell says the
build went to the next model (a step-up), that model has the findings in its handover brief: never
tell them again, and wait on it as below. When tell fails but says the findings count as delivered
or as a round, herdr sent them: never tell them as findings again. When it also says to read the
builder's pane, read it (\`herdr agent read ${agent} --source recent-unwrapped\`), and if they never
arrived, send them as a nudge, which is no round: write ${nudge} as above holding what ${round}
holds, and run \`${sw} tell $1 nudge ${nudge}\`. Then wait on it as below. When tell says $1 is held
for the lead, that its step-up failed partway, or refuses for any other reason, stop with what it
printed, as above. Once the findings are sent, wait for the builder as above. Then read the
builder's reply (\`herdr agent read ${agent} --source recent-unwrapped\`). When \`git rev-parse HEAD\`
is still the head you reviewed (no fix was committed), and the builder declined each finding you
sent with a reason you accept, the round passes on that head, as one with nothing to fix does: log
each as declined, rebut them in the PR as above, in one comment with each finding and the builder's
reason, and do the pass step above on that head, its review listing them under
\`## Handled by the review agent\` with those reasons. When HEAD is still the same otherwise, stop with
\`no fix pushed: <the builder's reply, in one line>\`, as above. When HEAD moved, run the green step
above on it, with wait-pr --head as there: its first line names the head it waits on, so once it
has run on that head the PR has it (a push that did not land ends it with \`the PR's head is <X>,
not <sha>\`, as there). Log nothing before then: a fix in this worktree is not on the PR until the
push lands. With the PR at that head, read the new diff (\`git diff <the head you reviewed>
HEAD\`) and log each finding you sent: as fixed when the diff fixes it, and as declined, with the
reason that fits, when the builder declined it with a reason you accept; rebut those in the PR as
above, in one comment with each finding and the builder's reason. One it did neither to, or
declined with a reason you do not accept, is not logged; the next round raises it again if it still
holds. Once that head is green and triaged with nothing to nudge, after a wording nudge run
\`${sw} review-agent --recheck $1 $2 <the head you reviewed> <each file:line ${round} cites>\`, each
path relative to the repo root (never under the worktree's path), which counts no round. When it prints \`wording recheck passed\`, it has written ${4}, a pass of the head it
names: do the pass step above from \`Then hand the PR on\`, with that head in place of $5. When it
says CI has not finished or to run it again, do that. When it refuses naming \`review-agent --next\`
(the diff changes more than those lines, say), a full round is due, and the refusal counts the
round the nudge did not. Then, or after a findings tell, run
\`${sw} review-agent --next $1 $2\` and do the round it prints (codex alone from round 2):
review, check the head, triage, and send its findings as above, until a round passes or you stop.

$(finding_rule)
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
  local story="$1" src="$2" wt="$3" slug p pr first="${4%% *}" why merged sign=()
  # shellcheck disable=SC2154 # assigned in another file
  [[ "${CFG_sign_commits}" != true ]] || sign=(-S)
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
    if why="$(git -C "${wt}" merge -q --no-edit ${sign[@]+"${sign[@]}"} "origin/story/${p}" 2>&1)"; then merged+=" origin/story/${p}"; continue; fi
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
# repo's checkout (Makefile, Makefile:lint). (repo, file, fn) are compared: fn by its first word, and a
# file-only entry overlaps only the same file-only entry. An empty status prints as -. Its own function, not inside a <(...):
# bash 3.2 misreads the parentheses in a heredoc there.
touches_rows() {
  python3 "${SWARM_HOME}/bin/lib/touches_rows.py" "${BOARD}/stories" "$1" "${PROJECT_DIR}" "${REPOS_DIR}" "${BOARD_STATE_DIR}/stories"
}

# board_pr_merge_rule — who lands a conductor's board PR: the conductor with merge = agent, the user
# with merge = human. A story-scope edit, a hold or a finish PR gets no codex-review under either.
board_pr_merge_rule() {
  if [[ "${CFG_merge}" == human ]]; then
    echo "Run no \`swarm.sh codex-review\` on it. With merge = human you cannot land that PR: list it in your report for the user."
  else
    echo "Run no \`swarm.sh codex-review\` on it: land it with \`swarm.sh merge --board <url>\` once its checks are green."
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
of another epic (in review, or with its builder open) touches the same part (by its first word) of a
file, or both name the bare file. On a refusal
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
\`--backlog\`, or the review agent's \`wait-pr\` from its own pane). That command then prints
\`stepped up: <slug>\` (wait prints it in place of \`stalled:\`): the next model carries on in the
same worktree and branch. Do not close, retry or tell that story for it; wait on its builder again.
A review file whose \`head moved:\` line names \`stepped up:\` is the review agent reporting one
from its \`wait-pr\`: the PR's head has not moved, so do not start the review again; wait on the
builder, then start the review on the head it pushes. A \`step-up failed: <slug>\` line means the
step-up stopped after closing the builder. Leave that story alone: \`wait --lead\` tells the lead,
so it does not go in your report. A review file whose one finding is that line is the same case.
EOF
  local rules sign; sign="$(sign_rule)"
  [[ -z "${sign}" ]] || printf '\n%s\n' "${sign}"
  rules="$(project_rules)"
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
never dismiss an alert. A PR's head is the <sha> \`swarm.sh watch\` printed for it (\`checks finished on
<sha>\`), never your checkout's HEAD: you work from the main checkout, on the base. For a head watch has not printed,
pass the full SHA a \`base merged, <cause>:\` refusal names after \`wait-pr --head\`, or, after a builder's push, the sha the builder reported, else \`git -C ../<repo>-wt/<slug> rev-parse HEAD\` in its worktree;
never a fresh \`gh pr view\` read, which right after a push can still name the old head, as an unpinned wait-pr can. $(wait_pr_rule "on exit 1 or a conflict, send the story's builder a nudge with \`${SWARM_HOME}/bin/swarm.sh tell <slug> nudge <file>\` (never findings, which count as a review round) naming the red check, or the base to merge in. When it exits 2 with \`the PR's head is <X>, not <sha>\`, the PR never got the head you named: never wait on <X> instead; send the builder a nudge naming both shas, so it pushes again and reports its HEAD, or report it to the lead." "report it to the lead" "<sha>")
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
whose pane has not changed that long with no background task running; a \`tell\` to a busy session
is queued and delivered only when its turn ends, so do not tell it: read the pane and list it for the lead. With goal on, wait never tells a
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
# edits to different parts of one file, so only the same part (by its first word) or two bare files hold a
# story back; a bare file does not clash with a part of it.
clash_rule() {
  cat <<EOF
Two stories clash only when their \`touches\` name the same file in the same repo and the same first
word of a part (\`file:part\`), or when both name the bare file (no \`:part\`). A bare file does not clash with a part of it.
A part's first word skips a leading \`§\`, \`#\`, "the", "a" or "an".
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

# WORKSPACE_SEP: between the project's label and the rest of a workspace label (`app · <epic>`).
WORKSPACE_SEP=" · "

# herdr_workspaces — herdr's workspaces, one "<id>\t<label>\t<cwd>\t<others>" line each. A workspace has no cwd
# of its own in herdr, so it is the cwd of its first pane in herdr's pane list: the conductor's, a
# review agent's, a lead agent's or the pane at PROJECT_DIR next_pane keeps ahead of a lead agent's
# outside the project, or, while new, the placeholder's epic_workspace made it with. A pane in a story
# worktree of this project's repo (<project>-wt/<slug>) counts as the project's, so a workspace whose
# conductor pane has gone is still its own; one in any other story worktree (<repo>-wt/<slug>, whose
# project it does not say) is skipped. With no pane left, empty. <others> is 1 when any pane not
# skipped is in a dir other than the project's (another project's), else 0. Fails when herdr gives no
# workspace list, or no pane list while it has a workspace.
herdr_workspaces() {
  local ws panes='{"result":{"panes":[]}}'
  ws="$(herdr workspace list 2>/dev/null)" || return 1
  if [[ "$(json "len(d['result']['workspaces'])" <<< "${ws}")" != 0 ]]; then
    panes="$(herdr pane list 2>/dev/null)" || return 1
  fi
  SWARM_WS="${ws}" SWARM_PANES="${panes}" python3 -I -c '
import json, os, sys
cwd, others = {}, set()
for p in json.loads(os.environ["SWARM_PANES"])["result"]["panes"]:
    d = (p.get("cwd") or "").rstrip("/"); parent = os.path.dirname(d)
    if parent == sys.argv[1] + "-wt":
        d = sys.argv[1]
    elif d != sys.argv[1] and parent.endswith("-wt"):
        continue
    if d:
        w = p.get("workspace_id") or p.get("pane_id", "").split(":")[0]
        cwd.setdefault(w, d)
        if d != sys.argv[1]:
            others.add(w)
for w in json.loads(os.environ["SWARM_WS"])["result"]["workspaces"]:
    i = w["workspace_id"]
    print("%s\t%s\t%s\t%d" % (i, w.get("label") or "", cwd.get(i, ""), i in others))' "${PROJECT_DIR}"
}

# project_label [<herdr_workspaces lines>] — this project's part of its workspace labels: its dir's
# name, with -<path_hash> after it only when herdr has a workspace labelled `<that name> · ...` whose
# cwd is another dir (/a/app's is app, then /b/app's is app-<hash>).
project_label() {
  local base list="${1-}"
  base="$(basename "${PROJECT_DIR}")"
  [[ $# -gt 0 ]] || list="$(herdr_workspaces)" || return 1
  if P="${base}${WORKSPACE_SEP}" D="${PROJECT_DIR}" awk -F'\t' 'index($2, ENVIRON["P"]) == 1 && $3 != "" && $3 != ENVIRON["D"] { f = 1 } END { exit !f }' <<< "${list}"; then
    printf '%s-%s' "${base}" "$(path_hash)"
  else
    printf '%s' "${base}"
  fi
}

# epic_workspace <label> — "<id>\t<workspace label>\t<placeholder tab>": this project's herdr workspace
# for <label>, created as `<project_label> · <label>` if there is none. A conductor's <label> is its
# epic's parent: (so the child epics of a split one share a workspace), else the epic's own slug, or
# backlog. Found by label and cwd (herdr_workspaces), so never another project's: under either form of
# project_label, since /b/app's turns back to app once /a/app has no workspace, or under the bare
# <label> an older swarm.sh gave it, and then only with no other project's pane in it (an older
# swarm.sh put every project's backlog, and each project's same-named epic, in one). A new workspace's placeholder tab is closed once the caller has
# added its own; a found one has none. Refused, with the reason printed and 1 returned, when herdr
# gives no list or no new workspace.
epic_workspace() {
  local label="$1" list base own want ws tab
  list="$(herdr_workspaces)" || { echo "conduct: herdr gave no workspace or pane list, so the workspace for ${label} could not be found"; return 1; }
  base="$(basename "${PROJECT_DIR}")"
  own="$(project_label "${list}")${WORKSPACE_SEP}${label}"
  for want in "${own}" "${base}${WORKSPACE_SEP}${label}" "${base}-$(path_hash)${WORKSPACE_SEP}${label}" "${label}"; do
    ws="$(W="${want}" D="${PROJECT_DIR}" B="${label}" awk -F'\t' '$2 == ENVIRON["W"] && $3 == ENVIRON["D"] && ($2 != ENVIRON["B"] || $4 == 0) { print $1; exit }' <<< "${list}")"
    [[ -z "${ws}" ]] || { printf '%s\t%s\t\n' "${ws}" "${want}"; return; }
  done
  read -r ws tab <<< "$(herdr workspace create --label "${own}" --cwd "${PROJECT_DIR}" --no-focus \
    | json "d['result']['workspace']['workspace_id']+' '+d['result']['tab']['tab_id']")"
  [[ -n "${ws}" ]] || { echo "conduct: herdr could not create the workspace ${own}"; return 1; }
  printf '%s\t%s\t%s\n' "${ws}" "${own}" "${tab}"
}

# path_hash — 6 hex characters of a checksum of the project's path, which tell two dirs of one name apart.
path_hash() {
  local crc
  crc="$(printf '%s' "${PROJECT_DIR}" | cksum)"
  printf '%06x' $((${crc%% *} % 16777216))
}

# conductor_name <epic>|backlog — a conductor's agent name. herdr's names span projects and every
# project has a backlog, so the backlog conductor's is conduct-backlog-<the dir's name, cut to 9>-<6 hex
# of the project's path>: 32 characters at most, distinct for two dirs of one name, and never ending
# like a retired agent's (-done).
conductor_name() {
  local n
  [[ "$1" == backlog ]] || { agent_name "conduct-$1"; return; }
  # Sanitized before the cut: a multibyte character can become several dashes.
  n="$(agent_name "conduct-backlog-$(basename "${PROJECT_DIR}")")"
  printf '%s-%s' "${n:0:25}" "$(path_hash)"
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
# stories with no epic: conduct-backlog-<project dir> (conductor_name), in its project's backlog workspace
# (epic_workspace), needing no epic file.
# Under merge = agent with no allow rule for swarm.sh merge, it dies with merge_rule_stop's line first.
start_conductor() {
  local epic="$1" epic_file="${BOARD}/epics/$1.md" label prompt ws wslabel placeholder out inbox err names tab name report why
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
    # Its workspace would be the lead's own agents' (next_pane's lead_agents_workspace).
    [[ "${label}" != "${LEAD_AGENTS_LABEL}" ]] \
      || die "conduct: ${epic} would take the lead's agents' workspace, <project>${WORKSPACE_SEP}${LEAD_AGENTS_LABEL}; rename the epic, or its parent:"
  fi
  # Before the brief, the old report's removal and the workspace, so a refusal changes nothing.
  if why="$(merge_rule_stop)"; then die "${why}"; fi
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
  out="$(epic_workspace "${label}")" || die "${out}"
  IFS=$'\t' read -r ws wslabel placeholder <<< "${out}"
  # On exit, not after start_agent: a conductor that fails to start dies, and left the tab empty.
  # shellcheck disable=SC2064 # expand now; the tab id is herdr's, [a-zA-Z0-9:]
  [[ -z "${placeholder}" ]] || trap "herdr tab close '${placeholder}' >/dev/null 2>&1 || true" EXIT
  # The backlog's tab takes the conductor's name too: an older swarm.sh put every project's backlog tab
  # in one workspace named backlog, which a project still reuses, and close shuts every tab with its label there.
  tab="${epic}"; [[ "${epic}" != backlog ]] || tab="${name}"
  # In that workspace, even when the tab's record still lists a live pane in another (a retired
  # conductor's, in a workspace an older swarm.sh shared): next_pane then opens <tab>-2.
  PANE_WORKSPACE="${ws}" start_agent "${tab}" "${name}" "${PROJECT_DIR}" conduct "${prompt}" conductor "${names}"
  # Notes left for an earlier run are not this one's. Only once it started: a refused second conduct
  # must leave a live conductor's notes; this one reads its inbox only after its first wait.
  inbox="$(conductor_inbox "${name}")"; rm -f "${inbox}.md" "${inbox}.reading.md" "${inbox}.woke" "${inbox}.later" "${inbox}.upgrade"   # a stale .lock note_lock clears itself
  echo "workspace ${wslabel} (${ws})"
  # An epic being built is active, or status and next list it as a later epic waiting on the user.
  # In BOARD_STATE_DIR, as unblock's is (set_fm), never the epic file; any other status is left as it is.
  # The conductor is already running, so a state file that cannot be written is reported, never
  # fatal: a failed conduct would invite a second conductor. set_fm dies, so it runs in a subshell.
  [[ -f "${epic_file}" && "$(get_fm "${epic_file}" status)" == later ]] || return 0
  if err="$(set_fm "${epic_file}" status active 2>&1)"; then
    echo "epic ${epic}: status later -> active (in .swarm/board-state)"
  else
    echo "epic ${epic}: could not write its state in ${BOARD_STATE_DIR}/epics, so it is still later; set status: active by hand, with agreed: <today> in the same edit (${err#swarm: })" >&2
  fi
}
