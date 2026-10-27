#!/usr/bin/env bash
# init_test.sh — swarm.sh init in throwaway git repos: the board from the plugin's templates, never
# over a file that exists, .claude/swarm/ with a commented commit_trailers line, the .gitignore
# lines, a CI workflow with a board-only skip, a pre-commit hook, a second run that changes nothing,
# board_dir, the swarm.sh merge allow rule in Claude Code's settings, auto mode's setup step and
# init --auto-mode-done, and the refusals outside a repo's root.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
TEMPLATES="$(dirname "${SWARM}")/../templates/docs"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
run() { (cd "$1" && shift && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" "$@" 2>&1); }
# same <template-dir> <board> — "same" when the board holds every template file, byte for byte.
same() {
  local f
  while IFS= read -r f; do cmp -s "$1/${f}" "$2/${f}" || { echo "differs: ${f}"; return; }; done \
    < <(cd "$1" && find . -type f | sed 's|^\./||')
  echo same
}
has() { grep -qxF -- "$2" <<< "$1" && echo yes || echo no; }
# origin <repo> [<branch>] — give <repo> an origin, a local bare repo whose default branch is <branch>
# (main), fetched, so init can tell origin's default branch.
origin() {
  local bare="$1.git" w="$1.seed"
  "${GIT[@]}" init -q --bare -b "${2:-main}" "${bare}" && "${GIT[@]}" init -q -b "${2:-main}" "${w}"
  "${GIT[@]}" -C "${w}" commit -q --allow-empty -m seed && "${GIT[@]}" -C "${w}" push -q "${bare}" "${2:-main}"
  git -C "$1" remote add origin "${bare}" && git -C "$1" fetch -q origin
}
# gate <repo> <path> [<base>] — the CI gate's verdict on a PR that adds <path> in <repo>, run as CI
# runs it, against the commit before (or <base>).
gate() {
  local base
  base="$(cd "$1" && "${GIT[@]}" add -A && "${GIT[@]}" commit -q --allow-empty -m base --no-verify && git rev-parse HEAD)"
  mkdir -p "$(dirname "$1/$2")" && echo x > "$1/$2"
  (cd "$1" && "${GIT[@]}" add -A && "${GIT[@]}" commit -qm pr --no-verify \
    && BASE_SHA="${3:-${base}}" GITHUB_OUTPUT=/dev/stdout bash .github/swarm-board-only.sh 2>/dev/null | grep '^board_only=')
}

# --- A fresh repo: every template file, .claude/swarm/, the three lines; the second run changes nothing.
p="${ROOT}/fresh"; "${GIT[@]}" init -q "${p}"; origin "${p}"
printf 'node_modules/' > "${p}/.gitignore"   # no trailing newline: the first added line must not join it
out="$(run "${p}" init || true)"
check "init copies every template file" "same" "$(same "${TEMPLATES}" "${p}/docs")"
sections=$'Alternatives\nCurrent state\nDesign\nEpics\nGoals\nNon-goals\nOpen questions\nProblem\nRisks and safety\nRollout'
check "init writes the HLD template with a grants line and the ten sections" "yes|${sections}" \
  "$(grep -qxF 'grants: []' "${p}/docs/hld/README.md" && echo yes)|$(sed -nE 's/^## ([^ ]+( [^ ]+)*)  .*/\1/p' "${p}/docs/hld/README.md" | LC_ALL=C sort)"
check "init's Board.base has a view on the HLDs" "yes" "$(grep -qF -- '- file.inFolder("hld")' "${p}/docs/Board.base" && echo yes || echo no)"
check "init creates .claude/swarm/" "yes" "$([[ -d "${p}/.claude/swarm" ]] && echo yes || echo no)"
check "init adds the three .gitignore lines after the existing one" \
  $'node_modules/\n.swarm/\ndocs/.obsidian/*\n!docs/.obsidian/app.json' "$(cat "${p}/.gitignore")"
check "init adds a commented commit_trailers line" "# commit_trailers = Co-Authored-By: Your Name <you@example.com>" \
  "$(cat "${p}/.claude/swarm/config")"
# shellcheck disable=SC2016 # the workflow's own ${...}, matched literally
check "init writes a CI that runs the gate on a PR and a push, and otherwise make check, on pushes to main" "yes|yes|yes|yes|yes|yes" \
  "$(grep -qxF 'BOARD="docs/"' "${p}/.github/swarm-board-only.sh" && echo yes)|$(grep -qxF '        run: bash .github/swarm-board-only.sh' "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qF '${{ github.event.pull_request.base.sha || github.event.before }}' "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qF 'if: steps.gate.outputs.board_only != '"'true'" "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qxF '          make check' "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qF 'branches: ["main"]' "${p}/.github/workflows/ci.yml" && echo yes)"
check "init writes an executable pre-commit hook for docs/" "yes|yes" \
  "$(grep -qxF 'swarm_board="docs/"' "${p}/.git/hooks/pre-commit" && echo yes)|$([[ -x "${p}/.git/hooks/pre-commit" ]] && echo yes)"
check "init says to commit what it wrote, naming each path" \
  "Commit what init wrote, so CI runs and the config travels with the repo: .gitignore .claude/swarm/config .github/workflows/ci.yml .github/swarm-board-only.sh $(cd "${TEMPLATES}" && find . -type f | sed 's|^\./|docs/|' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" \
  "$(grep '^Commit what init wrote' <<< "${out}")"
# make_check <dir> — CI's make check step, run in <dir>: its output and exit code.
make_check() {
  sed -n '/- name: make check/,$p' "${p}/.github/workflows/ci.yml" | sed -n '/run: |/,$p' | sed '1d; s/^          //' > "${ROOT}/make-check.sh"
  # As CI runs it: not under the make that runs this suite, whose MAKEFLAGS would add make[1] lines.
  (cd "$1" && env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS bash "${ROOT}/make-check.sh" 2>&1; echo "exit $?")
}
mkdir -p "${ROOT}/no-make" "${ROOT}/with-make"; printf 'check:\n\t@echo checked\n' > "${ROOT}/with-make/Makefile"
check "CI's make check fails, naming the missing target, when make has no check target" \
  $'::error::make has no check target; add one to the Makefile for CI to run\nexit 1' "$(make_check "${ROOT}/no-make")"
check "and runs it when there is one" $'checked\nexit 0' "$(make_check "${ROOT}/with-make")"
check "init warns that make has no check target" "yes" \
  "$(has "${out}" "make has no check target: add one to the Makefile; until then CI fails every change that is not board-only, and the hook checks nothing")"
check "init ends with the trust step" "yes" "$(grep -q 'run claude once in .* and accept the folder trust prompt' <<< "${out}" && echo yes || echo no)"
before="$(cd "${p}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | sort | xargs cksum)"
out="$(run "${p}" init || true)"
check "a second run copies nothing and says so" "yes" "$(has "${out}" "copied nothing: the board has every template file")"
check "a second run adds no line and says so" "yes" "$(has "${out}" ".gitignore already has every line")"
check "a second run changes no file" "${before}" \
  "$(cd "${p}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | sort | xargs cksum)"
