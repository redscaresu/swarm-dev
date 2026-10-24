---
description: Use when asked to plan an epic or split it into stories. Scopes an epic (docs/epics/<slug>.md) into adversarially-checked stories with a herdr swarm — every agent in its own pane
argument-hint: "<epic-slug>  e.g. firewall-end-to-end"
---

The board is the directory `swarm.sh config board_dir` prints (`docs/` unless the project's
`.claude/swarm/config` says otherwise); every `docs/epics/` and `docs/stories/` below
is inside it.

Scope the epic `$1` into stories. Run it as a swarm so the user can watch every agent; do not
decompose it yourself in one pass, except for a small epic (step 0). Requires herdr (`HERDR_ENV=1`); if not inside herdr, say so and
stop. If `$1` is empty, list `docs/epics/*.md` (not the README) and ask which. If the epic does not
exist, help the user write it from `docs/epics/README.md` first.

Every agent writes its answer as JSON to `.swarm/$1/<name>.json` — the only file it may write —
and replies with that path. Put each prompt below in `.swarm/briefs/<name>.md`, then:

    swarm.sh agent scope-$1 <name> "$PWD" <role> .swarm/briefs/<name>.md
    swarm.sh wait <name>        # run in the background, one per agent

**An expired login.** If a `wait` prints `auth`, that agent stopped on "Login expired · Please run
/login". No agent can fix that, and only the user's `/login` clears it. Stop, and tell the user to
run `/login` and nothing else. Once they say it is done, write a file that says "Your login is
renewed: resume where you stopped.", run `swarm.sh tell <name> resume <file>` for each agent whose
`wait` printed `auth`, and wait on each again in the background.

**Resuming.** An interrupted run picks up where it stopped: before starting an agent, check for
its output file. If it exists, parses as JSON and is newer than `docs/epics/$1.md`, reuse it and do not
start that agent again; an older one belongs to a previous plan, so start the agent.

Every brief begins with the ground rules: *You are scoping docs/epics/$1.md; read it first.
Read-only — write nothing except your output file, never commit, never touch real cloud or
credentials. Cite evidence as file:line. Keep free text short.*

**0. Size** — judge the epic from its **Done when**. An epic of at most 3 stories with no `risk: high` is
planned by the lead alone: you write the stories in a board-PR worktree (`swarm.sh board-pr start scope-$1`),
not the main checkout, commit them there, since codex sees only committed changes, run one `swarm.sh codex-review`
pass over them in that worktree, and report as below. A story whose merge can spend money (it adds or changes a CI job or schedule that runs against real cloud, raises a spend cap, or turns on something billed) gets `costs: money`, as in step 2. A board outside the project's repo is edited where it is
(`board-pr` refuses it): write the stories there and skip the worktree and the commit. Skip steps 1 to 3, and start no agent.
A large epic, one you judge at more than 8 stories (too big for one full run) whose **Done when** holds goals that can ship apart, becomes child epics instead of stories, planned by the lead alone in the same board-PR worktree (or, for a board outside the project's repo, where it is, with no worktree and no commit, as the small path does): write one `docs/epics/<child>.md` per goal, with front matter `status: active` (`status: later` when $1 is `later`, so its children wait for the user as it did), `parent: $1`, and `depends_on` (the parent's dependencies plus any sibling it builds on, never the parent itself), and a body with its own **Done when**, out of scope, constraints and your part, each child small or medium. Set the parent's `status: split`: nothing plans a split epic, and it counts as done once none of its children is left on the board. `swarm.sh next` offers `plan-epic <child>` for each child in turn.
**The split critic.** No child's verifiers see the whole split, so before the board PR start one `split-critic` agent, role `critic` (read-only), on the parent and the drafted children (its brief names their paths). It answers three things: every parent **Done when** item maps to exactly one child (it names the missing and the duplicated items); the children build in their `depends_on` order; no child is too big for one full plan. Output `.swarm/$1/split-critic.json` `{findings:[{kind, why, fix}]}`; `swarm.sh board-pr open scope-$1` refuses a split with no such file, or one older than the board PR's worktree, and records the PR in `.swarm/$1/split-pr`, so `flow` counts a split whose critic found nothing too. On a resume, reuse its answer only when it is newer than the board PR's worktree (not, as **Resuming** says for the other agents, than `docs/epics/$1.md`); an older one is an earlier draft's, so start the critic again. Fix or decline each finding. Then commit (in the worktree), run one `swarm.sh codex-review` pass, report the children with their **Done when** and `depends_on` and the critic's findings with what you did about each, and open the board PR as the small path does. Skip steps 1 to 3, and start no agent but the split critic.
Once the board PR is open, log each split-critic finding against it: `swarm.sh log-finding --reviewer split-critic <kind> <board PR URL> '…'` when you fixed it, and `swarm.sh log-finding --declined <reason> --reviewer split-critic <kind> <board PR URL> '…'` when you did not.
**What the split critic missed.** When a child's own plan, a later board PR or a build finds a gap that belonged to the split (a parent **Done when** item no child covers, a missing child epic, a dependency order fix), log it against the split's board PR: `swarm.sh log-finding --reviewer escaped split-gap <split's board PR URL> '…'`. `swarm.sh flow`'s reviewers section sets the critic's fixes beside these escaped split-gaps, per split, and its cost section gives the split critic's tokens a row of its own. On a board outside the project's repo there is no board PR: the critic still runs and you fix or decline each finding, but log-finding needs a PR, so neither its findings nor later split-gaps are logged, and `flow` does not count that split.
A medium epic, any other, gets the full run.

