---
kind: docs
status: blocked
blocked_by: [wire-escalate-role, fable-on-call-release]
epic: goal-for-builders
depends_on: [wire-escalate-role, fable-on-call-release]
touches: [commands/plan-epic.md (**4. Critic** paragraph), docs/method.md (§ Scoping an epic)]
---

# plan-epic and the method ask that a story's Done when names what the builder's session can show

One line in commands/plan-epic.md's **4. Critic** paragraph, and one in docs/method.md § Scoping an epic: a story's **Done when** names what the builder's own session can show (a test run, a command's output, a file). It never names something only the conductor or a merge can show, so a goal's judge can see it (HLD § A goal for builders). Nothing else changes. humanizer over both lines and the PR description.

**Done when:**
- `grep -n 'session can show' commands/plan-epic.md docs/method.md` finds one line in each; the method's sits between the § Scoping an epic heading and § Building.
- The diff touches only those two files, one added or rewritten line in each.
- humanizer ran over the two lines and the PR description, and the PR says so; every tests/*_test.sh and `claude plugin validate .` pass.
