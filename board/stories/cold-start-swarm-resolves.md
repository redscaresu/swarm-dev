---
kind: code
status: ready
epic: cold-start
depends_on: []
touches: [commands/, skills/swarm-dev/SKILL.md, README.md]
---

# Typing `/swarm` and Enter in a fresh install runs swarm-dev's /swarm, not /hld

The cold-start check (2026-10-14, a throwaway CLAUDE_CONFIG_DIR with only swarm-dev 0.14.1 installed) typed `/swarm` and pressed Enter. The slash menu completed it to `/swarm-dev:hld`, its first match, so a new user following the README lands in /hld. Find out from Claude Code's docs and a fresh session how the slash menu ranks plugin commands. Then make the name the README, the skill and /swarm's own output tell a user to type run /swarm. Either the command names make `/swarm` match swarm-dev:swarm first, or every place that tells a user what to type says the name that works (for example `/swarm-dev:swarm`). Take the smaller change that works. A rename must keep `/hld`, `/plan-hld` and `/plan-epic` reachable the same way, and update every reference in commands/, skills/, README.md, docs/ and bin/swarm.sh's printed text. README prose goes through humanizer:humanizer.

**Done when:**
- In a fresh CLAUDE_CONFIG_DIR with only this branch installed as a marketplace, typing the command the README tells a user to type and pressing Enter runs swarm-dev's swarm command; the PR quotes the transcript line (`<command-name>`) that shows it.
- The same holds for `/hld`, `/plan-hld` and `/plan-epic` as the README writes them.
- `grep` across commands/, skills/, README.md, docs/ and bin/swarm.sh finds no user-facing instruction to type a name that the check above showed resolving to another command.
- `claude plugin validate .` and every tests/*_test.sh pass.