check "a second run leaves the CI and the hook, naming them" "yes|yes" \
  "$(has "${out}" "left   .github/workflows/ci.yml (swarm-dev wrote it; delete it and run init again to rewrite it)")|$(has "${out}" "left   .git/hooks/pre-commit (swarm-dev wrote it)")"
check "init is logged" "init" "$(cut -f2 "${p}/.swarm/events.tsv" | sort -u)"
# A gate missing beside a ci.yml init wrote is written again.
rm "${p}/.github/swarm-board-only.sh"
run "${p}" init >/dev/null || true
check "a missing gate beside init's ci.yml is written again" "yes" "$(grep -qxF 'BOARD="docs/"' "${p}/.github/swarm-board-only.sh" && echo yes || echo no)"
# A ci.yml init wrote that no longer matches is still init's: left, with no step to add.
echo "# mine" >> "${p}/.github/workflows/ci.yml"
out="$(run "${p}" init || true)"
check "a changed ci.yml init wrote is left, and no gate step is printed" "yes|no" \
  "$(has "${out}" "left   .github/workflows/ci.yml (swarm-dev wrote it; delete it and run init again to rewrite it)")|$(grep -q 'add this step' <<< "${out}" && echo yes || echo no)"

# --- A board file the user changed is left, and named.
echo "mine" > "${p}/docs/stories/README.md"
rm "${p}/docs/Board.base"
out="$(run "${p}" init || true)"
check "a changed board file is not overwritten" "mine" "$(cat "${p}/docs/stories/README.md")"
check "the output names it as left" "yes" "$(has "${out}" "left   docs/stories/README.md (it exists)")"
check "a missing one is copied back" "yes" "$(has "${out}" "copied docs/Board.base")"

