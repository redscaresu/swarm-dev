---
kind: code
status: blocked
epic: safer-faster-swarm
depends_on: [fallback-reviewer]
touches: [bin/lib/build.sh:review_agent brief, commands/swarm.md, tests/review_test.sh]
easy: true
estimate_lines: 60
---

# The review agent's brief carries the checks the lead learned by hand

From the lead's memory (memory-rules-into-framework). The review agent's brief and the fallback reviewer's brief gain a short checklist, one line each:
- a claim checked against a stand-in (a mock, a sibling API, a narrower sample) is unverified;
- an audit or test scoped to one file, when the defect class spans many, is a finding;
- a new code path must enforce every rule the existing paths enforce;
- a zero or empty value shown to a person must say what it means;
- a repair path that changes something must say what it did;
- a change that contradicts a decision marked `(user, <date>)` in the epic or story is a finding, even when it is stricter.
Each line is under 200 bytes, so the brief stays short. outcomes' recurring kinds later show whether each line lowered its kind.

**Done when:**
- tests/review_test.sh greps the review agent's brief and the fallback brief for each of the six lines.
- A fixture epic with a `(user, 2026-10-17)` decision and a PR that reverses it: the brief the review agent receives includes that decision line.
