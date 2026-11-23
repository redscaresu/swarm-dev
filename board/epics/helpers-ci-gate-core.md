---
status: later
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-ci-gate
depends_on: [foundation-exit, helpers-shared-base]
---

# ci_gate's shared Go core lands in internal/merge, run by nothing yet

The parts every ci_gate subcommand uses (gh, the Python value codec, reads, globs, workflow triggers, the `_ci-gate` entry and its signal handling) exist as Go with tests. No bash call runs them yet.

A child of [helpers-ci-gate](helpers-ci-gate.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** internal/merge has gh.go, pyvalues.go, reads.go, globs.go and triggers.go, each with Go tests. cmd/swarm/cigate.go registers `_ci-gate`, which ignores TERM, HUP and INT across the span ci_gate.py ignores them, and leaves SIGQUIT as it is. tests/ci_gate_cases_test.sh runs base.cases on the Python, and fails naming go when the seed is marked go. No file under bin/ runs the Go.

**Stories:**
- [ci-gate-go-gh](../stories/ci-gate-go-gh.md)
- [ci-gate-go-pyvalues](../stories/ci-gate-go-pyvalues.md)
- [ci-gate-go-reads](../stories/ci-gate-go-reads.md)
- [ci-gate-go-globs](../stories/ci-gate-go-globs.md)
- [ci-gate-go-triggers](../stories/ci-gate-go-triggers.md)
- [ci-gate-go-entry](../stories/ci-gate-go-entry.md)
- [ci-gate-go-signals](../stories/ci-gate-go-signals.md)

**Out of scope:**
- The subcommands themselves (helpers-ci-gate-modes, helpers-ci-gate-main)
- The poll cache (helpers-ci-gate-cache)

**Your part:**
- You merge every port here (protected merge package). The carve-out covers every story, as in the parent.

**Areas:**
- ci-gate-go-gh: [internal/iface/iface.go:CodeHost, internal/iface/iface.go:package comment, internal/adapter/gh/gh.go:Host, internal/adapter/gh/gh_test.go, internal/merge/gh.go, internal/merge/gh_test.go]
- ci-gate-go-pyvalues: [internal/merge/pyvalues.go, internal/merge/pyvalues_test.go]
- ci-gate-go-reads: [internal/merge/reads.go, internal/merge/reads_test.go]
- ci-gate-go-globs: [internal/merge/globs.go, internal/merge/globs_test.go]
- ci-gate-go-triggers: [internal/merge/triggers.go, internal/merge/triggers_test.go, internal/merge/testdata/workflows]
- ci-gate-go-entry: [cmd/swarm/cigate.go, bin/ported/_ci-gate, internal/merge/cigate.go, internal/merge/cigate_test.go, tests/ci_gate_cases_test.sh, tests/ci_gate_cases/base.cases, docs/port/tests.tsv:tests/ci_gate_cases_test.sh row, scripts/test-map.tsv:internal/merge row]
- ci-gate-go-signals: [internal/layers/imports_test.go:allowedStd exception, internal/layers/testdata/imports:signals fixtures, cmd/swarm/signals.go, cmd/swarm/signals_test.go, internal/merge/cigate.go:deps, cmd/swarm/cigate.go:signals, AGENTS.md:Go layers rule, docs/port/README.md:bridge exception]
