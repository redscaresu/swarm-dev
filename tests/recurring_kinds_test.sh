#!/usr/bin/env bash
# recurring_kinds_test.sh — the block `swarm.sh outcomes` prints after its rows: kinds fixed on 3 or
# more PRs in the last 30 days. A fixture with two kinds on 3 PRs, one on 2 and one whose third PR is
# 40 days old flags only the first two. Once a story with `checks:` for a kind merged (deleted on
# origin/HEAD, as story_text finds a merged story), its PRs in the 30 days before and since that day
# print, since marked with the days it covers while fewer than 30 have passed.
# Rows of 4, 6 and 7 fields count, a bogus reviewer's row does not, and a non-UTF-8 byte breaks nothing.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects" "${dir}/bin"
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/gh"; chmod +x "${dir}/bin/gh"
ago() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }
# OLD: a 20th at least 35 days ago, so the 30 days from it are over and hold a month's end; BAD is
# that month's day 32, which a date compared as text would count.
OLD="$(python3 -c 'import datetime as d; x = d.date.today() - d.timedelta(days=35)
print((x if x.day >= 20 else x.replace(day=1) - d.timedelta(days=1)).replace(day=20))')"
BAD="${OLD:0:8}32"
git -C "${P}" init -q
commit() { git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$1"; }
merged() { git -C "${P}" update-ref refs/remotes/origin/main HEAD; }   # origin/HEAD is now HEAD
printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/a-note.md"
echo '# Stories' > "${P}/docs/stories/README.md"   # the board outlives its stories
git -C "${P}" add -A && commit board
git -C "${P}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main && merged
printf '%s\n' $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts9' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  "$(ago 29)"$'\tvacuous-test\to/r#1\t29 days old: inside the window' \
  "$(ago 18)"$'\tvacuous-test\thttps://github.com/o/r/pull/1\tthe same PR again\tfixed\tcodex' \
  "$(ago 15)"$'\tvacuous-test\to/r#2\tb\tfixed\tcodex' \
  "$(ago 5)"$'\tvacuous-test\to/r#3\tc\tescaped\tunknown' \
  "$(ago 4)"$'\tvacuous-test\to/r#4\tdeclined, no lesson\tdeclined\tcodex' \
  "$(ago 30)"$'\tvacuous-test\to/r#10\t30 days old: outside the window' \
  "$(ago -1)"$'\tvacuous-test\to/r#11\tfuture' \
  "$(ago 3)"$'\tmissing-check\to/r#20\ta' \
  "$(ago 2)"$'\tmissing-check\to/r#21\tb' \
  "$(ago 1)"$'\tmissing-check\to/r#22\tc' \
  "$(python3 -c 'import datetime, sys; print(datetime.date.fromisoformat(sys.argv[1]) - datetime.timedelta(days=5))' "${OLD}")"$'\tmissing-check\to/r#23\tbefore its check' \
  "${BAD}"$'\tmissing-check\to/r#24\timpossible' \
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
UNCHECKED="$(printf '%s\n' "${HEAD}" $'missing-check\t3\t\t\t\t' $'vacuous-test\t3\t\t\t\t')"

check "only the kinds on 3 PRs in 30 days are flagged (a PR logged twice counts once; declined, impossible and future rows not at all)" \
  "$(block)" "${UNCHECKED}"
check "the 30 days end today: a fix 29 days old counts, one 30 days old does not" \
  "$(block | awk -F'\t' '$1 == "vacuous-test" { print $2 }')" 3

printf -- '---\nkind: code\nstatus: ready\nchecks: vacuous-test\n---\n' > "${P}/docs/stories/vacuous-check.md"
printf -- '---\nkind: code\nstatus: ready\nchecks: missing-check\n---\n' > "${P}/docs/stories/missing check.md"
git -C "${P}" add -A && commit add && merged
check "a check story still on the board shows no counts" "$(block)" "${UNCHECKED}"
# One commit deletes the spaced check story and a story without checks: (which sorts first).
git -C "${P}" rm -q "docs/stories/missing check.md" docs/stories/a-note.md
GIT_COMMITTER_DATE="${OLD}T12:00:00" commit merged-old && merged
# The story branch deletes vacuous-check beside a new story much like it (a rename, to git's eye), 12
# days ago; main merges it with a merge commit 10 days ago.
base="$(git -C "${P}" symbolic-ref --short HEAD)"
git -C "${P}" checkout -q -b story/vacuous
git -C "${P}" rm -q docs/stories/vacuous-check.md
printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/vacuous-next.md"
git -C "${P}" add -A && GIT_COMMITTER_DATE="$(ago 12)T12:00:00" commit story-deletes
check "a check story deleted only on the local branch, not on origin/HEAD, shows no counts" \
  "$(block | grep '^vacuous-test')" $'vacuous-test\t3\t\t\t\t'
git -C "${P}" checkout -q "${base}"
GIT_COMMITTER_DATE="$(ago 10)T12:00:00" git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
  merge -q --no-ff -m merged-recent story/vacuous && merged
check "a merged check story (a path with a space, deleted beside a story without checks:) shows its PRs in the 30 days before and since; an impossible date counts in neither" \
  "$(block | grep '^missing-check')" $'missing-check\t3\tmissing check\t'"${OLD}"$'\t1\t0'
VACUOUS=$'vacuous-test\t3\tvacuous-check\t'"$(ago 10)"$'\t3\t1/11d'
check "fewer than 30 days after the merge, since_30d shows the days it covers, and a future fix is not counted" \
  "$(block | grep '^vacuous-test')" "${VACUOUS}"
check "a check story deleted beside a similar new one still counts, dated by the merge commit, not the branch's" \
  "$(block | grep '^vacuous-test' | cut -f3,4)" "vacuous-check"$'\t'"$(ago 10)"
git -C "${P}" symbolic-ref --delete refs/remotes/origin/HEAD
check "with no origin/HEAD (a clone that never set it), HEAD is read" "$(block | grep '^vacuous-test')" "${VACUOUS}"

# fixed_rows reads rows of any width from four fields up: a later column drops no row, an unknown
# reviewer is read, and a bad one drops the row. A stray non-UTF-8 byte breaks nothing.
for w in 'o/r#101\tx' 'o/r#102\tx\tfixed\tcodex' 'o/r#103\tx\tfixed\tunknown\ta later column'; do
  printf '%s\twide\t%b\n' "$(ago 1)" "${w}" >> "${P}/.swarm/findings.tsv"
  printf '%s\twide-bogus\t%b\n' "$(ago 1)" "${w/codex/bogus}" >> "${P}/.swarm/findings.tsv"
done
for n in 1 2 3; do printf '%s\tbytes\to/r#11%s\tbad \xff byte\n' "$(ago 1)" "${n}" >> "${P}/.swarm/findings.tsv"; done
check "4-, 6- and 7-field rows all count, a bogus reviewer drops its row, and a non-UTF-8 byte breaks nothing" \
  "$(block | grep -E $'^(wide|wide-bogus|bytes)\t')" "$(printf '%s\n' $'bytes\t3\t\t\t\t' $'wide\t3\t\t\t\t')"

echo "${fails} failure(s)"
[[ "${fails}" -eq 0 ]]
