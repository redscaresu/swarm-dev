---
status: later
---

# The dash shows what is really happening and who has to act: only real user steps say "needs you", stale or stuck things are visible, and escalation to Fable is on screen

**Done when:**
- With `lead = session` in the config (new key, default off), the "needs you" box holds only steps nobody else can do: a story's **You:** lines, an expired login, a draft HLD. Every merge row (green, failing, running or unknown: a lead session merges for the user), `lead` stories with no **You:** line, WAITING agents (the lead answers dialogs, Fable consent included) and agents to look at go in a "lead's queue" box. A plan awaiting approval leaves no board signal and is not shown. With the key off, the dash is as today. A fixture board with one of each shows the split.
- `dash --watch` notices when the installed plugin version (installed_plugins.json; each version installs to its own directory) differs from the one it started on and re-execs the new script (the cause of the false "session ended" rows on 2026-10-15); a test swaps the version file and sees the new script run.
- Fable on call: the header shows the escalate role's model and effort (`on call: fable·xhigh`) and how many escalations today; an escalated builder's row is marked with its ladder step and the time it escalated; `escalate`, `dialog`, `escalated`, `reset` and `drop` events stand out in Recent with their times. Fixture events.tsv/agents.tsv lines show each.
- Each working agent's row shows how long it has been in its state (from STALL_PY's signs), marked once it passes `stall_minutes`.
- A running codex review shows in the dash with its age (codex-review leaves a marker while it runs; the story that adds the row adds the marker).
- Recent groups consecutive log-finding lines on one PR into one line (`8 findings declined on #133`), and a fixed finding shows once, not once from findings.tsv and again from events.tsv.
- The board story `dash-no-board` is absorbed: a folder with no board says so, names `swarm.sh init` and exits non-zero.

**Out of scope:** a web UI. Changing what `next` prints. Any change to infrafactory beyond turning the `lead` key on in its config.

**Constraints:** bash 3.2, python3 in the existing PANES_PY/STALL_PY style; shellcheck and every tests/*_test.sh; dash stays read-only (it never starts, tells or closes an agent). New keys default to today's behaviour. Stories that touch dash_render share one hot function: put them in separate waves or one story. Depends on flow-speedups' codex-time-limit only for the codex row. Bump plugin.json in a release story.

**Checks before every stage:** every PR passes shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .`; shows each new check failing with its code removed; and ran humanizer over changed README/docs prose and its description, saying so.

**Your part:** none; the plan was approved upfront on 2026-10-15. After the release the lead runs `claude plugin update` (an older swarm.sh refuses the unknown key) and turns on `lead = session` in swarm-dev's and infrafactory's config (infrafactory's via its own board PR).
