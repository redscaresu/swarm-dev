#!/usr/bin/env bash
# handover_test.sh — `swarm.sh handover <dir> [--memory <dir>]` (bin/lib/handover.sh, bin/lib/handover.py)
# over a fixture project with uncommitted board edits (a changed, a new and a deleted story), a .swarm/
# holding a session log under sessions/, a stray *.jsonl, a file named like a token, pane records in
# state/ (one in a token-named file) and agent session ids in agents.tsv and events.tsv (one only there,
# in free text, as a restart writes it), gh and herdr stubbed. The handover holds swarm/ without the
# session logs, the token-named file, state/ or a session id, board.patch, snapshot.md (the open PR, and
# only the agent a pane record that may be read names) and RESTORE.md, which lists the token-named file
# and state/ as skipped. Running RESTORE.md's
# blocks in a fresh clone gives the same `swarm.sh next` and board files. With no --memory nothing from
# the lead's memory folder is in it, though one sits where Claude Code keeps it for the project; with
# --memory <dir> that folder's files are. An out dir that is not empty, or is inside the project's repo,
# is refused.
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
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$2") <(echo "$3") || true; fails=$((fails + 1)); fi
}

# gh lists one open PR; herdr lists this project's agent (pane w1:p1, recorded in .swarm/state) and
# another project's. git reads no user config, so no signer is asked.
STUB_BIN="${ROOT}/bin"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp"
cat > "${STUB_BIN}/gh" <<'EOF'
#!/bin/sh
[ "$1 $2" = "pr list" ] || exit 1
pwd -P >> "${GH_PWD}"
echo '[{"number":7,"title":"Add the thing","headRefName":"story/a","isDraft":false,"url":"https://github.com/o/p/pull/7"}]'
EOF
cat > "${STUB_BIN}/herdr" <<'EOF'
#!/bin/sh
[ "$1 $2" = "agent list" ] || exit 1
echo '{"result":{"agents":[{"name":"a","agent_status":"working","pane_id":"w1:p1","session_id":"x"},{"name":"other","agent_status":"idle","pane_id":"w9:p9"},{"name":"hidden","agent_status":"idle","pane_id":"w7:p7"}]}}'
EOF
chmod +x "${STUB_BIN}/gh" "${STUB_BIN}/herdr"
# board.patch keeps a/ and b/, and no colour, all the same.
printf '[diff]\n\tnoprefix = true\n[color]\n\tdiff = always\n' > "${ROOT}/gitconfig"
export GH_PWD="${ROOT}/gh-pwd" PATH="${STUB_BIN}:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" TZ=UTC \
  GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS

# The project, on origin's main: three stories, a, b (ready) and c.
O="${ROOT}/origin.git"; P="${ROOT}/p"
git init -q --bare -b main "${O}"
git init -q -b main "${P}"
mkdir -p "${P}/docs/stories" "${P}/docs/epics"
echo '.swarm/' > "${P}/.gitignore"
echo '# Stories' > "${P}/docs/stories/README.md"; echo '# Epics' > "${P}/docs/epics/README.md"
story() { printf -- '---\nkind: code\nstatus: %s\n---\n\n# %s\n' "$2" "$1" > "${P}/docs/stories/$1.md"; }
story a draft; story b ready; story c ready
git -C "${P}" add -A && git -C "${P}" commit -q -m one
git -C "${P}" remote add origin "${O}"
git -C "${P}" push -q origin main

