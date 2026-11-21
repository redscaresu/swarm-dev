---
kind: code
status: ready
depends_on: []
touches: [bin/lib/merge.sh:ci_gate (the main mode's poll), bin/lib/merge.sh:merge_pr (its wait for CI on the base), tests/merge_ci_budget_test.sh]
estimate_lines: 150
fix: true
---

# swarm.sh merge's wait for CI on main stops using up the GitHub API limit

On 2026-11-21 the swarm used up the 5,000-call hourly REST limit twice in under an hour. The first time was before 10:10Z. The second ran from the 10:29Z reset to 11:14Z. Every agent's gh call then failed until the next reset, and a merge failed with "API rate limit exceeded".

`.swarm/gh-calls.tsv` logged 3,054 calls between 10:29Z and 11:14Z. `swarm.sh merge` made about 1,400 of them (46%), split almost evenly across three endpoints:
- `actions/runs` (paginated)
- `commits/:id/check-runs`
- `commits/:id/status`

Those calls come from `ci_gate main` in `merge_pr` (bin/lib/merge.sh:1433). It reads all three every `MERGE_POLL` (20 s) for up to `MERGE_CI_SECONDS`. Several merges ran that wait at once, each on its own merge commit, so main's CI was read many times over.

Scope:
- `ci_gate main` polls less often. It starts at `MERGE_POLL` and doubles to a cap of 120 s while nothing has changed since the last read. It resets to `MERGE_POLL` when a run starts or ends.
- When `ci_gate main` reads a merge commit that a newer merge's wait covers (a later commit on the base whose CI includes it), it leaves the wait to that one. The base's newest merge then carries the wait for CI on main. An older merge exits with that merge's commit named.
- A red on the newer commit still prints `fix-main:` once, from the newer merge's wait.
- The poll's cap is a constant beside `MERGE_POLL`, with a `SWARM_` override like it. Add its row under `docs/port/`, as AGENTS.md says.

**Done when:**
- A new test runs `ci_gate main` against a gh stub whose CI stays pending for a fixed span. It counts the stub's calls and fails when the count is more than half what a fixed 20 s poll makes over the same span.
- A second case runs two merges' main waits at once on stub commits A and B, where B is newer and includes A. It shows A's wait exits naming B, and that B's red prints `fix-main:` once.
- docs/reference-merging.md § Merging says how the wait for CI on main polls, and that an older merge leaves the wait to the newest.
- scripts/select-tests.sh --run passes