# --- board_dir = board: the files land in board/, and the .gitignore lines name it.
p="${ROOT}/custom"; "${GIT[@]}" init -q "${p}"; origin "${p}"
mkdir -p "${p}/.claude/swarm" && echo "board_dir = board" > "${p}/.claude/swarm/config"
run "${p}" init >/dev/null || true
check "board_dir = board puts the files in board/" "same|no docs" \
  "$(same "${TEMPLATES}" "${p}/board")|$([[ -e "${p}/docs" ]] && echo docs || echo no docs)"
check "the CI's skip names board/" "yes" "$(grep -qxF 'BOARD="board/"' "${p}/.github/swarm-board-only.sh" && echo yes || echo no)"
check "the commented commit_trailers line follows the config's own" $'board_dir = board\n# commit_trailers = Co-Authored-By: Your Name <you@example.com>' \
  "$(cat "${p}/.claude/swarm/config")"
check "the .gitignore lines name board/" $'.swarm/\nboard/.obsidian/*\n!board/.obsidian/app.json' "$(cat "${p}/.gitignore")"

# --- board_dir = .: the board is the repo root, so the lines and the listing are relative to it.
q="${ROOT}/dot"; "${GIT[@]}" init -q "${q}"; origin "${q}"
mkdir -p "${q}/.claude/swarm" && echo "board_dir = ." > "${q}/.claude/swarm/config"
echo mine > "${q}/notes.txt"
out="$(run "${q}" init || true)"
line="$(grep '^Commit what init wrote' <<< "${out}" || true)"
check "board_dir = . says to commit only what init wrote, not the repo's other files" "yes|no" \
  "$([[ "${line}" == *" stories/README.md"* ]] && echo yes || echo no)|$([[ "${line}" == *notes.txt* ]] && echo yes || echo no)"
check "board_dir = . names the lines without a path" $'.swarm/\n.obsidian/*\n!.obsidian/app.json' "$(cat "${q}/.gitignore")"
check "board_dir = . lists files relative to the root" "yes" "$(has "${out}" "copied stories/README.md")"
check "board_dir = . gates on the board's own files at the root" "yes|board_only=true|board_only=false" \
  "$(grep -qxF 'BOARD=""' "${q}/.github/swarm-board-only.sh" && echo yes)|$(gate "${q}" stories/a.md)|$(gate "${q}" src/main.go)"

# --- The gate skips only the board's own files: a docs page beside the board runs the checks.
q="${ROOT}/docs-pages"; "${GIT[@]}" init -q "${q}"; origin "${q}"
run "${q}" init >/dev/null || true
check "a PR that changes only docs/stories/ is board-only" "board_only=true" "$(gate "${q}" docs/stories/a.md)"
check "a PR that adds a docs page beside the board is not" "board_only=false" "$(gate "${q}" docs/guide.md)"
check "a push that opens a branch (an all-zero base) is not" "board_only=false" "$(gate "${q}" docs/stories/b.md 0000000000000000000000000000000000000000)"

