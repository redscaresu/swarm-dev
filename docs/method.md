# The method

Work is planned top-down, you approve each level before the next is made, and every agent at every
level runs in its own herdr pane so you can watch it. This is the short guide. The detail behind
each step is in [`reference.md`](reference.md).

## The planning chain

1. **Epic**: `/epic <title>` opens a pane on the most capable model, where you write
   `docs/epics/<slug>.md` with it as `status: draft`: the problem with evidence, goals that can be
   checked, non-goals and constraints. A reviewer attacks the draft, and it becomes `active` only
   when you agree it (reference.md § Writing an epic).
2. **Stories**: `/plan-epic <epic>` splits the agreed epic into one-PR stories. Skeptics and
   codex check for gaps and overlaps (reference.md § Scoping an epic).
3. **Build**: `swarm.sh conduct <epic>` hands the epic to a fresh conductor, which builds its
   `ready` stories in parallel panes and merges them, or hands them to you to merge (reference.md
   § Building, § Merging).

`/swarm-dev:swarm` runs the chain after the epic. `swarm.sh next` reads the board and names the next
step, `/swarm-dev:swarm` does it and loops, and it stops only at an approval, a draft epic, a
`lead` story, or a `later` epic. On an empty board it explains the flow instead. After the step,
`next` prints `idle:` lines for capacity nothing uses: a blocked story an agent builds whose
`depends_on` story (one an agent builds, not in review) shares no file in `touches` with it and has no `needs:` line naming what it uses
(the lead drops the dependency or adds the line). When the step leaves the builders idle and no
story is buildable, it also prints the project with up to five candidates for a one-off: the findings
declined as `out-of-scope` in the last 30 days that no story has filed yet (the lead records each one
it files as filed in the findings log). With nothing to offer it prints no project line. Those declined findings
are the swarm's own list of follow-ups. The board is the
only state, so a run can stop anywhere and the next `/swarm-dev:swarm` continues. Building comes
first (a conductor still working, then an already-started one-off with `resume <slug>`, then an active epic's ready stories with `conduct <epic>`, then new one-offs), then
planning (an active epic with no stories, then an agreed HLD with no epics). An epic is planned
only once every epic it `depends_on` is done or has only stories in `review` left, so its stories
are scoped against code that exists. That can happen while a conductor is still working: `next`
then names the planning first, and the lead keeps waiting on the conductor in the background.
When `next` says to wait on a conductor, it also lists each ready `lead` story that a blocked story
depends on (`also: lead <slug> blocks <slugs>`). The lead runs those while it waits, since no
conductor will build them.

A story the swarm must not build says so with `kind: lead`: the lead runs it, and any step that is
yours is marked **You:** in it. An open question for you is a `lead` story too, so the board's
**Waiting on you** view lists it. An epic is done when its last story's PR deletes the epic file
and marks it done in the HLD's `## Epics`.

The session that runs the chain supervises, reviews and merges. It does not do the agents' work.

## Who does what

Three parties do the work, and the plan decides which one does each step, not the build.

- **You** agree the HLD, approve the epics and the stories, merge PRs (with `merge = human`), say go
  before each `lead` story, and do its **You:** steps.
- **The lead** is your own Claude Code session, the one you run `/swarm-dev:swarm` in. It
  supervises, reviews, and runs `lead` stories while you watch.
- **Agents** plan, conduct and build everything else, each in its own pane; builders also get
  their own worktree.

The lead's messages to agents go through `swarm.sh tell`, never a bare `herdr agent prompt`. When
the board is in the project's repo, its board edits go through `swarm.sh board-pr`, each in its own
worktree, never the main checkout (reference.md § The lead).

A story is `kind: lead`, never an agent's, when it:

- changes real cloud, uses credentials, or changes permissions;
- is hard to undo (deletes data, turns something off, a production change): its **Done when** names
  your go-ahead;
- needs a person: a decision, a portal click, another team's approval, a network only you can reach.
  That step is a **You:** line in the story, and the lead does the rest around it.

A merge is never a story of its own. A `kind` that is none of code, docs, chore or lead is never
built: `swarm.sh` stops and names it.

**Planned up front.** `/plan-hld` writes each epic's **Your part**: the human steps it expects.
`/plan-epic` turns them into `lead` stories, and its report ends with **What you will do**, so you
see your share of the work before you approve it. A step found during the build that needs you is a
new `lead` story, not done quietly.

**Every stop names its exit.** A `lead` story says what it needs from you in its body, and each
**You:** step says how the lead learns it is done. A status or flag raised for you says who clears
it and how.

## The board

The board is files: `docs/epics/` and `docs/stories/`, one file per item, with front
matter the scripts read. There is no shared board file to conflict on; the PR that finishes a
story deletes its file, and the PR is the record. A project can move the board (§ Configuring a
project). `templates/docs/` holds the READMEs that define each format and an Obsidian Base
(`Board.base`) that shows the board as a view.

## Configuring a project

`swarm.sh init`, run from the project's git root, copies the board templates into `board_dir`
without overwriting a file, creates `.claude/swarm/`, and adds `.swarm/` and the board's Obsidian
lines to `.gitignore`. The next `/swarm-dev:swarm` asks once for the brief
(`.claude/swarm/brief.md`) and writes only what you say; an empty file means you declined.

`.claude/swarm/config` holds `key = value` lines and `#` comments. The script parses it and never
runs it; an unknown key or a bad value stops `swarm.sh` with the file and line. `swarm.sh config`
prints every setting and where it came from. Each key's full rules are in reference.md
§ Settings, or the section named in its row.

| Key | Default | What it does |
|---|---|---|
| `board_dir` | `docs` | where the board is, relative to the project unless absolute |
| `repos_dir` | the project's parent | where a story's `repo: <name>` is found |
| `merge` | `human` | `human`: no agent merges, and a green, reviewed PR waits for you. `agent`: the conductor merges, except a story with `costs: money`, which `swarm.sh merge` holds for you (reference.md § Merging) |
| `lessons_file` | `.claude/swarm/brief.md` | where adopted lesson rules live; the brief, `AGENTS.md`, `CLAUDE.md` or `.claude/CLAUDE.md`. Every brief carries the file's tagged rule lines; a brief over 4 KB with them is flagged, not cut (reference.md § The outer loop) |
| `stall_minutes` | `30` | a working builder with no sign of life this long is `stalled?`, and `dash` and `wait --stall` flag it (reference.md § Building) |
| `sonnet_share` | `0` | `N`: one in N `kind: code` stories marked `easy: true` and without `risk: high` is built on Sonnet, to compare it with Opus. `0` is off (reference.md § Model and effort) |
| `escalate_after` | `2` | `N`: a story whose `attempts:` has reached N is built on Fable. `0` is off (reference.md § Model and effort) |
| `escalate_ladder` | empty | models from low to high, such as `sonnet,opus,fable`: swarm.sh steps a struggling build up to the next one in the same worktree. Empty is off (reference.md § The escalation ladder) |
| `builder_subagent_model` | empty | a model such as `haiku` that builders' subagents run on. Empty leaves Claude Code's choice (reference.md § Settings) |
| `goal` | `off` | `N`: each builder gets a `/goal` condition and N more turns to meet it. Needs Claude Code 2.1.269 or later (reference.md § Building) |
| `codex_minutes` | `10` | `swarm.sh codex-review` stops codex after this many minutes (reference.md § Building) |
| `fallback_reviewer` | empty | a model such as `sonnet` that reviews in codex's place when codex hits its usage limit. Empty skips the review (reference.md § Building) |
| `lead` | `off` | `session`: a lead session acts for you, so `dash` splits needs you in two: your steps, and the lead's queue (reference.md § Settings) |
| `merge_admin` | `off` | `on`: `swarm.sh merge` passes `--admin` to `gh pr merge`, for a repo whose ruleset requires an approving review, but only once its own checks pass and the base has no other rule `--admin` would skip (reference.md § Settings) |

The project is `$SWARM_PROJECT` if set, else the nearest directory up from where you are with
`.claude/swarm/config`, else the git repo you are in. A worktree resolves to its main checkout. The
project need not be a git repo: a board kept in a notes vault works, as long as every story names
its `repo:`. When the board is not in the story's repo, the builder leaves the story file alone and
the lead runs `swarm.sh finish <slug>` once the PR merges.

## Where the rest is

[`reference.md`](reference.md) holds the lead's board PRs and wake, writing the HLD, model and effort,
settings, scoping an epic, building, logs and outcomes, flow and features, the outer loop, merging
and releases.
