---
status: active
hld: 2026-10-13-builders-use-claude-codes-goal-advisor-and-agent-view
depends_on: [agent-state-from-the-session]
---

# A story that has failed twice is built on Fable, and a Fable failure goes to the lead (HLD Goals 2 and 4, Rollout 2; Goal 4 changed by the user on 2026-10-15)

**Done when:**
- One function chooses a story's role; build_story calls it and the role test hook (beside `_base`, bin/swarm.sh:2630) calls it. A test resolves attempts 0 and 1 to code/code-risky, 2 to `escalate` with `escalate_after = 2`, and never `escalate` with `escalate_after = 0`.
- End to end against stubs, `story`, `close`, `story`, `close`, `story` records roles code, code, escalate in agents.tsv, each in a fresh worktree: a counted failure removes the attempt's worktree and story/<slug> branch and closes its PR unmerged (linked for the lead item), and next_step does not report the story as `resume`.
- `close <slug>` raises `attempts:` once per build, only when a builder for the slug was open or retired and the story says `status: ready`, on both keep_panes paths; a double close counts once. `reconcile` never counts. Other close labels (hld-*, conduct-*, plan-*) are unchanged.
- A story closed after a failed `escalate` build becomes `kind: lead` with `escalated_from: <kind>` and its attempts' PRs or reports linked, with no **You:** step. `next` prints `escalated <slug>` for it, ahead of `gate`. commands/swarm.md's `escalated` arm has the lead decide on the spot: re-scope the story and `swarm.sh reset <slug>`, or drop it through a board PR. A story is reset at most once; after a second failed escalate build the lead drops it. Either way the lead tells the user what it chose and why. `swarm.sh reset <slug>` clears the count and puts the original kind back.
- An escalate builder on `waitingFor: dialog open` (Fable's usage-credits consent) is answered by its conductor: it accepts through `herdr pane send-keys` in the builder's pane, logs `dialog <slug>` to events.tsv, and waits on the builder again. The builder is not closed, and the dialog does not count as an attempt.
- Each escalation step is in events.tsv with its UTC time, for the training data (the user, 2026-10-15): `escalate <slug>` at the build, `dialog <slug>` when its consent is answered, `escalated <slug>` at the failed close, and `reset` or `drop <slug>` with the lead's reason.
- `dash --ladder` shows, per role, how many agents agents.tsv recorded and the models the sessions' first .jsonl message names, so a Fable attempt that fell back to Opus shows as Opus.
- A structural test fails when a ROLE_GROUPS role (:263) is reached by no `swarm.sh agent` line in commands/*.md, no start_agent call and no fixture story through the role function; it is shown red on db657b7's shape.
- A test fails when the method's config table (docs/method.md:116-129) and load_config/CONFIG_KEYS differ; it lands before `escalate_after` is added. A defaults test pins `escalate_after = 2`.
- docs/method.md § Model and effort and § Scoping an epic, README Cost and safety, and the stories READMEs describe the attempt count and the exception below.

**Out of scope:** the goal and the `close` cause argument (goal-for-builders). Any change to `code`/`code-risky`. A `kind: lead` story is never built by an agent.

**Constraints:** `escalate_after` ships on (2) by the user's decision of 2026-10-13, a deliberate exception to docs/method.md:171; the epic writes the exception into the method. swarm.sh writes `attempts:`, `kind: lead` and `escalated_from:` through a front-matter writer beside set_status, never an agent. Failed attempts' PRs come from `gh pr list --head story/<slug> --state all`, or nothing is linked and the story says so. New key: CFG_ default, CONFIG_KEYS, validator (non-negative integer, 0 off), method table row. `reset` is logged (not READ_ONLY). The give-up rule is conductor text in conduct_story_mode/conduct_epic_mode and commands/swarm.md; the retry stays in the same conductor. bash 3.2. Bump plugin.json.

**Your part:** none. By the user's decision of 2026-10-15 ("You should decide the escalation not me"), escalation decisions are the lead's: accepting Fable's usage-credits consent and deciding what happens to a story whose Fable build failed. The lead, after the wiring PR merges: `swarm.sh log-finding doc-ahead-of-code <PR URL> "method :152 promised Fable after two failures since db657b7; nothing called escalate"`. Escalation ships on by your decision, so there is no turn-on story.
