#!/usr/bin/env bash
# review_test.sh — merge = human and the review status: the merge guard on every agent, `review`,
# `reconcile`, the gate in `next`, and `findings`; also how an agent starts (a name already
# taken, a failed start, codex's update check). gh and herdr are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
U="https://github.com/o/svc/pull"

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

item() { # <board> <path> <front-matter line>... — a fresh item: its file, and no state file
  local path="$1/$2" title; rm -f "$(dirname "$1")/.swarm/board-state/${2%.md}"; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
# val <item file> <key> — <key> as swarm.sh reads it: board.sh's own get_fm, with the item's board as
# BOARD, in the project that holds it.
# shellcheck source=/dev/null
val() { local d="${1%/*}"; (export BOARD="${d%/*}"; export PROJECT_DIR="${BOARD%/*}"; . "${SWARM%/*}/lib/board.sh"; get_fm "$1" "$2"); }

# Stubs. gh answers from fixture files; herdr accepts everything and logs its arguments.
mkdir -p "${ROOT}/bin" "${ROOT}/gh"
cat > "${ROOT}/bin/gh" <<EOF
#!/bin/sh
F="${ROOT}/gh"
EOF
cat >> "${ROOT}/bin/gh" <<'EOF'
echo "$*" >> "$F/calls"
case "$1 $2" in
  "pr view") case " $* " in *" headRefOid "*) cat "$F/head"; exit 0 ;; esac
             case " $* " in *" body,url "*) echo '{"body":"","url":"https://github.com/o/svc/pull/7"}'; exit 0 ;; esac
             st=$(awk -v u="$3" '$1 == u { print $2 }' "$F/prs"); [ -n "$st" ] || exit 1
             echo "{\"state\":\"$st\"}"; exit 0 ;;
  "pr diff") exit 0 ;;
  "repo view") case " $* " in *" -q "*) echo o/svc ;; *) echo '{"nameWithOwner":"o/svc"}' ;; esac; exit 0 ;;
  "pr list") while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             # One write, as gh makes: watch stops reading at the PR it reports, and jq writing on
             # into the closed pipe (SIGPIPE ignored, as on CI) would print an error into its output.
             out="$(jq -r "$q" "$F/prlist.json")"; printf '%s\n' "${out}"; exit 0 ;;
esac
# watch's REST reads (watch_rows), from prlist.json too: the list, and each PR's mergeable state.
case "$2 $3" in
  "--paginate repos/o/svc/pulls?"*) while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             out="$(jq '[.[] | {number, head: {ref: .headRefName, sha: .headRefOid}, updated_at: .updatedAt}]' "$F/prlist.json" | jq -r "$q")"
             printf '%s\n' "${out}"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/pulls/7) echo '{"head":{"sha":"abc1234def"}}' ;;
  repos/o/svc/pulls/*) n="${2##*/}"; while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             jq ".[] | select(.number == ${n}) | {mergeable: {MERGEABLE: true, CONFLICTING: false}[.mergeable]}" "$F/prlist.json" | jq -r "$q" ;;
  repos/o/svc/commits/abc1234def/check-runs*) cat "$F/runs.json" ;;
  repos/o/svc/check-runs/1/annotations*) cat "$F/annotations.json" ;;
  repos/o/svc/code-scanning/alerts*) cat "$F/alerts.json" ;;
  repos/o/svc/commits/head*/check-runs*) h="${2#repos/o/svc/commits/}"; h="${h%%/*}"
             # runs-fail: every read fails, or only the heads listed in runs-fail-heads. head7 is still running.
             if [ -f "$F/runs-fail" ] && { [ ! -f "$F/runs-fail-heads" ] || grep -qx "$h" "$F/runs-fail-heads"; }; then cat "$F/runs-fail"; exit 1; fi
             if [ "$h" = head7 ]; then echo '1 1'; exit 0; fi
             while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             out="$(echo '{"check_runs":[{"status":"completed"}]}' | jq -r "$q")"; printf '%s\n' "${out}" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
cat > "${ROOT}/bin/herdr" <<EOF
#!/bin/sh
ROOT_LOG="${ROOT}/herdr.log"
echo "\$*" >> "\$ROOT_LOG"
EOF
cat >> "${ROOT}/bin/herdr" <<EOF
A="${ROOT}/agents.json"; F="${ROOT}/start-fails"; P="${ROOT}/panes.json"; O="${ROOT}/start-fails-once"; I="${ROOT}/prompt-idle"; N="${ROOT}/rename-noop"; L="${ROOT}/list-fails"; R="${ROOT}/proj/.swarm/reconcile.lock"
EOF
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create")   echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "pane split")   echo '{"result":{"pane":{"pane_id":"w:2"}}}' ;;
  "agent prompt") if [ -f "$I" ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'; else echo '{"result":{"agent":{"agent_status":"working"}}}'; fi ;;
  "agent list")   [ ! -d "$R" ] || echo "agent list under reconcile.lock" >> "$ROOT_LOG"
                  if [ -f "$L" ]; then exit 1; fi; if [ -f "$A" ]; then cat "$A"; else echo '{"result":{"agents":[]}}'; fi ;;
  "agent rename") if [ -f "$A" ] && [ ! -f "$N" ]; then sed -i.bak "s/\"name\":\"[a-z0-9-]*\",\"agent_status\":\"\([a-z]*\)\",\"pane_id\":\"$3\"/\"name\":\"$4\",\"agent_status\":\"\1\",\"pane_id\":\"$3\"/" "$A"; fi ;;
  "agent start")  if [ -f "$O" ]; then rm -f "$O"; echo '{"error":{"code":"agent_pane_busy"}}'; exit 1; fi
                  if [ -f "$F" ]; then echo '{"error":{"code":"agent_name_taken"}}'; exit 1; fi ;;
  "pane list")    if [ -f "$P" ]; then cat "$P"; fi ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w","label":"e"}]}}' ;;
