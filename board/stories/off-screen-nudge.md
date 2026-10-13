---
kind: code
status: blocked
blocked_by: [session-reader-and-wait]
epic: agent-state-from-the-session
depends_on: [session-reader-and-wait]
touches: [bin/swarm.sh:ended_on_api_error (deleted), bin/swarm.sh:wait_agent, bin/swarm.sh:wait_conductor, bin/swarm.sh:STALL_PY.last_seen, tests/epic_test.sh (nudge block :213-231), tests/next_test.sh (:158-166), tests/events_test.sh (nudge line), commands/swarm.md:27, docs/method.md (§ Building wait paragraph; § The audit log)]
---

# `wait` nudges an idle builder that has no PR, logs each nudge, and no longer reads the pane

Delete ended_on_api_error (:758-762) and its callers (:861, :880). wait_agent nudges a session that reports idle when all of these hold: its name maps to a story (stall_py story, as in :803-805); with pr_per = story, story/<slug> has no PR (`gh pr list --head`, any state); with pr_per = epic, story/<slug> has not been pushed. It nudges up to API_ERROR_NUDGES times per wait. A gh or git failure counts as having a PR. Each nudge calls record_event `nudge <name>`; wait itself stays read-only. STALL_PY.last_seen skips `nudge` lines, so the signs of life stay as they are. A name with no story (conductor, hld, planner) is never nudged. wait_conductor does not nudge and waits for the report or the timeout. In this PR, update commands/swarm.md:27 and docs/method.md (§ Building's wait paragraph; § The audit log).

**Done when:** An idle builder with no PR is nudged exactly API_ERROR_NUDGES times, and the events log holds that many `nudge <name>` lines. A builder with a PR, or a pushed branch in epic mode, is not nudged, and neither is one whose gh call fails. An idle conductor with no report is not nudged, and wait returns at the timeout (next_test.sh:158-166 inverted). `grep ended_on_api_error bin/swarm.sh` finds nothing. A `nudge` line does not lower a builder's stall age. Each new test is shown red on the old code.

**From review (binding; overrides the scope above where they differ):**
- Nudge only stories of kind code, docs or chore (from the story's front matter); never verify, whose idle return goes to the lead.
- Resolve the story's repo with repo_dir "$(fm story repo)" as story_commit_time does; run `gh pr list -R <that repo> --head story/<slug> --state all`, and in epic mode `git -C <src> ls-remote --exit-code origin story/<slug>`. A resolve failure counts as having a PR.
- Deliver the nudge without herdr's `--until working`; then wait at least one STALL_POLL_MS slice, or until the session reads busy, before another nudge. New nudge text names the reason ('you are idle and story/<slug> has no PR'); rename API_ERROR_NUDGES to IDLE_NUDGES and rewrite its comment (:751); a test greps the prompt text.
- `wait` is in READ_ONLY_COMMANDS: state the new contract (a read-only command logs only `nudge` lines) in § The audit log, and assert in events_test that a nudging wait appends only `nudge` lines.
- Done when adds: three nudges are spread over at least two slices on a fixture that stays idle; a verify story is not nudged; with repos_dir set, a builder whose PR sits in the story's repo is not nudged.
- This story and status-and-dash-read-the-session both edit docs/method.md § Building in wave 4: the second to merge rebases.
