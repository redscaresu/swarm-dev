---
kind: code
status: ready
epic: conductor-hands-off
depends_on: []
touches: [bin/lib/merge.sh:watch_prs, bin/swarm.sh:watch usage line, docs/reference.md:watch lines, tests/watch_opened_test.sh (new), tests/review_test.sh:watch --epic and --backlog section, tests/queue_test.sh:watchrun fixture, tests/escalate_triggers_test.sh:heads fixture]
estimate_lines: 150
easy: false
---

# watch --epic and --backlog return once when a story PR opens

watch_prs (bin/lib/merge.sh:1518-1637) returns on a conflict, a red-head step-up, finished checks, a stall, a queued: line or a waiting agent, never on a PR opening (merge.sh:1556-1597). The conductor brief will start review-<slug> when a story's PR opens, so add that event. With --epic or --backlog only (the lead's bare watch leaves review starts to the conductor), the first poll that lists an open story/<slug> PR in watch's scope with no `opened <owner/repo>#<n>` line in watch-seen records that line, prints `<owner/repo> #<n> <branch> opened` and returns 0. Each PR once. Check it before the conflict and check-run reads, so it costs no gh call beyond watch_rows' list. Existing watch --epic/--backlog tests expect another first line: seed their watch-seen with the opened lines rather than change what they assert. Document the line in docs/reference.md's watch lines and the watch usage line in bin/swarm.sh.

**Done when:**
- tests/watch_opened_test.sh (new), gh stubbed to list an open story/a PR of epic e: `swarm.sh watch --epic e` prints `o/svc #<n> story/a opened` and exits 0; a second `watch --epic e` on the same stub does not print it again. Fails on today's watch, which prints `checks finished` or nothing.
- The same test: `watch --backlog` reports a no-epic story's PR the same way; `watch --epic e` never reports another epic's story PR; the bare `swarm.sh watch` prints no `opened` line.
- tests/review_test.sh's watch section, tests/queue_test.sh and tests/escalate_triggers_test.sh assert the same lines as before (only their watch-seen fixtures change).
