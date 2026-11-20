#!/usr/bin/env bash
# diff_base_test.sh — tests/diff_run.sh --base, which the diff-run workflow runs on each PR, and
# scripts/diff-run-branches.sh, which names the head's branches for it. The head is a git checkout
# holding the harness, its fixtures and scripts/allow/, as CI's is. (1) With the head on story/a: a
# difference a's entry covers passes; one only b's entry covers is red, with b's entry on the base
# (committed before the head's commit) and with b's entry added by the head; b's entry added by the
# head with no difference behind it is not red. (2) With no story branch, every difference is red,
# and the run says no entry applies. A malformed entry of a story --base leaves out still stops the
# run, and --base with --stage, or --branch without --base, is a bad argument. (3) A merge group:
# diff-run-branches.sh names the head branch of each queue entry up to the group's head commit and
# no later one, so the group's two story PRs, each with an entry for its own change, pass; with one
# entry removed the run is red, naming that PR's change. A pull_request run names its own head branch,
# and a group whose head is in no entry is an error. (4) In .github/workflows/diff-run.yml the gate
# step runs the base's copy of scripts/board-only.sh, and every step after it runs only when the gate
# says the PR is not board-only, so a board-only PR skips them.
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
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; sed 's/^/  | /' "${ROOT}/out"; fails=$((fails + 1)); }

# The base tree and the head checkout, as the workflow has them. The head runs the harness, so its
# fixtures and its scripts/allow/ are the ones read.
BASE="${ROOT}/base" HEAD="${ROOT}/head"
for t in "${BASE}" "${HEAD}"; do
  mkdir -p "${t}/tests"
  (cd "${REPO}" && tar -cf - tests/diff_run.sh tests/diff_allow.py tests/diff_fixtures_*.sh scripts/diff-run-branches.sh) | tar -C "${t}" -xf -
done
cat > "${HEAD}/tests/diff_fixtures_probe.sh" <<'FX'
# shellcheck shell=bash disable=SC2034
fx_probe() { FX_CMD=(bash "${TREE}/probe.sh"); }
FX
git -C "${HEAD}" init -q -b story/a
git -C "${HEAD}" -c user.name=t -c user.email=t@t add -A
git -C "${HEAD}" -c user.name=t -c user.email=t@t commit -q -m base
# commit <msg> — commit everything in the head checkout.
commit() { git -C "${HEAD}" add -A && git -C "${HEAD}" -c user.name=t -c user.email=t@t commit -q -m "$1"; }
# probe <base's output> <head's output> — what fx_probe prints on each tree, a line a word.
probe() {
  printf 'printf "%%s\\n" %s\n' "$1" > "${BASE}/probe.sh"
  printf 'printf "%%s\\n" %s\n' "$2" > "${HEAD}/probe.sh"
}

# run <rc> [diff_run args...] — run the head's diff_run.sh, base against head, on fx_probe; its output
# in ${ROOT}/out.
run() {
  local want="$1" rc=0; shift
  bash "${HEAD}/tests/diff_run.sh" "$@" "${BASE}" "${HEAD}" probe > "${ROOT}/out" 2>&1 &
  DR_PID=$!; wait "${DR_PID}" || rc=$?; DR_PID=""
  [[ ${rc} == "${want}" ]] || { echo "exit ${rc}, not ${want}"; return 1; }
}
# expect <name> <rc> <line> [diff_run args...] — the run exits <rc> and prints a line holding <line>.
expect() {
  local name="$1" want="$2" line="$3"; shift 3
  if ! run "${want}" "$@" > "${ROOT}/why"; then bad "${name}" "$(cat "${ROOT}/why")"
  elif ! grep -qF -- "${line}" "${ROOT}/out"; then bad "${name}" "no line '${line}'"
  else ok "${name}"; fi
}
# lacks <name> <line> — the last run printed no line holding <line>.
lacks() { if grep -qF -- "$2" "${ROOT}/out"; then bad "$1" "a line '$2'"; else ok "$1"; fi; }

FENCE='```'
# entry <slug> <pr> <old> <new> — the head's scripts/allow/stage-1/<slug>.md: one probe stdout hunk
# that turns the line <old> into <new>.
entry() {
  mkdir -p "${HEAD}/scripts/allow/stage-1"
  printf -- '---\nstory: %s\npr: %s\nkind: stage\n---\n\n# %s\n\n## probe stdout\n\n%s\n-%s\n+%s\n%s\n' \
    "$1" "$2" "$1" "${FENCE}diff" "$3" "$4" "${FENCE}" > "${HEAD}/scripts/allow/stage-1/$1.md"
}
drop() { rm -f "${HEAD}/scripts/allow/stage-1/$1.md"; }

# (1) The head, on story/a, changes two to TWO.
probe "one two" "one TWO"
entry a 11 two TWO
commit "a's entry"
expect "a difference the head story's own entry covers passes" 0 "same probe" --base --branch story/a
expect "--base says whose entries apply" 0 "allow: --base applies the entries of a alone" --base --branch story/a
drop a; entry b 12 two TWO
commit "b's entry, on the base"
expect "a difference only b's entry covers, with b's entry on the base, is red" 1 "DIFF probe stdout" --base --branch story/a
expect "a story with no entry is named as having none" 1 "the entries of a (no entry) alone" --base --branch story/a
git -C "${HEAD}" reset -q --soft HEAD~1
expect "a difference only b's entry covers, with b's entry added by the head, is red" 1 "+TWO" --base --branch story/a
drop b; entry a 11 two TWO; entry b 12 one ONE
expect "b's entry added by the head with no difference behind it is not red" 0 "same probe" --base --branch story/a
lacks "b's entry is never applied, so it cannot fail to apply" "ALLOW-FAIL"

