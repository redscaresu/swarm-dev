---
kind: code
status: blocked
epic: go-layers
depends_on: [go-interfaces]
needs: go-interfaces (the covers lines in internal/layers/classes_test.go)
touches: [.github/workflows/go.yml:go-checks steps (a step after go test)]
estimate_lines: 20
easy: true
---

# Print what the Go layer checks cover on every go-checks run, green ones too

Uses the classes test's 'covers <pkg> as <class>' lines from go-interfaces (internal/layers/classes_test.go). go-checks runs go test ./... without -v, so a passing test's t.Log never shows (.github/workflows/go.yml:103-105), and the epic says the check prints the packages it covers. Adds one go-checks step after go test, gated like the steps around it: go test -count=1 -v ./internal/layers/ into a file under RUNNER_TEMP, then print the file. It fails when go test fails or the file has no covers line, so a renamed test cannot print nothing and pass. It prints every layer test's log, so the allowed lists, the clock exemption and the short list appear as later stories add them. No new action and no ${{ }} in the script, so zizmor has nothing new to judge. .github/ is protected, so swarm.sh merge holds the PR for the user. The repo is public and the step runs on the standard Linux runner, so it costs nothing (HLD:460-461; go-actions-bill checks the bill). Break: run the step's script on a worktree copy whose classes test logs no covers line; it must fail.

**Done when:**
- The story PR's go-checks log shows the new step, green, with a covers line for each of cmd/swarm, internal/iface, the four adapters, internal/clock and internal/layers. The step's script, run by hand on a worktree copy whose classes test logs no covers line, exits non-zero. The story PR says it used the worktree copy.
- scripts/select-tests.sh --run passes
