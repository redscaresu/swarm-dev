---
kind: code
status: blocked
epic: binary-fetch
depends_on: [fetch-ensure, fetch-download, fetch-build]
needs: fetch-ensure (binary_present, the swarm.sh call path its call-level case runs, tests/binary_fetch_test.sh for the macOS job, docs/running.md's First run); fetch-download (binary_download, which this adds a step to, and tests/binary_download_test.sh for the macOS job); fetch-build (tests/binary_source_test.sh for the macOS job)
touches: [bin/lib/binary.sh:binary_quarantined (new, at the file's end), bin/lib/binary.sh:binary_download (the quarantine step after the checksum), bin/lib/binary.sh:binary_present (only under (b)), tests/binary_quarantine_test.sh, docs/port/tests.tsv:tests/binary_quarantine_test.sh row, .github/workflows/macos.yml:SUBSET, docs/running.md:First run]
estimate_lines: 140
---

# On macOS a downloaded binary carrying the quarantine mark is refused, and the macOS job runs the fetch's tests

Needs fetch-ensure: binary_present, the swarm.sh call path its call-level case runs, tests/binary_fetch_test.sh and docs/running.md's First run. Needs fetch-download: binary_download, which this adds a step to, and tests/binary_download_test.sh. Needs fetch-build: tests/binary_source_test.sh. Needs quarantine-present: the user's choice in its You: step.
binary_quarantined <file>, a new function at bin/lib/binary.sh's end. On Darwin it runs BINARY_XATTR, a named constant /usr/bin/xattr and never a PATH lookup, as `-p com.apple.quarantine <file>`.
- The mark is present: one `binary: ` line saying the binary carries macOS's quarantine mark, was not installed, and what to do. Return 1, never a fallback.
- BINARY_XATTR missing on Darwin: one line, return 1 (fail closed).
- On Linux it starts nothing.
binary_download calls it on the downloaded asset after the checksum, with the os it already read from uname -s, so it starts no new uname. It runs once, at download (the epic's (3)).
quarantine-present chose (b), on 2026-11-22, so this applies: binary_present also runs it on <root>/swarm on Darwin, told by $OSTYPE so Linux forks nothing. The PR records the per-call cost beside fetch-ensure's.
Tests: new tests/binary_quarantine_test.sh sources binary.sh and adds its docs/port/tests.tsv row. On macOS, a gh wrapper ahead of tests/binary_fetch_stubs.sh's stub runs the stub, then marks the downloaded file with a real `xattr -w com.apple.quarantine`. So this story leaves the stubs file alone, which fetch-fallback edits in this wave. On Linux, use a uname stub reporting Darwin, and set BINARY_XATTR after sourcing to a stub (marked, unmarked) or a missing path.
.github/workflows/macos.yml is the macOS job (job macos-tests, SUBSET at :33, comment list at :26-32); ci.yml has none. Add four files to SUBSET, each with one comment line: tests/binary_download_test.sh (the checksum under BSD shasum), tests/binary_source_test.sh (go.mod read with bash 3.2's builtins), tests/binary_fetch_test.sh (the composed fetch, traps and rename under bash 3.2) and tests/binary_quarantine_test.sh (a real mark). No new action and no pin change. The PR changes .github/, so swarm.sh merge holds it for the user: this is the epic's Your part. Do not merge it.
Docs: docs/running.md's First run gains one list item for the quarantine line and what to do. Run the humanizer.

Under (b), `binary_present` must tell a quarantined binary from an absent one: it returns a distinct status (or prints the refusal and exits) for a marked file, and `binary_ensure` stops the call on it instead of falling through to `binary_fetch`. Falling through would download over the marked file and run it (codex).

**Done when:**
- Under (b): a present binary carrying the mark stops the call with one line, and the gh stub logs no release download.
- On macOS (the builder's machine), with the download marked by a real xattr -w com.apple.quarantine, `swarm.sh config` from an empty no-.git copy with bin/ported/config present: exit 1, exactly one stderr line naming the mark, empty stdout, no <copy>/swarm and no .fetch-* folder. On Linux that case says it is skipped.
- With a uname stub reporting Darwin, binary_download: a BINARY_XATTR stub reporting the mark returns 1 with one line; one reporting none returns 0; BINARY_XATTR naming a missing file returns 1 with one line. With Linux, no xattr start is logged.
- Only under (b): a present <copy>/swarm with a real mark makes `swarm.sh config` exit 1 with one line on macOS; unmarked, config runs. The PR body records, dated, the median of 20 runs of `swarm.sh usage` with the check.
- macos.yml's SUBSET names the four files, each with a comment line. The macos-tests run on the PR's head (swarm.sh wait-pr --head) is green. Its log shows the real-mark case passed; the PR quotes those lines and the run URL. zizmor and shellcheck are green on that head.
- Mutations on a copy, FAIL lines quoted, each turning a named case red: the xattr call removed (the real-mark case, and the marked stub case); the Darwin gate replaced by a `command -v xattr` lookup (the missing-file case).
- docs/running.md's First run says what the quarantine line means and what to do. tests/doc_check_test.sh passes. The PR says the humanizer ran.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
