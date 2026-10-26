---
kind: code
status: ready
epic: review-loop
depends_on: []
touches: [bin/lib/build.sh:review_agent, bin/lib/build.sh:review_round, bin/swarm.sh:review-agent dispatch arm, bin/swarm.sh:main event target, bin/swarm.sh:usage header, docs/reference.md:Commands review-agent row, tests/review_agent_test.sh:next round cases, tests/flow_test.sh:review-agent:next fixture]
estimate_lines: 230
easy: false
---

# review-agent --next starts the next review round in the same session

The round-2 mechanism: the review agent loops in its own session. New mode `swarm.sh review-agent --next <slug> <PR URL>`, run from review-<slug>'s own pane, starts no agent. It applies review_agent's head checks (worktree at the PR head, nothing uncommitted), moves the last findings file to .prev, writes .swarm/reviews/<slug>.head, and prints the round and that round's instruction (codex alone from round 2, as review_brief's cr line). review_round (build.sh:614-617) counts rounds the way the ladder does: a findings tell counts when it is ok or 'herdr sent it the brief' (as findings_told, agents.sh:1708-1712), and so does a findings step-up (escalate 'ok (findings-N: ...)', lifecycle.sh:792) that carried the findings in place of a tell. The count still spans step-ups (it resets only at the story's start). review_agent's refusal while review-<slug> is live (build.sh:575-585) stays for every other caller. bin/swarm.sh main logs --next as `review-agent:next <slug> ok (round <n>)`, never as review-agent, so flow's review-agent starts and review_wait (flow_throughput.py:100, flow_review_loops.py:96) do not read a round as a new review start. Document the mode in bin/swarm.sh's usage and docs/reference.md's Commands row; the owner stories rewrite § Building's review paragraph.

**Done when:**
- tests/review_agent_test.sh: --next from review-<slug>'s pane after one ok tell:findings prints round 2 and the codex-alone instruction, writes the PR head to .swarm/reviews/<slug>.head, moves <slug>.md to <slug>.md.prev, and starts no agent (the herdr stub logs no start).
- After a findings tell logged 'herdr sent it the brief', --next prints the next round, not the same one again; after two ok findings tells and a findings-3 step-up, it prints round 4. Each check fails on today's review_round.
- --next from any other pane, with no review-<slug> listed, or with the worktree off the PR head or uncommitted, refuses and changes no file under .swarm/reviews.
- events.tsv gets `review-agent:next <slug> ok (round 2)`, and a plain review-agent still refuses while review-<slug> is live with no findings file.
- tests/flow_test.sh: a fixture with one review-agent start and two review-agent:next lines gives the same review_wait and review-agent start count as one without them; tests/flow_review_loops_test.sh and tests/doc_check_test.sh pass.
