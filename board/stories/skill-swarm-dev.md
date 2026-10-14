---
kind: code
status: ready
epic: cold-start
depends_on: [release-agent-state]
touches: [skills/swarm-dev/SKILL.md (new), tests/skill_test.sh (new)]
---

# Ship a swarm-dev skill an agent loads when asked how to use swarm-dev, and a test that it names only real commands

New skills/swarm-dev/SKILL.md (named swarm-dev, not swarm, so it does not clash with commands/swarm.md). Front matter is name + description. The description carries the phrases 'how to use swarm-dev', 'set up a project' and 'why /swarm stopped'. The body is short: what swarm-dev is, the first-run steps (swarm.sh init, run claude once and accept the trust prompt, /hld <title>, /swarm; /swarm asks for the brief once), one line naming where /swarm stops for the user, and the commands. For detail it points at ${CLAUDE_PLUGIN_ROOT}/README.md (§ Getting started, § When /swarm stops for you) and docs/method.md and copies neither (epic:14,24). It says 'the board' (swarm.sh config board_dir), never docs/ or board/ (.claude/swarm/config:2; commands/swarm.md:5-7). Check the Claude Code plugin docs first: skill location, front matter, and whether ${CLAUDE_PLUGIN_ROOT} expands in a SKILL.md body (commands use it: commands/swarm.md:10). If it does not, use the variable the docs give for skills, and cite the docs in the PR. New tests/skill_test.sh, modelled on tests/init_test.sh (check() helper, bash 3.2, no herdr). It extracts every `swarm.sh <sub>` from SKILL.md and checks each against dispatch's arms (is_command's awk, bin/swarm.sh:2895-2898). It checks every `/<name>` against commands/<name>.md, and checks the description for the three phrases. CI globs pick the test up with no workflow edit (.github/workflows/ci.yml:23,33). README: no edit here; cold-start-swarm-first-run adds the skill to Getting started in the same release (see contradictions). Run humanizer:humanizer over SKILL.md's body and the PR description, and say so in the PR.

**Done when:**
- skills/swarm-dev/SKILL.md exists, `claude plugin validate .` passes with no skill warning, and the PR cites the plugin docs on skill location, front matter and the plugin-root variable.
- tests/skill_test.sh passes on the PR head and fails, shown in the PR, on two planted edits: a SKILL.md line naming `swarm.sh frobnicate` (or `/frobnicate`), and a description with 'why /swarm stopped' removed.
- SKILL.md body is under 60 lines, has no `docs/` or `board/` board path, and contains no paragraph copied from README.md or docs/method.md (`grep -F` of each paragraph finds nothing).
- shellcheck tests/*.sh and every tests/*_test.sh pass; the PR says humanizer ran over SKILL.md and the PR description.

**From review (binding; overrides the scope above where they differ):**
- skill_test accepts `swarm.sh <sub>` for dispatch's arms plus the arms main handles before dispatch (`version`, `update`, bin/swarm.sh:87-90).
- It checks only backticked tokens that start with `/` and contain no further `/`, against the plugin's commands plus an explicit allowlist of Claude Code built-ins (e.g. `/login`, `/clear`); paths such as `${CLAUDE_PLUGIN_ROOT}/README.md` are not commands.
- Replace the per-paragraph grep -F check: no line of 40 or more characters in SKILL.md appears verbatim (`grep -Fx`) in README.md or docs/method.md.
- This story adds README's line about the skill (Getting started), so README never names a skill that does not exist; cold-start-swarm-first-run does not.
