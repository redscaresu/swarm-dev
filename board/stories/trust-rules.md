---
kind: code
status: blocked
epic: first-port
depends_on: [first-port-freeze-start]
needs: first-port-freeze-start (its **You:** steps: the freeze is on, so the epic may start)
touches: [internal/trust/trust.go, internal/trust/json.go, internal/trust/trust_test.go]
estimate_lines: 240
---

# internal/trust decides from .claude.json's bytes what require_trusted.py decides, with no caller yet

Needs first-port-freeze-start's **You:** steps: the freeze is on. It ports the helper's rule with no caller: bash still runs the .py until trusted-go-port wires it. It builds beside the tests-only PR, so the port PR stays under the 300-line cap and the chain stays 3 deep.
- internal/trust, a rules package named for what it decides. Decide(data []byte, readErr error, root string, inGit bool) int returns 0 or 1 as bin/lib/require_trusted.py:1-10 exits.
- Reading, as Python's json.load(open(config)) reads (require_trusted.py:4-6):
  a read error (missing, a directory, no permission) gives 0;
  bytes that are not UTF-8, a UTF-8 BOM, text that is not JSON, or data after the value give 0;
  NaN, Infinity and -Infinity are values. A scan outside strings may rewrite them to null before encoding/json reads the text: the rule asks only 'an object?' and 'exactly true?', and null answers both as NaN does;
  numbers are never decoded into float64 (json.Decoder.UseNumber), since 1e400 is JSON to Python;
  duplicate keys keep the last;
  nesting deeper than a named constant, 10000 (encoding/json's own limit), gives 1, as Python's uncaught RecursionError exits 1. The same scan counts the depth, so no error text is matched.
- The rule: a top level, projects or folder entry that is not an object gives 1 where Python's .get would raise, path by path in Python's order, so a trusted folder before a bad parent is still trusted. Only JSON true trusts. With projects missing, nothing is trusted.
- The ancestors follow Python's os.path.dirname, not filepath.Dir, which cleans the path, and are walked only when not in git.
- internal/trust/trust_test.go: a table with one row per case of trusted-tests-outside's list, (a) to (o), and rows for '/a//b/', a relative root, a 5000-digit integer and a lone surrogate escape in a folder key. Each row's want is what python3 bin/lib/require_trusted.py exits on the same bytes, run by hand once. No test runs python3.
- The PR body names what no single Python fixes, which the Go does not match: depth between a Python's limit and 10000 (3.9.6 reads 994 levels, 3.14.7 reads 116216); a 5000-digit integer, which 3.14.7 refuses to read (exit 0) and 3.9.6 reads, as the Go does; a lone surrogate escape, which only Python can match to a root that is not UTF-8; a locale that is not UTF-8, where Python decodes in that encoding.

**Done when:**
- (1) go test ./internal/trust/ passes, with a row for each case the scope names. (2) On a copy of the worktree without .git, each of these turns a named row red, and the FAIL lines are in the PR body: a read error giving 1; NaN rejected; numbers decoded into float64; duplicate keys keeping the first; the depth limit removed; any truthy value trusting; ancestors through filepath.Dir; ancestors walked inside git too; the paths checked in reverse order. (3) The PR body has the hand runs of python3 require_trusted.py, one per row. (4) go test -v ./internal/layers/ prints internal/trust as rules, and its checks pass. (5) gofmt -l . prints nothing, and go vet ./... and go test ./... pass. (6) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
