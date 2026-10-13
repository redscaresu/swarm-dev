---
kind: verify
status: ready
epic: agent-state-from-the-session
depends_on: []
touches: [board/hld/2026-10-13-builders-use-claude-codes-goal-advisor-and-agent-view.md (§ Open questions)]
---

# Find the first Claude Code release with `--session-id` and interactive sessions in `claude agents --json`

Bisect the released versions with `npx --yes @anthropic-ai/claude-code@<v>`, as CI already does (.github/workflows/ci.yml:44). Never install globally. Never point an older build at the user's config: CLAUDE_CONFIG_DIR is always a throwaway dir. For each version, check three things: `--help` lists `--session-id`; `agents --json` exists; and `agents --json` lists an interactive session of the same version started with `--session-id <uuid>` (run under a pty in the background, e.g. `script -q /dev/null ...`, and killed afterwards) with a `status`. If a check needs a logged-in session or an installed build, stop and reply naming the versions and the commands. That step is the lead story older-claude-builds. Write the answer into the HLD's open question (board/hld/2026-10-13-builders-use-claude-codes-goal-advisor-and-agent-view.md:438-439): the version V, the exact `--version` output format, and one line of evidence per version checked. No code.

**Done when:** The HLD's open question names V and shows that V passes all three checks and the release before V fails one, or that V is the first release with `claude agents`. Each version's line gives the exact command and output. When the conductor re-runs V's three checks, they pass.

**From review (binding; overrides the scope above where they differ):**
- If you can, capture one real `claude agents --json` entry in a waiting state (a permission or dialog prompt) and record its `waitingFor` key and value type in the HLD's open question, ids and paths replaced; the reader stories rely on it.