# Uncommitted board edits in the main checkout: a is now ready, d is new, c is gone.
story a ready; story d ready; rm "${P}/docs/stories/c.md"
# .swarm/: the logs, a report, a pane record, a session log and a stray *.jsonl, and a token-named file.
SID="0c2d6b3b-5b21-4cde-9237-f3b84d4ed5ca" SID2="61062605-d9ac-48c9-9931-b28d3036c897"
mkdir -p "${P}/.swarm/sessions" "${P}/.swarm/state" "${P}/.swarm/briefs"
printf '2026-11-01\tcode\ta\tclaude\topus\thigh\t%s\n' "${SID}" > "${P}/.swarm/agents.tsv"
printf '2026-11-01T10:00:00Z\tstarted\ta\t-\tok ~~ session=%s\n' "${SID}" > "${P}/.swarm/events.tsv"
printf '2026-11-02T10:00:00Z\trestart\ta\tw1:p1\tok (resumed session %s)\n' "${SID2}" >> "${P}/.swarm/events.tsv"
echo 'report' > "${P}/.swarm/conduct-e1.report.md"
echo 'w1:p1 a' > "${P}/.swarm/state/build"
echo 'w7:p7 hidden' > "${P}/.swarm/state/token-pane"   # named like a token: never read, so w7:p7 is not this project's
echo 'brief for a' > "${P}/.swarm/briefs/a.md"
echo '{"session":"log"}' | gzip > "${P}/.swarm/sessions/2026-11-01-a-${SID}.jsonl.gz"
echo 'archive index' > "${P}/.swarm/sessions/index.txt"   # under sessions/, though not named like a log
echo '{"stray":"log"}' > "${P}/.swarm/briefs/run.jsonl"
echo 'not-a-real-token' > "${P}/.swarm/gh-token.txt"
# This machine's own: a launch wrapper holding an environment value, a lock and two pid files.
mkdir -p "${P}/.swarm/launch" "${P}/.swarm/locks" "${P}/.swarm/lead"
echo 'export ANTHROPIC_FOUNDRY_API_KEY=launch-env-value' > "${P}/.swarm/launch/a.1"
echo 'held' > "${P}/.swarm/locks/merge"
echo '12345' > "${P}/.swarm/lead/pid"; echo '12346 - a' > "${P}/.swarm/upgrade.pid"
mkdir -p "${P}/.swarm/merge-o-p-main.lock"; echo '12347' > "${P}/.swarm/merge-o-p-main.lock/pid"
echo '12348' > "${P}/.swarm/reconcile.lock"; echo '2026-11-01' > "${P}/.swarm/auto-mode-done"
echo 'w3' > "${P}/.swarm/lead/workspace"
# A folder handover cannot list: said in RESTORE.md, not dropped quietly.
mkdir -p "${P}/.swarm/reviews"; echo 'r' > "${P}/.swarm/reviews/r1.md"; chmod 000 "${P}/.swarm/reviews"
# The lead's memory, where Claude Code keeps it for the project, and a folder named with --memory.
DEFAULT_MEM="${CLAUDE_PROJECTS_DIR}/${P//[^A-Za-z0-9]/-}/memory"
mkdir -p "${DEFAULT_MEM}" "${ROOT}/mem"
echo 'default-memory-note' > "${DEFAULT_MEM}/lead.md"
echo 'named-memory-note' > "${ROOT}/mem/lead.md"

sw() { (cd "$1" && shift && env -u SWARM_PROJECT HERDR_ENV=1 bash "${REPO}/bin/swarm.sh" "$@"); }

# --- Without --memory.
H="${ROOT}/handover"
sw "${P}" handover "${H}" > "${ROOT}/out" 2>&1 || { echo "FAIL handover exited non-zero:"; cat "${ROOT}/out"; exit 1; }
check "the handover holds swarm/, board.patch, snapshot.md and RESTORE.md, and nothing else" \
  $'RESTORE.md\nboard.patch\nsnapshot.md\nswarm' "$(cd "${H}" && LC_ALL=C ls -A)"
check "swarm/ holds .swarm/ without the session logs and the token-named file" \
  $'agents.tsv\nbriefs/a.md\nconduct-e1.report.md\nevents.tsv\ngh-calls.tsv' "$(cd "${H}/swarm" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
check "no session log anywhere in the handover" "" "$(find "${H}" -name '*.jsonl*' -o -name sessions)"
check "no session id in any copied file, the restarted one too" "" "$(grep -rlE "${SID}|${SID2}" "${H}" || true)"
check "agents.tsv's session column is -" $'2026-11-01\tcode\ta\tclaude\topus\thigh\t-' "$(cat "${H}/swarm/agents.tsv")"
check "events.tsv keeps its line, with the session id as -" \
  $'2026-11-01T10:00:00Z\tstarted\ta\t-\tok ~~ session=-\n2026-11-02T10:00:00Z\trestart\ta\tw1:p1\tok (resumed session -)' \
  "$(cat "${H}/swarm/events.tsv")"
check "RESTORE.md lists the token-named file as skipped" \
  "- swarm/gh-token.txt: its name looks like a credential, so it was not read" "$(grep -F 'gh-token' "${H}/RESTORE.md")"
check "RESTORE.md lists what belongs to this machine as skipped" \
  "- swarm/launch/: agent launch wrappers, which hold the environment values an agent started with, credentials among them
- swarm/locks/: this machine's locks
- swarm/merge-o-p-main.lock/: this machine's lock
- swarm/state/: this machine's herdr pane records, which would claim panes of the same id on another
- swarm/auto-mode-done: this machine's word that auto mode's setup ran: run /auto-mode-setup on the new one, then swarm.sh init --auto-mode-done
- swarm/reconcile.lock: this machine's lock
- swarm/upgrade.pid: a process id on this machine
- swarm/lead/pid: a process id on this machine
- swarm/lead/workspace: this machine's herdr workspace id for the lead" \
  "$(grep -E '^- swarm/(launch|locks|state|merge-o-p-main\.lock)/|(\.?pid|\.lock|auto-mode-done|workspace): ' "${H}/RESTORE.md")"
