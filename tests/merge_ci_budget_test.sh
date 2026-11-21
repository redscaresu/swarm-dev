#!/usr/bin/env bash
# merge_ci_budget_test.sh — swarm.sh merge's wait for CI on the base (ci_gate main) stays inside the
# GitHub API budget: its reads back off while nothing changes, and when several merges wait at once,
# an older one leaves the wait to the newest merge whose commit holds it.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'stop_test_group; chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

# --- ci_gate main on a simulated clock, with merge.sh's own poll, cap and wait, and a gh stub whose CI
# stays pending for the whole wait: it counts the stub's calls and when each read came. A second
# workflow run starts halfway through, so the read after the one that sees it comes a poll later.
read -r POLL CAP SPAN <<< "$(PROJECT_DIR="${ROOT}" bash -c 'source "$1/bin/lib/merge.sh"; echo "${MERGE_POLL} ${MERGE_POLL_MAX} ${MERGE_CI_SECONDS}"' _ "${REPO}")"
sim="$(env -u SWARM_POLL_CACHE python3 -I - "${REPO}/bin/lib" "${POLL}" "${CAP}" "${SPAN}" "${M}" <<'PY'
import json, sys, types
sys.path.insert(0, sys.argv[1])
import ci_gate as c
poll, cap, span, sha = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
clock, calls, reads, late = [0.0], [0], [], span / 2
def run(i, name, status):
    return {"id": i, "name": name, "path": ".github/workflows/%s.yml" % name, "head_sha": sha, "event": "push",
            "status": status, "conclusion": None, "html_url": "https://github.com/o/r/actions/runs/%d" % i}
def gh(*args):
    calls[0] += 1
    path = args[-1]
    if "/actions/runs?" in path:
        reads.append(clock[0])
        runs = [run(1, "ci", "in_progress")] + ([run(2, "late", "queued")] if clock[0] >= late else [])
        return json.dumps({"total_count": len(runs), "workflow_runs": runs})
    if "/check-runs?" in path:
        return json.dumps({"total_count": 0, "check_runs": []})
    if "/status?" in path:
        return json.dumps({"total_count": 0, "statuses": []})
    raise c.Err("no stub for " + path)
c.gh = gh
c.expected = lambda *a: [".github/workflows/ci.yml"]   # read once, before the polls: not counted
c.required = lambda *a: ([], "")
c.time = types.SimpleNamespace(time=lambda: clock[0], sleep=lambda t: clock.__setitem__(0, clock[0] + t))
rc, msg = c.main_ci("o/r", sha, "main", "7", 1, span, poll, 0, cap, None)
first = min(i for i, t in enumerate(reads) if t >= late)
gaps = [b - a for a, b in zip(reads, reads[1:])]
print(rc, calls[0], len(reads), "%g" % max(gaps[:first]), "%g" % gaps[first])
PY
)"
read -r sim_rc sim_calls sim_reads sim_max sim_after <<< "${sim}"
fixed=$(( 3 * (${SPAN%.*} / ${POLL%.*} + 1) ))
is "simulated wait: CI pending for ${SPAN}s ends in a timeout" 2 "${sim_rc}"
check "simulated wait: at most half the ${fixed} calls a fixed ${POLL}s poll makes over ${SPAN}s (made ${sim_calls})" \
  test "$(( sim_calls * 2 ))" -le "${fixed}"
check "simulated wait: each read is three calls, and CI was read more than twice" test "${sim_calls}" = "$(( sim_reads * 3 ))" -a "${sim_reads}" -gt 2
is "simulated wait: with nothing changing, the gap between reads grows to the cap" "${CAP}" "${sim_max}"
is "simulated wait: once a run starts, the next read comes a poll later" "${POLL}" "${sim_after}"

# --- merge hands ci_gate main its poll cap (SWARM_MERGE_POLL_MAX), and the folder of wait records for a
# story's merge only: a --board merge waits on its own commit. A python3 spy logs ci_gate main's arguments.
mkdir -p "${ROOT}/spy"
# shellcheck disable=SC2016 # expanded when the spy runs
printf '#!/bin/sh\ncase "$1 $2" in *ci_gate.py\\ main) printf "[%%s]" "$@" >> "%s"; echo >> "%s" ;; esac\nexec "%s" "$@"\n' \
  "${ROOT}/spy.log" "${ROOT}/spy.log" "$(command -v python3)" > "${ROOT}/spy/python3"
chmod +x "${ROOT}/spy/python3"
fresh; : > "${ROOT}/spy.log"; merge PATH="${ROOT}/spy:${ROOT}/bin:${PATH}" SWARM_MERGE_POLL_MAX=7 "${URL}"
is "a story merge: exits 0" 0 "${rc}"
check "a story merge: ci_gate main gets the cap and the wait records' folder" grep -qF "[7][${P}/.swarm/main-waits]" "${ROOT}/spy.log" # vacuous-test: ok, the spy's bracketed arguments, not JSON
check "a wait leaves no record behind" bash -c "[ -z \"\$(ls -A '${P}/.swarm/main-waits' 2>/dev/null)\" ]"
fresh; rm "${S}"; : > "${ROOT}/spy.log"; merge PATH="${ROOT}/spy:${ROOT}/bin:${PATH}" SWARM_MERGE_POLL_MAX=7 --board "${URL}"
is "a --board merge: exits 0" 0 "${rc}"
check "a --board merge: ci_gate main gets the cap and no wait records' folder" grep -q '\[7\]\[\]$' "${ROOT}/spy.log"

