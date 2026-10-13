---
kind: code
status: blocked
blocked_by: [off-screen-nudge]
epic: agent-state-from-the-session
depends_on: [session-reader-and-wait, off-screen-nudge]
touches: [bin/swarm.sh (wait_agent, wait_conductor, a transcript auth check beside the session reader), tests/epic_test.sh (wait block), tests/next_test.sh (conductor block), commands/swarm.md (the wait step), docs/method.md (§ Building's wait paragraph), README.md (When `/swarm` stops for you)]
---

# `wait` returns `auth` when an agent stopped on an expired login

On 2026-10-13 a conductor and its builder both ended a turn on "Login expired · Please run /login"
at 16:45 and sat idle for two hours: wait_conductor treats an idle conductor with no report as still
going until its hour runs out, and nothing names the cause. An agent cannot fix this; only the user's
`/login` can. When a waited-on Claude agent's session reads idle (session-reader-and-wait) and its
transcript's last assistant entry is an authentication error (read from the session's .jsonl, the file
cost_report already finds; never the pane), `wait` and `wait_conductor` return `auth` at once and print
one line naming the agent. `/swarm` (commands/swarm.md) stops on `auth`, tells the user to run `/login`
and nothing else, and after the user says it is done sends each stopped agent a `resume` tell.
off-screen-nudge never nudges an agent whose last entry is an auth error.

**Done when:**
- With the claude stub's session `idle` and a fixture .jsonl whose last assistant entry is the auth error, `wait <builder>` and `wait conduct-<epic>` each print `auth` and exit within one slice, and the builder is not nudged. Shown red on the old code.
- A session idle after an ordinary turn (no auth error) is unchanged: a builder is nudged per off-screen-nudge, a conductor is waited on.
- The fixture's error entry is copied from a real transcript's shape (ids and text replaced), cited in the PR.
- commands/swarm.md's wait step, § Building and README's "When `/swarm` stops for you" say what `auth` means and that only the user's `/login` clears it.
