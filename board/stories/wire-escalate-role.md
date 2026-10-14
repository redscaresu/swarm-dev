---
kind: code
status: blocked
blocked_by: [method-config-table-test]
epic: fable-on-call
depends_on: [method-config-table-test]
touches: [bin/swarm.sh:CFG_ defaults, CONFIG_KEYS, load_config (escalate_after arm), bin/swarm.sh:story_role, bin/swarm.sh:build_story (role line), bin/swarm.sh:dispatch (_role arm), bin/swarm.sh:READ_ONLY_COMMANDS, tests/epic_test.sh (role block :408-433), tests/config_test.sh (escalate_after block), docs/method.md (config table; § Model and effort; § Scoping an epic)]
---

# story_role builds a story with attempts: >= escalate_after as escalate (Fable); escalate_after defaults to 2

New key escalate_after: CFG_escalate_after=2, CONFIG_KEYS, a load_config arm (non-negative whole number, sonnet_share's regex at :180-181; 0 is off), and a method config-table row. story_role (#79, :1551) becomes story_role <slug>: it reads kind (empty = code), risk and attempts: (absent = 0) with fm, and returns escalate when escalate_after > 0 and attempts >= escalate_after, before the code-risky and sonnet_share arms, for every kind an agent builds (HLD Goal 2: any story). sonnet_share's agents.tsv first-attempt check is untouched. build_story (:1577) calls story_role "${slug}"; its kind check stays. Test hook `_role <slug>` beside _base (:3332), added to READ_ONLY_COMMANDS (:3351). Nothing writes attempts: yet. Docs: the table row (and the sonnet_share row's retry wording); § Model and effort :156-163 says a story whose attempts: reaches escalate_after builds as escalate; § Scoping an epic :181-183 records the exception: escalate_after ships on (2) by the user's decision of 2026-10-13, since it changes nothing until a story has failed twice. This is the wiring PR the lead logs against.

**Done when:**
- tests/epic_test.sh role block, through `_role`: attempts 0 and 1 give code for a code story and code-risky for risk: high; attempts: 2 gives escalate with the default; with escalate_after = 0, attempts 0, 1, 2 and 5 never give escalate; with escalate_after = 3, attempts 2 is code and 3 is escalate; a docs story with attempts: 2 gives escalate.
- `swarm.sh story` of a ready code story with attempts: 2 writes an agents.tsv line `escalate ... fable xhigh`.
- sonnet_share's existing checks pass unchanged, and a slug sampled for code-sonnet with attempts: 2 gives escalate.
- tests/config_test.sh: `swarm.sh config escalate_after` prints 2 with no config; -1, 1.5 and two are refused naming file and line; method-config-table-test's check passes with the new row.
- humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- story_role validates `attempts:` before any arithmetic: a value that is not `^(0|[1-9][0-9]*)$` is refused naming the story file (never evaluated). Done when adds: `_role` on `attempts: two` and on `attempts: a[$(touch X)]` refuses, and X is not created.
- Escalate is checked only for kinds an agent builds (agent_kind, bin/swarm.sh:1543): `_role` on a `kind: lead` story with `attempts: 3` never prints escalate (test).
- Escalation applies to every kind an agent builds: the role tests cover code, code-risky, code-sonnet, docs, chore and verify at attempts 0, 1 and 2.
- `_role` is in READ_ONLY_COMMANDS: add tests/events_test.sh to touches and assert it logs nothing.
- README § Cost and safety says `escalate_after = 2` ships on and `0` turns it off; README.md in touches, humanizer over it.
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).
