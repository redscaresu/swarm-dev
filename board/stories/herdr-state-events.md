---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [restore-keeps-launch-flags, api-error-stall]
touches: [bin/lib/agents.sh:wait, bin/lib/herdr_events.py (new), tests/]
---

# wait listens to herdr's event stream instead of polling

`wait` polls `herdr agent wait` in 60 s slices and scrapes pane text for stalls (agents.sh:612-690).
herdr's socket method `events.subscribe` pushes `pane.agent_status_changed`, `pane.exited`,
`pane.closed` and `pane.output_matched` (herdr socket-api docs). A small python client
(herdr_events.py) lets `wait` return at once when an agent goes idle or blocked, or its pane dies;
`agent list`'s `state_change_seq` unchanged over N polls is the fallback stall signal.

**Done when:**
- With a fake socket emitting agent_status_changed to blocked, `wait` returns `blocked` without a poll; a pane.closed returns `gone`.
- With no socket, wait falls back to today's polling (existing wait tests pass unchanged).
