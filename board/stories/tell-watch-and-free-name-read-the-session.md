---
kind: code
status: ready
epic: agent-state-from-the-session
depends_on: [off-screen-nudge, status-and-dash-read-the-session]
touches: [bin/swarm.sh:tell_agent, bin/swarm.sh:watch_prs, bin/swarm.sh:free_agent_name, bin/swarm.sh:dispatch (tell arm), bin/swarm.sh:main (tell target), bin/swarm.sh:review_rule, bin/swarm.sh:usage header :10, tests/next_test.sh (tell block), tests/review_test.sh (name and watch blocks), tests/epic_test.sh:91, tests/events_test.sh (tell lines), commands/swarm.md:58, docs/method.md (:237; § Building watch sentence)]
risk: high
---

# `tell`, `watch` and free_agent_name read the session; `tell` takes a kind

tell_agent refuses busy (still working), waiting (names waitingFor; text must never land in a dialog) and gone, and delivers to idle. The command becomes `tell <slug> <kind> <file>`, where kind is findings, nudge or resume; there is no default, and an unknown kind dies listing the three. The events line keeps the slug as its target (STALL_PY.last_seen and dash read it) and carries the kind. watch_prs (:1675-1684) lists its own agents whose session is waiting, with waitingFor. free_agent_name (:2488-2498) refuses a busy or waiting holder and retires an idle or gone one. Codex and no-session agents keep herdr, and the `any` checks and retire_agent stay. In this PR, update the usage line :10, the dispatch arm :2614, main's target for tell, review_rule :934, commands/swarm.md:58, docs/method.md:237 and § Building's watch sentence. AGENTS.md:42 is a shared file: the lead edits it, alone, after this PR merges; this story does not touch it.

**Done when:** When herdr says `done` and the session says `busy`, tell refuses with 'still working' and free_agent_name refuses before any pane opens. A `waiting` agent makes tell refuse and watch return, both naming waitingFor. When herdr says `blocked` and the session says `busy`, watch does not return. tell refuses gone. herdr `working` with session `idle` lets tell deliver and free_agent_name retire. Another project's holder is still refused. A reused name reads the newer line. tell with no kind, or with an unknown kind, fails. The events line's target is the slug and the line carries the kind. next_test's tell block (:221-262), review_test's name and watch blocks (:218-237, :301-320), epic_test:91 and the tell lines in events_test are all updated. Each new test is shown red on the old code.

**From review (binding; overrides the scope above where they differ):**
- The events line keeps 5 fields: target = slug, outcome = ok/die; the kind goes in the command field as `tell:<kind>`. Update events_test:74,118 and dash_test:430-442. Done when adds: every events line still has 5 fields, and a tell still lowers that builder's stall age through last_seen.
- Codex and no-session reads in tell_agent, watch_prs and free_agent_name go through session-reader-and-wait's named fallback helper; remove the direct reads at :897, :1677 and :2490. Replace the post-retire check (:2497) with `agent_field "$1" pane_id` being empty.
- free_agent_name checks herdr's holder first: no herdr holder means the name is free, whatever an old session says. tell and free_agent_name refuse on `unknown`.
- Done when adds: an old line whose session is busy while herdr has no holder lets the start proceed; unknown is refused by tell and free_agent_name; retire followed by the post-check succeeds.
