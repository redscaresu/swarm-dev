---
kind: code
status: blocked
epic: delivery-liveness
depends_on: [rules-file-briefs]
needs: [rules-file-briefs (order only: both edit bin/lib/build.sh:conduct_brief)]
touches: [bin/lib/agents.sh:tell_agent gone refusals, bin/lib/build.sh:conduct_brief tell paragraph (new), commands/swarm.md:a could-not-reach refusal is final, docs/reference.md:tell paragraph in Building, tests/tell_queue_test.sh:gone refusal cases, tests/epic_briefs_test.sh:tell refusal phrase]
estimate_lines: 130
easy: false
---

# A tell to a gone agent is refused once, naming its exit

Goal 2. tell_agent's two gone refusals stay one die per call (agents.sh:1812 no pane; agents.sh:1834 state gone), and each names where the agent's exit comes from. For a builder that is `swarm.sh wait --lead`'s no-agent: line; for review-<slug> its no-review: line; for conduct-<epic> `swarm.sh next`'s `no conductor started: <conductor> is gone` line. Reword 1834 to start `could not reach <name>:` like 1812. Today it reads `<name>: its Claude session has ended (gone)`, and no test or reader pins that text (only a comment, agents.sh:2164). The fallthrough at 1837 also starts `could not reach` and is left as it is. Add a tell paragraph to conduct_brief, which has none today (build.sh:1528-1606), and a sentence to commands/swarm.md: a `could not reach` refusal is final, so list the story under no agent and never tell it again. Queued tells to a gone agent already go to the lead once (tell_drop agents.sh:2182-2183, tell_undelivered agents.sh:2321): the three-poll test guards that, it adds nothing. review_brief is not touched: its 'refuses for any other reason, stop' (build.sh:1390) already stops the review agent, and merge-safety and review-rounds-end edit that function. No change to tell's delivery or queue (HLD Non-goals). Order only: rules-file-briefs (#717) edits conduct_brief's rules heading, so this story waits for it to merge. A note to a conductor whose pane is open but whose session is gone is refused too: tell_agent checks the conductor's state before it accepts a note (today kind=note returns before tell_state).

**Done when:**
- tests/tell_queue_test.sh: a tell to a builder with no pane exits 1 with one refusal that starts `could not reach <name>:` and names `swarm.sh wait --lead`'s `no-agent:` line; for review-<slug> it names `no-review:`; for conduct-<epic> it names `swarm.sh next`'s `no conductor started:` line (three cases).
- A tell to an agent whose state reads gone exits 1 with one refusal that starts `could not reach <name>:` and names the same per-kind exit (three cases); each call adds exactly one tell:<kind> event.
- False case: a tell to a live busy builder prints `queued:`, exits 0 and logs no refusal (agents.sh:1831).
- A fixture with a gone builder and one queued findings tell: three `wait --lead` polls print exactly one `tell undelivered:` line, and the number of tell:findings events for that builder after the third poll equals the number after the first.
- The rendered conductor brief and commands/swarm.md say a `could not reach` refusal is final (list the story under no agent, never tell it again); tests/epic_briefs_test.sh pins the phrase, and deleting the sentence from conduct_brief turns that test red (copy-aside proof).
- docs/reference.md's tell paragraph in Building names the per-kind exit; shellcheck, make check and scripts/select-tests.sh --run pass.
- `swarm.sh tell conduct-<epic> note <file>` to a conductor whose pane is open and whose session is gone is refused as could not reach, and logs no ok.
