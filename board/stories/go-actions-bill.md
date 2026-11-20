---
kind: lead
status: blocked
epic: go-module
depends_on: [go-checks-ci, go-macos-job]
needs: go-checks-ci (a week of go-checks runs); go-macos-job (a week of macos-tests runs)
touches: []
estimate_lines: 0
easy: true
---

# You: check the Actions bill a week after go-checks and macos-tests start

Uses a week of runs from go-checks-ci's and go-macos-job's jobs.
- **You:** a week after the later of the two merges, open the repo's Actions usage and billing page. Note the minutes each new job used and any charge. The HLD says standard runners are free for a public repo, but nobody has checked that against this repo's bill (HLD:460-461). The repo is public (gh api, 2026-11-20).
- If macOS minutes are charged, decide what to do: trim the subset, run macos-tests on fewer events, or keep it as it is. Any change is a story of its own.
- Record the week's minutes per job and the charge in this story file.

**Done when:**
- This story records the minutes go-checks and macos-tests used in their first week, and the charge (0 or the amount), as read from the bill.
