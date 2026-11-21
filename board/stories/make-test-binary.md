---
kind: code
status: ready
epic: binary-wrapper
depends_on: []
touches: [scripts/test.sh:top-level build, Makefile:test, .github/workflows/ci.yml:test-shard, AGENTS.md:Before you open a PR, AGENTS.md:Development rules (prove a mutation), tests/runner_binary_test.sh (new), docs/port/tests.tsv:runner_binary_test row]
estimate_lines: 165
risk: high
---

# make test builds the Go binary once and hands it to every test in SWARMDEV_BIN

Needs no other story. The binary variable is SWARMDEV_BIN for the whole epic: no SWARM_ prefix, so scripts/test.sh:60 and tests/test_helpers.sh:25 keep it, and agent starts drop it (bin/lib/agents.sh:388-392). scripts/test.sh's top level (not --one) builds ./cmd/swarm once into the run's own directory, before the phases (scripts/test.sh:473,484), and exports SWARMDEV_BIN after the SWARM_* unset (:60). A failed build prints Go's error and one line naming the build, and fails the run before any test file starts. A nested run (scripts/test.sh:210-216) of the same tree reuses the outer binary and builds nothing: about 20 tests start a nested make test of the real tree, and tests/sleep_scale_test.sh:131 holds one to 5 s. A run of another tree (a no-.git copy) builds its own, overriding an inherited SWARMDEV_BIN. A tree with no go.mod builds nothing and says so in one line. A tree with go.mod and no go on PATH fails the run before any test file starts, naming go: never run the tests without the binary (critic). make test now needs Go wherever it runs; AGENTS.md says so. CI: ci.yml's test-shard has no Go (ci.yml:51-80); add go.yml's pinned setup-go step (go.yml:57-62, go-version-file go.mod), skipped on a board-only PR like the test step. Keep the 14-shard matrix (tests/test_shard_test.sh). macos.yml already sets up Go before its make test subset (macos.yml:46,76), so the build also runs there under bash 3.2. Docs: the Makefile's test comment, and AGENTS.md's pre-PR block and its 'Prove a mutation without git' rule (make test in the copy builds the copy's own Go, and a broken build fails the run). This story owns every AGENTS.md line in the epic. The PR changes the Makefile and .github/, so swarm.sh merge holds it for the user. Run the humanizer over the PR body. risk: high: it changes the runner of the required test check, and a build-failure or skip path that exits 0 would turn the check green without running tests (critic).

**Done when:**
- A new test makes a no-.git copy holding the Makefile, scripts/, cmd/, go.mod and two trivial test files, its main.go changed to print a word of the test's own. make test in the copy passes; both files see the same SWARMDEV_BIN; running it prints the copy's word, not the outer tree's.
- That run makes one go build: a go wrapper first on PATH logs exactly one build call.
- With a syntax error in the copy's main.go, make test exits non-zero, prints Go's error and the build line, and no test file runs, even with SWARMDEV_BIN exported by the caller.
- With go.mod in the copy and no go on PATH, make test exits non-zero, prints one line naming go, and no test file runs.
- A nested make test of the same tree builds nothing (the go wrapper logs no call), and tests/sleep_scale_test.sh and tests/test_runner_test.sh pass unchanged.
- On this PR's head commit every test-shard job ran the setup-go step and the build (the job log shows the build line), and tests/test_shard_test.sh passes. macos-tests passes on the same head, with the build line in its log.
- tests/port_tests_list_test.sh passes, with a row for runner_binary_test if the rule finds a reach.
- Mutation: make scripts/test.sh skip the build and the first check goes red; make the no-go path skip the build and the no-go check goes red; drop the reuse rule and the nested check goes red.
- scripts/select-tests.sh --run passes