# --- A board outside the repo: CI without the gate, and a hook that never skips.
q="${ROOT}/outside"; "${GIT[@]}" init -q "${q}"; origin "${q}"
mkdir -p "${q}/.claude/swarm" && echo "board_dir = ${ROOT}/vault" > "${q}/.claude/swarm/config"
out="$(run "${q}" init || true)"
check "a board outside the repo gets a CI with no gate or deep checkout, and a hook with / that says only make check" "yes|no|no|yes|yes" \
  "$(has "${out}" "wrote  .github/workflows/ci.yml (it runs make check)")|$(grep -qE 'gate|fetch-depth' "${q}/.github/workflows/ci.yml" && echo yes || echo no)|$([[ -e "${q}/.github/swarm-board-only.sh" ]] && echo yes || echo no)|$(grep -qxF 'swarm_board="/"' "${q}/.git/hooks/pre-commit" && echo yes)|$(has "${out}" "wrote  .git/hooks/pre-commit (it runs make check)")"

# --- The CI's push branch is origin's default, never the branch checked out; with no origin, no CI.
q="${ROOT}/trunk"; "${GIT[@]}" init -q -b feat "${q}"; origin "${q}" trunk
git -C "${q}" remote set-head origin -d
run "${q}" init >/dev/null || true
check "the CI's push branch is origin's default, asked of origin, not the branch checked out" "yes" \
  "$(grep -qF 'branches: ["trunk"]' "${q}/.github/workflows/ci.yml" && echo yes || echo no)"
q="${ROOT}/no-origin"; "${GIT[@]}" init -q "${q}"
out="$(run "${q}" init || true)"
check "with no origin, init writes no CI and says why" "yes|no" \
  "$(has "${out}" "wrote no CI: cannot tell origin's default branch; set origin, or make it reachable, and run init again")|$([[ -e "${q}/.github" ]] && echo yes || echo no)"
# An origin added but never fetched is asked for the HEAD it advertises.
q="${ROOT}/unfetched"; "${GIT[@]}" init -q "${q}"; origin "${q}" trunk
git -C "${q}" remote remove origin && git -C "${q}" remote add origin "${q}.git"
run "${q}" init >/dev/null || true
check "an origin never fetched is asked for its default branch" "yes" \
  "$(grep -qF 'branches: ["trunk"]' "${q}/.github/workflows/ci.yml" && echo yes || echo no)"
# A cached origin/HEAD is used as it is: origin is not asked.
q="${ROOT}/cached"; "${GIT[@]}" init -q "${q}"; origin "${q}" trunk
git -C "${q}" update-ref refs/remotes/origin/cached HEAD 2>/dev/null || git -C "${q}" update-ref refs/remotes/origin/cached refs/remotes/origin/trunk
git -C "${q}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/cached
run "${q}" init >/dev/null || true
check "a cached origin/HEAD names the push branch, and origin is not asked" "yes" \
  "$(grep -qF 'branches: ["cached"]' "${q}/.github/workflows/ci.yml" && echo yes || echo no)"
# An origin that never answers is given up on after SWARM_ORIGIN_ASK_SECONDS, and its transport (a
# child of git, as ssh would be) is killed with it.
q="${ROOT}/hangs"; "${GIT[@]}" init -q "${q}"
printf '#!/bin/sh\necho $$ > "%s"\nexec sleep 60\n' "${ROOT}/hang.pid" > "${ROOT}/hang.sh" && chmod +x "${ROOT}/hang.sh"
git -C "${q}" config protocol.ext.allow always && git -C "${q}" remote add origin "ext::${ROOT}/hang.sh"
started=${SECONDS}
out="$(SWARM_ORIGIN_ASK_SECONDS=2 run "${q}" init || true)"
check "an origin that hangs is given up on, its transport killed too, and init writes no CI" "yes|fast|gone" \
  "$(has "${out}" "wrote no CI: cannot tell origin's default branch; set origin, or make it reachable, and run init again")|$(if (( SECONDS - started < 20 )); then echo fast; else echo slow; fi)|$(if kill -0 "$(cat "${ROOT}/hang.pid")" 2>/dev/null; then echo alive; else echo gone; fi)"
