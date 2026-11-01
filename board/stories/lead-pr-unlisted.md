---
kind: code
status: ready
epic: merge-mechanics
depends_on: []
touches: [bin/lib/board.sh:next_report, bin/lib/board.sh:unlisted_prs (new), commands/swarm.md:unlisted line, docs/reference-lead.md:next's unlisted line, docs/lead-by-hand.md:A PR outside any story, tests/next_test.sh:unlisted PR cases, tests/merge_rules_test.sh:lead story PR case, tests/*_test.sh:next output (only suites whose output changes; listed in the PR)]
estimate_lines: 200
easy: false
---

# next names an open lead PR that no story or epic lists (#692)

#692 (HLD Goal 12, HLD:458-459). The merge route for a listed lead PR already works: merge_pr's item loop (bin/lib/merge.sh:1038-1050) takes any story or epic with the URL on prs: and status review, and mark_review (bin/lib/board.sh:2519-2551) has no kind check, so a kind: lead story's PR listed by `swarm.sh review <slug> <url>` merges; merge_caller (merge.sh:145-176) lets the lead's pane merge. The epic's 'refused at merge.sh:866' was not reproduced (see contradictions): pin the route with a test, change no merge code. The gap is the unlisted PR (the v0.29.0 cases were a config-only PR and a lead doc fix, issue #692). New: next_report (board.sh:697-750) prints one line per open PR in the board's repo that the gh user opened (`gh pr list --author @me`), whose head is not story/*, board/* or release/v*, and that no story or epic lists on prs:: `unlisted: <PR URL> (<head>): no story or epic lists it; list it under the kind: lead story that covers it with swarm.sh review <slug> <url>, then swarm.sh merge <url>; with none, it waits on the user`. One gh call, made under next_reads' deadline (report_read, board.sh:669-693); a cut or failed read prints a line saying the check did not run, never nothing (rules.md: an empty value says what it means). Not in next_step: dash and status run it every frame and it makes no gh call (board.sh:405-406). commands/swarm.md says what the lead does with the line. Keep merge's refusal text: tests/merge_rules_test.sh:26 and tests/merge_protected_hold_test.sh:97 pin it. Remove docs/lead-by-hand.md's 'A PR outside any story' block (lines 24-29). About 20 other suites run next with a stub gh (tests/after_key_test.sh, dash_check_test.sh, next_time_limit_test.sh and others: `grep -l next tests/*.sh`). Make the unlisted read stub-safe: it runs only when the stub or gh answers `pr list`, and a stub that does not know the call gets the did-not-run line. Run every one of those suites; edit only those whose output really changes, and list each such file in the PR body.

**Done when:**
- tests/next_test.sh: with a gh stub listing three open PRs by @me (head docs/x listed nowhere, head story/s, head fix/y on a story's prs:), `swarm.sh next` prints an `unlisted:` line for docs/x only, after the step's lines.
- tests/next_test.sh: when the stub's pr list fails, next prints a line saying the unlisted check did not run, and the step line is unchanged.
- tests/next_test.sh: a `swarm.sh status` run leaves no `pr list --author` call in the stub's log (next_step makes no new gh call).
- tests/merge_rules_test.sh: after `swarm.sh review <slug> <url>` for a kind: lead story, `swarm.sh merge <url>` reaches the stub's `pr merge`; a PR no item lists still fails with `no story or epic lists`.
- docs/reference-lead.md names the unlisted: line, docs/lead-by-hand.md has no 'A PR outside any story' block, and tests/doc_check_test.sh passes.
- Every suite that runs next passes, and the PR body lists any it changed and why.
- The PR body shows each new case going red with the code it guards removed (worktree-copy method, AGENTS.md).
