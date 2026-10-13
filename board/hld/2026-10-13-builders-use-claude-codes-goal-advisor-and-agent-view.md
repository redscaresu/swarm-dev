---
title: Builders use Claude Code's goal and agent view, with Fable on call
date: 2026-10-13
status: agreed
---

# Builders use Claude Code's goal and agent view, with Fable on call

The file keeps the slug `builders-use-claude-codes-goal-advisor-and-agent-view` from the title the
design started with; the advisor was declined while writing it (§ Alternatives).

## Problem

Three things seen running swarm-dev on infrafactory on 2026-10-11 and 2026-10-12 (its `.swarm/`
logs; `swarm.sh cost` over them):

1. **Builders stop mid-story and sit idle.** Nothing inside the session keeps a builder going until
   its story's **Done when** holds: the brief asks it to "reply with the PR URL ... then stay open"
   (`bin/swarm.sh:1034-1035`), and when it stops short the conductor must notice and nudge it with
   `swarm.sh tell`. The infrafactory log has 156 `tell` lines for 67 `story` starts
   (`.swarm/events.tsv`, to 2026-10-12); the log cannot tell a review finding from a nudge, so the
   nudge share is not known. One cause is already patched by hand: an API error ends the turn and
   `wait` re-prompts the agent up to three times (`API_ERROR_NUDGES`, `bin/swarm.sh:751-753`;
   the loop at `:849-870`).
2. **An agent's state is read from the screen.** Every `wait`, `watch`, `status`, `dash` and `tell`
   decision reads herdr's `agent_status` (`bin/swarm.sh:827-873, 1678, 1693, 2014, 2500-2508`),
   which herdr classifies from the pane's terminal UI: "`blocked` means Herdr recognized an approval
   or question UI ... `unknown` means ... Herdr cannot classify it confidently"; its `done` means
   ready for input and not yet seen (`~/.claude/skills/herdr/SKILL.md:55-59`). The only thing
   Claude Code tells herdr is its session id, at `SessionStart`
   (`~/.claude/hooks/herdr-agent-state.sh`). One workaround reads the screen because of it:
   `ended_on_api_error` greps the pane text for `⏺ API Error` (`bin/swarm.sh:758-762`). Seen once,
   on 2026-10-13: herdr listed the builder `fakeaws-load-vpc-subnet-igw-az` as `done` while Claude
   Code's own `claude agents --json` listed that session as `busy`; later the same day 15 of 15
   sessions agreed. A stale `done` is a timing gap in a guess; the session's own report has no gap.
   A different problem, which no state source fixes, is that idle is not finished: a conductor is
   idle between its own background waits, so `/swarm` waits for its report file
   (`wait_conductor`, `bin/swarm.sh:875-891`; `docs/method.md:179-181`). That stays.
3. **Cost.** `swarm.sh cost 2026-10-12` on infrafactory: an estimated $627 at list price over 145
   agents in one day, and $764 over 214 agents from 2026-10-11. Of the $627, `code-risky` (Opus at
   `xhigh`, 39 agents) is $337, 54%; `code` (Opus at `high`, 22 agents) is $109. Cache reads are 1.46B
   of the 1.49B tokens: the spend is each turn re-reading the context, so a model that takes more
   turns per story costs more than its price per token suggests. 53 of the 97 code builders started
   since 2026-09-29 ran as `code-risky` (`.swarm/agents.tsv`).

And one thing found while writing this: the method says "Fable is escalation only: a story that
failed twice" (`docs/method.md:152`) and `policy()` has the `escalate` role (`bin/swarm.sh:280`),
but nothing has ever called it. None of infrafactory's 266 agents ran as `escalate`.

Claude Code 2.1.x ships three features that bear on these: `/goal` (a judge that keeps a session going
until a condition shows in its output), `/advisor` (a stronger model consulted at decision points),
and the agent view (`claude agents --json`: each session's own state, reported by Claude Code, not
read off a screen). This HLD decides which of them swarm-dev adopts, where, and behind what switch.

## Goals

Each one can fail:

