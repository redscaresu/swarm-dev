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

item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# Stubs. gh answers from fixture files; herdr accepts everything and logs its arguments.
mkdir -p "${ROOT}/bin" "${ROOT}/gh"
cat > "${ROOT}/bin/gh" <<EOF
#!/bin/sh
F="${ROOT}/gh"
EOF
cat >> "${ROOT}/bin/gh" <<'EOF'
case "$1 $2" in
  "pr view") st=$(awk -v u="$3" '$1 == u { print $2 }' "$F/prs"); [ -n "$st" ] || exit 1
             echo "{\"state\":\"$st\"}"; exit 0 ;;
  "repo view") case " $* " in *" -q "*) echo o/svc ;; *) echo '{"nameWithOwner":"o/svc"}' ;; esac; exit 0 ;;
  "pr list") while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             jq -r "$q" "$F/prlist.json"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/pulls/7) echo '{"head":{"sha":"abc1234def"}}' ;;
  repos/o/svc/commits/abc1234def/check-runs*) cat "$F/runs.json" ;;
  repos/o/svc/check-runs/1/annotations*) cat "$F/annotations.json" ;;
  repos/o/svc/code-scanning/alerts*) cat "$F/alerts.json" ;;
  repos/o/svc/commits/head*/check-runs) while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             echo '{"check_runs":[{"status":"completed"}]}' | jq -r "$q" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
cat > "${ROOT}/bin/herdr" <<EOF
#!/bin/sh
echo "\$*" >> "${ROOT}/herdr.log"
EOF
cat >> "${ROOT}/bin/herdr" <<EOF
A="${ROOT}/agents.json"; F="${ROOT}/start-fails"; P="${ROOT}/panes.json"; O="${ROOT}/start-fails-once"; I="${ROOT}/prompt-idle"; N="${ROOT}/rename-noop"; L="${ROOT}/list-fails"
EOF
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "tab create")   echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "pane split")   echo '{"result":{"pane":{"pane_id":"w:2"}}}' ;;
  "agent prompt") if [ -f "$I" ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'; else echo '{"result":{"agent":{"agent_status":"working"}}}'; fi ;;
  "agent list")   if [ -f "$L" ]; then exit 1; fi; if [ -f "$A" ]; then cat "$A"; else echo '{"result":{"agents":[]}}'; fi ;;
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
item "${b}" stories/n.md "status: blocked" "kind: code" "epic: e1" "blocked_by: [a]"
item "${b}" epics/e1.md "status: active"
run review a "${U}/1" >/dev/null
check "review sets the status and the PRs" "review|${U}/1" \
  "$(sed -n 's/^status: //p' "${b}/stories/a.md")|$(sed -n 's/^prs: //p' "${b}/stories/a.md")"
check "review refuses what is not a PR URL, and leaves the item alone" "yes|review|${U}/1" \
  "$(has 'not a PR URL' "$(run review a "https://example.com/x" || true)")|$(sed -n 's/^status: //p' "${b}/stories/a.md")|$(sed -n 's/^prs: //p' "${b}/stories/a.md")"

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
out="$(run reconcile)"
check "a merged story is finished" "gone" "$([[ -e "${b}/stories/a.md" ]] && echo there || echo gone)"
check "a closed PR sends its story back to ready" "ready" "$(sed -n 's/^status: //p' "${b}/stories/c.md")"
check "and writes no attempts: line: a PR closed unmerged is not a failed build" "" "$(grep '^attempts:' "${b}/stories/c.md" || true)"
check "a story sent back to ready keeps its attempts: as it was" "ready|1" \
  "$(sed -n 's/^status: //p' "${b}/stories/c2.md")|$(sed -n 's/^attempts: //p' "${b}/stories/c2.md")"
