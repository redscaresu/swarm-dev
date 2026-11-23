---
kind: code
status: blocked
epic: first-port
depends_on: [first-port-freeze-start]
needs: first-port-freeze-start (its **You:** steps: the freeze is on, so the epic may start)
touches: [tests/config_test.sh:folder trust block, tests/diff_fixtures_trust.sh, tests/speed_list.txt:trusted_git line]
estimate_lines: 175
---

# Tests-only: swarm.sh _trusted pins how require_trusted.py reads .claude.json, and diff fixtures for the port

Needs first-port-freeze-start's **You:** steps: the freeze is on, so the epic may start. Step 1 of the six port steps (HLD:250-262) for bin/lib/require_trusted.py, the helper this epic ports. It is 10 lines, run as a process by one caller (bin/lib/agents.sh:131), imports no bin/lib module, is imported by none and has no inline site (docs/port/sites.tsv).
No test reaches inside it: none names the file, and docs/port/tests.tsv has no row for it. So nothing is rewritten. This PR adds the cases the Go must keep, driven through `swarm.sh _trusted <cwd>` (bin/swarm.sh:859, a frozen name: docs/port/names.tsv:85), as the six cases at tests/config_test.sh:462-495 are.
- tests/config_test.sh, in the folder-trust block: a helper that writes .claude.json from raw text (trust() uses json.dumps, which cannot write NaN or a duplicate key). Then one check per case, on a plain folder outside git unless it says otherwise. Each refusal checks the die line, as the existing cases do.
  Goes ahead: (a) text that is not JSON (cut off); (b) bytes that are not UTF-8; (c) a directory where the file should be; (d) a UTF-8 BOM before the object.
  Refused: (e) no projects key; (f) the top level a list; (g) projects a list; (h) the folder's entry null; (i) hasTrustDialogAccepted 1, and "true", each on its own.
  (j) A duplicate folder key keeps the last one, both ways round. (k) NaN elsewhere in a file that trusts nothing is refused, not gone ahead. (l) 1e400 elsewhere in such a file is refused. (m) Order: the folder's own entry trusted, with its parent's entry a list, is trusted; the folder's entry missing, with its parent's a list, is refused.
  (n) Arrays nested 500 deep elsewhere in a file that trusts the folder: trusted. (o) Arrays nested 200000 deep elsewhere: refused, since Python's RecursionError is not caught (require_trusted.py:4-6) and exits 1. On the lead's Mac (2026-11-23) python3 3.9.6 reads 994 levels and 3.14.7 reads 116216, so both cases sit outside every Python's limit. Check both on each CI OS's python3.
  If case (b)'s answer depends on the locale on either CI OS, drop it and say why in the PR.
- A new file tests/diff_fixtures_trust.sh, a file of its own so no other fixture edit clashes. Its fixtures run `swarm.sh _trusted` with ${ROOT}/claude-config/.claude.json, since diff_run.sh sets CLAUDE_CONFIG_DIR there (tests/diff_run.sh:47-51): fx_trusted_git (a worktree trusted through its main checkout), fx_trusted_refused, fx_trusted_ancestor, fx_trusted_no_file, fx_trusted_bad_json, fx_trusted_not_object (projects a list), fx_trusted_nan, fx_trusted_nested (500 deep) and fx_trusted_deep (200000 deep). FX_CALLS names none, as there is no gh or herdr call. On fx_trusted_not_object and fx_trusted_deep the base prints Python's traceback, which the port's allow entry will name.
- tests/speed_list.txt gains trusted_git, so the port's speed job times the call on both trees.

**Done when:**
- (1) Every new check in tests/config_test.sh passes against bin/lib/require_trusted.py as main has it. (2) Each new check is shown able to fail: on a copy of the worktree without .git, a named mutation of require_trusted.py turns it red. The PR body has a table: check, mutation, FAIL line. The mutations include: every exception taken as unreadable (exit 0), which also turns (o) red; `is True` replaced by truthiness; NaN rejected (parse_constant raising ValueError); the ancestor loop run inside git too; the paths checked in reverse order. (3) The diff-run job is green on the PR, and its log lists every fx_trusted_* fixture. (4) The speed job's log has a trusted_git row. (5) make test TESTS='tests/config_test.sh tests/diff_run_test.sh' passes. (6) scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
