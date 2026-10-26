#!/usr/bin/env bash
# select_tests_test.sh — scripts/select-tests.sh on a fixture git repo that carries the real
# scripts/test-map.tsv and fixture tests: each named path's change selects the test that names it
# plus its row's floor and no other, a doc adds the doc floor, scripts/test.sh, the Makefile and
# a bin/lib top-level line select every test, a test selects itself, a board story nothing, a board README its
# template test, and a rename both paths' tests; committed, staged, unstaged and untracked changes
# all count. Any doubt selects every test: a path no row matches, a `named` path no test names (the
# selector's own test, whose fixture names real paths, never counts as naming one), no origin/main.
# An empty selection says so on stderr. bin/ goes by reach: a change to a function the go arm reaches
# selects the tests that run that arm (directly, through a wrapper function or a hook), a test that
# sources the lib and calls a caller, and the bin floor, not a test that runs only the stop arm; a
# call by a built name, a test that runs swarm.sh with no command word and a function no test reaches
# each select every test, and say why. --run hands the list to a stub make with JOBS=4, or runs
# nothing and says so. --functions names the bin/ functions and dispatch arms a change reaches,
# from both sides of the diff, and the functions that run a changed .py; a line in no function, or a
# .py no function runs, gives full. Last, --check-map: it names each unmapped path under bin/, scripts/,
# commands/, hooks/ and docs/, refuses a map that lists a missing test, and passes the real repo's
# ls-files.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEL="${REPO}/scripts/select-tests.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
trap 'rm -rf "${tmp}"' EXIT
G="${tmp}/repo"; fails=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# The fixture's git reads no user or system config: a global setting that signs commits would use
# the user's key and fail with a cold agent.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

check() { # <name> <got> <want>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
lines() { printf '%s\n' "$@" | LC_ALL=C sort -u; }

# The fixture: the files the cases change, the real map, each row's floor tests (which name none of
# those files), the selector's own test naming a hook it does not test, and a test naming each named
# path, one per test.
DOC_FLOOR=(); for t in doc_check features llms config epic_codex board_pr merge skill removed flow_sections; do DOC_FLOOR+=("tests/${t}_test.sh"); done
CMD_FLOOR=(); for t in doc_check roles epic_codex skill removed command_names; do CMD_FLOOR+=("tests/${t}_test.sh"); done
SHELL_FLOOR=(tests/loose_match_test.sh tests/timeouts_test.sh)
BIN_FLOOR=(); for t in agent_state command_names doc_check events lib_path loose_match removed roles skill timeouts; do BIN_FLOOR+=("tests/${t}_test.sh"); done
git init -q -b main "${G}"
mkdir -p "${G}/bin/lib" "${G}/bin/gh-shim" "${G}/board/stories" "${G}/commands" "${G}/docs" "${G}/hooks" "${G}/scripts" "${G}/tests"
for f in bin/lib/x.sh bin/gh-shim/gh board/stories/a.md board/stories/README.md commands/swarm.md commands/plan-epic.md docs/method.md \
  hooks/merge-guard.sh hooks/agent-state.sh scripts/board-only.sh scripts/test.sh Makefile; do echo base > "${G}/${f}"; done
cp "${REPO}/scripts/test-map.tsv" "${G}/scripts/"
for t in "${DOC_FLOOR[@]}" "${CMD_FLOOR[@]}" "${SHELL_FLOOR[@]}" "${BIN_FLOOR[@]}" tests/board_readme_test.sh; do echo 'echo floor' > "${G}/${t}"; done
echo 'echo hooks/agent-state.sh' > "${G}/tests/select_tests_test.sh"
echo 'cat docs/method.md' > "${G}/tests/names_method_test.sh"
echo 'cat commands/swarm.md' > "${G}/tests/names_swarm_test.sh"
echo 'cat commands/plan-epic.md' > "${G}/tests/names_plan_epic_test.sh"
echo 'bash hooks/merge-guard.sh' > "${G}/tests/names_guard_test.sh"
echo 'cp scripts/board-only.sh .' > "${G}/tests/names_gate_test.sh"
echo 'bin/gh-shim/gh api' > "${G}/tests/names_shim_test.sh"
echo 'cat commands/renamed.md' > "${G}/tests/names_renamed_test.sh"
echo 'echo plan-swarm.md old-board-only.sh merge-guard.shx' > "${G}/tests/x_test.sh"   # near misses
# --functions' fixture: a dispatch case in bin/swarm.sh, and functions of both forms in bin/lib/x.sh,
# one of which runs named.py, which imports helper.py, which imports util.py; another imports
# inline.py after a ;. lone.py is named only in a top-level comment, quiet.py only in a comment in a
# function. named.py mentions solo.py only in a comment and aside.py only in its docstring. noted is a
# one-liner with a comment.
cat > "${G}/bin/swarm.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# go_to — what the go arm runs.
go_to() {
  echo go
  uses_step
}

dispatch() {
  cmd="${1:-}"; shift || true
  case "${cmd}" in
    go) go_to ;;
    # halt: stop's old name
    stop|halt) echo stop
               echo stopped ;;
    *) exit 2 ;;
  esac
}

