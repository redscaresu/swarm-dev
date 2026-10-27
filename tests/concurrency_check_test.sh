#!/usr/bin/env bash
# concurrency_check_test.sh — next's idle dependency line (touches_rows.py --idle): a blocked story's
# dependency is named over-broad only when they share no touches part (clash-by-part's rule) and the
# story's needs: does not name it; and commands/swarm.md quotes the line the check prints.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# idle <b's touches> [b's extra front-matter line] — what --idle prints for a board of two stories:
# a, ready, touching x.sh:f run and y.sh; b, blocked on a.
idle() {
  local dir
  dir="$(mktemp -d "${ROOT}/case.XXXXXX")"
  mkdir -p "${dir}/stories" "${dir}/state" "${dir}/repos"
  printf -- '---\nstatus: ready\nkind: code\ntouches: [x.sh:f run, y.sh]\n---\n\n# a\n' > "${dir}/stories/a.md"
  { printf -- '---\nstatus: blocked\nkind: code\ndepends_on: [a]\ntouches: [%s]\n' "$1"
    if [[ -n "${2:-}" ]]; then echo "$2"; fi
    printf -- '---\n\n# b\n'; } > "${dir}/stories/b.md"
  SWARM_AGENT_KINDS="code docs chore" python3 "${REPO}/bin/lib/touches_rows.py" \
    "${dir}/stories" --idle "${dir}" "${dir}/repos" "${dir}/state"
}
LINE="idle: b waits on a but shares no touches part with it and needs nothing from it"

check "a dependency sharing a part (same file, same first word) gives no line" "" "$(idle "x.sh:f check")"
check "a dependency sharing the file with other parts gives the line" "${LINE}" "$(idle "x.sh:g")"
check "a dependency that shares nothing but is named in needs gives no line" "" "$(idle "c.sh" "needs: a (its run flag)")"
check "a needs: line that names another story leaves the line" "${LINE}" "$(idle "c.sh" "needs: z (its run flag)")"

# swarm.md's next idle list quotes the line --idle prints, with <story> and <dep> for the slugs:
# compared with the line itself, as printed for a disjoint pair, not with LINE above.
# shellcheck disable=SC2016 # backticks are the Markdown's, never expanded
# `|| true`: with no such quote, grep's exit 1 under pipefail would end the script with no FAIL line.
quoted="$(grep -o '`idle: <story> waits on <dep>[^`]*`' "${REPO}/commands/swarm.md" | head -1 | tr -d '`' || true)"
if [[ -z "${quoted}" ]]; then echo "FAIL commands/swarm.md quotes the line touches_rows.py prints: no \`idle: <story> waits on <dep> ...\` quote in it"; fails=$((fails + 1))
else check "commands/swarm.md quotes the line touches_rows.py prints" "$(idle "c.sh")" "$(sed 's/<story>/b/; s/<dep>/a/' <<< "${quoted}")"; fi

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
