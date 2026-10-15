---
kind: code
status: blocked
blocked_by: [stall-sees-uncommitted-work]
epic: lead-loop
depends_on: [stall-sees-uncommitted-work]
touches: [bin/swarm.sh:is_tell_kind, bin/swarm.sh:tell_agent (note branch), bin/swarm.sh:conduct_brief (inbox rule), bin/swarm.sh:STALL_PY (sign_time skips tell:note), bin/swarm.sh:usage header (tell line), tests/next_test.sh (tell block), tests/epic_test.sh (conductor brief checks), tests/dash_test.sh (conductor stall rows), docs/method.md (tell kinds; events.tsv paragraph)]
---

# `swarm.sh tell <conductor> note <file>` leaves a busy conductor a note in its inbox, and the conductor reads it after each wait

is_tell_kind (bin/swarm.sh:1399) accepts note, so main logs tell:note (bin/swarm.sh:4283). tell_agent (bin/swarm.sh:1407): after the kind and file checks and before the pane/state gate (:1412-1427), a note refuses unless the name is a live conductor's (conduct-*, not -done<N>, the test dispatch's wait arm uses at :4216), then appends a timestamped 'From the lead:' block and the file to ${PROJECT_DIR}/.swarm/inbox/<name>.md (mkdir -p) and prints 'noted <name>'. It never delivers a prompt and never reads state, so busy, waiting or idle all take it; a builder still refuses as today. conduct_brief's shared tail (:1849-1862) tells the conductor: after each wait returns, read .swarm/inbox/<name>.md, act on it, then empty it. STALL_PY sign_time (:461-465) skips tell:note: the dash counts a conductor's own events lines as signs of life (docs/method.md:133, bin/swarm.sh:3369), and a note is no sign the conductor works. Docs: usage header tell line (:10), the die text listing kinds, method.md's tell kinds and events.tsv paragraph. No README change: the user never runs tell.

**Done when:**
- tests/next_test.sh tell block: with conduct-e's stub session busy, `tell conduct-e note <file>` exits 0, .swarm/inbox/conduct-e.md holds the file's text, herdr.log gains no `agent prompt`, and events.tsv gains `tell:note conduct-e ok`.
- A second note to conduct-e appends: the inbox holds both texts, first one first.
- `tell s1 note <file>` (a builder) exits non-zero naming conductors, and no inbox file exists; `tell conduct-e bogus <file>` refuses and its message lists note with findings, nudge and resume; the existing tell checks pass unchanged.
- tests/epic_test.sh: the story-mode and epic-mode conductor briefs both contain `.swarm/inbox/conduct-<epic>.md` and the read-then-empty rule.
- tests/dash_test.sh: a working conductor whose only events line inside stall_minutes is an ok `tell:note` to it shows stalled; the same line as `tell:resume` shows working.
- The PR shows each new check failing with its code removed; humanizer ran over the changed docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Keep the agent_field pane_id check (this project started a conduct-* agent of that name) ahead of the note branch; skip only the busy-state refusal. `tell conduct-zz note f` with no such agent exits non-zero, writes no inbox file and logs no ok line.
- Brief rule: after each wait or watch returns, `mv` .swarm/inbox/<name>.md aside (atomic, so a later append makes a new file), then read the moved copy and act on it. epic_test greps for the mv wording.
- tell:note is not a sign of life in STALL_PY. dash_test: in both the tell:note and the tell:resume control cases, the conductor's session .jsonl mtime is older than stall_minutes.