dispatch "$@"
EOF
cat > "${G}/bin/lib/x.sh" <<'EOF'
# x.sh — the fixture's helpers; it names named.py, and lone.py only here.
LIB_SETTING=1

run_named() {
  python3 bin/lib/named.py
}

sub_two() (
  # quiet.py is not run here
  echo two
)
gone() { echo gone; }
run_inline() {
  python3 -c 'import sys; sys.path.insert(0, "bin/lib"); from inline import X'
}
noted() { echo noted; }  # a one-liner with a comment
after() {
  echo after
}

step_one() {
  echo one
}

uses_step() {
  step_one
}

run_go_py() {
  python3 bin/lib/runs_go.py
}
EOF
# reach's fixture: tests that run the go arm (directly, by a wrapper function, by a hook, by a script
# whose path to swarm.sh is unquoted, by a hook that runs it through PATH, by a hook whose function
# passes "$@" on, by a hook that passes "$@" on and names go, by a .py a function runs and the test
# runs itself), run only the stop arm,
# source the lib to call step_one's caller, and call step_one itself.
# shellcheck disable=SC2016 # the hook's text, expanded when it runs
printf '#!/usr/bin/env bash\n"$(dirname "$0")/../bin/swarm.sh" go\n' > "${G}/hooks/runs-go.sh"
echo 'bash bin/swarm.sh go' > "${G}/tests/runs_go_test.sh"
echo 'bash bin/swarm.sh stop' > "${G}/tests/runs_stop_test.sh"
printf 'going() { bash bin/swarm.sh go "$@"; }\ngoing --fast\n' > "${G}/tests/wrapper_test.sh"
echo 'bash hooks/runs-go.sh' > "${G}/tests/hook_test.sh"
echo 'bash bin/swarm.sh go' > "${G}/scripts/start.sh"
echo 'bash scripts/start.sh' > "${G}/tests/script_test.sh"
echo 'swarm.sh go' > "${G}/hooks/bare.sh"
echo 'bash hooks/bare.sh' > "${G}/tests/bare_hook_test.sh"
printf 'source bin/lib/x.sh\nstep_one\n' > "${G}/tests/names_step_test.sh"
# shellcheck disable=SC2016 # fixture text, expanded when it runs
echo 'bash bin/swarm.sh "$@"   # go' > "${G}/hooks/fwd.sh"
# shellcheck disable=SC2016 # fixture text, expanded when it runs
echo 'bash hooks/fwd.sh "$1"' > "${G}/tests/fwd_test.sh"
printf 'f() { bash bin/swarm.sh "$@"; }\nf go\n' > "${G}/hooks/fn-fwd.sh"
echo 'bash hooks/fn-fwd.sh' > "${G}/tests/fn_fwd_test.sh"
printf 'source bin/lib/x.sh\nuses_step\n' > "${G}/tests/sources_lib_test.sh"
printf 'import subprocess\nsubprocess.run(["bash", "bin/swarm.sh", "go"])\n' > "${G}/bin/lib/runs_go.py"
echo 'python3 bin/lib/runs_go.py' > "${G}/tests/py_go_test.sh"
printf '"""Prints helper.X; aside.py is only mentioned here."""\nimport helper  # solo.py is only mentioned here\nprint(helper.X)\n' \
  > "${G}/bin/lib/named.py"
echo 'print(3)' > "${G}/bin/lib/solo.py"
echo 'print(4)' > "${G}/bin/lib/aside.py"
printf 'import util\nX = util.Y\n' > "${G}/bin/lib/helper.py"
echo 'Y = 1' > "${G}/bin/lib/util.py"
echo 'print(1)' > "${G}/bin/lib/lone.py"
echo 'X = 1' > "${G}/bin/lib/inline.py"
echo 'print(2)' > "${G}/bin/lib/quiet.py"
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
  "$(lines "${DOC_FLOOR[@]}" tests/names_method_test.sh)"
