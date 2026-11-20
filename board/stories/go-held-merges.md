---
kind: lead
status: ready
epic: go-module
depends_on: []
touches: []
estimate_lines: 0
easy: true
---

# You: merge go-module-build's, go-checks-ci's and go-macos-job's PRs when swarm.sh merge holds them

Ready at once, with no depends_on: its step comes while those three stories are still open, so an edge on them would make it ready only after the step it holds (critic). The step moves here from go-required-checks.
- go-module-build changes .github/workflows/ci.yml and the root Makefile. go-checks-ci and go-macos-job each add a file under .github/workflows/. All three are protected paths (bin/lib/board.sh:2455-2464), so swarm.sh merge holds each one for you under merge = agent.
- Lead: before you hand one over, check that its checks are green on its head and its review agent passed it.
- **You:** merge each held PR.

**Done when:**
- The PRs of go-module-build, go-checks-ci and go-macos-job are merged by the user, each with its checks green on its head.