check "RESTORE.md lists a folder it could not read" \
  "- swarm/reviews/: could not be read (Permission denied), so nothing in it was copied" "$(grep -F 'swarm/reviews/' "${H}/RESTORE.md")"
chmod 755 "${P}/.swarm/reviews"   # so the later handovers, and the trap's rm -rf, can read it
check "no launch wrapper's environment value is in the handover" "" "$(grep -rl 'launch-env-value' "${H}" || true)"
check "RESTORE.md counts the three session logs left out" "1" "$(grep -c '^- 3 session logs: ' "${H}/RESTORE.md")"
check "board.patch holds the three board edits" $'docs/stories/a.md\ndocs/stories/c.md\ndocs/stories/d.md' \
  "$(git -C "${P}" apply --numstat "${H}/board.patch" | cut -f3 | LC_ALL=C sort)"
check "snapshot.md lists the open PR" "- #7 Add the thing (story/a, open) https://github.com/o/p/pull/7" "$(grep -F '#7' "${H}/snapshot.md")"
check "snapshot.md lists this project's agent, not another's nor one only a token-named file names, with no other field" "- a: working, pane w1:p1" \
  "$(sed -n '/^## Agents/,$p' "${H}/snapshot.md" | grep '^- ')"
check "without --memory, no memory/ folder" "no" "$([[ -e "${H}/memory" ]] && echo yes || echo no)"
check "without --memory, no file from the memory folder is in the handover" "" \
  "$(grep -rlE 'default-memory-note|named-memory-note' "${H}" || true)"
check "the checkout's own index is untouched: the new story is still untracked" "?? docs/stories/d.md" \
  "$(git -C "${P}" status --porcelain -- docs/stories/d.md)"

check "gh pr list ran in the project" "${P}" "$(cat "${GH_PWD}")"

# --- Restore into a fresh clone with RESTORE.md's own commands, the handover moved to another folder
# (with a space in its name) as it is on another machine: the same next and board files.
C="${ROOT}/clone"; M="${ROOT}/moved handover"
mv "${H}" "${M}"
git clone -q "${O}" "${C}"
awk '/^```sh$/{on=1; next} /^```$/{on=0} on' "${M}/RESTORE.md" > "${ROOT}/restore.sh"
(cd "${C}" && HANDOVER_DIR="${M}" bash -eu "${ROOT}/restore.sh") || { echo "FAIL RESTORE.md's commands failed in the clone"; fails=$((fails + 1)); }
next_of() { (cd "$1" && env -u SWARM_PROJECT -u HERDR_ENV bash "${REPO}/bin/swarm.sh" next 2>&1 | sed "s|$1|<project>|g"); }
want_next="$(next_of "${P}")"
check "the restored clone gives the same swarm.sh next" "${want_next}" "$(next_of "${C}")"
check "the restored clone has the same board files" "" "$(diff -r "${P}/docs" "${C}/docs" || true)"
check "the restored clone's .swarm/ has the copied files" "$(cat "${M}/swarm/events.tsv")|report" \
  "$(cat "${C}/.swarm/events.tsv")|$(cat "${C}/.swarm/conduct-e1.report.md")"

# --- With --memory: the named folder's files, and RESTORE.md says to keep it private.
H2="${ROOT}/handover2"
sw "${P}" handover "${H2}" --memory "${ROOT}/mem" > "${ROOT}/out" 2>&1 || { echo "FAIL handover --memory exited non-zero:"; cat "${ROOT}/out"; exit 1; }
check "with --memory, its files are in memory/" "named-memory-note" "$(cat "${H2}/memory/lead.md" 2>/dev/null)"
check "with --memory, RESTORE.md says never to publish it" "1" "$(grep -c "never commit it or push it anywhere, as memory/ holds the lead's own notes" "${H2}/RESTORE.md")"

# --- Refusals: a folder that is not empty, and one inside the project's repo.
mkdir -p "${ROOT}/full"; echo x > "${ROOT}/full/x"
rc=0; sw "${P}" handover "${ROOT}/full" > "${ROOT}/out" 2>&1 || rc=$?
check "a folder that is not empty is refused" "1|swarm: handover: ${ROOT}/full is not an empty folder; name a new one" "${rc}|$(cat "${ROOT}/out")"
# A folder that cannot be listed may hold files: it is refused, and what is in it is left as it was.
mkdir -p "${ROOT}/unlisted"; echo keep > "${ROOT}/unlisted/RESTORE.md"; chmod 300 "${ROOT}/unlisted"
rc=0; sw "${P}" handover "${ROOT}/unlisted" > "${ROOT}/out" 2>&1 || rc=$?
chmod 755 "${ROOT}/unlisted"
check "a folder that cannot be listed is refused, and its file is left as it was" \
  "1|swarm: handover: ${ROOT}/unlisted is not an empty folder; name a new one|keep" "${rc}|$(cat "${ROOT}/out")|$(cat "${ROOT}/unlisted/RESTORE.md")"
