---
kind: code
status: later
epic: helpers-shared
depends_on: [go-report-text, go-store-files, go-py-decode, go-entries-per-file, shared-copies-list]
needs: go-report-text: report.PRKey. go-store-files: Store.ReadFile. go-py-decode: pytext.DecodeReplace. go-entries-per-file: the register call. shared-copies-list: docs/port/copies.tsv's codex_story_prompt row, deleted here.
touches: [internal/review/declines.go, internal/review/declines_test.go, cmd/swarm/declines.go, bin/ported/_declines, bin/swarm.sh:codex_story_prompt, docs/port/sites.tsv:codex_story_prompt row, docs/port/copies.tsv:codex_story_prompt row, docs/port/swarm-names.tsv:SWARM_LIB row, tests/diff_fixtures_codex.sh, tests/codex_test.sh:declines checks, tests/speed_list.txt:codex_declines line]
estimate_lines: 220
---

# codex_story_prompt's declined-findings list comes from the binary

Needs PRKey from go-report-text, ReadFile from go-store-files, DecodeReplace from go-py-decode, register from go-entries-per-file, and codex_story_prompt's row in docs/port/copies.tsv from shared-copies-list. The inline program at bin/swarm.sh:928-933 imports pr_key and prints each findings.tsv row declined on SWARM_PR's key as `- round R, declined as W: T (because: B)`. A rules function in internal/review does the same: rows padded to 9 columns, 'unknown' and '(no reason)' for empty cells, the because part only when set, bad bytes replaced. Its column-5 read carries `// outcome-scan: ok findings.tsv`. The _declines entry takes the findings path and the PR. codex_story_prompt calls it with binary_run and keeps the empty-SWARM_PR path, which starts no process. The call sits in a $(...) (bin/swarm.sh:927), so with no binary the die ends only that subshell: the prompt has no declined list and stderr has the binary's line, as a failed python3 leaves it today. The ported body is Go in a rules package, which internal/layers keeps from starting any process. Delete the site's rows in docs/port/sites.tsv (:34) and docs/port/copies.tsv. SWARM_LIB's row loses bin/swarm.sh, its only use there (:928-929). Marker bin/ported/_declines.

**Done when:**
- (1) tests/diff_run.sh --base <base> is clean on fixtures in tests/diff_fixtures_codex.sh that run codex-review with SWARM_STORY and SWARM_PR set and a codex stub that writes its prompt under the root: rows declined on that PR given as a URL and as owner/repo#N, rows on another PR, an empty round, a reason and a because, a short row, no findings file. tests/speed_list.txt names fx_codex_declines. (2) The run goes red with one Go rule broken (the because part always shown), shown on a worktree copy without .git. (3) tests/port_sites_test.sh passes with codex_story_prompt's row deleted, and goes red on a copy with the inline program put back. (4) A check in tests/codex_test.sh runs codex-review with SWARMDEV_BIN naming a missing file and gets the prompt without the declined list and the binary's line on stderr. (5) tests/codex_test.sh, tests/port_copies_test.sh and tests/port_swarm_names_test.sh pass. (6) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
