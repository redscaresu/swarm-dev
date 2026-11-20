# shellcheck shell=bash
# diff_fixtures_hooks.sh — tests/diff_run.sh's fixtures for the four hooks hooks/hooks.json runs, each
# run as hooks.json's command runs it ("${CLAUDE_PLUGIN_ROOT}/hooks/<hook>", which diff_run.sh sets to
# the tree) and fed its hook JSON on stdin: merge-guard.sh refusing a raw PR merge and passing `ls`,
# lead-stop.sh on a Stop with next naming a step and with none, agent-state.sh working and idle, and
# user-caught-reminder.sh in the lead's session and in an agent's. diff_run.sh sources this file by a
# glob; its header says what a fixture sets.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

# hook_project — a swarm project at ${ROOT}/proj: a git repo with an empty .claude/swarm/config, a
# board (docs/stories, docs/epics) and a .swarm/, the command's cwd there.
hook_project() {
  mkdir -p "${ROOT}/proj/.claude/swarm" "${ROOT}/proj/.swarm" "${ROOT}/proj/docs/stories" "${ROOT}/proj/docs/epics"
  git -C "${ROOT}/proj" init -q
  : > "${ROOT}/proj/.claude/swarm/config"
  FX_CWD="${ROOT}/proj"
}

# hook_run <hook> <json> [arg] — run hooks/<hook> as hooks.json does, <json> its stdin.
hook_run() {
  printf '%s\n' "$2" > "${ROOT}/hook.json"
  FX_STDIN="${ROOT}/hook.json"
  FX_CMD=(sh -c "\"\${CLAUDE_PLUGIN_ROOT}/hooks/$1\"${3:+ $3}")
}

# hook_bash <command> — a PreToolUse hook's JSON for a Bash call of <command> from the project.
hook_bash() {
  python3 -I -c 'import json, sys; print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
    "session_id": "sess-1", "cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "${ROOT}/proj" "$1"
}

# hook_event <event> — a hook's JSON for <event> in session sess-1 from the project.
hook_event() {
  python3 -I -c 'import json, sys; print(json.dumps({"hook_event_name": sys.argv[1], "session_id": "sess-1",
    "cwd": sys.argv[2], "stop_hook_active": False, "prompt": "go on"}))' "$1" "${ROOT}/proj"
}

# merge-guard.sh refuses a raw merge (exit 2, and an incident line in .swarm/events.tsv); `ls` takes
# its fast path. Neither calls gh or herdr.
fx_hook_guard_merge() { hook_project; hook_run merge-guard.sh "$(hook_bash 'gh pr merge 7 --squash')"; }
fx_hook_guard_ls() { hook_project; hook_run merge-guard.sh "$(hook_bash ls)"; }

# hook_lead — the lead's pane in herdr, whose agent list (swarm.sh _step's, and lead-stop.sh's own
# when the step may have started) has no agent. SWARM_SLEEP_SCALE=1 gives lead-stop its own 45 s
# deadline: make test's 0.01 cuts it to 1 s, which a slow machine's _step outruns, and the hook then
# allows with no step and no herdr call.
hook_lead() {
  hook_project
  printf '#!/bin/sh\necho %s\n' "'{\"result\": {\"agents\": []}}'" > "${ROOT}/herdr-stub"; chmod +x "${ROOT}/herdr-stub"
  FX_HERDR="${ROOT}/herdr-stub"; FX_ENV=(HERDR_ENV=1 SWARM_SLEEP_SCALE=1); FX_CALLS=("herdr agent list")
}

# lead-stop.sh on a Stop. With a ready story and no agent running it, next's step has not started, so
# it blocks; on an empty board next names no step (done), so it allows.
fx_hook_stop_step() {
  hook_lead
  printf -- '---\nkind: code\nstatus: ready\n---\n\n# A story\n' > "${ROOT}/proj/docs/stories/a-story.md"
  hook_run lead-stop.sh "$(hook_event Stop)"
}
fx_hook_stop_none() { hook_lead; hook_run lead-stop.sh "$(hook_event Stop)"; }

# agent-state.sh in a builder's pane: the pane's own session (its SWARM_RESUME argv's --resume names
# the hook's session_id) reports its state to herdr, in the background.
hook_agent() {
  hook_project
  printf 'claude\n--resume\nsess-1\n' > "${ROOT}/resume.argv"
  printf '#!/bin/sh\nexit 0\n' > "${ROOT}/herdr-stub"; chmod +x "${ROOT}/herdr-stub"
  FX_HERDR="${ROOT}/herdr-stub"; FX_CALLS=("herdr pane report-agent")
  FX_ENV=(SWARM_AGENT=builder-a-story HERDR_PANE_ID=w1:p1 "SWARM_RESUME=${ROOT}/resume.argv")
}
fx_hook_state_working() { hook_agent; hook_run agent-state.sh "$(hook_event UserPromptSubmit)" working; }
fx_hook_state_idle() { hook_agent; hook_run agent-state.sh "$(hook_event Stop)" idle; }

# user-caught-reminder.sh prints its line in the lead's session and nothing in an agent's.
fx_hook_caught_lead() { hook_project; hook_run user-caught-reminder.sh "$(hook_event UserPromptSubmit)"; }
fx_hook_caught_agent() { hook_project; FX_ENV=(SWARM_AGENT=builder-a-story); hook_run user-caught-reminder.sh "$(hook_event UserPromptSubmit)"; }
