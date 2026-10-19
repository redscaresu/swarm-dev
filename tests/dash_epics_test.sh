#!/usr/bin/env bash
# dash_epics_test.sh — an epic's progress from history, codex review rows under their epic, and
# running now.
# `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and events.tsv, a stub
# herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are stubbed to fail, so the
# width comes from COLUMNS (or the default 100), except in the pty tests.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
P="${ROOT}/proj"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json"

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }
lacks() { ! grep -qF -- "$1" <<< "$2"; }

item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

mkdir -p "${ROOT}/nobin" "${ROOT}/size" "${ROOT}/projects/p"
unset COLUMNS LINES
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/stty"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/tput"
chmod +x "${ROOT}/size/stty" "${ROOT}/size/tput"
# SWARM_NO_CI_REFRESH: project D has a github.com origin, and no ci line refresh may outlive the test.
export PATH="${ROOT}/size:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" SWARM_NO_CI_REFRESH=1
mkdir -p "${TMPDIR}"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks again.
fresh() { rm -f "${TMPDIR}"/swarm-dash-*; }
# Claude Code's sessions: the conductor (sess-1) and s-three's builder (sess-today) are busy, and
# s-one's builder waits on a permission prompt.
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"input"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude.json"

ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }

# herdr and gh that always fail: no project here has a herdr, and gh is never reached.
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/herdr"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/gh"
chmod +x "${ROOT}/nobin/herdr" "${ROOT}/nobin/gh"
lbox() { # <title> <frame> — that box of the left column, the right column cut off
  python3 -c '
import sys
t, out = sys.argv[1], []
for l in sys.stdin.read().splitlines():
    if l.startswith("╭─ " + t + " ") or out:
        out.append(l.split("╮ ")[0].split("╯ ")[0].split("│ │")[0])
        if l.startswith("╰"):
            break
print("\n".join(out))' "$1" <<< "$2"
}