1. **For a Claude session, no `swarm.sh` code path reads a pane's text or herdr's `agent_status` to
   decide its state.** `wait`, the stall rule, `status`, `watch`, `dash` and `tell` take the
   session's own `status` and `waitingFor` from `claude agents --json`, joined by a session id
   `swarm.sh` minted at launch. `ended_on_api_error` is gone. herdr's status is read only for codex
   agents (which have no Claude session) and as the "taken up" gate in `deliver_prompt`. A test
   fixture where herdr says `done` and the session says `busy` reports the builder as working; one
   with no entry for a recorded session reports it `gone`, never idle.
2. **A story that has failed twice starts on Fable.** The
   attempt count is on the story file, written by one command; the third build runs as `escalate`;
   a failure on Fable makes the story a `lead` item with a **You:** step. A behavioural test proves
   a story with two recorded failures resolves to role `escalate`, and a structural one that every
   role in `ROLE_GROUPS` is passed as a role by `commands/*.md` or `bin/swarm.sh`.
   `dash --ladder` shows how many agents each role has ever started.
3. **With `goal` on, a builder is idle short of its reply only with a goal end or pause the
   conductor reported, by cause.** The events log records whether a `tell` carried review findings
   or a nudge; on one epic run with `goal` on, the nudge count is zero and every builder that
   stopped short is accounted for as met, impossible, stalled, bound, paused or cleared-on-error.
4. **Nothing changes with the defaults, apart from escalation and the agent-state source.**
   `goal` is off. `escalate_after` defaults to `2`: the user's call (§ Fable on call says why).
   The agent-state source has no setting (§ Rollout says why). A project that sets nothing builds
   as it does today until a story has failed twice.
5. **The method and the README match the code.** `docs/method.md` § Model and effort, § Building
   and § Configuring a project describe the attempt count, the goal and the agent-state source;
   `README.md` names the minimum Claude Code version under Requirements, the goal in the inner-loop
   row, and Fable after two failures under Cost and safety. The flow diagram is unchanged. A test
   checks that every key in the method's config table is in `load_config` and the reverse; the rest
   is checked by the HLD and PR reviews.

## Non-goals

- **The advisor.** Not adopted; § Alternatives says when to revisit.
- **The model ladder.** `code` stays Opus `high`, `code-risky` Opus `xhigh`; no Sonnet builders. A
  cost cut by effort is one line in `policy()` and a separate decision, made from `swarm.sh cost`.
- **A goal for conductors.** Builders first.
- **Why 53 of 97 code builders were `risk: high`.** If `/plan-epic` over-marks risk, no policy fixes
  it; that is a planning change for another HLD.
- **Background sessions (`claude --bg`).** Agents stay interactive sessions in herdr panes, where
  the user watches them. The agent list is read; nothing is started through it.
- **Cross-machine.** `claude agents` is local, and so is every pane.
- **herdr's role in panes, prompts and the dashboard.** Unchanged.

## Current state

- **Launch.** `start_agent` (`bin/swarm.sh:454-504`) opens a herdr pane and runs
  `herdr agent start --kind claude -- --model <m> --effort <e> --permission-mode auto` (plus a
  `--disallowedTools` guard on the merge command with `merge = human`); the brief is then submitted
  as the first prompt with `herdr agent prompt` and counted as taken up when herdr sees `working` or
  `blocked` (`deliver_prompt`, `bin/swarm.sh:737-749`). Every agent is an interactive session in a
  pane: no `-p`, no `--bg`, no `--name`, no `--session-id`.
- **Policy.** `policy()` (`bin/swarm.sh:265-283`) is the one place: `code` Opus `high`, `code-risky`
  Opus `xhigh` (a story with `risk: high`), `conduct` Opus `high`, `escalate` Fable `xhigh` (never
  reached: `build_story` picks the role from `kind` and `risk` alone, `bin/swarm.sh:1073`), design
  on Fable. Reasoning in `docs/method.md` § Model and effort.
