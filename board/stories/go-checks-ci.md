---
kind: code
status: blocked
epic: go-module
depends_on: [go-module-build]
needs: go-module-build (go.mod (setup-go's go-version-file), cmd/swarm for the checks to run over, and scripts/build.sh with its --list for the build-contract step)
touches: [.github/workflows/go.yml, cmd/swarm/main.go, cmd/swarm/main_test.go]
estimate_lines: 160
---

# go.yml's go-checks job fails a PR on unformatted Go, a vet, staticcheck or errcheck finding, a line in go.sum, a module beside the standard library, a failing Go test or a broken build contract

Uses go.mod, cmd/swarm and `scripts/build.sh --list` from go-module-build.
- Put the checks in a new file, .github/workflows/go.yml, so ci.yml's lines stay free for other epics. go-layers adds its checks as steps of this job. Copy ci.yml's triggers, its top-level `permissions: contents: read` and its job permissions (ci.yml:3-22). One job, `go-checks`, on ubuntu-latest.
- Steps: checkout and the board-only gate, copied byte for byte from ci.yml:24-37. Then actions/setup-go, pinned to a verified commit SHA, with go-version-file: go.mod, cache: false, `id: setup` and `if: steps.gate.outputs.board_only != 'true'`. The gate skips steps, never the job. That way a board-only or version-only PR still reports go-checks green: a required check that never reports blocks the PR.
- Make each check its own step with `if: ${{ !cancelled() && steps.setup.outcome == 'success' }}`, so a single run shows every failing check:
  - `gofmt -l .` prints nothing;
  - `go vet ./...` passes;
  - staticcheck passes;
  - errcheck passes;
  - `go build ./...` passes;
  - `go test ./...` passes;
  - `scripts/build.sh` runs, the files in dist/ equal --list's asset names plus its checksums file, and `shasum -a 256 -c` passes in dist/;
  - last, after the tools are installed and the build and tests ran: go.sum is absent or zero bytes, and `go list -m all` prints exactly `github.com/redscaresu/swarm-dev`. A require with a replace to a local directory adds no go.sum line, so the go.sum step alone does not hold the standard-library rule (HLD:105-106, 331; codex).
- staticcheck: download the linux/amd64 release tarball at a pinned version (2026.2.2 when read on 2026-11-19). Check it against a sha256 written in the workflow before it runs. Take the hash from the release's .sha256 asset, and confirm it against the tarball you downloaded.
- errcheck has no release assets. Pin `github.com/kisielk/errcheck@v1.30.0` and its module h1: hash. Check that `go mod download -json` reports that hash, then `go install` it from outside the module. setup-go v6+ sets GOTOOLCHAIN=local, so a tool whose go line is newer than 1.27.1 fails to install: pick a version that installs.
- Put a comment beside the two pins: dependabot does not watch them (.github/dependabot.yml has only github-actions), so they are bumped by hand.
- Do not change scripts/board-only.sh: a PR that changes go.yml changes a path outside board/, so the gate already runs everything (scripts/board-only.sh:34-38).
- If the new checks find anything in go-module-build's code, fix it in this PR; cmd/swarm/main.go and main_test.go are in touches for that (critic).
- Red proof. CI runs only on pull_request and on a push to main (ci.yml:3-10), so a bare branch runs nothing.
  - Push throwaway/go-checks-red from this story's branch with one commit that breaks each of the seven: an unformatted file, a vet finding, a staticcheck finding, an ignored error, a line in go.sum, a require with a replace to a local module, and a failing test. Open it as a draft PR. Check in the log that each step fails on its own break; if a step fails only because of another break, give its break a commit of its own.
  - A second commit changes both pinned hashes.
  - A draft PR against this story's branch that changes only one board/ file must show go-checks green, with its steps skipped.
  - Put the run URLs and the step results in this PR's body. Then close both draft PRs and delete their branches.
- zizmor must pass. The PR is held for the user (.github/ is a protected path).

**Done when:**
- go-checks is green on this story's PR. On the throwaway PR, each of the gofmt, go vet, staticcheck, errcheck, go test, go.sum and module-list steps is red, each on its own break, and the run URL is in this PR's body. With both pinned hashes changed, the staticcheck and errcheck steps fail before either tool runs. On a board-only PR against this branch, go-checks reports green with every check step skipped. zizmor passes on go.yml.
- scripts/select-tests.sh --run passes