# (2) No story branch, a bad entry left out, and bad arguments.
expect "a branch that is no story branch names no entry" 1 "--base: board/x is no story/<slug> branch" --base --branch board/x
expect "with no story, the run says no entry applies" 1 "allow: --base names no story" --base
printf -- '---\nstory: b\npr: 12\nkind: stage\n---\n\n# b\n' > "${HEAD}/scripts/allow/stage-1/b.md"
expect "a malformed entry of a story --base leaves out stops the run" 2 "the entry has no hunks" --base --branch story/a
drop b
expect "--base with --stage is a bad argument" 2 "--base takes neither --stage nor --only" --base --stage 1 --branch story/a
expect "--branch without --base is a bad argument" 2 "--branch goes with --base" --branch story/a

# (3) A merge group of two story PRs, a (#11) and b (#12), with #13 queued behind them.
BIN="${ROOT}/bin"; mkdir -p "${BIN}"
G1="$(printf '1%.0s' {1..40})" G2="$(printf '2%.0s' {1..40})" G3="$(printf '3%.0s' {1..40})"
cat > "${BIN}/gh" <<GH
#!/usr/bin/env bash
[[ "\$1 \$2" == "api graphql" ]] || { echo "gh stub: \$*" >&2; exit 1; }
cat <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"position":3,"headCommit":{"oid":"${G3}"},"pullRequest":{"number":13,"headRefName":"story/c"}},
 {"position":1,"headCommit":{"oid":"${G1}"},"pullRequest":{"number":11,"headRefName":"story/a"}},
 {"position":2,"headCommit":{"oid":"${G2}"},"pullRequest":{"number":12,"headRefName":"story/b"}}]}}}}}
JSON
GH
chmod +x "${BIN}/gh"
# branches <rc> <event> [NAME=value...] — run the head's diff-run-branches.sh for <event>, its output in
# ${ROOT}/out, and check its exit.
branches() {
  local want="$1" event="$2" rc=0; shift 2
  env PATH="${BIN}:${PATH}" GITHUB_EVENT_NAME="${event}" GITHUB_REPOSITORY=o/r "$@" \
    bash "${HEAD}/scripts/diff-run-branches.sh" > "${ROOT}/out" 2>&1 || rc=$?
  [[ ${rc} == "${want}" ]] || { echo "exit ${rc}, not ${want}"; return 1; }
}
if ! branches 0 merge_group HEAD_SHA="${G2}" BASE_REF=refs/heads/main > "${ROOT}/why"; then bad "a merge group's branches are read" "$(cat "${ROOT}/why")"
elif [[ "$(cat "${ROOT}/out")" != "story/a"$'\n'"story/b" ]]; then bad "a merge group names its PRs, up to its own head, in queue order" "not story/a then story/b"
else ok "a merge group names its PRs, up to its own head, in queue order"; fi
group=(); while IFS= read -r b; do group+=(--branch "${b}"); done < "${ROOT}/out"
probe "one two" "ONE TWO"
entry a 11 two TWO; entry b 12 one ONE
expect "the group's two story PRs, each with its own entry, pass" 0 "same probe" --base "${group[@]}"
drop b
expect "with b's entry removed, the group is red" 1 "DIFF probe stdout" --base "${group[@]}"
expect "and the red names b's change" 1 "+ONE" --base "${group[@]}"
if ! branches 0 pull_request HEAD_REF=story/a > "${ROOT}/why"; then bad "a pull_request names its head branch" "$(cat "${ROOT}/why")"
elif [[ "$(cat "${ROOT}/out")" != "story/a" ]]; then bad "a pull_request names its head branch" "not story/a"
else ok "a pull_request names its head branch"; fi
if ! branches 1 merge_group HEAD_SHA="$(printf '9%.0s' {1..40})" BASE_REF=refs/heads/main > "${ROOT}/why"; then bad "a group whose head is in no entry is an error" "$(cat "${ROOT}/why")"
elif ! grep -qF "no entry in main's merge queue has head commit" "${ROOT}/out"; then bad "a group whose head is in no entry is an error" "no line naming the head"
else ok "a group whose head is in no entry is an error"; fi

# (4) diff-run.yml: the gate step runs the base's copy of scripts/board-only.sh, as ci.yml's do, and
# every step after it runs only when it says the PR is not board-only, so a board-only PR skips them.
if python3 - "${REPO}/.github/workflows/diff-run.yml" <<'PY'
import sys
steps, cur = [], None
for raw in open(sys.argv[1]).read().split("\n"):
    if raw.startswith("      - "):
        cur = [raw[8:]]
        steps.append(cur)
    elif raw.startswith("        ") and cur is not None:
        cur.append(raw[8:])
    elif raw.strip() and not raw.startswith("        "):
        cur = None
def top(step, key):
    return next((line[len(key) + 1:].strip() for line in step if line.startswith(key + ":")), None)
gates = [i for i, s in enumerate(steps) if 'git show "${BASE_SHA}:scripts/board-only.sh"' in "\n".join(s)]
if len(gates) != 1 or top(steps[gates[0]], "id") != "gate":
    sys.exit("FAIL diff-run.yml: no one gate step with id gate that runs the base's copy")
rest = steps[gates[0] + 1:]
want = "steps.gate.outputs.board_only != 'true'"
cond = lambda s: top(s, "if") or ""
bad = [top(s, "name") for s in rest if "||" in cond(s) or not (cond(s) == want or cond(s).startswith(want + " &&"))]
if not rest or bad:
    sys.exit("FAIL diff-run.yml: a step after the gate runs on a board-only PR: %s" % (bad or "none after it"))
PY
then ok "diff-run.yml: every step after the gate skips a board-only PR"; else fails=$((fails + 1)); fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
