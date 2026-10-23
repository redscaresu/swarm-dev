---
kind: code
status: ready
checks: loose-match
depends_on: []
touches: [tests/loose_match_test.sh (new), Makefile]
estimate_lines: 90
easy: true
---

# A lint fails on a loose text match in bin/

`loose-match` is the most common recurring finding: 66 PRs in 30 days, with no check (`swarm.sh outcomes`, 2026-10-23). Recent instances: `grep FAIL` missed ANSI-coloured lines, a regex built from an unescaped URL, a check name with a parenthesis cut to its first word, `Docs: none` matched inside fenced blocks, and a slug ending in `-done` read as retired.

Add tests/loose_match_test.sh, run by `make test`. It scans bin/ and hooks/ for the shapes behind those findings:
- `grep` (or `grep -q`/`-E`) whose pattern interpolates a shell variable without `-F`, `-x` or `-w`;
- `[[ ... == *"$var"* ]]` substring tests on an id, slug or URL;
- `awk` `~` matches built from a variable.

A line can opt out with a trailing `# loose-match: ok <reason>` comment. Lines that hit today and are correct get that comment, each with its reason. Lines that hit and are wrong are fixed in this PR only if the fix is one line; otherwise the test lists them in an allowlist file with the finding, so the lint lands green.

**Done when:**
- tests/loose_match_test.sh fails on a fixture script holding each of the three shapes, and passes on the same fixture with `-F`, `-x` or the opt-out comment.
- It runs over bin/ and hooks/ in `make test`, and passes on main.
