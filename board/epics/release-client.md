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

## real-release-check results (2026-11-23)

The lead ran these on the throwaway copy redscaresu/swarm-dev-release-spike, from a throwaway CLAUDE_CONFIG_DIR (/tmp/rrc/cc), with SWARMDEV_BIN and SWARM_PROJECT unset.

- **Before:** copy main c389aba3, stable 3ed134ce, prerelease 097c6ca7, pre-marketplace 25af1ca5, newest release v0.31.8. swarm-dev stable and prerelease 06b35a67, pre-marketplace 653d9366, newest release v0.31.3.
- **The copy brought forward:** swarm-dev main d3a2b1d2 merged in (5d8944d, 1cc59cd). One copy-only commit, b944ae49, keeps plugin.json at the copy's 0.31.8 and sets `binary_repo` to the copy. No seam was added to swarm-dev.
- **v0.31.90:** published with five files, and prerelease moved to e8ffb92e: https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45097381585
- **Install:** `claude plugin marketplace add https://github.com/redscaresu/swarm-dev-release-spike.git#pre-marketplace`, then `claude plugin install swarm-dev@swarm-dev-pre`. Scope user, installPath .../swarm-dev-pre/swarm-dev/0.31.90, version 0.31.90.
- **The real wrapper's fetch:** v0.31.90's `swarm.sh version` downloaded and verified darwin/arm64. Its swarm's SHA-256 6cff7344…36c3 is v0.31.90's SHA256SUMS line. The file carries com.apple.provenance only, no quarantine mark.
- **Update:** after v0.31.91 published (https://github.com/redscaresu/swarm-dev-release-spike/actions/runs/45097735824), v0.31.90's `swarm.sh update` moved the install to 0.31.91. v0.31.91's folder held a swarm with v0.31.91's sum, 097286bc…a56c, before any restart.
- **Swaps on v0.31.91:** each upload took a new asset id with the uploaded file's digest, so GitHub accepted each one.
  - (i) Another file under swarm-darwin-arm64, SHA256SUMS unchanged: refused. "the SHA-256 of v0.31.91's swarm-darwin-arm64 does not match its line in SHA256SUMS", and no swarm was installed.
  - (ii) An unattested local build, its sum written into SHA256SUMS: refused. "gh attestation verify failed … not proven and it was not run", and no swarm was installed.
  - (iii) v0.31.90's attested swarm-darwin-arm64 under v0.31.91's name, its sum written into SHA256SUMS: **installed**. Its SHA-256 6cff7344 is v0.31.90's. binary_attest checks only --repo and --signer-workflow, so an older release's signed binary passes as a newer one. The fix is the story binary-attest-release-commit.
  - The originals were restored with --clobber, and the release read shows their digests again. Positive control: a fresh fetch installed v0.31.91's 097286bc.
- **Rollback:** the admin role force-moved the copy's prerelease to v0.31.90 (e8ffb92e), after v0.31.90's swarm was removed. v0.31.91's `swarm.sh update` moved the install to 0.31.90 ("updated from 0.31.91 to 0.31.90"). installPath is .../0.31.90, and its swarm has v0.31.90's sum, 6cff7344.
- **Restart:** a fresh `claude -p` session on the throwaway config found .../0.31.90/bin/swarm.sh. `swarm.sh version` printed 0.31.90, and the swarm beside it hashed to 6cff7344…36c3.
- **After:** copy main 1366655d, stable 3ed134ce, prerelease e8ffb92e (left at v0.31.90's commit), pre-marketplace 25af1ca5, newest release v0.31.91. swarm-dev stable and prerelease 06b35a67, pre-marketplace 653d9366, newest release v0.31.3: unchanged. The lead's real installed_plugins.json is unchanged (dc604ce0…). Its known_marketplaces.json changed at 02:04Z, but only in claude-plugins-official's and claude-skills' lastUpdated: a background marketplace refresh. swarm-dev's entry (2026-11-19) did not change.
