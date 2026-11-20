#!/usr/bin/env bash
# diff_run_hooks_test.sh — tests/diff_run.sh, the differential run, on the hook fixtures of
# tests/diff_fixtures_hooks.sh: merge-guard.sh, lead-stop.sh, agent-state.sh and
# user-caught-reminder.sh, each fed its hook JSON on stdin. (1) Two copies of this tree compare clean
# on every hook fixture, and so do v0.31.2's tree and v0.31.3's (neither changed hooks/), each fixture
# making its named calls, and each copy's streams are what the hook does: merge-guard's refusal exits 2
# with its incident line, lead-stop blocks on a step and allows on none, agent-state reports to herdr
# with its --seq masked, the reminder prints in the lead's session alone. (2) With copy b changed, the
# run is red, naming the fixture and stream, for merge-guard's exit code, one byte of lead-stop's
# stdout, one byte of merge-guard's event line, one extra herdr call from agent-state, one byte of
# agent-state's herdr argv outside --seq and a --seq of another shape. (3) The caller's
# SWARM_FORBID_PROJECT, which make test exports, leaves merge-guard's event line in both trees, and b
# dropping it is red. (4) An agent-state fixture with its SWARM_RESUME file removed is red in both
# trees by its missing herdr call (MISSING), though the trees agree.
# shellcheck disable=SC2016 # the mutations are hook code, expanded when that copy runs it
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
# A diff_run.sh still running gets a TERM and is waited on first: its own EXIT trap kills the fixture
# commands' groups, which stop_test_group, holding only this test's group, never reaches.
DR_PID=""
trap '[[ -z "${DR_PID}" ]] || { kill -TERM "${DR_PID}" 2>/dev/null; wait "${DR_PID}" 2>/dev/null; }; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"; mkdir -p "${HOME}"
# make test exports it, naming the checkout the tests run from; by hand, name this one.
export SWARM_FORBID_PROJECT="${SWARM_FORBID_PROJECT:-${REPO}}"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; sed 's/^/  | /' "${ROOT}/out"; fails=$((fails + 1)); }

HOOKS=(hook_guard_merge hook_guard_ls hook_stop_step hook_stop_none hook_state_working hook_state_idle hook_caught_lead hook_caught_agent)
COPY=(bin hooks templates .claude-plugin)

# Two copies at paths of different lengths, of what the fixtures run and the harness with its fixtures.
A="${ROOT}/a" B="${ROOT}/copies/b"
for t in "${A}" "${B}"; do
  mkdir -p "${t}/tests"
  (cd "${REPO}" && tar -cf - "${COPY[@]}" tests/diff_run.sh tests/diff_fixtures_*.sh) | tar -C "${t}" -xf -
done

# run <rc> [diff_run args...] — run a's diff_run.sh, its output in ${ROOT}/out, and check its exit.
run() {
  local want="$1" rc=0; shift
  bash "${A}/tests/diff_run.sh" "$@" > "${ROOT}/out" 2>&1 &
  DR_PID=$!; wait "${DR_PID}" || rc=$?; DR_PID=""
  [[ ${rc} == "${want}" ]] || { echo "exit ${rc}, not ${want}"; return 1; }
}
# diffs — the DIFF lines of the last run, one per line, sorted.
diffs() { sed -n 's/^DIFF //p' "${ROOT}/out" | LC_ALL=C sort | tr '\n' ';'; }

mutated=()
mutate() { # <tree> <file> <old> <new>: an <old> the file lacks fails the test
  grep -qF -- "$3" "$1/$2" || { echo "FAIL mutate: no '$3' in $2"; exit 1; }
  [[ -e "$1/$2.orig" ]] || { cp -p "$1/$2" "$1/$2.orig"; mutated+=("$1/$2"); }
  DR_OLD="$3" DR_NEW="$4" perl -pi -e 's/\Q$ENV{DR_OLD}\E/$ENV{DR_NEW}/' "$1/$2"
}
restore() { local f; for f in ${mutated[@]+"${mutated[@]}"}; do mv "${f}.orig" "${f}"; done; mutated=(); }

# expect <name> <fixture> <DIFF streams, ;-separated and sorted> — b as mutated is red on exactly
# those streams of <fixture>; then b is restored.
expect() {
  local got
  if ! run 1 "${A}" "${B}" "$2" > "${ROOT}/why"; then bad "$1" "$(cat "${ROOT}/why")"
  elif got="$(diffs)" && [[ "${got}" != "$3" ]]; then bad "$1" "DIFF lines '${got}', not '$3'"
  else ok "$1"; fi
  restore
}

