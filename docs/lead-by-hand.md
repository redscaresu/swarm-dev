# What the lead still does by hand

These are the steps a lead still takes by hand as of v0.29.0. Each one is a gap in swarm-dev with an
open issue. Read this list once a session. When one of these symptoms shows, do the step, then log it:

```bash
swarm.sh intervene lead-hand "<slug or PR>: <what you saw and did>"
```

That line feeds the next release's retro. Each release removes the entries it fixes, so the list
should get shorter.

## Review rounds that do not end

**Symptom.** A PR is on its third or later findings round, each round finding new edge cases, or
codex raises a point the builder already declined with evidence.
**Check.** Read the round's findings (`.swarm/reviews/<slug>.round.md`, or `<slug>.md` once the
review agent has stopped). Is any finding a regression this PR
introduces, or a line that is now false about the code?
**Step.** Send one last round that fixes only those. Send it as a nudge
(`swarm.sh tell <slug> nudge <file>`), not as findings. Then accept: `swarm.sh review <slug> <PR URL>`,
then, with `merge = agent` or an HLD `merge` grant, `swarm.sh merge --head <full sha> <PR URL>`;
otherwise the PR waits for the user's merge. File the rest as a follow-up story.
**Side effect.** A findings tell counts a round once it is delivered; with `escalate_ladder` set, the `step_up_findings`-th
round (default 3) steps the builder up to the next model, and on the top rung a round can hold the
story for the lead. A nudge counts no round.
**Issue.** [#685](https://github.com/redscaresu/swarm-dev/issues/685), and
[#686](https://github.com/redscaresu/swarm-dev/issues/686) for a lighter review in later rounds.

## A false stall step-up

**Symptom.** `escalate` moves a builder up a model (`stalled`) while it was waiting on its own
background test run, or could not sign a commit.
**Check.** `herdr agent read <slug>`: a live background shell or a GPG error.
**Step.** Leave a waiting builder alone. For GPG, see below.
**Issue.** [#687](https://github.com/redscaresu/swarm-dev/issues/687).

## An agent that fails to start

**Symptom.** `swarm.sh story` fails with `pane ... not found`,
`the pane's shell did not take the agent's environment` or `agent_not_found`, often under load.
`swarm.sh review-agent` makes up to 3 starts on these by itself, so it needs no rerun.
**Step.** Run the `swarm.sh story` command again, up to twice.
**Issue.** [#688](https://github.com/redscaresu/swarm-dev/issues/688).

## A locked GPG agent

**Symptom.** Builders stop with staged, unsigned work, or commits fail to sign.
**Step.** Ask the user to unlock GPG, then nudge each builder that was waiting.
**Issue.** [#689](https://github.com/redscaresu/swarm-dev/issues/689).

## Finished panes left open

**Symptom.** `herdr agent list` shows many agents with status `done`: review agents, planning agents,
conductors of finished epics.
**Step.** `herdr pane close <pane>` for each. With `merge = agent`, close a conductor only after its
Finish PR's `swarm.sh merge --board` has exited; closing it sooner kills that merge.
**Issue.** [#690](https://github.com/redscaresu/swarm-dev/issues/690).

## A merge refused because a story file is gone

**Symptom.** `swarm.sh merge` refuses with `a story on the board cannot be read` just after another
merge.
**Step.** `git pull` in the project, then run the merge again.
**Issue.** [#691](https://github.com/redscaresu/swarm-dev/issues/691).

## A PR outside any story

**Symptom.** `swarm.sh merge` refuses with `no story or epic lists <PR URL>`.
**Step.** If a lead story covers it, list it with `swarm.sh review <slug> <PR URL>` first. Otherwise
leave the PR for the user to merge.
**Issue.** [#692](https://github.com/redscaresu/swarm-dev/issues/692).

## A merge of main that may have dropped main's lines

**Symptom.** A PR's branch contains a merge of the base, especially one that resolved a conflict.
**Check.** `git show --remerge-diff <merge commit>`: every removed line must be one the PR means to
remove. Also, `git diff origin/<base>...<head> --stat` should match
`git diff $(git merge-base origin/<base> <head>) <head> --stat`.
**Step.** If a line of the base was dropped, send the builder a nudge naming it before you merge.
**Issue.** [#693](https://github.com/redscaresu/swarm-dev/issues/693).

## A builder that keeps changing its PR

**Symptom.** A builder pushes again and again after opening its PR, so CI restarts and no review
starts; or `review-agent` refuses with `worktree has uncommitted changes` while the builder runs
checks in place.
**Step.** Nudge it: push what is ready, put further points in the PR body, run mutation checks on a
copy of HEAD.
**Issue.** [#695](https://github.com/redscaresu/swarm-dev/issues/695).

## A builder that loads the machine or reads session logs

**Symptom.** A builder runs a long, heavy load test on the machine running the swarm, or searches
`~/.claude/projects`.
**Step.** Stop it and tell it the rule: no load generation on this machine, no session logs.
**Issue.** [#696](https://github.com/redscaresu/swarm-dev/issues/696).

## A new epic with no conductor

**Symptom.** A plan PR merged with `swarm.sh merge --board` set an epic active, and no conductor
started for it.
**Step.** `swarm.sh conduct <epic>`.
**Issue.** [#697](https://github.com/redscaresu/swarm-dev/issues/697).

## A flaky test

**Symptom.** `tests/watch_opened_test.sh` passes every case, then fails with
`rm: cannot remove ...: Directory not empty`.
**Step.** Once the run finishes, `gh run rerun <run id> --failed`. Tell the builder it is not from
its change.
**Issue.** [#698](https://github.com/redscaresu/swarm-dev/issues/698).

## A conductor's merge refused by the permission classifier

**Symptom.** A conductor reports that `swarm.sh merge` was refused by auto mode.
**Step.** Run the same merge from the lead's pane.
**Issue.** [#699](https://github.com/redscaresu/swarm-dev/issues/699).

## After a release

**Symptom.** `swarm.sh upgrade` (run by `merge --release`) moves no running agent, or lists agents
that are closed.
**Step.** Restart the lead session yourself. Agents already running finish on the old version.
**Issue.** [#694](https://github.com/redscaresu/swarm-dev/issues/694).
