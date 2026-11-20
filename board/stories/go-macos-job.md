---
kind: code
status: blocked
epic: go-module
depends_on: [go-module-build]
needs: go-module-build (go.mod and cmd/swarm's Go test for `go test ./...`, and tests/build_test.sh for the subset)
touches: [.github/workflows/macos.yml]
estimate_lines: 80
easy: true
---

# A macOS job runs the Go tests and a chosen subset of the bash tests under macOS's bash 3.2

Uses go.mod, cmd/swarm/main_test.go and tests/build_test.sh from go-module-build.
- Put the job in a new file, .github/workflows/macos.yml: one job, `macos-tests`, on a named macOS arm64 image. Two of the four binaries are for macOS, and every job today runs on Linux (HLD:291-292; ci.yml). binary-fetch adds its quarantine case to this file. Its Areas say ci.yml, so note the change on its board PR.
- Copy ci.yml's triggers and permissions, and its checkout and board-only gate (ci.yml:24-37). Add setup-go, pinned by SHA, with go-version-file: go.mod and cache: false. The gate skips steps, never the job. No step has continue-on-error.
- bash 3.2 first on PATH: a single file cannot go first on PATH, and the runner's Homebrew bash 5 wins otherwise (critic). A step links /bin/bash into a new `$RUNNER_TEMP/bash32` directory and writes that directory to `$GITHUB_PATH`, which puts it first for every later step. `make test` runs `bash scripts/test.sh` (Makefile:35) and the tests start with `#!/usr/bin/env bash`, so both find it.
- Steps: `go test ./...`. Then a step that prints `bash --version` and fails unless it says version 3.2 (HLD:340). Then the subset, run with `make test TESTS="<files>" JOBS=2`.
- Keep the subset in one env var in macos.yml, with a comment that says why each file is there. Start from tests/build_test.sh (the build contract on BSD tools), tests/test_helpers_test.sh (the prelude every test sources) and tests/env_allowlist_test.sh (the agents' environment). Keep it small. Drop a file only with the reason in the PR. binary-wrapper and binary-fetch add theirs later.
- No costs: money. The repo is public (gh api, 2026-11-20), and GitHub does not bill standard hosted runners on public repos. go-actions-bill checks the real bill after a week.
- Red proof, from a throwaway draft PR off this branch: a commit that breaks the Go test turns macos-tests red at the go test step. A second commit undoes that and breaks one subset bash test, with Go unchanged, and turns it red at the subset step (codex). A draft PR against this branch that changes only one board/ file shows it green with the steps skipped. Put the run URLs in the PR body, then close both PRs and delete their branches.
- zizmor must pass. The PR is held for the user (.github/ is a protected path).

**Done when:**
- macos-tests is green on this story's PR, on a macOS arm64 runner. Its log shows bash 3.2 from the version step, `go test ./...` passing and an ok line for each subset file. On the throwaway PR, a broken Go test turns it red at the go test step, and a broken subset bash test with Go unchanged turns it red at the subset step. The version step fails when the bash32 link is left out (shown on the throwaway PR or in a run on this branch). A board-only PR against this branch gets it green with the steps skipped. The run URLs are in the PR body. macos.yml has no continue-on-error. zizmor passes on macos.yml.
- scripts/select-tests.sh --run passes