# --- Two merges' waits at once: A (${M}) merged first, B newer and holding it. A leaves the wait to
# B and exits naming it; B's red prints fix-main: once, from B's merge alone.
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; URL2=https://github.com/o/r/pull/8
fresh
checks "${FX}/${M}.checks" "$(run test in_progress)"; wfruns "${FX}/${M}.runs" "$(run ci in_progress "" "${M}")"
rm -rf "${ROOT}/fxb"; cp -R "${FX}" "${ROOT}/fxb"; echo "${B}" > "${ROOT}/fxb/oid"
checks "${ROOT}/fxb/${B}.checks" "$(run test in_progress)"; statuses "${ROOT}/fxb/${B}.status"
wfruns "${ROOT}/fxb/${B}.runs" "$(run ci in_progress "" "${B}")"
# B's compare with A says B is behind it: only A's wait may leave. A's compare with B is the stub's
# default, ahead.
echo '{"status":"behind","ahead_by":0,"behind_by":1}' > "${ROOT}/fxb/compare.${B}...${M}"
item t "status: review" "prs: ${URL2}"; item d "status: blocked" "depends_on: [s]"
racer() { # <fixtures> <url> <out>
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0.2 \
    SWARM_MERGE_POLL_MAX=0.4 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0 SWARM_MERGE_CI_SECONDS=40 SWARM_LOCK_WAIT=30 \
    STUB_FX="$1" bash "${SWARM}" merge "$2" > "$3" 2>&1) &
}
racer "${FX}" "${URL}" "${ROOT}/outa"; pa=$!; racer "${ROOT}/fxb" "${URL2}" "${ROOT}/outb"; pb=$!
for _ in $(seq 600); do kill -0 "${pa}" 2>/dev/null || break; sleep 0.1; done
ra=0; wait "${pa}" || ra=$?
# Only now does B's CI go red, so B's wait was still running when A's left it.
checks "${ROOT}/fxb/red" "$(run e2e completed failure)"; mv "${ROOT}/fxb/red" "${ROOT}/fxb/${B}.checks"
rb=0; wait "${pb}" || rb=$?
is "two waits: A's merge exits 0, its CI left to B's" 0 "${ra}"
check "two waits: A's wait exits naming B's commit and PR" grep -qxF "main-ci: covered by ${B:0:7} (PR #8)" "${ROOT}/outa"
check "two waits: A's note names d, the story it made ready, as after a green main" grep -qF "ready now: d" "${ROOT}/outa"
check "two waits: A logs main-ci covered by B" logged "^main-ci s covered by ${B:0:7} (PR #8)$"
check "two waits: A read the compare with B once" test "$(grep -c "compare/${M}...${B}" "${ROOT}/gh.log")" = 1
is "two waits: B's red merge exits 1" 1 "${rb}"
is "two waits: one fix-main: line across both merges" 1 "$(cat "${ROOT}/outa" "${ROOT}/outb" | grep -c '^fix-main:' || true)"
check "two waits: B's merge prints it, naming B's red check and commit" grep -qF "fix-main: e2e (failure) on ${B:0:7}" "${ROOT}/outb"
check "two waits: no record left behind" bash -c "[ -z \"\$(ls -A '${P}/.swarm/main-waits' 2>/dev/null)\" ]"
rm -rf "${ROOT}/fxb"

# --- A live wait on an older commit, one this merge's commit is ahead of, covers nothing: the merge
# keeps its own wait and prints its own fix-main:. The record is this test shell's, so its pid is live.
OLD=cccccccccccccccccccccccccccccccccccccccc
fresh
checks "${FX}/${M}.checks.1" "$(run test in_progress)"; checks "${FX}/${M}.checks" "$(run e2e completed failure)"
echo '{"status":"behind","ahead_by":0,"behind_by":1}' > "${FX}/compare.${M}...${OLD}"
mkdir -p "${P}/.swarm/main-waits"
printf '{"repo":"o/r","base":"main","sha":"%s","pr":"9","pid":%s,"want":[".github/workflows/ci.yml"]}\n' "${OLD}" "$$" \
  > "${P}/.swarm/main-waits/${OLD}-$$.json"
merge "${URL}"
rm -f "${P}/.swarm/main-waits/${OLD}-$$.json"
check "a live wait on an older commit: the merge reads the compare with it" grep -qF "compare/${M}...${OLD}" "${ROOT}/gh.log"
check "a live wait on an older commit: the merge keeps its wait and prints its own fix-main:" said "fix-main: e2e (failure) on ${M:0:7}"
check "a live wait on an older commit: the merge is not covered" bash -c "! grep -qF 'covered by' '${ROOT}/out'"

finish "merge CI budget"
