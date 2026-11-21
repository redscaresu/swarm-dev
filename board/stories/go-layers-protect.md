---
kind: code
status: ready
epic: go-layers
depends_on: []
touches: [bin/lib/board.sh:OWN_PROTECTED (the regex and its comment), tests/merge_protected_hold_test.sh:the plugin's own repo paths loop and the guardian case, docs/method.md:own-repo hold sentence (line 143), docs/reference-merging.md:§ Merging own-repo hold sentence (line 101)]
estimate_lines: 30
easy: true
risk: high
---

# Hold for the user a story PR that changes internal/layers/, where the checks that keep protected rules in place live

Under the carve-out (HLD:480-485): this story changes the merge hold, so the board PR lists it and waits for the user's go. Without it, one agent-merged PR can move a protected rule into internal/board and widen internal/layers' short list in the same diff, and neither path is held (bin/lib/board.sh:2514). Adds internal/layers/ to OWN_PROTECTED as a whole directory with its trailing slash, so internal/layersx/ is not held, and says why in its comment. internal/iface/ and internal/clock/ are not added: every port adds interface methods, so each port PR would wait for the user. merge.sh:438 and tests/doc_check_test.sh:44 read OWN_PROTECTED, so they need no change. docs/method.md:143 and docs/reference-merging.md:101 each get a new sentence naming internal/layers/ and why, not a longer list (AGENTS.md: never lengthen a sentence that lists them). From its merge on, every later PR that changes internal/layers/ is held for the user: this epic's checks, and a port that widens an allowed list. Break: drop internal/layers/ from OWN_PROTECTED; the hold test must go red.

**Done when:**
- tests/merge_protected_hold_test.sh holds a story PR changing internal/layers/x_test.go in the plugin's own repo, with the hold line naming the path, and merges one changing internal/layersx/x.go, as it does internal/guardian/x.go (tests/merge_protected_hold_test.sh:155-158). docs/method.md and docs/reference-merging.md each name internal/layers/ in a sentence of its own. tests/doc_check_test.sh passes.
- scripts/select-tests.sh --run passes
