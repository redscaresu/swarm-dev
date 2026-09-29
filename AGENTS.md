# AGENTS.md

You are an agent. This file tells you how to use swarm-dev in a project, and how to work on this
repository. The method, and why it is shaped this way, is in [`docs/method.md`](docs/method.md):
read it before you run anything.

## Using swarm-dev in a project

**Check before you start.** Stop and tell the user which is missing if any of these fail:

```bash
[ "$HERDR_ENV" = 1 ]            # you are inside a herdr pane; every agent opens a pane beside you
command -v swarm.sh             # the plugin is installed and this session started after it
gh auth status                  # PRs, checks and merges go through gh
git remote get-url origin       # a GitHub origin; swarm.sh resolves the owner from it
```

If `swarm.sh` is missing, the user runs `claude plugin marketplace add redscaresu/swarm-dev` and
`claude plugin install swarm-dev@swarm-dev`, then restarts Claude Code.

**Set the project up** if `docs/stories/README.md` does not exist: follow the README's
§ Quick start, step 3. Ask the user for the contents of `.claude/swarm/brief.md` (their commit
trailers, where credentials live, commands that must not run); do not invent them.

**Run the chain, one level at a time, and let the user approve each:**

| Step | You run | It produces |
|---|---|---|
| Design | `/hld <title>` | `docs/hld/YYYY-MM-DD-<slug>.md`, co-written in its own pane |
| Epics | `/plan-hld <hld-file-name>` | `docs/epics/<slug>.md` per epic, after approval |
| Stories | `/plan-epic <epic-slug>` | `docs/stories/<slug>.md` per story, after approval |
| Build | `swarm.sh conduct <epic-slug>` | a fresh conductor that builds and merges the epic |

Useful while it runs: `swarm.sh policy <role>` (model and effort for a role), `swarm.sh watch`
(returns when a story PR needs the lead), `herdr agent read <name> --source recent-unwrapped`
(what an agent is doing).

**Rules that are not negotiable:**

- You supervise; the agents do the work. Do not write an HLD, epic or story plan yourself when a
  command exists for it.
- Never merge a PR whose checks are not all green on its head commit.
- Never hand a `kind: lead` story (real cloud, credentials) or a `kind: operator` story (the user's
  decision or hand step) to an agent. List them for the user.
- One conductor at a time, and only the lead edits the shared files `AGENTS.md` names.
- A question for the user is a `kind: operator` story on the board, not a line in chat.

## Working on this repository

```
bin/swarm.sh          the only script: panes, story builds, conductors, the model policy
commands/             /hld, /plan-hld, /plan-epic (Markdown the plugin loads)
docs/method.md        the method; change it when behaviour changes
templates/docs/       what a project copies: the board formats and Obsidian views
.claude-plugin/       plugin and marketplace manifests
```

Before you open a PR:

```bash
make hooks                                  # once: the gitleaks pre-commit hook
shellcheck bin/swarm.sh scripts/pre-commit
claude plugin validate .
```

`bin/swarm.sh` must run on macOS's bash 3.2: no `mapfile`, no associative arrays. Pin every GitHub
Action to a commit SHA, with `persist-credentials: false` and read-only permissions; zizmor fails
the PR otherwise. CI (shellcheck, plugin-validate, gitleaks, zizmor) is required on `main`.
