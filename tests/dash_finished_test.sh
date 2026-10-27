#!/usr/bin/env bash
# dash_finished_test.sh — bin/lib/dash_finished.py on a fixture repo whose board is board/: a commit
# that deletes a story file and changes only the board's own files (hld/, .obsidian/) is not the
# story's own work, so the story does not count as finished; one that also changes code does, and so
# does one that changes board/README.md.bak (the board's own README.md is that file alone). Each story
# is in an epic of its own, so the epic on an output row names the story that counted.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

FINISHED="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib/dash_finished.py"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
Q="${ROOT}/repo"; B="${Q}/board"
GQ=(git -C "${Q}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
mkdir -p "${B}/stories" "${B}/hld" "${B}/.obsidian" "${Q}/src"
git -C "${Q}" init -q -b main

# story <slug> — a ready story in epic e-<slug>, no prs:, so only its deleting commit can finish it.
story() { printf -- '---\nstatus: ready\nepic: e-%s\nkind: code\n---\n\n# %s\n' "$1" "$1" > "${B}/stories/$1.md"; }
story s-hld; story s-obs; story s-code; story s-bak
echo "# HLD" > "${B}/hld/plan.md"; echo '{}' > "${B}/.obsidian/app.json"; echo 1 > "${Q}/src/a"
"${GQ[@]}" add -A && "${GQ[@]}" commit -qm "seed"
# Each deletion beside one other change, under a subject that names no branch.
"${GQ[@]}" rm -q board/stories/s-hld.md; echo "more" >> "${B}/hld/plan.md"; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Edit the plan"
"${GQ[@]}" rm -q board/stories/s-obs.md; echo '{"a":1}' > "${B}/.obsidian/app.json"; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Tidy the vault"
"${GQ[@]}" rm -q board/stories/s-code.md; echo 2 > "${Q}/src/a"; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Ship s-code"
"${GQ[@]}" rm -q board/stories/s-bak.md; echo "old" > "${B}/README.md.bak"; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Ship s-bak"

out="$(python3 "${FINISHED}" "${B}" board/ HEAD "${ROOT}/no-events.tsv")"
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; printf '     %s\n' "${out}"; fails=$((fails + 1)); fi
}
row() { [[ "$(awk -F'\t' -v e="e-$1" '$1 == "story" && $2 == e' <<< "${out}" | wc -l | tr -d ' ')" -eq "$2" ]]; }
check "a commit that also changes code finishes its story" row s-code 1
check "a commit that changes only hld/ finishes no story" row s-hld 0
check "a commit that changes only .obsidian/ finishes no story" row s-obs 0
check "a commit that changes board/README.md.bak finishes its story" row s-bak 1
# Newest first, one row each, and nothing else: empty output fails here too.
check "only the code commits' stories are counted" [ "${out}" == "$(printf 'story\te-s-bak\tcode\t-\nstory\te-s-code\tcode\t-')" ]

[[ ${fails} -eq 0 ]]
