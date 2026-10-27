---
kind: code
status: blocked
epic: conductor-hands-off
depends_on: [story-merge-notes-conductor]
needs: [story-merge-notes-conductor: conductor_note <epic> <file> (bin/lib/merge.sh)]
touches: [bin/lib/board.sh:mark_review, docs/reference.md:ready-now note paragraph, tests/handover_note_test.sh (new)]
estimate_lines: 70
easy: true
risk: high
---

# A story handed to the user with swarm.sh review notes its conductor

Uses story-merge-notes-conductor's conductor_note (bin/lib/merge.sh). Under merge = human the review agent ends its loop with `swarm.sh review <slug> <PR URL>` (mark_review, bin/lib/board.sh:1688). Nothing tells the conductor, so one waiting only on that story never reports. After mark_review puts a story in review (not when it dies on a held stacked story), send its epic's conductor a note through conductor_note: the story and its PRs now wait for the user. An epic's own review (`swarm.sh review <epic> <urls>`) sends none. A failed tell is a warning and never fails the review.

**Done when:**
- tests/handover_note_test.sh (new), herdr stubbed, conduct-e listed: `swarm.sh review s1 <url>` for a story of e leaves one note in .swarm/inbox/conduct-e.md naming s1 and its PR. Fails on today's code, which writes no inbox.
- The same test: a review held on an open parent (`held: s1 waits for ...`) sends no note; `swarm.sh review e <url>` for the epic sends none; with no conductor running, no inbox is written.
