---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/build.sh:conductor brief, bin/lib/merge.sh:watch_prs, bin/lib/board.sh:next_step, commands/swarm.md, tests/]
---

# A green PR is reviewed at once, and one left waiting is flagged

On 2026-10-18 ten swarm-dev PRs sat green and mergeable while the conductor worked through reviews
in batches ("wait for any of four reviews"); #265 waited from 02:18 to past 18:00. Nobody was told:
the lead's `wait --until-report` fires only on a report or a stop.

- Conductor brief: start a PR's review the moment its head is green and clean, with no batch and
  no cap below the number of green PRs; merge a PR the moment its latest head has passed review.
  Never hold a finished review result for the next batch.
- `watch_prs` (and the conductor's `wait`) returns `queued: #<n> green <m>m with no review` when a
  PR's head has been green and mergeable for `queue_minutes` (default 30, a config key) with no
  review agent on that head and no merge.
- `next`, for a project with a running conductor, prints the same line ahead of `wait`, and
  commands/swarm.md tells the lead to send it to the conductor.

**Done when:**
- A fixture with a PR green and clean for 31 minutes and no review agent makes `watch` and `next` print the queued line; with a review agent on that head, or at 29 minutes, they do not.
- The rendered conductor brief has the review-on-green and merge-at-once rules, and no batch wording (a test greps both).
