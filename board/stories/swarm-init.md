---
kind: code
status: ready
touches: [bin/swarm.sh (new init function, its dispatch arm and usage line), tests/init_test.sh (new), commands/swarm.md (offer init when the board is missing), README.md (Getting started step 3), docs/method.md (§ Configuring a project, one sentence), .claude-plugin/plugin.json]
---

# `swarm.sh init` sets up a project's board from the installed plugin

Getting started step 3 asks a new user to clone swarm-dev into /tmp, copy `templates/docs/` by hand
and append to `.gitignore`. The installed plugin already holds the templates (`${SWARM_HOME}/templates/docs`,
bin/swarm.sh:52), so add `swarm.sh init`, run from the project root:

- copy `${SWARM_HOME}/templates/docs/.` into the board dir (`swarm.sh config board_dir`, default `docs/`) without overwriting any file that exists (`cp -Rn`), and list what it copied and what it left;
- create `.claude/swarm/` if missing (no config file: defaults need none);
- append `.swarm/`, `<board>/.obsidian/*` and `!<board>/.obsidian/app.json` to `.gitignore`, each only if that exact line is not already there;
- refuse outside a git repo's root, naming the root;
- end by saying the one step left: run `claude` once here and accept the folder trust prompt (it does not try to set trust itself).

Running it twice changes nothing the second time. It is logged like any other writing command (not in READ_ONLY_COMMANDS).
`/swarm` (commands/swarm.md), when `<board>/stories/README.md` is missing, offers to run `swarm.sh init` and waits for the user's yes. AGENTS.md:25's "Set the project up" line is the lead's edit after this merges, pointing at the command.

**Done when:**
- In a throwaway git repo, `init` creates the board with every template file, `.claude/swarm/`, and the three `.gitignore` lines; a second run copies nothing, adds no line and says so. Shown red on the old code (no `init` arm).
- A board file the user changed is not overwritten, and the output names it as left.
- With `board_dir = board` in `.claude/swarm/config`, the files land in `board/` and the `.gitignore` lines name `board/`.
- Run from a subdirectory, or outside git, it refuses and names the reason.
- README Getting started step 3 becomes `swarm.sh init` (or `/swarm` offering it) plus the trust step; the clone-to-/tmp lines are gone; the README and PR text go through the humanizer (AGENTS.md).
- plugin.json bumped.
