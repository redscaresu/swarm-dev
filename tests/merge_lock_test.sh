#!/usr/bin/env bash
# merge_lock_test.sh — a direct swarm.sh merge (no merge queue) holds the project's lock on its repo's
# base, .swarm/merge-<owner>-<repo>-<base>.lock, from the base check through gh pr merge and its read
# back, so two review agents that pass at once cannot both merge past one base check. A merge finding
# the lock held by a live swarm.sh waits SWARM_MERGE_LOCK_WAIT seconds, then refuses naming its pid and
# merges nothing; a lock whose pid is gone is taken over; a refusal after the lock is taken frees it.
# On merge_fixture.sh, whose gh stub runs ${FX}/on-merge during gh pr merge.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
live=""
trap '[[ -z "${live}" ]] || kill "${live}" 2>/dev/null || true; chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

LOCK="${P}/.swarm/merge-o-r-main.lock"
# held_by <pid> — the lock as a merge that is <pid> left it.
held_by() { mkdir -p "${LOCK}"; echo "$1" > "${LOCK}/pid"; }

# --- Another merge into o/r's main is running: this one waits, then refuses, and its lock stays.
fresh; sleep 60 & live=$!
held_by "${live}"
merge SWARM_MERGE_LOCK_WAIT=1 --head "${H1}" "${URL}"
refused "a lock held by a live swarm.sh" "another swarm.sh merge into main of o/r has held ${LOCK} (pid ${live}) for 1s; nothing was merged"
is "the live merge's lock is left as it was" "${live}" "$(cat "${LOCK}/pid" 2>/dev/null)"
kill "${live}" 2>/dev/null || true; wait "${live}" 2>/dev/null || true; live=""

# --- A merge that died holding it: its lock is taken over, held through gh pr merge, and freed.
( exit 0 ) & dead=$!; wait "${dead}" || true
fresh; held_by "${dead}"
echo "test -d '${LOCK}' && touch '${FX}/locked'" > "${FX}/on-merge"
merge --head "${H1}" "${URL}"
is "a dead holder's lock: merges" 0 "${rc}"
check "a dead holder's lock: gh pr merge ran" merged
check "the lock is held while gh pr merge runs" test -e "${FX}/locked"
check "and freed once the merge read back" test ! -e "${LOCK}"

# --- A refusal after the lock is taken (the base gained code the head's CI never ran with) frees it.
fresh; echo '{"ahead_by":1,"files":[{"filename":"bin/x.sh","status":"modified"}]}' > "${FX}/behind"
merge --head "${H1}" "${URL}"
is "a base check that refuses: exits non-zero" 1 "${rc}"
check "a base check that refuses: no pr merge" not_merged
check "and leaves no lock behind" test ! -e "${LOCK}"

finish merge_lock
