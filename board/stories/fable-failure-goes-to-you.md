---
kind: code
status: blocked
blocked_by: [close-counts-a-failed-build]
epic: fable-on-call
depends_on: [close-counts-a-failed-build]
touches: [bin/swarm.sh:close_agent (escalate branch after counting), bin/swarm.sh:next_step (escalated step), bin/swarm.sh:reset_story (new), bin/swarm.sh:dispatch (reset arm), bin/swarm.sh:usage header (reset line), tests/close_test.sh, tests/next_test.sh (gate block), tests/events_test.sh (reset logged), docs/method.md (§ Model and effort), board/stories/README.md, templates/docs/stories/README.md, README.md (§ Cost and safety)]
risk: high
---

# A failed escalate build makes the story a lead item for you; swarm.sh reset puts it back

In close_agent, after a counted close whose build was escalate (the newest agents.tsv line for agent_name(slug) has role escalate): set_fm kind: lead and escalated_from: <its kind, code when empty>, keep status: ready, and append a block between HTML-comment markers holding the lead's choices (re-scope it and `swarm.sh reset <slug>`, or drop it; at most one reset per story) and the PR URLs from `gh pr list --head story/<slug> --state all --json url` in the story's repo, or a line that none was found (gh failed, or pr_per = epic). waiting_on_user (:1907) already lists a ready lead story and build_story (:1569) already refuses one: no change there. New `swarm.sh reset <slug>`: removes attempts:, restores kind from escalated_from and removes it, removes the marked block; a story with neither attempts: nor escalated_from is refused, named. A dispatch arm and a usage line; not in READ_ONLY_COMMANDS, so main logs it. Docs: § Model and effort (after Fable, the lead decides; reset), both stories READMEs (escalated_from, reset), README Cost and safety (reset).

**Done when:**
- tests/close_test.sh: a ready code story with attempts: 2, built as escalate and closed, ends with kind: lead, escalated_from: code, attempts: 3, status: ready, the lead's-choices block (no **You:** line) and both PR URLs the gh stub lists; with gh failing it says none was found.
- A counted close of a code build with attempts: 1 leaves kind unchanged.
- tests/next_test.sh: `next` on that board prints `escalated <slug>`, not gate.
- `swarm.sh reset <slug>` on the escalated, otherwise unedited story returns the file as it was before its first counted close (diff against the fixture), `_role <slug>` gives code, and events.tsv has reset <slug> ok; reset of a story with neither field fails naming it.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Take the attempts' PR urls from the cleanup helper's single `gh pr list` output; no second gh call.
- A story with no kind line, escalated then reset, comes back with `kind: code` (stated as intended); the round-trip diff test uses an explicit `kind: code` fixture. Escalated_from round-trips for chore and verify too.
- A close_test case: newest agents.tsv role code with attempts already at escalate_after writes no kind: lead.
- README § When /swarm stops for you gains a row for an escalated story (kind: lead, escalated_from) and `swarm.sh reset`; skills/swarm-dev/SKILL.md names reset and the escalated item (tests/skill_test.sh then checks reset is a dispatch arm); both in touches, humanizer over them.
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).

**From the user (2026-10-15; binding, overrides the scope and the review notes above where they differ):** "You should decide the escalation not me." The escalated story carries no **You:** step. The marked block names the lead's choices instead: re-scope and `swarm.sh reset <slug>`, or drop it, with at most one reset per story. `next_step` prints `escalated <slug>` for a ready `kind: lead` story that has `escalated_from`, ahead of `gate`, so /swarm acts on it instead of stopping. tests/next_test.sh checks that line in place of `gate` with `lead: <slug>`. README § When /swarm stops for you gets no row for it. The docs say the lead decides and tells the user.

**From the user (2026-10-15; binding): log when each escalation step happened.** "It should be noted though as part of the logs for the training data when exactly this escalation occured." agents.tsv records only the date, and events.tsv's `story` line does not name the role. So each step writes its own events.tsv line, with log_event's UTC timestamp:
- `escalate <slug>`, result `attempt <n>`: build_story starts a build as escalate.
- `escalated <slug>`, result `attempts <n>, <k> PRs`: close_agent turns the story into `kind: lead`.
- `reset <slug>`, result the reason: `swarm.sh reset <slug> <reason>` takes a required reason, which the lead writes.
- `drop <slug>`, result the reason: new `swarm.sh drop <slug> <reason>` only logs. A board PR deletes the story file.

Tests: tests/events_test.sh checks each line's command, target and result, and that reset or drop with no reason fails, naming the missing argument. touches adds bin/swarm.sh:build_story and bin/swarm.sh:drop (new, dispatch arm, usage line).
