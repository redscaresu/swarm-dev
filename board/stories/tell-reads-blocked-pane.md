---
kind: code
status: blocked
epic: stuck-work
depends_on: [pane-prompt-classifier, tell-from-review-pane]
needs: [pane-prompt-classifier: the pane classifier in bin/lib/panes.py, tell-from-review-pane (review-loop): tell_agent as it leaves it]
touches: [bin/lib/agents.sh:tell_agent, tests/tell_blocked_test.sh (new)]
estimate_lines: 80
easy: true
risk: high
---

# tell checks the pane before refusing an agent listed as blocked or waiting

Uses pane-prompt-classifier's classifier, and tell_agent as review-loop's tell-from-review-pane leaves it. A dialog the user cleared leaves the status at blocked, and on 2026-10-26 no tell reached #540's builder until the user typed into its pane (v0.28.0 retro). tell_agent refuses both `waiting*` (a session state) and herdr:blocked in one arm (bin/lib/agents.sh:1642). For either, read the pane once: send the tell only when the classifier names nothing and the pane shows an empty input box; refuse as today otherwise, so no tell's keys can answer a permission prompt.

**Done when:**
- tests/tell_blocked_test.sh (new), for herdr:blocked and for a session waiting state: an agent whose pane shows an empty prompt receives the tell; one whose pane shows a permission prompt is refused and sent no keys. Each check fails with the pane check removed or loosened.
