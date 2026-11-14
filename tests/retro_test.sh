#!/usr/bin/env bash
# retro_test.sh — `swarm.sh retro [--since <tag>] [--memory <dir>]` over a fixture project tagged
# v0.1.0 and v0.2.0, its origin out of reach, with a gh first on PATH that records each call and exits 1: with no --since it
# names v0.2.0 and its commit's day (from the local origin/HEAD, which unset asks for --since), --since v0.1.0 names that tag's day, and an unknown tag exits
# non-zero naming it. Its first lines name the short commit of the git checkout swarm.sh runs from, or,
# run from a copy of bin/ and .claude-plugin/ outside any, plugin.json's version and that it is not one. The
# memories section prints each note's name and description but not MEMORY.md, says so for an empty
# or missing folder, and with no --memory reads the folder named for the project's main checkout
# under CLAUDE_PROJECTS_DIR, from a worktree too. In the copy, a section that raises prints its error while the next still runs,
# and a section imports bin/lib's report.py, not the project's. A full run makes no gh call.
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

# gh records each call and fails; herdr fails. git reads no user config, so no signer is asked.
STUB_BIN="${ROOT}/bin"; GH_CALLS="${ROOT}/gh-calls"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 1\n' "${GH_CALLS}" > "${STUB_BIN}/gh"
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/herdr"
chmod +x "${STUB_BIN}/gh" "${STUB_BIN}/herdr"
: > "${ROOT}/gitconfig"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" TZ=UTC \
  GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS

# The project: v0.1.0 committed on 2026-01-05, v0.2.0 on 2026-02-10, both on origin's main.
O="${ROOT}/origin.git"; P="${ROOT}/p"
git init -q --bare -b main "${O}"
git init -q -b main "${P}"
mkdir -p "${P}/.swarm" "${P}/docs/stories"; touch "${P}/docs/stories/README.md"
git -C "${P}" add -A
GIT_COMMITTER_DATE="2026-01-05T10:00:00Z" git -C "${P}" commit -q -m one
git -C "${P}" tag v0.1.0
GIT_COMMITTER_DATE="2026-02-10T10:00:00Z" git -C "${P}" commit -q --allow-empty -m two
git -C "${P}" tag v0.2.0
git -C "${P}" remote add origin "${O}"
git -C "${P}" push -q origin main --tags
git -C "${P}" remote set-head origin main
# origin cannot be reached from here on: retro finds the default tag offline, from the local origin/HEAD.
mv "${O}" "${O}.gone"

# The logs every later section reads: findings declined and fixed, intervene, other incident and reap lines.
printf '%s\n' $'2026-02-11\tdocs\tredscaresu/x#1\tthe README names a gone flag\tdeclined\tcodex\tout-of-scope' \
  $'2026-02-12\ttest-gap\tredscaresu/x#2\tno case for an empty file\tfixed\tcodex\t\t1' > "${P}/.swarm/findings.tsv"
sw() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "$@"); }
sw intervene user-caught flaky-test "a test failed twice before anyone looked" >/dev/null
sw intervene lead-hand flaky-test "typed into a stalled conductor's pane" >/dev/null
printf '%s\n' $'2026-02-13T09:00:00Z\tincident\tconduct-e\t-\tstalled: no output for 30m' \
  $'2026-02-13T10:00:00Z\treap\ttests/slow_test.sh\t-\tTIMEOUT after 600s' >> "${P}/.swarm/events.tsv"

# The memory folders: two notes, the index and a session log beside them; an empty one; the default one.
M="${ROOT}/memory"; E="${ROOT}/empty"; mkdir -p "${M}" "${E}"
printf -- '---\nname: wait-on-ci\ndescription: wait on CI with wait-pr, never a loop\nmetadata:\n  type: feedback\n---\n\nbody\n' > "${M}/wait-on-ci.md"
printf -- '---\nname: board-dir\ndescription: the board lives in board/\n---\n' > "${M}/board-dir.md"
printf -- '- [Wait on CI](wait-on-ci.md) — index line\n' > "${M}/MEMORY.md"
echo '{"secret":"session text"}' > "${M}/s1.jsonl"
D="${CLAUDE_PROJECTS_DIR}/${P//[^A-Za-z0-9]/-}/memory"; mkdir -p "${D}"
printf -- '---\nname: default-note\ndescription: read from the default folder\n---\n' > "${D}/default-note.md"

