---
kind: code
status: blocked
blocked_by: [goal-wait-no-nudge, codex-time-limit]
epic: flow-speedups
depends_on: [goal-wait-no-nudge, codex-time-limit]
touches: [bin/swarm.sh:wait_conductor, bin/swarm.sh:dispatch (wait arm), bin/swarm.sh:usage header (wait line), tests/epic_test.sh (the wait block), docs/method.md (§ Building, the wait paragraph), commands/swarm.md (step 2, the wait bullet), tests/next_test.sh (conductor wait block), README.md (wait line)]
---

# `swarm.sh wait --until-report conduct-<epic>` waits past the hour until the conductor reports, needs a login or is stuck on a prompt, and never nudges

The dispatch wait arm accepts `--until-report`, only for a conductor name (anything else dies naming conductors), and calls wait_conductor with timeout 0. wait_conductor reads 0 as no deadline: each wait_agent slice gets 3600000, and it loops until a report exists or the state is waiting, gone or auth. Plain `wait` keeps 3600000. commands/swarm.md step 2 runs `swarm.sh wait --until-report <agent>` in the background and drops 'the wait's timeout (an hour)'. The usage header and method.md's wait paragraph name the flag.

**Done when:**
- tests/epic_test.sh, the wait block: with the herdr stub keeping conduct-e idle, SWARM_CONDUCTOR_POLL=1, and the report written 4 s after start, `wait --until-report conduct-e` exits 0 printing idle, and only after the report exists (elapsed >= 4 s).
- With the stub's session waiting on a prompt it returns `waiting: ...`. With a transcript ending on 'Login expired' it prints `auth`. In both cases herdr.log has no `agent prompt` and events.tsv has no nudge line.
- `wait --until-report s1` fails naming conductors. `wait conduct-e 2000` with no report still returns 1 after about 2 s, and the existing wait checks pass unchanged.
- grep finds `--until-report` in commands/swarm.md's wait step and not 'an hour' there.
- The PR shows each new check failing with its code removed; humanizer ran over the changed README/docs/commands prose and the PR description, and the PR says so; shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Depends on codex-time-limit too (both edit the usage header, dispatch, commands/swarm.md and method.md).
- The checks go in tests/next_test.sh's conductor block (:181-292), reusing waitc, session and stub; add tests/next_test.sh to touches.
- Add a slice override for tests, SWARM_CONDUCTOR_SLICE_MS (default 3600000). With --until-report, a busy rc-1 return from wait_agent loops again instead of breaking.
- Extra Done when: session busy, slice 1000 ms, flipped to idle with the report written after 3 s: `wait --until-report conduct-e1` exits 0 printing idle only after the report, having crossed several slices. Replace 'still returns 1' with: plain `wait conduct-e 2000` still prints idle at about 2 s, as tests/next_test.sh:265-270 checks. The no-nudge and no-prompt checks are regression guards, named that way.
- README.md lists the new flag beside the wait command (AGENTS.md: a user-visible change updates README).
