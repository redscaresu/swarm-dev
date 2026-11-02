---
kind: lead
status: ready
epic: board-loose-ends
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# Lead: the v0.31.0 checkpoint, Goals 1 to 9 against their bars from flow

Filed ready, so `next` lists it with the lead's stories. Not before the 20th story merge of v0.31.0 or 2026-11-08 (seven days after the stage started with #810 on 2026-11-01), whichever comes first: the lead checks that on each `next`. release-v0-31-0's readings step (loose-ends-fates) is a second catch. 1. Run `gh api rate_limit`. Then run each of these once, in order and never in a loop: `swarm.sh dataset` (without it, flow's predictions section only prints the command, flow_predictions.py:15), `swarm.sh flow --since 2026-11-01` into a file, and `swarm.sh flow --since 2026-10-28 --until 2026-10-31` for the v0.30.0 window's ci_health baseline. 2. Write board/retros/v0.31.0-checkpoint.md (new): heading, *Created:* date, the window and the plugin version the build ran on. Add a `## Checkpoint` section with one row per goal, giving value, bar, flow section and docs/features.tsv row: Goal 1: time_in_state review_wait_median and p90 (:69), review_loops prs_4plus_rounds (:70) and deferred_proved_real (:71). Goal 2: tell_refusals (:64). Goal 3: incidents' stalled inputs (:65). Goal 4: start_failures not_restarted (:66). Goal 5: incidents lead-hand per 100 merged story PRs (:62) and lead_queue p90_min (:63). Goal 6: whether each of Goals 1 to 5 came from its section, with no pane read. Goal 7: the rules-file row (:60). Goal 8: merges dropped_lines (:67). Goal 9: the ladder-cost row (:61). Also record ci_health (:47) against the v0.30.0 window, and the predictions rows. A value flow does not give is written `not measured: <why>`, never 0 (rules.md:15). A missing section files a story; telemetry-writers has left the board. 3. For a goal off its bar, file a story in the v0.31.0 stage, under the epic that owns the area or under this one, by board PR, and name its slug in the row. 4. Turn back a feature that made things worse by its config line in .claude/swarm/config (its own PR, a protected path held for the user), and list it for the retro. Examples: red_runs_per_pr above the v0.30.0 window's under review_verify = ci, or deferred_proved_real over 10% of deferred findings. **You:** read the record and say which features, if any, to turn back. Land the file by board PR. If retro-report's retro file format has landed by then, give the file the fields its check reads. Each goal's row says pass, fail or not measured, keeps the raw value and its sample count, and a not measured row names the filed story that repairs the reading, so missing telemetry can never read as a pass. Goal 5's denominator (merged story PRs in the window) is not in flow (docs/features.tsv:62; flow_throughput.py:110 has no merged count): record Goal 5 as not measured and file that repair story, never divide by builds or epic totals. The checkpoint file carries no `covers:` or `done:` field, so retro-gate's check cannot read it as the retro.

**Done when:**
- board/retros/v0.31.0-checkpoint.md is on main. Its Checkpoint section has one row for each of Goals 1 to 9, each with pass, fail or not measured, the raw value and sample count, bar, flow section and features.tsv row, plus ci_health against the v0.30.0 window and the predictions section's rows.
- Each goal that fails or is not measured names a story slug that is on the board or merged; Goal 5's names the merged story-PR denominator story.
- The file has no `covers:` or `done:` field.
- The user's answer on turning features back is in the file. Each feature turned back links its config PR and is listed for the retro.
