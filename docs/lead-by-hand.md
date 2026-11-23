# What the lead still does by hand

These are the steps a lead still takes by hand as of v0.32.0. Each one is a gap in swarm-dev with an
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

## Rolling back the prerelease

**Symptom.** A port released to prerelease stalls the swarm.
**Step.**
1. Revert or fix the port on main first. The next release moves prerelease forward past the rollback.
2. Move prerelease back to the tag commit of the last good release. Use your force-push: the admin role may do it, and `github.token` may not.
   Find the commit with `git rev-parse v<good>^{commit}`, then run `gh api -X PATCH repos/redscaresu/swarm-dev/git/refs/heads/prerelease -f sha=<commit> -F force=true`.
3. In each session that follows prerelease, run `claude plugin marketplace update swarm-dev-pre` and `claude plugin update swarm-dev@swarm-dev-pre`, then restart the session.
   The update rewrites the install path and the restart loads it. No uninstall or cache clear is needed. The release-install-proof run showed the older plugin.json and hooks come back this way, and release-client's real-release check showed the older binary does too.
4. Check that stable and prerelease point at their tags (L2 in the release-ci epic). Everyone shares one gh login, so the ruleset cannot tell a stray push from yours.
5. Do not re-run the release run of the version you rolled back from, in either form ("Re-run all jobs" or "Re-run failed jobs"). A rerun finishes that release and moves prerelease forward again.

**Issue.** [#1116](https://github.com/redscaresu/swarm-dev/issues/1116).

## Switching to the prerelease

**Symptom.** A stage's trial starts, and a machine should run what prerelease holds, not stable.
**Step.**
1. Run `claude plugin marketplace add https://github.com/redscaresu/swarm-dev.git#pre-marketplace`, then `claude plugin install swarm-dev@swarm-dev-pre`.
2. Run `claude plugin uninstall swarm-dev@swarm-dev`. Both installs enabled at once load the hooks twice.
3. Restart every session. Check with `swarm.sh version` that each prints prerelease's version.
4. At the stage's end, once stable has moved, go back: install swarm-dev@swarm-dev, uninstall swarm-dev@swarm-dev-pre, and restart. `swarm.sh version` then prints stable's version, which also checks that stable updates.

**Issue.** [#1153](https://github.com/redscaresu/swarm-dev/issues/1153).
