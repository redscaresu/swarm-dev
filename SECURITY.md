# Security Policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.
Report privately through GitHub's
[private vulnerability reporting](https://github.com/redscaresu/swarm-dev/security/advisories/new).

Please include a description of the issue and its impact, steps to reproduce,
and the affected commit or version.

## What swarm-dev can reach

swarm-dev holds no credentials of its own. `swarm.sh` starts Claude Code and
codex agents in herdr panes, and they run with your local `claude`, `codex`,
`gh` and `git` authentication, in auto permission mode. The standard builder
brief forbids touching real cloud or credentials and forbids merging; a project
adds its own rules in `.claude/swarm/brief.md`. Stories that need real cloud or
credentials (`kind: lead`) or a human (`kind: operator`) are refused by the
swarm, not handed to an agent.

A path by which an agent started by swarm-dev could read credentials, merge, or
act outside its worktree despite those rules is a security issue: report it
privately as above.
