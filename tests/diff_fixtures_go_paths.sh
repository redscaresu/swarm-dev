# shellcheck shell=bash
# diff_fixtures_go_paths.sh — tests/diff_run.sh's fixtures for the paths only the user merges in the
# plugin's own repo (protected-go-paths, #1038): internal/guard/, internal/merge/, internal/release/,
# internal/agentenv/ and .claude-plugin/. Under merge = agent, the tree under test's swarm.sh merge on a
# story PR changing each, and swarm.sh grants on one such PR under an HLD that grants merge. Each runs on
# diff_fixtures_merge.sh's project (diff_merge_project: merge_fixture.sh's fresh, its gh, herdr and
# claude stubs, every stub answer fixed), but in the plugin's own repo: those paths are protected only
# there (plugin_repo, read from the tree's own .claude-plugin/plugin.json), and fresh names o/r.
# diff_run.sh sources this file, and every other tests/diff_fixtures_*.sh, by a glob; its header says
# what a fixture sets.
# shellcheck disable=SC2034,SC2154 # diff_run.sh reads the FX_ settings; merge_fixture.sh sets P, FX and the rest

GO_PATHS_EPOCH=1767225600   # 2026-01-01T00:00:00Z, the fixed clock of the date stub below

# go_paths_project — diff_merge_project's project (merge = agent, the stubs as gh and herdr, merge()'s
# env), with story s in review on GO_PATHS_URL, PR 7 of the plugin's own repo (the tree's plugin.json
# repository, in lower case, as plugin_repo reads it), the board's origin that repo, and a date stub
# beside the claude one, first on PATH.
go_paths_project() {
  local own
  diff_merge_project
  own="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["repository"].lower().rstrip("/").split("github.com/")[-1])' < "${TREE}/.claude-plugin/plugin.json")"
  GO_PATHS_URL="https://github.com/${own}/pull/7"
  item s "status: review" "prs: ${GO_PATHS_URL}"; echo "{\"nameWithOwner\":\"${own}\"}" > "${FX}/origin"
  # date: +%s is GO_PATHS_EPOCH, so the hold's record (protected: <url> <head> <epoch> <path>, which
  # diff_run.sh does not mask) is the same on every run; any other form is the real date's.
  printf '#!/bin/sh\n[ "$*" != +%%s ] || { echo %s; exit 0; }\nexec %s "$@"\n' "${GO_PATHS_EPOCH}" "$(command -v date)" > "${ROOT}/bin/date"
  chmod +x "${ROOT}/bin/date"
}

# go_paths_merge <path> — the PR changes story s's file and <path>, both modified, and the command is
# the tree's swarm.sh merge of it.
go_paths_merge() {
  go_paths_project
  printf '[{"filename":"docs/stories/s.md","status":"modified"},{"filename":"%s","status":"modified"}]\n' "$1" > "${FX}/files"
  echo 2 > "${FX}/nfiles"
  diff_merge "${GO_PATHS_URL}"
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
