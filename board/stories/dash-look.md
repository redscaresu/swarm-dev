---
kind: code
status: ready
touches: [bin/swarm.sh (dash_render and its DASH python only), tests/dash_test.sh, scripts/demo-dash.sh, docs/dash.md, docs/assets/dash.gif, README.md (the dash screenshot line)]
---

# A prettier `swarm.sh dash`: two columns, a colour per model, agent cards and a status bar

The user wants `dash` to look like a terminal UI they saw on X (2026-10-13): boxed panels side by
side, each agent a small card with a coloured model label, a timestamped log on the right, and a status
bar at the bottom. The lead has a still of it at
`/private/tmp/claude-501/-Users-ehsanashouri-go-src-github-com-redscaresu-infrafactory/93fa4cb0-f9f9-4283-882d-3e1a4917df18/scratchpad/dash-reference.jpg`
(open it with the Read tool); take the look from it, not its content. Today's dash (docs/dash.md) is one
column of boxes where every model looks the same.

- **Two columns** when the terminal is at least 140 columns wide: needs-you and epics on the left, recent
  as a timestamped log (`HH:MM`) on the right. Narrower terminals keep today's single column, unchanged.
- **A colour per model**, the same everywhere it appears: Fable, Opus, Sonnet, Haiku and codex each get one
  (256-colour ANSI), shown as a short label (e.g. ` opus·xhigh `) on the agent's line. `NO_COLOR` set, or
  output not a terminal, prints no escape codes at all.
- **Agent cards**: a working agent's line under its epic shows role, the model label, elapsed time since it
  started, and its state; a stalled one keeps today's `!`.
- **A status bar** on the last line: merge mode, today's cost, the counts already in the summary line, and
  the keys (`q r t l`).
- Everything else stays: the same data, the same sections, `--tree`, `l`, redraw-only-on-change.

Use only what dash uses today (bash 3.2, python3, plain ANSI). No new dependency.

**Done when:**
- dash_test's existing checks pass unchanged at 100 columns (single column), and new checks cover: at 160 columns the epics and the recent log sit side by side (the same row holds both); each model's label carries its own colour code; with `NO_COLOR=1`, or piped, the output holds no `\033[`; the status bar is the last line and names the keys.
- A width between 140 and 160 never wraps a line (every line is at most the terminal width), shown red on a version that does not truncate.
- scripts/demo-dash.sh renders the new look; docs/assets/dash.gif is re-recorded from it; docs/dash.md describes the two columns, the colours and `NO_COLOR`.
- README and the PR description go through the humanizer (AGENTS.md). No plugin.json bump: it ships in the next release story.
