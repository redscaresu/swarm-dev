---
kind: code
status: blocked
epic: leaner-faster-swarm
depends_on: [backlog-conductor]
touches: [bin/swarm.sh:merge_pr (the item check), conduct_merge_rule, waiting_on_user, usage header: merge line, commands/plan-epic.md:decompose brief, tests/merge_test.sh]
risk: high
---

# Under merge = agent, a story marked `costs: money` waits for the user's merge

The user lets the lead and conductors merge infrafactory PRs, except ones that cost money
(2026-10-16), and approved `merge = agent` for infrafactory once such PRs are held for them. Today
`merge = agent` merges every reviewed PR, so it cannot be turned on there.

A story's front matter may say `costs: money`: merging its PR can spend money (it adds or changes a
CI job or schedule that runs against real cloud, raises a spend cap, or turns on something billed).
merge_pr (bin/swarm.sh:3413), where it finds the item in review that lists the URL, refuses with
`held: <slug> costs money; the user merges it` and changes nothing when that item says
`costs: money`, whoever calls it. conduct_merge_rule (:1961) tells the conductor: a `costs: money`
story is put in review with `swarm.sh review` and left for the user, never `swarm.sh merge`, and its
report lists it under Waits on the user. waiting_on_user lists it as `awaiting your merge (costs
money): <slug> <url>`, also under merge = agent. plan-epic's decompose brief (commands/plan-epic.md)
sets `costs: money` on any story whose merge can spend money as defined above, and the skeptic
brief checks it. Under merge = human nothing changes except the waiting line's wording. Waits on
backlog-conductor, which rewrites conduct_merge_rule.

bash 3.2. shellcheck bin/swarm.sh scripts/pre-commit tests/*.sh, every tests/*_test.sh and
`claude plugin validate .` must pass. Leave README.md, docs/method.md and AGENTS.md to
readme-and-agents and method-guide-and-reference; decline as out of scope any review finding about
them.

**Done when:** tests/merge_test.sh (gh stub), each case shown failing with its check removed (FAIL
lines in the PR body):
- with merge = agent, `swarm.sh merge --head <sha> <url>` for a story in review marked
  `costs: money` exits non-zero, prints `held:` and the slug, and the gh stub records no merge call;
- the same story without the key merges as today;
- `swarm.sh status` lists the held story as `awaiting your merge (costs money)` under merge = agent;
- the conductor brief (merge = agent, epic and backlog mode) contains `costs: money` and says to leave
  such a PR for the user;
- commands/plan-epic.md's decompose and skeptic briefs name `costs: money` (a grep check).
