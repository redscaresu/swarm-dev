# shellcheck shell=bash
# diff_fixtures_dropped_entry.sh — tests/diff_run.sh's fixtures for swarm.sh _dropped-lines, the
# dropped-lines check that merge's dropped_lines runs on a fetched PR, called with its own arguments.
# Each builds diff_fixtures_dropped.sh's project (dropped_project) and makes no gh or herdr call, so
# FX_CALLS names none. A tree with no _dropped-lines arm prints swarm.sh's help text for both, and exits
# 2: scripts/allow/stage-2/dropped-lines-entry.md names that difference. diff_run.sh sources this file,
# and every other tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

# No arguments: the usage line on stdout, and exit 2.
fx_dropped_entry_usage() { dropped_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" _dropped-lines); }
# The work repo's own branch, its head OWN: the merge of main drops `fix: true`, a line main added to
# docs/stories/s.md. That line, after the merge's SHA, and exit 1.
fx_dropped_entry_scan() { dropped_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" _dropped-lines "${ROOT}/w" main "${OWN}"); }
