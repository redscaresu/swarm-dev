---
kind: code
status: blocked
blocked_by: [main-checkout-guard]
epic: safer-faster-swarm
depends_on: [main-checkout-guard]
touches: [hooks/merge-guard.sh, tests/merge_guard_test.sh]
easy: true
estimate_lines: 40
---

# The guard stops an agent killing processes by pattern

On 2026-10-17, an infrafactory builder (#610) ran a `pkill` that matched another session's
`sleep 30`, and killed the lead's CI wait (exit 137). The lead's wait never reported, and nothing
said why until the conductor's report. Processes on this machine belong to many sessions, so a
match by name or pattern can hit any of them.

In a swarm agent's session (SWARM_AGENT set), hooks/merge-guard.sh exits 2 on `pkill`, `killall`,
and `kill` with a `$(pgrep ...)` or `$(pidof ...)` argument. It logs `guard-blocked: pattern-kill`
like the other rules. `kill <pid>` with a literal or a `$!`/variable PID passes: an agent may stop
what it started. The lead's session is not an agent and is not blocked.

**Done when:**
- tests/merge_guard_test.sh: with SWARM_AGENT set, `pkill -f sleep`, `killall sleep` and `kill $(pgrep sleep)` exit 2. `kill $!`, `kill 1234` and `echo pkill` pass. Without SWARM_AGENT, all pass.
- Each block appends `guard-blocked: pattern-kill` to events.tsv (asserted).