# kept <fixture> <stream> — that stream as the last kept run compared it, on side SIDE, under KD.
kept() { cat "${KD}/$1/${SIDE}/$2"; }
# kept_has <fixture> <stream> <line> — that stream holds <line>, whole.
kept_has() { grep -qxF -- "$3" "${KD}/$1/${SIDE}/$2"; }
# kept_calls <fixture> — every call of that run as kept, calls:fg's and each step's: agent-state runs
# its herdr call in the background, so it is a step's.
kept_calls() { cat "${KD}/$1/${SIDE}/calls:fg" "${KD}/$1/${SIDE}"/step.* 2> /dev/null || true; }

# expect_calls <name> <fixture> — b as mutated is red, and only on <fixture>'s call streams (calls:fg
# or a step's, which is labelled by its argv and first call); then b is restored.
expect_calls() {
  local got l off=""
  if ! run 1 "${A}" "${B}" "$2" > "${ROOT}/why"; then bad "$1" "$(cat "${ROOT}/why")"; restore; return; fi
  got="$(diffs)"
  while IFS= read -r l; do [[ -z "${l}" || "${l}" == "$2 calls:"* ]] || off+="${l};"; done <<< "${got//;/$'\n'}"
  if [[ -z "${got}" || -n "${off}" ]]; then bad "$1" "DIFF lines '${got}', not only $2's call streams"; else ok "$1"; fi
  restore
}

# streams <name> <keep dir> — each side's kept streams are what the hooks do, beyond the two agreeing.
streams() {
  local want st
  KD="$2"
  for SIDE in a b; do
    want="$(printf '<time>\tincident\t-\t-\tmerge-blocked: gh pr merge ~~ version=<version>')"
    if [[ "$(kept hook_guard_merge exit)" == 2 && "$(kept hook_guard_merge stderr)" == "merge-guard: blocked (gh pr merge)."* ]] \
      && kept_has hook_guard_merge files "${want}"; then ok "$1: merge-guard refuses with its event line (${SIDE})"
    else bad "$1: merge-guard refuses with its event line (${SIDE})" "exit $(kept hook_guard_merge exit), files: $(kept hook_guard_merge files)"; fi
    if [[ "$(kept hook_guard_ls exit)" == 0 && -z "$(kept hook_guard_ls stderr)$(kept hook_guard_ls files)" ]]; then ok "$1: merge-guard passes ls (${SIDE})"
    else bad "$1: merge-guard passes ls (${SIDE})" "exit $(kept hook_guard_ls exit), stderr: $(kept hook_guard_ls stderr)"; fi
    want='{"decision": "block", "reason": "next says: story a-story. Start it now, or tell the user why it cannot start."}'
    if [[ "$(kept hook_stop_step stdout)" == "${want}" ]] \
      && kept_has hook_stop_step files "$(printf '<time>\tlead-stop\tstory\t-\tblocked ~~ role=lead version=<version>')"; then
      ok "$1: lead-stop blocks on next's step (${SIDE})"
    else bad "$1: lead-stop blocks on next's step (${SIDE})" "stdout: $(kept hook_stop_step stdout), files: $(kept hook_stop_step files)"; fi
    if [[ -z "$(kept hook_stop_none stdout)" ]] \
      && kept_has hook_stop_none files "$(printf '<time>\tlead-stop\tdone\t-\tallowed ~~ role=lead version=<version>')"; then
      ok "$1: lead-stop allows with no step (${SIDE})"
    else bad "$1: lead-stop allows with no step (${SIDE})" "stdout: $(kept hook_stop_none stdout), files: $(kept hook_stop_none files)"; fi
    for st in working idle; do
      want="herdr pane report-agent --source swarm --agent claude --state ${st} --seq <seq> --agent-session-id sess-1 w1:p1 -- claude --resume sess-1"
      if [[ "$(kept_calls "hook_state_${st}")" == "${want}" ]]; then ok "$1: agent-state reports ${st} to herdr (${SIDE})"
      else bad "$1: agent-state reports ${st} to herdr (${SIDE})" "calls: $(kept_calls "hook_state_${st}")"; fi
    done
    if [[ "$(kept hook_caught_lead stdout)" == "If this message points out a problem the swarm or the lead missed, log it first: "* \
      && -z "$(kept hook_caught_agent stdout)" && "$(kept hook_caught_agent exit)" == 0 ]]; then
      ok "$1: the reminder prints in the lead's session alone (${SIDE})"
    else bad "$1: the reminder prints in the lead's session alone (${SIDE})" "lead: $(kept hook_caught_lead stdout), agent: $(kept hook_caught_agent stdout)"; fi
  done
}

