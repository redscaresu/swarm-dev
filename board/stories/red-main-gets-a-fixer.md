---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/merge.sh:main CI wait, bin/lib/build.sh:conductor brief, commands/swarm.md, tests/]
---

# A red main gets a fixer at once

On 2026-10-18 main went red after #287 and #293 merged (each green alone: #293 removed HLDs, and a
next_test.sh case still planted its failure on an HLD path). `swarm.sh merge` saw it and froze
every merge, which is right, but nobody owned the fix: the conductor guessed tests-fast (#284)
would fix it, it did not, and the queue sat frozen until the lead wrote a one-line test fix (#308).

When `merge` (or its main-CI wait) finds main red on a commit it merged, it records
`main-red <sha> <failing checks>` in events.tsv and prints `fix-main: <checks> on <sha>` with the
failed job's FAIL lines. The conductor brief: on `fix-main`, start a builder at once on a one-off
`fix-main-<short sha>` (story written by swarm.sh, kind code, the FAIL lines in its body), ahead of
every other story; merges stay frozen until main is green. Never wait on an unrelated PR to fix it.
`next` names a red main ahead of everything else, for the lead.

**Done when:**
- A stub main-CI run that fails with a FAIL line makes `merge` print `fix-main:` with that line and write the one-off story; a green one does neither.
- The rendered conductor brief has the fix-main rule (a test greps it); `next` with a recorded red main prints it first.
