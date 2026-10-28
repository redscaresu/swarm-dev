---
kind: lead
status: later
depends_on: []
touches: []
---

# Lead: cut v0.29.0, and switch on the next stage

The 0.28 HLD ships in staged releases (board/hld/2026-10-25-swarm-dev-0-28.md, Rollout § Stages). The plan PR could only add epics, so each stage's release is this lead story (stage-gating's constraints). Start it when `swarm.sh next` prints `release v0.29.0`.

1. **Docs.** List the behaviour changes since v0.28.0 (`git log v0.28.0..origin/main`). Each story updated its own docs; check README.md, AGENTS.md, docs/ and commands/ cover every change, and land a docs PR for any gap.
1b. **What the lead still does by hand** (user, 2026-10-28). docs/lead-by-hand.md (new) holds it, a file the plugin ships, so every project's lead reads it, not only swarm-dev's own (a project's agents read that project's AGENTS.md, never the plugin's; user, 2026-10-28). commands/swarm.md's read-first line names it next to docs/method.md, and AGENTS.md links to it. It lists every manual step the lead took in the v0.29.0 build that v0.29.0 does not fix, from the build's `lead-hand` and `user-caught` incident lines and .swarm/lead/retro-v029-themes.md. Each entry says what triggers it, what the lead does, and the follow-up story that removes it. Steps v0.29.0 fixes are left out. The section shrinks release by release: each later release's docs step crosses off what it fixed. The docs PR runs a read-only codex check that no entry or doc line states something false about the code.
1c. **Rules for docs/lead-by-hand.md** (user, 2026-10-28). (a) Each entry uses only commands the plugin ships (`swarm.sh`, `herdr`), never the swarm-dev lead's own `.swarm/` scripts (review-manager, lead-check, conflict-teller), which other projects do not have. (b) Each entry is: the symptom, what to check, the safe command, and its effect on swarm-dev's own counts (for example, findings sent with a raw `herdr agent prompt` skip tell's round count, so the step-up ladder never fires). It ends with `swarm.sh intervene lead-hand "<what>"`, so every use is logged for the next retro. (c) Each entry links a GitHub issue for its fix (not a board slug, which other projects cannot see). The docs step of every release deletes the entries that release fixes, and the codex check flags an entry whose fix has merged. Keep each entry to a few lines: every lead reads the file each session. Where `wait --lead` can detect a symptom, the follow-up fix is a `wait --lead` line that names the step, which also removes the entry.
2. **The release PR**, through /swarm-dev:swarm's release arm: bump only `.claude-plugin/plugin.json` to 0.29.0, list the PRs merged since v0.28.0, the behaviour changes every project gets on upgrade, and the infrafactory build they were tried on (or none). No HLD grants `release`, so the user merges it.
3. **You:** merge the release PR, then restart the lead session (`/exit`, then `claude --continue`) so it runs v0.29.0. The lead learns it is done when `swarm.sh version` prints 0.29.0.
4. **The next stage.** Once v0.29.0 is tagged, `next` prints `stage v0.30.0`: follow its arm to set that stage's draft epics active (a board PR under the HLD's `epics` grant).


**Done when:**
- A merged docs PR makes README.md, AGENTS.md, docs/ and commands/ cover every behaviour change since v0.28.0, and adds docs/lead-by-hand.md ("What the lead still does by hand"), named in commands/swarm.md's read-first line and linked from AGENTS.md, each entry following step 1c's rules: plugin commands only, symptom, check, safe command, side effects, an intervene line and a GitHub issue link.
- The tag v0.29.0 exists, `gh release view v0.29.0` shows it, and `swarm.sh version` in the lead session prints 0.29.0.
- The v0.30.0 stage's epics are active on main.
- The release notes name the behaviour changes from merge-holds: a PR that changes hooks/, .github/, a root Makefile or .claude/ holds for the user under merge = agent (protected-path-hold); a story PR whose base moved is re-checked before it merges (merge-base-moved, merge-base-update-branch, merge-base-update-wait), at the cost of one more CI run per merge after another.
