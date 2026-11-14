#!/usr/bin/env bash
# retro_findings_test.sh — retro's findings section over a fixture findings.tsv in a project tagged
# v0.2.0 ten days ago, with six declines: an out-of-scope one and a deferred one since the tag, one from
# before the tag's day, one later logged --filed, one later fixed, and one a board story carries.
# `swarm.sh retro --since v0.2.0` lists exactly the first two, newest first, each with its reason; a tag
# made today lists none and says so. out_of_scope_findings with no day keeps its 30-day window, which
# idle_lines reads: it lists the one from before the tag's day too, but not one from 40 days ago.
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

# gh and herdr fail. git reads no user config, so no signer is asked.
STUB_BIN="${ROOT}/bin"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp" "${ROOT}/memory"
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/gh"
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/herdr"
chmod +x "${STUB_BIN}/gh" "${STUB_BIN}/herdr"
: > "${ROOT}/gitconfig"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" TZ=UTC \
  GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS

# ago <n> — the day n days before today, YYYY-MM-DD (UTC, as TZ is).
ago() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }
OLD="$(ago 40)"; BEFORE="$(ago 12)"; TAGDAY="$(ago 10)"; D1="$(ago 8)"; D2="$(ago 6)"; TODAY="$(ago 0)"

# The project: v0.2.0 committed on TAGDAY, v0.3.0 today; a board story that carries one finding's text.
P="${ROOT}/p"
git init -q -b main "${P}"
mkdir -p "${P}/.swarm" "${P}/docs/stories"; touch "${P}/docs/stories/README.md"
git -C "${P}" add -A
GIT_COMMITTER_DATE="${TAGDAY}T10:00:00Z" git -C "${P}" commit -q -m one
git -C "${P}" tag v0.2.0
GIT_COMMITTER_DATE="${TODAY}T00:00:00Z" git -C "${P}" commit -q --allow-empty -m two
git -C "${P}" tag v0.3.0
printf -- '---\nkind: code\nstatus: ready\n---\n\n# Carry it\n\nFix it: a story carries this text.\n' > "${P}/docs/stories/carry-it.md"

row() { # <day> <kind> <pr> <text> <reason>
  printf '%s\t%s\t%s\t%s\tdeclined\tcodex\t%s\n' "$1" "$2" "$3" "$4" "$5"
}
{
  row "${OLD}" docs o/r#7 "older than the idle window" out-of-scope
  row "${BEFORE}" docs o/r#3 "declined before the tag's day" out-of-scope
  row "${D1}" docs o/r#1 "the README names a gone flag" out-of-scope
  row "${D1}" docs o/r#4 "later filed as a story" out-of-scope
  row "${D1}" test-gap o/r#5 "later fixed on its PR" deferred
  row "${D1}" docs o/r#6 "a story carries this text" out-of-scope
  row "${D2}" test-gap o/r#2 "no case for an empty file" deferred
} > "${P}/.swarm/findings.tsv"
sw() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "$@"); }
sw log-finding --filed --reviewer lead docs o/r#4 "later filed as a story" >/dev/null
sw log-finding --reviewer codex test-gap o/r#5 "later fixed on its PR" >/dev/null

# section <out> — the findings section's lines, its heading first, up to the blank line after it.
section() { sed -n '/^## findings$/,/^$/p' <<< "$1" | sed '/^$/d'; }

rc=0; out="$(sw retro --since v0.2.0 --memory "${ROOT}/memory")" || rc=$?
check "retro --since v0.2.0 exits 0" "${rc}" 0
check "it lists exactly the open out-of-scope and deferred findings since the tag, newest first, with their reasons" \
  "$(section "${out}")" "## findings"$'\n'"deferred ${D2} test-gap o/r#2: no case for an empty file"$'\n'"out-of-scope ${D1} docs o/r#1: the README names a gone flag"

check "a tag made today lists none and says so" "$(section "$(sw retro --since v0.3.0 --memory "${ROOT}/memory")")" \
  "## findings"$'\n'"no out-of-scope or deferred findings open since v0.3.0"

# With no day, idle_lines' 30-day window: the decline from before the tag's day too, not the 40-day-old one.
check "out_of_scope_findings with no day keeps its 30-day window" \
  "$(PROJECT_DIR="${P}" BOARD="${P}/docs" bash -c '. "$1/reports.sh"; out_of_scope_findings' _ "${REPO}/bin/lib")" \
  "deferred	${D2} test-gap o/r#2: no case for an empty file"$'\n'"out-of-scope	${D1} docs o/r#1: the README names a gone flag"$'\n'"out-of-scope	${BEFORE} docs o/r#3: declined before the tag's day"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
