---
kind: code
status: blocked
epic: release-ci
depends_on: [publish-plan]
needs: publish-plan (scripts/publish-release.sh plan, its gh read and REF functions, and tests/publish_release_test.sh's gh stub)
touches: [scripts/publish-release.sh:plan (the states of an existing release), tests/publish_release_test.sh:existing-release cases]
estimate_lines: 150
risk: high
---

# scripts/publish-release.sh plan finishes a release that already exists, and refuses one it cannot finish safely

Uses publish-plan's `scripts/publish-release.sh plan`, its gh read and REF functions, and its test's gh stub. It replaces publish-plan's two refusals for an existing release (a tag at SHA; a release for v<V>) with these states, and writes the same `steps=` and `tag=` lines. Epic Done when (3) rests on it; release-publish-proof proves it on the copy (codex: split from publish-plan).
- The five file names come from `scripts/build.sh --list` (the asset lines and the checksums line), never a copy (build.sh:2-4).
- Tag at SHA and one published release for v<V> holding all five: `move`, or `none`, by publish-plan's REF function.
- No tag and one draft for v<V> whose target_commitish is SHA: `attach publish move` (move by the REF function), whatever files it holds. attach uses --clobber, on a draft only.
- Refuse, naming the state: a published release missing a file (never write to a published release); a draft at another commit; two or more releases for v<V>; a tag at SHA with no published release.
- The REF check still comes first, so a draft whose REF has diverged refuses too.

**Done when:**
- tests/publish_release_test.sh passes with these cases added on publish-plan's stub. It prints exactly: `move` for a tag at SHA with a published release holding all 5 files and REF behind; `none` for the same with REF at SHA, and with REF ahead; `attach publish move` for a draft at SHA holding 2 of the 5 files, and for the same draft on the second page of the releases list (skeptic-publish-plan). Each of these exits 1 with one line and nothing in GITHUB_OUTPUT: a published release missing a file; a draft at another commit; two drafts for v<V>; a tag at SHA with no release; a draft at SHA with REF diverged. publish-plan's cases still pass. Each new case goes red when the branch it covers is broken, shown on a copy of the worktree without .git.
- scripts/select-tests.sh --run passes
