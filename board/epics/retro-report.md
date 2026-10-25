---
status: draft
hld: 2026-10-25-swarm-dev-0-28
stage: v0.31.0
depends_on: [rules-file, ladder-cost]
---

# The outer loop closes at the retro

The outer loop closes at the retro: swarm.sh retro --since <tag> writes the report (out-of-scope findings with no story, recurring kinds with no check after folding, incidents, reaped load from the reap events, unplaced memories), the retro file format lives on the board, a retro-file board PR skips codex, and the retro-v0.31.0 kind: lead story runs last over v0.27.2..v0.31.0, placing every Appendix B and C item and confirming each later story merged or dropped with a reason. HLD Goals 2 and 10, Design § The retro gate (the report, the story, the file) and § Memory extraction (the sort).

**Done when:**
- swarm.sh retro --since <tag> (default: the last v<version> tag) is a dispatch arm in bin/swarm.sh (`bin/swarm.sh:retro dispatch arm`) that writes the five lists from .swarm/ and the board: declined out-of-scope findings with no story (findings.tsv), recurring kinds with no check after folding (docs / docs-misstate-code / stale-docs / docs-stale; test-gap / test-coverage / missing-case; outcomes_join.py:271-311's check columns), incidents (flow_incidents.py's kinds), reaped load (the `reap` events test-speed writes), and the lead's memories under --memory <dir> (default: the main checkout's directory under ~/.claude/projects/, agents.sh:601's CLAUDE_PROJECTS); a fixture test pins each list, the folding, and an empty memory dir; gh calls stay inside Appendix C's budget rule.
- A retro file format lives on the board with a template, a README entry and a Board.base view: `covers: <from>..<to>` and `done: YYYY-MM-DD`; the retro story is `retro-<version>`, kind: lead, with You: steps; tests/board_readme_test.sh passes; a board-only PR of kind retro file merges on green CI with no codex-review (less-noise's kind mechanism), with a test.
- The retro-v0.31.0 story (kind: lead, story-level depends_on on every other v0.31.0 story in this epic, retro-gate and handover-usage) is done when the retro file `covers: v0.27.2..v0.31.0`, `done:` set, is on main: every item of the five lists ended as a story, a check, a rule (rules file, a project's brief or AGENTS.md) or a reasoned drop; every Appendix B and C item is listed with where it went (rules-file, less-noise's AGENTS.md lines, a check, or a drop), since the lead's store here is empty; each of the seven later stories is merged or dropped with a reason; merge-agent-on and the parked lead stories are closed or re-dated; the step_up_findings default and the top rung are decided from flow's cost and review_loops; the v0.28.0 to v0.30.0 readings (test_runs, holds, merge_ins, lead_queue, green_to_review_min, ci_health) are recorded against their features.tsv bars; each memory placed is deleted from the lead's store.
- docs/reference.md and README.md describe swarm.sh retro and the file; bin/swarm.sh's usage header names it; doc_check passes.

**Out of scope:**
The release gate and next's retro step (retro-gate); handover and usage (handover-usage); the swarm promoting a rule by itself; a registry of boards; reading the old machine's .swarm/ (Appendices A to D are the 0.27 evidence).

**Constraints:**
- The lead runs swarm.sh retro from main's bin/swarm.sh at the release base (the installed plugin is v0.30.0 and has no retro arm), as the HLD's Rollout § This machine records the lead did in 0.27; the retro file says which commit's swarm.sh wrote it.
- tests/removed_test.sh pins the collect text and bans 'swarm.sh cost', 'swarm.sh export', 'docs/review.md', lessons_report; the retro's names avoid them.
- doc_check: swarm.sh retro is a dispatch arm in the same PR that documents it; bin/swarm.sh is touched as `bin/swarm.sh:retro dispatch arm` and `bin/swarm.sh:usage header` (handover-usage touches `bin/swarm.sh:handover dispatch arm`).
- Never run outcomes, flow or retro against the real repo in a loop; one run after gh api rate_limit (Appendix C).
- bash 3.2, shellcheck, loose_match_test, lib_path_test, make test, claude plugin validate; humanizer over README, docs, templates and the retro file's prose.
- Order: retro-gate's gate story goes after this epic's format story (it reads covers: and done:); handover-usage's usage-header line goes after this epic's header story; this epic's retro-v0.31.0 story goes after every other v0.31.0 story (retro-gate's and handover-usage's), and the release-v0.31.0 story after it.

**Areas:** bin/swarm.sh:retro dispatch arm, bin/swarm.sh:usage header, bin/lib/ (new retro helper .py and .sh), bin/lib/outcomes_join.py:kind folding, bin/lib/merge.sh:board PR kind retro file, templates/docs/ (retro format, Board.base view), board/ (retro dir, README), docs/reference.md:retro, README.md, tests/ (retro, board_readme, board_pr)

**Your part:**
User: go through the 0.28 retro with the lead, deciding each item (story, check, rule, drop) and each Appendix B and C memory (check, rules file, one project, drop). Lead: open retro-v0.31.0 once every other v0.31.0 PR has merged (check `ls board/stories` for none of v0.31.0's code stories), run main's `bin/swarm.sh retro --since v0.27.2` into the story, land the retro file by board PR, close merge-agent-on and the parked lead stories as decided.
