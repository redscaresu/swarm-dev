---
kind: docs
status: blocked
blocked_by: [log-finding-reasons-and-reviewers, blocked-by-from-depends-on]
epic: leaner-faster-swarm
depends_on: [log-finding-reasons-and-reviewers, blocked-by-from-depends-on]
touches: [commands/plan-epic.md, docs/method.md:§ Scoping an epic, tests/plan_epic_test.sh]
---

# plan-epic scales with the epic and plans short chains: small epics by the lead with one codex pass; otherwise chains at most 3 deep, the critic beside the skeptics, one survey for a one-repo epic, review fixes folded in, and plan findings logged

Waits on log-finding-reasons-and-reviewers (record_finding takes the reviewers skeptic and critic, and `--declined <reason>`) and on blocked-by-from-depends-on (unblock and waiting_on_user read depends_on alone, so stories need no blocked_by). Changes to commands/plan-epic.md: a new first step says that an epic of at most 3 stories with no `risk: high`, judged from its **Done when**, is planned by the lead alone: the lead writes the stories, runs one `swarm.sh codex-review` pass over them, and reports as below. A larger or riskier epic gets the full run. Step 2 (decompose) and the skeptic bullet say a depends_on chain is at most 3 stories deep, and that a story's scope opens with what it needs from each depends_on: the file or the function. depends_on itself stays a list of slugs. The survey step starts one survey agent when the epic names one repo, and three otherwise. The critic joins step 3's parallel list, and the steps are renumbered. Step 2's risk clause gives `risk: high` only to real-cloud, teardown, credentials and safety paths (no longer hygiene), and the report says which stories carry it and why. The report prints stories ÷ longest chain. On approval, review fixes are folded into each story's scope and Done when, never put in a separate block of their own. The front matter is `status: ready`, or `blocked` with depends_on and no blocked_by (:86). Drop '(a board-only PR needs no version bump)'. Once the board PR is open, log every skeptic, codex and critic finding against it: `swarm.sh log-finding --reviewer skeptic|codex|critic <kind> <board PR URL> '…'` when the plan adopted the finding, and with `--declined <reason>` when it did not. The kind list drops verify (:52). docs/method.md § Scoping an epic says the same. A new tests/plan_epic_test.sh pins each rule with a grep. Run humanizer:humanizer over the commands/ and docs/ prose you change and over the PR description, and say so in the PR. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when.

**Done when:**
- tests/plan_epic_test.sh checks commands/plan-epic.md for: the small-epic path (at most 3 stories, no risk: high, the lead with one codex pass); `at most 3` for chains; a depends_on rule that names the file or function; `longest chain` in the report; the critic inside step 3; a risk clause naming real-cloud, teardown, credentials and safety, without `hygiene`; one survey for a one-repo epic; review fixes `folded into` the scope; and `log-finding --reviewer skeptic` and `critic` against the board PR, with `--declined <reason>`.
- The same test checks that commands/plan-epic.md has no `blocked_by`, no `verify` and no `needs no version bump`.
- Each check fails on the file as main holds it today. The PR shows this by running the test against `git show origin/main:commands/plan-epic.md`.
- docs/method.md § Scoping an epic has no `three surveys` and no `then a critic`.
- Every tests/*_test.sh passes.
