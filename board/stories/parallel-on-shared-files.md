---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:conductor brief, docs/method.md:Building, tests/]
---

# Stories that share a file build side by side

On 2026-10-18 twelve ready stories sat unstarted behind eight open PRs for hours, because the
conductor's brief (bin/lib/build.sh:121, :149, :860, and method.md § Building) holds back any
story whose `touches` overlap a running one, file by file. Git merges edits to different parts of
one file without help, and `touches` already names functions (`bin/lib/board.sh:next_step`), so
the file-level hold costs far more wall clock than the conflicts it avoids. Each PR also went
through 3-4 review rounds while its builder sat idle.

Change the brief and method.md:
- Two stories clash only when they name the same `file:symbol`, or when either names the bare
  file of a file the other also names. Otherwise both build at once.
- A builder whose PR conflicts with main merges main in, resolves, reruns the tests and pushes; a
  conflict never sends a story back to `ready`.
- Review stops after round 3: from round 4 on, only a real bug (wrong behaviour, data loss, a
  security hole) sends the PR back. Anything smaller is declined with a reason and logged with
  `log-finding --declined`.

**Done when:**
- A test renders the conductor brief and greps the symbol-level clash rule, the merge-main-in rule and the round-3 cap; the old file-level wording is gone.
- method.md § Building says the same, and a test greps it.
