---
kind: code
status: blocked
depends_on: [conductor-lanes]
needs: "conductor-lanes: conduct --lane, lane conductor names and the story's lane (bin/lib/build.sh, bin/lib/board.sh)"
touches: [bin/lib/board.sh:next_step conductor arms, bin/lib/merge.sh:the start of conductors after a board merge, bin/lib/agents.sh:status and wait for lane names, bin/lib/lifecycle.sh:upgrade rounds, tests/conductor_lanes_start_test.sh (new), docs/reference.md:next and status entries, hooks/lead-stop.sh:started's conduct arm and the step and why it reads, commands/swarm.md:the conduct step]
estimate_lines: 150
easy: false
---

# The swarm starts and watches every lane's conductor

Needs, from conductor-lanes: `conduct --lane`, the lane names and each story's lane.

- Where swarm.sh starts a conductor for ready work today, it starts one for each lane that has ready stories or open PRs: `next`, and a board merge that readies stories (#360 and #365). `next` prints one `conduct <epic> --lane <k>` step per lane that has no conductor.
- `status`, `wait`, `wait --until-report`, collect and `upgrade` handle lane conductors like any other conductor. An epic counts as collected once every lane has reported.

**Done when:**
- tests/conductor_lanes_start_test.sh: with `conductor_lanes = 2` and ready backlog stories in both lanes, a board merge starts both lane conductors. `next` with one lane running prints the other lane's `conduct` step. With `conductor_lanes = 1` the steps are unchanged.
- `make test` passes.