# ssh is asked in BatchMode, so it never prompts, unless the user names their own ssh.
mkdir -p "${ROOT}/ssh-bin"; printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "${ROOT}/ssh.args" > "${ROOT}/ssh-bin/ssh"; chmod +x "${ROOT}/ssh-bin/ssh"
q="${ROOT}/over-ssh"; "${GIT[@]}" init -q "${q}"; git -C "${q}" remote add origin "ssh://example.invalid/x.git"
PATH="${ROOT}/ssh-bin:${PATH}" run "${q}" init >/dev/null || true
check "origin over ssh is asked in BatchMode" "yes" "$(grep -q -- '-o BatchMode=yes' "${ROOT}/ssh.args" 2>/dev/null && echo yes || echo no)"
: > "${ROOT}/ssh.args"; git -C "${q}" config core.sshCommand "ssh -o Mine=1"
PATH="${ROOT}/ssh-bin:${PATH}" run "${q}" init >/dev/null || true
check "with core.sshCommand set, init leaves the user's ssh as it is" "yes|no" \
  "$(grep -q -- '-o Mine=1' "${ROOT}/ssh.args" && echo yes || echo no)|$(grep -q BatchMode "${ROOT}/ssh.args" && echo yes || echo no)"

# --- The hook: a board-only commit skips make check; any other commit runs it.
q="${ROOT}/hooked"; "${GIT[@]}" init -q "${q}"
run "${q}" init >/dev/null || true
printf 'check:\n\t@echo checked; false\n' > "${q}/Makefile"
(cd "${q}" && "${GIT[@]}" add Makefile && "${GIT[@]}" commit -qm make --no-verify)
echo s > "${q}/docs/stories/s.md"
check "the hook lets a board-only commit through without make check" "ok" \
  "$(cd "${q}" && "${GIT[@]}" add -A docs && "${GIT[@]}" commit -qm board >/dev/null 2>&1 && echo ok || echo refused)"
echo c > "${q}/code.txt"
check "the hook runs make check on any other commit, and a failing check stops it" "refused" \
  "$(cd "${q}" && "${GIT[@]}" add code.txt && "${GIT[@]}" commit -qm code >/dev/null 2>&1 && echo ok || echo refused)"
rm "${q}/Makefile"
out="$( { cd "${q}" && "${GIT[@]}" add -A && "${GIT[@]}" commit -qm code 2>&1; } || true)"
check "with no check target, the hook warns and lets the commit through" "yes|yes" \
  "$(has "${out}" 'pre-commit: make has no check target, so nothing was checked; add one to the Makefile')|$([[ "$(git -C "${q}" log -1 --format=%s)" == code ]] && echo yes || echo no)"

# --- core.hooksPath set: no hook is written there, and the lines to add are printed.
q="${ROOT}/hookspath"; "${GIT[@]}" init -q "${q}"; mkdir -p "${q}/.githooks"
git -C "${q}" config core.hooksPath .githooks
out="$(run "${q}" init || true)"
check "with core.hooksPath set, init writes no hook and prints the lines to add" "no|no|yes|yes" \
  "$([[ -e "${q}/.githooks/pre-commit" ]] && echo yes || echo no)|$([[ -e "${q}/.git/hooks/pre-commit" ]] && echo yes || echo no)|$(has "${out}" "left   .githooks/pre-commit (core.hooksPath is .githooks); add these lines to it, before any exec (a line after one never runs):")|$(has "${out}" 'swarm_board="docs/"')"
# husky's core.hooksPath (.husky/_) is regenerated: the lines go in .husky/pre-commit, its user file.
q="${ROOT}/husky"; "${GIT[@]}" init -q "${q}"; mkdir -p "${q}/.husky/_"; git -C "${q}" config core.hooksPath .husky/_
out="$(run "${q}" init || true)"
check "with husky, init names .husky/pre-commit, not .husky/_/" "yes" \
  "$(has "${out}" "left   .husky/pre-commit (core.hooksPath is .husky/_); add these lines to it, before any exec (a line after one never runs):")"
