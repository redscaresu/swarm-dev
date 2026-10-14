---
kind: docs
status: ready
epic: cold-start
depends_on: [release-agent-state, wait-reports-login-expired]
touches: [commands/swarm.md (:2 description, brief step after :16, done arm :81), README.md (§ Getting started :53-86)]
---

# /swarm starts here: asks for the brief once, explains the flow on an empty board; README Getting started matches

commands/swarm.md: the description begins 'Start here' (:2). After the init/trust paragraph (:13-16), if .claude/swarm/brief.md is missing, ask the user once, in one message, for their commit trailers, where credentials live, and commands that must never run. Write only what they said, under BRIEF_MAX_BYTES (bin/swarm.sh:665). If they decline, write an empty file, so they are not asked again. Do not commit it; tell them to commit it, because an untracked brief blocks pulling a later lesson PR (lessons_file defaults to the brief: commands/swarm.md:46, docs/method.md:130). Nothing writes the brief today (survey; bin/swarm.sh:195,1235). In the `done` arm (:81): `next` prints the same done for an empty board and a finished one (bin/swarm.sh:1454-1460,1564). So when <board>/hld, epics and stories hold no file but README.md, explain the flow in about five lines (design, epics, stories, builds, where it stops for the user) and suggest /hld <title>; a finished board keeps today's line. No bin/swarm.sh change. README § Getting started (README:53-86): step 4 says /swarm asks for the brief once; the trailing brief paragraph (:79) is folded into it; add one line: ask your agent 'how do I use swarm-dev?' and it loads the swarm-dev skill. Leave § When /swarm stops for you (:88) to the agent-state stories. Projects with no brief, this repo included (.claude/swarm/ holds only config), get asked once after upgrading; that is intended. Run humanizer:humanizer over the changed swarm.md prose, README and the PR description, and say so in the PR.

Also touches docs/method.md (see below).

**Done when:**
- `sed -n 2p commands/swarm.md` begins `description: Start here`.
- commands/swarm.md names .claude/swarm/brief.md, the three questions, the empty-file decline, and 'not committed'; it has the empty-board branch in the `done` arm, with the five-line flow and /hld <title>.
- README § Getting started names `swarm.sh init`, the trust prompt, `/hld`, `/swarm`, the brief question and the skill, and README has no other paragraph about brief.md outside § Getting started and § How it works.
- The PR's diff touches no line edited by tell-watch-and-free-name-read-the-session or wait-reports-login-expired: it is rebased on main after both merged.
- Every tests/*_test.sh and `claude plugin validate .` pass; the PR says humanizer ran.

**From review (binding; overrides the scope above where they differ):**
- An empty board means no `*.md` other than README.md under <board>/hld, epics and stories, the rule board() uses (bin/swarm.sh:1454-1459); `HLDs.base` and other non-Markdown files do not count. Done when adds: in a scratch repo, on a board made by `swarm.sh init`, the condition as written in commands/swarm.md holds, and it stops holding once one HLD `.md` is added; the PR shows the commands.
- docs/method.md changes in this PR: its /swarm summary (:17-22) mentions the empty-board explanation, and § Configuring a project (:110-114) says the next /swarm asks once for the brief, invents nothing, and that an empty file means declined. It goes through the humanizer with the rest.
- The brief step tells the user to commit `.claude/swarm/brief.md` (even empty), and says why: an untracked brief stops reconcile's pull once a `lesson:` PR adds the file.
- README's skill line belongs to skill-swarm-dev, not this story.
