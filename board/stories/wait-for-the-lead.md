---
kind: code
status: blocked
blocked_by: [flow-and-features]
epic: leaner-faster-swarm
depends_on: [flow-and-features]
touches: [bin/swarm.sh:wait_command, wait_lead, usage header: wait --lead line, commands/swarm.md:wait arm, docs/method.md:§ Who does what lead wakeups paragraph, tests/wait_lead_test.sh]
---

# `swarm.sh wait --lead` returns when the lead's queue gains an item, and /swarm handles it at once

Waits on flow-and-features (wait_command: the wait arm's body, out of dispatch). This fixes what happened on 2026-10-16, when three held stories waited 2 hours unnoticed. Add wait_lead, a `--lead [timeout-ms]` branch in wait_command, and a header line after the `wait --until-report` line (:8). It snapshots the lead's queue from the main checkout's board: escalated stories (is_escalated, bin/swarm.sh:2854: ready, kind: lead, escalated_from:), held ones being those with held_for:; and, with merge = human only, stories and epics in status: review whose every PR head is green (ci_gate head, called as it is). It polls every SWARM_LEAD_POLL seconds (default 30) and returns as soon as an item is new, printing one line per new item, `held: <slug> (<cause>)`, `escalated: <slug>` or `merge: <slug> <PR URL>`, and exits 0. A review item whose head is not green is not new until it is. At its timeout (default one hour, as wait's) it exits non-zero with nothing printed. It never nudges and changes no board file. As wait logs its nudges, it appends one `lead-woken <slug>` line to events.tsv per item it prints, and none while it waits; docs/features.tsv counts these. It calls is_escalated, waiting_on_user and ci_gate without editing them. commands/swarm.md's wait arm (:46-59): in the same response as `wait --until-report`, also start `swarm.sh wait --lead` in the background. When it returns, handle each line at once: for `held:` or `escalated:`, do the `escalated <slug>` step for that slug, since `next` names a running conductor first (:2753-2771) and would not reach it; for `merge:`, tell the user the PR waits on their merge. Then start it again; the conductor's wait keeps running. docs/method.md: a new paragraph at the end of § Who does what (after **Every stop names its exit.**, :98-101) on how the lead is woken. Tests in a new tests/wait_lead_test.sh, with stub herdr and gh. bash 3.2 (no mapfile, no associative arrays). shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` must pass. Leave README.md, AGENTS.md and .claude-plugin/plugin.json alone. Decline as out of scope any review finding about them, or about anything outside this story's touches and Done when. Run humanizer:humanizer over the docs/ and commands/ prose you change and over the PR description, and say so in the PR.

**Done when:**
- tests/wait_lead_test.sh: `wait --lead`, started on a board that already has one held story, does not return for it. Adding `held_for: paused` to another escalated story makes it return within two polls, printing `held: <slug> (paused)`. A story turned kind: lead with escalated_from: and no held_for: prints `escalated: <slug>`.
- With merge = human, a story set to status: review with a prs: line whose head the gh stub reports red prints nothing; once the stub reports it green, it prints `merge: <slug> <PR URL>`. With merge = agent, a review story prints nothing.
- With a stub herdr listing a running conductor, a new held story still makes it return.
- With no change it exits non-zero at a short timeout and prints nothing. events.tsv gains no line while it waits, and one `lead-woken` line per item it prints.
- A grep check: commands/swarm.md's wait arm names `wait --lead`, and says to do the `escalated <slug>` step for a held: or escalated: line without waiting for next.
- shellcheck, every tests/*_test.sh and `claude plugin validate .` pass.
