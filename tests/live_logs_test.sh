#!/usr/bin/env bash
# live_logs_test.sh — no test writes a project's live .swarm, run from make, a pane or a story
# worktree. Every tests/*_test.sh sources tests/test_helpers.sh as its first command after set -euo
# pipefail: it drops the pane's SWARM_* and HERDR_SOCKET_PATH, which name the lead's real project and
# herdr. make test runs each file from its TMPDIR with SWARM_PROJECT naming a stand-in project of
# the job's own, as a pane's names the real one, and fails a file whose swarm.sh reaches it: every
# file is checked on every run. Both name the checkout the tests run from in SWARM_FORBID_PROJECT,
# which swarm.sh refuses to act on, named directly or through a worktree of it: such a call stops
# before it writes, under make test and run on its own. And events_test.sh, whose fixtures once landed in the
# real findings.tsv and events.tsv, run under make test from a copy of this repo, leaves the copy's
# findings.tsv, events.tsv and .swarm/lead/pid (which wait_lead_test.sh's wait --lead once took on
# the real checkout) as they were. So do the two hooks that write events.tsv themselves
# (hooks/merge-guard.sh, hooks/lead-stop.sh), run from a worktree of the copy with the prelude. A copy,
# not the main checkout: a conductor appends to the real logs while the suite runs, and a failing guard
# would itself write fixtures into the log it guards.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# Every test file's first command after set -euo pipefail is the source line; a comment is not a command.
# shellcheck disable=SC2016 # the line as the files hold it
SRC='source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"'
unsourced=""
for t in "${REPO}"/tests/*_test.sh; do
  first="$(awk '/^set -euo pipefail$/ { s = 1; next } s && !/^[[:space:]]*(#|$)/ { print; exit }' "${t}")"
  [[ "${first}" == "${SRC}" ]] || unsourced+="${t##*/} "
done
check "every tests/*_test.sh sources tests/test_helpers.sh as its first command after set -euo pipefail" "${unsourced}" ""

# The runner's check, on a fixture that runs swarm.sh log-finding: with the prelude and a cd into a
# project of its own, it passes and the finding lands there; without the prelude, the pane's
# SWARM_PROJECT wins over its cd, the finding lands in the stand-in, and the file fails naming it;
# with the prelude and no cd, the call stops: the runner's TMPDIR is in no project.
FX="${ROOT}/fx"; mkdir -p "${FX}/proj/.claude/swarm"; : > "${FX}/proj/.claude/swarm/config"
fixture() { # <name> <prelude: yes|no> <cd: yes|no>
  { echo '#!/usr/bin/env bash'; echo 'set -euo pipefail'
    [[ "$2" == no ]] || echo "source \"${REPO}/tests/test_helpers.sh\""
    [[ "$3" == no ]] || echo "cd \"${FX}/proj\" || exit 1"
    echo "env -u HERDR_ENV bash \"${REPO}/bin/swarm.sh\" log-finding vacuous-test https://github.com/o/r/pull/9 'a line'"
  } > "${FX}/$1_test.sh"
}
fixture without no yes; fixture with yes yes; fixture unpinned yes no
runner() { (cd "${REPO}" && TEST_RUNS_LOG="" JOBS=1 bash scripts/test.sh "$@" 2>&1) || true; }
o="$(runner "${FX}/without_test.sh")"
check "without the prelude, the file fails: the summary line, the runner's reason, and the finding it left in the stand-in" \
  "$(grep -cE "^FAIL .*/without_test\.sh [0-9]+s$|ran swarm\.sh against the pane's SWARM_PROJECT|^\./\.swarm/findings\.tsv$" <<< "${o}")" "3"
check "and nothing reached the project it cd'd into" "$(ls -A "${FX}/proj/.swarm" 2>/dev/null)" ""
o="$(runner "${FX}/with_test.sh")"
check "with the prelude, the file passes" "$(grep -cE "^ok   .*/with_test\.sh [0-9]+s$" <<< "${o}")" "1"
check "and its finding landed in the project it cd'd into" "$(wc -l < "${FX}/proj/.swarm/findings.tsv" | tr -d ' ')" "1"
o="$(runner "${FX}/unpinned_test.sh")"
check "with the prelude and no cd, an unpinned call stops at not in a swarm project under the runner" "$(grep -c 'not in a swarm project' <<< "${o}")" "1"

# The copy: this repo but its .git and .swarm, a git repo and a swarm project of its own (its
# .claude/swarm/config comes along, as in the real one), with a findings.tsv and an events.tsv of one
# line and a lead/pid no process holds.
# Never the live .swarm, written and pruned while the suite runs, nor .git; a commit, so the copy can have a worktree.
COPY="${ROOT}/repo"; mkdir -p "${COPY}"
rsync -a --exclude .git --exclude .swarm "${REPO}/" "${COPY}/"; git -C "${COPY}" init -q
git -C "${COPY}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "${COPY}/.swarm/lead"
printf '2026-10-25\tseed\thttps://github.com/o/r/pull/1\ta line\tfixed\tlead\n' > "${COPY}/.swarm/findings.tsv"
printf '2026-10-25T00:00:00Z\tseed\t-\tw:0\tok\n' > "${COPY}/.swarm/events.tsv"
echo 99999999 > "${COPY}/.swarm/lead/pid"
lines() { wc -l < "$1" | tr -d ' '; }
state() { echo "findings $(lines "${COPY}/.swarm/findings.tsv")|events $(lines "${COPY}/.swarm/events.tsv")|lead/pid $(cat "${COPY}/.swarm/lead/pid" 2>&1)"; }
rc=0; (cd "${COPY}" && make -s test TESTS=tests/events_test.sh JOBS=1 > "${ROOT}/make.out" 2>&1) || rc=$?
check "make test TESTS=tests/events_test.sh passes in the copy" "exit ${rc}" "exit 0"
# A test that names the copy itself, with the prelude: through the copy's runner and run on its own, as
# from a pane. swarm.sh refuses the project both times, and the copy's logs stay as seeded.
{ echo '#!/usr/bin/env bash'; echo 'set -euo pipefail'; echo "source \"${COPY}/tests/test_helpers.sh\""
  echo "cd \"${COPY}\" || exit 1"; echo "env -u HERDR_ENV bash \"${COPY}/bin/swarm.sh\" log-finding vacuous-test https://github.com/o/r/pull/9 'a line'"; } > "${FX}/checkout_test.sh"
