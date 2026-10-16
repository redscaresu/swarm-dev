---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:codex_review, codex_review_cmd, usage header: codex-review line, docs/method.md:§ Building codex-review run sentence, tests/codex_test.sh]
---

# `codex-review` can be given the story, so codex reviews against its touches and Done when

With SWARM_STORY=<slug> set, codex_review (bin/swarm.sh:5526-5557) reads <board>/stories/<slug>.md and runs `codex exec review '<prompt>'` without --base, because codex refuses a prompt beside --base. The prompt says to review this branch's changes against origin/<base> (git diff origin/<base>...HEAD), lists the story's touches and its **Done when** items, and says that work outside them is not a finding. A SWARM_STORY that names no story fails before codex starts. Without SWARM_STORY nothing changes. codex_review_cmd (:1904) takes an optional slug and, when given one, prints the SWARM_STORY= prefix. No caller passes a slug yet; scoped-parallel-reviews does. The header's codex-review line (:39). The time limit, the marker and the signal handling stay as they are. Do not touch dispatch, review_rule, codex_rule or story_brief. docs/method.md: only the codex-review paragraph's sentence on how codex is run ('It runs `codex exec review --base origin/<base>` with no prompt', :610-611). Check first that the installed codex accepts this form (`codex exec review --help`). bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/codex_test.sh: with SWARM_STORY set, a stub codex records an argv with no --base and a prompt that holds origin/<base>, each touches entry, each Done when item and `not a finding`. Without SWARM_STORY the argv is `exec review --base origin/<base>`, as today.
- SWARM_STORY=missing fails naming the story file, and the stub codex never runs.
- The PR quotes `codex --version` and the `codex exec review --help` lines showing that it takes a prompt without --base.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.
