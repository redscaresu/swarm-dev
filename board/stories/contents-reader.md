---
kind: code
status: ready
epic: shared-helpers
depends_on: []
touches: [bin/lib/merge.sh:pr_contents (new), bin/lib/merge.sh:merge_read, bin/lib/merge.sh:release_check, bin/lib/board.sh:pr_hld, tests/pr_contents_test.sh (new)]
estimate_lines: 170
easy: false
risk: high
---

# One reader for a file at a PR's ref, for merge_read, pr_hld and release_check

Add pr_contents <owner/repo> <ref> <path> (bin/lib/merge.sh, beside merge_read): the file's bytes on stdout through gh's contents API, path URL-quoted; exit 0 read, 1 absent (HTTP 404), 2 any other failure. merge_read (merge.sh:141-156) keeps its head rule on top (a 404 at the head is absent only for a path merge_gone lists); pr_hld's per-file read (bin/lib/board.sh:1160-1168) and release_check's two plugin.json reads (merge.sh:1254-1257, which today treat a 404 like any failure) call it, each keeping its message. Other epics' stories that read through it (fixes-027's epic-guard-renames, merge-holds' pinned-head reads) follow this one: keep the name and arguments stable.

**Done when:**
- tests/pr_contents_test.sh (new), with a stub gh contents API answering ok, 404 and 500: pr_contents exits 0, 1 and 2, and asks for a path holding # or ? quoted.
- At each consumer, the same stub: merge_read (through merge --board's epic guard) reads the file, treats a 404 at the base as absent and at the head as absent only for a removed path, and fails unreadable on a 500; pr_hld (through `swarm.sh grants`) keeps a file, drops one absent at the head, and dies naming the file on a 500; release_check (through merge --release) compares the versions, and refuses naming plugin.json on a 404 and on a 500. Each check fails if that consumer stops calling pr_contents or merges two outcomes.
- tests/grants_test.sh and tests/merge_test.sh pass.
