---
kind: code
status: blocked
epic: epic-guard
depends_on: [epic-guard-board-pr, merge-grant-gate]
needs: epic_unticketed from epic-guard-board-pr (bin/lib/board.sh)
touches: [bin/lib/merge.sh:merge_pr --board branch, tests/merge_test.sh, docs/reference.md:Merging and board-pr entry, README.md:merging]
estimate_lines: 160
easy: false
risk: high
---

# swarm.sh merge --board refuses a PR that sets an epic active with no ticket, under either merge mode

Needs epic_unticketed from epic-guard-board-pr (bin/lib/board.sh), including its rules:
- every epic in the PR is checked;
- the `hld:` HLD must be agreed and grant `epics` at both base and head;
- the base and head HLD bytes go through a mktemp file into hld_grants;
- any read error fails closed.

Build against merge_pr and tests/merge_test.sh as merge-grant-gate and release-grant-gate leave them. The epic's `depends_on: [hld-grants]` already orders this story after release-grant-gate, so depends_on lists only merge-grant-gate. That keeps the chain at 3: epic-guard-merge → epic-guard-board-pr → lead-epics-key.

**Where it runs.** In merge_pr's --board branch, after the path loop, call epic_unticketed on `files` (from ci_gate files, which includes a rename's old path). Run it outside the `merge = agent` block, for both merge modes, and before merge-grant-gate's human refusal. Otherwise that refusal would mask the guard.

**The reader.** It runs `gh api -H 'Accept: application/vnd.github.raw' repos/<repo>/contents/<path>?ref=<ref>` (as release_check does), with the PR's head SHA for the head and its base branch for the base.
- A 404 means absent.
- Any other failure fails closed: merge_fail "--board: gh cannot read <path> at <ref>, so whether <url> sets an epic active with no ticket is unknown".

**The refusal:** merge_fail "--board: <url> sets <slug> active with no ticket (agreed:, parent:, hld: of an agreed HLD granting epics, or lead_epics = on); commit it as status: draft first, then run /swarm-dev:epic <slug>".

No new reader. Never name plan-hld.

**Docs.** Add one line each to docs/reference.md § Merging, to its board-pr entry, and to README's merging text: `merge --board` refuses the same PRs. Run the humanizer over them.

risk: high because this is a merge-path guard. Failing open loses the guard, and failing wrong blocks every board merge.

**Done when** (tests/merge_test.sh, with the stub gh's contents fixtures, wf.<file>.<ref>):
- **Fixtures.** The HLD and the epic fixtures have different file names, because the stub keys fixtures by basename. Every `hld:` case asserts gh.log has `contents/<board>/hld/<name>.md?ref=main`.
- **Refused.** Each of these is refused, the line names the epic and `/swarm-dev:epic <slug>`, and gh.log has no `pr merge`:
  - a new active epic with no ticket;
  - a draft→active flip with no ticket;
  - `hld:` whose HLD is draft at the base while the head's copy says agreed;
  - `hld:` whose HLD is agreed at the base but deleted, superseded or without `epics` at the head;
  - a bad grant value in the HLD;
  - a PR mixing a ticketed and an unticketed active epic, in both file orders, naming the unticketed slug;
  - a 502 on the epic read.
- **Merged.** Each of these merges:
  - `agreed:`;
  - `parent:`;
  - `hld:` naming an HLD agreed with `grants: [epics]` at both ends;
  - `lead_epics = on`;
  - later→active;
  - a PR that changes no epic's status.
- **Human mode.** Under `merge = human`, the refusal holds too. The test gives the HLD `grants: [merge]` but not `epics`, so merge-grant-gate lets the lead through and the guard's own text is asserted.
- Every --board case as merge-grant-gate and release-grant-gate leave tests/merge_test.sh passes unchanged.
- `make test` passes.
