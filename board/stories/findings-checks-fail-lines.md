---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:findings, mutation_rule, usage header: findings line, docs/method.md:§ Building green paragraph, tests/fail_lines_test.sh]
---

# `swarm.sh findings` names each new test whose FAIL line is missing from the PR body as `rules-unchecked`, with the command that logs it

This makes the vacuous-test rule a mechanical check. findings (bin/swarm.sh:3811-3854) also reads the PR's body and diff (gh pr view --json body, gh pr diff). It finds each test the diff adds or changes, by the names on added lines in test files: Go `func TestX`, Python `def test_x`, bash `check` lines in tests/*_test.sh, JS `it(` and `test(`. Each name needs a line in the body that contains FAIL and the name. For each one missing, findings prints `rules-unchecked: <name> has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked <PR URL> …)`. The conductor triages that line like any other findings note and logs it as finding_rule already says for one (`--reviewer ci`), so no conductor rule changes: do not touch green_rule, finding_rule, rules_review_rule or review_rule. mutation_rule (:1996-1999) tells builders to paste each test's FAIL line into the PR body, not just note it, and keeps the phrase 'prove each new or changed test can fail', which tests/epic_test.sh checks. The header's findings line (:34). docs/method.md: only the **Green means more than green checks.** paragraph (:645-648). Tests in a new tests/fail_lines_test.sh, with a gh stub. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/fail_lines_test.sh: a PR diff that adds `func TestFoo`, with a body that holds no FAIL line for it, makes findings print `rules-unchecked: TestFoo has no FAIL line in the PR body` followed by `log-finding --reviewer ci rules-unchecked` and the PR URL. With `--- FAIL: TestFoo` in the body, it prints no such line.
- A new `check` line in a tests/*_test.sh file is matched in the same way, and a PR that changes no test file prints no rules-unchecked line.
- The same test greps mutation_rule's body in bin/swarm.sh for the instruction to paste the FAIL line into the PR body, and tests/epic_test.sh's mutation checks pass unchanged.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.
