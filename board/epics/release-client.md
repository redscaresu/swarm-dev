---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [binary-fetch, release-ci]
stage: v0.32.0
---

# Goal 4, swarm.sh's half

swarm.sh names the plugin it is installed as, reads the version on its own ref, counts a release done only when its files exist, and fetches a real release's binary.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** (1) With swarm-dev@swarm-dev-pre installed, `swarm.sh update`, `merge --release`'s update step and dash's install lookup act on that ID, and `merge --release` finds the new version under plugins/cache/swarm-dev-pre/swarm-dev/<version>/bin/swarm.sh and moves the agents. With swarm-dev@swarm-dev installed they act as today. (2) `swarm.sh update` ends by running the new version's wrapper once, so its binary is there before the next session's hooks run. (3) `swarm.sh version` warns only about a version on the machine's own ref, inside its time bound. (4) `merge --release` reports a release done only once its four files and checksums are attached and the ref has moved. (5) On the public throwaway copy the real wrapper downloads and verifies a published asset, and refuses one that was swapped after publishing. With prerelease moved back one version, an update and a restart run the older version's binary. (6) No doc states the old release or update behaviour: README.md's install and update, docs/running.md's updating, AGENTS.md's patch rule ("A fix to the swarm's own loop ... ships as a patch release") and its release paragraph ("When `swarm.sh next` prints `release` ..."), commands/swarm.md's release arm, llms.txt:5 and docs/lead-by-hand.md's switch to prerelease.

**Out of scope:**
- The release workflow and the refs (release-ci)
- The download code (binary-fetch)
- Porting any of this to Go (port-release)
- `swarm.sh upgrade`, which names no plugin (bin/lib/lifecycle.sh:5346-5362)

**Constraints:**
- stage: v0.32.0.
- The plugin's ID and its cache folder are fixed text today: PLUGIN and MARKETPLACE at bin/swarm.sh:129-130, used at :153-154, bin/lib/dash.sh:551 and bin/lib/merge.sh:2636,2642-2643.
- The version check reads main's plugin.json with curl (bin/swarm.sh:127,141). It reads the machine's own ref, with a time bound (tests/timeouts_test.sh).
- release_confirmed reads only that the release is not a draft (bin/lib/merge.sh:2711-2729).
- It edits bin/swarm.sh's version block after binary-wrapper and binary-fetch changed plugin_version beside it (bin/swarm.sh:133), which is why it depends on binary-fetch.
- AGENTS.md says a loop fix ships as a patch 'so running projects get it' (AGENTS.md:147-148). It becomes: the prerelease machine gets it at once, every other machine at the stage's end (HLD:70-73).
- An 0.31.2 install keeps reading main's plugin.json, so between the v0.32.0 tag and the stage exit it warns about a version it cannot get yet.
- release_upgrade and release_confirmed are bash that nothing holds for the user in stage 1; the stories that touch them wait for the user's go on the board PR (HLD:480-485).

**Your part:**
- Lead: run the real-release check on the public throwaway copy.
- Carve-out (HLD:480-485): the stories that touch `merge --release` (release_upgrade, release_confirmed) are listed. You clear them on the board PR.
- Its stories that change release_confirmed or release_upgrade while they are bash are merged in a merge = human window, as ship-gates' are: the lead sets merge = human, you merge, the lead sets it back (P12) (critic).

**Areas:**
- bin/swarm.sh (show_version, update_plugin, PLUGIN)
- bin/lib/dash.sh (dash_installed)
- bin/lib/merge.sh (release_upgrade, release_confirmed)
- README.md (install, update)
- docs/running.md (updating)
- AGENTS.md (patch rule, release paragraph)
- commands/swarm.md (release arm)
- llms.txt
- docs/lead-by-hand.md (switch to prerelease)
- tests/

**Shared rules cited above:**
- P12: A story that changes a rule of the guard, merge, the release gates or the agents' environment while that rule is still bash is merged by the user, through a merge = human window as in ship-gates. A port that only swaps a call site in those files is not such a change.

**release-ci's results:** the throwaway copy (redscaresu/swarm-dev-release-spike), its rulesets, and the spike, install and publish proofs are recorded in [board/epics/release-ci.md at 6db3c48e](https://github.com/redscaresu/swarm-dev/blob/6db3c48e202814122fd8b9eb2b801cffeff38eca/board/epics/release-ci.md), the last version before release-ci finished. The real-release check here uses that copy.