esac
EOF
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
run() { (cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
first() { printf '%s' "${1%%$'\n'*}"; }

# --- review: the item waits on a human merge, with its PRs on the board.
item "${b}" stories/a.md "status: ready" "kind: code" "epic: e1"
item "${b}" stories/n.md "status: blocked" "kind: code" "epic: e1" "depends_on: [a]"
item "${b}" epics/e1.md "status: active"
run review a "${U}/1" >/dev/null
check "review sets the status and the PRs" "review|${U}/1" "$(val "${b}/stories/a.md" status)|$(val "${b}/stories/a.md" prs)"
check "review refuses what is not a PR URL, and leaves the item alone" "yes|review|${U}/1" \
  "$(has 'not a PR URL' "$(run review a "https://example.com/x" || true)")|$(val "${b}/stories/a.md" status)|$(val "${b}/stories/a.md" prs)"

# --- next: a PR waiting on a human is a gate, and never restarts a conductor.
out="$(run next)"
check "a story in review is a gate, not conduct" "gate" "$(first "${out}")"
check "the gate names the PR to merge" "yes" "$(has "awaiting your merge: a ${U}/1" "${out}")"

# --- reconcile: finish when every PR merged; back to ready if one closed; else wait.
printf '%s\n' "${U}/1 MERGED" "${U}/2 CLOSED" "${U}/3 OPEN" "${U}/4 MERGED" > "${ROOT}/gh/prs"
item "${b}" stories/c.md "status: review" "kind: code" "prs: ${U}/2"
echo "prs: a line in the body" >> "${b}/stories/c.md"
item "${b}" stories/c2.md "status: review" "kind: code" "attempts: 1" "prs: ${U}/2"
item "${b}" epics/e2.md "status: review" "prs: ${U}/1 ${U}/3"
item "${b}" epics/e3.md "status: review" "prs: ${U}/1 ${U}/4"
item "${b}" stories/e3.md "status: blocked" "kind: code" "depends_on: [w]"   # a story with the epic's slug
out="$(run reconcile)"
check "a merged story is finished" "gone" "$([[ -e "${b}/stories/a.md" ]] && echo there || echo gone)"
check "a closed PR sends its story back to ready" "ready" "$(val "${b}/stories/c.md" status)"
check "and writes no attempts: line: a PR closed unmerged is not a failed build" "" "$(val "${b}/stories/c.md" attempts)"
check "a story sent back to ready keeps its attempts: as it was" "ready|1" \
  "$(val "${b}/stories/c2.md" status)|$(val "${b}/stories/c2.md" attempts)"
check "its prs: goes, and a body line like it stays" "|prs: a line in the body" \
  "$(val "${b}/stories/c.md" prs | head -1)|$(grep -x 'prs: a line in the body' "${b}/stories/c.md")"
check "reconcile says which PR closed" "yes" "$(has "back to ready: c (closed without merging: ${U}/2)" "${out}")"
check "an epic with one of two PRs merged stays in review" "review" "$(sed -n 's/^status: //p' "${b}/epics/e2.md")"
check "an epic with both PRs merged is finished, and a story with its slug stays" "gone|there" \
  "$([[ -e "${b}/epics/e3.md" ]] && echo there || echo gone)|$([[ -e "${b}/stories/e3.md" ]] && echo there || echo gone)"
rm "${b}/stories/e3.md"
# With conductor_lanes = 2 and the backlog's two lane conductors running (their briefs, panes this project
# recorded, herdr's list): a story whose PR closed unmerged tells them its build is gone, so a story held
# for a clash with it is startable; an epic's finish tells no lane.
bl1="$(run _conductor backlog 1)"; bl2="$(run _conductor backlog 2)"
echo "conductor_lanes = 2" > "${p}/.claude/swarm/config"
mkdir -p "${p}/.swarm/briefs" "${p}/.swarm/state"; : > "${p}/.swarm/briefs/conduct-backlog.l1.md"; : > "${p}/.swarm/briefs/conduct-backlog.l2.md"
printf 'w:7 conductor\n' > "${p}/.swarm/state/${bl1}"; printf 'w:8 conductor\n' > "${p}/.swarm/state/${bl2}"
printf '{"result":{"agents":[{"name":"%s","agent_status":"working","pane_id":"w:7"},{"name":"%s","agent_status":"working","pane_id":"w:8"}]}}\n' "${bl1}" "${bl2}" > "${ROOT}/agents.json"
item "${b}" stories/c3.md "status: review" "kind: code" "prs: ${U}/2"
item "${b}" epics/e4.md "status: review" "prs: ${U}/1"
: > "${ROOT}/herdr.log"
run reconcile >/dev/null
check "a PR closed unmerged tells the backlog's lanes its build is gone, and a finished epic tells none" "yes|no" \
  "$(has "c3's build is gone (merged, cleared, or its start failed)" "$(cat "${p}/.swarm/inbox/${bl2}.md" 2>&1)")|$(grep -q "e4's build is gone" "${p}/.swarm/inbox/${bl2}.md" 2>/dev/null && echo yes || echo no)"
check "the lanes are listed and told only once reconcile's lock is free" "yes|no" \
  "$(grep -q '^agent list' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -q 'agent list under reconcile.lock' "${ROOT}/herdr.log" && echo yes || echo no)"
# Both lanes have reported: nothing can be waiting, so a story's reopen asks herdr nothing.
: > "${p}/.swarm/conduct-backlog.l1.report.md"; : > "${p}/.swarm/conduct-backlog.l2.report.md"; : > "${p}/.claude/swarm/config"
item "${b}" stories/c4.md "status: review" "kind: code" "prs: ${U}/2"
: > "${ROOT}/herdr.log"; run reconcile >/dev/null
check "with every lane reported and conductor_lanes back at 1, a PR closed unmerged makes no herdr call" "no" \
  "$(grep -q 'agent list' "${ROOT}/herdr.log" && echo yes || echo no)"
# A reconcile that dies after it queued a note (the board state cannot be written) still sends it once its
# lock is free, and leaves no queue file behind.
echo "conductor_lanes = 2" > "${p}/.claude/swarm/config"; rm -f "${p}/.swarm/conduct-backlog.l1.report.md" "${p}/.swarm/conduct-backlog.l2.report.md" "${p}/.swarm/inbox/${bl2}.md"
item "${b}" stories/c5.md "status: review" "kind: code" "prs: ${U}/2"
chmod 555 "${p}/.swarm/board-state/stories"
rc=0; run reconcile >/dev/null 2>&1 || rc=$?
chmod 755 "${p}/.swarm/board-state/stories"
check "a reconcile that dies after queuing a lane note still sends it once its lock is free, and leaves no queue file" "no|yes|0" \
  "$([[ ${rc} -eq 0 ]] && echo yes || echo no)|$(has "c5's build is gone" "$(cat "${p}/.swarm/inbox/${bl2}.md" 2>&1)")|$(set -- "${TMPDIR:-/tmp}"/swarm-lane-notes.*; [[ -e "$1" ]] && echo "$#" || echo 0)"
rm -f "${b}/stories/c5.md"
rm -f "${ROOT}/agents.json" "${p}/.swarm/briefs/conduct-backlog.l1.md" "${p}/.swarm/briefs/conduct-backlog.l2.md" "${p}/.swarm/state/${bl1}" "${p}/.swarm/state/${bl2}" "${b}/stories/c3.md" "${b}/stories/c4.md" "${p}/.swarm/conduct-backlog.l1.report.md" "${p}/.swarm/conduct-backlog.l2.report.md"
rm -rf "${p}/.swarm/inbox"; : > "${p}/.claude/swarm/config"
check "its dependent unblocks once it is finished" "ready: n" "$(run unblock)"

# --- A board in the project repo: the merged PR took r off the board and left s on it. A pull that
# cannot go keeps the items in review, with their PRs; once it can, r goes with its state, and s is
# marked done in its state, its file left, so the main checkout has no edit and the next pull goes.
"${GIT[@]}" init -q --bare "${ROOT}/app.git"
"${GIT[@]}" clone -q "${ROOT}/app.git" "${ROOT}/app" 2>/dev/null
item "${ROOT}/app/docs" stories/r.md "status: ready" "kind: code"
item "${ROOT}/app/docs" stories/s.md "status: ready" "kind: code"
"${GIT[@]}" -C "${ROOT}/app" add docs && "${GIT[@]}" -C "${ROOT}/app" commit -q -m board
"${GIT[@]}" -C "${ROOT}/app" push -q origin main
"${GIT[@]}" clone -q "${ROOT}/app.git" "${ROOT}/pr"
"${GIT[@]}" -C "${ROOT}/pr" rm -q docs/stories/r.md && "${GIT[@]}" -C "${ROOT}/pr" commit -q -m "the PR"
inrepo() { (cd "${ROOT}/app" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
inrepo review r "${U}/1" >/dev/null
inrepo review s "${U}/4" >/dev/null
"${GIT[@]}" -C "${ROOT}/app" commit -q --allow-empty -m "diverged"
"${GIT[@]}" -C "${ROOT}/pr" push -q origin main
inrepo reconcile >/dev/null || true
check "a pull that fails keeps merged items in review, with their PRs" "review ${U}/1|review ${U}/4" \
  "$(val "${ROOT}/app/docs/stories/r.md" status) $(val "${ROOT}/app/docs/stories/r.md" prs)|$(val "${ROOT}/app/docs/stories/s.md" status) $(val "${ROOT}/app/docs/stories/s.md" prs)"
"${GIT[@]}" -C "${ROOT}/app" reset -q --keep HEAD~1
inrepo reconcile >/dev/null || true
gone() { if [[ -e "$1" ]]; then echo there; else echo gone; fi; }
check "the PR's own delete is pulled, and r's state file goes" "gone|$(git -C "${ROOT}/app.git" rev-parse main)|gone" \
  "$(gone "${ROOT}/app/docs/stories/r.md")|$(git -C "${ROOT}/app" rev-parse HEAD)|$(gone "${ROOT}/app/.swarm/board-state/stories/r")"
check "s, which its PR left on the board, is marked done, and the main checkout has no edit" "there|done||" \
  "$(gone "${ROOT}/app/docs/stories/s.md")|$(val "${ROOT}/app/docs/stories/s.md" status)|$(val "${ROOT}/app/docs/stories/s.md" prs)|$(git -C "${ROOT}/app" status --porcelain --untracked-files=no)"
"${GIT[@]}" -C "${ROOT}/pr" commit -q --allow-empty -m "a later PR" && "${GIT[@]}" -C "${ROOT}/pr" push -q origin main
rc=0; inrepo reconcile >/dev/null || rc=$?
check "and the next reconcile pulls" "0|$(git -C "${ROOT}/app.git" rev-parse main)" "${rc}|$(git -C "${ROOT}/app" rev-parse HEAD)"
# A new story r, with the front matter the old one had (written by hand: item would clear its state).
{ echo ---; echo "status: ready"; echo "kind: code"; echo ---; echo; echo "# r"; } > "${ROOT}/app/docs/stories/r.md"
check "a new story r, after r's PR deleted the old one: ready, with no prs and no state file" "ready||gone" \
  "$(val "${ROOT}/app/docs/stories/r.md" status)|$(val "${ROOT}/app/docs/stories/r.md" prs)|$(gone "${ROOT}/app/.swarm/board-state/stories/r")"
rm "${ROOT}/app/docs/stories/r.md"

# --- reconcile never touches an edit. setup_app <name>: a bare origin whose board has stories k and m
# and a tracked README; its main checkout <name> (k in review, its PR merged) and a clone <name>-up,
# which pushes "the base's" change to m.
setup_app() {
  local d="${ROOT}/$1"
  "${GIT[@]}" init -q --bare "${d}.git"
  "${GIT[@]}" clone -q "${d}.git" "${d}" 2>/dev/null
  item "${d}/docs" stories/k.md "status: ready" "kind: code"
  item "${d}/docs" stories/m.md "status: ready" "kind: code"
  echo readme > "${d}/README"
  "${GIT[@]}" -C "${d}" add docs README && "${GIT[@]}" -C "${d}" commit -q -m board && "${GIT[@]}" -C "${d}" push -q origin main
  "${GIT[@]}" clone -q "${d}.git" "${d}-up"
  echo "the base's line" >> "${d}-up/docs/stories/m.md"
  "${GIT[@]}" -C "${d}-up" commit -q -am "edit m" && "${GIT[@]}" -C "${d}-up" push -q origin main
  (cd "${d}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" review k "${U}/1" >/dev/null 2>&1)
  cp "${d}-up/docs/stories/m.md" "${d}/docs/stories/m.md"   # the same edit to m, by hand, unstaged
}
at() { local d="${ROOT}/$1"; shift; (cd "${d}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
same_as_base() { if cmp -s "${ROOT}/$1-up/docs/stories/m.md" "${ROOT}/$1/docs/stories/m.md"; then echo same; else echo differs; fi; }
# A hand edit that is already the base's still stops the pull, named, and is left as it is.
setup_app id
out="$(at id reconcile || true)"
check "a board edit equal to the base's stops the pull, named, and stays unstaged" "yes| M docs/stories/m.md|same|review" \
  "$(has "board files are changed here: docs/stories/m.md; land each edit through swarm.sh board-pr, or check the file out to drop it, then run reconcile again" "$(grep 'cannot pull' <<< "${out}")")|$(git -C "${ROOT}/id" status --porcelain -- docs/stories/m.md)|$(same_as_base id)|$(val "${ROOT}/id/docs/stories/k.md" status)"
# A local commit: the pull cannot fast-forward, so nothing is touched and the edit stays.
setup_app nf; "${GIT[@]}" -C "${ROOT}/nf" commit -q --allow-empty -m "local"
out="$(at nf reconcile || true)"
check "no fast-forward: reconcile stops and says why" "yes" "$(has "cannot fast-forward" "${out}")"
check "no fast-forward: the board edit survives, unstaged" " M docs/stories/m.md|same" \
  "$(git -C "${ROOT}/nf" status --porcelain -- docs/stories/m.md)|$(same_as_base nf)"
# A changed tracked file outside the board, which the base changes too: stop, name it, touch nothing.
setup_app nb; echo changed >> "${ROOT}/nb/README"
echo "the base's readme" >> "${ROOT}/nb-up/README"
"${GIT[@]}" -C "${ROOT}/nb-up" commit -q -am "edit README" && "${GIT[@]}" -C "${ROOT}/nb-up" push -q origin main
out="$(at nb reconcile || true)"
check "a changed file outside the board stops reconcile, named, with no advice to check it out" "yes|no" \
  "$(has "board files are changed here: docs/stories/m.md; land each edit through swarm.sh board-pr, or check the file out to drop it; files outside the board are changed here: README; commit or move each change, then run reconcile again" "${out}")|$(if grep -q "pull it by hand" <<< "${out}"; then echo yes; else echo no; fi)"
check "and the board edit survives" " M docs/stories/m.md" "$(git -C "${ROOT}/nb" status --porcelain -- docs/stories/m.md)"
# A staged edit, even one equal to the base's, stops the pull too, and keeps its content.
setup_app st; "${GIT[@]}" -C "${ROOT}/st" add docs/stories/m.md
out="$(at st reconcile || true)"
check "a staged edit stops the pull, named, and stays staged" "yes|M  docs/stories/m.md|same" \
  "$(has "board files are changed here: docs/stories/m.md" "${out}")|$(git -C "${ROOT}/st" status --porcelain -- docs/stories/m.md)|$(same_as_base st)"
# No tracked edit, but an untracked file the base adds: git refuses the pull, and nothing changes.
setup_app pf; git -C "${ROOT}/pf" checkout -q -- docs/stories/m.md
echo "theirs" > "${ROOT}/pf-up/notes.txt"
"${GIT[@]}" -C "${ROOT}/pf-up" add notes.txt && "${GIT[@]}" -C "${ROOT}/pf-up" commit -q -m notes && "${GIT[@]}" -C "${ROOT}/pf-up" push -q origin main
echo "mine" > "${ROOT}/pf/notes.txt"
out="$(at pf reconcile || true)"
check "a pull git refuses is reported, naming the file" "yes|yes" \
  "$(has "git refused the pull (" "${out}")|$(has "notes.txt" "$(grep 'cannot pull' <<< "${out}")")"
check "and the untracked file, HEAD and the merged item are as they were" "mine|$(git -C "${ROOT}/pf.git" rev-parse main~2)|review" \
  "$(cat "${ROOT}/pf/notes.txt")|$(git -C "${ROOT}/pf" rev-parse HEAD)|$(val "${ROOT}/pf/docs/stories/k.md" status)"

# --- reconcile pulls a main checkout that is behind, with no review item merged. setup_behind <name>
# [ahead]: a bare origin whose board has g and h and a tracked README; its main checkout <name>, with
# h flipped to ready by unblock, in its state file; with ahead, a clone pushes a commit to the base
# that deletes g.
setup_behind() {
  local d="${ROOT}/$1"
  "${GIT[@]}" init -q --bare "${d}.git"
  "${GIT[@]}" clone -q "${d}.git" "${d}" 2>/dev/null
  item "${d}/docs" stories/g.md "status: ready" "kind: code"
  item "${d}/docs" stories/h.md "status: blocked" "kind: code" "depends_on: [t]"
  echo readme > "${d}/README"
  "${GIT[@]}" -C "${d}" add docs README && "${GIT[@]}" -C "${d}" commit -q -m board && "${GIT[@]}" -C "${d}" push -q origin main
  if [[ $# -gt 1 ]]; then
    "${GIT[@]}" clone -q "${d}.git" "${d}-up"
    "${GIT[@]}" -C "${d}-up" rm -q docs/stories/g.md && "${GIT[@]}" -C "${d}-up" commit -q -m "a board PR" && "${GIT[@]}" -C "${d}-up" push -q origin main
  fi
  at "$1" unblock >/dev/null
}
tree() { git -C "${ROOT}/$1" rev-parse HEAD; git -C "${ROOT}/$1" status --porcelain -- . ':!.swarm'; git -C "${ROOT}/$1" diff; }   # .swarm/ is swarm.sh's own state
setup_behind bp ahead
out="$(at bp reconcile; echo "exit $?")"
check "no item merged, the base ahead: reconcile fast-forwards, g is gone, h keeps its flip" "yes|$(git -C "${ROOT}/bp.git" rev-parse main)|gone|ready" \
  "$(has "exit 0" "${out}")|$(git -C "${ROOT}/bp" rev-parse HEAD)|$(gone "${ROOT}/bp/docs/stories/g.md")|$(val "${ROOT}/bp/docs/stories/h.md" status)"
# Edits to README and h's body, files the pull leaves alone (as Obsidian rewrites its own): the pull goes, and they stay.
setup_behind bo ahead; echo changed >> "${ROOT}/bo/README"; echo "a local note" >> "${ROOT}/bo/docs/stories/h.md"
rc=0; at bo reconcile >/dev/null || rc=$?
check "no item merged, changed files the pull does not touch: reconcile pulls, and keeps the edits" "0|$(git -C "${ROOT}/bo.git" rev-parse main)|gone| M README| M docs/stories/h.md" \
  "${rc}|$(git -C "${ROOT}/bo" rev-parse HEAD)|$(gone "${ROOT}/bo/docs/stories/g.md")|$(git -C "${ROOT}/bo" status --porcelain --untracked-files=no | paste -sd'|' -)"
setup_behind bn; echo changed >> "${ROOT}/bn/README"; before="$(tree bn)"   # a pull, if tried, would stop on README
out="$(at bn reconcile; echo "exit $?")"
check "no item merged, the base not ahead: reconcile prints nothing, and HEAD is unchanged" "exit 0|same" \
  "${out}|$([[ "$(tree bn)" == "${before}" ]] && echo same || echo differs)"
# g is in review and gh cannot read its PR: if it merged, the pull would take g before its build is cleared.
setup_behind bu ahead; at bu review g "${U}/99" >/dev/null
out="$(at bu reconcile; echo "exit $?")"
check "no item merged, a PR unread: reconcile does not pull, and names the PR" "yes|exit 0|$(git -C "${ROOT}/bu.git" rev-parse main~1)|there" \
  "$(has "reconcile: not pulling ${ROOT}/bu: gh cannot read ${U}/99 (g)" "${out}")|$(tail -1 <<< "${out}")|$(git -C "${ROOT}/bu" rev-parse HEAD)|$([[ -e "${ROOT}/bu/docs/stories/g.md" ]] && echo there || echo gone)"
# The same with h in review, its PR merged: nothing is pulled while g's PR is unread, so h, whose PR
# may have deleted it on the base, stays in review for the reconcile that pulls.
setup_behind bw ahead; at bw review g "${U}/99" >/dev/null; at bw review h "${U}/1" >/dev/null
out="$(at bw reconcile; echo "exit $?")"
check "an item merged, a PR unread: reconcile does not pull, names the PR, and leaves the item in review" "yes|exit 0|$(git -C "${ROOT}/bw.git" rev-parse main~1)|there|review ${U}/1|yes|" \
  "$(has "reconcile: not pulling ${ROOT}/bw: gh cannot read ${U}/99 (g)" "${out}")|$(tail -1 <<< "${out}")|$(git -C "${ROOT}/bw" rev-parse HEAD)|$(gone "${ROOT}/bw/docs/stories/g.md")|$(val "${ROOT}/bw/docs/stories/h.md" status) $(val "${ROOT}/bw/docs/stories/h.md" prs)|$(has "merged: h, not pulled yet; it stays in review until reconcile pulls ${ROOT}/bw" "${out}")|$(git -C "${ROOT}/bw" status --porcelain --untracked-files=no)"
# Nothing behind: no pull was due, so an unread PR holds nothing back, and reconcile says nothing of it.
setup_behind bv; at bv review g "${U}/99" >/dev/null
check "no pull due, a PR unread: no not-pulling note" "no" "$(if at bv reconcile | grep -q "not pulling"; then echo yes; else echo no; fi)"
# Offline: the fetch fails, so reconcile cannot tell it is behind, says so, and exits 0.
setup_behind bf ahead; git -C "${ROOT}/bf" remote set-url origin "${ROOT}/missing.git"
out="$(at bf reconcile; echo "exit $?")"
check "no item merged, a failed fetch: reconcile says the checkout may be behind, and exits 0" "yes|exit 0" \
  "$(has "reconcile: cannot fetch ${ROOT}/bf, so it may be behind its upstream" "${out}")|$(tail -1 <<< "${out}")"

# --- The merge guard: every Claude agent starts unable to run gh pr merge, a conductor with merge = agent too.
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
start() { # <slug> — start a story with the stubs, and print herdr's agent start line
  item "${b}" "stories/$1.md" "status: ready" "kind: code" "repo: svc"
  (cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" story "$1" >/dev/null 2>&1)
  grep "^agent start $1 " "${ROOT}/herdr.log"
}
conductor() { # <epic> — start its conductor with the stubs, and print herdr's agent start line
  item "${b}" "epics/$1.md" "status: active"
  (cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" conduct "$1" >/dev/null 2>&1)
  grep "^agent start conduct-$1 " "${ROOT}/herdr.log" | tail -1
}
GUARD='--disallowedTools Bash(gh pr merge:*)'
check "merge = human (the default) starts a story agent and a conductor with gh pr merge disallowed" "yes|yes" \
  "$(has "${GUARD}" "$(start g1)")|$(has "${GUARD}" "$(conductor e)")"
echo "merge = agent" > "${p}/.claude/swarm/config"
check "merge = agent keeps the guard on a story agent and on the conductor, which merges through swarm.sh merge" "yes|yes" \
  "$(has "${GUARD}" "$(start g2)")|$(has "${GUARD}" "$(conductor e)")"
check "a story agent's and a conductor's sessions carry SWARM_AGENT, their name, for the guard hook" "yes|yes" \
  "$(has '"SWARM_AGENT":"g2"' "$(grep "^agent start g2 " "${ROOT}/herdr.log")")|$(
  has '"SWARM_AGENT":"conduct-e"' "$(grep "^agent start conduct-e " "${ROOT}/herdr.log" | tail -1)")"
check "a builder's brief says who merges: a human, or with merge = agent the conductor or the lead" "yes|yes" \
  "$(has "Never merge, by any route (a human merges)." "$(cat "${p}/.swarm/briefs/g1.md")")|$(has "Never merge, by any route (the conductor or the lead merges, with swarm.sh merge)." "$(cat "${p}/.swarm/briefs/g2.md")")"
rm -f "${p}/.swarm/state/e" "${b}/epics/e.md"   # the conductor's tab record, which tidy below would list

# --- The review agent's and the fallback reviewer's briefs: the lead's checklist, and each line of the
# story and its epic (whose decisions sit in its Done when, as on a real board) that holds a user's
# decision, verbatim with its path:line, cut at 1500 bytes, all of them at 2000. A mark in code, a
# fence, or the story's Done when is quoted, not a decision.
item "${b}" epics/rv.md "status: active"
printf '%s\n' "**Done when:**" "- **Release in three groups (user, 2026-10-17).** RV-DECISION, which the PR reverses." \
  "- **Fewer parts (user, 2026-10-17).**" "  - RV-SUB-ONE" "- Quotes \`(user, 2026-10-17)\` only in code RV-CODE" "" \
  '```' "- (user, 2026-10-17) RV-FENCE" '```' >> "${b}/epics/rv.md"
start rv1 >/dev/null
printf '%s\n' --- "status: review" "kind: code" "epic: rv" "repo: svc" "touches: [x.sh]" --- "" "# rv1" "" \
  "**Done when:**" "- one release, not three" "- it quotes (user, 2026-10-17) RV-DW-QUOTE" "" "## Notes" "" \
  "Accents (user, 2026-10-17): x$(printf 'é%.0s' $(seq 1000))" "" \
  "Filler (user, 2026-10-17): RV-FILLER $(printf 'y%.0s' $(seq 600))" > "${b}/stories/rv1.md"
wt="$(git -C "${ROOT}/svc" worktree list --porcelain | sed -n 's/^worktree \(.*rv1\)$/\1/p')"
git -C "${wt}" rev-parse HEAD > "${ROOT}/gh/head"
(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" review-agent rv1 "${U}/8" >/dev/null 2>&1) \
  || echo "FAIL review-agent rv1 did not start"
brief="$(cat "${p}/.swarm/briefs/review-rv1.md" 2>/dev/null)"
# fallback [story] — the fallback reviewer's brief after codex hits its usage limit in rv1's
# worktree, for SWARM_STORY=<story> or none; a run past 30 s is KILLed.
mkdir -p "${ROOT}/limit-bin"; printf '#!/bin/sh\necho "ERROR: You have hit your usage limit." >&2\nexit 1\n' > "${ROOT}/limit-bin/codex"
chmod +x "${ROOT}/limit-bin/codex"
fallback() {
  local pid i id
  cp "${p}/.claude/swarm/config" "${ROOT}/config.keep"
  { cat "${ROOT}/config.keep"; echo "fallback_reviewer = sonnet"; } > "${p}/.claude/swarm/config"
  (cd "${wt}" && exec env -u SWARM_PROJECT -u SWARM_STORY ${1:+SWARM_STORY="$1"} SWARM_PROJECT="${p}" HERDR_ENV=1 HERDR_WORKSPACE_ID=w \
    SWARM_CODEX_SECONDS=5 SWARM_FALLBACK_MIN_SECONDS=1 SWARM_CONDUCTOR_POLL=1 PATH="${ROOT}/limit-bin:${ROOT}/bin:${PATH}" bash "${SWARM}" codex-review main >/dev/null 2>&1) &
  pid=$!
  for ((i = 0; i < 150; i++)); do kill -0 "${pid}" 2>/dev/null || break; sleep 0.2; done
  kill -0 "${pid}" 2>/dev/null && kill -KILL "${pid}"; wait "${pid}" || true
  cp "${ROOT}/config.keep" "${p}/.claude/swarm/config"
  id="${1:-${wt##*/}}"; cat "${p}/.swarm/briefs/fallback/${id:0:32}.md" 2>/dev/null || echo "no fallback brief"
}
fbrief="$(fallback rv1)"; fbare="$(fallback)"
CHECKLIST=(
  "- A claim checked against a stand-in (a mock, a sibling API, a narrower sample) is unverified."
  "- An audit or test scoped to one file, when the defect class spans many, is a finding."
  "- A new code path must enforce every rule the existing paths enforce."
  "- A zero or empty value shown to a person must say what it means."
  "- A repair path that changes something must say what it did."
  "- For each function, command-line flag or error message the diff changes, re-read its header comment, error text and every README, doc, command or skill line that names it."
  "- An exception to the scope rule above: a comment, doc or error-text line the changed code no longer matches is a finding at its file:line, even when that file is outside the touches."
  "- For each wait, external call (gh, herdr, curl) and status the diff adds, name its timeout, its failure, what clears it and what a second concurrent run does; a missing answer is a finding."
  "- A change that contradicts a decision marked \`(user, <date>)\` in the epic or story is a finding, even when it is stricter."
)
for l in "${CHECKLIST[@]}"; do
  check "the review agent's and the fallback's briefs carry: ${l:2:40}..." "yes|yes|yes" \
    "$(has "${l}" "${brief}")|$(has "${l}" "${fbrief}")|$( (( ${#l} < 200 )) && echo yes || echo "no, ${#l} bytes")"
done
SCOPE="A point that only a change to a file outside the touches can fix is out of scope, not a finding. A gap in the PR's own code is a finding, even where the touches and Done when do not name it."
check "both briefs say, in the same words, a point only a file outside the touches can fix is out of scope and a gap in the PR's own code is a finding" "yes|yes" \
  "$(has "${SCOPE}" "${brief}")|$(has "${SCOPE}" "${fbrief}")"
check "neither brief still says work outside the touches is not a finding" "0|0" \
  "$(grep -ci 'outside them is not a finding' <<< "${brief}" || true)|$(grep -ci 'outside them is not a finding' <<< "${fbrief}" || true)"
check "the review brief's Out of scope holds only what a change outside the touches can fix" "yes" \
  "$(has "raised that only a" "${brief}")"
check "the review agent's brief has the checklist among what to check, before When the review is done" "yes" \
  "$(awk '/^Hold the PR to these/ { h = NR } /^When the review is done/ { w = NR } END { print (h && w && h < w) ? "yes" : "no" }' <<< "${brief}")"
# marked_at <file> <text> — the line a brief should show for <file>'s line holding <text>: "- <file>:<n>: <line>",
# <file> relative to the project.
marked_at() { local n; n="$(grep -nF -- "$2" "$1" | head -1 | cut -d: -f1)"; printf -- '- %s:%s: %s' "${1#"${p}"/}" "${n}" "$(sed -n "${n}p" "$1")"; }
for l in "$(marked_at "${b}/epics/rv.md" RV-DECISION)" "$(marked_at "${b}/epics/rv.md" "Fewer parts")"; do
  check "both briefs carry the epic's marked line verbatim with its project-relative path:line: ${l}" "yes|yes" "$(has "${l}" "${brief}")|$(has "${l}" "${fbrief}")"
done
READ="Read each decision in full at that line (it may continue on the following lines or list items) before you judge the PR against it."
check "both briefs tell the reviewer to read each decision in full at its line" "yes|yes" "$(has "${READ}" "${brief}")|$(has "${READ}" "${fbrief}")"
for w in RV-SUB-ONE RV-CODE RV-FENCE RV-FILLER; do
  check "neither brief carries ${w}: an unmarked line, a mark in code or a fence, or past the 2000 bytes" "0|0" \
    "$(grep -c "${w}" <<< "${brief}" || true)|$(grep -c "${w}" <<< "${fbrief}" || true)"
done
check "a mark in the story's Done when is not a decision: RV-DW-QUOTE is only in the Done when each brief quotes" "1|1" \
  "$(grep -c RV-DW-QUOTE <<< "${brief}" || true)|$(grep -c RV-DW-QUOTE <<< "${fbrief}" || true)"
NOTE="1 more decision is left out of this brief (past 2000 bytes): read ${b#"${p}"/}/stories/rv1.md."
check "both briefs say how many decisions were left out and where they are" "yes|yes" "$(has "${NOTE}" "${brief}")|$(has "${NOTE}" "${fbrief}")"
utf8() { python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8"); print("yes")' 2>/dev/null || echo no; }
check "a 2000-byte marked line of two-byte characters is cut at 1500 bytes on a character boundary, with an ellipsis: both briefs stay valid UTF-8" "yes|yes|yes|1|0" \
  "$(utf8 <<< "${brief}")|$(utf8 <<< "${fbrief}")|$(has "$(marked_at "${b}/stories/rv1.md" Accents | cut -c1-200)" "${brief}")|$(
  grep -c 'Accents (user, 2026-10-17): x.*…$' <<< "${brief}" || true)|$(grep -c "$(printf 'é%.0s' $(seq 1000))" <<< "${brief}" || true)"
for l in "${CHECKLIST[@]:0:${#CHECKLIST[@]}-1}"; do
  check "a fallback brief with no story still carries: ${l:2:40}..." "yes" "$(has "${l}" "${fbare}")"
done
check "a fallback brief with no story has neither the decision check nor any decision" "0|0" \
  "$(grep -c '(user, ' <<< "${fbare}" || true)|$(grep -c RV-DECISION <<< "${fbare}" || true)"
check "the fallback runs leave the project's config as they found it" "merge = agent" "$(cat "${p}/.claude/swarm/config")"
rm -f "${p}/.swarm/state/rv" "${p}/.swarm/state/fallback" "${b}/epics/rv.md" "${b}/stories/rv1.md"

# --- Starting an agent: a taken name, a failed start, codex's update check.
echo brief > "${ROOT}/brief.md"
agent() { # <name> <role> — start one agent with the stubs, and print swarm's output
  : > "${ROOT}/herdr.log"
  (cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w CLAUDE_STUB_AGENTS="${ROOT}/name-sessions.json" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" agent t "$1" "${p}" "$2" "${ROOT}/brief.md" 2>&1) || true
}
# holder <herdr status> <session status> [waitingFor] — herdr lists lead in this project's pane w:9
# as <herdr status>, and lead's newest agents.tsv line records the session s-lead, listed by Claude
# Code as <session status> (`none`: not listed, so gone; `-`: no session recorded, so herdr answers).
# $OLD is the status of s-old, an older session of the name.
holder() {
  local sess=s-lead; [[ "$2" != - ]] || sess=-
  echo "{\"result\":{\"agents\":[{\"name\":\"lead\",\"agent_status\":\"$1\",\"pane_id\":\"w:9\"}]}}" > "${ROOT}/agents.json"
  printf '2026-10-13\tlead\tlead\tclaude\topus\thigh\t%s\n' "${sess}" >> "${p}/.swarm/agents.tsv"
  { printf '[{"sessionId":"s-old","status":"%s"}' "${OLD:-idle}"
    [[ "$2" == none || "$2" == - ]] || printf ',{"sessionId":"s-lead","status":"%s"%s}' "$2" "${3:+,\"waitingFor\":\"$3\"}"
    echo ']'; } > "${ROOT}/name-sessions.json"
}
old_line() { printf '2026-10-13\tlead\tlead\tclaude\topus\thigh\ts-old\n' >> "${p}/.swarm/agents.tsv"; }
started() { grep -E '^agent (rename|start) ' "${ROOT}/herdr.log" | awk '{print $1, $2, $3, ($2 == "rename" ? $4 : "")}' | sed 's/ $//' | paste -sd'|' -; }
paned() { grep -qE '^(tab create|pane split)' "${ROOT}/herdr.log" && echo yes || echo no; }
refuses() { # <name> <want in the output> — the start just run was refused, saying so, before any pane or rename
  check "$1" "yes|no|no" "$(has "$2" "${out}")|$(paned)|$(grep -q '^agent rename' "${ROOT}/herdr.log" && echo yes || echo no)"
}
mkdir -p "${p}/.swarm/state"; echo "w:9 lead" > "${p}/.swarm/state/own"   # w:9 is this project's pane
holder working idle; agent lead lead >/dev/null
check "a holder whose session is idle (herdr: working) is retired, and the start goes on" "agent rename w:9 lead-done|agent start lead" "$(started)"
holder idle none; agent lead lead >/dev/null
check "a holder whose session is gone is retired, and the start goes on" "agent rename w:9 lead-done|agent start lead" "$(started)"
holder idle idle
echo '{"result":{"agents":[{"name":"lead","agent_status":"idle","pane_id":"w:9"},{"name":"lead-done","agent_status":"idle","pane_id":"w:8"}]}}' > "${ROOT}/agents.json"
agent lead lead >/dev/null
check "a name reused a second time retires to the next free -done name" "agent rename w:9 lead-done2|agent start lead" "$(started)"
holder "done" busy; out=$(agent lead lead)
refuses "a holder whose session is busy (herdr: done) stops the start before any pane opens" "still working"
holder idle waiting "permission prompt"; out=$(agent lead lead)
refuses "a holder whose session is waiting stops the start, naming what it waits for" "waiting on permission prompt"
holder idle compacting; out=$(agent lead lead)
refuses "a holder whose session state is unknown stops the start" "(unknown)"
old_line; OLD=busy holder idle idle; agent lead lead >/dev/null
check "a reused name reads the newer line (older busy, newer idle): retired" "agent rename w:9 lead-done|agent start lead" "$(started)"
OLD=busy holder idle idle; old_line; out=$(agent lead lead)
refuses "a reused name reads the newer line (older idle, newer busy): refused" "still working"
# herdr's holder decides first: with none here, the name is free, whatever an old session says.
holder idle busy; echo '{"result":{"agents":[]}}' > "${ROOT}/agents.json"; agent lead lead >/dev/null
check "an old line whose session is busy, with no herdr holder, lets the start go on" "agent start lead" "$(started)"
echo '{"result":{"agents":[{"name":"lead","agent_status":"idle","pane_id":"w:77"}]}}' > "${ROOT}/agents.json"; out=$(agent lead lead)
refuses "another project's agent holding the name is refused, never retired, before any pane opens" "an agent this project did not start"
# No session recorded (as for codex): herdr answers for the holder.
holder working -; out=$(agent lead lead)
refuses "a holder with no session that herdr reports working stops the start" "still working"
holder blocked -; out=$(agent lead lead)
refuses "a holder with no session that herdr reports blocked stops the start" "waiting on a prompt"
holder idle -; agent lead lead >/dev/null
check "a holder with no session that herdr reports idle is retired" "agent rename w:9 lead-done|agent start lead" "$(started)"
# Only a finished holder is retired: herdr giving no status, or one not known to be finished, refuses.
holder "" -; out=$(agent lead lead)
refuses "a holder with no session and no herdr status is refused as unknown, not retired" "herdr gives no state for the agent holding this name (unknown)"
holder starting -; out=$(agent lead lead)
refuses "a holder with no session in a herdr state not known to be finished is refused, naming it" "is 'starting', not finished"
# A rename that leaves the name held: the check after retiring stops the start.
holder idle idle; touch "${ROOT}/rename-noop"; out=$(agent lead lead); rm -f "${ROOT}/rename-noop"
check "a name still held after retiring stops the start before any pane opens" "yes|no" "$(has "still taken after retiring" "${out}")|$(paned)"
rm -f "${ROOT}/agents.json"; touch "${ROOT}/start-fails"; out=$(agent l2 lead)
check "a failed start closes its pane and shows herdr's error" "yes|yes" \
  "$(grep -q '^pane close ' "${ROOT}/herdr.log" && echo yes || echo no)|$(has agent_name_taken "${out}")"
rm -f "${ROOT}/start-fails"; agent cx codex >/dev/null
check "codex starts with its update check off" "yes" "$(has 'check_for_update_on_startup=false' "$(grep '^agent start cx ' "${ROOT}/herdr.log")")"
check "codex outside a planning tab stays read-only" "yes" "$(has '-s read-only' "$(grep '^agent start cx ' "${ROOT}/herdr.log")")"
: > "${ROOT}/herdr.log"
(cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" agent scope-ep cx4 "${p}" codex "${ROOT}/brief.md" >/dev/null 2>&1) || true
check "a planning codex writes only in its tab's output dir, told where paths start" "yes|yes|yes" \
  "$(has "-s workspace-write -C ${p}/.swarm/ep -c" "$(grep '^agent start cx4 ' "${ROOT}/herdr.log")")|$([[ -d "${p}/.swarm/ep" ]] && echo yes || echo no)|$(has "The project is ${p}; every relative path below is relative to it." "$(grep '^agent prompt w:' "${ROOT}/herdr.log")")"
check "codex starts with hooks off, so no trust dialog can take the brief" "yes" "$(has '-c features.hooks=false' "$(grep '^agent start cx4 ' "${ROOT}/herdr.log")")"
(cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" agent plan-h cxh "${p}" codex "${ROOT}/brief.md" >/dev/null 2>&1) || true
check "an HLD-planning codex (tab plan-<hld>) writes only in .swarm/<hld>" "yes" \
  "$(has "-s workspace-write -C ${p}/.swarm/h -c" "$(grep '^agent start cxh ' "${ROOT}/herdr.log")")"

# --- The session id: minted once per claude agent, passed to herdr, and recorded before the brief.
tsv="${p}/.swarm/agents.tsv"
sid() { grep "^agent start $1 " "${ROOT}/herdr.log" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p' | paste -sd' ' -; }
logged() { awk -F'\t' -v n="$1" '$3 == n { print $7 }' "${tsv}" 2>/dev/null; }
uuid() { grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' <<< "$1" && echo yes || echo no; }
agent sid1 lead >/dev/null; s="$(sid sid1)"
check "a claude agent starts with a minted --session-id, and its agents.tsv line ends in it" "yes|${s}" "$(uuid "${s}")|$(logged sid1)"
touch "${ROOT}/start-fails-once"; agent sid2 lead >/dev/null; s="$(sid sid2)"
check "a start retried after a failed first try reuses the same session id" "2|yes|${s%% *}" \
  "$(wc -w <<< "${s}" | tr -d ' ')|$(uuid "${s%% *}")$([[ "${s% *}" == "${s#* }" ]] || echo ' (two ids)')|$(logged sid2)"
# herdr reports a session for every pane, so a codex line that read it back would not end in '-'.
echo '{"result":{"agents":[{"name":"x","agent_status":"idle","pane_id":"w:1","agent_session":{"value":"herdr-sess"}},{"name":"y","agent_status":"idle","pane_id":"w:2","agent_session":{"value":"herdr-sess"}}]}}' > "${ROOT}/agents.json"
agent cx5 codex >/dev/null
check "a codex start has no --session-id, and its line ends in '-'" "no|-" \
  "$(grep -q -- '--session-id' "${ROOT}/herdr.log" && echo yes || echo no)|$(logged cx5)"
rm -f "${ROOT}/agents.json"; touch "${ROOT}/prompt-idle"; agent sid3 lead >/dev/null; rm -f "${ROOT}/prompt-idle"
check "a start whose brief is not taken up still leaves its line, and every line has 7 fields" "yes|$(sid sid3)|0" \
  "$(uuid "$(logged sid3)")|$(logged sid3)|$(awk -F'\t' 'NF != 7' "${tsv}" | wc -l | tr -d ' ')"
# A python3 that cannot mint the id stops the start, by name, before any pane opens.
mkdir -p "${ROOT}/nouuid"
printf '#!/bin/sh\ncase "$*" in *uuid*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v python3)" > "${ROOT}/nouuid/python3"
chmod +x "${ROOT}/nouuid/python3"; : > "${ROOT}/herdr.log"
out=$(cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/nouuid:${ROOT}/bin:${PATH}" bash "${SWARM}" agent t sid4 "${p}" lead "${ROOT}/brief.md" 2>&1) || true
check "a session id that cannot be minted stops the start, named, before any pane opens" "yes|no" \
  "$(has 'could not mint a session id (python3)' "${out}")|$(grep -qE '^(tab create|pane split)' "${ROOT}/herdr.log" && echo yes || echo no)"

# --- status: each open pane's agent, from its Claude session (the claude stub) where one is recorded,
# else herdr's word; an empty pane; and what waits on the user.
mkdir -p "${p}/.swarm/state"
printf '%s\n' 'w:5 lead' 'w:6 builder' 'w:7 closed' > "${p}/.swarm/state/t"
printf '%s\n' 'w:8 finished' 'w:10 waiter' 'w:11 lost' 'w:12 odd' 'w:13 re' 'w:14 re' 'w:15 cx9' 'w:16 nosess' 'w:17 authed' >> "${p}/.swarm/state/t"
printf '%s\n' 'w:8 finished' > "${p}/.swarm/state/t-2"
# re is a reused name: its older line's agent was retired to re-done (w:13), and the newer one runs in w:14.
tsvline() { printf '2026-10-13\tcode\t%s\t%s\topus\thigh\t%s\n' "$@" >> "${p}/.swarm/agents.tsv"; }
tsvline builder claude s-builder; tsvline finished claude s-finished; tsvline waiter claude s-waiter
tsvline lost claude s-lost; tsvline odd claude s-odd; tsvline re claude s-re-old; tsvline re claude s-re-new
tsvline cx9 codex -; tsvline nosess claude -; tsvline authed claude s-authed
# authed is idle, and its transcript ends on an expired login (the fixture wait's tests use).
mkdir -p "${ROOT}/projects/p"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl" "${ROOT}/projects/p/s-authed.jsonl"
# herdr's word, where the session must win: builder done while busy, finished working while idle,
# waiter and lost idle, odd working; re's newer agent says <re> (STATUS_RE) and its retired one idle.
herdr_agents() { # <re's herdr status>
  printf '{"result":{"agents":[%s]}}\n' "$(printf '{"name":"%s","agent_status":"%s","pane_id":"%s"},' \
    builder "done" w:6 finished working w:8 waiter idle w:10 lost idle w:11 odd working w:12 \
    re-done idle w:13 re "$1" w:14 cx9 blocked w:15 nosess starting w:16 authed idle w:17 | sed 's/,$//')"
}
echo '{"result":{"panes":[{"pane_id":"w:5"},{"pane_id":"w:6"},{"pane_id":"w:8"},{"pane_id":"w:10"},{"pane_id":"w:11"},{"pane_id":"w:12"},{"pane_id":"w:13"},{"pane_id":"w:14"},{"pane_id":"w:15"},{"pane_id":"w:16"},{"pane_id":"w:17"}]}}' > "${ROOT}/panes.json"
sessions() { # <re's older status> <re's newer status> [waiter's waitingFor, as JSON string text]
  printf '[{"sessionId":"s-builder","status":"busy"},{"sessionId":"s-finished","status":"idle"},{"sessionId":"s-waiter","status":"waiting","waitingFor":"%s"},{"sessionId":"s-odd","status":"compacting"},{"sessionId":"s-re-old","status":"%s"},{"sessionId":"s-re-new","status":"%s"},{"sessionId":"s-authed","status":"idle"}]\n' "${3:-input}" "$1" "$2" > "${ROOT}/sessions.json"
}
herdr_agents working > "${ROOT}/agents.json"; sessions busy idle
item "${b}" stories/ls.md "status: ready" "kind: lead"
status() { (cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w CLAUDE_PROJECTS_DIR="${ROOT}/projects" CLAUDE_STUB_AGENTS="${CLAUDE_STUB_AGENTS:-${ROOT}/sessions.json}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status "$@" 2>&1); }
row() { grep -E "^  $1 " <<< "$2" | sed -E 's/ +/ /g; s/^ //; s/ \[.*//'; }
out=$(status); all=$(status --all)
check "status shows a pane whose agent never started as empty" "yes" \
  "$(grep -qE '^  lead +EMPTY' <<< "${out}" && echo yes || echo "no, got: ${out}")"
check "status shows a busy session as working while herdr says done" "builder working" "$(row builder "${out}")"
check "status leaves out a pane closed by hand" "no" "$(grep -q 'closed' <<< "${all}" && echo yes || echo no)"
check "status shows an idle session as idle while herdr says working" "finished idle: finished, or waiting for its next step" "$(row finished "${all}")"
check "status shows a waiting session's waitingFor" "waiter WAITING on input: herdr agent read waiter" "$(row waiter "${out}")"
check "status shows a recorded session with no entry as gone" "lost gone: session ended" "$(row lost "${out}")"
check "status shows a session in a state it does not know as unknown" "odd unknown: no session state" "$(row odd "${out}")"
check "an idle agent whose login expired shows auth and /login" "authed auth: its login expired; run /login, then /swarm-dev:swarm tells it to resume" "$(row authed "${out}")"
check "status counts gone, unknown and auth as needing a look, never idle" "Agents: 8 need a look or are working, 3 idle or done" "$(sed -n 1p <<< "${out}")"
check "a reused name shows the newer session (older busy, newer idle), and the retired pane retired" "re idle: finished, or waiting for its next step|re-done done (retired)" \
  "$(row re "${all}")|$(row re-done "${all}")"
herdr_agents idle > "${ROOT}/agents.json"; sessions idle busy
check "a reused name shows the newer session (older idle, newer busy), and the retired pane retired" "re working|re-done done (retired)" \
  "$(row re "$(status --all)")|$(row re-done "$(status --all)")"
sessions idle busy 'Allow Bash to run:\n  rm -rf build && make all && make test && make install && echo done\n(y/n)'
check "status shows a long, multi-line waitingFor on one line, cut with …" "waiter WAITING on Allow Bash to run: rm -rf build && make all && make test &&…: herdr agent read waiter" \
  "$(row waiter "$(status)")"
check "a codex agent herdr says is blocked is WAITING" "cx9 WAITING on a question: herdr agent read cx9" "$(row cx9 "${out}")"
check "an agent with no session recorded shows herdr's word" "nosess starting" "$(row nosess "${out}")"
check "status with a claude that cannot list shows recorded sessions as unknown" "builder unknown: no session state" \
  "$(row builder "$(CLAUDE_STUB_AGENTS="${ROOT}/no-such-file" status)")"
check "status lists a lead story under Waiting on you" "yes" "$(has 'lead: ls' "$(sed -n '/^Waiting on you/,/^Next/p' <<< "${out}")")"
check "status counts an idle agent instead of listing it" "no" "$(grep -qE '^  finished ' <<< "${out}" && echo yes || echo no)"
rm -f "${ROOT}/agents.json" "${ROOT}/panes.json" "${p}/.swarm/state/t" "${p}/.swarm/state/t-2" "${b}/stories/ls.md"

# --- findings: a success check can still carry a failure note (the CodeQL case), and open alerts.
echo '{"check_runs":[{"id":1,"name":"CodeQL","conclusion":"success","output":{"annotations_count":1}},{"id":2,"name":"test","conclusion":"success","output":{"annotations_count":0}}]}' > "${ROOT}/gh/runs.json"
printf '%s\n' '[{"annotation_level":"failure","path":"a.py","start_line":3,"message":"Clear-text logging of sensitive information\nmore"}]' > "${ROOT}/gh/annotations.json"
echo '[{"number":5,"rule":{"id":"py/clear-text-logging","severity":"error","security_severity_level":"high"},"most_recent_instance":{"location":{"path":"a.py","start_line":3},"message":{"text":"This logs a password."}}}]' > "${ROOT}/gh/alerts.json"
out="$(run findings svc 7)"
check "findings prints a failure note on a successful check" "yes" \
  "$(has "check CodeQL (success): failure a.py:3 Clear-text logging of sensitive information" "${out}")"
check "findings prints open code-scanning alerts" "yes" "$(has "alert #5 high py/clear-text-logging a.py:3 This logs a password." "${out}")"

# --- watch --epic and --backlog: a conductor wakes only for its own stories' PRs. Two epics and a
# one-off share a repo; the PRs it must skip come first and have finished their checks too.
w="${ROOT}/watch"
mkdir -p "${w}/.claude/swarm" "${ROOT}/wrepos"
echo "repos_dir = ${ROOT}/wrepos" > "${w}/.claude/swarm/config"
git init -q "${ROOT}/wrepos/svc" && git -C "${ROOT}/wrepos/svc" remote add origin https://github.com/o/svc
item "${w}/docs" epics/mine.md "status: active"
item "${w}/docs" epics/other.md "status: active"
item "${w}/docs" stories/a.md "status: ready" "kind: code" "epic: mine" "repo: svc"
item "${w}/docs" stories/b.md "status: ready" "kind: code" "epic: other" "repo: svc"
item "${w}/docs" stories/c.md "status: ready" "kind: code" "repo: svc"
cat > "${ROOT}/gh/prlist.json" <<'EOF'
[{"number": 1, "headRefName": "story/b", "headRefOid": "head1", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"},
 {"number": 2, "headRefName": "epic/mine", "headRefOid": "head2", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"},
 {"number": 3, "headRefName": "story/a", "headRefOid": "head3", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"},
 {"number": 4, "headRefName": "story/c", "headRefOid": "head4", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]
EOF
# Each watch is bounded, so one that polls on fails here rather than hangs the run.
check "watch --backlog reports a no-epic story's PR and skips every epic story's PR in the same repo" "o/svc #4 story/c checks finished on head4" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 10; exec @ARGV' bash "${SWARM}" watch --backlog 2>&1)"
: > "${ROOT}/gh/calls"
check "watch --epic skips another epic's PR and the epic/<slug> head in the same repo" "o/svc #3 story/a checks finished on head3" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 10; exec @ARGV' bash "${SWARM}" watch --epic mine 2>&1)"
check "watch --epic reads the mergeable state of its own story's PR alone" "api repos/o/svc/pulls/3" \
  "$(grep -o '^api repos/o/svc/pulls/[0-9]*' "${ROOT}/gh/calls" | tr '\n' ' ' | sed 's/ $//')"
# A fix-main story has no epic, but every conductor builds and merges it: an epic's watch wakes for
# its PR too. Bounded, so a watch that skips it fails here rather than polling on.
item "${w}/docs" stories/fix-main-abcdef1.md "status: review" "kind: code" "repo: svc"
cp "${ROOT}/gh/prlist.json" "${ROOT}/gh/prlist.keep"
{ sed 's/}]$/},/' "${ROOT}/gh/prlist.keep"
  echo ' {"number": 5, "headRefName": "story/fix-main-abcdef1", "headRefOid": "head5", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]'; } > "${ROOT}/gh/prlist.json"
check "watch --epic wakes for a fix-main story's PR" "o/svc #5 story/fix-main-abcdef1 checks finished on head5" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 10; exec @ARGV' bash "${SWARM}" watch --epic mine 2>&1)"
mv "${ROOT}/gh/prlist.keep" "${ROOT}/gh/prlist.json"; rm -f "${w}/docs/stories/fix-main-abcdef1.md"

# A check-runs read that fails (a spent rate limit: an error body, exit 1) is unknown for that poll: no
# syntax error, said once, and watch polls on. Bounded at 3 s, polling every 0.12 s.
sed 's/head3/head6/' "${ROOT}/gh/prlist.json" > "${ROOT}/gh/prlist.keep"; mv "${ROOT}/gh/prlist.json" "${ROOT}/gh/prlist.orig"; mv "${ROOT}/gh/prlist.keep" "${ROOT}/gh/prlist.json"
echo '{"message":"API rate limit exceeded for user ID 1.","documentation_url":"https://docs.github.com/rest/overview/rate-limits"}' > "${ROOT}/gh/runs-fail"
: > "${ROOT}/gh/calls"
out="$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0.002 PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 3; exec @ARGV' bash "${SWARM}" watch --epic mine 2>&1 || true)"
check "watch prints no syntax error on a rate-limited check-runs read" "no" "$(grep -q 'syntax error' <<< "${out}" && echo yes || echo no)"
check "watch says a failed check-runs read failed once" "1" "$(grep -c "gh cannot read o/svc #3's check runs" <<< "${out}")"
check "watch polls on after a failed check-runs read" "yes" "$([[ $(grep -c 'commits/head6/check-runs' "${ROOT}/gh/calls") -ge 2 ]] && echo yes || echo no)"
check "watch says why gh could not read the check runs" "1" "$(grep -c "(API rate limit exceeded for user ID 1.)" <<< "${out}")"
check "watch reads up to 100 check runs" "yes" "$(grep -q 'commits/head6/check-runs?per_page=100' "${ROOT}/gh/calls" && echo yes || echo no)"
# One PR's read fails while another's succeeds (its checks still run): the failure is said once, not on
# every poll, and a failure on the other PR is named too once it fails.
item "${w}/docs" stories/fix-main-abcdef1.md "status: review" "kind: code" "repo: svc"
{ sed 's/}]$/},/' "${ROOT}/gh/prlist.json"
  echo ' {"number": 5, "headRefName": "story/fix-main-abcdef1", "headRefOid": "head7", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]'; } > "${ROOT}/gh/prlist.two"
mv "${ROOT}/gh/prlist.two" "${ROOT}/gh/prlist.json"
echo head6 > "${ROOT}/gh/runs-fail-heads"; : > "${ROOT}/gh/calls"
out="$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0.002 PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 3; exec @ARGV' bash "${SWARM}" watch --epic mine 2>&1 || true)"
check "watch says one PR's failed read once while another PR's read succeeds" "1" "$(grep -c "gh cannot read o/svc #3's check runs" <<< "${out}")"
check "watch polls the succeeding PR on every poll beside the failing one" "yes" "$([[ $(grep -c 'commits/head7/check-runs' "${ROOT}/gh/calls") -ge 2 ]] && echo yes || echo no)"
echo 'head6
head7' > "${ROOT}/gh/runs-fail-heads"; : > "${ROOT}/gh/calls"
out="$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0.002 PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 3; exec @ARGV' bash "${SWARM}" watch --epic mine 2>&1 || true)"
check "watch names each PR whose read failed, once each" "1 1" "$(grep -c "gh cannot read o/svc #3's check runs" <<< "${out}") $(grep -c "gh cannot read o/svc #5's check runs" <<< "${out}")"
rm -f "${ROOT}/gh/runs-fail" "${ROOT}/gh/runs-fail-heads" "${w}/docs/stories/fix-main-abcdef1.md"; mv "${ROOT}/gh/prlist.orig" "${ROOT}/gh/prlist.json"

# watch reports this project's agents whose session is waiting, with what each waits for; herdr
# lists every project's (lead, in w:6, is another's). A Claude agent's state is its session's (the
# claude stub), never herdr's; a codex agent (cx) has no session, so herdr answers for it. mine-two is
# a second Claude agent, idle unless $TWO says otherwise. The PR above is already seen, so the next
# event is the agents.
mkdir -p "${w}/.swarm/state"; printf 'w:5 mine-builder\nw:7 cx\nw:8 mine-two\n' > "${w}/.swarm/state/tab"   # this project's panes
printf 'w:6 a brief line\n' > "${w}/.swarm/state/brief-x.md"   # a brief's words are not a pane record
printf '2026-10-13\tcode\t%s\t%s\topus\thigh\t%s\n' mine-builder claude s-mb cx codex - mine-two claude s-two > "${w}/.swarm/agents.tsv"
wagents() { # <mine-builder's herdr status> <cx's herdr status>
  echo "{\"result\":{\"agents\":[{\"name\":\"lead\",\"agent_status\":\"blocked\",\"pane_id\":\"w:6\"},{\"name\":\"mine-builder\",\"agent_status\":\"$1\",\"pane_id\":\"w:5\"},{\"name\":\"cx\",\"agent_status\":\"$2\",\"pane_id\":\"w:7\"},{\"name\":\"mine-two\",\"agent_status\":\"idle\",\"pane_id\":\"w:8\"}]}}" > "${ROOT}/agents.json"
}
wsession() { # <mine-builder's session status> [its waitingFor]; mine-two's session is $TWO (default idle), waiting on $TWO_WHY
  echo "[{\"sessionId\":\"s-mb\",\"status\":\"$1\"${2:+,\"waitingFor\":\"$2\"}},{\"sessionId\":\"s-two\",\"status\":\"${TWO:-idle}\"${TWO_WHY:+,\"waitingFor\":\"${TWO_WHY}\"}}]" > "${ROOT}/watch-sessions.json"
}
# watchrun — run watch --epic mine for at most 10 seconds (Claude's sessions from $WATCH_SESSIONS, else
# watch-sessions.json) and print what it printed, or "(still watching)" once it has read the agents
# and not returned, so a watch that wrongly polls on fails rather than hangs. It runs as swarm.sh's
# own pid (exec), so its sleep is its child: swarm.sh is stopped first, so it is not there to report
# the sleep killed, then the sleep.
watchrun() {
  local pid kids grace=-1
  : > "${ROOT}/herdr.log"
  (cd "${w}" && exec env -u SWARM_PROJECT HERDR_ENV=1 CLAUDE_STUB_AGENTS="${WATCH_SESSIONS:-${ROOT}/watch-sessions.json}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic mine > "${ROOT}/watch.out" 2>&1) &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    kill -0 "${pid}" 2>/dev/null || break
    [[ ${grace} -ne 0 ]] || break   # two seconds after it first read the agents
    if [[ ${grace} -gt 0 ]]; then grace=$((grace - 1)); elif grep -q '^agent list' "${ROOT}/herdr.log"; then grace=2; fi
  done
  if kill -0 "${pid}" 2>/dev/null; then
    kids="$(pgrep -P "${pid}" || true)"; kill "${pid}" 2>/dev/null || true; { wait "${pid}"; } 2>/dev/null || true
    for k in ${kids}; do kill "${k}" 2>/dev/null || true; done
    echo "(still watching)"; return
  fi
  { wait "${pid}"; } 2>/dev/null || true
  cat "${ROOT}/watch.out"
}
wagents idle idle; wsession waiting "permission prompt"
check "watch names this project's agent whose session waits (herdr: idle), with what it waits for" "agent(s) waiting: mine-builder (permission prompt)" "$(watchrun)"
check "watch does not report the same wait twice in a row" "(still watching)" "$(watchrun)"
wagents idle blocked; wsession idle
check "watch names a codex agent herdr reports blocked" "agent(s) waiting: cx" "$(watchrun)"
# herdr says blocked, but the session is busy: nothing needs the lead, so watch polls on.
wagents blocked idle; wsession busy
check "watch does not return on an agent herdr reports blocked whose session is busy" "(still watching)" "$(watchrun)"
# That poll found nothing waiting, so the wait reported first is forgotten: a builder answered that
# stops on a second prompt of the same kind is reported again, not left waiting.
wagents idle idle; wsession waiting "permission prompt"
check "watch reports the same wait again after a poll with nothing waiting" "agent(s) waiting: mine-builder (permission prompt)" "$(watchrun)"
# Each agent's wait is its own: mine-two is answered while mine-builder still waits, then waits again
# on the same text, and is reported again.
TWO=waiting TWO_WHY="permission prompt" wsession waiting "permission prompt"
check "watch reports a second agent waiting while the first still waits" "agent(s) waiting: mine-builder (permission prompt), mine-two (permission prompt)" "$(watchrun)"
wsession waiting "permission prompt"
check "watch is quiet when one of two waiting agents is answered" "(still watching)" "$(watchrun)"
TWO=waiting TWO_WHY="permission prompt" wsession waiting "permission prompt"
check "watch reports an agent that waits again on the same text while another still waits" "agent(s) waiting: mine-builder (permission prompt), mine-two (permission prompt)" "$(watchrun)"
# A read that fails changes nothing: the waits already reported are not reported again after it.
touch "${ROOT}/list-fails"
check "watch is quiet on a poll whose herdr read fails" "(still watching)" "$(watchrun)"
rm -f "${ROOT}/list-fails"
check "watch does not report a wait twice across a failed read" "(still watching)" "$(watchrun)"
# So does a failed Claude Code list, which would read every Claude session unknown, so not waiting.
check "watch is quiet on a poll whose Claude Code list fails" "(still watching)" "$(WATCH_SESSIONS="${ROOT}/no-such-file" watchrun)"
check "watch does not report a wait twice across a failed Claude Code list" "(still watching)" "$(watchrun)"
rm -f "${ROOT}/agents.json"

# --- tidy: closes only empty panes and retired agents' panes; lists them first without --yes.
for f in agents.json panes.json; do [[ -f "${ROOT}/${f}" ]] && mv "${ROOT}/${f}" "${ROOT}/${f}.keep"; done
mkdir -p "${p}/.swarm/state"
printf '%s\n' "w:1 conductor" "w:2 s1" "w:3 s2" "w:4 fix-done" "w:9 gone" > "${p}/.swarm/state/t"
echo '{"result":{"panes":[{"pane_id":"w:1"},{"pane_id":"w:2"},{"pane_id":"w:3"},{"pane_id":"w:4"}]}}' > "${ROOT}/panes.json"
echo '{"result":{"agents":[{"pane_id":"w:1","name":"conduct-t","agent_status":"working"},{"pane_id":"w:3","name":"s2-done","agent_status":"idle"},{"pane_id":"w:4","name":"fix-done","agent_status":"working"}]}}' > "${ROOT}/agents.json"
tidy() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_PANE_ID=w:0 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tidy "$@" 2>&1); }
: > "${ROOT}/herdr.log"
out="$(tidy)"
check "tidy lists the empty pane and the retired one, and closes nothing" "yes|yes|no|no" \
  "$(has "s1  empty: no agent started" "${out}")|$(has "s2-done  retired" "${out}")|$(grep -q 'conduct-t\|fix-done' <<< "${out}" && echo yes || echo no)|$(grep -q 'pane close' "${ROOT}/herdr.log" && echo yes || echo no)"
tidy --yes >/dev/null
check "tidy --yes closes exactly those two, and keeps the rest on record" "pane close w:2|pane close w:3|w:1 conductor w:4 fix-done w:9 gone" \
  "$(grep '^pane close' "${ROOT}/herdr.log" | paste -sd'|' -)|$(tr '\n' ' ' < "${p}/.swarm/state/t" | sed 's/ $//')"
check "tidy --yes refuses to run without HERDR_PANE_ID" "yes" \
  "$(has 'HERDR_PANE_ID is not set' "$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tidy --yes 2>&1)")"
rm -f "${p}/.swarm/state/t" "${ROOT}/panes.json" "${ROOT}/agents.json"
for f in agents.json panes.json; do [[ -f "${ROOT}/${f}.keep" ]] && mv "${ROOT}/${f}.keep" "${ROOT}/${f}"; done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
