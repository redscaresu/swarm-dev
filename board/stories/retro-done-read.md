---
kind: code
status: ready
epic: retro-gate
depends_on: []
touches: [bin/lib/board.sh:retro_done (new), tests/retro_done_test.sh]
estimate_lines: 110
easy: false
---

# retro_done reads a retro file at a git ref: done, and covering a version from at or before the last tag

Add retro_done <ref> <version> <tag> to bin/lib/board.sh beside version_gt (:1348). next's retro step reads at origin/<base> and merge --release's gate at RELEASE_BASE, so it takes the ref. It reads <board_rel>retros/v<version>.md with one git show <ref>:<path>, never the checkout. With the board outside the repo (BOARD_IN_REPO != 1) it returns 1, saying no retro file can be read at <ref>: the epic reads the retro at the release's base, and such a board has none. It passes when the file's first front-matter block has done: YYYY-MM-DD and covers: v<a.b.c>..v<x.y.z>, with x.y.z equal to <version> and a.b.c at or before <tag> (! version_gt a.b.c <tag>). On a pass it prints 'covers v<a.b.c>..v<x.y.z>, done <date>' on stdout and returns 0; the gate and next quote that line. Otherwise it prints why on one line and returns 1. The failures are: no file, no done:, a done: that is not YYYY-MM-DD, no covers:, a covers: not of that form, covers ending at another version, and covers starting after the tag. The format is retro-file-format's (board/stories/retro-file-format.md): one line each, no quotes. Only exact matches pass: a covers: below the front matter, or a value with a trailing word, fails. A file with neither field is a note, so v0.28.0.md, v0.30.0.md and v0.31.0-checkpoint.md stay notes. Nothing calls it in this PR. bash 3.2; avoid removed_test's banned names.

**Done when:**
- tests/retro_done_test.sh (new), on a git fixture: covers: v1.2.0..v1.3.0 with done: 2026-11-20 passes for version 1.3.0 with tag 1.2.0, and with tag 1.2.5. It prints 'covers v1.2.0..v1.3.0, done 2026-11-20'. It fails, printing why, for covers ending at v1.2.5, for covers starting at v1.2.6 with tag 1.2.5, with no done:, with done: soon, with a covers: only in the body, and with no file.
- Same test: a file committed after <ref> fails at <ref> while the checkout has it. With the board outside the repo, it fails while the file is on disk.
- The test fails on a worktree copy with the <to> = <version> check removed, and again with the read widened from the front matter to the whole file. The PR body has the FAIL lines.
