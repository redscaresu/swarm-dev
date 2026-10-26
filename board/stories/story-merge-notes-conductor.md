---
kind: code
status: ready
epic: conductor-hands-off
depends_on: []
needs: [less-noise's board-root-helper: the board-root helper that replaces the inline copies in merge_pr and ready_tell (bin/lib/merge.sh); order only, the lead adds depends_on once the slug is final]
touches: [bin/lib/merge.sh:conductor_note (new), bin/lib/merge.sh:merge_pr story path, bin/lib/merge.sh:ready_tell, AGENTS.md:swarm.sh merge bullet, docs/reference.md:ready-now note paragraph, tests/merge_note_test.sh (new)]
estimate_lines: 170
easy: false
risk: high
---

# A story PR's merge notes its running conductor, even when reconcile fails

Only `swarm.sh merge --board` tells running conductors what a merge made ready (ready_tell, bin/lib/merge.sh:554-607, called at :384-393), and when its reconcile fails (:562-567) nobody is told. Once review agents merge, the conductor never hears a story merged, so nothing starts what the merge readied. Add one helper, conductor_note <epic> <file> (new), out of ready_tell's checks (herdr list, live pane, no report written): it notes the epic's running conductor (the backlog's for no epic) or prints the `ready now: ... no conductor runs` line. ready_tell calls it. After merge_pr lands a story PR (its story path, :400-409), it sends the story's conductor (epic read before the merge) one note: the PR merged and the stories it made ready. When reconcile fails after a merge, story or --board, the note still goes, naming the failure; the story path still dies after it as today. A failed tell is a warning and never fails the merge. This is the epic's 'notes survive a reconcile that fails under set -e' item as it exists on main. Update AGENTS.md's swarm.sh merge bullet (:80), which says only a --board merge notes conductors. Less-noise's board-root-helper also edits merge_pr and ready_tell (it replaces the inline board-root copy at :556), and merge-holds' protected-path-hold and merge-base-moved/merge-base-update edit merge_pr and AGENTS.md:80: this story merges after them.

**Done when:**
- tests/merge_note_test.sh (new), gh and herdr stubbed, conduct-e listed: after `swarm.sh merge` lands a story PR of epic e whose merge readies s2, .swarm/inbox/conduct-e.md holds one note naming the PR and s2. Fails on today's code, which writes no inbox for a story merge.
- The same test with reconcile made to fail after the merge: the inbox still gets a note naming the PR and the failure, and merge still exits non-zero. With `merge --board`, whose inbox stays empty on a failed reconcile today, the note goes too. Each fails on today's code.
- The same test: with no conductor running, or one that has written its report, no inbox is written and the `no conductor runs` line is printed.
- tests/tell_note_test.sh and tests/board_pr_test.sh pass unchanged; AGENTS.md:80 says a story merge notes its conductor too.