# (1) Clean, on two copies of this tree, and on v0.31.2's and v0.31.3's.
K="${ROOT}/keep"
if run 0 --keep "${K}" "${A}" "${B}" "${HOOKS[@]}" > "${ROOT}/why"; then ok "two copies compare clean on every hook fixture"
else bad "two copies compare clean on every hook fixture" "$(cat "${ROOT}/why")"; fi
for fx in "${HOOKS[@]}"; do grep -qxF "same ${fx}" "${ROOT}/out" || bad "${fx} ran on the copies" "no 'same ${fx}' line"; done
streams copies "${K}"
rm -rf "${K}"

for v in v0.31.2 v0.31.3; do
  mkdir -p "${ROOT}/${v}"
  if git -C "${REPO}" rev-parse -q --verify "${v}^{commit}" > /dev/null; then
    git -C "${REPO}" archive "${v}" "${COPY[@]}" | tar -C "${ROOT}/${v}" -xf -
  else echo "FAIL tag ${v}: not in ${REPO} (fetch the tags)"; fails=$((fails + 1)); fi
done
if run 0 --keep "${K}" "${ROOT}/v0.31.2" "${ROOT}/v0.31.3" "${HOOKS[@]}" > "${ROOT}/why"; then ok "v0.31.2 and v0.31.3 compare clean on every hook fixture"
else bad "v0.31.2 and v0.31.3 compare clean on every hook fixture" "$(cat "${ROOT}/why")"; fi
for fx in "${HOOKS[@]}"; do grep -qxF "same ${fx}" "${ROOT}/out" || bad "${fx} ran on the tags" "no 'same ${fx}' line"; done
streams tags "${K}"
rm -rf "${K}"

# (2) One change to b at a time.
mutate "${B}" hooks/merge-guard.sh '[[ ${rc} -ne 0 && ${rc} -ne 2 ]] || exit "${rc}"' '[[ ${rc} -ne 0 && ${rc} -ne 2 ]] || exit "$((rc + 1))"'
expect "merge-guard's exit code" hook_guard_merge "hook_guard_merge exit;"
mutate "${B}" hooks/lead-stop.sh '"next says: "' '"next sayz: "'
expect "one byte of lead-stop's stdout" hook_stop_step "hook_stop_step stdout;"
mutate "${B}" hooks/merge-guard.sh '"incident", "-",' '"incidenT", "-",'
expect "one byte of merge-guard's event line" hook_guard_merge "hook_guard_merge files;"
mutate "${B}" hooks/agent-state.sh '"${h}" pane "$@" <' '"${h}" pane extra < /dev/null > /dev/null 2>&1 & "${h}" pane "$@" <'
expect_calls "one extra herdr call from agent-state" hook_state_working
mutate "${B}" hooks/agent-state.sh '--agent claude --state' '--agent claudE --state'
expect_calls "one byte of agent-state's herdr argv outside --seq" hook_state_working
mutate "${B}" hooks/agent-state.sh '--state "${state}" --seq "${seq}"' '--state "${state}" --seq "${seq}0"'
expect_calls "a --seq of another shape is not masked" hook_state_working

# (3) make test's SWARM_FORBID_PROJECT names no fixture project, so (1) saw the line in both trees;
# b's guard writing none is red.
mutate "${B}" hooks/merge-guard.sh '        if forbidden(d):' '        if True:'
expect "merge-guard's event line dropped" hook_guard_merge "hook_guard_merge files;"

# (4) A fixture of this test's own, in a's checkout (diff_run.sh loads it by its glob): agent-state
# with no SWARM_RESUME file exits before its herdr call in both trees, which then agree.
cat > "${A}/tests/diff_fixtures_probe.sh" <<'FX'
# shellcheck shell=bash
fx_probe_noresume() { fx_hook_state_working; rm -f "${ROOT}/resume.argv"; }
FX
if run 1 "${A}" "${B}" probe_noresume > "${ROOT}/why" && [[ -z "$(diffs)" ]] \
  && grep -qxF "MISSING probe_noresume (a): no call 'herdr pane report-agent' in calls:fg or a step" "${ROOT}/out" \
  && grep -qxF "MISSING probe_noresume (b): no call 'herdr pane report-agent' in calls:fg or a step" "${ROOT}/out"; then
  ok "an agent-state fixture with no SWARM_RESUME file is red by its missing call"
else bad "an agent-state fixture with no SWARM_RESUME file is red by its missing call" "$(cat "${ROOT}/why")"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
