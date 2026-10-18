#!/usr/bin/env bash
# init_test.sh — swarm.sh init in throwaway git repos: the board from the plugin's templates, never
# over a file that exists, .claude/swarm/ with a commented commit_trailers line, the .gitignore
# lines, a CI workflow with a board-only skip, a pre-commit hook, a second run that changes nothing,
# board_dir, and the refusals outside a repo's root.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
TEMPLATES="$(dirname "${SWARM}")/../templates/docs"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
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

# --- A fresh repo: every template file, .claude/swarm/, the three lines; the second run changes nothing.
p="${ROOT}/fresh"; "${GIT[@]}" init -q "${p}"
printf 'node_modules/' > "${p}/.gitignore"   # no trailing newline: the first added line must not join it
out="$(run "${p}" init || true)"
check "init copies every template file" "same" "$(same "${TEMPLATES}" "${p}/docs")"
check "init creates .claude/swarm/" "yes" "$([[ -d "${p}/.claude/swarm" ]] && echo yes || echo no)"
check "init adds the three .gitignore lines after the existing one" \
  $'node_modules/\n.swarm/\ndocs/.obsidian/*\n!docs/.obsidian/app.json' "$(cat "${p}/.gitignore")"
check "init adds a commented commit_trailers line" "# commit_trailers = Co-Authored-By: Your Name <you@example.com>" \
  "$(cat "${p}/.claude/swarm/config")"
check "init writes a CI that skips a board-only PR and otherwise runs make check, on pushes to main" "yes|yes|yes|yes" \
  "$(grep -qF 'BOARD: "docs/"' "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qF 'if: steps.gate.outputs.board_only != '"'true'" "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qF 'then make check;' "${p}/.github/workflows/ci.yml" && echo yes)|$(grep -qF 'branches: ["main"]' "${p}/.github/workflows/ci.yml" && echo yes)"
check "init writes an executable pre-commit hook for docs/" "yes|yes" \
  "$(grep -qxF 'swarm_board="docs/"' "${p}/.git/hooks/pre-commit" && echo yes)|$([[ -x "${p}/.git/hooks/pre-commit" ]] && echo yes)"
# gate <repo> <path> — the CI gate's verdict on a PR that adds <path> in <repo>, run as CI would.
gate() {
  local base
  sed -n '/id: gate/,/- name: make check/p' "$1/.github/workflows/ci.yml" | sed -n '/run: |/,$p' | sed '1d;$d' \
    | sed 's/^          //' > "${ROOT}/gate.sh"
  base="$(cd "$1" && "${GIT[@]}" add -A && "${GIT[@]}" commit -q --allow-empty -m base --no-verify && git rev-parse HEAD)"
  mkdir -p "$(dirname "$1/$2")" && echo x > "$1/$2"
  (cd "$1" && "${GIT[@]}" add -A && "${GIT[@]}" commit -qm pr --no-verify \
    && BOARD="$(sed -n 's/^ *BOARD: "\(.*\)"$/\1/p' .github/workflows/ci.yml)" BASE_SHA="${base}" GITHUB_OUTPUT=/dev/stdout bash "${ROOT}/gate.sh")
}
check "init ends with the trust step" "yes" "$(grep -q 'run claude once in .* and accept the folder trust prompt' <<< "${out}" && echo yes || echo no)"
before="$(cd "${p}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | sort | xargs cksum)"
out="$(run "${p}" init || true)"
check "a second run copies nothing and says so" "yes" "$(has "${out}" "copied nothing: the board has every template file")"
check "a second run adds no line and says so" "yes" "$(has "${out}" ".gitignore already has every line")"
check "a second run changes no file" "${before}" \
  "$(cd "${p}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | sort | xargs cksum)"
check "a second run leaves the CI and the hook, naming them" "yes|yes" \
  "$(has "${out}" "left   .github/workflows/ci.yml (swarm-dev wrote it)")|$(has "${out}" "left   .git/hooks/pre-commit (swarm-dev wrote it)")"
check "init is logged" "init" "$(cut -f2 "${p}/.swarm/events.tsv" | sort -u)"

# --- A board file the user changed is left, and named.
echo "mine" > "${p}/docs/stories/README.md"
rm "${p}/docs/Board.base"
out="$(run "${p}" init || true)"
check "a changed board file is not overwritten" "mine" "$(cat "${p}/docs/stories/README.md")"
check "the output names it as left" "yes" "$(has "${out}" "left   docs/stories/README.md (it exists)")"
check "a missing one is copied back" "yes" "$(has "${out}" "copied docs/Board.base")"

# --- board_dir = board: the files land in board/, and the .gitignore lines name it.
p="${ROOT}/custom"; "${GIT[@]}" init -q "${p}"
mkdir -p "${p}/.claude/swarm" && echo "board_dir = board" > "${p}/.claude/swarm/config"
run "${p}" init >/dev/null || true
check "board_dir = board puts the files in board/" "same|no docs" \
  "$(same "${TEMPLATES}" "${p}/board")|$([[ -e "${p}/docs" ]] && echo docs || echo no docs)"
check "the CI's skip names board/" "yes" "$(grep -qF 'BOARD: "board/"' "${p}/.github/workflows/ci.yml" && echo yes || echo no)"
check "the commented commit_trailers line follows the config's own" $'board_dir = board\n# commit_trailers = Co-Authored-By: Your Name <you@example.com>' \
  "$(cat "${p}/.claude/swarm/config")"
check "the .gitignore lines name board/" $'.swarm/\nboard/.obsidian/*\n!board/.obsidian/app.json' "$(cat "${p}/.gitignore")"