# --- An epic's progress from history, in a project of its own (Q), with no herdr. Each story file
# below names epic x, and is deleted in a different way; only a deletion that closed its story counts.
Q="${ROOT}/q"
qitem() { P="${Q}" item "$@"; }
GQ=(git -C "${Q}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
mkdir -p "${Q}/.swarm/state" "${Q}/src"
git -C "${Q}" init -q -b main
echo .swarm/ > "${Q}/.gitignore"; echo "status" > "${Q}/STATUS.md"
qitem epics/x.md 'status: active'
qitem epics/y.md 'status: active'
qitem stories/y-wait.md 'status: blocked' 'epic: y' 'depends_on: [x-b]'
qitem stories/y-then.md 'status: later' 'epic: y'
for s in x-merged x-big x-fin x-again x-gone x-scope x-scope2 x-twice x-squash x-ops; do qitem "stories/${s}.md" 'status: ready' 'epic: x'; done
qitem stories/x-own.md 'status: ready' 'epic: x' 'prs: https://github.com/o/r/pull/5'
qitem stories/x-rev.md 'status: review' 'epic: x' 'prs: https://github.com/o/r/pull/1'
# epic: x in the body, not the front matter: never x's, open or finished.
qitem stories/x-body.md 'status: ready' 'kind: code'
qitem stories/y-loose.md 'status: ready' 'kind: code'
echo "epic: x" >> "${Q}/docs/stories/x-body.md"; echo "epic: x" >> "${Q}/docs/stories/y-loose.md"
# A front matter only counts on the first line: this file's later --- block is body.
printf '# late\n\n---\nepic: x\n---\n' > "${Q}/docs/stories/y-late.md"
# CRLF line endings: still x's, and ready.
printf -- '---\r\nstatus: ready\r\nepic: x\r\n---\r\n\r\n# crlf\r\n' > "${Q}/docs/stories/x-crlf.md"
touch "${Q}/docs/stories/README.md"
"${GQ[@]}" add -A && "${GQ[@]}" commit -qm board
# A story that listed its PR, deleted with its code (a squash merge looks like this). Counts.
echo 1 > "${Q}/src/a"; "${GQ[@]}" rm -q docs/stories/x-own.md docs/stories/x-body.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "ship x-own"
# Its own PR merge, the board file deleted on story/x-merged. Counts. "@@" in the subject must not
# split the commit: commits are split on NUL.
"${GQ[@]}" checkout -qb story/x-merged && "${GQ[@]}" rm -q docs/stories/x-merged.md && "${GQ[@]}" commit -qm "close x-merged"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #2 from o/story/x-merged @@ x" story/x-merged
# A story PR squash-merged: its code and its board deletion in one commit, status still ready, no
# prs. Its own work, so it counts.
echo 4 > "${Q}/src/b"; "${GQ[@]}" rm -q docs/stories/x-squash.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Ship x-squash (#8)"
# A story whose only work beside its board file sits under the board's directory (a runbook in
# docs/operations.md): its own work, so it counts.
echo "runbook" > "${Q}/docs/operations.md"; "${GQ[@]}" rm -q docs/stories/x-ops.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Write the operations runbook (#9)"
# Re-scopes never count. A board/ PR, even one that changes code too:
echo 5 > "${Q}/src/b"; "${GQ[@]}" rm -q docs/stories/x-scope.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Merge pull request #3 from o/board/lead-not-operator"
# and a commit whose only change off the board is a root note (infrafactory #409 edited STATUS.md).
echo "re-scoped" >> "${Q}/STATUS.md"; "${GQ[@]}" rm -q docs/stories/x-scope2.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "tidy the board"
# Board-only: a story in review taken off (reconcile's finish) counts; one the swarm logged as
# finished counts; a split (x-big into x-b and x-c in one board commit) does not.
"${GQ[@]}" rm -q docs/stories/x-rev.md docs/stories/x-fin.md && "${GQ[@]}" commit -qm "board: finished"
printf '2026-10-01T10:00:00Z\tfinish\tx-fin\tw1:p1\tok\n' > "${Q}/.swarm/events.tsv"
"${GQ[@]}" rm -q docs/stories/x-big.md; qitem stories/x-b.md 'status: ready' 'epic: x'; qitem stories/x-c.md 'status: ready' 'epic: x'
"${GQ[@]}" add -A && "${GQ[@]}" commit -qm "split x-big"
# Closed by its own PR, added again, then re-scoped away: closed once, so it counts once.
"${GQ[@]}" checkout -qb story/x-twice && "${GQ[@]}" rm -q docs/stories/x-twice.md && "${GQ[@]}" commit -qm "close x-twice"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #4 from o/story/x-twice" story/x-twice
qitem stories/x-twice.md 'status: ready' 'epic: x'; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "x-twice again"
"${GQ[@]}" rm -q docs/stories/x-twice.md && "${GQ[@]}" commit -qm "drop x-twice"
# Deleted by its own PR, then added again: open, not also finished.
"${GQ[@]}" checkout -qb story/x-again && "${GQ[@]}" rm -q docs/stories/x-again.md && "${GQ[@]}" commit -qm "close x-again"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #6 from o/story/x-again" story/x-again
qitem stories/x-again.md 'status: ready' 'epic: x'; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "x-again again"
# Closed on origin/main, which this checkout has not pulled: open here, not also finished.
"${GQ[@]}" checkout -qb story/x-gone && "${GQ[@]}" rm -q docs/stories/x-gone.md && "${GQ[@]}" commit -qm "close x-gone"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #7 from o/story/x-gone" story/x-gone
git -C "${Q}" update-ref refs/remotes/origin/main HEAD
git -C "${Q}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "${Q}" reset -q --hard HEAD~1
# Findings dated yesterday and three days ago, and timed events late two days ago and early
# yesterday, all read in calendar days.
day() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }
at() { python3 -c 'import datetime, sys; d = datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])); print(datetime.datetime.combine(d, datetime.time.fromisoformat(sys.argv[2])).astimezone().isoformat())' "$1" "$2"; }
printf '%s\tk1\thttps://github.com/o/r/pull/3\tone from yesterday\n%s\tk2\thttps://github.com/o/r/pull/4\tone from three days ago\n' "$(day 1)" "$(day 3)" > "${Q}/.swarm/findings.tsv"
printf '%s\ttell:findings\tlate-two-days-ago\tw1:p1\tok\n%s\ttell:nudge\tearly-yesterday\tw1:p1\tok\n' "$(at 2 23:59:00)" "$(at 1 00:01:00)" >> "${Q}/.swarm/events.tsv"
qdash() { fresh; (cd "${Q}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" "$@" bash "${SWARM}" dash 2>&1 || true); }
out="$(qdash env)"
# Finished: x-own, x-merged, x-squash, x-ops, x-rev, x-fin, x-twice. Open: x-b, x-c, x-again, x-gone, x-crlf.
XROW='^│ ○ x +█{7}░{5}  7/12  5 ready +│$'
check "progress counts only deletions that closed a story, once each" grep -qE "${XROW}" <<< "${out}"
check "an epic with ready stories and nothing running is ○ ready" grep -qE '^│ ○ x ' <<< "${out}"
check "an epic whose remaining stories are all blocked or later is ⏸" grep -qE '^│ ⏸ y +░{12}  0/2   1 blocked · 1 later +│$' <<< "${out}"
check "the legend names ○ ready" has "○ ready" "$(tail -2 <<< "${out}")"
check "a date-only entry from yesterday reads yesterday" grep -qE '^│ yesterday  ✎ one from yesterday' <<< "${out}"
check "a date-only entry three days old reads 3d ago" grep -qE '^│ +3d ago  ✎ one from three days ago' <<< "${out}"
check "a timed event late two days ago reads 2d ago" grep -qE '^│ +2d ago  · tell:findings late-two-days-ago' <<< "${out}"
check "a timed event over a day ago, early yesterday, reads yesterday" grep -qE '^│ yesterday  · tell:nudge early-yesterday|^│ +[0-9]+h ago  · tell:nudge early-yesterday' <<< "${out}"
out="$(qdash env GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=diff.noprefix GIT_CONFIG_VALUE_0=true GIT_CONFIG_KEY_1=color.ui GIT_CONFIG_VALUE_1=always GIT_CONFIG_KEY_2=diff.mnemonicPrefix GIT_CONFIG_VALUE_2=true)"
check "progress holds under diff.noprefix and color.ui=always" grep -qE "${XROW}" <<< "${out}"
# The board in a repo of its own (board_dir), with no origin, while the project has origin/main: the
# base ref is resolved in the board's repo, which falls back to its HEAD (x-gone stays open). The
# project's events.tsv has no finish of x-fin, so x-fin does not count here.
R="${ROOT}/r"; B="${ROOT}/rboard"
mkdir -p "${R}/.claude/swarm" "${R}/.swarm"
git -C "${R}" init -q -b main && git -C "${R}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "${R}" update-ref refs/remotes/origin/main HEAD && git -C "${R}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
echo "board_dir = ../rboard/docs" > "${R}/.claude/swarm/config"
cp -R "${Q}/." "${B}" && rm -rf "${B}/.swarm" && git -C "${B}" update-ref -d refs/remotes/origin/main && git -C "${B}" symbolic-ref --delete refs/remotes/origin/HEAD
out="$(fresh; cd "${R}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a board in its own repo counts from that repo's history" grep -qE '^│ ○ x +█{7}░{5}  6/11  5 ready +│$' <<< "${out}"

# --- A running codex review (codex-review's marker, .swarm/state/codex-review.<pid>: start epoch, base,
# cwd) is a row under its worktree's epic, with its age, in neither needs you nor the lead's queue. A
# marker whose pid is dead, or older than codex_minutes (10) plus 1, shows nothing, and dash leaves both.
C="${ROOT}/codex"; S="${C}/.swarm/state"; mkdir -p "${S}" "${C}/.claude/swarm" "${C}/docs/epics" "${C}/docs/stories"; git -C "${C}" init -q
touch "${C}/docs/stories/README.md"; echo "lead = session" > "${C}/.claude/swarm/config"
citem() { local path="${C}/docs/$1" body="$2" title; title="$(basename "$1" .md)"; shift 2; { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; echo; echo "${body}"; } > "${path}"; }
citem epics/alpha.md '' 'status: active'; citem epics/beta.md '' 'status: active'
citem stories/cs-one.md '' 'status: ready' 'epic: alpha'
citem stories/c-you.md '**You:** create the user' 'status: ready' 'kind: lead'
citem stories/c-lead.md 'The lead runs it.' 'status: ready' 'kind: lead'
# The live pids are this test's own sleeps, off its stdout so no pipe waits on them, killed on exit.
sleep 300 >/dev/null 2>&1 & live1=$!; sleep 300 >/dev/null 2>&1 & live2=$!; sleep 300 >/dev/null 2>&1 & live3=$!
sleep 300 >/dev/null 2>&1 & live4=$!
trap 'kill "${live1}" "${live2}" "${live3}" "${live4}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
sh -c 'exit 0' & dead=$!; wait "${dead}" || true
marker() { printf '%s\t%s\t%s\n' "$(( $(date +%s) - $2 * 60 ))" "${4:-main}" "${ROOT}/repo-wt/$3" > "${S}/codex-review.$1"; }   # <pid> <minutes ago> <worktree> [base]
marker "${live1}" 7 cs-one; marker "${live2}" 3 epic-beta; marker "${dead}" 2 dead-one; marker "${live3}" 12 old-one
# A long slug on an epic base: the name column is cut, never the base or the age.
citem stories/a-rather-long-story-slug.md '' 'status: ready' 'epic: alpha'
marker "${live4}" 4 a-rather-long-story-slug epic/alpha
before="$(cksum "${S}"/codex-review.*)"
for cols in 100 160; do
  out="$(fresh; cd "${C}" || exit 1; env -u HERDR_ENV -u SWARM_PROJECT COLUMNS="${cols}" PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
  # under <row text> — the epic header (a progress bar's line) above that row.
  under() { awk -v r="$1" '/[█░]/ { e = $0 } index($0, r) { print e; exit }' <<< "${out}" | grep -oE '(alpha|beta) '; }
  check "codex row at ${cols} columns: a story worktree's review shows with its 7m age and base" grep -qE 'codex review cs-one .*running 7m vs main' <<< "${out}"
  check "codex row at ${cols} columns: a story worktree's review sits under its story's epic" test "$(under 'codex review cs-one')" = "alpha "
  check "codex row at ${cols} columns: an epic worktree's review sits under that epic" test "$(under 'codex review epic-beta')" = "beta "
  check "codex row at ${cols} columns: a dead pid's marker shows no row" lacks "codex review dead-one" "${out}"
  check "codex row at ${cols} columns: a marker past codex_minutes plus 1 shows no row" lacks "codex review old-one" "${out}"
  check "codex row at ${cols} columns: not in needs you" lacks "codex review" "$(lbox "needs you" "${out}")"
  check "codex row at ${cols} columns: not in the lead's queue" lacks "codex review" "$(lbox "lead's queue" "${out}")"
done
check "codex row at 160 columns: a long slug's row keeps its base and age" grep -qE 'codex review a-rather.*running 4m vs epic/alpha' <<< "${out}"
check "dash leaves every codex-review marker, dead or overdue, as it was" test "$(cksum "${S}"/codex-review.*)" = "${before}"

# --- Running now, in a project of its own (D) whose panes are w5's: two epic builders at work, three
# idle one-off builders (their stories on no epic) and one held story.
D="${ROOT}/running"; mkdir -p "${D}/.swarm/state" "${D}/docs/epics" "${D}/docs/stories" "${ROOT}/dbin"; git -C "${D}" init -q
# An upstream remote beside origin: gh is asked about origin by name, never left to pick.
git -C "${D}" remote add upstream https://github.com/up/d.git && git -C "${D}" remote add origin https://github.com/o/d.git
touch "${D}/docs/stories/README.md"
ditem() { local path="${D}/docs/$1" title; title="$(basename "$1" .md)"; shift; { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"; }
# The epic's file lists PR 20 too, so dash_slow views it once, and story/ro-retry still maps to it.
ditem epics/re.md 'status: active' 'prs: https://github.com/o/d/pull/20'
ditem stories/rb-one.md 'status: ready' 'epic: re' 'prs: https://github.com/o/d/pull/11'
ditem stories/rb-two.md 'status: ready' 'epic: re' 'prs: https://github.com/o/d/pull/12'
# ro-review's PR is open on story/ro-review, which its file lists only from review on: gh pr list finds it.
ditem stories/ro-review.md 'status: ready'
ditem stories/ro-merge.md 'status: review' 'prs: https://github.com/o/d/pull/14'
ditem stories/ro-imp.md 'status: ready'
# A retry: the story still lists the earlier attempt's closed PR 16; the retry's PR 20 is open on story/ro-retry.
ditem stories/ro-retry.md 'status: ready' 'prs: https://github.com/o/d/pull/16'
ditem stories/rh-held.md 'status: ready' 'kind: lead' 'escalated_from: code' 'held_for: paused'
printf 'w5:p1 rb-one\nw5:p2 rb-two\nw5:p3 ro-review\nw5:p4 ro-merge\nw5:p5 ro-imp\nw5:p6 ro-retry\n' > "${D}/.swarm/state/d"
printf '%s\tcode\t%s\tclaude\topus\thigh\t%s\n' "$(date +%F)" rb-one drb1 "$(date +%F)" rb-two drb2 \
  "$(date +%F)" ro-review dro1 "$(date +%F)" ro-merge dro2 "$(date +%F)" ro-imp dro3 "$(date +%F)" ro-retry dro4 > "${D}/.swarm/agents.tsv"
printf '%s\tstory\trb-one\tw5:p1\tok\n' "$(ago 25)" > "${D}/.swarm/events.tsv"
dlog() { # <session> <minutes ago> <content block>
  printf '{"type":"assistant","timestamp":"%s","message":{"content":[%s]}}\n' "$(ago "$2")" "$3" >> "${ROOT}/projects/p/$1.jsonl"
}
dlog drb1 3 '{"type":"tool_use","name":"Bash","input":{}}'
dlog drb2 12 '{"type":"text","text":"reading"},{"type":"tool_use","name":"Read","input":{}}'
# rb-two's newest tool is a Write of 80 KB, longer than the 64 KB dash reads first, then its short result.
dlog drb2 10 "{\"type\":\"tool_use\",\"name\":\"Write\",\"input\":{\"content\":\"$(head -c 81920 /dev/zero | tr '\0' x)\"}}"
printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","content":"ok"}]}}\n' "$(ago 9)" >> "${ROOT}/projects/p/drb2.jsonl"
dlog dro4 30 '{"type":"text","text":"Opened the retry PR."}'
dlog dro1 30 '{"type":"text","text":"Opened the PR."}'
# A newest line whose message is not an object costs nothing: ro-review's row still reads.
echo '{"type":"assistant","timestamp":"2026-10-01T00:00:00Z","message":"odd"}' >> "${ROOT}/projects/p/dro1.jsonl"
dlog dro2 30 '{"type":"text","text":"Done; the PR is in review."}'
dlog dro3 40 '{"type":"text","text":"The plan first."}'
dlog dro3 20 '{"type":"text","text":"IMPOSSIBLE: the API has no such call"}'
# Then 80 KB of hook output and a small tool call: the reply is past the 64 KB read first, so dash
# reads further back for an idle one-off builder, the one row that needs it.
printf '{"type":"attachment","timestamp":"%s","content":"%s"}\n' "$(ago 19)" "$(head -c 81920 /dev/zero | tr '\0' x)" >> "${ROOT}/projects/p/dro3.jsonl"
dlog dro3 18 '{"type":"tool_use","name":"Bash","input":{}}'
printf '[{"sessionId":"drb1","status":"busy"},{"sessionId":"drb2","status":"busy"},{"sessionId":"dro1","status":"idle"},{"sessionId":"dro2","status":"idle"},{"sessionId":"dro3","status":"idle"},{"sessionId":"dro4","status":"idle"}]' > "${ROOT}/d.json"
cat > "${ROOT}/dbin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"rb-one","agent_status":"working","pane_id":"w5:p1"},{"name":"rb-two","agent_status":"working","pane_id":"w5:p2"},{"name":"ro-review","agent_status":"idle","pane_id":"w5:p3"},{"name":"ro-merge","agent_status":"idle","pane_id":"w5:p4"},{"name":"ro-imp","agent_status":"idle","pane_id":"w5:p5"},{"name":"ro-retry","agent_status":"idle","pane_id":"w5:p6"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w5:p1"},{"pane_id":"w5:p2"},{"pane_id":"w5:p3"},{"pane_id":"w5:p4"},{"pane_id":"w5:p5"},{"pane_id":"w5:p6"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w5","label":"running"}]}}' ;;
  *) exit 1 ;;
esac
STUB
# gh: PR 11 is green, PR 12 failing, PR 14 green, and origin's open PR list (url and head only) has
# PR 13 on story/ro-review, whose CI is running, and PR 20 on story/ro-retry, green; PR 16 is closed.
cat > "${ROOT}/dbin/gh" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
  "pr view https://github.com/o/d/pull/11"|"pr view https://github.com/o/d/pull/14") echo '{"state":"OPEN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/d/pull/12") echo '{"state":"OPEN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}' ;;
  "pr list -R") [ "$4" = https://github.com/o/d.git ] || exit 1
    echo '[{"url":"https://github.com/o/d/pull/13","headRefName":"story/ro-review"},{"url":"https://github.com/o/d/pull/15","headRefName":"other"},{"url":"https://github.com/o/d/pull/20","headRefName":"story/ro-retry"}]' ;;
  "pr view https://github.com/o/d/pull/16") echo '{"state":"CLOSED","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}' ;;
  "pr view https://github.com/o/d/pull/20") echo '{"state":"OPEN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/d/pull/13") echo '{"state":"OPEN","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":""}]}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${ROOT}/dbin/herdr" "${ROOT}/dbin/gh"
