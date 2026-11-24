---
kind: lead
status: ready
epic: foundation-exit
depends_on: []
touches: [board/stories/stage1-exit.md]
estimate_lines: 0
easy: true
---

# Lead: stage 1's exit, from the v0.32.0 cut to stable on it

The one story of foundation-exit (X1): no PR of its own and no after: line. The retro and the release are `next`'s steps around it, never stories. Follow the epic's X4 order.

1. Lead: once `next` prints `retro v0.32.0`, go through the report with the user and land board/retros/v0.32.0.md (covers: v0.31.3..v0.32.0, done: set) by board PR. It records that the v0.31.0 test-speed items move to v0.33.
2. Lead: once `next` prints `release`, cut v0.32.0 with `swarm.sh merge --release`, a version bump only, with README.md, AGENTS.md and docs/ in line with everything since v0.31.3. Check by hand the four assets, SHA256SUMS, the attestation and that prerelease points at v0.32.0.
3. Lead: add `redscaresu/swarm-dev#pre-marketplace` if it is missing, install swarm-dev@swarm-dev-pre, then run the prerelease install's `swarm.sh upgrade` in each project with agents, so they move to v0.32.0 and not to the stable path. Then uninstall swarm-dev@swarm-dev and restart the sessions (docs/lead-by-hand.md § Switching to the prerelease). Run `swarm.sh version` once.
4. Lead: record here the differential run against v0.31.2 (each difference named: the fix: true stories' and stage 1's allow list), CI's wall time and process starts per command from the speed job, and the lines of bash and Python and the python3 start sites left.
5. **You:** switch the second Mac to swarm-dev@swarm-dev-pre (the same steps as 3), uninstalling swarm-dev@swarm-dev.
6. **You:** run v0.32.0 on both Macs, read the figures in step 4, agree stage 1's allow list and say go.
7. **You:** right after the go, switch the second Mac back: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, restart its sessions.
8. Lead: move stable to v0.32.0 and check that stable and prerelease both point at it.
9. **You:** update the second Mac with no other step, and run one command. If the update fails, the exit stays open and the fix is a fix: true story.
10. Lead: quote the user's go with its date, then `swarm.sh finish stage1-exit` and `swarm.sh finish foundation-exit`, a board PR each.

**Done when:**
- v0.32.0 is tagged with four binaries, SHA256SUMS and an attestation, and stable and prerelease are on it.
- board/retros/v0.32.0.md is on main with covers: and done: set and the v0.33 test-speed line.
- This file records the differential run, the speed figures and the three counts, and quotes the user's dated go.
- The second Mac updated on stable with no other step and ran a command.

## Exit figures (2026-11-24)

Step 4, read on v0.32.0 (d28a74f). The release was checked by hand first: four binaries, SHA256SUMS (all four OK), an attestation on each (all four verified), and prerelease on d28a74f. Stable is still on v0.31.3 (06b35a67).

**Differential run against v0.31.2.** The diff-run job by hand, stage 1, on v0.32.0: [run 45301114197](https://github.com/redscaresu/swarm-dev/actions/runs/45301114197), red. Of 45 fixtures, 36 are the same and 9 differ. The six stage 1 allow entries: four apply in full; docs-gate-go applies 5 of 6 hunks and protected-go-paths 71 of 76.

- go_paths_agentenv, go_paths_guard, go_paths_merge, go_paths_plugin, go_paths_release: explained by protected-go-paths (#1038). v0.32.0 holds the PR for a protected Go path, so the merge and its CI calls are gone. One hunk per fixture, in calls:fg, no longer applies, so the entry needs refreshing.
- gate_release_go_docs: explained by docs-gate-go (#1039). Its check-runs and status reads are gone; one hunk no longer applies.
- usage: the dash line is gone, from delete-dash (#1082), a stage story the user decided on 2026-11-20. No allow entry names it.
- dropped_merge_own_story (14 hunks) and gate_release_port_listed (2 hunks): **not explained.** The same gh calls, in the same order, moved from calls:fg to a step label of their own. No fix: true story or allow entry names this. It looks like the step-label timing gap deferred on #1063.

**Speed.** The speed job by hand on v0.32.0 against v0.31.2: [run 45301119110](https://github.com/redscaresu/swarm-dev/actions/runs/45301119110), green. Five runs a tree, alternating, under strace.

| command | v0.31.2 median | v0.32.0 median | v0.31.2 starts | v0.32.0 starts |
|---|---|---|---|---|
| next | 194 ms | 200 ms | 43 | 43 |
| status | 205 ms | 211 ms | 42 | 42 |
| trusted_git | 74 ms | 68 ms | 12 | 13 |
| usage | 49 ms | 50 ms | 8 | 8 |

tests/speed_list.txt lists only these four commands.

**What is left to port, on v0.32.0.**
- Bash: 23,987 lines, from bin/swarm.sh (1,495) and bin/lib/*.sh with hooks/*.sh (22,492, 13 files).
- Python: 8,031 lines in 55 bin/lib/*.py files.
- python3 start sites: 122 lines outside comments name python3 across 12 files in bin/ and hooks/; docs/port/sites.tsv lists 26 rows, the inline sites that import a bin/lib helper.
