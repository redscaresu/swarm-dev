---
kind: code
status: later
epic: board-store
depends_on: []
touches: [internal/config/config.go (new), internal/config/keys.go (new), internal/config/config_test.go (new)]
estimate_lines: 300
---

# load_config's parse is Go, with the same keys, defaults, rules and messages

Needs no other story. A new rules package internal/config, a line-for-line port of load_config (bin/swarm.sh:347-426; the epic's :273 is stale) and the settings block above it (:307-343). keys.go holds the 26 keys in CONFIG_KEYS' order, each with its default from :308-335. Each sits on a line of its own as `{name: "<key>", def: "<default>"},`, so doc_check can read the list (doc-check-go-settings). keys.go also holds REMOVED_KEYS. Parse(path string, content []byte, home string) returns each key's value and source (<path>:<n>, or default), the warnings in order and the first error. Each message matches the bash word for word: a warning as bash echoes it, an error without the `swarm: ` that die() adds. The rules: cut each line at its first #; skip whitespace-only lines; the key = value regex, with [[:space:]] as the C locale has it. lessons_file is skipped silently. A REMOVED_KEYS key warns and loads on. A $ or backtick is refused. Port the 19 case arms. An unknown key's message lists CONFIG_KEYS. A leading ~ or ~/ in board_dir and repos_dir becomes home. A later line for a key wins. A last line with no newline is read, and the CR of a CRLF line counts as trailing space. top_rung_rounds' -ge 2 is bash 3.2 arithmetic, which wraps past 2^64: 18446744073709551618 passes and 9223372036854775808 fails, and the Go matches both. demote_kinds splits as IFS=, read -a does: a trailing comma adds an empty kind, and spaces stay inside a kind. agent_env splits as read -a does with the default IFS. Out of scope: the escalate_ladder model check (bin/swarm.sh:549-560) and agent_env's reserved names (:651), which run outside load_config; and the -f test and the file read, which the first caller does (no regular file means Defaults()). The Go test is tests/config_test.sh's go_check (docs/port/tests.tsv:40): it parses one valid line for each key in the Go list, and fails, naming the key, when that line comes back as an unknown key. It reads no bash: the check that the Go lists equal CONFIG_KEYS and REMOVED_KEYS is config-compare's, which reads bin/swarm.sh already, so this package's tests need no tests.tsv row. No non-test file of the package names a SWARM_ token, comments included (tests/port_swarm_names_test.sh:31-33). The reviewer reads load_config against the Go rule by rule (P6). port: true.

**Done when:**
- internal/config's Go test parses a valid line for every key in the Go list and fails on a key with no parse case: deleting the merge_admin case on a copy without .git makes it red, naming merge_admin.
- Go tests pin each by its exact text: an unknown key's error with the known list in CONFIG_KEYS' order; each REMOVED_KEYS key's warning with its path and line; lessons_file loading with no warning; a $ value's error; the expected 'key = value' error; top_rung_rounds = 18446744073709551618 loading and 9223372036854775808 failing.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass, the layer checks among them.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
