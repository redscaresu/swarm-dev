# Retros

A retro closes a release: it takes each item of the retro report's lists and decides what becomes of it.
Its file is `docs/retros/v<version>.md`, named for the release it ends.

```
---
covers: v<from>..v<to>
done: YYYY-MM-DD
---

# Retro v<to>

Report: written at commit <sha> by swarm.sh.

## <the report's list>

- <item>: story <slug>
- <item>: check <test or check that now catches it>
- <item>: rule in <rules.md, the project's brief or AGENTS.md>
- <item>: dropped, <the reason>
```

`covers:` names the two tags the retro spans, and `done:` the day it finished.
Write each on one line, with no quotes, so a check in bash 3.2 can read them.
The body lists every item of the report's lists with what became of it: a story, a check, a rule (in rules.md, the project's brief or AGENTS.md), or a drop with its reason.
It also names the commit of the swarm.sh that wrote the report.

The retro itself is a `kind: lead` story named `retro-<version>` with each dot a `-`, such as `retro-v0-31-0`.
Its **You:** steps are the decisions on each item.
The retro file lands by board PR.
A rule the retro places lands in its own PR first, so the file can point at it.

A file here that lacks `covers:` or `done:` is a note.
No check reads a note as a retro.
The Retros view in `Board.base` lists every file with a `covers:` value, so a retro still under way shows there before its `done:` is set.
