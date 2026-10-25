# Brief

## Commits
- End every commit message with the trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Sign every commit and merge with `-S` (GPG). If signing fails, stop and report that you are
  blocked; never commit unsigned.
- PR bodies end with: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

## Credentials
- GitHub: `gh`'s own login (`gh auth`). Run `unset GITHUB_TOKEN` before any `gh` call, so a stray
  token never shadows it.
- Claude: Azure Foundry, from the session environment. swarm.sh passes the `ANTHROPIC_FOUNDRY_*` and
  `ANTHROPIC_DEFAULT_*_MODEL` variables to every agent; never print their values.
- codex: its own login (`codex login`).
- No secret ever goes in code, a commit, a PR body, a log or a comment.

## Never run
- A merge by any route but `swarm.sh merge` (no `gh pr merge`, no `gh api` merge, no web page).
- A push to `main`, or a force-push to any branch but your own story branch (and then only with
  `--force-with-lease`, naming the branch).
- `git checkout -- <file>`, `git restore`, `git reset --hard`, `git stash` or `git clean` on
  uncommitted work. To undo a temporary edit, copy the file aside and copy it back.
- Anything that reads a private key or credential file (`*.pem`, `~/.ssh`, `~/.aws/credentials`):
  not with cat, grep or any tool.
- An install of a package version reported as malicious, even to check it. Check with metadata only
  (`npm view <pkg>@<ver> version`).
- Anything that creates, changes or deletes cloud resources.