# A global core.hooksPath runs in every repo: init says so, and prints no lines for it.
q="${ROOT}/global-hooks"; "${GIT[@]}" init -q "${q}"; printf '[core]\n\thooksPath = %s\n' "${ROOT}/global-hooks-dir" > "${ROOT}/gitconfig"
out="$(GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" run "${q}" init || true)"
check "with a global core.hooksPath, init writes no hook and says its lines belong in none there" "no|yes|no" \
  "$([[ -e "${ROOT}/global-hooks-dir/pre-commit" ]] && echo yes || echo no)|$(grep -q "set outside this repo): wrote no hook, since one there runs in every repo" <<< "${out}" && echo yes || echo no)|$(has "${out}" 'swarm_board="docs/"')"

# --- A repo with workflows: they are left, and the skip step is printed to add.
q="${ROOT}/workflows"; "${GIT[@]}" init -q "${q}"
mkdir -p "${q}/.github/workflows" && printf 'name: mine\n' > "${q}/.github/workflows/build.yml"
out="$(run "${q}" init || true)"
check "with workflows, init writes no ci.yml and leaves theirs" "no|name: mine" \
  "$([[ -e "${q}/.github/workflows/ci.yml" ]] && echo yes || echo no)|$(cat "${q}/.github/workflows/build.yml")"
# shellcheck disable=SC2016 # the workflow's own ${...}, matched literally
check "and prints the board-only step to add, for the checks' own job, with shell: bash" "yes|yes|yes|yes" \
  "$(grep -q "left   .github/workflows (it exists); add this step to the job that runs your checks" <<< "${out}" && echo yes)|$(has "${out}" "      - name: Skip a board-only change")|$(has "${out}" '        run: bash .github/swarm-board-only.sh')|$(has "${out}" '        shell: bash')"
check "and writes the gate that step runs" "yes" "$(grep -qxF 'BOARD="docs/"' "${q}/.github/swarm-board-only.sh" && echo yes || echo no)"

# --- An existing pre-commit hook stays byte for byte, and init prints the line to add.
q="${ROOT}/hook"; "${GIT[@]}" init -q "${q}"
printf '#!/bin/sh\ngitleaks protect --staged\n' > "${q}/.git/hooks/pre-commit"
hook="$(cksum < "${q}/.git/hooks/pre-commit")"
out="$(run "${q}" init || true)"
check "an existing pre-commit hook is left byte-identical" "${hook}" "$(cksum < "${q}/.git/hooks/pre-commit")"
check "and init prints the lines to add" "yes|yes" \
  "$(has "${out}" "left   .git/hooks/pre-commit (it exists); add these lines to it, before any exec (a line after one never runs):")|$(has "${out}" "  if make -n check >/dev/null 2>&1; then make check || exit 1")"

# --- A CRLF .gitignore that has every line already gets none of them again.
q="${ROOT}/crlf"; "${GIT[@]}" init -q "${q}"
printf '.swarm/\r\ndocs/.obsidian/*\r\n!docs/.obsidian/app.json\r\n' > "${q}/.gitignore"
crlf="$(cksum < "${q}/.gitignore")"
run "${q}" init >/dev/null || true
check "a CRLF .gitignore with every line is left as it is" "${crlf}" "$(cksum < "${q}/.gitignore")"

