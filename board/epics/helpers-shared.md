---
status: split
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [foundation-exit]
---

# The modules the other helpers import run as Go, each beside its Python copy under a comparison test until its last importer is ported: clock, events_outcome, report and touches_rows, and gh_cache, which report imports

The two section runners can run a ported section.

Stage 2 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) Each of the five has a Go package, and a test runs the Python and the Go over the same fixtures, the malformed cases the Python tests have among them, and compares the output byte for byte. It goes red when either side alone is changed. (2) The four inline sites that import only these modules call the binary (bin/lib/lifecycle.sh:486,4791; bin/swarm.sh:859; and the patch gate's cache at bin/lib/board.sh:1703), with a clean differential run for their commands. The patch gate's cache keeps its key and its files, and an old session's bash and the binary read each other's entries. (3) flow_report.py and retro_report.py run a section that has no .py file through the binary, in the same name order, under the same heading and with the same context, shown with one fixture section in Go. (4) A list names, for each of the five, what still imports its Python copy, inline sites included, and a test fails when a copy outlives its last importer or is deleted before it.

**Out of scope:**
- Porting any flow, outcomes, retro or dash helper (the other helper epics)
- panes.py (helpers-panes)
- Front matter, config and event lines (board-store)
- recurring.py, which moves with its two importers (helpers-reports)

**Constraints:**
- Go checks to build, from docs/port/tests.tsv (agreed by the user on 2026-11-20): tests/flow_sections_test.sh, tests/outcome_scan_test.sh. Each keeps the assertion its go_check column names.
- Port rules P1 to P6 and P8.
- Exception 3 (HLD:278-281) lets report.py, events_outcome.py, clock.py and touches_rows.py keep a Python copy under the comparison test until the last importer is ported; panes.py is helpers-panes'. 26 Python files import report.py, 24 events_outcome.py, 11 clock.py and 5 touches_rows.py, so no module can go in one PR with its importers. Every other helper epic depends on this one.
- gh_cache.py is not on the exception's list, but report.py imports it (bin/lib/report.py:2), so report.py's copy cannot run without it. The plan reads the exception as covering it, under the same test: contradiction 24. Its copy goes when report.py's does.
- recurring.py is on no list and has two importers, so it leaves this epic and moves with them (helpers-reports).
- The site at bin/lib/board.sh:1703 is inside non_fix_cache, the patch gate's cache. This epic swaps the call and changes no rule, so P12's window does not apply.
- flow_report.py runs each flow_<name>.py in its own process space with shared globals (runpy), and retro_report.py runs retro_<name>.py by glob (bin/lib/reports.sh:525-591). The runners stay Python until their last section is ported, and the Go starts no python3.
- The Go clock is go-layers' clock package; this epic adds only what clock.py has.
- gh_cache's files under .swarm/ keep their format: older sessions read them.
- Port rules P13 and P14.

**Your part:**
- Carve-out (HLD:480-485): one story is listed, the one that swaps the patch gate's cache site to the binary (non_fix_cache, bin/lib/board.sh:1703): it touches the release gates. You clear it on the board PR.
- Lead: shared step L2 (below): cut patches to the prerelease ref as ports merge, and roll back by the ref if the swarm stalls.
- You: report.py imports gh_cache.py, so gh_cache would be a sixth module under exception 3, which names five (HLD:278-281). A kind: lead story with a You: step asks you to agree that, or to have gh_cache bridged with one live implementation. The port stories that touch gh_cache depend on it (codex).

**Areas:**
- internal/ (report, events outcome, touches rows, gh cache)
- bin/lib/flow_report.py
- bin/lib/retro_report.py
- bin/lib/lifecycle.sh (the two inline sites)
- bin/swarm.sh (codex_story_prompt's inline site)
- bin/lib/board.sh (non_fix_cache's inline site)
- tests/ (comparison test, fixtures)

**Shared rules cited above:**
- L2: Lead: cut a v0.32.x patch to the prerelease ref as ports merge (HLD:307). If the swarm stalls, revert or fix the port on main, move the ref back and restart the sessions (HLD:433-436). After each patch, and before and after each stable move, the lead checks that stable and prerelease point at their expected tags: the lead and every agent share one gh login, so the ruleset cannot tell an agent's push from the lead's.
- P1: No stage: line. Every story is port: true, fix: true or tests-only. Anything else merged after v0.32.0 makes `next` ask for a minor (bin/lib/board.sh:477), and the freeze forbids it (HLD:345-348).
- P2: The six port steps (HLD:250-262). A tests-only PR first rewrites the inside-reaching tests to drive swarm.sh from outside, passes on the bash, and shows each rewritten check can fail. The port PR then adds the Go, deletes the bash and Python it replaces, adds the command's marker file, repeats the mutation proofs on the Go, corrects every doc line that names a deleted file, and shows a clean differential run against the tree just before.
- P3: One copy of each rule (goal 3). When bash left behind still calls a ported rule, that bash runs the binary for it in the same PR, through a `_` entry.
- P4: The Go takes the same lock files the same way and writes the same file formats (HLD:337-338,447-449). While any bash caller of a lock is left, a test has the bash hold it while the Go waits, and the reverse.
- P5: Rules packages reach herdr, gh, git and files only through the four interfaces, and time through the clock (go-layers). Every gh, herdr and git call keeps its time bound. SWARM_FORBID_PROJECT is refused (bin/swarm.sh:201-211).
- P6: The reviewer reads the deleted bash against the Go, rule by rule, with the inventory as the checklist (HLD:261-262; rules.md:13).
- P8: The file lists shrink with the files: the shellcheck list (Makefile:37; .github/workflows/ci.yml:41; AGENTS.md), py_compile (ci.yml:44), LINT_FILES (Makefile:47) and scripts/test-map.tsv's rows.
- P12: A story that changes a rule of the guard, merge, the release gates or the agents' environment while that rule is still bash is merged by the user, through a merge = human window as in ship-gates. A port that only swaps a call site in those files is not such a change.
- P13: A port's check that it starts no python3, awk, sed, perl or curl covers the ported body. The frame's own starts, such as the awk that checks SWARM_SLEEP_SCALE (bin/swarm.sh:120), are port-frame's, and the full check with a failing python3 on PATH is bash-retired's.
- P14: Any story, in any stage, that changes output on purpose adds its entry to its stage's allow list in its own PR, citing the story and the exact lines. port-checks writes the entries for the stories that merged before the list existed, ship-gates' two at least.
