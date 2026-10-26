---
kind: code
status: ready
epic: stuck-work
depends_on: []
touches: [bin/lib/panes.py:prompt detection, tests/pane_prompt_test.sh (new), tests/fixtures/panes (new)]
estimate_lines: 150
easy: false
---

# panes.py tells a pane stuck on a prompt, a dialog, manual mode, a login or an API error

Detection only, no queue line (split from stuck-work-watch by the v0.28.0 retro rule). panes.py names a pane's last screen `prompt` (a Claude Code permission prompt, or a dialog such as 'Teach auto mode'), `manual` (manual mode, as left after a prompt is answered), `login` or `api-error`, else nothing; a pane mid-command or at an empty input box is nothing. Reuse panes.py's existing reads (the usage-limit dialog, api-error) rather than a second reader. Build fixtures from real pane text where session archives or .swarm logs hold it, else from Claude Code's prompt text, and say which in the PR.

**Done when:**
- tests/pane_prompt_test.sh (new) feeds each fixture to the classifier: each kind is named on its pane, and nothing on a pane mid-command and on an empty input box. Each check fails when its pattern is removed.
