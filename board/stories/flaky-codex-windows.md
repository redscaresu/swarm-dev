---
kind: code
status: ready
epic: flaky-tests
depends_on: []
touches: [tests/codex_test.sh:grace case, tests/codex_test.sh:deep chain case]
estimate_lines: 50
easy: false
---

# codex_test's grace and deep-chain cases stop depending on how fast a loaded runner starts the TERM trap

Needs no other story. Cause, from the 5 most recent of 15 codex_test flaky runs (gh run view <id> --repo redscaresu/swarm-dev --attempt 1 --log-failed). The grace case (tests/codex_test.sh:152-159) got 'yes|no' 3 times (41172376144, 40847282634, 40684914346): the stub's trap ran `sleep 3`, then touched graceful, and it was KILLed first. The deep-chain case (:145-150) got 'no chained' 2 times (40572721411, 40521637884): the 11-process chain was not built before the KILL. The survey's guesses (gone()'s 2 s at :78-85, `sleep 1` at :168, the 0.3 s stubs at :194/:203) failed in none of these 5. Read the other 10 runs first (40438050993 40148794975 39824144488 39766868772 39761860565 39737400666 39724251777 39718437588 39714998271 39588451828) and name each one's failing check. Fix any other case they show. Fix: each case waits on the condition its check reads (the trap's own start, chained or graceful), or gives the grace room the trap needs, without a fixed sleep before a check. Keep what the grace case proves: a grace cut under 3 s still fails it (comment :152-154). Run the 20 runs one at a time, JOBS=1. Do not touch the codex_test cases that reliable-runs' codex-rate-limit stories pin. Edit only the grace and deep-chain cases. Any other case the 15 logs show is named in the PR and filed as a follow-up story, not fixed here.

**Done when:**
- In the PR, each of the 15 runs is named with its failing check, quoted from its log.
- Forced-load proof in a worktree copy without .git: the stub's TERM trap starts 2 s late. The unfixed grace and deep-chain cases fail, and the fixed ones pass. The PR quotes both.
- In the copy, a grace cut to 2 s (SWARM_CODEX_GRACE=2 on that case) turns the grace check red.
- 20 runs of make test TESTS=tests/codex_test.sh JOBS=1, one at a time, all green. The count is in the PR.
- No check is removed or loosened: the same check names pass, with the same wants.
- shellcheck is clean on tests/codex_test.sh.
