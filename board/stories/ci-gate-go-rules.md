---
kind: code
status: later
epic: helpers-ci-gate
depends_on: []
touches: [internal/merge/rules.go, internal/merge/rules_test.go, tests/ci_gate_cases/base.cases:go mark, tests/ci_gate_cases/required.cases, tests/ci_gate_cases/age.cases]
estimate_lines: 290
risk: high
---

# Go that nothing runs: the base's rules and a commit's runs, and the base, required and age modes

Needs core's reads, gh, pyvalues and entry.
Adds base_rules (ADMIN_RULES, ADMIN_CLASSIC), required, is_req and by_rule (ci_gate.py:100-142, :697-727), and a commit's runs: sha_runs, run_path and ci_items (:658-665, :711-719). Registers base, required and age (:1007-1033). base_rules quotes the base as urllib.parse.quote(base, safe="") does: every byte but letters, digits and _.-~ (Go's url.PathEscape leaves more). required's reason embeds Python's exception text (:704; contradiction 6). Marks base.cases go and adds required.cases and age.cases.

**Done when:**
- (1) tests/ci_gate_cases_test.sh passes with base, required and age marked go: rulesets and classic protection, a part of the rules that cannot be read, a base named 'release/1.0+x', a status-only base commit, 'no check runs or statuses', a pending head (exit 2), and an unreadable finish time; age's times written relative to the run's clock. (2) Go tests of by_rule's split of a required check's runs from the rest, and of ci_items and sha_runs on a head with runs and statuses. (3) Each case file goes red on a worktree copy without .git where the Go alone is broken (base_rules dropping classic protection; age rounding up; the quote leaving '/'), and where ci_gate.py alone is; the PR quotes the FAIL lines. (4) gofmt -l . prints nothing, go vet ./... and go test ./... pass, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
