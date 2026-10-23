---
status: active
depends_on: [safer-faster-swarm]
check: make test
---

# Every release starts with a retro, idle capacity is refilled by the framework, and rules a lead learns become rules for every project

**Problem (with evidence, 2026-10-22/23, the 0.26 cycle):**
- **The board ran dry and nothing noticed.** With two agent stories left in review, the swarm sat nearly idle. `next` printed `wait conduct-...`. The rule "when the board runs dry, find the next work" existed only in the lead's private memory (written 2026-10-18), and the lead broke it. The user had to ask "why are there so few things running".
- **Follow-ups pile up unread.** Conductors logged 99 findings as `declined out-of-scope` between v0.25.0 and the 0.26 release. Only the lead reading a backlog report by hand turned any of them into stories. Among them:
  - swarm.sh never reaps a builder's leftover load (#376)
  - `kill_tree` has a respawn race (#367)
  - a note fires only from `merge --board`, not from reconcile or unblock (#360)
  - `next` waits only on the first conductor (#365)
  - three test stubs went vacuous after #374
  - `touches` misses files on #336, #344, #346 and #347
- **Leftover load kept the machine busy.** In one day, builders left a 10-core stress container, three CPU spinners and four `yes` burners running for up to 3 hours. One builder sat stuck for 3 hours waiting on its own burners. #376 only added a brief rule.
- **Lead-only rules.** The user wants rules the lead learned to apply to any software swarm-dev builds, not to live in one lead's memory. The lead's memory holds about 40 feedback rules. Some are already in swarm-dev (red-merge guard, stall checks, user decisions not overridden, release docs gate). Others are generic and missing: refill when idle, fix the shared upstream cause first, a narrow sample is not a conclusion, verify against the thing itself, a silent fix looks like no fix.
- The user asked (2026-10-23) for a retro "just before the release of a version ... as part of swarm dev", and for memories that apply to all software swarm-dev builds to be extracted.

**Done when:**
- `swarm.sh retro` prints, since the last tag:
  - every out-of-scope finding with no story yet, grouped by kind
  - red mains and their causes
  - flaky test files
  - stalls
  - leftover-process reaps
  - lead memories added since the tag that name no project-specific thing

  `merge --release` refuses a release PR that links no retro, the way it refuses one with no docs line, and says how to write one. The lead's release steps (commands/swarm.md, reference.md § Releases) put the retro before the docs PR.
- `next` and `status` show a `refill` step when a conductor runs with at most one ready or building agent story. It lists cheap later stories, active epics without stories, and out-of-scope findings with no story. The lead's stop hook treats `refill` like any other step it must start.
- The generic rules from the lead's memory are in swarm-dev, each in the place that enforces it (lead skill and commands, builder brief, review brief, or a check), with a test where it can be checked. A new `swarm.sh rules --from-memory <dir>` lists a lead's memory files that aren't yet covered, for the retro's memory step.
- swarm.sh reaps a builder's load processes and containers when its build ends or it is closed, and caps load across all builders (a machine-wide CPU budget in config, 4 by default).
- The follow-ups listed under Problem are fixed, or each is dropped in the epic's PR with a reason: the respawn race, notes on reconcile and unblock, watching every conductor, the vacuous stubs, `touches` accuracy, CI shellcheck over hooks/, and perl in Requirements.

**Out of scope:** the Go migration (a separate decision, not yet made). Infrafactory.
**Constraints:** every new flag or gate ships off or warn-only first, and a lead story turns it on (method.md). No change spends cloud money.
**Your part:** approve the stories `/plan-epic` proposes. Nothing else.
