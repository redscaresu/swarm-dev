---
kind: code
status: ready
epic: reference-split
depends_on: []
touches: [tests/doc_check_test.sh:anchor check (new)]
estimate_lines: 70
easy: true
---

# doc_check fails a markdown link whose #anchor matches no heading in its target

doc_check's link check drops the #anchor, so a moved section leaves a dead `docs/reference.md#building` link that passes. Add an anchor check to tests/doc_check_test.sh. For each `](<path>#<slug>)` and `](#<slug>)` link, the slug must equal a heading of the target under GitHub's rule: lowercase, punctuation dropped except - and _, spaces to -, -1 and -2 for repeats, headings inside code fences skipped. It reads the files doc_check already reads (tests/doc_check_test.sh:90-92) plus AGENTS.md and llms.txt, which hold links into docs/. Today there are 26 such links, in README.md (8), AGENTS.md (2) and docs/reference.md (16), and none is broken. Add fixture cases beside the existing ones (tests/doc_check_test.sh:130). Prove the check fails on a worktree copy; say so in the PR.

**Done when:**
- scripts/select-tests.sh --run passes with tests/doc_check_test.sh in its run.
- Fixture cases: a missing anchor in another file and one in the same file are reported with file and link; a right anchor, a repeated heading's -1 slug and a fenced `# comment` line behave as GitHub does.
- In a worktree copy, changing README.md:150's `#building` to `#buildin` fails the real-docs check, naming README.md and the link.
- In the copy, breaking AGENTS.md:83's `#merging` fails the check, so AGENTS.md is read.
