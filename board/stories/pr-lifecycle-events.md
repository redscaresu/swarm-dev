---
kind: code
status: blocked
epic: telemetry-writers
depends_on: [events-outcome-helper]
needs: [events-outcome-helper: append_event key=value fields and the outcome()/fields() readers in bin/lib/events_outcome.py (telemetry-readers)]
touches: [bin/lib/merge.sh:watch_prs (opened line: pr-opened event), bin/lib/merge.sh:wait_pr (green exit: first-green event), tests/watch_opened_test.sh:pr-opened cases, tests/wait_pr_test.sh:first-green cases, docs/reference-logs.md:read-only exception sentence (Logs and outcomes)]
estimate_lines: 160
easy: false
---

# pr-opened from watch's opened line and first-green from wait-pr's green exit, once per PR

Builds on telemetry-readers' contract (append_event's key=value fields, its separator, bin/lib/events_outcome.py outcome() and fields()), merged before this epic starts (the epic's depends_on). Builders open PRs with a raw gh pr create, so no swarm.sh command runs then (contradiction 27). `pr-opened`, target the slug, outcome the PR URL, is written at watch_prs' opened line (merge.sh:2775), which its seen file already makes once per conductor watch. `first-green`, target the slug, outcome the head SHA, is written at wait_pr's green exit (merge.sh:2195) once per PR, with its own seen marker under .swarm, since wait-pr runs again and again. The slug comes from the PR's branch story/<slug>, read where wait_pr already reads the PR, never by a new gh call per poll; a PR on no story branch writes none. watch and wait-pr stay in READ_ONLY_COMMANDS (main logs nothing for them, as for wait's nudge lines); the Logs doc's read-only exception sentence names both. A failed write never changes either command's output or exit.

**Done when:**
- tests/watch_opened_test.sh: a conductor's watch that prints `opened` writes one pr-opened line with the slug and URL; a second watch over the same PR writes none; the lead's bare watch writes none.
- tests/wait_pr_test.sh: a green wait-pr on a story PR writes one first-green line with the slug and SHA; a second green wait on that PR writes none; a red exit writes none.
- With events.tsv unwritable, both commands print and exit as before.
- tests/events_test.sh's READ_ONLY_COMMANDS and dispatch arm checks pass unchanged.
- Copy-aside proof: dropping first-green's seen marker turns the second-wait case red.
- docs/reference-logs.md's read-only exception sentence names both events; tests/doc_check_test.sh passes.
