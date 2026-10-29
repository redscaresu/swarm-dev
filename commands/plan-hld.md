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
- **Origin.** Run `git fetch origin` first: the checks below read origin's board, and `board-pr
  start` makes `<wt>` from it.
- **A leftover worktree.** If `<wt>` exists, run `swarm.sh board-pr done plan-$1` first. It removes
  `<wt>` when the PR on its tip has merged or closed, or when the run that started it wrote nothing.
  Two refusals mean this plan's unopened work is there, and an earlier run stopped: `<wt> has
  uncommitted changes`, and `no PR on board/plan-$1 has its tip ..., and it has commits past
  origin/<base>`. On either, resume in `<wt>`, and still run the checks below: origin can have moved
  since that run. On any other refusal (a gh error, a tip that differs from origin's, a locked
  worktree, the branch checked out elsewhere), stop and report it.
- **A new worktree.** Without `<wt>`, run `swarm.sh board-pr start plan-$1`, which makes `<wt>`
  from origin's base.
- **Checks.** Read origin's HLD, `git show origin/<base>:<board>/hld/$1.md`, where `<base>` is what
  `swarm.sh base` prints and `<board>` is the board's path in the repo; never `<wt>`'s copy, which
  on a resume carries the earlier run's `planned:`. Stop, saying why, when it is not `status:
  agreed`, when its `planned:` has a value (it was planned already; an empty one, `""` or a bare
  `# comment` is none, as `swarm.sh next` reads it), or when an epic on origin already names it:
  `swarm.sh next` never plans an HLD that epics carry (outside the repo, only to resume an
  interrupted run, below), and a second plan would write its epics again. An epic names it when its front matter's `hld:` is `$1` itself, read as `next` reads it
  (the lines between the file's first two `---`; quotes, one pair of brackets, a trailing comment
  and whitespace aside; a body line is not read, and `parent:` is not followed). This loop over
  origin's epics prints each that does:

      git ls-tree -r --name-only origin/<base> -- '<board>/epics/' | while read -r f; do
        git show "origin/<base>:$f" | awk '/^---$/ && ++n == 2 { exit } n == 1' |
          grep -qE "^hld: *\[?[\"']?<name>[\"']?\]?[[:space:]]*(#.*)?\$" && echo "$f"
      done

  where `<name>` is `$1` with each `.` written `\.`. On a resume, stop too when origin's HLD changed
  since `<wt>` was started, which `git -C <wt> diff --quiet "$(git -C <wt> merge-base HEAD
  origin/<base>)" origin/<base> -- <board>/hld/$1.md` reports by failing: that run's agents and its
  `grants` read the old HLD, and the answers in `.swarm/$1/` are its. On a stop, remove a `<wt>` you
  just started with `swarm.sh board-pr done plan-$1`; a resumed one holds the earlier run's work, so
  leave it and say so. On a board outside the repo, feed each `docs/epics/*.md` to the same `awk`
  and `grep`. There an epic naming the HLD is not a stop when the HLD has no `planned:` value,
  `.swarm/$1/writing-epics` lists every epic naming the HLD, and no story's `epic:` and no epic's
  `parent:` names one of them, and `.swarm/events.tsv` has no `conduct` or `finish` line for one of
  them. An interrupted run wrote those epics in place and no work has started on them: resume and
  overwrite them as below.

A board outside the project's repo has no worktree and no origin: skip the PR, origin and worktree
steps, run the checks on the board's own files, read and write the board where it is, and read
`<wt>` below as the project.

Run it as a swarm (`${CLAUDE_PLUGIN_ROOT}/docs/method.md` § The planning chain); every agent writes
its answer as JSON to `<project>/.swarm/$1/<name>.json`, with its `.json.partial` the only files it may write, and replies with
that path. Put each brief in `.swarm/briefs/<name>.md`, then start each agent in `<project>`, as
`/plan-epic` does, so its one write lands inside its working directory; started in `<wt>`, it would
write outside it, which can prompt or be refused, and `swarm.sh wait` then sits on a blocked agent:

    swarm.sh agent plan-$1 <name> "<project>" <role> .swarm/briefs/<name>.md
    swarm.sh wait <name>        # run in the background, one per agent

Name agents as below (`survey-code`, `hld-lead`, `skeptic-<epic slug>`, `codex`, `critic`), never
after the HLD: an agent's name is cut at 32 characters, and a dated HLD name fills most of that.

**An expired login.** If a `wait` prints `auth`, that agent stopped on "Login expired · Please run
/login". No agent can fix that, and only the user's `/login` clears it. Stop, and tell the user to
run `/login` and nothing else. Once they say it is done, write a file that says "Your login is
renewed: resume where you stopped.", run `swarm.sh tell <name> resume <file>` for each agent whose
`wait` printed `auth`, and wait on each again in the background.

