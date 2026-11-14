---
kind: code
status: ready
epic: handover-usage
depends_on: []
touches: [bin/swarm.sh:handover dispatch arm, bin/swarm.sh:usage header (handover line), bin/lib/handover.sh (new), tests/handover_test.sh (new), scripts/test-map.tsv:handover row, docs/reference-logs.md:Commands table (swarm.sh handover row), README.md:handover line]
estimate_lines: 220
easy: false
---

# swarm.sh handover carries what another machine needs that is not in git

For 0.28 (0.27 retro, 2026-10-25): a lead-only practice from 2026-10-24 that every project should get. The usage warning that was part of this story is now its own story, usage-warning.

`swarm.sh handover <dir>` writes what another machine needs that is not in git:
- the project's `.swarm/` without session logs (no `*.jsonl`, nothing under a sessions directory, no agent session ids)
- a patch of the main checkout's uncommitted board edits
- a snapshot of open PRs and agents
- a RESTORE.md that says how to restore each part into a fresh clone

The lead's memory directory is copied only when the user names it (`--memory <dir>`), and it is never published. Never read a credential file: `.swarm/` files whose name matches a token, key or secret pattern are skipped and listed in RESTORE.md as skipped.

Add the dispatch arm (`bin/swarm.sh:handover dispatch arm`) and one line for it in the usage header; retro-command already added its own header line, so put this one beside it. Add the command's row to docs/reference-logs.md § Commands and one line to README.md. Record in the PR body that Appendix B's lead-handover note (HLD 2026-10-25-swarm-dev-0-28) is the only infrafactory memory this moves into swarm-dev.

**Done when:**
- tests/handover_test.sh: a fixture project's handover holds `.swarm/` without session logs, the board patch, the snapshot and RESTORE.md; restoring it into a fresh clone of the fixture gives the same `swarm.sh next` and board files
- The same test plants a session log and a file named like a token under `.swarm/`; neither is in the handover, and RESTORE.md lists the token-named file as skipped
- Without `--memory`, no file from the memory directory is in the handover; with it, they are
- Each of the three cases goes red with its rule removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- doc_check_test passes with the new command, its usage line and its Commands row
- scripts/select-tests.sh --run passes