rc=0; sw "${P}" handover "${P}/docs/h" > "${ROOT}/out" 2>&1 || rc=$?
check "a folder inside the project's repo is refused, and the folder it made is gone" \
  "1|swarm: handover: ${P}/docs/h is inside the project's repo, where it could be committed; name a folder outside it|no" \
  "${rc}|$(cat "${ROOT}/out")|$([[ -e "${P}/docs/h" ]] && echo yes || echo no)"

rc=0; sw "${P}" handover "${ROOT}/mem/out" --memory "${ROOT}/mem" > "${ROOT}/out" 2>&1 || rc=$?
check "a folder inside the --memory folder is refused, and the folder it made is gone" \
  "1|swarm: handover: ${ROOT}/mem/out is inside --memory ${ROOT}/mem, which it would copy into itself; name a folder outside it|no" \
  "${rc}|$(cat "${ROOT}/out")|$([[ -e "${ROOT}/mem/out" ]] && echo yes || echo no)"

# --- A board in a repo of its own (board_dir names it): a folder inside the project's repo is still
# refused, the patch is the board repo's edits, and gh pr list runs in the project, not the board repo.
Q="${ROOT}/q"; B="${ROOT}/boardrepo"
git init -q -b main "${Q}"; git init -q -b main "${B}"
mkdir -p "${Q}/.claude/swarm" "${B}/docs/stories"
echo '.swarm/' > "${Q}/.gitignore"; printf 'board_dir = %s\n' "${B}/docs" > "${Q}/.claude/swarm/config"
echo '# Stories' > "${B}/docs/stories/README.md"
git -C "${Q}" add -A && git -C "${Q}" commit -q -m one
git -C "${B}" add -A && git -C "${B}" commit -q -m one
echo 'new' > "${B}/docs/stories/e.md"
# q's state/ is a symlink to p's: its pane records are p's, so q's snapshot names no agent of p's.
mkdir -p "${Q}/.swarm"; ln -s "${P}/.swarm/state" "${Q}/.swarm/state"
rc=0; sw "${Q}" handover "${Q}/h" > "${ROOT}/out" 2>&1 || rc=$?
check "with the board in its own repo, a folder inside the project's repo is refused" \
  "1|swarm: handover: ${Q}/h is inside the project's repo, where it could be committed; name a folder outside it" "${rc}|$(cat "${ROOT}/out")"
: > "${GH_PWD}"
sw "${Q}" handover "${ROOT}/hq" > "${ROOT}/out" 2>&1 || { echo "FAIL handover of q exited non-zero:"; cat "${ROOT}/out"; fails=$((fails + 1)); }
check "with the board in its own repo, gh pr list runs in the project and the patch holds the board's edit" \
  "${Q}|docs/stories/e.md" "$(cat "${GH_PWD}")|$(git -C "${B}" apply --numstat "${ROOT}/hq/board.patch" 2>/dev/null | cut -f3)"
check "a symlinked state/ is not read for pane records" "- none running in this project's panes" \
  "$(sed -n '/^## Agents/,$p' "${ROOT}/hq/snapshot.md" | grep '^- ')"
check "with the board in its own repo, RESTORE.md says to apply the patch in the board repo's clone and to repoint board_dir" "3" \
  "$(grep -cE "board is in a repo of its own \(${B}\)|run from the board repo's clone's root, not the project's|board_dir in .claude/swarm/config names ${B}/docs on the old machine" "${ROOT}/hq/RESTORE.md")"

# --- A board at the project's root (board_dir = .): board.patch holds the board's edits, not the
# project's other uncommitted files.
R="${ROOT}/r"
git init -q -b main "${R}"
mkdir -p "${R}/.claude/swarm" "${R}/stories"
echo '.swarm/' > "${R}/.gitignore"; echo 'board_dir = .' > "${R}/.claude/swarm/config"
echo '# Stories' > "${R}/stories/README.md"; echo 'v1' > "${R}/main.go"
git -C "${R}" add -A && git -C "${R}" commit -q -m one
echo 'new' > "${R}/stories/f.md"; echo 'v2' > "${R}/main.go"; echo 'scratch' > "${R}/notes.txt"
sw "${R}" handover "${ROOT}/hr" > "${ROOT}/out" 2>&1 || { echo "FAIL handover of r exited non-zero:"; cat "${ROOT}/out"; fails=$((fails + 1)); }
check "with board_dir = ., board.patch holds the board's edit and no other file" "stories/f.md" \
  "$(git -C "${R}" apply --numstat "${ROOT}/hr/board.patch" 2>/dev/null | cut -f3)"

if (( fails > 0 )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
