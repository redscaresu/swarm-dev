# What the lead still does by hand

These are the steps a lead still takes by hand as of v0.29.0. Each one is a gap in swarm-dev with an
open issue. Read this list once a session. When one of these symptoms shows, do the step, then log it:

```bash
swarm.sh intervene lead-hand <cause> "<slug or PR>: <what you saw and did>"
```

The cause is one word from the list in `/swarm-dev:swarm` (`flaky-test`, `review-rounds`, `upgrade`
and so on). An unknown one fails and lists them all.

That line feeds the next release's retro. Each release removes the entries it fixes, so the list
should get shorter.

## Finished panes left open

**Symptom.** `herdr agent list` shows many agents with status `done`: review agents, planning agents,
conductors of finished epics.
**Step.** `herdr pane close <pane>` for each. With `merge = agent`, close a conductor only after its
Finish PR's `swarm.sh merge --board` has exited; closing it sooner kills that merge.
**Issue.** [#690](https://github.com/redscaresu/swarm-dev/issues/690).

## A builder that keeps changing its PR

**Symptom.** A builder pushes again and again after opening its PR, so CI restarts and no review
starts; or `review-agent` refuses with `worktree has uncommitted changes` while the builder runs
checks in place.
**Step.** Nudge it: push what is ready, put further points in the PR body, run mutation checks on a
copy of HEAD.
**Issue.** [#695](https://github.com/redscaresu/swarm-dev/issues/695).

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