check "an unstaged command selects the command floor and the test that names it, no other" "$(sel 'echo 1 >> commands/swarm.md')" \
  "$(lines "${CMD_FLOOR[@]}" tests/names_swarm_test.sh)"
check "a command only its own test names still selects command_names_test.sh, which greps every command" \
  "$(sel "echo 1 >> commands/plan-epic.md; ${commit}")" "$(lines "${CMD_FLOOR[@]}" tests/names_plan_epic_test.sh)"
check "a staged hook selects the shell-scan floor and the test that names it, no other" "$(sel 'echo 1 >> hooks/merge-guard.sh; git add -A')" \
  "$(lines "${SHELL_FLOOR[@]}" tests/names_guard_test.sh)"
check "a script selects the test that names it, alone" "$(sel "echo 1 >> scripts/board-only.sh; ${commit}")" tests/names_gate_test.sh
check "the gh shim selects the shell-scan floor and the test that names it, no other" "$(sel "echo 1 >> bin/gh-shim/gh; ${commit}")" \
  "$(lines "${SHELL_FLOOR[@]}" tests/names_shim_test.sh)"
check "scripts/test.sh selects every test" "$(sel "echo 1 >> scripts/test.sh; ${commit}")" "${ALL}"
check "the Makefile selects every test" "$(sel "echo 1 >> Makefile; ${commit}")" "${ALL}"
check "a bin/lib file's top level selects every test" "$(sel "echo 1 >> bin/lib/x.sh; ${commit}")" "${ALL}"
check "a test selects itself" "$(sel "echo 1 >> tests/x_test.sh; ${commit}")" tests/x_test.sh
check "a new untracked test selects itself" "$(sel 'echo 1 > tests/new_test.sh')" tests/new_test.sh
check "a board story selects nothing" "$(sel "echo 1 >> board/stories/a.md; ${commit}")" ""
check "a board README selects the test that checks it against its template" "$(sel "echo 1 >> board/stories/README.md; ${commit}")" \
  tests/board_readme_test.sh
check "a rename selects for both paths" "$(sel "git mv commands/swarm.md commands/renamed.md; ${commit}")" \
  "$(lines "${CMD_FLOOR[@]}" tests/names_renamed_test.sh tests/names_swarm_test.sh)"
check "an untracked file no row matches selects every test" "$(sel 'echo 1 > notes.txt')" "${ALL}"
check "a named file only the selector's own test names selects every test" "$(sel "echo 1 >> hooks/agent-state.sh; ${commit}")" "${ALL}"
check "no origin/main selects every test" \
  "$(sel "echo 1 >> board/stories/a.md; ${commit}; git update-ref -d refs/remotes/origin/main")" "${ALL}"
git -C "${G}" update-ref refs/remotes/origin/main "${BASE}"
sel 'echo 1 > notes.txt' > /dev/null
check "it says why it selects every test" "$(cd "${G}" && bash "${SEL}" 2>&1 >/dev/null)" \
  "select-tests: every test: notes.txt: no row in scripts/test-map.tsv matches it"
sel "echo 1 >> board/stories/a.md; ${commit}" > /dev/null
check "an empty selection says so on stderr" "$(cd "${G}" && bash "${SEL}" 2>&1 >/dev/null)" \
  "select-tests: no test file covers this branch's changes"

# reach: the bin/ row, by function.
GO=(tests/runs_go_test.sh tests/wrapper_test.sh tests/hook_test.sh tests/script_test.sh tests/bare_hook_test.sh
  tests/fn_fwd_test.sh tests/fwd_test.sh tests/py_go_test.sh)
check "a function the go arm reaches selects the go tests, the lib caller's and the bin floor, not the stop test" \
  "$(sel "perl -pi -e 's/echo one/echo 1/' bin/lib/x.sh; ${commit}")" "$(lines "${GO[@]}" tests/sources_lib_test.sh tests/names_step_test.sh "${BIN_FLOOR[@]}")"
check "a deleted function still selects the tests of its callers" \
  "$(sel "perl -0pi -e 's/step_one\\(\\) \\{\\n  echo one\\n\\}\\n//' bin/lib/x.sh; ${commit}")" \
  "$(lines "${GO[@]}" tests/sources_lib_test.sh tests/names_step_test.sh "${BIN_FLOOR[@]}")"
