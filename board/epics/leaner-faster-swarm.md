---
status: active
---

# A leaner swarm that runs more builders at once and measures what it does

The lead and a Fable review (2026-10-16) went through infrafactory's logs since 2026-10-09: $1195 at list prices, 131 builds, 487 PR findings. Builds averaged 1 to 2.5 running at once per epic (maximum 4), held there mostly by long `depends_on` chains. On the one fully logged day, 65% of PR findings were declined, many as out of the story's scope. 55% of story PRs needed main merged in. Several process decisions had no data behind them. The user approved this epic on 2026-10-16. infrafactory stays `merge = human`.

**Done when:**
- **Throughput.**
  - plan-epic's decompose and skeptic briefs say a `depends_on` chain is at most 3 stories, and that each `depends_on` names the file or function the story needs from the other.
  - The plan-epic report prints stories ÷ longest chain.
  - The next epic is planned while the current one's last wave is in review (method.md:22-23 relaxed), not only once it is done.
  - The critic runs in parallel with the skeptics and codex.
  - **Stacked builds.** A story whose `depends_on` stories all have open PRs, but not all merged, starts from their PR branch (or a merge of them) instead of waiting. When a parent's PR head moves, the conductor tells the child to merge it in. The child's PR targets main and is merged only after its parents. A test covers start, a parent update and merge order.
  - **A backlog conductor.** `swarm.sh conduct --backlog` runs ready stories with no epic the way a conductor runs an epic: build, review, and hand to the lead (merge = human) or merge (merge = agent). One-off stories stop landing on the lead.
  - **Planning scales with the epic.** An epic of at most 3 stories with no `risk: high` is planned by the lead with one codex pass. The full plan-epic (surveys, decompose, skeptics, codex, critic) is kept for larger or riskier epics.
  - **Parallel reviews.** A conductor starts one review agent per PR (codex plus /code-review) instead of reviewing PRs one after another, and triages what comes back. Four PRs that land together are reviewed at once.
- **Fewer review rounds.**
  - Every PR reviewer (the conductor's codex pass, /code-review, the lead's pass) is given the story's `touches` and **Done when**, and told that work outside them is not a finding.
  - plan-epic keeps `risk: high` for real cloud, teardown, credentials and safety paths, and says so.
- **Simpler stories and releases.**
  - plan-epic folds review fixes into a story's scope, with no "From review (binding; overrides)" block.
  - On a single-repo epic, plan-epic runs one survey.
  - Per-epic release stories are gone. The lead cuts a release from main when it has unreleased changes, and `bump_rule`, its brief rule and the AGENTS.md lines that exist only to serve release stories go with them.
  - `swarm.sh reconcile` pulls the main checkout whenever it is behind, not only when a review item merged (reconcile-always-pulls), so the lead never pulls by hand.
- **Data.**
  - `log-finding --reviewer escaped <original PR> <kind> "…"` records a defect a later fix found in merged work.
  - `log-finding --declined` takes a reason (out-of-scope, nit, wrong).
  - Plan-review findings (skeptic, codex, critic) are logged against the board PR with their reviewer and whether the plan adopted them.
  - `outcomes` (or a new report) gives each story's start → PR and PR → merge times and its count of main-merge commits.
  - `cost` includes sessions in the project dir that are not in agents.tsv (the lead).
  - **Throughput.** A report (`swarm.sh flow --since`) gives, per epic and per project, builders running at once (mean and max over time), stories ÷ longest chain, time each PR waited for review (PR opened → first review started), and how many builds started stacked. Each throughput change above sets its number beside the baseline from before this epic.
  - **Is it worth it.** `docs/features.tsv` lists each feature: when it landed, the metric it is meant to move, and that metric's baseline. A `swarm.sh features` report joins it with usage from events.tsv, agents.tsv and findings.tsv. A feature with no uses in 30 days, or with no metric, is listed for deletion.
  - **Lesson rules.** No new rules (decided 2026-10-14). The vacuous-test rule becomes a mechanical check: the conductor (or CI) greps the PR body for each new test's FAIL line and logs `rules-unchecked` when it is missing. The other six tagged rules in AGENTS.md:146-152 become one "decline these in review" note.
