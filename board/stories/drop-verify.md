---
kind: code
status: ready
epic: leaner-faster-swarm
depends_on: []
touches: [bin/swarm.sh:ROLE_GROUPS, policy, agent_kind, held_story, templates/docs/stories/README.md, docs/method.md:§ Who does what kinds paragraph, § Model and effort reading-and-running bullet, tests/roles_test.sh, tests/dash_test.sh:ladder verify check, tests/next_test.sh:verify kind case]
---

# The verify kind and role go

Check that neither swarm-dev's nor ../infrafactory's board has a `kind: verify` story, and quote the grep in the PR. Remove the verify role and kind from the functions this story owns: ROLE_GROUPS (bin/swarm.sh:292) and policy's verify arm (:311); agent_kind (:2223-2225), so `next`, `status` and dash treat a `kind: verify` story as one no agent builds, as they treat a typo; held_story's verify sentence (:5147-5148) and the verify and pr_per mentions in its comments (:5142, :5157). The other functions that name verify are drop-epic-prs' (build_story, failed_build, nudge_reason), drop-unused-switches' (close_agent) and backlog-conductor's (conduct_brief), and export_report's ENUMS line (:1462) goes with export_report in flow-and-features; each removes it there. templates/docs/stories/README.md: the kind list (:12) and the verify hold (:30). docs/method.md: the § Who does what paragraph that lists the kinds ('A merge is never a story of its own', :89-91) and the § Model and effort bullet **Reading is Sonnet, running is Haiku.** (:194-196). Tests: tests/roles_test.sh (:48), tests/dash_test.sh's ladder check (:72, :215), and a new tests/next_test.sh case. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ and templates/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- `swarm.sh policy verify` exits non-zero naming the roles, `swarm.sh policy chore` still prints `claude haiku medium`, and `swarm.sh dash --ladder` has no verify row.
- tests/next_test.sh: a ready `kind: verify` story gets no `conduct` or `story` step, and `swarm.sh status --all` lists it under what waits on you as `verify: <slug>`, as for any kind no agent builds.
- `grep -nw verify templates/docs/stories/README.md` prints nothing, and held_story's message has no verify sentence.
- The PR quotes the board greps of both projects.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.