check "the stop arm (and its other name, halt) selects the test that runs it and the bin floor, no other" \
  "$(sel "perl -pi -e 's/echo stop/echo stopping/' bin/swarm.sh")" "$(lines tests/runs_stop_test.sh "${BIN_FLOOR[@]}")"
# why — what select-tests.sh says on stderr in the fixture as the last case left it.
why() { (cd "${G}" && { bash "${SEL}" > /dev/null; } 2>&1); }
check "a call by a built name that may be the function selects every test, and says so" \
  "$(sel "perl -pi -e 's/echo one/echo 1/; s/^  step_one\\b/  \"step_\\\${1:-one}\"/' bin/lib/x.sh; ${commit}")|$(why)" \
  "${ALL}|select-tests: every test: bin/lib/x.sh:step_one: bin/lib/x.sh:26 calls a function by a name it builds, which may be step_one"
check "a variable set to a built name and run selects every test, and says so" \
  "$(sel "perl -pi -e 's/echo one/echo 1/; s/^  step_one\\b/  fn=\"step_\\\${1:-one}\"; \"\\\$fn\"/' bin/lib/x.sh; ${commit}")|$(why)" \
  "${ALL}|select-tests: every test: bin/lib/x.sh:step_one: bin/lib/x.sh:26 calls a function by a name it builds, which may be step_one"
check "a test that runs swarm.sh with no command word selects every test, and says so" \
  "$(sel "perl -pi -e 's/echo one/echo 1/' bin/lib/x.sh; echo 'for c in a b; do bash bin/swarm.sh \"\$c\"; done' > tests/blind_test.sh")|$(why)" \
  "$(lines "${ALL}" tests/blind_test.sh)|select-tests: every test: tests/blind_test.sh runs swarm.sh with no command word in it"
check "a function no test reaches selects every test, and says so" \
  "$(sel "perl -pi -e 's/echo two/echo 2/' bin/lib/x.sh; ${commit}")|$(why)" \
  "${ALL}|select-tests: every test: bin/lib/x.sh:sub_two: no test reaches it"

# --functions, on the bin/ fixture above.
fn() { sel "$1" --functions; }
check "an edit inside a function gives that function" \
  "$(fn "perl -pi -e 's/echo two/echo 2/' bin/lib/x.sh; ${commit}")" bin/lib/x.sh:sub_two
check "edits to a dispatch arm's line and its next line give each arm's commands" \
  "$(fn "perl -pi -e 's/go_to ;;/go_to \"\\\$@\" ;;/; s/echo stopped/echo halted/' bin/swarm.sh")" \
  "$(lines 'bin/swarm.sh:arm go' 'bin/swarm.sh:arm halt' 'bin/swarm.sh:arm stop')"
check "an edit to the comment above an arm gives that arm" \
  "$(fn "perl -pi -e 's/old name/former name/' bin/swarm.sh")" "$(lines 'bin/swarm.sh:arm halt' 'bin/swarm.sh:arm stop')"
check "an edit to a function's doc comment gives that function" \
  "$(fn "perl -pi -e 's/what the go arm runs/the go arm/' bin/swarm.sh; ${commit}")" bin/swarm.sh:go_to
check "a deleted function gives its name from the base" \
  "$(fn "perl -ni -e 'print unless /^gone\\(\\)/' bin/lib/x.sh; ${commit}")" bin/lib/x.sh:gone
check "an edit at file top level gives full" "$(fn "perl -pi -e 's/LIB_SETTING=1/LIB_SETTING=2/' bin/lib/x.sh; ${commit}")" full
check "--functions says why it gives full" "$(cd "${G}" && bash "${SEL}" --functions 2>&1 >/dev/null)" \
  "select-tests: full: bin/lib/x.sh:2 at the base is in no function"
check "a new function with its doc comment gives that function alone" \
  "$(fn "printf '\\n# added — new\\nadded() {\\n  :\\n}\\n' >> bin/lib/x.sh; ${commit}")" bin/lib/x.sh:added
check "a new untracked .sh gives its functions" \
  "$(fn "printf '# new.sh\\nNEW=1\\nnew_one() {\\n  :\\n}\\nnew_two() { :; }\\n' > bin/lib/new.sh")" \
  "$(lines bin/lib/new.sh:new_one bin/lib/new.sh:new_two)"
