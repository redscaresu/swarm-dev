---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [bin/lib/lifecycle.sh:upgrade_state, tests/upgrade_test.sh]
easy: true
estimate_lines: 100
---

# upgrade restarts an agent whose turn has ended, even while its background jobs keep it busy

On 2026-10-22, the 0.25.0 upgrade (`swarm.sh upgrade`, no argument) moved only conduct-safer-faster-swarm. Two later runs left the backlog conductor and every builder on the old version. All of them sat at an empty prompt with their turn over, but each had background shells running (a `make test`, a `wait-pr`, a conductor's `watch` or `wait`). `claude agents --json` reports a session with running background shells as `busy`, and upgrade_state (bin/lib/lifecycle.sh:1892) treats `busy` as never to be interrupted. A conductor always has a wait running, so upgrade could never move one. The user saw them all as finished. The lead had to have the user run a one-off copy that read `busy` as idle.

When Claude Code says `busy`, upgrade_state also checks whether the turn has ended. Read the session's log, the way `api_stopped` reads it: the last assistant entry has ended its turn, and no tool call is waiting for its result. If so, the agent counts as idle. A turn still in progress, or one waiting on a prompt, stays busy. The restart already tells the agent its background commands stopped and to start them again (docs/reference.md § upgrade), so nothing is lost. Say so in docs/reference.md, and drop the line saying a busy builder is never interrupted where it no longer holds.

**Done when:**
- tests/upgrade_test.sh: with a stub `claude agents` reporting `busy`, a session log whose last assistant entry ended its turn reads as idle, and the agent is restarted and told to start its background commands again. A log ending in a tool call with no result reads busy and is left alone. A session waiting on a prompt stays busy.
- docs/reference.md's upgrade paragraph says an ended turn with background jobs is restarted.
