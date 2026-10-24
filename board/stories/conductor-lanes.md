---
kind: code
status: ready
depends_on: []
touches: [bin/swarm.sh:CFG defaults and CONFIG_KEYS and the conduct and unblock dispatch, bin/lib/build.sh:conductor_name and conduct_backlog_mode and the conductor brief, bin/lib/board.sh:unblock_startable, tests/conductor_lanes_test.sh (new), docs/reference.md:conduct entry and Settings]
estimate_lines: 220
easy: false
---

# An epic or the backlog can have several conductors, each owning its own stories

At 15:29 on 2026-10-24, seven green backlog PRs waited on one backlog conductor. It triages each review, sends findings and merges in turn, so review agents and builders sat idle in parallel. The user asked for several conductors doing this, as part of swarm-dev.

- Add the config key `conductor_lanes` (default 1). A value that is not a whole number of 1 or more is refused.
- With N > 1, `swarm.sh conduct <epic>|--backlog --lane <k>` (k from 1 to N) starts the conductor of lane k:
  - Its name is `conduct-<epic>-l<k>`. For the backlog it is `conductor_name backlog` with `-l<k>`, still 32 characters at most. Its report and inbox are per lane.
  - With N = 1, nothing changes: no `--lane`, and today's names.
- A story's lane: a `lane:` line in its front matter if it has one. Otherwise `cksum` of the slug mod N, plus 1. It is written to the story's board state when its build starts and never moves, even if N changes later.
- `unblock --startable <epic>|--backlog --lane <k>` prints only lane k's stories. The conductor brief tells a lane conductor to build, review and merge only its own stories. It never touches another lane's PR.
- A `tell <conduct-...> note` sent to the lane-less name goes to every lane's inbox.

**Done when:**
- tests/conductor_lanes_test.sh:
  - with `conductor_lanes = 3`, `unblock --startable --backlog --lane 2` prints exactly the ready backlog stories whose lane is 2, and the three lanes together print each ready story once;
  - a story whose build started in lane 2 stays in lane 2 after `conductor_lanes` changes to 2;
  - lane conductor names are distinct and at most 32 characters;
  - with `conductor_lanes = 1`, the names and output are unchanged.
- `make test` passes.
