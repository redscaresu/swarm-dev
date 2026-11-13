---
kind: code
status: ready
epic: retro-report
depends_on: []
touches: [bin/lib/lifecycle.sh:board_pr_kind, tests/board_pr_kinds_test.sh:retro file cases, docs/reference-lead.md:Board PR kinds]
estimate_lines: 40
easy: true
---

# board-pr names a retro file PR's kind

Add a `retro file` kind to board_pr_kind (bin/lib/lifecycle.sh:70-85). A PR named `retro-<x>` gets it when the PR worktree's <board>/retros holds a file whose cleaned name is <x>. Check it with `board_pr_names "$2/retros" "$x"`, as plan- does for hld/. So retros/v0.31.0.md makes retro-v0-31-0 a retro file PR. A story slug such as retro-goals-step stays a story-scope edit. board_pr_kind_line (:98-108) already prints `no codex-review` for every kind except plan and agreement. This change names the kind and does not change what runs: a retro-<v> PR already gets no codex-review as a story-scope edit. Add the kind's bullet to docs/reference-lead.md § Board PR kinds (:64-80). Open PR #862 edits board_pr, another function in the same file. Rebase on it if it has merged.

**Done when:**
- tests/board_pr_kinds_test.sh: retro-v0-31-0, opened with retros/v0.31.0.md in the PR, prints `board-pr: retro-v0-31-0 is a retro file PR: no codex-review`. retro-goals-step, with no such file, prints the story-scope edit line.
- The new cases fail on a worktree copy without the retro-?* case, and the PR body has the FAIL lines. tests/doc_check_test.sh and tests/loose_match_test.sh pass, and shellcheck passes.