**1. Survey** — role `survey`, in parallel: one agent (lands, constraints and overlaps together) unless the epic's text names another repo, three then (one, when a survey already exists; see below). The single agent is named `survey`, so its output is `.swarm/$1/survey.json`. Output `{summary, facts:[{fact, evidence}]}`.
- `survey-lands`: where the change lands — packages, functions, tests, fixtures, golden files,
  and which existing tests must change.
- `survey-constraints`: the project's ADRs, policies, safety rules and
  `AGENTS.md` rules, and hygiene and audit tests it would trip.
- `survey-overlaps`: `docs/stories/`, `docs/epics/`, open PRs, the last 20 merges; which existing
  stories this epic absorbs, blocks or depends on.

When a survey already exists (the user's, yours, or one from an earlier plan for a similar repo),
start one `survey` agent that checks it against the code and covers only what it misses, and give
the lead that survey and any earlier plan too. One survey is enough for a
one-repo epic; the review in step 3 is where the plan's bugs turn up.

**2. Decompose** — one agent, `lead`, role `lead`, given the survey files. Output
`{stories:[{slug, title, kind, risk, costs, repo, scope, done_when, needs, touches, depends_on, estimate_lines, easy}], waves, contradictions}`.
`needs` is what the story uses from each `depends_on` story (the file or the function), empty when it has none.
`repo` is the repo the story changes, by its directory name in `swarm.sh config repos_dir`; leave it
empty for the project's own repo. It is required when the project is not a git repo.
`estimate_lines` is the lead's guess at the PR's size; `easy` is true when it is under about 100 lines, adds no new command and no shared helper in `bin/swarm.sh`. A story is capped at one new command or one changed behaviour and about 300 lines; split a bigger one.
One agent story is one PR (a `lead` story may end with no PR, for example an approval); `done_when` must be able to fail; `kind` is code | docs | chore |
lead (real cloud, credentials, or a step by the user, marked **You:**), by swarm-dev
`docs/method.md` § Who does what; every step in the epic's **Your part** is in a `lead` story,
and a merge is never a story of its own; `risk: high` only for real-cloud, teardown,
credentials and safety paths; `costs: money` on any story whose merge can spend money (it adds or
changes a CI job or schedule that runs against real cloud, raises a spend cap, or turns on something
billed): with `merge = agent`, `swarm.sh merge` holds its PR for the user; no shared hot file (`AGENTS.md`, `STATUS.md`, and the config, schema and
check files `AGENTS.md` names as shared) in more than one story; a `depends_on` chain is at most 3 stories deep, and a story's scope opens with what it needs from each `depends_on`: the file or the function;
reuse existing
stories by slug; record every disagreement with the epic under `contradictions`. If a survey
failed, it says what it could not check. A check that several stories repeat (a freeze, a pinned
SHA, an empty deploy queue) is written once, in the epic, under **Checks before every stage**,
and each story points at it: copied into five stories, one wrong assumption needs five fixes.
Code that adds a flag or setting ships with it off, so merging the code changes no behaviour; turning
it on is a separate `lead` story with its own PR. A PR that both adds code and switches it on cannot
tell you which of the two broke something, and cannot be rolled back one half at a time.

**3. Verify** — in parallel, a chain at most 3 deep (this session, the one running plan-epic, checks chain depth over the whole graph):
- one `skeptic-<slug>` per `risk: high` story, role `skeptic`, capped at five (say which were not checked), given the `depends_on` graph. An epic with no `risk: high` story gets no skeptic.
  It tries to refute the story: a `depends_on` chain through it more than 3 stories deep, wrong about the code, too big for one PR (over the cap of one new command or one changed behaviour and about 300 lines in step 2, by its `estimate_lines`), an unstated dependency, a `done_when` that passes while the work is broken.
  Output `{sound, problems:[{why}], fix}`; unsure means `sound: false`.
- one `codex`, role `codex` (read-only, a different model family): missing stories, stories too
  big for one PR, `done_when` criteria that could pass on broken work, and overlaps within a wave.
  Its brief says the review needs no GitHub login: a repo's `AGENTS.md` may ask for
  `gh auth status` first, which fails inside codex's sandbox, and codex then stops without reviewing.
- one `critic`, role `critic`, given the `depends_on` graph and the waves: what the plan missed — a change the epic's
**Done when** needs that no story makes, an unrespected constraint, a test or doc nobody updates, a
  real-cloud step hidden inside an agent story. For every story, skeptic or not, it also checks: a story that should carry `risk: high` (real cloud, teardown, credentials, a safety path) and does not, a `touches` clash inside a wave, a `depends_on` story that shares no file in `touches` with it while its `needs` is empty (disjoint touches: drop the dependency, or fill in `needs`), a wrong `kind` (an agent story that needs real cloud, credentials or a person), and a missing or wrong `costs: money` (a story whose merge can spend money). A story's **Done when** names only what the builder's session can show, never something only the conductor or a merge can. Under 250 words for the whole-plan part, plus one short line for each story that has a problem.

**Then report**, in this order: refuted stories and why; contradictions; codex and critic findings
the plan does not answer; the surviving stories with `kind`, `estimate_lines`, `touches` and waves; which stories carry `risk: high` and why; stories ÷ longest chain (this session checks chain depth over the whole graph, since skeptics run only on `risk: high` stories); then **What you will do**: every `lead`
story, what each needs from the user (its **You:** steps), and, with `merge = human`, that the user
merges the resulting PRs. Ask before
writing anything. Before each approval point (this one, and the small path's and the split's question
before `board-pr open`), run `swarm.sh grants $1`: when it lists `stories`, the epic's HLD lets you
write the stories and open the board PR without asking, and the report says the HLD's `stories` grant
did that. Without it, ask. (The small path has already written and committed the stories and run codex: it asks before
`swarm.sh board-pr open scope-$1 "<title>" <body-file>`, and runs `swarm.sh board-pr done scope-$1` once the PR
has merged, and has no agent to close.) On approval write one `docs/stories/<slug>.md` per story (front matter `kind`, `repo`
when set, `status: ready`, or `blocked` with `depends_on` and no other blocker line, `epic: $1`, `depends_on`, `needs` when a dependency shares no file in `touches`, `touches`, `estimate_lines`, `easy`, `risk` when
high, `costs: money` when set; body: scope and **Done when**, with review fixes folded into each story's scope and Done when, never in a block of their own; a `lead` story also says what it needs from the user, one **You:** line per step that is theirs), open a PR with one `swarm.sh codex-review` pass, and `swarm.sh close
scope-$1`. Once the board PR is open, log every skeptic, codex and critic finding against it:
`swarm.sh log-finding --reviewer skeptic|codex|critic <kind> <board PR URL> '…'` when the plan adopted the finding, and
`swarm.sh log-finding --declined <reason> --reviewer skeptic|codex|critic <kind> <board PR URL> '…'` when it did not.
The kind is a short kebab-case name for the class of mistake, and `<reason>` is `out-of-scope`, `nit` or `wrong`. Waves are then built with `swarm.sh story <slug>`.
