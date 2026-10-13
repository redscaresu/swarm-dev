#!/usr/bin/env bash
# init_test.sh — swarm.sh init in throwaway git repos: the board from the plugin's templates, never
# over a file that exists, .claude/swarm/, the .gitignore lines, a second run that changes nothing,
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
check "init ends with the trust step" "yes" "$(grep -q 'run claude once in .* and accept the folder trust prompt' <<< "${out}" && echo yes || echo no)"
before="$(cd "${p}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | sort | xargs cksum)"
out="$(run "${p}" init || true)"
check "a second run copies nothing and says so" "yes" "$(has "${out}" "copied nothing: the board has every template file")"
check "a second run adds no line and says so" "yes" "$(has "${out}" ".gitignore already has every line")"
check "a second run changes no file" "${before}" \
  "$(cd "${p}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | sort | xargs cksum)"
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
check "the .gitignore lines name board/" $'.swarm/\nboard/.obsidian/*\n!board/.obsidian/app.json' "$(cat "${p}/.gitignore")"

# --- board_dir = .: the board is the repo root, so the lines and the listing are relative to it.
q="${ROOT}/dot"; "${GIT[@]}" init -q "${q}"
mkdir -p "${q}/.claude/swarm" && echo "board_dir = ." > "${q}/.claude/swarm/config"
out="$(run "${q}" init || true)"
check "board_dir = . names the lines without a path" $'.swarm/\n.obsidian/*\n!.obsidian/app.json' "$(cat "${q}/.gitignore")"
check "board_dir = . lists files relative to the root" "yes" "$(has "${out}" "copied stories/README.md")"

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
