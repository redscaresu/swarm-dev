---
kind: code
status: blocked
epic: epic-guard
depends_on: [lead-epics-key, epic-agreed-line]
needs: CFG_lead_epics from lead-epics-key (bin/swarm.sh); the agreed: line that /epic step 5 writes, from epic-agreed-line; hld_grants (bin/lib/board.sh:575) from grants-reader, merged in #425
touches: [bin/lib/board.sh:new epic_unticketed, bin/lib/lifecycle.sh:board_pr open, tests/board_pr_test.sh, docs/method.md:lead_epics row, docs/reference.md:board-pr entry, README.md:board-pr]
estimate_lines: 150
easy: false
---

# board-pr open refuses an epic that goes active with no ticket

Needs:
- CFG_lead_epics, from lead-epics-key (bin/swarm.sh);
- the `agreed:` line /epic step 5 writes, from epic-agreed-line, so an activation through /epic passes;
- hld_grants (bin/lib/board.sh:575), from grants-reader (#425). Reuse it; do not write a second grants parser.

**The reader.** Add one shared reader to bin/lib/board.sh: `epic_unticketed <reader> <paths>`. epic-guard-merge reuses it.
- It prints each `<board>/epics/<slug>.md` among <paths> (README.md excepted) that:
  - is `status: active` at the head;
  - was absent or `draft` at the base;
  - has no ticket.
- It checks every such epic in the PR, never stopping at the first ticketed one, and prints each unticketed slug.
- `<reader> base|head <path>` prints a file's bytes. It returns 1 when the file is absent and 2 on a read error.
- A 2 at the base or at the head fails the whole check, so the PR is refused. An unreadable head epic is never treated as deleted.
- Read `status`, `agreed:`, `parent:` and `hld:` with get_fm on those bytes (`-`), never fm, since fm reads the board-state override (board.sh:3-5).

**The tickets:**
- an `agreed: YYYY-MM-DD` line;
- a non-empty `parent:` (slug_list);
- an `hld: <name>`, where name is a plain slug and `<board>/hld/<name>.md` is `status: agreed` with `epics` in its hld_grants, at BOTH the base and the head;
- `lead_epics = on`, which skips the check entirely.

The `hld:` ticket checks both ends for different reasons. The base check stops a PR from granting itself. The head check stops a PR from deleting its HLD, superseding it or removing the `epics` grant in the same diff.

hld_grants takes a file, so write the HLD's bytes at each end to a mktemp file, and remove it with a trap. Any non-zero from hld_grants, such as a bad grant value or a read error, refuses the PR. The message names `<board>/hld/<name>.md` and the end (base or head), never the temp path. Check the exit status outside any `$(...)` that captures the result, because a die inside one does not stop board_pr.

These pass:
- a file missing at the head (deleted);
- `later`→`active`;
- an unchanged status.

A renamed epic counts as added.

**Where it runs.** Call epic_unticketed in board_pr open after the outside-board loop (bin/lib/lifecycle.sh:73), before `gh pr list`, the commit and the push (:88-109), so a refused PR is never pushed. Read the base with `git -C <wt> show origin/<base>:<path>` (as :81) and the head from the worktree file.

**The refusal:** `board-pr: <slug> goes active with no ticket (agreed:, parent:, hld: of an agreed HLD granting epics, or lead_epics = on); commit it as status: draft first, then run /swarm-dev:epic <slug>`. Committing as a draft matters because /epic on a missing file writes a fresh skeleton (commands/epic.md:24-27), which would orphan the lead's text in the worktree.

**Fixture and rules.** Give tests/board_pr_test.sh:325's med.md, which has no ticket, an `agreed:` line. Keep to bash 3.2 and the loose-match lint (grep -F, or globs marked ok). Never name plan-hld.

**Docs.**
- Extend docs/method.md's `lead_epics` row with the `off` clause: the guard refuses the board PR.
- Add one line on the refusal to docs/reference.md's board-pr entry and to README's board-pr text.
- Run the humanizer over them.

**Done when:**
- tests/board_pr_test.sh refuses each of these with that message, with no `pr create` in gh.log and no board/<name> branch on origin:
  - a new `status: active` epic with no ticket;
  - a draft→active flip with no ticket;
  - `hld:` naming an HLD that is draft (or missing) on origin/main but `status: agreed` with `grants: [epics]` in the worktree;
  - `hld:` naming an HLD that is agreed with `epics` at the base but, in the worktree, deleted, `superseded`, or without `epics`;
  - `hld:` naming a draft HLD, or one whose grants lack `epics`;
  - an HLD with a bad grant value: refused, naming `<board>/hld/<name>.md`, not a temp path;
  - an unreadable epic file in the worktree (a head read error);
  - a PR adding two active epics, one ticketed and one not, in both file orders. The refusal names the unticketed slug.
- Each of these opens:
  - `agreed:`;
  - `parent:` (the existing old-b case at :320);
  - `hld:` naming an HLD that is `status: agreed` with `grants: [epics]` at both ends;
  - `lead_epics = on`;
  - later→active;
  - a body-only edit to an active epic;
  - a deleted epic;
  - after a refusal, the same epic committed as `status: draft`.
- `make test` passes.
