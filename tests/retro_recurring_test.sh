#!/usr/bin/env bash
# retro_recurring_test.sh — retro's recurring section over a fixture project tagged v0.1.0 ten days ago.
# docs-misstate-code fixed on 2 PRs and stale-docs on a third since the tag fold into one docs row with
# 3 PRs that names both; a stale-docs fix from before the tag's day does not count, and neither does a
# kind on 2 PRs. A kind on 3 PRs shows until a merge on the board's origin/HEAD deletes its checks:
# story, and the docs row goes once a checks: story for stale-docs, a name folded into docs, merges.
# With nothing left, one line says so.
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
check() { # <name> <got> <want>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# gh and herdr fail; git reads no user config, so no signer is asked.
STUB_BIN="${ROOT}/bin"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp" "${ROOT}/memory"
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/gh"; printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/herdr"
chmod +x "${STUB_BIN}/gh" "${STUB_BIN}/herdr"
: > "${ROOT}/gitconfig"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" \
  GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
ago() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }

# The project: its board in docs/, with the check stories on it; v0.1.0 committed 10 days ago.
P="${ROOT}/p"
git init -q -b main "${P}"
mkdir -p "${P}/.swarm" "${P}/docs/stories"; echo '# Stories' > "${P}/docs/stories/README.md"
printf -- '---\nkind: code\nstatus: ready\nchecks: vacuous-test\n---\n' > "${P}/docs/stories/vacuous-check.md"
printf -- '---\nkind: code\nstatus: ready\nchecks: stale-docs\n---\n' > "${P}/docs/stories/stale-check.md"
git -C "${P}" add -A
GIT_COMMITTER_DATE="$(ago 10)T12:00:00" git -C "${P}" commit -q -m board
git -C "${P}" tag v0.1.0
merged() { git -C "${P}" update-ref refs/remotes/origin/main HEAD; }   # origin/HEAD is now HEAD
git -C "${P}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main && merged

printf '%s\n' \
  "$(ago 9)"$'\tdocs-misstate-code\to/r#1\ta\tfixed\tcodex' \
  "$(ago 8)"$'\tdocs-misstate-code\thttps://github.com/o/r/pull/2\tb\tfixed\tcodex' \
  "$(ago 7)"$'\tstale-docs\to/r#3\tc\tescaped\tescaped' \
  "$(ago 11)"$'\tstale-docs\to/r#4\tbefore the tag day\tfixed\tcodex' \
  "$(ago 6)"$'\ttwo-prs\to/r#5\td\tfixed\tcodex' \
  "$(ago 5)"$'\ttwo-prs\to/r#6\te\tfixed\tcodex' \
  "$(ago 4)"$'\tvacuous-test\to/r#7\tf\tfixed\tcodex' \
  "$(ago 3)"$'\tvacuous-test\to/r#8\tg\tfixed\tcodex' \
  "$(ago 2)"$'\tvacuous-test\to/r#9\th\tfixed\tcodex' > "${P}/.swarm/findings.tsv"

section() { # the recurring section's lines, without its heading
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" retro --since v0.1.0 --memory "${ROOT}/memory") \
    | sed -n '/^## recurring$/,/^$/p' | sed '1d;/^$/d'
}

check "docs-misstate-code on 2 PRs and stale-docs on a third fold into one docs row, most PRs first; two-prs is absent" \
  "$(section)" "$(printf '%s\n' 'docs: 3 PRs, as docs-misstate-code, stale-docs' 'vacuous-test: 3 PRs, as vacuous-test')"

git -C "${P}" rm -q docs/stories/vacuous-check.md
git -C "${P}" commit -q -m deleted-locally
check "a checks: story deleted only on the local branch, not on origin/HEAD, still leaves its kind listed" \
  "$(section | grep -c '^vacuous-test:')" 1
merged
check "once a merge on origin/HEAD deleted vacuous-test's checks: story, its kind is absent" \
  "$(section)" 'docs: 3 PRs, as docs-misstate-code, stale-docs'

git -C "${P}" rm -q docs/stories/stale-check.md
git -C "${P}" commit -q -m stale-check-merged && merged
check "a merged checks: story for stale-docs, a name folded into docs, is docs' check, and an empty list says so" \
  "$(section)" "no recurring kind without a check: none was fixed on 3 or more PRs since $(ago 10) and lacks a merged checks: story"

echo "${fails} failure(s)"
[[ "${fails}" -eq 0 ]]
