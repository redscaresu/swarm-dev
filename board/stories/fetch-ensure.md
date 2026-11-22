---
kind: code
status: blocked
epic: binary-fetch
depends_on: [fetch-download, fetch-attest]
needs: fetch-download (binary_download, binary_repo, BINARY_CANNOT, tests/binary_fetch_stubs.sh); fetch-attest (binary_attest, and BINARY_GH_MIN for README's gh row)
touches: [bin/lib/binary.sh:binary_gh_path (new), bin/lib/binary.sh:binary_present (new), bin/lib/binary.sh:binary_fetch (new), bin/lib/binary.sh:binary_ensure (new), bin/lib/binary.sh:header comment, bin/swarm.sh:lib source lines (binary.sh moved above the version case), bin/swarm.sh:version/update case (binary_ensure call after it), tests/binary_fetch_test.sh, tests/binary_fetch_stubs.sh:gh stub attestation form, tests/binary_build_test.sh:no-.git case, tests/diff_run.sh:PASS_ENV, tests/env_allowlist_test.sh:as_agent, README.md:Requirements, docs/running.md:First run (new), docs/running.md:Offline (new), docs/reference-logs.md:gh_calls paragraph]
estimate_lines: 290
risk: high
---

# Every swarm.sh call in an installed copy with no binary downloads, checks and installs it, then exports its path

Needs fetch-download: binary_download, binary_repo, BINARY_CANNOT and tests/binary_fetch_stubs.sh. Needs fetch-attest: binary_attest, and BINARY_GH_MIN for README's gh row.
Where: bin/lib/binary.sh gets a block between binary_run and fetch-download's block, in this order: binary_gh_path, binary_present, binary_fetch, binary_ensure. That order keeps binary_present and binary_ensure apart, so fetch-quarantine and fetch-fallback can edit them in one wave. Update the header.
bin/swarm.sh sources binary.sh above the version/update case (the source line is now :621, the case :228-231). It calls binary_ensure "${SWARM_HOME}" right after that case, before find_project (:260). So version and update never fetch here (version-fetch adds version), and a call outside a project fetches too. The call site exits 1 when binary_ensure fails, so no command's bash runs.
binary_ensure <root>:
- SWARMDEV_BIN set: nothing (HLD:239-242).
- <root>/.git exists: nothing. A checkout builds lazily through binary_path (HLD:235). The diff-run and speed jobs run worktrees under env -i (diff-run.yml:59-77, speed.yml:69-82).
- Otherwise binary_present (an executable <root>/swarm, builtins only, no fork), else binary_fetch. Then export SWARMDEV_BIN=<root>/swarm.
- On failure it prints binary_fetch's one line and returns binary_fetch's code, which fetch-fallback reads. It never dies, so version-fetch can go on.
binary_present is a function of its own: quarantine-present's choice (b) changes only it.
binary_gh_path: PATH without any folder ending /gh-shim, as bin/gh-shim/gh:13-19 skips them, builtins only. So the download never runs through this version's or an older version's shim and is not logged in gh-calls.tsv. fetch-fallback reuses it.
binary_fetch <root> <version> runs in a subshell, with PATH from binary_gh_path and its own EXIT, INT, TERM and HUP trap; swarm.sh's traps stay as they are. Steps: a temp folder <root>/.fetch-<pid> on the same filesystem; binary_download into it; binary_attest on the downloaded asset, with binary_repo and --list's signer; chmod +x; mv -f onto <root>/swarm. The trap removes the folder on every path it sees. A KILL leaves the folder, holding a file that is not executable and that no call runs; the next call fetches again. hooks/lead-stop.sh KILLs its swarm.sh calls' process group at its 45 s deadline (:29,56-57), and its call may be the first after an install. No lock and no docs/port/locks.tsv row: the per-call temp name and the rename make two calls safe. The checks run once, here, never on a call that finds the binary.
Add the attestation form to tests/binary_fetch_stubs.sh's gh stub, for the file it served.
Test copies with no .git: make test sets SWARMDEV_BIN, so they run as today, except tests that drop it. tests/nopy_test.sh runs tests/diff_run.sh, whose env -i passes no SWARMDEV_BIN (:170). tests/env_allowlist_test.sh's as_agent (:107-110) replays an agent's env without it (:191). In a no-.git copy both now reach the fetch. Fix them by a route the PR names, such as passing make test's SWARMDEV_BIN through when the tree has no .git. Keep env_allowlist's check at :191 as it is, and the diff-run job's worktree runs. Find any other such test with a search the PR quotes (env -i, env -u SWARMDEV_BIN, unset SWARMDEV_BIN).
tests/binary_build_test.sh's no-.git case (:172-178) now reaches the fetch. Its copy has no scripts/build.sh, so it gets fetch-download's line: update the expected line. Its go stub still logs no call.
Tests: new tests/binary_fetch_test.sh drives swarm.sh from outside, so it needs no docs/port row. Use a no-.git copy (bin/, scripts/build.sh, .claude-plugin/, go.mod, cmd/, internal/), SWARMDEV_BIN unset, the stubs first on PATH, run from a project. Synchronise with fifos or marker files, never sleeps. KILL with in_new_group and stop_group (tests/test_helpers.sh).
Docs: README.md Requirements' GitHub CLI row (:53) names BINARY_GH_MIN. docs/running.md gets two sections before Updating (:155). First run: each installed version's first call downloads and checks its binary once; what each stop line means; what a killed fetch leaves. Offline: with no network the call stops in one line; version and update still run. docs/reference-logs.md's gh_calls paragraph (:470-482) gets one line: the calls that fetch the binary run the real gh past the shim and are not counted. Run the humanizer over that prose and the PR body.
risk high: this is where the checks compose, and a wrong order publishes a file nothing checked.

The fetch runs before `main` installs swarm.sh's own traps, so a TERM or INT sent to swarm.sh during the download does not reach traps set inside a `binary_fetch` subshell. Run the fetch in the same shell, or install a trap for the fetch's span that kills the gh child and removes the temp folder, and restore the previous trap after it (codex).

**Done when:**
- A case sends TERM to swarm.sh while the gh stub's download sleeps: within 5 s no gh child is left running and no temp folder is left in the plugin folder.
- `swarm.sh config` from the copy: the gh stub logs release download (github.com repo, v<plugin.json version>, this platform's asset and SHA256SUMS), then attestation verify on a file in <copy>/.fetch-<pid>/ with the asset's name and release.yml as signer. Afterwards <copy>/swarm is executable and cmp-equal to the fake release, config's output follows, and no .fetch-* folder is left.
- A copy whose scripts/build.sh --list names another signer: the attestation call carries it.
- A stub on PATH that the command runs sees SWARMDEV_BIN=<copy>/swarm. With bin/ported/_wrapper-fixture in the copy, `swarm.sh _wrapper-fixture a 'b c'` fetches, then prints the fixture's two arguments and the frame's project, as tests/binary_dispatch_test.sh:225-227 checks.
- A second call logs no gh, uname, shasum or sha256sum start, and leaves <copy>/swarm's inode and mtime as they were.
- A wrong checksum and a failing attestation stub, each through `swarm.sh config` with bin/ported/config present: exit 1, exactly one stderr line, empty stdout, no <copy>/swarm and no .fetch-* folder.
- Two `swarm.sh config` calls whose gh stubs meet at a rendezvous, so both downloads finish before either publishes: both exit 0 with config's output, <copy>/swarm is cmp-equal to the fake release, and no .fetch-* folder is left.
- With mv on PATH a logging stub that holds the second writer's mv on a fifo: while it is held, the test runs <copy>/swarm _wrapper-fixture and gets the fixture's output. The held mv's source is an executable file in a .fetch-* folder in the copy, cmp-equal to the fake release.
- PATH holds the copy's bin/gh-shim with its gh replaced by a stub that logs and exits 1, then an older version's gh-shim folder the same, then the gh stub; go is a fail stub. The fetch succeeds, both shim logs are empty, and the gh stub logged each of its calls once. With the copy's real shim and a real older one first instead, it succeeds within the test's time bound.
- A TERM to swarm.sh while the gh stub holds mid-download: exit non-zero, no .fetch-* folder and no <copy>/swarm. A KILL to the call's process group at that point: no <copy>/swarm, the folder left holds no executable file, and the next call fetches and exits 0.
- `swarm.sh update` with a claude stub in the empty copy makes no gh call and leaves no <copy>/swarm.
- In a no-.git copy of the worktree, `make test TESTS="tests/nopy_test.sh tests/env_allowlist_test.sh tests/diff_run_test.sh" JOBS=1 TEST_RUNS_LOG=` passes, plus each test the search found. No fixture's output holds a `binary:` line, and no gh stub logs a release call. The PR quotes the search and its hits. tests/binary_build_test.sh passes with its no-.git case's new line.
- Mutations on a worktree copy, FAIL lines quoted, each turning a named case red: the binary_attest call removed (the first case, and the attestation case); the signer from --list replaced by today's literal (the signer case); the export removed (the stub sees SWARMDEV_BIN); binary_present's branch removed (the second-call case); a fixed temp name instead of .fetch-<pid> (the rendezvous case); mv replaced by cp onto <copy>/swarm (the held-mv case); binary_gh_path's skip removed (the stub-shim case); the subshell trap removed (the TERM case).
- The PR body records, dated, the median of 20 runs of `swarm.sh usage` from the copy with the binary present, once with SWARMDEV_BIN unset and once with it set. It quotes the speed job's usage row on the PR's head.
- README.md's Requirements, docs/running.md's First run and Offline, and docs/reference-logs.md's gh_calls line say the above. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