# --- board_dir = .: the board is the repo root, so the lines and the listing are relative to it.
q="${ROOT}/dot"; "${GIT[@]}" init -q "${q}"
mkdir -p "${q}/.claude/swarm" && echo "board_dir = ." > "${q}/.claude/swarm/config"
out="$(run "${q}" init || true)"
check "board_dir = . names the lines without a path" $'.swarm/\n.obsidian/*\n!.obsidian/app.json' "$(cat "${q}/.gitignore")"
check "board_dir = . lists files relative to the root" "yes" "$(has "${out}" "copied stories/README.md")"
check "board_dir = . gates on the board's own files at the root" "yes|board_only=true|board_only=false" \
  "$(grep -qF 'BOARD: ""' "${q}/.github/workflows/ci.yml" && echo yes)|$(gate "${q}" stories/a.md)|$(gate "${q}" src/main.go)"

# --- The gate skips only the board's own files: a docs page beside the board runs the checks.
q="${ROOT}/docs-pages"; "${GIT[@]}" init -q "${q}"
run "${q}" init >/dev/null || true
check "a PR that changes only docs/stories/ is board-only" "board_only=true" "$(gate "${q}" docs/stories/a.md)"
check "a PR that adds a docs page beside the board is not" "board_only=false" "$(gate "${q}" docs/guide.md)"

# --- A board outside the repo: CI without the gate, and a hook that never skips.
q="${ROOT}/outside"; "${GIT[@]}" init -q "${q}"
mkdir -p "${q}/.claude/swarm" && echo "board_dir = ${ROOT}/vault" > "${q}/.claude/swarm/config"
out="$(run "${q}" init || true)"
check "a board outside the repo gets a CI with no gate, and a hook with /" "yes|no|yes" \
  "$(has "${out}" "wrote  .github/workflows/ci.yml (it runs make check)")|$(grep -qE 'id: gate|steps.gate' "${q}/.github/workflows/ci.yml" && echo yes || echo no)|$(grep -qxF 'swarm_board="/"' "${q}/.git/hooks/pre-commit" && echo yes)"

# --- The CI's push branch is the branch checked out when origin has no HEAD.
q="${ROOT}/trunk"; git -c init.defaultBranch=trunk init -q "${q}"
run "${q}" init >/dev/null || true
check "the CI's push branch is the repo's own" "yes" "$(grep -qF 'branches: ["trunk"]' "${q}/.github/workflows/ci.yml" && echo yes || echo no)"

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

# --- core.hooksPath set: no hook is written there, and the lines to add are printed.
q="${ROOT}/hookspath"; "${GIT[@]}" init -q "${q}"; mkdir -p "${q}/.githooks"
git -C "${q}" config core.hooksPath .githooks
out="$(run "${q}" init || true)"
check "with core.hooksPath set, init writes no hook and prints the lines to add" "no|no|yes|yes" \
  "$([[ -e "${q}/.githooks/pre-commit" ]] && echo yes || echo no)|$([[ -e "${q}/.git/hooks/pre-commit" ]] && echo yes || echo no)|$(has "${out}" "left   .githooks/pre-commit (core.hooksPath is .githooks); add these lines to it:")|$(has "${out}" 'swarm_board="docs/"')"

# --- A repo with workflows: they are left, and the skip step is printed to add.
q="${ROOT}/workflows"; "${GIT[@]}" init -q "${q}"
mkdir -p "${q}/.github/workflows" && printf 'name: mine\n' > "${q}/.github/workflows/build.yml"
out="$(run "${q}" init || true)"
check "with workflows, init writes no ci.yml and leaves theirs" "no|name: mine" \
  "$([[ -e "${q}/.github/workflows/ci.yml" ]] && echo yes || echo no)|$(cat "${q}/.github/workflows/build.yml")"
check "and prints the board-only step to add, for the checks' own job, with shell: bash" "yes|yes|yes|yes" \
  "$(grep -q "left   .github/workflows (it exists); add this step to the job that runs your checks" <<< "${out}" && echo yes)|$(has "${out}" "      - name: Skip a board-only PR")|$(has "${out}" '          BOARD: "docs/"')|$(has "${out}" '        shell: bash')"

# --- An existing pre-commit hook stays byte for byte, and init prints the line to add.
q="${ROOT}/hook"; "${GIT[@]}" init -q "${q}"
printf '#!/bin/sh\ngitleaks protect --staged\n' > "${q}/.git/hooks/pre-commit"
hook="$(cksum < "${q}/.git/hooks/pre-commit")"
out="$(run "${q}" init || true)"
check "an existing pre-commit hook is left byte-identical" "${hook}" "$(cksum < "${q}/.git/hooks/pre-commit")"
check "and init prints the lines to add" "yes|yes" \
  "$(has "${out}" "left   .git/hooks/pre-commit (it exists); add these lines to it:")|$(has "${out}" "  if [ -f Makefile ] && grep -q '^check:' Makefile; then make check || exit 1; fi")"

# --- A CRLF .gitignore that has every line already gets none of them again.
q="${ROOT}/crlf"; "${GIT[@]}" init -q "${q}"
printf '.swarm/\r\ndocs/.obsidian/*\r\n!docs/.obsidian/app.json\r\n' > "${q}/.gitignore"
crlf="$(cksum < "${q}/.gitignore")"
run "${q}" init >/dev/null || true
check "a CRLF .gitignore with every line is left as it is" "${crlf}" "$(cksum < "${q}/.gitignore")"

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