- **Simplify the framework.**
  - method.md is split into a guide of at most 150 lines plus a reference file.
  - Deleted: the `verify` kind and role, `pr_per = epic`, the `decisions` and `export` commands, and config keys no project sets (each checked against both projects' config first).
  - `blocked_by` is derived from `depends_on`, not written.
  - The escalation machinery is left as it is.
- **The dash.**
  - It shows a "running now" panel: each open agent, its time running, its last activity, its PR and CI state, and held stories.
  - "Needs you" lists only the next **You:** step.
  - A ready lead story says what it waits for.
  - The uncommitted-edits line names the files.
  - Repeated events collapse in "recent", and findings lines carry their PR number.
  - One dash can show both projects.
  - **The speedometer.** The dash's top line shows stories merged per day (7-day rolling) with two warning lights: items waiting on the lead or the user, with the oldest one's age, and escaped defects in the last 7 days.
  - A one-off builder shows its PR and what it waits on (review, the lead's merge, an IMPOSSIBLE reply), never a bare "idle".
  - `swarm.sh wait --lead` returns when the lead's queue gains an item (a held story, a green PR waiting for its merge, an escalation), so the lead is woken instead of finding them later. On 2026-10-16, three held stories waited 2 hours unnoticed.
- **README.** The last story updates README's text and diagrams to match everything above, through humanizer.

**Out of scope:** `merge = agent` for infrafactory (the user said no, 2026-10-16). Skipping the conductor's codex pass. Sonnet for builders (sonnet-share-on covers it). A pre-review docs-vs-code pass (measure the builders' rules-checked step first).

**Constraints:** bash 3.2. Every deletion is checked against infrafactory's and swarm-dev's config and board first. Stories follow the new rules: chains of at most 3, no override blocks.

**Your part:** none.

**Plan notes (scoping, 2026-10-16):**
- 26 stories (23 agent, 3 lead) ÷ longest chain 3 = 8.7. Line numbers are from 6b86465, main today; function names are the anchors.
- drop-old-switches is split by behaviour into drop-epic-prs, drop-verify and drop-unused-switches in wave 1, and finish-switch-removal in wave 2. A function has one owner per wave, and that owner removes every deleted switch's trace from it: drop-epic-prs also takes verify out of build_story, failed_build and nudge_reason, and the bump, signing and finished = mark out of story_brief; drop-unused-switches takes verify out of close_agent; backlog-conductor takes 'or verify' out of conduct_brief. A definition can go only once nothing reads it, and some readers sit in other owners' functions (CFG_sign_commits in story_brief and conduct_epic_mode; bump_rule in review_rule, story_brief and conduct_epic_mode), so finish-switch-removal deletes those definitions after the three merge. The pr_per and base_branches keys go there too: taking a key out of load_config makes every test config line naming it die (bin/swarm.sh:204), and those lines run through the pr_per = epic tests that drop-epic-prs deletes (tests/epic_test.sh:535-690).
- Release-story removal has no story of its own. Its code is the bump_rule calls in story_brief and review_rule, which drop-epic-prs owns, and bump_rule itself, which finish-switch-removal deletes. Its text (commands/hld.md:49, commands/plan-hld.md:53) goes with the release step in plan-during-review-and-release, and AGENTS.md's release paragraph with readme-and-agents. A story of its own would share story_brief, review_rule and the combined builder-and-conductor bump check (tests/epic_test.sh:279-282) with drop-epic-prs.
- dispatch has one owner per wave: flow-and-features in wave 1, scoped-parallel-reviews in wave 2. Five command changes need it (decisions and export out; features, flow, wait --lead and review-agent in), and a chain of 3 with the docs stories last leaves two slots. So flow-and-features carries every wave-1 command change, which makes it the plan's largest story, and moves the wait arm's body into wait_command, so wait-for-the-lead adds --lead in wave 2 without editing dispatch. dash --project, conduct --backlog, watch --backlog and merge --release go through arms that already pass their arguments on (bin/swarm.sh:5433, :5427, :5443, :5450), and READ_ONLY_COMMANDS changes in wave 1 only.
- The usage header is comment lines, not a function. Each story edits only its own command's lines, and no two stories in one wave edit lines with no unchanged line between them: git merge-file reports a conflict for changes on adjacent lines and none with one unchanged line between (checked on a scratch file). So the log-finding line (:17), next to the export line (:16) that flow-and-features deletes in wave 1, is updated by scoped-parallel-reviews in wave 2, and backlog-conductor leaves watch's line (:35, which never listed --epic either) beside findings' (:34).
- docs/method.md § Building and the rest of the file: each story edits only the paragraphs or bullets it names, no two stories in a wave name the same one, and new paragraphs go at named spots. A deleted switch still mentioned in a paragraph that another story owns stays until method-guide-and-reference removes it, with a grep over docs/, commands/, templates/ and skills/. docs/dash.md, commands/swarm.md and the shared test files are split the same way, by bullet, arm and section.
- backlog-conductor moves to wave 1, owning conduct_brief, stop_rule, watch_prs and conduct_merge_rule, so stacked-parent-updates can put stacked_rule in both conductor modes in wave 2. In v1 both were in wave 2, and neither could add it to the other's mode without a chain of 4. It leaves the pr_per branches of conduct_brief and stop_rule to finish-switch-removal, because drop-epic-prs' tests exercise them until it merges.
- next_step is drop-epic-prs' in wave 1 and plan-during-review-and-release's in wave 2, which carries both of this epic's changes to it (planning during review, the release step) and merge_pr's --release. merge_pr is free in wave 2 because stacked-start-and-merge-order keeps merge order in mark_review instead.
- Merge order lives in mark_review, not merge_pr: `swarm.sh merge` merges only an item in review (bin/swarm.sh:3501-3508), so a child that review holds as blocked can neither be merged by a conductor nor, under merge = human, be handed to the user. codex asked that children with open PRs be tracked through review. A stacked child never reaches review while a parent is open, so status's Stacked section covers ready and held (blocked) children, and a held child after its review is one of them. A held child's builder may be closed (a bare close of a blocked story counts nothing and keeps its build, failed_build :5185); the stacked rule starts a builder in its worktree with `swarm.sh agent` when it has to merge a parent's change.
- The release PR merges through `swarm.sh merge --release`, because merge refuses a PR that no story or epic lists (bin/swarm.sh:3507) and --board admits board files only. With merge = human, the user merges it.
- release-this-epic depends only on plan-during-review-and-release, and flow-after-the-epic on the wave-1 and wave-2 throughput stories, which keeps the chain at 3. Both run after the docs stories: `next` prints `release` only after its build, plan and escalated steps, and flow-after-the-epic starts after release-this-epic, as its scope says.
- codex asked for a controlled conductor exercise with four PRs. A conductor is a Claude session, so no test can run one. review_agent_test proves that review-agent returns at once and that four start before any finishes; the brief check proves the rule says not to wait; flow-after-the-epic checks the events of a real epic.
- READ_ONLY_COMMANDS leave no events.tsv line (bin/swarm.sh:5478-5483), so dash, status, flow, features and the other readers have `unlogged` uses in docs/features.tsv and are judged on their metric. wait --lead logs one `lead-woken` line per item it wakes the lead for, as wait logs its nudges, so it can be counted.
- findings-checks-fail-lines leaves rules_review_rule alone: a conductor logs a `rules-unchecked:` line through finding_rule's existing rule for a `swarm.sh findings` note (`--reviewer ci`), and the printed line names the command. Making rules_review_rule print always would change tests/epic_test.sh:285-286 and :628-629, which sit in drop-epic-prs' sections.
- Declined (skeptic-backlog-conductor, minor): the conduct usage line is bin/swarm.sh:6 (:5 is story, :7 is wait), so the plan's ':6' was right.
- Declined in part (skeptic-drop-old-switches): its suggestion to keep verify, the six switches and the bump in one story is superseded by the lead's split by behaviour.
- `log-finding --reviewer escaped <original PR> <kind>` puts the PR first, but log-finding takes `<kind> <pr-url>` (bin/swarm.sh:17, :816). log-finding-reasons-and-reviewers keeps that order.
- 'Config keys no project sets': repos_dir, stall_minutes, sonnet_share, escalate_after, builder_subagent_model and codex_minutes are unset in both configs too, but they default on (bin/swarm.sh:137, :147-153) or board/stories/sonnet-share-on.md sets them. Only the off-by-default switches go: sign_commits, review_bot, keep_panes, merge_admin, finished and base_branches, and pr_per with them.
- AGENTS.md:87 wants every user-visible PR to update README in the same PR. Here README.md and AGENTS.md have one story each (readme-and-agents), because a command table that a dozen stories edit would conflict in every wave.
- depends_on stays a list of slugs, because unblock treats any entry that is not a slug as a hand step that never clears (bin/swarm.sh:2902). The file or function each story needs is named in the first line of its scope.
- codex cannot be given the scope beside --base (docs/method.md:610-611), so codex-review-knows-the-story switches to a prompt with no --base; how well codex reviews that way is unproven. /code-review takes no context argument, so the review agent states the scope before calling it.
- 'The lead's pass' on one-off stories (commands/swarm.md's story arm) is replaced by the backlog conductor, whose reviews go through review_rule, so they are scoped too. next_step keeps printing `story <slug>` and `resume <slug>`, and the /swarm arms map them to `conduct --backlog`.
- No story bumps plugin.json. The release that carries this epic is release-this-epic's, cut by the lead through the new release step; v1's wave-1 bump is gone.
- 'AGENTS.md:146-152' is infrafactory's AGENTS.md (swarm-dev's has 98 lines and no tagged rules). Agents never edit it, and infrafactory is merge = human, so infrafactory-lesson-note is a lead story with a **You:** merge, although the epic says 'Your part: none'. The note keeps the six lesson tags so that `lessons` proposes none of them again. Builders' Rules-checked walk still lists those kinds; measuring that step first is the epic's own out-of-scope item.
- Planning that scales: the lead judges 'at most 3 stories' from the epic's Done when, before any decomposition exists. AGENTS.md's 'do not write a story plan yourself' gains the exception in readme-and-agents.
- features reads one project's logs, so a feature used only in infrafactory reads as unused in swarm-dev. flow-after-the-epic runs both before filing any deletion.
- Planning during review mainly helps merge = human (infrafactory). Under merge = agent the conductor stays up until its PRs merge, and status: review is short.
- Stacking on unreviewed PRs means a parent that is closed and rebuilt (clear_build deletes story/<p>) strands its child. stacked-parent-updates lists such a child as lost, and the conductor closes it as paused.
- Plan findings that the plan adopted are logged as fixed, so `lessons` counts them like PR findings.
- docs/assets/dash.gif (README.md:10) goes stale with the dash changes. Re-recording it needs a live terminal recording, so no story does it.
- review-yield-tuning (board/stories/review-yield-tuning.md) compares decline rates before and after one tuning change. scoped-parallel-reviews' out-of-scope rule moves the same rates, so its measured epic should start after this epic ships.
