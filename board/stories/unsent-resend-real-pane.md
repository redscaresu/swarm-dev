---
kind: lead
status: blocked
epic: liveness-signals
depends_on: [unsent-brief-resend]
needs: [unsent-brief-resend: the resend pass in bin/lib/lifecycle.sh:wait_lead]
touches: []
estimate_lines: 0
easy: true
---

# Lead: Enter submits a collapsed paste in a real herdr pane

The resend is shown only against stubs in unsent-brief-resend. Once it merges and the plugin carrying it is installed, the lead pastes a long brief into a real idle agent pane without submitting it, runs the resend pass, and checks that the brief is submitted once and that a pane with an unrelated paste after a finished brief is left alone. 'Signals must be true' (the epic's constraint) asks for one real check.

**Done when:**
- The lead records on this story's PR or note one real pane where the resend submitted an unsent brief exactly once, and one where an unrelated paste after a finished brief was not submitted.
