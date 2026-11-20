---
kind: lead
status: ready
epic: go-module
depends_on: []
touches: [.claude/swarm/config:agent_env line (only if a GO* name is needed)]
estimate_lines: 0
easy: true
---

# Lead: Go 1.27.1 runs `go build` in a builder's pane before go-module's conductor starts

Needs no other story. Do it before `swarm.sh conduct go-module`. go-module waits on ship-gates, so there is time. No story depends_on this one: that edge would make go-toolchain-pane -> go-module-build -> go-checks-ci -> go-required-checks 4 stories deep (see contradictions).
- go.mod pins go 1.27.1, the Go already on this machine (/opt/homebrew/bin/go, go1.27.1 darwin/arm64; survey, 2026-11-19). To pin a newer patch, install it here first and change go-module-build's scope.
- Check in a pane started the way swarm.sh starts a builder (env cleaned to AGENT_ENV, `/bin/zsh -f`; bin/lib/agents.sh:388-397, launch_file :496). A hand-made stand-in shell is not enough (rules.md). In it: `go version` prints go1.27.1, `go env GOCACHE GOPATH GOTOOLCHAIN` resolve under HOME, and `go build` of a throwaway module in a temp dir writes its binary.
- Agents get PATH and HOME but no GO* name. If the pane needs one, add `agent_env = <names>` to .claude/swarm/config in a PR. **You:** merge that PR (.claude/ is a protected path).
- Paste the pane's output into this story file, then close it.

**Done when:**
- In a pane started the way a builder's is, `go version` prints go1.27.1 and a throwaway module builds. That output is in this story. If a GO* name was needed, the agent_env line is on main and a newly started pane shows the variable.
