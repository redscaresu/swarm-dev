---
kind: code
status: blocked
epic: go-module
depends_on: [protected-go-paths]
needs: protected-go-paths (its merge: no Go lands before the Go paths are protected, HLD § Protected paths)
touches: [go.mod, cmd/swarm/main.go, cmd/swarm/main_test.go, scripts/build.sh, tests/build_test.sh, .gitignore:Go build outputs, .github/workflows/ci.yml:shellcheck step file list, Makefile:SHELLCHECK_FILES, AGENTS.md:pre-PR commands (Before you open a PR), AGENTS.md:tree (Working on this repository), tests/board_only_test.sh:shellcheck list assertion]
estimate_lines: 285
---

# The repo has one Go module that builds one binary, and scripts/build.sh builds the four release binaries and their checksum file

Waits for protected-go-paths to merge, so no Go lands before the Go paths are protected. Go 1.27.1 must run in your pane (`go version`). If it does not, stop and tell the conductor.
- go.mod: `module github.com/redscaresu/swarm-dev` and `go 1.27.1`, with no require lines. Standard library only (HLD:105-106, 331). `go mod tidy` must leave go.mod unchanged and write no go.sum, and `go list -m all` prints only the module.
- cmd/swarm/main.go is the only Go package. It prints `swarm: no command is ported yet` on stderr and exits 2; ported behaviour is out of scope. Put the logic in a `run(args, stderr) int`, and have main() exit with its result. Add no internal/ package: go-layers adds the first ones. Never use internal/guard, merge, release or agentenv, which ship-gates protects (board/stories/protected-go-paths.md). Handle or return every error (HLD:333): go-checks-ci runs staticcheck and errcheck over this code.
- cmd/swarm/main_test.go: a test of run()'s line and exit code. A second test runs the test binary itself as a subprocess (os.Args[0], with an env var that TestMain reads to call main()). It checks exit 2, empty stdout and the exact stderr line, so a main() that drops run()'s result goes red (codex).
- While cmd/swarm is the only package, `go build ./...` writes ./swarm at the root. With several packages it writes nothing (go help build). So build.sh, and later the wrapper, build with `-o` and `./cmd/swarm`. .gitignore gains `/swarm` and `/dist/` (HLD:230).
- scripts/build.sh (bash 3.2, shellcheck-clean, cd to its repo root itself) is the release contract that binary-fetch and release-ci read, and neither keeps a copy (epic Constraints). One PLATFORMS list, `darwin/arm64 darwin/amd64 linux/arm64 linux/amd64` (HLD:225), feeds both the build loop and `--list`.
  `scripts/build.sh [--out <dir>]` (default dist/) makes <dir> if it is missing. It removes only the files it writes there, each swarm-<os>-<arch> and SHA256SUMS, and nothing else in <dir> (codex). Then it runs `CGO_ENABLED=0 GOOS=<os> GOARCH=<arch> go build -trimpath -o <dir>/swarm-<os>-<arch> ./cmd/swarm` for each platform, and writes <dir>/SHA256SUMS in sha256sum format (`<64 hex>  <asset>`, one line per asset). If any build fails, it exits non-zero and writes no SHA256SUMS.
  `--list` prints the contract without running go, one tab-separated line each: `asset<TAB><os>/<arch><TAB><name>` for each platform, then `checksums<TAB>SHA256SUMS<TAB>sha256`, then `signer<TAB>.github/workflows/release.yml`.
- tests/build_test.sh: put a stub `go` first on PATH that records GOOS, GOARCH, CGO_ENABLED and its args, and writes a file at the -o path. Run build.sh with --out set to a temp dir. A stub is used because test shards have no Go until binary-wrapper; go-checks-ci runs the real four-platform build. Check that:
  - --list names exactly the four HLD platforms, written out literally in the test with one check each;
  - --list's signer line is exactly `signer<TAB>.github/workflows/release.yml`, written literally, and that file exists (codex);
  - the files written equal --list's asset names plus SHA256SUMS;
  - a sentinel file put in --out first is still there afterwards;
  - the stub saw each os/arch with CGO_ENABLED=0;
  - `shasum -a 256 -c SHA256SUMS` passes;
  - a stub that fails linux/arm64 makes build.sh exit non-zero and leaves no SHA256SUMS, even with one left from an earlier run;
  - --list works with no go on PATH.
  Do not add the test to SLOW or SERIAL: the 14 shards and tests/test_shard_test.sh must keep passing.
- Shellcheck lists: in ci.yml:41, Makefile:37-38 and AGENTS.md:190, replace the four scripts/*.sh names with `scripts/*.sh` (keep scripts/pre-commit). build.sh and any later script are then covered with no list edit. No test compares the three lists, so they must stay equal.
- AGENTS.md: add go.mod, cmd/swarm/ and scripts/build.sh to the tree, each on its own line. Add `gofmt -l .` (must print nothing), `go vet ./...` and `go test ./...` to the pre-PR block. Leave the required-checks sentence (AGENTS.md:279): go-required-checks edits it once the user has made the checks required.
- Before you push, run `scripts/build.sh` once with the real go and list dist/. The PR is held for the user: ci.yml and the root Makefile are protected paths.

tests/board_only_test.sh:206-207 looks for the literal `scripts/board-only.sh` in the workflow's shellcheck command. If the list becomes a glob such as `scripts/*.sh`, update that assertion in the same PR so it checks the file is still covered, not the literal name (codex).

**Done when:**
- At the repo root, `go build ./...` exits 0 and writes ./swarm, which `git status --porcelain` does not show. `go mod tidy` leaves go.mod as `go 1.27.1` with no require lines, and writes no go.sum. `go list -m all` prints only github.com/redscaresu/swarm-dev. `gofmt -l .` prints nothing. `go vet ./...` and `go test ./...` pass. The Go tests go red if the message or the exit code changes, and the subprocess test goes red when main() exits 0 whatever run() returns. `scripts/build.sh` with the real go writes the four swarm-<os>-<arch> files and SHA256SUMS into dist/, and `shasum -a 256 -c SHA256SUMS` passes there. tests/build_test.sh passes under make test. On a worktree copy it goes red when one asset's name changes in the build step but not in the list, when a platform is dropped from the list, when the signer line names .github/workflows/ci.yml, when build.sh removes a file in --out it did not write, when a failed build still writes SHA256SUMS, and when --list calls go. `make lint` shellchecks scripts/build.sh: a shellcheck finding planted in it fails the run. ci.yml's shellcheck step, Makefile SHELLCHECK_FILES and AGENTS.md's shellcheck line name the same files.
- scripts/select-tests.sh --run passes
- tests/board_only_test.sh passes with the new shellcheck list
