#!/usr/bin/env bash
# select_tests_test.sh — scripts/select-tests.sh on a fixture git repo that carries the real
# scripts/test-map.tsv and fixture tests: each named-path's change selects the test that names it
# and no other, a doc adds the doc floor, scripts/test.sh, the Makefile and bin/lib select every
# test, a test selects itself, board/ nothing, and a rename both paths' tests; committed, staged,
# unstaged and untracked changes all count. Any doubt selects every test: a path no row matches, a
# `named` path no test names, no origin/main. --run hands the list to a stub make with JOBS=4, or
# runs nothing. Last, --check-map: it names each unmapped path under bin/, scripts/, commands/,
# hooks/ and docs/, refuses a map that lists a missing test, and passes the real repo's ls-files.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEL="${REPO}/scripts/select-tests.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
trap 'rm -rf "${tmp}"' EXIT
G="${tmp}/repo"; fails=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

check() { # <name> <got> <want>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
lines() { printf '%s\n' "$@" | LC_ALL=C sort; }

# The fixture: the files the cases change, the real map, the doc floor's tests (which name none of
# those files) and a test naming each named path, one per test.
FLOOR=()
for t in doc_check features llms config epic_codex board_pr merge skill removed flow_sections; do FLOOR+=("tests/${t}_test.sh"); done
git init -q -b main "${G}"
mkdir -p "${G}/bin/lib" "${G}/bin/gh-shim" "${G}/board/stories" "${G}/commands" "${G}/docs" "${G}/hooks" "${G}/scripts" "${G}/tests"
for f in bin/lib/x.sh bin/gh-shim/gh board/stories/a.md commands/swarm.md docs/method.md hooks/merge-guard.sh \
  hooks/agent-state.sh scripts/board-only.sh scripts/test.sh Makefile; do echo base > "${G}/${f}"; done
cp "${REPO}/scripts/test-map.tsv" "${G}/scripts/"
for t in "${FLOOR[@]}"; do echo 'echo floor' > "${G}/${t}"; done
echo 'cat docs/method.md' > "${G}/tests/names_method_test.sh"
echo 'cat commands/swarm.md' > "${G}/tests/names_swarm_test.sh"
echo 'bash hooks/merge-guard.sh' > "${G}/tests/names_guard_test.sh"
echo 'cp scripts/board-only.sh .' > "${G}/tests/names_gate_test.sh"
echo 'bin/gh-shim/gh api' > "${G}/tests/names_shim_test.sh"
echo 'cat commands/renamed.md' > "${G}/tests/names_renamed_test.sh"
echo 'echo plan-swarm.md old-board-only.sh merge-guard.shx' > "${G}/tests/x_test.sh"   # near misses
git -C "${G}" add -A; git -C "${G}" commit -qm base
git -C "${G}" update-ref refs/remotes/origin/main HEAD
BASE="$(git -C "${G}" rev-parse HEAD)"
ALL="$(cd "${G}" && lines tests/*_test.sh)"

# sel <shell> [args] — select-tests.sh's stdout in the fixture after <shell>'s changes on a branch
# off the base; a fresh branch each time, with nothing left from the last case.
sel() {
  git -C "${G}" checkout -q -f -B case "${BASE}"; git -C "${G}" clean -qfd
  (cd "${G}" && eval "$1")
  (cd "${G}" && bash "${SEL}" "${@:2}" 2>/dev/null)
}
commit='git add -A && git commit -qm change'

check "a doc selects the doc floor and the test that names it" "$(sel "echo 1 >> docs/method.md; ${commit}")" \
  "$(lines "${FLOOR[@]}" tests/names_method_test.sh)"
check "an unstaged command selects the test that names it, alone" "$(sel 'echo 1 >> commands/swarm.md')" tests/names_swarm_test.sh
check "a staged hook selects the test that names it, alone" "$(sel 'echo 1 >> hooks/merge-guard.sh; git add -A')" tests/names_guard_test.sh
check "a script selects the test that names it, alone" "$(sel "echo 1 >> scripts/board-only.sh; ${commit}")" tests/names_gate_test.sh
check "the gh shim selects the test that names it, alone" "$(sel "echo 1 >> bin/gh-shim/gh; ${commit}")" tests/names_shim_test.sh
check "scripts/test.sh selects every test" "$(sel "echo 1 >> scripts/test.sh; ${commit}")" "${ALL}"
check "the Makefile selects every test" "$(sel "echo 1 >> Makefile; ${commit}")" "${ALL}"
check "a bin/lib file selects every test" "$(sel "echo 1 >> bin/lib/x.sh; ${commit}")" "${ALL}"
check "a test selects itself" "$(sel "echo 1 >> tests/x_test.sh; ${commit}")" tests/x_test.sh
check "a new untracked test selects itself" "$(sel 'echo 1 > tests/new_test.sh')" tests/new_test.sh
check "a board-only change selects nothing" "$(sel "echo 1 >> board/stories/a.md; ${commit}")" ""
check "a rename selects for both paths" "$(sel "git mv commands/swarm.md commands/renamed.md; ${commit}")" \
  "$(lines tests/names_renamed_test.sh tests/names_swarm_test.sh)"
check "an untracked file no row matches selects every test" "$(sel 'echo 1 > notes.txt')" "${ALL}"
check "a named file no test names selects every test" "$(sel "echo 1 >> hooks/agent-state.sh; ${commit}")" "${ALL}"
check "no origin/main selects every test" \
  "$(sel "echo 1 >> board/stories/a.md; ${commit}; git update-ref -d refs/remotes/origin/main")" "${ALL}"
git -C "${G}" update-ref refs/remotes/origin/main "${BASE}"
sel 'echo 1 > notes.txt' > /dev/null
check "it says why it selects every test" "$(cd "${G}" && bash "${SEL}" 2>&1 >/dev/null)" \
  "select-tests: every test: notes.txt: no row in scripts/test-map.tsv matches it"

# --run: a stub make records its arguments and any SHARD it was left.
mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/make" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" "SHARD \${SHARD-unset}" > "${tmp}/make.args"
STUB
chmod +x "${tmp}/bin/make"
out="$(PATH="${tmp}/bin:${PATH}" SHARD=1/8 sel 'echo 1 >> commands/swarm.md; echo 1 >> docs/method.md' --run)"
want="$(lines "${FLOOR[@]}" tests/names_method_test.sh tests/names_swarm_test.sh | tr '\n' ' ')"
check "--run runs make test on the whole selection, JOBS=4, with no SHARD" "${out}|$(cat "${tmp}/make.args")" \
  "|$(printf '%s\n' test "TESTS=${want% }" JOBS=4 "SHARD unset")"
rm -f "${tmp}/make.args"
out="$(PATH="${tmp}/bin:${PATH}" sel "echo 1 >> board/stories/a.md; ${commit}" --run)"
check "--run on an empty selection runs nothing and says so" "${out}|$([[ -e "${tmp}/make.args" ]] && echo ran)" \
  "select-tests: no test file covers this branch's changes; nothing to run|"

# --check-map, on a map with no row for any of these, then on one that lists a missing test.
M="${tmp}/map"; mkdir -p "${M}/scripts"; git init -q "${M}"
printf 'board/**\tnone\n' > "${M}/scripts/test-map.tsv"
out="$(cd "${M}" && printf '%s\n' bin/new.sh scripts/new.sh commands/new.md hooks/new.sh docs/new.md README.md .github/x.yml board/a.md \
  | bash "${SEL}" --check-map)" && rc=0 || rc=$?
check "--check-map names each unmapped path under bin, scripts, commands, hooks and docs, and fails" "${out}|${rc}" \
  "$(printf 'select-tests: %s: no row in scripts/test-map.tsv matches it\n' bin/new.sh scripts/new.sh commands/new.md hooks/new.sh docs/new.md)|1"
printf 'docs/**\tnamed tests/gone_test.sh\n' > "${M}/scripts/test-map.tsv"
out="$(cd "${M}" && bash "${SEL}" --check-map < /dev/null 2>&1)" && rc=0 || rc=$?
check "a map that lists a missing test is refused" "${out}|${rc}" "select-tests: scripts/test-map.tsv:1: tests/gone_test.sh does not exist|2"
out="$(cd "${REPO}" && git ls-files | bash "${SEL}" --check-map)" && rc=0 || rc=$?
check "the real map covers every tracked file under bin, scripts, commands, hooks and docs" "${out}|${rc}" "|0"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