**Resuming.** An interrupted run picks up where it stopped: before starting an agent, check for
its output file. A file in `.swarm/$1/` counts only when this attempt wrote it against the tree
`<wt>` holds, so clear the others first. The two checks below apply only to a board in the project's
repo; a board outside it has no board PR and no `base-rev`, so skip them there.

- **Another attempt.** Run `gh pr list --head board/plan-$1 --state all --json createdAt --jq
  '.[].createdAt'`. If it fails, stop and report it: an error prints no date, and reads as no PR.
  A PR created after `.swarm/$1/base-rev` was written belongs to the attempt that wrote it, which
  is over: delete `.swarm/$1/`. An older PR belongs to an attempt already cleared.
- **Another tree.** `.swarm/$1/base-rev` holds `git -C <wt> merge-base HEAD origin/<base>`, the
  commit `<wt>` was made from, which the briefs read. When the file is missing or holds another
  commit, delete `.swarm/$1/`'s outputs and `.partial` files and write the file again.

Then reuse an output that exists, parses as JSON and is newer than `.swarm/$1/base-rev` (the
reference; on a board outside the repo, `docs/hld/$1.md`, with no `base-rev`), and do not start that
agent again; an older one belongs to a previous plan, so start the agent. A `.partial` file is an unfinished run, not a result: start the agent, which carries on from it. Delete a `.partial` that is not newer than that same reference first: it belongs to a previous plan.

Every brief begins: *You are decomposing the agreed HLD `<wt>/docs/hld/$1.md`; read it first. `<wt>`
is origin's copy of the project: read the code, epics and stories there, not in `<project>`, where
you run and which can be behind. Read-only — write nothing but your output file and its `.partial`, never commit, never
touch real cloud or credentials. If `<output>.partial` exists, a run was cut off: start from it and carry on, do not redo it. Write your findings early to `<output>.partial` and update it as you go, so a timed-out turn loses one item, not all, then rename it to the output file as your last step: only the output file means you finished. Cite evidence as file:line. Keep free text short.* (with `<wt>`,
`<project>` and the output path written out in full)

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
<slug>`, and nothing plans it until then. Whatever the grant says, write `status: draft` for an epic
whose `stage:` the base does not allow yet: the newest `v<x.y.z>` tag on `origin/<base>` is below
the minor before its stage (`v0.30.0` for a `v0.31.0` epic), and no epic of that stage is `active`
there. `board-pr open` refuses it `active`, and `next`'s stage step sets it active once that tag
exists.

Write in `<wt>`, never the main checkout. Write one `docs/epics/<slug>.md` per epic. An epic file
there that already carries `hld: $1` is this plan's own, from the run you resume: overwrite it, and
delete one the plan no longer has. Any other file of that slug in `docs/epics/` or `docs/stories/`
would overwrite an unrelated epic or story, and a PR that changes an epic the board already has is
no plan: rename that epic first, and every `depends_on` that names it, and say so in the report.
Front matter `status:` as above, `hld: $1` (the file name, no `.md`), `depends_on: [<epic slugs>]`,
`[]` when none; body: goal, **Done when**, out of scope, constraints, **Your part**. In the same
worktree set the HLD's front matter to one `planned: YYYY-MM-DD` line, today's date and nothing
after it, and the lines under its last `## Epics` to one `- [<slug>](../epics/<slug>.md)` per epic,
the same slug in the text and the path and nothing else on the line, replacing what a run you
resume wrote rather than adding to it. Change no line of the HLD above `## Epics`, write nothing
after the links, and change nothing else on the board: the PR adds its epics, each carrying `hld:
$1`, and touches no other file. `swarm.sh grants` puts the board PR under this HLD in that exact
shape and under none in any other, where the `merge` grant no longer covers it. Commit, run one
`swarm.sh codex-review` pass there, then `swarm.sh board-pr open plan-$1 "<title>" <body-file>`. If it says
the PR on the branch has merged or closed, run `swarm.sh board-pr done plan-$1` and start again from
the top. A board outside the project's repo is written in place: no commit, no board PR. There,
before you write any epic, write `<project>/.swarm/$1/writing-epics`, one slug per line: every epic
this run writes and, on a resume, every slug the file already lists. Remove it once the HLD's
`planned:` line is written. While it is there and the HLD has no `planned:`, `swarm.sh next` offers
`plan-hld $1` again to finish the interrupted run. A run interrupted before this file existed has
none: the user writes it by hand, one slug per epic naming the HLD, after checking that none of
those epics has work on it.

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
