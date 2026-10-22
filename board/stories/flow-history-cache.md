---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/report.py:merged PR list, bin/lib/flow_ci_health.py, bin/lib/reports.sh:story PR rows, bin/lib/gh_cache.py (new), tests/gh_cache_test.sh (new), docs/reference.md:Flow and features]
easy: false
estimate_lines: 250
---

# flow caches finished GitHub history and fetches only what is new

User, 2026-10-22: optimise flow rather than cap it. That evening two builders each ran `swarm.sh flow --since 2026-10-16` on this repo to quote in their PRs, and one run spent GitHub's whole REST budget (about 4300 calls) in 14 minutes, stalling every agent. flow re-reads history that can never change on every run:
- report.py:234 lists up to 1000 merged PRs with files and bodies.
- flow_ci_health.py:39 lists 200 runs per branch, and line 55 reads every attempt of each.
- flow-flaky-tests adds failed jobs' logs.
- reports.sh:256 runs a `gh pr list --head story/<slug>` per story.

#347 cached one of these, `.swarm/outcomes-prs.tsv`. Do the same for the rest.

One small cache module (bin/lib/gh_cache.py) under `.swarm/gh-cache/`, keyed by repo. It caches only finished records, which never change:
- merged or closed PRs, with their files and bodies
- completed workflow runs and their attempts
- the logs of completed jobs

An open PR or an in-progress run is always read fresh. Each source fetches only what is new since the newest cached record (merged PRs by `merged:>=<date>`, runs by `created:>=<date>`), and the window `--since` asks for is then served from the cache. Writes are atomic (temp file plus rename), so a parallel flow run never reads half a file. A cache that can't be read or parsed is rebuilt, never trusted. `flow --no-cache` reads everything fresh. Logs are capped, keeping only the FAIL lines flow uses, not whole logs.

**Done when:**
- tests/gh_cache_test.sh, with a stub gh that counts its calls: a second `flow --since <7 days>` right after the first makes no call for merged PRs or completed runs, only for open ones and what's new. A run that was in progress on the first call and completed on the second is fetched again then cached. A corrupt cache file is rebuilt. `--no-cache` fetches everything.
- The PR quotes the gh call count of two back-to-back `flow --since <7 days ago>` runs on this repo (gh-calls-by-agent's log, if merged, or a counting wrapper): the second makes under 50 calls.
