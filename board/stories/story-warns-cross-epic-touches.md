---
kind: code
status: blocked
blocked_by: [merge-command, tell-conductor-note, codex-time-limit, wait-until-report]
epic: lead-loop
depends_on: [merge-command, tell-conductor-note, codex-time-limit, wait-until-report]
touches: [bin/swarm.sh:build_story (touches warning), bin/swarm.sh:touches_overlap (new), bin/swarm.sh:dispatch (story arm, --strict), bin/swarm.sh:main (EV_TARGET story arm), bin/swarm.sh:usage header (story line), bin/swarm.sh:conduct_brief (warned-story rule), tests/epic_test.sh (story block; conductor brief checks), docs/method.md (§ Building, **Pick the wave.**)]
---

# `swarm.sh story` warns when another epic's open build touches the same function or file, and `--strict` refuses

build_story (bin/swarm.sh:1768), before it creates anything: read this story's touches and every other story's whose epic: differs (no epic counts as different). Split the bracketed list on commas outside parentheses, drop parentheticals, trim. `<file>:<fn>` entries match on fn exactly; file-only entries match on the file. For each overlap whose story is in review or has an open builder (builder_state, :2429; call it only for overlapping stories), print to stderr `warning: <other> (epic <e>) is open and touches <entry>; start <slug> after it merges` and go on. `--strict` makes that a die naming the other story, before any worktree, pane or brief. Parse in python3 (bash 3.2: no associative arrays). Dispatch's story arm (:4181) takes --strict; main logs the slug as target, not --strict. conduct_brief's shared tail tells the conductor to start a warned story only after the other merges. Docs: usage header story line, method.md § Building, **Pick the wave.**

**Done when:**
- tests/epic_test.sh story block: a (epic e1, ready, touches [bin/swarm.sh:tell_agent (note), docs/x.md]) and b (epic e2, review, touches [bin/swarm.sh:tell_agent (kinds)]): `story a` prints a warning naming b and tell_agent, and still starts a (herdr.log has its agent start).
- `story --strict a` exits non-zero naming b, herdr.log has no agent start for a, no story/a branch or worktree exists, and events.tsv's story line has target a.
- No warning when b is ready with no builder open, when b is in e1, or when b touches only bin/swarm.sh:tell_agent_x; a warning when b is ready and the herdr stub lists b's builder open; `docs/method.md (§ A; § B, C)` is read as one entry, docs/method.md.
- Both conductor briefs contain the warned-story rule.
- The PR shows each new check failing with its code removed; humanizer ran over the changed docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- The flag is `--strict` everywhere (dispatch, EV_TARGET, usage, method.md, tests).
- The conductor brief says: start each story with `swarm.sh story --strict <slug>`; on a refusal, start it after the named story merges. Without --strict, story warns and starts as the epic says.
- Parser: an entry with no '/' or '.' before any ':' or '(' inherits the previous entry's file (so `bin/swarm.sh:config defaults, CONFIG_KEYS` gives bin/swarm.sh:CONFIG_KEYS). A `<repo>: ` prefix sets the entry's repo, otherwise the story's `repo:` does; compare (repo, file[, fn]) only. A file-only entry overlaps any entry in that file.
- --strict refuses when builder_state is unknown; plain mode warns 'cannot tell'.
- Extra Done when: `bin/swarm.sh:x, CONFIG_KEYS` against `bin/swarm.sh:CONFIG_KEYS` warns; the same file in a different repo does not; with the listfail stub, --strict refuses and starts nothing; file-only `bin/swarm.sh` against `bin/swarm.sh:tell_agent` warns.
- method.md notes that with pr_per = epic the check misses stories already merged into an epic branch.
