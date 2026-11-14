# Retros

A retro goes through the retro report's lists and decides what becomes of each item.
Its file is `retros/v<version>.md` on the board, named for the version being released.

```
---
covers: v<from>..v<to>
done: YYYY-MM-DD
---

# Retro v<version>

Report: written at <commit or version> by swarm.sh.

## <one of the report's lists>

- <item>: story <slug>
- <item>: check <the test or check that now catches it>
- <item>: rule in <rules.md, the project's brief or AGENTS.md>
- <item>: dropped, <the reason>
```

`covers:` is the window the retro covers, from an earlier tag to the version the file is named for, and `done:` is the day it was finished.
Write each on one line with no quotes, so that a check running in bash 3.2 can read them.
The body takes every item on the report's lists and says what became of it: a story, a check, a rule (in rules.md, the project's brief or AGENTS.md), or a drop with its reason.
It also says which swarm.sh wrote the report, by its commit or its version.

The retro is a `kind: lead` story named `retro-<version>`, with each dot written as `-`, such as `retro-v0-31-0`.
It marks each step that is yours with **You:**.
The retro file lands by board PR.
A rule the retro places lands in its own PR, before the retro file's.

A file here that lacks `covers:` or `done:` is a note, and no check reads it as a retro.
The Retros view in `Board.base` lists every file whose `covers:` is set, so this README and the notes with no `covers:` stay out of it.
