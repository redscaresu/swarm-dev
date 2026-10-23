---
kind: docs
status: ready
depends_on: []
touches: [commands/plan-epic.md, docs/reference.md, README.md, tests/plan_epic_test.sh]
estimate_lines: 30
easy: true
---

# plan-epic runs a skeptic only on risk: high stories

/plan-epic's step 3 starts one skeptic per story, capped at five. Planning plan-hld and epic-guard on 2026-10-24 started 12 verify agents for 9 stories. The skeptics read the same graph and the same code, so their findings overlap. Most of the real catches came from the survey (removed_test, the merge = human gap, the plan-hld re-fire) and from the one whole-plan critic. Skeptics and critics together have had 68 of 73 findings adopted, so the whole-plan reviewers are worth keeping. The per-story fan-out is the part to cut. The user agreed this change for 0.27 on 2026-10-24.

Change step 3 of `commands/plan-epic.md`:
- Start a `skeptic-<slug>` only for a story with `risk: high`, still capped at five. An epic with no `risk: high` story gets no skeptic.
- Move the per-story checks a skeptic made into the critic's brief for every other story: the `touches` clash inside a wave, a `depends_on` with disjoint touches and no `needs:` line, a wrong `kind`, and a missing or wrong `costs: money`. The lead already checks chain depth over the whole graph.
- Keep the codex pass and the critic as they are. Keep the split critic.
- Update the report and log-finding lines that assume a skeptic for every story.

Bring `docs/reference.md` (the "a skeptic per story" line near :240) and README into line. Update `tests/plan_epic_test.sh` if it asserts the old wording.

**Done when:**
- `commands/plan-epic.md` step 3 starts skeptics only for `risk: high` stories, and the critic's brief lists the four per-story checks above.
- `grep -rn "skeptic per story\|one \`skeptic-<slug>\` per story" commands docs README.md` prints nothing.
- `make test` passes.
