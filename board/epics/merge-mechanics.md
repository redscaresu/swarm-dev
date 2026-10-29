---
status: draft
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: [reference-split]
---

# merge-mechanics

HLD Goal 12 (v0.31.0): merge mechanics hold. #692 a lead PR outside a story has a merge path; #697 merge --board of a plan PR that files ready stories starts their conductor and says why when it does not; #694 upgrade resumes agents without a herdr session id, skips closed ones, and merge --release asks before running it; #699 a lead investigation. #691 shipped in lead-woken.

**Done when:**
- stage: v0.31.0
- #692: swarm.sh merge merges a PR a kind: lead story lists on its prs: line after swarm.sh review (today refused at merge.sh:866), and next names a lead PR no story lists; docs/lead-by-hand.md:66-71 removed.
- #697: merge --board of a plan or stage PR that files ready stories under an active epic, or sets active an epic that has ready stories, starts that epic's conductor (ready_tell, then conduct_ready, merge.sh:1113-1165) and prints why when it starts none (today it is silent when board_ready lists nothing); an epic set active with no stories starts nothing, writes no report and is offered to plan-epic by next (codex: a conductor on an empty epic would report at once under stop_rule, build.sh:57-69, and finish it unplanned); tests for both and for the silent case. The lead supplies the two v0.29.0 `merge` event lines of the plan PRs that started nothing (the live .swarm/events.tsv) as the story's evidence of the cause.
- #694: upgrade_one (lifecycle.sh:4545-4592) reads the session id from agents.tsv through recorded_session (agents.sh:775-780) when herdr has none instead of dying at 4556, skips agents whose pane is closed and says so, and release_upgrade (merge.sh:2090-2119, called at 1045-1048) asks before running; a non-interactive session defaults to not running it and says so; tests/upgrade_test.sh cases for each.
- #699: a kind: lead story with a You: step records what the permission classifier refused in a conductor's swarm.sh merge and why, or that it did not recur in the v0.31.0 build, and files a fix story or closes.
- docs/features.tsv row: lead-hand incidents of these kinds per build, read from `flow incidents` rows with cause in story-gone, pr-no-story, no-conductor, classifier, upgrade (telemetry-writers' list; 12 in v0.29.0; bar 0); docs/lead-by-hand.md entries for #692 (66-71), #694 (119-124), #697 (98-103), #699 (113-117) removed.

**Out of scope:**
#691 (lead-woken, v0.30.0); merge queue or merge_admin settings; a herdr change to hold session ids (HLD Non-goals); conductor lanes.

**Constraints:**
- stage: v0.31.0. depends_on reference-split. Parts: merge.sh:merge_caller (the lead-PR route), merge.sh:conduct_ready (#697), lifecycle.sh:upgrade_one and merge.sh:release_upgrade (#694); merge-safety's merge_pr parts are merged by then. handover-usage touches bin/swarm.sh's dispatch: name parts, no clash.
- merge --release's confirm is a prompt in the lead's session: without a tty it must not run upgrade, and say so.
- #699 is kind: lead (unknown cause, HLD:461-463): never given to an agent.
- upgrade's resume sends no new brief (lifecycle.sh:3921-3924): the skipped-closed and recorded-session paths change nothing there.

**Areas:** bin/lib/merge.sh:merge_caller (lead PR route, 866), bin/lib/merge.sh:conduct_ready, bin/lib/merge.sh:release_upgrade (confirm), bin/lib/lifecycle.sh:upgrade_one, bin/lib/agents.sh:recorded_session (new caller), bin/lib/board.sh:next_step (unlisted lead PR line), commands/swarm.md:release arm (confirm), docs/reference (Merging and Releases, in their split files), docs/lead-by-hand.md:#692 #694 #697 #699, docs/features.tsv:Goal 12 row, board/stories/<#699 lead story>, tests/merge_test.sh, tests/merge_queue_test.sh, tests/conduct_backlog_test.sh, tests/upgrade_test.sh, tests/next_test.sh:lead PR cases

**Your part:**
- #699's You: step: reproduce the classifier refusal from a conductor pane, or confirm it has not recurred in the v0.31.0 build.
- Give the #697 story the two `merge` event lines from .swarm/events.tsv for the plan PRs that started no conductor (the log is gitignored, so a builder cannot read it).
- Answer merge --release's new confirm when cutting v0.31.0.
