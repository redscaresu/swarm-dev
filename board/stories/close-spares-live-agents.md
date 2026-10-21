---
kind: code
status: ready
risk: high
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/lifecycle.sh:close_tabs, bin/lib/lifecycle.sh:close_panes, tests/]
---

# Closing a conductor never closes a live builder

On 2026-10-21 `swarm.sh close conduct-safer-faster-swarm` closed every tab of the epic (close_tabs,
lifecycle.sh:792) and with them 12 builders whose PRs were open. Their work survived only because it
was on disk. herdr's CLI `tab close` skips the TUI's last-pane confirmation.

- `close <conductor>` closes the conductor's own pane only (`herdr agent get <name>` → `pane close`).
- Before any `tab close`, list the tab's panes; if one holds an agent that is working, or whose story
  has an open PR, refuse naming each, unless `--all` is passed. Without `--all`, survivors may be
  moved out first with `herdr pane move <p> --new-tab`.

**Done when:**
- A fixture with a conductor tab and a builder tab whose story has an open PR: `close <conductor>` closes only the conductor's pane and prints the builder as kept; with `--all` it closes both.
- An epic whose builders have all merged closes every tab as today.
