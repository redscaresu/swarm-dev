#!/usr/bin/env bash
# retro_reaped_test.sh — retro's reaped section over a fixture project tagged v0.2.0 on 2026-02-10.
# Its events.tsv holds a test file's reap line and a codex-review reap line since the tag, one reap
# line the day before it, and a non-reap line. `swarm.sh retro` prints the two since the tag, each
# with its local day, target, outcome and slug=/role= fields. It leaves out the one before the tag
# (which in Tokyo falls on the tag's day, and prints) and the other kind, counts per target, and says
# a fallback reviewer killed on its timeout writes no reap line. With no reap line since the tag, or
# no events.tsv, it prints one line saying which.
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
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/gh"
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/herdr"
chmod +x "${STUB_BIN}/gh" "${STUB_BIN}/herdr"
: > "${ROOT}/gitconfig"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" TZ=UTC \
  GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS

P="${ROOT}/p"
git init -q -b main "${P}"
mkdir -p "${P}/.swarm" "${P}/docs/stories"; touch "${P}/docs/stories/README.md"
git -C "${P}" add -A
GIT_COMMITTER_DATE="2026-02-10T10:00:00Z" git -C "${P}" commit -q -m one
git -C "${P}" tag v0.2.0
sw() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "$@"); }
reaped() { sw retro --since v0.2.0 --memory "${ROOT}/memory" | sed -n '/^## reaped$/,/^## /{/^## /d;p;}'; }
FALLBACK="a fallback reviewer killed on its timeout writes no reap line, so this list is not every kill"

check "with no events.tsv the section says it does not exist" "$(reaped)" \
  "no reap lines: ${P}/.swarm/events.tsv does not exist"$'\n'"${FALLBACK}"

# The day before the tag, the two writers on and after its day, and an incident that is not a reap line.
printf '%s\n' $'2026-02-09T23:00:00Z\treap\ttests/old_test.sh\t-\tTIMEOUT after 600s ~~ slug=old role=builder' \
  $'2026-02-10T08:00:00Z\treap\ttests/slow_test.sh\t-\tTIMEOUT after 612s ~~ slug=s1 role=builder version=0.30.0' \
  $'2026-02-12T09:00:00Z\tincident\tconduct-e\t-\tstalled: no output for 30m' \
  $'2026-02-13T10:00:00Z\treap\tcodex-s2\tp1\ttimed out after 20 min ~~ slug=s2 role=reviewer version=0.30.0' \
  > "${P}/.swarm/events.tsv"
check "since the tag: the test file and codex reap lines, a count per target, and the fallback line" "$(reaped)" \
  "2026-02-10  tests/slow_test.sh  TIMEOUT after 612s  slug=s1 role=builder
2026-02-13  codex-s2  timed out after 20 min  slug=s2 role=reviewer

1  codex-s2
1  tests/slow_test.sh
${FALLBACK}"

# Local days: in Tokyo the line at 23:00 UTC the day before the tag falls on the tag's day, and prints it.
check "the window and each row's day are local days" "$(TZ=Asia/Tokyo reaped | sed -n 1p)" \
  "2026-02-10  tests/old_test.sh  TIMEOUT after 600s  slug=old role=builder"

printf '%s\n' $'2026-02-09T23:00:00Z\treap\ttests/old_test.sh\t-\tTIMEOUT after 600s' > "${P}/.swarm/events.tsv"
check "with only a reap line before the tag the section says there is none since it" "$(reaped)" \
  "no reap lines since 2026-02-10 in ${P}/.swarm/events.tsv"$'\n'"${FALLBACK}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
