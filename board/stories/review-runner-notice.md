---
kind: code
status: later
depends_on: []
touches: [bin/lib/build.sh:review brief runner-notice line]
---

# One line in the review brief: GitHub's runner-migration notice is not about the PR and is not a finding

From the v0.31.0 retro (2026-11-17). 31 of 539 declined findings, on 31 PRs, flag GitHub's runner-migration notice. The user chose 'not a finding' at the v0.31.0 retro.

One line in the review brief: GitHub's runner-migration notice is not about the PR and is not a finding.

**Done when:**
- the review brief contains the line (shown on a worktree copy, quoted in the PR)
- Docs that state the behaviour say so
- scripts/select-tests.sh --run passes
