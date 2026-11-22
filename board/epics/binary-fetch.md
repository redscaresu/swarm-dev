---
status: active
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
depends_on: [binary-wrapper]
stage: v0.32.0
---

# Goal 5

An installed copy gets its binary by itself: every swarm.sh call makes sure a checked binary is there, downloaded with gh, or built from the source beside it when that cannot work.

Stage 1 of the [v0.32 Go rewrite HLD](../hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md).

**Done when:** Under stubs but where said: (1) On an installed copy with no binary and no variable set, any swarm.sh call but `version` and `update` first runs `gh release download` for its version and platform, checks the SHA-256, runs `gh attestation verify` for this repo with the release workflow as the signer, writes the binary atomically into the plugin folder and exports its path. A command with no marker whose bash calls a helper entry then finds it. The gh stub fails on any other arguments. (2) A wrong checksum, a failed attestation or a quarantine mark each stop the call with one line and run nothing. The quarantine case also runs in the macOS job with a real `xattr -w com.apple.quarantine`. (3) The checks run once, at download, except the quarantine check, which on macOS also runs on every call (the user chose (b) in quarantine-present on 2026-11-22). A later call makes no gh call, and the time a call adds with the binary present is measured and recorded. (4) With no network, another platform or a gh too old to verify, it builds from source when Go is installed and says so. With no Go, or with a local Go older than go.mod's pin and no network, it stops with one line saying why and what to do. It never runs old bash for a ported command. (5) Two wrappers started together on an empty folder both end with one whole binary. (6) The download uses the real gh and skips every gh-shim folder on PATH: with this version's shim folder and an older version's first on PATH, an empty plugin folder and no Go, the download succeeds and does not loop. (7) `swarm.sh version` and `update` still run with no binary and no network; `version` tries the fetch and says in one line when it could not.

**Out of scope:**
- The release workflow that publishes the files (release-ci)
- A run against a real release (release-client)
- Hook and gh-shim wrappers (port-guard, port-hooks)
- Signing and notarising the macOS binaries: the fallback, not built (HLD:222)
- Downloading with curl
- Windows

**Constraints:**
- stage: v0.32.0. bash 3.2, shellcheck.
- Asset names, the checksum file and the signer's workflow path come from go-module's build script.
- The wrapper downloads only with `gh release download` and keeps the binary in the plugin's own folder (HLD:214-217).
- Helpers are ported before any command and have no marker (HLD:266-268), which is why the binary is made sure of on every call, not only for a marked command.
- The shim is first on PATH for swarm.sh and every agent (bin/swarm.sh:229-233), and in stage 3 it needs the binary itself: the download may not go through it.
- Every check here runs under stubs but the quarantine case. release-client runs the wrapper against a real release (rules.md:9).
- Docs move in the same PRs: README.md's requirements and docs/running.md's first run and offline parts.

**Your part:**
- You merge the PR that adds the quarantine case to the macOS job (.github/).
- Carve-out (HLD:480-485): none. No story here touches the guard, merge or the release gates, or names env:.

**Areas:**
- bin/swarm.sh (binary lookup and fetch)
- tests/
- .github/workflows/ci.yml (macOS job)
- README.md (requirements)
- docs/running.md (first run, offline)