: > "${GH_CALLS}"
rc=0; out="$(sw retro --memory "${M}")" || rc=$?
check "a full retro over the fixture's findings, events and memory exits 0" "${rc}" 0
check "with no --since retro names v0.2.0 and its day" "$(sed -n 1p <<< "${out}")" "retro since v0.2.0: from 2026-02-10, the day of its commit"
check "--memory prints both notes' names and descriptions, and not MEMORY.md" "$(sed -n '/^## memories$/,/^$/p' <<< "${out}")" \
  "## memories"$'\n'"board-dir.md: board-dir — the board lives in board/"$'\n'"wait-on-ci.md: wait-on-ci — wait on CI with wait-pr, never a loop"

git -C "${P}" remote set-head origin -d
rc=0; err="$(sw retro --memory "${M}" 2>&1)" || rc=$?
check "with origin/HEAD unset and no --since, retro exits non-zero and asks for --since" \
  "${rc} $([[ "${err}" == *"origin/HEAD is not set"*"--since <tag>"* ]] && echo asks)" "1 asks"
git -C "${P}" remote set-head origin main

check "--since v0.1.0 names v0.1.0's day" "$(sw retro --since v0.1.0 --memory "${M}" | sed -n 1p)" \
  "retro since v0.1.0: from 2026-01-05, the day of its commit"
rc=0; err="$(sw retro --since v9.9.9 --memory "${M}" 2>&1)" || rc=$?
check "--since v9.9.9 exits non-zero" "$([[ ${rc} -ne 0 ]] && echo nonzero)" nonzero
check "and names v9.9.9" "$([[ "${err}" == *"no tag v9.9.9 in "* ]] && echo named)" named

check "an empty folder prints the line saying it holds none" "$(sw retro --memory "${E}" | sed -n '/^## memories$/{n;p;}')" \
  "no memory notes: ${E} holds none"
check "a missing folder says it does not exist" "$(sw retro --memory "${ROOT}/gone" | sed -n '/^## memories$/{n;p;}')" \
  "no memory notes: ${ROOT}/gone does not exist"
check "with no --memory the project's folder under CLAUDE_PROJECTS_DIR is read" "$(sw retro | sed -n '/^## memories$/{n;p;}')" \
  "default-note.md: default-note — read from the default folder"
git -C "${P}" worktree add -q -b wt "${ROOT}/p-wt"
check "with SWARM_PROJECT naming a worktree, the main checkout's folder is read" \
  "$(cd "${ROOT}" && env -u HERDR_ENV SWARM_PROJECT="${ROOT}/p-wt" bash "${REPO}/bin/swarm.sh" retro --since v0.2.0 | sed -n '/^## memories$/{n;p;}')" \
  "default-note.md: default-note — read from the default folder"

check "no retro run above made a gh call" "$(cat "${GH_CALLS}")" ""

# A copy of bin/ and .claude-plugin/ at the top of a git checkout of its own names that checkout's commit.
G="${ROOT}/plugin-git"; mkdir -p "${G}"
cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${G}/"
git init -q "${G}"; git -C "${G}" add -A; git -C "${G}" commit -q -m plugin
check "run from a checkout it names the checkout's short commit" \
  "$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${G}/bin/swarm.sh" retro --memory "${M}" | sed -n 2p)" \
  "written by swarm.sh at commit $(git -C "${G}" rev-parse --short HEAD)"

# A copy of bin/ and .claude-plugin/ outside any git checkout, with a section that raises before
# memories and one after it that imports report, beside a project-root report.py and json.py that must not load.
C="${ROOT}/plugin"; mkdir -p "${C}"
cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${C}/"
printf 'raise RuntimeError("broken on purpose")\n' > "${C}/bin/lib/retro_aa_boom.py"
printf 'import report\nprint(report.__file__)\n' > "${C}/bin/lib/retro_zz_lib.py"
echo 'print("project report.py")' > "${P}/report.py"
printf 'open("%s/json-imported", "w")\n' "${ROOT}" > "${P}/json.py"
version="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${C}/.claude-plugin/plugin.json")"
rc=0; out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${C}/bin/swarm.sh" retro --memory "${M}" 2>/dev/null)" || rc=$?
check "outside a git checkout it names plugin.json's version and says it is not one" "$(sed -n 2p <<< "${out}")" \
  "written by swarm.sh at version ${version}, not a git checkout"
check "reading that version imports no json.py from the project" "$([[ -e "${ROOT}/json-imported" ]] && echo imported || echo none)" none
check "a section that raises prints its error and fails the run" "$(grep '^error:' <<< "${out}") rc=${rc}" "error: aa_boom: broken on purpose rc=1"
check "the sections still run, in name order" "$(grep '^## ' <<< "${out}" | tr '\n' ' ')" "## aa_boom ## memories ## recurring ## zz_lib "
check "a section imports bin/lib's report.py" "$(sed -n '/^## zz_lib$/{n;p;}' <<< "${out}")" "${C}/bin/lib/report.py"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