# --- Claude Code's settings: with no permissions.allow rule for swarm.sh merge in the user's settings
# (the stub CLAUDE_CONFIG_DIR) or the project's two files, init names the rule and the user's file. It
# reads only that list, so a token under env never reaches its output, and it changes no settings file.
q="${ROOT}/claude-rule"; "${GIT[@]}" init -q "${q}"; mkdir -p "${CLAUDE_CONFIG_DIR}" "${q}/.claude"
S_USER="${CLAUDE_CONFIG_DIR}/settings.json" S_PROJ="${q}/.claude/settings.json" S_LOCAL="${q}/.claude/settings.local.json"
printf '{"projects": {}}\n' > "${CLAUDE_CONFIG_DIR}/.claude.json"
STEP="Your step: add \"Bash(swarm.sh merge *)\" to permissions.allow in ${S_USER}. Under merge = agent, Claude Code refuses conductors every merge without it, and you merge each PR by hand."
TOKEN=ghp_initTestToken0123456789
# sums — the checksum of each settings file and .claude.json under the stub config dir and the project.
sums() { find "${CLAUDE_CONFIG_DIR}" "${q}/.claude" \( -name 'settings*.json' -o -name .claude.json \) -type f -exec cksum {} + | LC_ALL=C sort; }
changed=""
# rule_init <name> <user> <project> <local> — init in ${q} with these settings files (an empty one is
# left out), its output in ${out}; a settings file that init changes or adds puts <name> in ${changed}.
rule_init() {
  local f before i=2
  for f in "${S_USER}" "${S_PROJ}" "${S_LOCAL}"; do
    if [[ -n "${!i}" ]]; then printf '%s\n' "${!i}" > "${f}"; else rm -f "${f}"; fi
    i=$((i + 1))
  done
  before="$(sums)"; out="$(run "${q}" init || true)"
  [[ "$(sums)" == "${before}" ]] || changed+=" $1"
}
rule_init user '{"permissions": {"allow": ["Bash(git status)", "Bash(swarm.sh merge *)"]}}' "" ""
check "with the rule in the user's settings, init prints no merge-rule step" "no" \
  "$(grep -q 'permissions.allow' <<< "${out}" && echo yes || echo no)"
rule_init absent '{"permissions": {"allow": ["Bash(swarm.sh status *)", "Bash(swarm.sh merge)", "Bash(swarm.sh merge --head *)"]}}' '{"permissions": {}}' ""
check "with no rule that lets swarm.sh merge run, init names the rule, the user's file and the files it read, before the trust step" "yes|yes|yes" \
  "$(has "${out}" "${STEP}")|$(has "${out}" "Claude Code's settings have no permissions.allow rule that lets swarm.sh merge run (read ${S_USER}, .claude/settings.json, .claude/settings.local.json).")|$(tail -1 <<< "${out}" | grep -q '^Last step: run claude once' && echo yes || echo no)"
rule_init local '{"permissions": {"allow": ["Bash(git status)"]}}' '{"permissions": {"allow": []}}' '{"permissions": {"allow": ["Bash(swarm.sh merge *)"]}}'
check "with the rule only in .claude/settings.local.json, init prints no merge-rule step" "no" \
  "$(grep -q 'permissions.allow' <<< "${out}" && echo yes || echo no)"
rule_init split '{"permissions": {"allow": ["Bash(swarm.sh merge --head *)"]}}' "" '{"permissions": {"allow": ["Bash(swarm.sh merge --board *)"]}}'
check "a --head rule in one file and a --board rule in another count as the rule together" "no" \
  "$(grep -q 'permissions.allow' <<< "${out}" && echo yes || echo no)"
rule_init legacy "" '{"permissions": {"allow": ["Bash(swarm.sh merge:*)"]}}' ""
check "the older :* form in .claude/settings.json counts as the rule" "no" \
  "$(grep -q 'permissions.allow' <<< "${out}" && echo yes || echo no)"
rule_init token "{\"env\": {\"GITHUB_TOKEN\": \"${TOKEN}\"}, \"permissions\": {\"allow\": [\"Bash(curl -u ${TOKEN} *)\"]}}" "{\"env\": {\"API_KEY\": \"${TOKEN}\"" ""   # vacuous-test: ok, the project's file is not JSON on purpose
check "a settings file's env token never reaches init's output, and a broken file counts as no rule" "yes|no" \
  "$(has "${out}" "${STEP}")|$(grep -qF "${TOKEN}" <<< "${out}" && echo yes || echo no)"
check "init changes no settings file and adds none" "" "${changed}"