check "a mode change to a bin file gives full" "$(fn "chmod +x bin/lib/x.sh; ${commit}")" full
check "an edit to a .py gives the shell functions whose bodies name it" "$(fn 'echo 1 >> bin/lib/named.py')" bin/lib/x.sh:run_named
check "an edit to a .py two imports away gives the functions that run the first" \
  "$(fn "echo 'Z = 2' >> bin/lib/util.py; ${commit}")" bin/lib/x.sh:run_named
check "an edit to a .py imported after a ; gives the function that imports it" \
  "$(fn "echo 'Y = 2' >> bin/lib/inline.py; ${commit}")" bin/lib/x.sh:run_inline
check "a .py named only in a top-level comment gives full" "$(fn "echo 1 >> bin/lib/lone.py; ${commit}")" full
check "a .py named only in a comment in a function gives full" "$(fn "echo 1 >> bin/lib/quiet.py; ${commit}")" full
check "a .py named only in another .py's comment gives full" "$(fn "echo 1 >> bin/lib/solo.py; ${commit}")" full
check "a .py named only in another .py's docstring gives full" "$(fn "echo 1 >> bin/lib/aside.py; ${commit}")" full
check "a .py a script runs gives full" \
  "$(fn "echo 'python3 bin/lib/named.py' >> scripts/board-only.sh; echo 1 >> bin/lib/named.py")" full
check "a .py a test runs gives full" \
  "$(fn "echo 'python3 bin/lib/named.py' > tests/direct_test.sh; echo 1 >> bin/lib/named.py")" full
check "an edit after a one-liner with a comment gives the next function" \
  "$(fn "perl -pi -e 's/echo after/echo later/' bin/lib/x.sh; ${commit}")" bin/lib/x.sh:after
check "a function it cannot parse gives full" \
  "$(fn "printf 'odd() { echo x; } ; echo y\\nlater() {\\n  :\\n}\\n' >> bin/lib/x.sh; ${commit}")" full
check "--functions reads no map" \
  "$(fn "echo bad > scripts/test-map.tsv; perl -pi -e 's/echo two/echo 2/' bin/lib/x.sh")" bin/lib/x.sh:sub_two
check "a change outside bin/ gives no function" "$(fn "echo 1 >> docs/method.md; ${commit}")" ""
check "--functions says so on stderr when it gives no function" "$(cd "${G}" && bash "${SEL}" --functions 2>&1 >/dev/null)" \
  "select-tests: no bin/ function: no change reaches a function in bin/swarm.sh, bin/lib/*.sh or bin/lib/*.py"
check "no origin/main gives full" \
  "$(fn "echo 1 >> bin/lib/named.py; git update-ref -d refs/remotes/origin/main")" full
git -C "${G}" update-ref refs/remotes/origin/main "${BASE}"

# --run: a stub make records its arguments and any SHARD it was left.
mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/make" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" "SHARD \${SHARD-unset}" > "${tmp}/make.args"
STUB
chmod +x "${tmp}/bin/make"
out="$(PATH="${tmp}/bin:${PATH}" SHARD=1/8 sel 'echo 1 >> commands/swarm.md; echo 1 >> docs/method.md' --run)"
want="$(lines "${DOC_FLOOR[@]}" "${CMD_FLOOR[@]}" tests/names_method_test.sh tests/names_swarm_test.sh | tr '\n' ' ')"
check "--run runs make test on the whole selection, JOBS=4, with no SHARD" "${out}|$(cat "${tmp}/make.args")" \
  "|$(printf '%s\n' test "TESTS=${want% }" JOBS=4 "SHARD unset")"
rm -f "${tmp}/make.args"
out="$(cd "${G}" && PATH="${tmp}/bin:${PATH}" bash "${SEL}" --run --functions 2>&1)" && rc=0 || rc=$?
check "--run with --functions is refused and runs nothing" "${out}|${rc}|$([[ -e "${tmp}/make.args" ]] && echo ran)" \
  "select-tests: --run takes no other option, so it cannot run --functions' or --check-map's output|2|"
out="$(PATH="${tmp}/bin:${PATH}" sel "echo 1 >> board/stories/a.md; ${commit}" --run)"
check "--run on an empty selection runs nothing and says so" "${out}|$([[ -e "${tmp}/make.args" ]] && echo ran)" \
  "select-tests: nothing to run|"

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
