---
kind: code
status: ready
risk: high
depends_on: []
touches: [bin/lib/merge.sh:release_check and merge_pr's --release path, tests/merge_test.sh]
estimate_lines: 80
easy: false
---

# A release ships only what its grant check read

`release_check` (bin/lib/merge.sh:1121) reads origin/<base> before `gh pr merge` runs. A story PR that lands in between ships in the release unchecked by the release grant (conduct-hld-grants report, 2026-10-24).

- Record the base SHA `release_check` read. Right before `gh pr merge`, read origin/<base> again; if it moved, run `release_check` again on the new base, and refuse if it fails.
- Afterwards, check that the resulting commit's first parent is the base SHA last checked. If not, print a refusal naming the unchecked commits, and do not update the plugin or start the upgrade.

**Done when:**
- tests/merge_test.sh: a base that moves between the check and `gh pr merge` re-runs the check, and a story added in that window that no release grant covers is refused; a resulting commit whose parent differs from the checked SHA is reported and skips the plugin update.
- `make test` passes.