for cols in 100 160; do
  out="$(fresh; cd "${D}" || exit 1; env -u HERDR_ENV COLUMNS="${cols}" CLAUDE_STUB_AGENTS="${ROOT}/d.json" PATH="${ROOT}/dbin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
  run="$(lbox "running now" "${out}")"; epicp="$(lbox "epics" "${out}")"
  check "running now at ${cols} columns: a builder's row has its running time, last tool and PR's CI state" grep -qE '● rb-one +up 25m +Bash 3m ago +#11 green' <<< "${run}"
  check "running now at ${cols} columns: the other builder's row too, its time from agents.tsv, its last entry past 64 KB" grep -qE '● rb-two +up [0-9hm]+ +Write 9m ago +#12 failing' <<< "${run}"
  check "running now at ${cols} columns: a held story with its cause" has "⏸ held rh-held: paused" "${run}"
  # Narrower than 140 columns it sits just above recent; from 140, in the left column just under the epics.
  check "running now at ${cols} columns: sits where its layout puts it" python3 -c '
import sys
t, wide = sys.stdin.read().splitlines(), sys.argv[1] == "160"
r = next(i for i, l in enumerate(t) if l.startswith("╭─ running now"))
end = next(i for i in range(r, len(t)) if t[i].startswith("╰"))
sys.exit(not (t[r - 1].startswith("╰") and "╭─ epics" in "".join(t[:r]) if wide else t[end + 1].startswith("╭─ recent")))' "${cols}" <<< "${out}"
  check "one-off builder at ${cols} columns: an open PR not in review waits for review" grep -qE 'ro-review .*#13 waits for review' <<< "${epicp}"
  check "running now at ${cols} columns: a PR found on the builder's branch shows its CI state" grep -qE 'ro-review .*#13 CI running' <<< "${run}"
  check "one-off builder at ${cols} columns: a story in review waits for the lead's merge" grep -qE "ro-merge .*#14 waits for the lead's merge" <<< "${epicp}"
  check "one-off builder at ${cols} columns: a last reply of IMPOSSIBLE: reads IMPOSSIBLE" grep -qE 'ro-imp .*IMPOSSIBLE' <<< "${epicp}"
  check "running now at ${cols} columns: a builder with no PR says so" grep -qE '! ro-imp .*no PR yet|✓ ro-imp .*no PR yet' <<< "${run}"
  check "one-off builder at ${cols} columns: a retry's open PR stands in for the closed one its story lists" grep -qE 'ro-retry .*#20 waits for review' <<< "${epicp}"
  check "running now at ${cols} columns: a retry shows its open PR, not the closed one" grep -qE 'ro-retry .*#20 green' <<< "${run}"
  check "running now at ${cols} columns: a closed PR is not shown" lacks "#16" "${run}"
  check "no agent row at ${cols} columns reads a bare idle" lacks " idle " "${out}"
  out="$(fresh; cd "${D}" || exit 1; env -u HERDR_ENV COLUMNS="${cols}" CLAUDE_STUB_AGENTS="${ROOT}/d.json" PATH="${ROOT}/dbin:${PATH}" bash "${SWARM}" dash --tree 2>&1 || true)"
  check "--tree at ${cols} columns: an idle one-off builder says what it waits on" grep -qE 'ro-review .*#13 waits for review' <<< "${out}"
  check "--tree at ${cols} columns: no agent row reads a bare idle" lacks " idle " "${out}"
done


[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