- **Waiting and stalls.** `wait_agent` blocks on `herdr agent wait` and treats `idle`/`done` as
  settled unless the pane text shows an API error (`bin/swarm.sh:849-873`). `wait --stall` steps
  through `herdr agent wait` in `STALL_POLL_MS` (60 s) slices (`settle`, `bin/swarm.sh:827-847`) and
  calls a builder `stalled?` when herdr says `working` but nothing has moved for `stall_minutes`
  (default 30): no worktree commit, no PR update, no `swarm.sh` action on its story
  (`agent_stalled`, `bin/swarm.sh:803-820`; `STALL_PY`, `bin/swarm.sh:327-370`). A conductor is waited
  on until its report file exists (`wait_conductor`, `bin/swarm.sh:875-891`).
- **Other readers of herdr's status.** `deliver_prompt` (taken up), `tell_agent` (refuses a
  `working` or `blocked` agent, `bin/swarm.sh:893-903`), `free_agent_name` (`:2488-2498`),
  `watch_prs` (blocked agents, `:1678`), `status` and `dash` through `PANES_PY.agent_state`
  (`:305-325`, `blocked` → WAITING, `working`, retired, else herdr's word). All keep only agents in
  panes this project opened (`own_panes`, `:375-377`). Codex agents (`/plan-epic`, `/plan-hld`) are
  waited on the same way and have no Claude session.
- **Session ids.** `record_agent` (`bin/swarm.sh:522-528`) copies, once, right after the brief is
  delivered, the session id herdr learned from the user-level `SessionStart` hook
  (`~/.claude/settings.json`, `herdr-agent-state.sh`) into `.swarm/agents.tsv`; `cost` joins it to
  `~/.claude/projects/*/<session>.jsonl`. The copy is lossy: 9 of infrafactory's 266 agents have `-`
  there, the hook not having reported yet.
- **What Claude Code 2.1.296 (installed here) shows.** `claude agents --json` lists interactive
  sessions as well as background ones, including every agent herdr started: on 2026-10-13, 19 and
  later 15 sessions, each herdr agent's `agent_session.value` matching a `sessionId` (this HLD
  session, a running conductor and its builders among them). The docs promise the fields (`cwd`,
  `kind`, `startedAt`; `pid` and `status` while the process is alive; `waitingFor` when waiting;
  `sessionId` and `name` when set; `id` and `state` for background sessions only) but conflict on
  whether interactive sessions are listed ("don't appear until you background them" against "every
  live session"); only the installed binary's `--help` says "interactive and background". An
  interactive entry's `status` is `busy` | `idle` | `waiting`; `waitingFor` is `permission prompt`,
  `input needed`, `sandbox request`, `worker request` or `dialog open`. `--session-id <uuid>` sets
  the id at launch. A call takes about 0.14 s and starts no daemon.
- **Goal and advisor, as documented and as installed.** `/goal <condition>` (4,000 characters) is
  "a wrapper around a session-scoped prompt-based Stop hook": after each turn the small fast model
  (`ANTHROPIC_DEFAULT_HAIKU_MODEL`, on whichever provider the session uses) judges the condition
  from the conversation alone; not met, it tells Claude to carry on; met or impossible, the goal
  clears with a transcript entry. Setting a goal "starts a turn immediately, with the condition
  itself as the directive". No `--goal` flag, no settings key, no hook event on completion; `-p`
  is the scripted form; `--bg` is not mentioned. Unavailable with `disableAllHooks` or
  `allowManagedHooksOnly`, and "the command tells you why". `--advisor <fable|opus|sonnet|id>` is in
  the CLI reference; the advisor must rank at or above the main model, is experimental, Anthropic
  API only, billed per call, with no cap on calls. Both are in the installed binary (`advisorModel`,
  `--advisor`, `/goal`, `CLAUDE_CODE_GOAL_CHECKIN_MINUTES`, `waitingFor` all present).

## Design

### Agent state: the session's own report, not the screen

For every Claude session this project starts, `claude agents --json` is the one source of its
state for `wait`, the stall rule, `status`, `watch`, `dash` and `tell`. herdr keeps what it is good
at: opening, naming and closing panes, delivering prompts, and being where the user watches. The
dashboard and the panes do not change.

- **The join needs no hook.** `start_agent` mints a UUID, passes `--session-id <uuid>` at launch,
  and records it in `.swarm/agents.tsv` before the brief is sent. The `SessionStart` hook that tells
  herdr the id stays for herdr's own use; `swarm.sh` no longer depends on it, and the 3.4% of
  agents with no recorded id go away. Codex agents get no id and are read from herdr as today.
- **What is read.** `status` (`busy` | `idle` | `waiting`) and, when waiting, `waitingFor`, so
  `status` and `dash` show why an agent waits, which herdr's `blocked` never carried. "Finished" is
  unchanged: a session never reports `done`, so a builder is finished when it has replied with its
  PR or branch and a conductor when its report file exists. `wait_conductor`'s wait on that file
  stays: it reads a file, not a screen, and idle is a conductor's normal state between background
  waits.
- **How `wait` blocks.** herdr's `agent wait` stays the wake-up, in the 60 s slices `settle` already
  uses; on each wake, and at the end of each slice, `wait` reads the session's status from the
  list and returns only when the session itself reports `idle` or `waiting`. A goal-driven builder
  is `busy` for as long as its goal runs; `wait` keeps stepping, and `--stall` keeps checking the
  signs of life between slices. One list call per slice per waiter (a conductor's `wait` per
  builder, its `watch`, a `dash --watch` redraw): at 0.14 s each this is nothing.
- **Failing loudly.** A field missing from an entry shows as `unknown` and `!` in `dash`, never as
  idle. No entry at all for a recorded session whose pane is still open is `gone`, shown as `!`
  (the process exited: a crash, a `/exit`); a closed pane is retired, as today. An interactive
  session with no entry is also the sign that Claude Code stopped listing interactive sessions
  (§ Risks).
- **What goes, what stays.** `ended_on_api_error`'s grep of the pane text goes. The nudge after
  an API error stays, keyed off-screen: with `goal` off, a session that reports `idle` with no PR
  on `story/<slug>` (story mode) or no pushed branch (epic mode) is nudged, up to
  `API_ERROR_NUDGES` times as now; with `goal` on, `swarm.sh` does not nudge, because the goal
  retries transient errors three times itself and a paused goal is a reported cause (§ A goal for
  builders). `tell_agent`'s refusal of a busy or waiting agent reads the session. `PANES_PY`
  maps Claude Code's words instead of herdr's. `deliver_prompt`'s "taken up" gate keeps herdr's
  `--until working --until blocked`: it confirms the paste landed, which is herdr's job.
- **The stall rule stays.** `busy` means a turn is running, not that work is moving, so
  `stall_minutes` and its signs of life (commit, PR update, swarm action) are unchanged; only the
  "herdr shows working" test becomes "the session reports busy".
- **Requirements.** A Claude Code whose `claude agents --json` lists interactive sessions and
  takes `--session-id`; the minimum version is pinned by the first story of the epic (the docs do
  not say which release listed interactive sessions). `require_claude`, beside `require_trusted`
  in `start_agent` (`bin/swarm.sh:459`), refuses before a pane opens, naming the version, and
  runs one self-check: the calling session's own id must appear in the list. `swarm.sh version`
  only warns (`bin/swarm.sh:64-76`) and conductors never call it, so the check lives where agents
  start.

### Fable on call: wire the escalate role

The method already says it (`docs/method.md:152`) and `policy()` has the role; this adds the
missing rung. The model ladder stays as it is.

- **The board counts attempts.** A story's front matter carries `attempts: <n>`, the number of
  builds of it that failed. On the story file because the board is the only state
  (`docs/method.md` § The planning chain): a fresh conductor, `dash` and `next` all see it.
- **One writer.** `swarm.sh close <slug>` raises the count when the story file still says
  `status: ready`: the builder was closed and the story is neither in review nor finished.
  `reconcile` never does: a PR closed unmerged is the route the user takes to re-scope a story
  (`commands/swarm.md`, the gate), not a builder's failure. With `pr_per = epic` the conductor runs
  `finish` before `close`, so a merged story is never counted. No other command writes it; it is a
  board write by `swarm.sh`, like `review`, `finish` and `reconcile` (`set_status`,
  `bin/swarm.sh:1455`), never by an agent.
- **When a conductor gives up on a builder.** When `wait --stall` returns stalled; when the
  builder is idle with no PR or branch after the nudges, or with a goal that ended short of its
  reply (§ A goal for builders, by cause); or when the review loop has not converged after the
  rounds the conductor's own judgment allows today. It runs `swarm.sh close <slug>`, which counts
  the attempt, and the story stays `ready`, so the conductor's next wave picks it up: the retry
  happens inside the same conductor, as it does implicitly now (`next_step`,
  `bin/swarm.sh:1306-1340`).
- **The third build is Fable.** With two failures on the board, `build_story` runs the story as
  `escalate` (Fable `xhigh`): one Fable session, only after two Opus attempts, recorded by role in
  `.swarm/agents.tsv` so `swarm.sh cost` shows what escalation cost. The setting `escalate_after`
  defaults to `2`; `0` turns escalation off. It ships on, by the user's decision (2026-10-13), not
  off as the method's ship-off rule would have it (`docs/method.md:171`): the rule exists so a
  merge changes no behaviour, and this path changes nothing until a story has already failed
  twice, which no project reaches by merging. The cost it adds is bounded to that case.
- **After Fable, you.** A story that fails on Fable is not retried: `close` sets it `kind: lead`
  (a second board write) with a **You:** step, "decide: re-scope it, build it by hand, or drop it;
  `swarm.sh reset <slug>` clears the count", and the three attempts' PRs or reports linked, so it
  is listed under **Waiting on you** and names its exit (`docs/method.md` § Who does what).
- **A judge's "impossible" is not an attempt.** A goal the judge calls impossible means the
  story's **Done when** names something the session cannot show (§ A goal for builders). That is
  a planning defect: the story becomes a `lead` item ("fix its **Done when**") and its count is
  untouched, so a badly phrased story cannot escalate to Fable to meet the same condition.
- **No role can be unwired again.** A behavioural test: a story with `attempts: 2` and
  `escalate_after = 2` resolves to role `escalate` (through a test hook like `_base`,
  `bin/swarm.sh:2630`). A structural test: every role in `ROLE_GROUPS` appears as the role argument
  of a `swarm.sh agent` line in `commands/*.md` or a `start_agent` call in `bin/swarm.sh`; a comment
  or a method sentence does not count, which is why a grep for the name would have passed on
  db657b7 (2026-09-29), where the role and the sentence arrived together and the rule did not.
  `dash --ladder` shows, beside each role's model, how many agents of that role
  `.swarm/agents.tsv` has ever recorded, so a role at 0 is visible on the screen the user watches.

### A goal for builders

Each builder's session gets a `/goal` whose condition is the story's own acceptance: its
**Done when** (the brief already says "Its **Done when** is the acceptance",
`bin/swarm.sh:1007, 1023`), plus the reply the brief asks for (`bin/swarm.sh:1034-1035`: in story
mode the PR URL and CI green, in epic mode the pushed branch), plus the bound. After each turn the
small fast model judges it from the transcript and tells the builder to carry on until it shows.
The judge sees tool results, so a **Done when** the builder can show from its own session (a test
run, a command's output, a file's contents) is judgeable; one only the conductor or a merge can
show is not, and the judge would push forever or call it impossible. So the goal adds one line to
what `/plan-epic` and its skeptics already hold a story to (`docs/method.md` § Scoping an epic): a
story's **Done when** names what the builder's session can show. Builders only: a conductor idles on
purpose while its background waits run; it can get a goal in a later HLD once builders have proved
it.

- **Off by default.** One setting, `goal`, off unless set to a turn bound: `goal = 10` turns it on
  and puts "or stop after 10 more turns" into the condition. Turning it on is a `lead` story.
- **The bound is a brake, not a cap.** The judge counts turns from the transcript; nothing in Claude
  Code enforces it (Claude Code's own cap is eight consecutive blocks with no tool call). The hard
  limits stay `stall_minutes` and the conductor closing the builder. On infrafactory a `code`
  builder's session has a median of 121 assistant messages and a `code-risky` one 195 (its
  `agents.tsv` sessions, counted 2026-10-13), so each goal turn re-reads a large context; the bound
  is small.
- **After the brief, and within the cap.** The goal is sent through `deliver_prompt` after the
  brief has been taken up: setting a goal starts a turn with the condition as its directive, so a
  goal sent first would run the builder's first turn without the brief's rules (never merge, the
  codex loop). `deliver_prompt` must accept a `/goal` line that sets without a `working` state.
  A condition over 4,000 characters is refused at `story` time with the story named, never
  truncated: the judge would judge a different condition.
- **How a goal ends or pauses, and what the conductor does.** The states swarm-dev recognises,
  all leaving the session `idle`:
  - *met*: the goal clears; the builder has its reply. The case `wait` handles today.
  - *impossible*: the goal clears with a failed entry. A planning defect, not an attempt
    (§ Fable on call).
  - *stalled*: no tool use for several turns; the loop stops with the goal still set. An attempt.
  - *bound*: the judge honoured "stop after N more turns". An attempt.
  - *paused*: three automatic retries on a transient error failed, a rate or usage limit, or a
    hook ended the turn; the goal is still set and "a message at any time" restarts it. The
    conductor's `tell` restarts it with the findings or a "carry on"; a pause is reported, not
    counted, and the conductor gives up on it as it would on any idle builder after the nudges it
    allows.
  - *cleared on error*: authentication, exhausted credits, a context overflow that compaction
    could not clear, or a model not available. Reported by cause; the conductor stops the wave and
    lists it for the user, since no retry fixes it.
  The conductor reads the cause from the builder's transcript entries and reply; nothing new is
  read from a screen. `swarm.sh` records it in the events log beside the `close`, so Goal 3 can be
  read off the log.
- **`tell` during a goal.** A builder with a running goal is `busy`, so `tell` is refused as it is
  for any working agent; the conductor waits, as `tell` already tells it to
  (`bin/swarm.sh:900`). Once the goal is met the builder is idle and `tell` lands as a plain
  turn. Review findings are on every story's path (`docs/method.md` § Building), so a `tell` that
  carries findings sets a fresh goal, "the findings in this message are addressed and you have
  replied with the new head", with the same bound. This is a story in the goal epic, after the
  spike.
- **The condition is what the session can show.** The judge reads only the conversation, so the
  condition is the story's **Done when** as evidence in the transcript plus the reply the
  conductor will check, never a fact the session cannot surface. The conductor's verification
  (every check green on the head, findings triaged, codex and `/code-review` passed) is unchanged
  and remains the gate; a goal cannot pass a story.
- **Spike first.** Interactive `/goal` is documented; what is not is its delivery through herdr's
  `agent prompt` paste (a multi-line condition as one command), the ordering with the brief, and
  whether `claude "/goal ..."` sets a goal as an interactive launch prompt. The epic's first story
  proves delivery after the brief in a herdr pane with hooks on as builders run them
  (`--permission-mode auto`, no `disableAllHooks`, no `--bare`), and tries the launch-prompt form
  and the settings-level Stop hook (§ Alternatives) beside it. If no form works, the epic stops
  there and the rest is not built.
- **Check-ins.** `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` (default 30) is the first interval a goal waits
  on a builder's own background shell, such as watching CI; later check-ins back off and stop
  after the third. `0` also turns off the automatic retries, so it is left at the default, the
  same order as `stall_minutes`.
- **The judge's provider and cost.** The judge runs on the session's provider on the small fast
  model, so a goal is available on Bedrock, Vertex and Foundry where that model resolves (unlike
  the advisor). Whether its tokens land in the session `.jsonl` that `swarm.sh cost` reads is
  unverified; `cost` may undercount the judge until checked on one session.

## Alternatives

- **herdr's status with Claude Code as a cross-check.** Keep herdr's word and consult the session
  only on `unknown` or disagreement. Declined: the pane-text workaround would stay, and a rule for
  which source wins is a heuristic on top of a heuristic. What the design keeps from it is herdr's
  wait as the wake-up: a trigger to look, never the answer.
- **Claude Code hooks as the state source.** A `Stop`, `Notification` or `PermissionRequest` hook
  written by swarm-dev would report each builder's state to a file under `.swarm/state/`, the way
  herdr's `SessionStart` hook reports the session id: no polling, and no reliance on the interactive
  listing. Declined for now: it needs a hook installed in every builder's settings (a worktree's
  `.claude/settings.local.json`, or the user's), is lost with `disableAllHooks` or `--bare`, and
  duplicates state Claude Code already keeps and lists. It is the fallback if the interactive
  listing drifts out of `claude agents --json` (§ Risks).
- **A settings-level prompt Stop hook instead of `/goal`.** `/goal` is "a wrapper around a
  session-scoped prompt-based Stop hook"; `build_story` already creates the worktree
  (`bin/swarm.sh:1084`) and could write the story's **Done when** as a prompt Stop hook in the
  worktree's `.claude/settings.local.json`. That removes the slash-command delivery, the ordering
  question and the 4,000-character cap, and the hook input's `stop_hook_active` gives a bound
  Claude Code enforces. It loses the goal's own check-ins, retries and pause reporting, and a
  settings file in the worktree can be committed by mistake. Not chosen yet: the spike tries both
  and the goal epic picks (§ Open questions).
- **The advisor (`--advisor fable`) as Fable on call.** Opus would consult Fable mid-turn when it
  judges itself stuck, before any failure. Not now: the feature is experimental, Anthropic API only,
  needs feature-flag fetching (off with `DISABLE_TELEMETRY`), and Claude decides when to call it
  with no cap ("There is no setting to cap or force advisor calls"). The API reports advisor usage
  as `usage.iterations[]` with a `model`; whether Claude Code writes that into the session `.jsonl`
  that `swarm.sh cost` reads is unverified, so what it would cost cannot be attributed today. An
  escalation is a whole Fable session, which is coarser but bounded, visible by role, and on the
  board. Revisit when the advisor leaves experimental; check one session's `.jsonl` for
  `iterations` first.
- **Dropping `code-risky` to `high` to cut cost.** On the 12 Oct run it would have saved about $145
  of $627, if risky stories then cost what `code` stories do. Declined for this HLD: the ladder
  stays, and the saving is confounded by risky stories being larger. The one-line change in
  `policy()` remains available, measured by `swarm.sh cost`.
- **Moving `code` to Sonnet with an Opus advisor.** Saves little: cache reads are 98% of tokens
  and `cost` prices them the same for both models (`bin/swarm.sh:685`), so about $30 of $109, less
  the advisor's calls, with a weaker builder that may take more turns. Declined.

## Risks and safety

- **Interactive sessions in `claude agents --json` is the one dependency the docs do not
  promise.** The fields are documented; the interactive listing is what the installed binary does
  and one line of the docs says, against another line that says the opposite. The guard is the
  self-check in `require_claude`: the calling session must be in the list, or no agent starts. If
  a release drops interactive sessions, the hook alternative is the fallback.
- **A goal can push a builder to claim, not do.** The judge reads only the transcript. Kept safe by
  the condition naming the story's evidence and the brief's output, and by the conductor's checks
  being unchanged: every check green on the head, `swarm.sh findings` triaged, codex and
  `/code-review` passed. The merge rules (`merge = human`, the `--disallowedTools` guard, the
  brief's "never merge") are untouched.
- **A goal costs turns.** Each "carry on" re-reads the builder's whole context, and with `goal` on
  Claude Code's three retries replace `swarm.sh`'s nudges rather than stack on them. The bound is
  soft, so the hard limits stay `stall_minutes` and the conductor; `goal` is off by default and
  measured with `swarm.sh cost` on one epic before a project leaves it on.
- **A goal acts only between turns.** A builder looping inside one turn is `busy`; the stall rule,
  not the goal, catches it.
- **Hooks off.** A goal is unavailable with `disableAllHooks` (read after settings precedence, so a
  target repo's own `.claude/settings.json` can set it for every builder in its worktrees),
  `allowManagedHooksOnly`, `--safe-mode` or `--bare`; the command says why, and `story` must
  surface that as a refusal rather than build on without the goal. The agent-state join no longer
  depends on any hook.
- **Claude Code drift.** Only `claude agents --json` is read (the files under `~/.claude/jobs/` are
  "not a stable interface"). A missing field is `unknown`, a missing entry `gone`, both `!` in
  `dash`, never idle. The goal's pause and retry notices need 2.1.269 or later, check-ins 2.1.234;
  `require_claude` pins the minimum.
- **Fable may not run as Fable.** `--model` is not checked up front: an unavailable model fails on
  the first request; the usage-credits consent is a dialog that, dismissed mid-session, continues
  the turn on the default model, and for an unwatched session is held five minutes and then ends
  the turn; and a Fable request flagged by safety classifiers (often cybersecurity content, which
  infrafactory's firewall and IAM stories are) re-runs on Opus and the session continues there.
  So an `escalate` builder may sit `waiting` (`waitingFor: dialog open`), fail its first turn, or
  run on another model while `cost` attributes it to `escalate`. The conductor reads `waitingFor`
  and lists a dialog for the user; `swarm.sh cost` and `dash --ladder` read the model from the
  session's first `.jsonl` message, not the role, so a demoted attempt shows as what it ran on.
- **Fable costs more per token** (`cost` prices it at $10/$20 against Opus's $4/$20, and on some
  plans it bills to usage credits). Bounded: one Fable session per story, only after two failures,
  visible by role; `escalate_after = 0` turns it off.
- **Two new board writes by `swarm.sh`:** the attempt count and `kind: lead` after a Fable failure,
  both in `close`, like `review`, `finish` and `reconcile` already write. Agents still never edit
  the board outside their own PR.
- **The judge's cost may be invisible.** Unverified whether evaluator tokens are in the session
  `.jsonl`; `cost` may undercount until one session is checked.
- **Safety rules it touches.** None loosened: no new permission, no credential, no real cloud. A
  `lead` story is still never given to an agent; a story escalated to Fable is a normal build in a
  worktree with the same brief and guards.

## Rollout

In order; each ships on its own and the next does not depend on the last except where said.

1. **Agent state from the session.** The one change with no setting: a switch would keep both
   sources, and so the pane-text workaround, for as long as it existed. Instead `require_claude`
   refuses a Claude Code without the interactive listing or `--session-id`, naming the version, so
   an old install fails before a pane opens rather than mid-run. First story: pin the minimum
   version. Bump the plugin version. Run one infrafactory epic on it before step 2 starts, so the
   attempt count in step 2 is fed by a state source already trusted.
2. **Fable on call.** `attempts:` and its one writer, the conductor's give-up rule, `escalate` in
   `build_story`, the `lead` item after Fable with `swarm.sh reset`, the two tests and the ladder
   counts. Ships on (`escalate_after = 2` by default; the user's call, recorded in § Fable on
   call). Log the unwired role with `swarm.sh log-finding doc-ahead-of-code ...` so the
   outer loop can make a rule of it if it recurs.
3. **A goal for builders.** The spike story first (delivery, ordering, the launch-prompt form and
   the Stop-hook form); then the `goal` setting, the condition in the brief, the end and pause
   causes in the events log, the nudge/findings distinction, the fresh goal on `tell`, and the
   method text. Ships off. A `lead` story turns it on for infrafactory for one epic, and
   `swarm.sh cost` and the nudge count decide whether it stays on.

## Open questions

- **`/goal` or a settings-level Stop hook.** Same judge, same condition; the hook has no delivery
  path, no cap and a bound Claude Code enforces, but loses the goal's check-ins and pause
  reporting and puts a file in the worktree. The spike tries both; the goal epic picks on what
  the spike shows. Deferred to the goal epic.
- **The default bound when `goal` is set.** Small; the number comes from the spike (how many goal
  turns a builder that stopped short needs to finish). Deferred to the goal epic.
- **The minimum Claude Code version.** The docs do not say which release first listed interactive
  sessions in `claude agents --json`; the first story of the agent-state epic finds it. Deferred.

## Epics

- [agent-state-from-the-session](../epics/agent-state-from-the-session.md)
- [fable-on-call](../epics/fable-on-call.md)
- [goal-for-builders](../epics/goal-for-builders.md)
