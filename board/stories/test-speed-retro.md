---
kind: lead
status: ready
depends_on: []
touches: []
---

# Retro: decide how to speed up the tests

The user asked on 2026-11-15 to discuss test speed at the next retro: are the tests overkill, how to
speed them up, and whether a move to Go would help. A read-only audit of origin/main that day found:

- 200 test files, 52,879 lines, over about 21.8k lines of bash and 58 Python helpers.
- CI: one run took about 9 minutes; its 12 shards took 124 to 514 s each; per-file times sum to 6,229 s,
  and the top 15 files take 40% of it (tell_queue 324 s, wait_lead 226 s, merge_rules 186 s,
  dash_time_limit 185 s). tell_queue is not marked SLOW.
- Locally (.swarm/test-runs.tsv): in November, 148 of 526 runs were full-suite runs, and they took 3 to 5
  hours with 2 to 12 other runs at once (mean load 14.8 on 14 CPUs). Quiet October full runs took 19 to 32
  minutes. Only 1 of 244 finished full runs exited 0. Selected-test runs: median 155 s over 1,250 runs.
- Every swarm.sh call parses all 1.48 MB of bash (bin/swarm.sh sources all 8 libs), about 0.37 s per call
  on the loaded machine.
- Overkill: little. 55 lines in 27 files read docs; no test greps bin/ source. Likely under 10% redundant.

Options, best value for effort first:
1. No full local runs: `scripts/select-tests.sh --run` only, a `~/.swarm/test-cap` of about 2, the full
   suite left to CI.
2. Lazy-load bin/lib/*.sh: source only the lib a command dispatches to.
3. Mark tell_queue, wait_lead and dash_time_limit SLOW, or split them, so one shard stops gating CI.
4. A fake clock for timeout paths, and a file-change wait instead of 0.2 s polls.
5. A shared git fixture template copied with `cp -R`, for the 49 files that build git repos.

Go: the audit recommends against it. It would remove the parse cost, but means rewriting about 21.8k
lines of bash and porting the black-box tests, and the race tests stay timing-bound. The middle path is
option 2, plus moving pure logic into the existing Python with in-process pytest.

Decided by the user on 2026-11-15: option 2 (lazy-loading the libs) is not for v0.31. The long-term
approach to the codebase and its tests is for v0.32, discussed at the retro.
The user also ruled out any machine cap (`~/.swarm/test-cap` stays 0), so option 1 is only
the no-full-local-runs part.

**You:** at the retro, pick which options become stories, and whether option 1 changes AGENTS.md's
"Before you open a PR" list.
