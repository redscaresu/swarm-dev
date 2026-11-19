---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [readers-exit]
---

# Starting an agent is Go: the agent command, panes and workspaces, the agents' environment and the rule that tells the lead's session

Then name-clash-all-starts lands on the Go.

Stage 3 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) agent has its marker, and agent_cmd and start_agent are gone (bin/lib/agents.sh:665-834). Every start still in bash (story, review-agent, conduct, step-up, restart) starts its agent through the binary. (2) An agent the Go starts gets exactly the environment tests/env_allowlist_test.sh expects: the AGENT_ENV names, the LC_, SWARM_ and XDG_ prefixes, a story's env:, the board's agent_env and the provider's settings, and nothing else. That test fails when one name is added to or dropped from the Go list. (3) Pane layout, agent names and a failed start's lines are the same on the fixtures (differential run clean). (4) lead_project is Go. hooks/lead-session.sh runs the binary's entry for it, find-only, and lead_caller and the two hooks that source it give the same answers on tests/lead_stop_test.sh and tests/user_caught_reminder_test.sh; with no binary lead-stop allows the stop and the reminder says nothing. (5) Then name-clash-all-starts, as a fix: true story: a clash fixture is refused and a non-clash fixture starts for each way an agent starts (agent, story, review-agent, conduct, step-up, step-up --resume and restart), and each case fails with the check removed.

**Out of scope:**
- tell (port-tell)
- story, conduct and review-agent (port-story, port-conduct, port-review-agent)
- close, restart and step-up (port-close, port-step-up)
- A second agent runner, or anything but herdr (HLD:88-89)

**Constraints:**
- Port rules P1 to P8.
- AGENT_ENV, AGENT_PREFIXES, AGENT_SET and HERDR_PANE_ENV (bin/lib/agents.sh:388-392) carry over exactly. Their Go package is protected, and the user merges it (HLD:457-458).
- lead_project (hooks/lead-session.sh:11) is sourced by bin/lib/lifecycle.sh:2634, and its first Go caller is lead_starts_pane (bin/lib/agents.sh:235). It is ported here, once, and the hook file becomes a wrapper in the same PR, so there is never a second copy. hooks/ is protected: the user merges it.
- name_clash runs only on swarm.sh agent starts today (board/stories/name-clash-all-starts.md:12). The check sits in the one Go start path, and port-story, port-review-agent, port-conduct and port-step-up keep its fixtures green.
- Locks: lead_agents_lock (bin/lib/agents.sh:240) and the bare mkdir locks at :1376 and :1675.
- herdr is named on 295 lines of agents.sh: all of it goes through the agent runner interface.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): none by its wording: the agents' environment is not on the list, and no story here names env:. You merge those PRs anyway (protected package).
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You merge the PRs that touch the protected agents' environment package and hooks/lead-session.sh.

**Areas:**
- internal/agentenv
- internal/ (agent runner, agent starts, lead session)
- bin/lib/agents.sh (own_panes to record_agent, deliver_prompt to session_took, free_agent_name to retire_agent)
- hooks/lead-session.sh
- bin/ (marker file)
- board/stories/name-clash-all-starts.md
- tests/
- docs/

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P2: The six port steps (HLD:250-262). A tests-only PR first rewrites the inside-reaching tests to drive swarm.sh from outside, passes on the bash, and shows each rewritten check can fail. The port PR then adds the Go, deletes the bash and Python it replaces, adds the command's marker file, repeats the mutation proofs on the Go, corrects every doc line that names a deleted file, and shows a clean differential run against the tree just before.
- P3: One copy of each rule (goal 3). When bash left behind still calls a ported rule, that bash runs the binary for it in the same PR, through a `_` entry.
- P4: The Go takes the same lock files the same way and writes the same file formats (HLD:337-338,447-449). While any bash caller of a lock is left, a test has the bash hold it while the Go waits, and the reverse.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P7: A folded or deferred item is its own fix: true story after its command's port, with a test that fails on the old behaviour. The stage's differential run names it, with the exact lines it changes, among the fix: true differences (HLD:60-67). Its story file is rewritten: Go touches, epic:, fix: true, and no 'Python rewrite' text (HLD:314-316).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.