o="$(cd "${COPY}" && TEST_RUNS_LOG="" JOBS=1 bash scripts/test.sh "${FX}/checkout_test.sh" 2>&1 || true)"
check "under the runner, a test that cd's into the checkout fails: swarm.sh refuses SWARM_FORBID_PROJECT" \
  "$(grep -cE "^FAIL .*/checkout_test\.sh [0-9]+s$|^swarm: SWARM_FORBID_PROJECT: " <<< "${o}")" "2"
o="$(cd "${COPY}" && bash "${FX}/checkout_test.sh" 2>&1)" && drc=0 || drc=$?   # its own status: rc is the copy's make test
check "run on its own, the prelude names the checkout and swarm.sh refuses it" "exit ${drc}|$(grep -c "^swarm: SWARM_FORBID_PROJECT: " <<< "${o}")" "exit 1|1"
# A worktree of the copy, named in SWARM_PROJECT: find_project takes that path as given, so swarm.sh
# compares its main checkout too and refuses it; the worktree's .swarm gains nothing.
git -C "${COPY}" worktree add -q -b wt "${ROOT}/wt"
{ echo '#!/usr/bin/env bash'; echo 'set -euo pipefail'; echo "source \"${COPY}/tests/test_helpers.sh\""
  echo "SWARM_PROJECT=\"${ROOT}/wt\" env -u HERDR_ENV bash \"${COPY}/bin/swarm.sh\" log-finding vacuous-test https://github.com/o/r/pull/9 'a line'"; } > "${FX}/worktree_test.sh"
o="$(cd "${COPY}" && TEST_RUNS_LOG="" JOBS=1 bash scripts/test.sh "${FX}/worktree_test.sh" 2>&1 || true)"
check "a test naming a worktree of the checkout in SWARM_PROJECT fails: swarm.sh refuses it through its main checkout" \
  "$(grep -cE "^FAIL .*/worktree_test\.sh [0-9]+s$|^swarm: SWARM_FORBID_PROJECT: " <<< "${o}")" "2"
check "and the worktree's .swarm gained nothing" "$(ls -A "${ROOT}/wt/.swarm" 2>/dev/null)" ""
# The hooks, run as a test in that worktree would run them: merge-guard.sh on a raw merge from the
# worktree, which it logs to the main checkout, and lead-stop.sh on a Stop naming the main checkout,
# where swarm.sh refuses next and the hook allows the stop. Both skip the copy, which the prelude names
# in SWARM_FORBID_PROJECT, so the guard still blocks and the copy's events.tsv gains no line.
cat > "${FX}/hooks_test.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
source "$1/tests/test_helpers.sh"
rc=0; printf '{"cwd": "%s", "tool_input": {"command": "gh pr merge 7"}}' "${PWD}" | bash "$1/hooks/merge-guard.sh" 2>/dev/null || rc=$?
echo "merge-guard exit ${rc}"
rc=0; out="$(printf '{"hook_event_name": "Stop", "cwd": "%s"}' "$1" | bash "$1/hooks/lead-stop.sh")" || rc=$?
echo "lead-stop exit ${rc}${out:+: ${out}}"
FIXTURE
o="$(cd "${ROOT}/wt" && bash "${FX}/hooks_test.sh" "${COPY}" 2>&1)" || true
check "from a worktree of the copy, under the prelude, the guard blocks a raw merge and lead-stop allows the stop" \
  "${o}" $'merge-guard exit 2\nlead-stop exit 0'
check "and neither hook added a line to the copy's events.tsv" "$(lines "${COPY}/.swarm/events.tsv")" 1
check "the copy's .swarm/findings.tsv and events.tsv gained no line, and its lead/pid is as it was" "$(state)" "findings 1|events 1|lead/pid 99999999"
[[ ${rc} -eq 0 ]] || { echo "---- make test in the copy: each file's line, then its first FAIL lines"; grep -E "^(ok|FAIL|TIMEOUT) +tests/" "${ROOT}/make.out"; grep "^FAIL" "${ROOT}/make.out" | grep -v " tests/" | head -n 10 || tail -n 20 "${ROOT}/make.out"; }
[[ "$(state)" == "findings 1|events 1|lead/pid 99999999" ]] \
  || { echo "---- what the copy's logs gained"; tail -n +2 "${COPY}/.swarm/findings.tsv"; tail -n +2 "${COPY}/.swarm/events.tsv" | head -n 20; }

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
