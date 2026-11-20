# shellcheck shell=bash
# diff_fixtures_go_paths.sh — tests/diff_run.sh's fixtures for the paths only the user merges in the
# plugin's own repo (protected-go-paths, #1038): internal/guard/, internal/merge/, internal/release/,
# internal/agentenv/ and .claude-plugin/. Under merge = agent, the tree under test's swarm.sh merge on a
# story PR changing each, and swarm.sh grants on one such PR under an HLD that grants merge. Each runs on
# the project merge_fixture.sh builds (fresh, its gh, herdr and claude stubs), with every stub answer
# fixed, but in the plugin's own repo: those paths are protected only there (plugin_repo, read from the
# tree's own .claude-plugin/plugin.json), and fresh names o/r. diff_run.sh sources this file, and every
# other tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
# shellcheck disable=SC2034,SC2154 # diff_run.sh reads the FX_ settings; merge_fixture.sh sets P, FX and the rest

GO_PATHS_MERGE_FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/merge_fixture.sh"
GO_PATHS_EPOCH=1767225600   # 2026-01-01T00:00:00Z, the fixed clock of the date stub below

# go_paths_project — merge_fixture.sh's project under ${ROOT}, fresh (merge = agent), with story s in
# review on GO_PATHS_URL, PR 7 of the plugin's own repo (the tree's plugin.json repository, in lower
# case, as plugin_repo reads it), and the board's origin that repo. The command runs in the project,
# with the stubs as gh and herdr, the claude and date stubs first on PATH, and merge_fixture.sh's
# merge() env (SWARM_MERGE_POLL=0 and the zero waits), so no poll count follows the clock.
go_paths_project() {
  local own
  export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
  # shellcheck source=tests/merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
  . "${GO_PATHS_MERGE_FIXTURE}"
  own="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["repository"].lower().rstrip("/").split("github.com/")[-1])' < "${TREE}/.claude-plugin/plugin.json")"
  GO_PATHS_URL="https://github.com/${own}/pull/7"
  fresh; item s "status: review" "prs: ${GO_PATHS_URL}"; echo "{\"nameWithOwner\":\"${own}\"}" > "${FX}/origin"
  # date: +%s is GO_PATHS_EPOCH, so the hold's record (protected: <url> <head> <epoch> <path>, which
  # diff_run.sh does not mask) is the same on every run; any other form is the real date's.
  printf '#!/bin/sh\n[ "$*" != +%%s ] || { echo %s; exit 0; }\nexec %s "$@"\n' "${GO_PATHS_EPOCH}" "$(command -v date)" > "${ROOT}/bin/date"
  chmod +x "${ROOT}/bin/date"
  FX_CWD="${P}"; FX_GH="${ROOT}/bin/gh"; FX_HERDR="${ROOT}/bin/herdr"
  FX_ENV=("PATH=${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0
    SWARM_MERGE_CI_SECONDS=60 SWARM_RELEASE_WAIT=0 "GIT_CONFIG_COUNT=${GIT_CONFIG_COUNT}"
    "GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0}" "GIT_CONFIG_VALUE_0=${GIT_CONFIG_VALUE_0}"
    "GIT_CONFIG_KEY_1=${GIT_CONFIG_KEY_1}" "GIT_CONFIG_VALUE_1=${GIT_CONFIG_VALUE_1}")
}

# go_paths_merge <path> — the PR changes story s's file and <path>, both modified, and the command is
# the tree's swarm.sh merge of it.
go_paths_merge() {
  go_paths_project
  printf '[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"%s","status":"modified"}]\n' "$1" > "${FX}/files"
  echo 2 > "${FX}/nfiles"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" merge "${GO_PATHS_URL}")
}

# Before #1038 each merges; from it, each is held for the user, with a held: line and a merge event.
fx_go_paths_guard() { go_paths_merge internal/guard/x.go; }
fx_go_paths_merge() { go_paths_merge internal/merge/x.go; }
fx_go_paths_release() { go_paths_merge internal/release/x.go; }
fx_go_paths_agentenv() { go_paths_merge internal/agentenv/x.go; }
fx_go_paths_plugin() { go_paths_merge .claude-plugin/marketplace.json; }

# swarm.sh grants on the PR changing internal/merge/x.go, with story s under epic e, whose agreed HLD
# grants merge: before #1038 it prints that HLD and merge; from it, none.
fx_go_paths_grants() {
  go_paths_merge internal/merge/x.go
  mkdir -p "${P}/docs/hld" "${P}/docs/epics"
  printf -- '---\ntitle: A\nstatus: agreed\ngrants: [merge]\n---\n\n# A\n' > "${P}/docs/hld/2026-01-01-a.md"
  printf -- '---\nstatus: active\nhld: 2026-01-01-a\n---\n\n# e\n' > "${P}/docs/epics/e.md"
  item s "status: review" "epic: e" "prs: ${GO_PATHS_URL}"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" grants "${GO_PATHS_URL}")
}
