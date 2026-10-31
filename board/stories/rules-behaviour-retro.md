---
kind: lead
status: ready
epic: retro-report
depends_on: []
touches: []
estimate_lines: 10
easy: true
---

# Lead: record where Appendix B's five behaviour items went, for the v0.31.0 retro

Moved from rules-file to retro-report on 2026-10-31 by the lead: its decisions are taken at the v0.31.0 retro, and as rules-file's lead story it held the v0.30.0 release for no work. This holds the record the epic asked to keep in its own file, since the epic's last story's PR deletes that file (build.sh:440). It says where each of Appendix B's five behaviour items went. (a) Refill: covered by a merged next step with a test: next's `idle: "<project>"` line with out-of-scope findings, and its done step (bin/lib/board.sh:534-553, 359; tests/next_test.sh:595-630). (b) Time-boxed delegated work: dropped as a check. swarm-dev's own delegated work runs in herdr panes, which wait already time-boxes (1 h by default, plus `stuck: no output for <N>m`; bin/lib/lifecycle.sh:4692-4719, bin/lib/agents.sh:1231-1240). The Agent and Workflow tools belong to Claude Code, and nothing swarm.sh runs sees their completion, so no check is cheap. (c) story-edits-unpushed. (d) guard-main-checkout-edits. (e) planning-briefs-rules. Lead: put these five in the v0.31.0 retro file (retro-report's retro-v0.31.0 story), with (c) to (e)'s merged PRs. **You:** at the v0.31.0 retro, confirm the drop of (b), or move it into rules.md or a story, and confirm that (a) counts as covered. Also record one gap for the retro: the texts agents write for people from swarm.sh's own briefs (story PR bodies, a conductor's epic report, handovers) get no humanizer pass yet (bin/lib/build.sh's briefs); the retro decides whether that is a story.

**Done when:**
- The v0.31.0 retro file lists each of the five items with its check, its story's merged PR or its drop. The user's decisions on (a) and (b) are written beside them, dated.
- The PR-body and report humanizer gap is in the same retro file, with the user's decision.
