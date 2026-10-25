---
kind: code
status: ready
epic: clash-by-part
depends_on: []
touches: [bin/lib/touches_rows.py:overlap, tests/epic_overlap_test.sh:part cases, tests/backlog_test.sh:clash case, tests/stacked_test.sh:bare-file fixtures, tests/stacked_status_test.sh:bare-file fixtures, tests/flow_holds_test.sh:bare-file fixtures, docs/features.tsv:clash row, README.md:building section]
estimate_lines: 180
easy: false
---

# The clash check compares parts: a bare file no longer clashes with every part of it

overlap() (bin/lib/touches_rows.py:65-66) holds two touches entries today when the files match and either part is empty, so a story naming a bare file clashes with every story naming any part of that file. Change it so two entries clash only when the file and repo match and either both parts are empty, or the parts' first tokens (the first word: a function or section name) match. touches_rows.py applies the same overlap() to the epic and the backlog paths (line 92), so both change at once.

Rewrite the fixtures in tests/stacked_test.sh, tests/stacked_status_test.sh and tests/flow_holds_test.sh that relied on a bare-file hold, so each still exercises a real clash (the same file and first token). README.md does not yet say how two stories clash: add one line saying so in this PR (AGENTS.md: a user-visible change updates README in the same PR). Add a clash row to docs/features.tsv with metric `flow holds: touches-clash holds per 10 PRs`, the 2026-10-24 baseline (four false holds, HLD Appendix A), and the cost to watch: flow's merge_ins.

**Done when:**
- A test shows `bin/swarm.sh` against `bin/swarm.sh:load_config` does not clash, `bin/swarm.sh` against `bin/swarm.sh` does, `bin/swarm.sh:load_config and the dispatch` against `bin/swarm.sh:load_config` does, and `bin/swarm.sh:load_config` against `bin/swarm.sh:main` does not. The bare-file and different-part cases go red with the old overlap(); the bare-against-bare case passes under both and guards that it still clashes.
- One test per path: `swarm.sh story --strict` between stories of two epics (tests/epic_overlap_test.sh) and between two backlog stories (tests/backlog_test.sh), each showing a part-only overlap is no longer held and a same-part one still is.
- The rewritten fixtures still hold on a real clash, and `make test` passes.
- README.md states the part rule, docs/features.tsv has the clash row, and doc_check passes.
