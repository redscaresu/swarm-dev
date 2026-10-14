---
kind: code
status: blocked
blocked_by: [close-counts-a-failed-build]
epic: fable-on-call
depends_on: [close-counts-a-failed-build]
touches: [bin/swarm.sh:close_agent (escalate branch after counting), bin/swarm.sh:reset_story (new), bin/swarm.sh:dispatch (reset arm), bin/swarm.sh:usage header (reset line), tests/close_test.sh, tests/next_test.sh (gate block), tests/events_test.sh (reset logged), docs/method.md (§ Model and effort), board/stories/README.md, templates/docs/stories/README.md, README.md (§ Cost and safety)]
risk: high
---

# A failed escalate build makes the story a lead item for you; swarm.sh reset puts it back

In close_agent, after a counted close whose build was escalate (the newest agents.tsv line for agent_name(slug) has role escalate): set_fm kind: lead and escalated_from: <its kind, code when empty>, keep status: ready, and append a block between HTML-comment markers holding a **You:** step (decide: re-scope it, build it by hand, or drop it; `swarm.sh reset <slug>` builds it again) and the PR URLs from `gh pr list --head story/<slug> --state all --json url` in the story's repo, or a line that none was found (gh failed, or pr_per = epic). waiting_on_user (:1907) already lists a ready lead story and build_story (:1569) already refuses one: no change there. New `swarm.sh reset <slug>`: removes attempts:, restores kind from escalated_from and removes it, removes the marked block; a story with neither attempts: nor escalated_from is refused, named. A dispatch arm and a usage line; not in READ_ONLY_COMMANDS, so main logs it. Docs: § Model and effort (after Fable, you; reset), both stories READMEs (escalated_from, reset), README Cost and safety (reset).

**Done when:**
- tests/close_test.sh: a ready code story with attempts: 2, built as escalate and closed, ends with kind: lead, escalated_from: code, attempts: 3, status: ready, a **You:** line and both PR URLs the gh stub lists; with gh failing it says none was found.
- A counted close of a code build with attempts: 1 leaves kind unchanged.
- tests/next_test.sh: `next` on that board prints gate with `lead: <slug>`.
- `swarm.sh reset <slug>` on the escalated, otherwise unedited story returns the file as it was before its first counted close (diff against the fixture), `_role <slug>` gives code, and events.tsv has reset <slug> ok; reset of a story with neither field fails naming it.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Take the attempts' PR urls from the cleanup helper's single `gh pr list` output; no second gh call.
- A story with no kind line, escalated then reset, comes back with `kind: code` (stated as intended); the round-trip diff test uses an explicit `kind: code` fixture. Escalated_from round-trips for chore and verify too.
- A close_test case: newest agents.tsv role code with attempts already at escalate_after writes no kind: lead.
- README § When /swarm stops for you gains a row for an escalated story (kind: lead, escalated_from) and `swarm.sh reset`; skills/swarm-dev/SKILL.md names reset and the escalated item (tests/skill_test.sh then checks reset is a dispatch arm); both in touches, humanizer over them.
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).
