---
kind: code
status: ready
epic: review-yield
depends_on: []
touches: [bin/swarm.sh:record_finding, bin/swarm.sh:REPORT_PY (finding_rows and its comment), bin/swarm.sh:decisions_report (finding_accept unpack), bin/swarm.sh:dispatch (log-finding arm), bin/swarm.sh:main (EV_TARGET log-finding arm), bin/swarm.sh:usage header (log-finding line), tests/lessons_test.sh, tests/decisions_test.sh, tests/events_test.sh (log-finding lines), docs/method.md (§ Learning across epics, :425-426 and :440-442)]
risk: high
---

# findings.tsv records which reviewer raised each finding: `log-finding --reviewer <who>` writes a sixth column, and finding_rows reads rows of any width

record_finding (bin/swarm.sh:769-786) takes a reviewer and appends it as field 6: codex, code-review, conductor, lead or unknown; anything else dies naming them, before any write. The dispatch log-finding arm (:4237-4238) peels `--declined` and `--reviewer <who>` in either order before the kind; no `--reviewer` writes unknown. main's log-finding arm (:4315-4318) skips the same flags so the events target stays `<kind> <pr>` and the command stays log-finding or log-finding:declined (the dash's declined-run grouping reads the target's last word, :3639-3646). REPORT_PY finding_rows (:807-811) reads by width: a row of 4+ fields is kept when field 5, if present, is fixed|declined and field 6, if present, is a reviewer value; fields past the 6th are ignored, so a later appended column drops nothing; it returns (date, kind, pr, text, outcome, reviewer), padding fixed and unknown. decisions_report's finding_accept loop (:1131) unpacks six; no new decision fields. fixed_rows keeps f[:4], so lessons (:886), outcomes (:1061) and dash (:3628) are unchanged. Update the usage header (:14), record_finding's usage die and comments (:769-771, :789-790), and method.md's log columns (:440-442) and log-finding mention (:425-426). This is the interface training-export reads by column. No open flow-speedups, lead-loop or dash-tells-the-truth story changes these functions, so it lands first; outcomes-every-attempt (absorbed by training-export) also edits tests/decisions_test.sh and rebases on it.

**Done when:**
- tests/lessons_test.sh: `log-finding --reviewer codex k <pr> t` appends a row whose field 5 is fixed and field 6 codex; `--declined --reviewer code-review` and `--reviewer code-review --declined` both append declined<TAB>code-review; with no flag field 6 is unknown; `--reviewer bot` and a bare trailing `--reviewer` exit non-zero and append nothing.
- tests/lessons_test.sh: a kind fixed once in each of a 4-field, a 6-field and a 7-field row on three PRs is a lessons candidate; the same three PRs where the 6-field row's reviewer is `bogus` is not.
- tests/decisions_test.sh: a 6-field declined row and a 7-field fixed row each give one finding_accept with chosen declined and fixed; the existing 4- and 5-field fixture objects (:65-66) are unchanged.
- tests/events_test.sh: `log-finding --reviewer codex --declined k <pr> t` and `log-finding --declined --reviewer lead k <pr> t` each log `log-finding:declined` with target `k <pr>`; `log-finding --reviewer conductor k <pr> t` logs `log-finding` with target `k <pr>`.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Enum: codex, code-review, ci (a PR review bot, check-run notes or code-scanning alerts from `swarm.sh findings`), conductor, lead, unknown for old lines.
- tests/lessons_test.sh's tab-test NF check becomes 6. Cite method.md by section (§ Learning across epics), not line numbers.
- dispatch, main's EV_TARGET and usage-header lines are shared with codex-time-limit, tell-conductor-note, merge-command, wait-until-report, board-pr-command and story-warns-cross-epic-touches: separate arms, rebase only.
