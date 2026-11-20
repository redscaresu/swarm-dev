# The port lists

*Created: 2026-11-20*

This folder holds the lists that the v0.32 Go port is checked against.
Each list is a tab-separated file with `#` comment lines at its top.
The comment lines say how to read the columns.
Each list has a test under `tests/`, except exit-codes.tsv, which has none yet.
Each test's failure line names the file and the row.
This is the one folder under `docs/` for contributors. The rest of `docs/` is for users.

## What each list holds

- [tests.tsv](tests.tsv) lists the tests that reach inside the code, and what the port does with each.
  Its test is [tests/port_tests_list_test.sh](../../tests/port_tests_list_test.sh).
  The test applies the reach rule in the file's header to every `tests/*_test.sh` and fails on a test with no row.
  A PR that adds a test which reaches inside adds its row in the same PR.
  A row stays when its test stops reaching, because the list is the record.
  A text row's `go_check` says what the Go check asserts once the bash it reads is gone.
- [sites.tsv](sites.tsv) lists the inline Python sites that import a `bin/lib` helper, and the epic that rewrites each.
  Its test is [tests/port_sites_test.sh](../../tests/port_sites_test.sh).
  The test fails on a site with no row.
  A PR that adds an inline site adds its row.
- [swarm-names.tsv](swarm-names.tsv) lists every `SWARM_` name that a file under `bin/`, `hooks/`, `cmd/` or `internal/` names.
  Its test is [tests/port_swarm_names_test.sh](../../tests/port_swarm_names_test.sh).
  The test fails on a name with no row, on a row no file names, and on a row whose files differ from the files that name it.
  A PR that adds a name adds its row.
  A PR that removes a name deletes its row, so the reviewer sees the name go.
- [locks.tsv](locks.tsv) lists every place the code takes a lock.
  Its test is [tests/port_locks_test.sh](../../tests/port_locks_test.sh).
  The test fails on a take site with no row, and on a function that takes a lock more often than its row's `n`.
  A PR that adds a take site adds its row.
  A PR that removes one deletes the row.
- [names.tsv](names.tsv) freezes the commands, settings, removed settings and hook paths of v0.31.3.
  Its test is [tests/port_names_test.sh](../../tests/port_names_test.sh).
  The test fails on each name that is gone, and says which row.
  Rows stay as the record.
- [fields.tsv](fields.tsv) lists the board front-matter fields the code reads, and the functions that read each.
  Its test is [tests/port_fields_test.sh](../../tests/port_fields_test.sh).
  The test fails on a row when none of its `read_by` functions still names the field.
  A port that moves a reader points `read_by` at the new function.
  Rows stay as the record.
- [exit-codes.tsv](exit-codes.tsv) lists the exit codes of each command, hook script and the gh shim, as of v0.31.3.
  No test reads it yet.
  Its `pinned by` column names the tests that assert each code, or `none`.

## What a PR does

A PR adds a row for a new `SWARM_` name, lock take site, inline site or inside-reaching test.
A PR deletes a row where the reviewer sees it when a name goes.
The rows of tests.tsv, names.tsv and fields.tsv stay as the record.

## How a port and its reviewer use them

A port PR keeps each test above green, or edits the row it breaks in the same PR.
A port epic's plan reads the tests.tsv rows whose `epic` column names it.
A row whose `go_check` states an assertion is a check the epic must add.
A row whose `go_check` is empty or says `retired-with:` adds no Go check.
Every row still carries the work its `mark` sets, whatever its `go_check` says.
A `becomes-a-Go-test` row moves its cases into a Go test.
A `rewrite-from-outside` row is rewritten to drive the command from outside.
The reviewer reads the deleted bash against the Go, rule by rule, with these lists as the checklist.
That is step 6 of the port's method (`board/hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md:262`).
A name, lock, field or code that is in a list and not in the Go is a finding.

## The SWARM_ set is open

Every `SWARM_*` variable in a session's environment reaches an agent (`bin/lib/agents.sh:430-502`).
So the set of names is open at runtime.
swarm-names.tsv lists only the names the code mentions.

## The closed plumbing list

Five bash functions keep a bash copy beside their Go counterpart until their last bash caller goes.
They are `die`, `within`, `scaled`, `nap` and `json`.
Nothing else may claim that leave.
Each count below is lines at command position in `bin/swarm.sh`, `bin/lib/*.sh` and `hooks/*.sh` (14 files), taken at main 923cc02e, with an argument after the name.
Comment lines are skipped.
A word in a message, such as "within 5 s" in an error text, is not counted.
A case arm's `)` counts as a command boundary only at the start of a line.
A `=` counts only as an assignment, not as part of `==` or `!=`.
Run this from the repo root, with the name in place of `within`:

```bash
perl -ne 'next if /^\s*#/; $n += () = /(?:^|\$\(|[|&;{(!]|^\s*(?:[^\s()"\x27]|"[^"]*")*\)|\b(?:then|do|else|if|while|until)\b|(?<![=!<>])=)\s*(?:\w+=(?:"[^"]*"|\S+)\s+)*within\s+\S/g; END { print "$n\n" }' bin/swarm.sh bin/lib/*.sh hooks/*.sh
```

- `die`: 535 call sites in 9 of 14 files.
  Defined in `bin/swarm.sh`.
- `within`: 90 call sites in 8 of 14 files.
  Defined twice: `bin/lib/merge.sh` and `hooks/lead-stop.sh`, which takes a deadline, not a number of seconds.
  A plain grep for `within` and an argument, skipping comment lines, gives 114 lines, because it also counts the word in messages.
  The epic's 155 and the survey's 112 come from other greps and do not match 90.
- `scaled`: 9 call sites in 4 of 14 files.
  Defined in `bin/lib/agents.sh`.
- `nap`: 12 call sites in 4 of 14 files.
  Defined in `bin/lib/agents.sh`, as `sleep "$(scaled …)"`.
- `json`: 80 call sites in 7 of 14 files.
  Defined in `bin/swarm.sh`.
  A call reads JSON on stdin and prints one Python expression of it.

A new bash function that is not on this list goes with the Go port of its callers, not beside it.
