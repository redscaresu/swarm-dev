---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [go-module]
stage: v0.32.0
---

# Goal 9

The packages that hold the rules start no process and touch no file: they take four interfaces (agent runner, code host, repo, store). Time comes from one clock package. CI fails code that breaks either rule, and a protected package that leans on code the user does not merge.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** The four interfaces exist, each with one named package that may implement it. A CI check fails a branch where a rules package imports os/exec, file calls, net or an adapter package, and a branch where any package but the clock reads the time. It also fails one of the four protected packages importing an internal/ package outside the four that is not on a short list the check prints (the interfaces, the clock, the store's types). Each is shown red on a throwaway change, and the check prints the packages it covers. A Go test shows the clock honours SWARM_DASH_NOW and sleeps honour SWARM_SLEEP_SCALE.

**Out of scope:**
- A second implementation of any interface, or anything shaped for Kubernetes (HLD:88-89,174-175)
- Full implementations: each port adds the methods it needs
- Removing scripts/lint's python-clock rule (bash-retired)

**Constraints:**
- stage: v0.32.0.
- Exactly one implementation of each: herdr, gh, git, and .swarm/ with the board's files (HLD:169-175).
- git, gh, herdr, claude and codex stay subprocesses found on PATH, so the tests' stubs keep working (HLD:335-336).
- The clock matches bin/lib/clock.py. SWARM_SLEEP_SCALE keeps its check and message (bin/swarm.sh:120-121).
- The import check covers every rules package by a rule on the tree, not a hand list of today's packages (rules.md:11).
- A rule of the guard, merge, the release gates or the agents' environment may not sit in a package the user does not merge: ship-gates fixes the four paths, and this check keeps the code inside them.
- The checks add no LLM cost (rules.md:29).

**Your part:**
- None, if the checks run inside go-module's required job. If they are their own check, you add it to the ruleset.
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.

**Areas:**
- internal/ (interfaces, clock)
- the Go checks script or job
- AGENTS.md
