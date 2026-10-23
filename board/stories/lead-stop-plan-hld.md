---
kind: code
status: ready
epic: plan-hld
depends_on: []
touches: [hooks/lead-stop.sh:started and plan_drafted and header comment, tests/lead_stop_test.sh]
estimate_lines: 90
easy: true
---

# The lead's turn cannot end with plan-hld or hld unstarted

Needs nothing from another story: the tests stub next. Run the epic's **Checks before every stage**.

hooks/lead-stop.sh's started() (the case at :180-189) gets two arms:
- `plan-hld) <drafted> || live "" "plan-${subject}" 0`, mirroring plan-epic. Parameterise plan_drafted (:155-177) rather than copy it: it takes the board-PR branch prefix and the file whose mtime the critic's answer must beat, `board/scope-<epic>` with `<board>/epics/<epic>.md` for plan-epic, and `board/plan-<hld>` with `<board>/hld/<hld>.md` for plan-hld. The critic stays at `.swarm/<subject>/critic.json`.
- `hld)` is started when the finish board-PR worktree `<repo>-wt/_board-finish-<subject>` exists. Today `*) return 0` (:187) lets the lead stop with `hld <hld>` printed and never run `swarm.sh finish`.

plan-hld-command builds to this contract: tab `plan-<hld>`, board PR `plan-<hld>`, critic `.swarm/<hld>/critic.json`. The header comment (:9-23) names plan-hld and hld. Lookups go through the hook's existing within/swarm wrappers (tests/timeouts_test.sh:264,314 pin their shape).

**Done when:**
- tests/lead_stop_test.sh, with `STUB_NEXT='plan-hld H'`: blocks the stop and names the line when no agent runs; allows it when an agent runs in tab plan-H or plan-H-2, when .swarm/H/critic.json parses and is newer than <board>/hld/H.md, or when board/plan-H is past base; blocks when critic.json is older than the HLD or is not JSON, or when board/plan-H is at base. Each case writes one `lead-stop plan-hld blocked|allowed` line to events.tsv.
- With `STUB_NEXT='hld H'`: blocks with no `_board-finish-H`, allows with it.
- Every plan-epic case passes unchanged.
- `make test` passes.
