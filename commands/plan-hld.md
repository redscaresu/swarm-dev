---
description: Use when asked to plan an agreed HLD into epics. Decomposes an agreed HLD (docs/hld/) into epics with a herdr swarm — every agent in its own pane
argument-hint: "<hld-file-name-without-.md>  e.g. 2026-09-27-firewalled-by-default"
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/hld/` and `docs/epics/` below is inside it.

Decompose the HLD `docs/hld/$1.md` into epics. Requires herdr (`HERDR_ENV=1`); if not inside herdr,
say so and stop. If `$1` is empty, list the agreed HLDs (`grep -l '^status: agreed$' docs/hld/*.md`,
never the README) and ask which.

The whole plan runs on origin's copy of the board in the plan worktree, `<wt>` below
(`<repo>-wt/_board-plan-$1`), never the main checkout, which can be behind after a plan PR merged
(`board-pr done` pulls nothing). `<project>` is the main checkout you run in, as an absolute path.

- **An open PR.** If the board PR `plan-$1` is already open (`gh pr list --head board/plan-$1
  --state open --json url --jq '.[].url'` prints a URL), report its URL and stop: until it merges,
  main has no `planned:` for the HLD, and planning it again would only open a second PR.
- **A leftover worktree.** If `<wt>` exists, run `swarm.sh board-pr done plan-$1` first. It removes
  `<wt>` when the PR on its tip has merged or closed, or when the run that started it wrote nothing.
  It refuses while `<wt>` holds this plan's unopened work: an earlier run stopped there, so resume
  in `<wt>` and skip the checks below, which that run passed.
- **A new worktree.** Without `<wt>`, run `git fetch origin`, then `swarm.sh board-pr start plan-$1`,
  which makes `<wt>` from origin's base.
- **Checks.** Stop, saying why, and remove the `<wt>` you just started with
  `swarm.sh board-pr done plan-$1`, when `<wt>`'s HLD is not `status: agreed`, when its `planned:`
  has a value (it was planned already; an empty one, `""` or a bare `# comment` is none, as
  `swarm.sh next` reads it), or when an epic in `<wt>` already names it: `swarm.sh next` never plans
  an HLD that epics carry, and a second plan would write its epics again. An epic names it when
  `SWARM_PROJECT=<wt> swarm.sh grants <epic>` prints `<wt>`'s `hld/$1.md` as its first line, for any
  `<epic>` in `<wt>`'s `docs/epics/` (swarm.sh reads `hld:` with quotes, brackets and a comment).

A board outside the project's repo has no worktree and no origin: skip the PR and worktree steps,
read and write the board where it is, and read `<wt>` below as the project.

Run it as a swarm (`${CLAUDE_PLUGIN_ROOT}/docs/method.md` § The planning chain); every agent writes
its answer as JSON to `<project>/.swarm/$1/<name>.json`, the only file it may write, and replies with
that path. Put each brief in `.swarm/briefs/<name>.md`, then start each agent in `<wt>`:

    swarm.sh agent plan-$1 <name> "<wt>" <role> .swarm/briefs/<name>.md
    swarm.sh wait <name>        # run in the background, one per agent

Name agents as below (`survey-code`, `hld-lead`, `skeptic-<epic slug>`, `codex`, `critic`), never
after the HLD: an agent's name is cut at 32 characters, and a dated HLD name fills most of that.

**An expired login.** If a `wait` prints `auth`, that agent stopped on "Login expired · Please run
/login". No agent can fix that, and only the user's `/login` clears it. Stop, and tell the user to
run `/login` and nothing else. Once they say it is done, write a file that says "Your login is
renewed: resume where you stopped.", run `swarm.sh tell <name> resume <file>` for each agent whose
`wait` printed `auth`, and wait on each again in the background.

**Resuming.** An interrupted run picks up where it stopped: before starting an agent, check for
its output file. If it exists, parses as JSON and is newer than `<wt>/.git` (when the plan worktree
was started; on a board outside the repo, `docs/hld/$1.md`), reuse it and do not start that agent
again; an older one belongs to a previous plan, so start the agent.

Every brief begins: *You are decomposing the agreed HLD `<wt>/docs/hld/$1.md`; read it first. `<wt>`
is origin's copy of the project: read the code, epics and stories there. Read-only — write nothing
but your output file, never commit, never touch real cloud or credentials. Cite evidence as
file:line. Keep free text short.* (with `<wt>` and the output path written out in full)

1. **Survey** — role `survey`, three in parallel, output `{summary, facts:[{fact, evidence}]}`:
   `survey-code` (what the design changes and where), `survey-constraints` (ADRs, policies, safety
   rules, hygiene and audit tests), `survey-overlaps` (existing epics, stories, open PRs).
2. **Decompose** — one `hld-lead`, role `hld-lead`, given the surveys. Output
   `{epics:[{slug, goal, done_when, out_of_scope, constraints, your_part, depends_on, areas}], order, contradictions}`.
   Each epic is independently shippable and has a **Done when** that could fail; `areas` names the
   packages or directories it changes, so epics that can be scoped and built in parallel are
   visible; `your_part` lists the steps the user or the lead must do (swarm-dev `docs/method.md` § Who does
   what), or says none; every goal in the HLD belongs to exactly one epic; every disagreement between the HLD
   and the code is a contradiction.
3. **Verify** — one `skeptic-<slug>` per epic, role `skeptic` (capped at five; name any unchecked),
   output `{sound, problems:[{why}], fix}`: a gap no epic covers, two epics overlapping, an epic too
   big to scope, a **Done when** that passes on broken work. Plus one `codex`, role `codex`, on the
   same questions across the whole set; its brief says the review needs no GitHub login, since a
   `gh auth status` preflight fails inside codex's sandbox and stops it.
4. **Critic** — one `critic`, role `critic`: an HLD goal, risk or rollout step that no epic owns, or
   a human step missing from an epic's `your_part`.

Report in this order: refuted epics, contradictions, codex and critic findings the plan does not
answer, then the surviving epics and their order, then **What you will do**: each epic's `your_part`.

Before the ask, run `SWARM_PROJECT=<wt> swarm.sh grants $1`, which reads `<wt>`'s HLD. When it lists
`epics`, the HLD lets you write the epics `status: active` and open the board PR without asking; do
so, and say in the report that the HLD's `epics` grant did. Without it, write each epic `status:
draft`, and ask before `board-pr open`: each draft is then agreed by the user through `/epic
<slug>`, and nothing plans it until then.

Write in `<wt>`, never the main checkout. Write one `docs/epics/<slug>.md` per epic. An epic file
there that already carries `hld: $1` is this plan's own, from the run you resume: overwrite it, and
delete one the plan no longer has. Any other file of that slug in `docs/epics/` or `docs/stories/`
would overwrite an unrelated epic or story: rename that epic first, and every `depends_on` that
names it, and say so in the report. Front matter `status:` as above, `hld: $1` (the file name, no
`.md`), `depends_on: [<epic slugs>]`, `[]` when none; body: goal, **Done when**, out of scope,
constraints, **Your part**. In the same worktree set the HLD's front matter to one `planned:
<today>` line and the lines under its `## Epics` to one link per epic, replacing what a run you
resume wrote rather than adding to it; change nothing else in the HLD, and nothing else on the
board, so `swarm.sh grants` can put the board PR under this HLD. Commit, run one `swarm.sh
codex-review` pass there, then `swarm.sh board-pr open plan-$1 "<title>" <body-file>`. If it says
the PR on the branch has merged or closed, run `swarm.sh board-pr done plan-$1` and start again from
the top. A board outside the project's repo is written in place: no commit, no board PR.

Once the board PR is open, log every skeptic, codex and critic finding against it, as `/plan-epic`
does: `swarm.sh log-finding --reviewer skeptic|codex|critic <kind> <board PR URL> '…'` when the plan
adopted the finding, and `swarm.sh log-finding --declined <reason> --reviewer skeptic|codex|critic
<kind> <board PR URL> '…'` when it did not. The kind is a short kebab-case name for the class of
mistake, and `<reason>` is `out-of-scope`, `nit` or `wrong`.

The board PR lands as any board PR does: `swarm.sh merge --board <url>`, or with `merge = human` the
user merges it, unless `swarm.sh grants <url>` lists `merge`. Once it has merged, or been closed
unmerged, run `swarm.sh board-pr done plan-$1` and `swarm.sh close plan-$1`: while its worktree
exists, `swarm.sh next` never offers `plan-hld $1`, so a closed PR's leftover worktree would hide the
HLD for good. After a merge, `swarm.sh next` offers `plan-epic <slug>` for each active epic in turn.
