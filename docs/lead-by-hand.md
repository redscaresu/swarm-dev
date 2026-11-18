# What the lead still does by hand

These are the steps a lead still takes by hand as of v0.31.0. Each one is a gap in swarm-dev with an
open issue. Read this list once a session. When one of these symptoms shows, do the step, then log it:

```bash
swarm.sh intervene lead-hand <cause> "<slug or PR>: <what you saw and did>"
```

The cause is one word from the list in `/swarm-dev:swarm` (`flaky-test`, `review-rounds`, `upgrade`
and so on). An unknown one fails and lists them all.

That line feeds the next release's retro. Each release removes the entries it fixes, so the list
should get shorter.

## A conductor's merge refused by the permission classifier

**Symptom.** A conductor reports that `swarm.sh merge` was refused by auto mode.
**Step.** Run the same merge from the lead's pane.
**Issue.** [#699](https://github.com/redscaresu/swarm-dev/issues/699).
