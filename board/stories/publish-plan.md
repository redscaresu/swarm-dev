---
kind: code
status: ready
epic: release-ci
depends_on: []
touches: [scripts/publish-release.sh, tests/publish_release_test.sh]
estimate_lines: 200
risk: high
---

# scripts/publish-release.sh plan: none on a push with no bump, every step for a new release, a refusal for any other state

Needs no other story. release-workflow calls it; publish-plan-recover adds the states of a release that already exists, without changing what the plan writes.
- `scripts/publish-release.sh plan`. Env, as scripts/board-only.sh:12 takes it: REPO, SHA (the pushed commit), BEFORE (the push's previous tip, github.event.before), REF (default prerelease), GITHUB_OUTPUT; gh reads GH_TOKEN. It reads the version at SHA and at BEFORE from .claude-plugin/plugin.json with `git show` and jq. On success it writes exactly one `steps=` line (`none`, or an ordered subset of `draft attach publish move`) and, unless `none`, one `tag=v<V>` line, and prints one line saying why. On a refusal it prints one `publish-release: <why>` line, writes nothing to GITHUB_OUTPUT and exits 1.
- No bump: the version at SHA equals BEFORE's. Print `none` and make no gh call. That is every push but a release's, so a gh blip never turns main red there (ci_gate counts main's push-only workflows, bin/lib/ci_gate.py:263), and a later push never trips over a half-done release of an earlier commit (critic, skeptic-release-workflow). A BEFORE that git cannot read (all zeros) counts as a bump, so the checks below still run (fail closed).
- Refuse a version at SHA that is not MAJOR.MINOR.PATCH (the check moves from release.yml:35-38), and one lower than BEFORE's.
- Every gh read goes through one function. A 404 is an answer only on the tag and REF reads: gh exits 1 with `HTTP 404` on stderr. Check that shape once against real gh (`gh api repos/redscaresu/swarm-dev/git/ref/tags/v0.0.0`, a read) and record it in the PR. Any other failure refuses. A step is never printed on an error (skeptic-publish-plan).
- Tag, `git/ref/tags/v<V>`: a 404 is no tag. An object.type other than `commit` (an annotated tag) refuses. A tag on another commit refuses: that version was released elsewhere. A tag at SHA is publish-plan-recover's state; refuse it here, naming it.
- REF, in its own function (publish-plan-recover calls it), read before anything is drafted so a release that cannot move is never drafted: `git/ref/heads/<REF>` 404 refuses (never create it); compare `<REF>...<SHA>`: `ahead` keeps `move`, `identical` or `behind` drops it, `diverged` refuses.
- Releases: `gh api --paginate repos/<REPO>/releases`, matched by exact tag_name (rules.md: exact records). Drafts have no tag and only a write token sees them; the header says so, and that the publish job's plan is the one acted on. No release for v<V>: `draft attach publish move`. Any release for v<V> is publish-plan-recover's state; refuse it here, naming it.
- jq, as release.yml:33-34 uses; no inline python3 (docs/port lists every such site). The test runs the script as a program, stubs only gh and builds its fixture repo with git. It sources no bin/lib file and writes no python3 stub, so it needs no docs/port/tests.tsv row (critic). It is picked by scripts/test-map.tsv:43's `scripts/*` named row; add no row.

**Done when:**
- tests/publish_release_test.sh passes. It runs the script on a git fixture with a gh stub on PATH that answers from fixture files, honours --paginate, logs each call and fails any call it has no fixture for. It prints exactly `none` for a push whose version equals BEFORE's, with an empty call log; and `draft attach publish move` for a bump with no tag, no release and REF behind, and for the same with BEFORE all zeros. Each of these exits 1 with one `publish-release:` line and nothing in GITHUB_OUTPUT: a version that is not MAJOR.MINOR.PATCH; a version lower than BEFORE's; an annotated tag; a tag on another commit; a tag at SHA; a release for v<V>; REF missing and REF diverged, both with no tag and no release; and a failed read of the tag, of REF, of the compare and of the releases list, each on its own. Each success writes exactly one steps= line, and one tag= line unless steps is none. The PR records real gh's exit code and stderr for a 404, and the stub matches them. Each case goes red when the branch it covers is broken, shown on a copy of the worktree without .git.
- scripts/select-tests.sh --run passes
