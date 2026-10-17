---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [split-bash]
touches: [bin/lib/board.sh:next_step, bin/lib/dash.sh, bin/lib/reports.sh:findings log, commands/swarm.md, commands/plan-epic.md, tests/next_test.sh]
easy: false
estimate_lines: 220
---

# The swarm finds its own idle capacity

On 2026-10-17 one builder ran while 3-4 stories could have built beside the split, and infrafactory sat idle with two small fixes known only to the lead. The user found both by asking. Three changes:
- **Over-broad dependencies.** `next` prints `idle: <story> waits on <dep> but shares no touches with it` for a blocked story whose `depends_on` story shares no file in `touches`. The lead either drops the dependency through a board PR, or keeps it and adds a `needs:` line naming what the story uses from the dependency. plan-epic's skeptic brief refutes a `depends_on` with no shared touches and no `needs:`.
- **An idle project.** When a project has no buildable story (every open story is blocked, later or lead), `next` prints `idle: <project>` with up to five candidates: `later` stories, and findings declined as `out-of-scope` in the last 30 days, newest first. The lead files or promotes one as a one-off, or says why none fits. A declined out-of-scope finding is the swarm's own list of follow-ups, so the lead stops keeping them in memory.
- **Visible.** dash's agents gauge line adds `idle: <n> buildable not started` when ready stories exist that no conductor has picked up.

**Done when:**
- Fixture: story B depends on A with disjoint touches and no `needs:`; `next` prints the idle line for B. With a shared file, or with a `needs:` line, it does not.
- Fixture: a project whose open stories are all blocked or later, with one out-of-scope declined finding, prints `idle:` and lists that finding and the later stories.
- commands/swarm.md says what the lead does with each `idle:` line, and commands/plan-epic.md's skeptic brief names the disjoint-touches check; tests/next_test.sh greps both.
