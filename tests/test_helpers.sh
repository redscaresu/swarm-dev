# shellcheck shell=bash
# test_helpers.sh — the prelude every tests/*_test.sh sources first, right after set -euo pipefail:
#
#   # shellcheck source=tests/test_helpers.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
#
# A test run on its own from a herdr pane (bash tests/<file>) inherits the pane's environment, which
# names the lead's real project: SWARM_PROJECT, which swarm.sh takes before the directory a test cd's
# into, the other SWARM_* settings, and HERDR_SOCKET_PATH, the real herdr. events_test.sh once logged
# its fixtures into the real .swarm/findings.tsv and events.tsv that way. So this drops every SWARM_*
# but the two make test sets (SWARM_SLEEP_SCALE, defaulted here as there, and SWARM_NO_CI_REFRESH) and
# HERDR_SOCKET_PATH. It does not change directory: a test names its files from BASH_SOURCE, which a
# direct run gives as a relative path. Each project a test makes is pinned by a cd into it, or by
# SWARM_PROJECT on the call; make test runs every file from its TMPDIR, outside any git repo, where a
# call left unpinned stops at "not in a swarm project", so no green test has one.
# tests/live_logs_test.sh checks that every test sources this first.
for v in $(compgen -e); do case ${v} in SWARM_SLEEP_SCALE|SWARM_NO_CI_REFRESH) ;; SWARM_*) unset "${v}" ;; esac; done
unset HERDR_SOCKET_PATH
export SWARM_SLEEP_SCALE="${SWARM_SLEEP_SCALE:-0.01}"
