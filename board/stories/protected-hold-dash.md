---
kind: code
status: blocked
epic: merge-holds
depends_on: [protected-hold-queue, dash-grant-queue]
needs: [protected-hold-queue: the ` (protected path)` row on waiting_on_user's awaiting-your-merge lines in bin/lib/board.sh, which dash parses, dash-grant-queue: its awaiting-rows change in bin/lib/dash_render.py, which this story extends with the protected-path tag]
touches: [bin/lib/dash_render.py:awaiting rows, bin/lib/dash.sh:dash_check merge rows, docs/reference.md:lead setting, tests/dash_needs_you_test.sh:protected-path case]
estimate_lines: 70
easy: true
---

# dash shows a protected-path hold under needs you, as a costs: money one

Uses protected-hold-queue's ` (protected path)` row on waiting_on_user's `awaiting your merge` lines (bin/lib/board.sh:waiting_on_user). It builds on dash-grant-queue's change to dash_render.py's awaiting rows, which decides whose queue a granted PR's row goes in.
- dash_render.py's awaiting-rows pattern (:339-344) accepts the new tag next to ` (costs money)`. Under lead = session, a protected-path merge row stays under needs you, as a costs: money row does under merge = agent (docs/reference.md:606). dash-grant-queue's rule for granted PRs stays as it is.
- dash --check's merge agreement (bin/lib/dash.sh:278-290) agrees on such a row.
- Until this merges, main's dash leaves out a protected-path row that status lists.

**Done when:**
- tests/dash_needs_you_test.sh gains a case: with merge = agent and lead = session, a story whose status line reads `awaiting your merge (protected path): <slug> <url>` is drawn under needs you with its PR, and `swarm.sh dash --check` reports agreement.
- Same file: a costs: money row, an untagged row and dash-grant-queue's granted-PR row are drawn as before.
- reference.md's lead setting line names protected-path rows next to costs: money ones.
