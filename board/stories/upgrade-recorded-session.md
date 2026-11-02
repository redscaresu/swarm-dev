---
kind: code
status: ready
epic: merge-mechanics
depends_on: []
touches: [bin/lib/lifecycle.sh:upgrade_one, docs/reference-merging.md:Moving a running epic to a new version, tests/upgrade_test.sh:session cases]
estimate_lines: 80
easy: true
---

# upgrade resumes an agent from its recorded session when herdr has none (#694)

#694, first half (HLD:461-462; issue #694: upgrade to 0.28.1 moved 0 of 31 agents, herdr held no session id). upgrade_one (bin/lib/lifecycle.sh:5244-5291) dies at 5255 when session_for_pane (bin/lib/agents.sh:786-788) is empty. Fall back to recorded_session <name> (agents.sh:793-799, already used by upgrade_state at lifecycle.sh:5325) and print one line saying the session came from agents.tsv (rules.md: a repair path says what it did). Only when both are empty does it die as now, naming both sources. The recorded id feeds resume_file, the resume array and `herdr agent start --resume` exactly as herdr's id does. Nothing in the resume brief changes: upgrade sends no new brief (docs/running.md:154-156). upgrade_list keeps only claude agents (lifecycle.sh:5173), so a codex agent's empty recorded_session never reaches upgrade_one. tests/upgrade_test.sh:300-305 pins today's `conduct-e: herdr gives no session for it` line: that case becomes a resumed one, and a new case keeps the refusal for an agent with neither id.

**Done when:**
- tests/upgrade_test.sh: an agent herdr lists with no agent_session but with an agents.tsv session id is restarted with `--resume <that id>` in the stub's `agent start` call, and upgrade's output names agents.tsv as the source.
- tests/upgrade_test.sh: an agent with neither id is not restarted and gets no ctrl+c, and its line names both sources.
- docs/reference-merging.md's 'Moving a running epic to a new version' paragraph says where the session id comes from.
- The PR body shows both cases red with the fallback removed.