# --- Auto mode's setup: until the user's settings hold a non-empty autoMode.environment (the list
# /auto-mode-setup writes) or the user ran init --auto-mode-done, init prints the step. Claude Code takes
# autoMode from no project settings file, so one there is no record. --auto-mode-done writes the date
# to .swarm/auto-mode-done and nothing outside .swarm/.
q="${ROOT}/auto-mode"; "${GIT[@]}" init -q "${q}"; mkdir -p "${q}/.claude"
AM_STEP="Your step: run /auto-mode-setup once in claude, so no agent's pane stops on the 'Teach auto mode' dialog. Then run swarm.sh init --auto-mode-done here, and init stops printing this step."
am_step() { grep -q 'auto-mode-setup' <<< "$1" && echo yes || echo no; }
printf '{"permissions": {"allow": ["Bash(swarm.sh merge *)"]}, "autoMode": {"environment": []}}\n' > "${S_USER}"
printf '{"autoMode": {"environment": ["Source control: github.com/o"]}}\n' > "${q}/.claude/settings.local.json"
out="$(run "${q}" init || true)"
check "with an empty autoMode.environment and one only in the project's settings, init prints the auto mode step and the --auto-mode-done command, before the trust step" "yes|yes" \
  "$(has "${out}" "${AM_STEP}")|$(tail -1 <<< "${out}" | grep -q '^Last step: run claude once' && echo yes || echo no)"
printf '{"autoMode": {"environment": ["Source control: github.com/o"]}}\n' > "${S_USER}"
out="$(run "${q}" init || true)"
check "with autoMode.environment in the user's settings, init prints no auto mode step" "no" "$(am_step "${out}")"
printf '{"autoMode": {"environment": []}}\n' > "${S_USER}"
# outside_swarm — the checksum of every file in the project outside .git/ and .swarm/, and in the stub
# config dir, which holds the user's settings and .claude.json.
outside_swarm() {
  { (cd "${q}" && find . \( -path ./.git -o -path ./.swarm \) -prune -o -type f -exec cksum {} +)
    find "${CLAUDE_CONFIG_DIR}" -type f -exec cksum {} +; } | LC_ALL=C sort
}
before="$(outside_swarm)"; run "${q}" init --auto-mode-done >/dev/null || true
check "init --auto-mode-done writes today's date to .swarm/auto-mode-done and changes no file outside .swarm/, settings files included" \
  "$(date +%F)|yes" "$(cat "${q}/.swarm/auto-mode-done" 2>/dev/null || true)|$([[ "$(outside_swarm)" == "${before}" ]] && echo yes || echo no)"
out="$(run "${q}" init || true)"
check "after init --auto-mode-done, init prints no auto mode step" "no" "$(am_step "${out}")"
out="$(run "${q}" init --auto-mode || true)"
check "init with an argument it does not know refuses with its usage" "yes" "$(has "${out}" "swarm: usage: swarm.sh init [--auto-mode-done]")"

# --- Refusals: a subdirectory names the root; outside git names that.
mkdir -p "${p}/sub"
out="$(run "${p}/sub" init || true)"
check "from a subdirectory it refuses, naming the root" "yes" "$(has "${out}" "swarm: init: run it from the root of the git repo, ${p}")"
check "and writes nothing there" "no" "$([[ -e "${p}/sub/docs" || -e "${p}/sub/board" ]] && echo yes || echo no)"
# With no config, the project is the subdirectory itself, so a logged refusal would land in it.
q="${ROOT}/bare"; "${GIT[@]}" init -q "${q}"; mkdir -p "${q}/sub"
out="$(run "${q}/sub" init || true)"
check "from a subdirectory of a repo with no config it refuses" "yes" "$(has "${out}" "swarm: init: run it from the root of the git repo, ${q}")"
check "and writes nothing at all, not even the log" $'.\n./sub' "$(cd "${q}" && find . -path ./.git -prune -o -print | sort)"
mkdir -p "${ROOT}/plain"
out="$(run "${ROOT}/plain" init || true)"
check "outside git it refuses, saying so" "yes" "$(grep -q 'not in a git repo' <<< "${out}" && echo yes || echo no)"
check "and writes nothing" "" "$(ls -A "${ROOT}/plain")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