check "its prs: line goes, and a body line like it stays" "prs: a line in the body" "$(grep '^prs:' "${b}/stories/c.md")"
check "reconcile says which PR closed" "yes" "$(has "back to ready: c (closed without merging: ${U}/2)" "${out}")"
check "an epic with one of two PRs merged stays in review" "review" "$(sed -n 's/^status: //p' "${b}/epics/e2.md")"
check "an epic with both PRs merged is finished" "gone" "$([[ -e "${b}/epics/e3.md" ]] && echo there || echo gone)"
check "its dependent unblocks once it is finished" "ready: n" "$(run unblock)"

# --- A board in the project repo: the merged PR took the story off itself. reconcile undoes its
# own edits (the review status, a retry's attempts:) so the pull goes through, and if the pull
# cannot, keeps the item in review as it was.
"${GIT[@]}" init -q --bare "${ROOT}/app.git"
"${GIT[@]}" clone -q "${ROOT}/app.git" "${ROOT}/app" 2>/dev/null
item "${ROOT}/app/docs" stories/r.md "status: ready" "kind: code"
item "${ROOT}/app/docs" stories/s.md "status: ready" "kind: code"
"${GIT[@]}" -C "${ROOT}/app" add docs && "${GIT[@]}" -C "${ROOT}/app" commit -q -m board
"${GIT[@]}" -C "${ROOT}/app" push -q origin main
"${GIT[@]}" clone -q "${ROOT}/app.git" "${ROOT}/pr"
"${GIT[@]}" -C "${ROOT}/pr" rm -q docs/stories/r.md && "${GIT[@]}" -C "${ROOT}/pr" commit -q -m "the PR"
inrepo() { (cd "${ROOT}/app" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# r was retried: close left attempts: 1 in the main checkout, uncommitted, and its PR deletes r.
perl -pi -e 's/^kind: code$/kind: code\nattempts: 1/' "${ROOT}/app/docs/stories/r.md"
inrepo review r "${U}/1" >/dev/null
inrepo review s "${U}/4" >/dev/null
"${GIT[@]}" -C "${ROOT}/app" commit -q --allow-empty -m "diverged"
"${GIT[@]}" -C "${ROOT}/pr" push -q origin main
inrepo reconcile >/dev/null || true
check "a pull that fails keeps merged items in review, with their PRs" "review ${U}/1|review ${U}/4" \
  "$(sed -n 's/^status: //p;s/^prs: //p' "${ROOT}/app/docs/stories/r.md" | paste -sd' ' -)|$(sed -n 's/^status: //p;s/^prs: //p' "${ROOT}/app/docs/stories/s.md" | paste -sd' ' -)"
check "and keeps a merged retry's attempts:" "1" "$(sed -n 's/^attempts: //p' "${ROOT}/app/docs/stories/r.md")"
"${GIT[@]}" -C "${ROOT}/app" reset -q --keep HEAD~1
inrepo reconcile >/dev/null || true
gone() { if [[ -e "$1" ]]; then echo there; else echo gone; fi; }
check "the PR's own delete is pulled, and finish takes off what it left" "gone|gone|$(git -C "${ROOT}/app.git" rev-parse main)" \
  "$(gone "${ROOT}/app/docs/stories/r.md")|$(gone "${ROOT}/app/docs/stories/s.md")|$(git -C "${ROOT}/app" rev-parse HEAD)"

# --- A board edit in the main checkout that is already the base's does not stop the pull; one that
# differs still does, and is named. The base gets a new story t and an edit to u.
item "${ROOT}/app/docs" stories/u.md "status: ready" "kind: code"
item "${ROOT}/app/docs" stories/v.md "status: ready" "kind: code"
"${GIT[@]}" -C "${ROOT}/app" add docs && "${GIT[@]}" -C "${ROOT}/app" commit -q -m "u v" && "${GIT[@]}" -C "${ROOT}/app" push -q origin main
"${GIT[@]}" -C "${ROOT}/pr" pull -q --ff-only
item "${ROOT}/pr/docs" stories/t.md "status: ready" "kind: code"
item "${ROOT}/pr/docs" stories/u.md "status: blocked" "kind: code" "blocked_by: [t]"
"${GIT[@]}" -C "${ROOT}/pr" add docs && "${GIT[@]}" -C "${ROOT}/pr" commit -q -m "plan t" && "${GIT[@]}" -C "${ROOT}/pr" push -q origin main
cp "${ROOT}/pr/docs/stories/t.md" "${ROOT}/pr/docs/stories/u.md" "${ROOT}/app/docs/stories/"   # the same edits, by hand
inrepo review v "${U}/1" >/dev/null
out="$(inrepo reconcile || true)"
check "board edits identical to the base are put back, and the pull goes through" "$(git -C "${ROOT}/app.git" rev-parse main)|gone|" \
  "$(git -C "${ROOT}/app" rev-parse HEAD)|$(gone "${ROOT}/app/docs/stories/v.md")|$(git -C "${ROOT}/app" status --porcelain -- docs/stories/t.md docs/stories/u.md)"
check "reconcile says which edits it put back" "yes" "$(has "docs/stories/u.md was already the base's" "${out}")"
"${GIT[@]}" -C "${ROOT}/pr" pull -q --ff-only && echo "status: ready" >> "${ROOT}/pr/docs/stories/t.md"
"${GIT[@]}" -C "${ROOT}/pr" add docs && "${GIT[@]}" -C "${ROOT}/pr" commit -q -m "edit t" && "${GIT[@]}" -C "${ROOT}/pr" push -q origin main
echo "a local note" >> "${ROOT}/app/docs/stories/t.md"
item "${ROOT}/app/docs" stories/x2.md "status: ready" "kind: code"
inrepo review x2 "${U}/1" >/dev/null
out="$(inrepo reconcile || true)"
check "a differing board edit still stops the pull, and is named" "yes" "$(has "docs/stories/t.md" "$(grep 'cannot pull' <<< "${out}")")"

# --- reconcile never loses an edit. setup_app <name>: a bare origin whose board has stories k and m
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
# A local commit: the pull cannot fast-forward, so nothing is touched and the edit stays.
setup_app nf; "${GIT[@]}" -C "${ROOT}/nf" commit -q --allow-empty -m "local"
out="$(at nf reconcile || true)"
check "no fast-forward: reconcile stops and says why" "yes" "$(has "cannot fast-forward" "${out}")"
check "no fast-forward: the board edit survives, unstaged" " M docs/stories/m.md|same" \
  "$(git -C "${ROOT}/nf" status --porcelain -- docs/stories/m.md)|$(same_as_base nf)"
# A changed tracked file outside the board: stop, name it, touch nothing.
setup_app nb; echo changed >> "${ROOT}/nb/README"
out="$(at nb reconcile || true)"
check "a changed file outside the board stops reconcile, named" "yes" "$(has "files outside the board are changed: README" "${out}")"
check "and the board edit survives" " M docs/stories/m.md" "$(git -C "${ROOT}/nb" status --porcelain -- docs/stories/m.md)"
# A staged edit, even one equal to the base's, is left alone and never claimed.
setup_app st; "${GIT[@]}" -C "${ROOT}/st" add docs/stories/m.md
out="$(at st reconcile || true)"
check "a staged edit is not claimed as put back" "no" "$(if grep -q "m.md was already" <<< "${out}"; then echo yes; else echo no; fi)"
check "a staged edit keeps its content" "same" "$(same_as_base st)"
# The pull fails after the put-back (an untracked file the base adds): every edit comes back.
setup_app pf
echo "theirs" > "${ROOT}/pf-up/notes.txt"
"${GIT[@]}" -C "${ROOT}/pf-up" add notes.txt && "${GIT[@]}" -C "${ROOT}/pf-up" commit -q -m notes && "${GIT[@]}" -C "${ROOT}/pf-up" push -q origin main
echo "mine" > "${ROOT}/pf/notes.txt"
out="$(at pf reconcile || true)"
check "a failed pull is reported" "yes" "$(has "the pull failed, and every board edit is as it was" "${out}")"
check "a failed pull restores the put-back edit from its backup" " M docs/stories/m.md|same" \
  "$(git -C "${ROOT}/pf" status --porcelain -- docs/stories/m.md)|$(same_as_base pf)"
check "the merged item stays in review" "review" "$(sed -n 's/^status: //p' "${ROOT}/pf/docs/stories/k.md")"

# --- reconcile carries the board's own uncommitted front-matter edits over a pull that changes the
# file. setup_flip <name>: a bare origin whose board has k, z, and x and y blocked on t (not on the
# board; x also depends on it); its main checkout <name>, with k in review (its PR merged), z in review (its PR open), and
# x and y flipped to ready by unblock, all uncommitted; and a clone <name>-up for the base's changes.
setup_flip() {
  local d="${ROOT}/$1"
  "${GIT[@]}" init -q --bare "${d}.git"
  "${GIT[@]}" clone -q "${d}.git" "${d}" 2>/dev/null
  item "${d}/docs" stories/k.md "status: ready" "kind: code"
  item "${d}/docs" stories/z.md "status: ready" "kind: code"
  item "${d}/docs" stories/x.md "status: blocked" "kind: code" "blocked_by: [t]" "depends_on: [t]"
  item "${d}/docs" stories/y.md "status: blocked" "kind: code" "blocked_by: [t]"
  "${GIT[@]}" -C "${d}" add docs && "${GIT[@]}" -C "${d}" commit -q -m board && "${GIT[@]}" -C "${d}" push -q origin main
  "${GIT[@]}" clone -q "${d}.git" "${d}-up"
  at "$1" review k "${U}/1" >/dev/null; at "$1" review z "${U}/3" >/dev/null; at "$1" unblock >/dev/null
}
push_up() { "${GIT[@]}" -C "${ROOT}/$1-up" add -A && "${GIT[@]}" -C "${ROOT}/$1-up" commit -q -m "the base's" && "${GIT[@]}" -C "${ROOT}/$1-up" push -q origin main; }
flipped() { sed -e 's/^status: blocked$/status: ready/' -e '/^blocked_by:/d' "$1"; }
same() { if cmp -s "$1" "$2"; then echo same; else echo differs; fi; }
# The base changes x's and z's bodies and deletes y: the pull goes through, and each keeps its edit.
setup_flip fl
echo "the base's line" | tee -a "${ROOT}/fl-up/docs/stories/x.md" >> "${ROOT}/fl-up/docs/stories/z.md"
"${GIT[@]}" -C "${ROOT}/fl-up" rm -q docs/stories/y.md; push_up fl
cp "${ROOT}/fl/docs/stories/y.md" "${ROOT}/fl-y"
out="$(at fl reconcile; echo "exit $?")"
check "a flip on a story the pull changes: reconcile pulls, and exits 0" "yes|$(git -C "${ROOT}/fl.git" rev-parse main)" \
  "$(has "exit 0" "${out}")|$(git -C "${ROOT}/fl" rev-parse HEAD)"
check "x has the base's body, status: ready and no blocked_by" "same" \
  "$(same <(flipped "${ROOT}/fl-up/docs/stories/x.md") "${ROOT}/fl/docs/stories/x.md")"
check "an in-review z keeps its status and prs: under the base's body" "review|${U}/3|the base's line" \
  "$(sed -n 's/^status: //p' "${ROOT}/fl/docs/stories/z.md")|$(sed -n 's/^prs: //p' "${ROOT}/fl/docs/stories/z.md")|$(tail -1 "${ROOT}/fl/docs/stories/z.md")"
check "the base deleted y: it stays deleted, and reconcile names it" "gone|yes" \
  "$(gone "${ROOT}/fl/docs/stories/y.md")|$(has "the pull deleted docs/stories/y.md" "${out}")"
copy="$(sed -n 's/.*the pull deleted docs\/stories\/y\.md.*(its copy is in \(.*\))$/\1/p' <<< "${out}")"
check "and the backup stays, holding y's edit at the path it names" "${ROOT}/fl/.swarm/state/reconcile-backup/|same|yes" \
  "$(grep -o '.*/reconcile-backup/' <<< "${copy}")|$(same "${ROOT}/fl-y" "${copy}")|$(has "the backup stays in ${copy%/docs/stories/y.md}" "${out}")"
check "a kept file names its backup before it is checked out" "yes" \
  "$(has "docs/stories/x.md changes only swarm.sh's front-matter keys; checking it out for the pull, to set them again after it (backup in ${copy%/docs/stories/y.md})" "$(sed -n '1p' <<< "${out}")")"
# A hand edit to x's body, under its flip, still stops the pull, named, and x stays as it was.
setup_flip fh
echo "the base's line" >> "${ROOT}/fh-up/docs/stories/x.md"; push_up fh
echo "a local note" >> "${ROOT}/fh/docs/stories/x.md"; cp "${ROOT}/fh/docs/stories/x.md" "${ROOT}/fh-x"
out="$(at fh reconcile || true)"
check "a hand edit to x stops the pull, named, and x is byte for byte as it was" "yes|same" \
  "$(has "docs/stories/x.md" "$(grep 'cannot pull' <<< "${out}")")|$(same "${ROOT}/fh-x" "${ROOT}/fh/docs/stories/x.md")"
# The base blocks x on another story while x is flipped to ready here: stop, named, x as it was.
setup_flip fc
perl -pi -e 's/^blocked_by: \[t\]$/blocked_by: [w]/' "${ROOT}/fc-up/docs/stories/x.md"; push_up fc
cp "${ROOT}/fc/docs/stories/x.md" "${ROOT}/fc-x"
out="$(at fc reconcile || true)"
check "the base changed x's blocked_by too: reconcile stops naming x, and x is as it was" "yes|same" \
  "$(has "docs/stories/x.md has an uncommitted front-matter edit, and the base changed its blocked_by: too" "$(grep 'cannot pull' <<< "${out}")")|$(same "${ROOT}/fc-x" "${ROOT}/fc/docs/stories/x.md")"
# The base adds w to x's depends_on alone: x's flip to ready is not set again over it.
setup_flip fp
perl -pi -e 's/^depends_on: \[t\]$/depends_on: [t, w]/' "${ROOT}/fp-up/docs/stories/x.md"; push_up fp
cp "${ROOT}/fp/docs/stories/x.md" "${ROOT}/fp-x"
out="$(at fp reconcile || true)"
check "the base changed x's depends_on under its flip: reconcile stops naming x, and x is as it was" "yes|same" \
  "$(has "docs/stories/x.md has an uncommitted front-matter edit, and the base changed its depends_on: too" "$(grep 'cannot pull' <<< "${out}")")|$(same "${ROOT}/fp-x" "${ROOT}/fp/docs/stories/x.md")"
# A diverged main (no fast-forward), and a pull that fails after x was checked out: x keeps its flip.
setup_flip fd
echo "the base's line" >> "${ROOT}/fd-up/docs/stories/x.md"; push_up fd
"${GIT[@]}" -C "${ROOT}/fd" commit -q --allow-empty -m "diverged"; cp "${ROOT}/fd/docs/stories/x.md" "${ROOT}/fd-x"
out="$(at fd reconcile || true)"
check "a diverged main: the pull stops, and x keeps its flip" "yes|same" \
  "$(has "cannot fast-forward" "${out}")|$(same "${ROOT}/fd-x" "${ROOT}/fd/docs/stories/x.md")"
setup_flip ff
echo "the base's line" >> "${ROOT}/ff-up/docs/stories/x.md"; echo "theirs" > "${ROOT}/ff-up/notes.txt"; push_up ff
echo "mine" > "${ROOT}/ff/notes.txt"; cp "${ROOT}/ff/docs/stories/x.md" "${ROOT}/ff-x"
out="$(at ff reconcile || true)"
check "a pull that fails after x was checked out restores x's flip from the backup" "yes|same" \
  "$(has "the pull failed, and every board edit is as it was" "${out}")|$(same "${ROOT}/ff-x" "${ROOT}/ff/docs/stories/x.md")"
# A merge lands on the base while reconcile runs (git, wrapped, pushes x: done before the
# fast-forward): reconcile moves to the base it checked, so its keys never cover the newer status.
setup_flip fr
echo "the base's line" >> "${ROOT}/fr-up/docs/stories/x.md"; push_up fr
checked="$(git -C "${ROOT}/fr.git" rev-parse main)"
mkdir -p "${ROOT}/late-bin"
cat > "${ROOT}/late-bin/git" <<EOF
#!/bin/sh
case " \$* " in *" pull "*|*" merge "*) [ -e "${ROOT}/late-done" ] || { : > "${ROOT}/late-done"
  perl -pi -e 's/^status: blocked\$/status: done/' "${ROOT}/fr-up/docs/stories/x.md"
  "$(command -v git)" -c user.name=t -c user.email=t@t -C "${ROOT}/fr-up" commit -q -am late
  "$(command -v git)" -C "${ROOT}/fr-up" push -q origin main; } ;; esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "${ROOT}/late-bin/git"
PATH="${ROOT}/late-bin:${PATH}" at fr reconcile >/dev/null || true
check "a merge that lands during reconcile is not pulled under its keys" "${checked}|ready|done" \
  "$(git -C "${ROOT}/fr" rev-parse HEAD)|$(sed -n 's/^status: //p' "${ROOT}/fr/docs/stories/x.md")|$(git -C "${ROOT}/fr.git" show main:docs/stories/x.md | sed -n 's/^status: //p')"

# --- The merge guard: every Claude agent starts unable to run gh pr merge, but a conductor with merge = agent.
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
check "merge = agent keeps the guard on a story agent, and starts only the conductor without it" "yes|no" \
  "$(has "${GUARD}" "$(start g2)")|$(grep -qF -- "${GUARD}" <<< "$(conductor e)" && echo yes || echo no)"
check "a builder's brief says who merges: a human, or with merge = agent the conductor or the lead" "yes|yes" \
  "$(has "Never merge, by any route (a human merges)." "$(cat "${p}/.swarm/briefs/g1.md")")|$(has "Never merge, by any route (the conductor or the lead merges, with swarm.sh merge)." "$(cat "${p}/.swarm/briefs/g2.md")")"
rm -f "${p}/.swarm/state/e" "${b}/epics/e.md"   # the conductor's tab record, which tidy below would list

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

# --- watch --epic: a conductor wakes only for its own epic's PRs. Two epics share a repo; the other
# epic's PR comes first and has finished its checks too.
w="${ROOT}/watch"
mkdir -p "${w}/.claude/swarm" "${ROOT}/wrepos"
echo "repos_dir = ${ROOT}/wrepos" > "${w}/.claude/swarm/config"
git init -q "${ROOT}/wrepos/svc" && git -C "${ROOT}/wrepos/svc" remote add origin https://github.com/o/svc
item "${w}/docs" epics/mine.md "status: active"
item "${w}/docs" epics/other.md "status: active"
item "${w}/docs" stories/a.md "status: ready" "kind: code" "epic: mine" "repo: svc"
item "${w}/docs" stories/b.md "status: ready" "kind: code" "epic: other" "repo: svc"
cat > "${ROOT}/gh/prlist.json" <<'EOF'
[{"number": 1, "headRefName": "story/b", "headRefOid": "head1", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"},
 {"number": 2, "headRefName": "epic/mine", "headRefOid": "head2", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]
EOF
check "watch --epic skips another epic's PR in the same repo" "o/svc #2 epic/mine checks finished on head2" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic mine 2>&1)"
# One PR per epic: the stories are finished (deleted) before the epic PR opens, so only the epic's
# repos: line still names the repo.
rm "${w}/docs/stories/a.md" "${w}/.swarm/state/watch-seen"
printf -- '---\nstatus: active\nrepos: svc\n---\n\n# mine\n' > "${w}/docs/epics/mine.md"
check "watch --epic finds the repo from the epic's repos: line once its stories are gone" "o/svc #2 epic/mine checks finished on head2" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic mine 2>&1)"

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
