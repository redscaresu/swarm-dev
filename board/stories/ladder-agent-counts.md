---
kind: code
status: blocked
blocked_by: [infrafactory-epic-on-agent-state]
epic: fable-on-call
depends_on: [infrafactory-epic-on-agent-state]
touches: [bin/swarm.sh:dash python (ladder_box only), tests/dash_test.sh (ladder block :191-205), docs/dash.md (:53)]
---

# dash --ladder shows, per role, how many agents agents.tsv recorded and the models their sessions ran on

In dash's python, ladder_box (bin/swarm.sh:2992-2997): beside each role's policy model, the number of agents.tsv lines with that role and the models named by the first message carrying a model in each such session's .jsonl. Reuse REPORT_PY's session_log (dash already execs REPORT_PY, :2599-2602); stop reading a file at its first model, so a --watch redraw stays cheap. A role with no lines shows 0 (escalate does today); a session with no log or no model counts but names no model. cost (:932-960) is unchanged. docs/dash.md:53 says what the ladder now shows.

**Done when:**
- tests/dash_test.sh: with an agents.tsv fixture of two code lines, one escalate line whose session's first assistant message is a claude-opus model, and no verify line, `dash --ladder` shows code 2, escalate 1 with opus (not fable), and verify 0.
- The PR shows that check failing with the count removed, and with the model taken from policy instead of the session.
- docs/dash.md describes the count and the session model; humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).
