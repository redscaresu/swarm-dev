---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/layers/imports_test.go:allowedStd exception, internal/layers/testdata/imports, cmd/swarm/signals.go, cmd/swarm/signals_test.go, internal/merge/cigate.go:deps, cmd/swarm/cigate.go:signals, AGENTS.md:Go layers rule, docs/port/README.md:bridge exception]
estimate_lines: 220
risk: high
---

# The binary catches and ignores TERM, HUP and INT for ci_gate's stop, through one wiring file the layer check allows

Needs ci-gate-go-entry: the deps and the wiring.
queued and stop need signals (ci_gate.py:322-352): a TERM, HUP or INT is a stop while queued waits, and is ignored while stop runs. internal/layers allows os/signal and syscall to no package outside the four adapters (internal/layers/imports_test.go:16-21). This adds one narrow exception, as the bridge has for os/exec (:23-30): cmd/swarm/signals.go may import os/signal and syscall, and nothing else may (contradiction 5).
- cmd/swarm/signals.go: a context that a TERM, HUP or INT cancels, naming the signal; and a span during which those three are ignored.
- internal/merge's deps carry both as functions, so internal/merge imports no os/signal; `_ci-gate`'s wiring passes the real ones.
- AGENTS.md's Go layers rule and docs/port/README.md's line on the bridge's exception name the second one.

**Done when:**
- (1) TestImportsFixtures passes with new fixture lines: cmd/swarm/signals.go importing os/signal and syscall has no finding; another cmd/swarm file and a rules package importing os/signal each have one. It goes red with the exception widened to all of cmd/swarm. (2) A process test in cmd/swarm: a TERM sent while the context is armed cancels it, names TERM, and the process lives; a TERM, HUP or INT inside the ignored span does not end the process. (3) Each new test goes red on a worktree copy without .git where its rule is broken; the PR quotes the FAIL lines. (4) The humanizer ran over the AGENTS.md and README lines, as the PR says. (5) go test ./internal/layers/ passes; gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
