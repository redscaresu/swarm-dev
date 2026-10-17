#!/usr/bin/env bash
# recurring_kinds_test.sh — the block `swarm.sh outcomes` prints after its rows: kinds fixed on 3 or
# more PRs in the last 30 days. A fixture with a kind on 3 PRs (one PR logged twice), one on 2 and one
# whose third PR is older than 30 days flags only the first; once a story with `checks:` for it has
# merged (deleted from the board, as story_text finds it), its PRs before and since that day print.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects" "${dir}/bin"
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/gh"; chmod +x "${dir}/bin/gh"
ago() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }
git -C "${P}" init -q
commit() { git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$1"; }
printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/other.md"
git -C "${P}" add -A && commit board
printf '%s\n' $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts9' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  "$(ago 20)"$'\tvacuous-test\to/r#1\ta' \
  "$(ago 18)"$'\tvacuous-test\thttps://github.com/o/r/pull/1\tthe same PR again\tfixed\tcodex' \
  "$(ago 15)"$'\tvacuous-test\to/r#2\tb\tfixed\tcodex' \
  "$(ago 5)"$'\tvacuous-test\to/r#3\tc\tescaped\tunknown' \
  "$(ago 4)"$'\tvacuous-test\to/r#4\tdeclined, no lesson\tdeclined\tcodex' \
  "$(ago 3)"$'\ttwo-prs\to/r#5\td' \
  "$(ago 2)"$'\ttwo-prs\to/r#6\te' \
  "$(ago 40)"$'\tstale\to/r#7\tf' \
  "$(ago 10)"$'\tstale\to/r#8\tg' \
  "$(ago 9)"$'\tstale\to/r#9\th' > "${P}/.swarm/findings.tsv"

block() { # the lines after the rows' blank line
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
    bash "${SWARM}" outcomes | sed '1,/^$/d')
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
HEAD=$'recurring\tprs_30d\tcheck\tcheck_merged\tbefore_30d\tsince_30d'

check "only the kind on 3 PRs in 30 days is flagged (a PR logged twice counts once, a declined one not at all)" \
  "$(block)" "$(printf '%s\n' "${HEAD}" $'vacuous-test\t3\t\t\t\t')"

# A check story still on the board has not merged; deleting it (its PR merging) 10 days ago does.
printf -- '---\nkind: code\nstatus: ready\nchecks: vacuous-test\n---\n' > "${P}/docs/stories/vacuous-check.md"
git -C "${P}" add -A && commit add
check "a check story still on the board shows no counts" \
  "$(block)" "$(printf '%s\n' "${HEAD}" $'vacuous-test\t3\t\t\t\t')"
git -C "${P}" rm -q docs/stories/vacuous-check.md
GIT_COMMITTER_DATE="$(ago 10)T12:00:00" commit merged
check "once its checks: story merged, its PRs in the 30 days before and since that day print" \
  "$(block)" "$(printf '%s\n' "${HEAD}" $'vacuous-test\t3\tvacuous-check\t'"$(ago 10)"$'\t2\t1')"

echo "${fails} failure(s)"
[[ "${fails}" -eq 0 ]]
