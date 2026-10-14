---
kind: code
status: blocked
blocked_by: [goal-condition]
epic: goal-for-builders
depends_on: [goal-condition]
touches: [bin/swarm.sh:build_story (goal send after start_agent), bin/swarm.sh:deliver_prompt (send-once mode), bin/swarm.sh:goal_entry (new), tests/epic_test.sh (herdr stub at the top: session .jsonl; Layout block), docs/method.md (§ Building, new **The goal.** paragraph), README.md (How it works step 3)]
risk: high
---

# With goal on, story sends the builder its /goal once after the brief and confirms it set from the transcript

Once start_agent returns (the brief taken up), build_story sends `/goal <the .goal.md condition>` with a send-once mode of deliver_prompt, since a retry would reset a goal that set. A new reader, goal_entry <name> <since-epoch>, prints the kind of the newest goal entry written after <since>: set, refused, met, impossible, stalled, bound, paused or cleared-on-error, as the spike quoted them. It reads the session .jsonl for the agents.tsv session id through REPORT_PY's session_log under CLAUDE_PROJECTS, never the pane and never agent_status. build_story waits for a set or refused entry newer than the send, within deliver_prompt's timeout. On set it exits 0. On refused, or no entry, it exits non-zero naming the story and Claude Code's reason (or that no entry came), and leaves the builder open. tests/agent_state_test.sh's ALLOWED is not edited. Test fixture: the herdr stub in tests/epic_test.sh writes <CLAUDE_PROJECTS_DIR>/p/<session-id>.jsonl on `agent start`, and on an `agent prompt` that starts /goal it appends the set or refused entry an env var picks. Docs: a new **The goal.** paragraph in method § Building, after the wait paragraph (the goal, its bound, a refusal), and README How it works step 3; humanizer over them.

**Done when:**
- tests/epic_test.sh, Layout block: with goal off, `story` sends one `agent prompt` (the brief). With goal = 7 and the stub writing the set entry, a second `agent prompt` follows the brief, its text /goal plus the .goal.md contents, and `story` exits 0.
- With the stub writing the refused entry, `story` exits non-zero naming the story and the refusal reason, and herdr.log shows no pane close for it. With no entry written (the pane alone would show a goal set), `story` fails.
- In each failing case herdr.log holds exactly one /goal prompt: nothing is resent.
- tests/agent_state_test.sh passes with ALLOWED unchanged.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From the spike (binding; overrides the scope above where they differ; report: .swarm/goal-spike.report.md, Claude Code 2.1.299; user chose form 1, bound 5, on 2026-10-14):**
- Form 1: `/goal <condition>` pasted with `herdr agent prompt`, sent once the brief's turn is idle (mid-turn also sets, but queues one extra turn).
- Confirm only from the session .jsonl: an attachment `goal_status` with `sentinel:true` and this condition, newer than the send. Never the pane.
- Refused (hooks restricted, or an untrusted folder): a `system/local_command` stdout line (`/goal can't run while hooks are restricted…` or `/goal is only available in trusted workspaces…`) and no sentinel; `story` fails naming the story.
- No Stop-hook or launch-prompt path; drop any worktree settings file.
