---
kind: code
status: ready
epic: safer-faster-swarm
depends_on: []
touches: [hooks/hooks.json (new), hooks/merge-guard.sh (new), docs/reference.md:§ merging guard paragraph (reference.md:531,680,742), README.md:merging line, tests/merge_guard_test.sh (new)]
risk: high
easy: false
estimate_lines: 280
---

# A plugin hook makes swarm.sh merge the only merge command in a swarm project, including through interpreters and scripts

merge_pr already pins the head, gates CI and holds costs: money (bin/swarm.sh:4036-4143). The repo has no hook, only --disallowedTools on the agents it starts (:648). The user's global hook (~/.claude/hooks/block-red-pr-merge.sh:18-23) matches only a command position and lets quoted forms through, so it does not cover them either. Ship hooks/hooks.json (PreToolUse, matcher Bash) running ${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.sh, a standalone script with no swarm.sh dispatch arm. It reads the tool call's JSON on stdin and acts only when the cwd is inside a swarm project (a .claude/swarm/config up the tree). It blocks: gh pr merge; gh api .../pulls/<n>/merge; gh api graphql with mergePullRequest; any of those inside text handed to a shell or interpreter (bash/sh/zsh -c, eval, python/node -c|-e, a heredoc or pipe into one of them, a heredoc written to a file); and swarm.sh merge joined to any other command (;, &, &&, ||, |, newline, $( ), backticks). A lone `swarm.sh merge ...` passes, as do plain mentions in echo, printf or grep. A block exits 2 with the reason and appends an incident line `merge-blocked: <form>` to the project's .swarm/events.tsv in record_event's five-field format. Outside a swarm project it allows everything. risk high: a wrong match blocks the lead or lets a raw merge through.

**Done when:**
- tests/merge_guard_test.sh feeds hook JSON on stdin. These exit 2: raw gh pr merge; gh api .../merge; `gh api graphql -f query='mutation{mergePullRequest...}'`; `bash -c "gh pr merge 1"`; `eval "gh pr merge 1"`; `python3 -c "import os; os.system('gh pr merge 1')"`; a heredoc holding gh pr merge written to m.sh and then run; `cd x && swarm.sh merge <url>`; `swarm.sh merge <url>; echo`; `swarm.sh merge <url> & echo`. These exit 0: `swarm.sh merge <url>`, `echo "gh pr merge"`, `grep 'swarm.sh merge' f`, and every case run outside a swarm project.
- The same test reads the command from hooks.json (matcher Bash, path under ${CLAUDE_PLUGIN_ROOT}), runs it with CLAUDE_PLUGIN_ROOT set to the repo on a raw gh pr merge JSON, and gets exit 2.
- A blocked call writes one incident line to events.tsv; `claude plugin validate .` passes.
