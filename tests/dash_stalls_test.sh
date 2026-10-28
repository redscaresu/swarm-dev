#!/usr/bin/env bash
# dash_stalls_test.sh — stalls and state ages in the agents' rows and in needs you.
# `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and events.tsv, a stub
# herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are stubbed to fail, so the
# width comes from COLUMNS (or the default 100), except in the pty tests.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
# One fixed instant, 2026-07-16 00:30 BST (2026-07-15T23:30:00Z): past midnight in London and not yet
# in UTC, where a local clock and a UTC one disagree on the day. dash takes it as SWARM_DASH_NOW. Every
# relative time below (ago, mins_ago, TODAY) is derived from it, never from the real clock, so the run
# lasts as long as it likes; the dated fixtures are fixed June and July dates, all before it. TZ is
# London unless the caller set one.
export SWARM_DASH_NOW=1784158200 TZ="${TZ:-Europe/London}"
# ago <minutes> — that long before the fixed now, as events.tsv writes it (UTC); mins_ago <minutes> —
# the same, as touch -t takes it (local); TODAY — the fixed now's local day, dash's today.
ago() { python3 -c 'import datetime, os, sys; print(datetime.datetime.fromtimestamp(float(os.environ["SWARM_DASH_NOW"]) - 60 * int(sys.argv[1]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
mins_ago() { python3 -c 'import os, sys, time; print(time.strftime("%Y%m%d%H%M", time.localtime(float(os.environ["SWARM_DASH_NOW"]) - 60 * int(sys.argv[1]))))' "$1"; }
TODAY="$(python3 -c 'import datetime, os; print(datetime.date.fromtimestamp(float(os.environ["SWARM_DASH_NOW"])))')"

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

mkdir -p "${P}/.swarm/state" "${ROOT}/bin" "${ROOT}/nobin" "${ROOT}/size" "${ROOT}/projects/p"
unset COLUMNS LINES
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/stty"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/tput"
chmod +x "${ROOT}/size/stty" "${ROOT}/size/tput"
export PATH="${ROOT}/size:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
mkdir -p "${TMPDIR}"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks again.
fresh() { rm -rf "${TMPDIR}"/swarm-dash-*; }
git -C "${P}" init -q
item hld/2026-01-01-x.md 'status: agreed'
item epics/e1.md 'status: active' 'hld: 2026-01-01-x'
item epics/e2.md 'status: later'
item stories/s-one.md 'status: review' 'epic: e1' 'prs: https://github.com/o/r/pull/7'
item stories/s-two.md 'status: blocked' 'epic: e1' 'depends_on: [s-one]'
item stories/s-three.md 'status: ready' 'epic: e1'
item stories/ask.md 'status: ready' 'kind: lead'
sed -i.bak 's/^# ask$/# Create the read-only IAM user/' "${P}/docs/stories/ask.md" && rm "${P}/docs/stories/ask.md.bak"
# A finished story of e1, deleted from the board after it merged: e1's progress counts it from git.
item stories/s-old.md 'status: review' 'epic: e1'
# Two slugs whose agent names are the same 32 characters: the done one must never be the builder's.
# Its PR is never asked about either: dash skips done items.
item stories/aaaaaaaaaa-bbbbbbbbbb-cccccccccc-1.md 'status: done' 'prs: https://github.com/o/r/pull/9'
item stories/aaaaaaaaaa-bbbbbbbbbb-cccccccccc-2.md 'status: ready' 'kind: code'
printf 'w1:p1 conductor\nw1:p2 s-one\nw1:p3 s-gone\nw1:p4 old\nw1:p5 odd\nw1:p11 s-two\n' > "${P}/.swarm/state/e1"
# e2's conductor wrote its report and went idle: [reported], not [idle].
printf 'w1:p8 conduct-e2\n' > "${P}/.swarm/state/e2"
# s-three's builder is working; with no sign of life on record it is never stalled (the stall block below).
printf 'w1:p9 s-three\nw1:p10 aaaaaaaaaa-bbbbbbbbbb-cccccccccc\n' > "${P}/.swarm/state/s-three"
echo "# report" > "${P}/.swarm/conduct-e2.report.md"
# A codex brief in state/ is prose, not a tab record (own_panes' rule): its pane must not show.
printf 'w1:p6 is where the brief says to look\n' > "${P}/.swarm/state/brief-x.md"
# A half-written tab record (*.tmp) is skipped, as status and tidy skip it.
printf 'w1:p7 halfway\n' > "${P}/.swarm/state/e1.tmp"
printf '2026-07-01\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-1\n2026-07-02\tcode\ts-one\tclaude\topus\thigh\tsess-2\n' > "${P}/.swarm/agents.tsv"
# Today's cost, the same as `swarm.sh cost <today>`: 1M input at $4 + 1M output at $20.
printf '%s\tcode\ts-three\tclaude\topus\thigh\tsess-today\n' "${TODAY}" >> "${P}/.swarm/agents.tsv"
echo '{"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":1000000}}}' > "${ROOT}/projects/p/sess-today.jsonl"
# One escalate agent whose session ran on opus (its first message with a model), not the fable its
# policy names; the ladder shows the session's model. No docs agent: docs shows 0.
printf '2026-07-02\tescalate\tx-esc\tclaude\tfable\txhigh\tsess-esc\n' >> "${P}/.swarm/agents.tsv"
# Ahead of opus: a non-string model and a failed turn's "<synthetic>" one, both skipped.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}' '{"message":{"model":5}}' \
  '{"message":{"id":"e0","model":"<synthetic>"}}' '{"message":{"id":"e1","model":"claude-opus-5-5"}}' \
  '{"message":{"id":"e2","model":"claude-fable-5-1"}}' > "${ROOT}/projects/p/sess-esc.jsonl"
# A chore agent whose log cannot be read: it counts, with no model, and the ladder still draws.
printf '2026-07-02\tchore\tx-chore\tclaude\thaiku\tmedium\tsess-locked\n' >> "${P}/.swarm/agents.tsv"
echo '{}' > "${ROOT}/projects/p/sess-locked.jsonl"; chmod 000 "${ROOT}/projects/p/sess-locked.jsonl"
# A session log's mtime is a sign of life (the stall rule): x-esc's was written days before the fixed now.
touch -t 202607101100 "${ROOT}/projects/p/sess-esc.jsonl"
printf '2026-07-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
# Five findings on another PR the same day: one recent row, not five.
for i in 1 2 3 4 5; do printf '2026-07-04\tkind%s\thttps://github.com/o/r/pull/8\tfinding %s\n' "${i}" "${i}" >> "${P}/.swarm/findings.tsv"; done
printf '2026-07-03T10:00:00Z\tfinish\ts-zero\tw1:p1\tok\n2026-07-04T10:00:00Z\treview\ts-one\tw1:p1\tok\n' > "${P}/.swarm/events.tsv"
# Older actions, so that from 140 columns the recent log is taller than the needs-you box beside it.
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '2026-06-%02dT10:00:00Z\ttell\told-%s\tw1:p1\tok\n' "${i}" "${i}" >> "${P}/.swarm/events.tsv"; done

# Claude Code's sessions: the conductor (sess-1) and s-three's builder (sess-today) are busy, and
# s-one's builder waits on a permission prompt. The wait checks below rewrite this file.
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"input"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude.json"
# herdr: this project's conductor (working) and builder (blocked), an empty pane (w1:p3), and
# another project's agent (w9:p1), which must not be shown. s-three's herdr status is done while its
# session is busy: the session's word is the one dash shows.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sess-1"}},{"name":"conduct-e2","agent_status":"idle","pane_id":"w1:p8"},{"name":"s-one","agent_status":"blocked","pane_id":"w1:p2"},{"name":"foreign","agent_status":"working","pane_id":"w9:p1"},{"name":"old-done","agent_status":"idle","pane_id":"w1:p4"},{"name":"odd","agent_status":"idle","pane_id":"w1:p5","agent_session":"not-an-object"},{"name":"prose","agent_status":"working","pane_id":"w1:p6"},{"name":"halfway","agent_status":"working","pane_id":"w1:p7"},{"name":"s-three","agent_status":"done","pane_id":"w1:p9"},{"name":"aaaaaaaaaa-bbbbbbbbbb-cccccccccc","agent_status":"working","pane_id":"w1:p10"},{"name":"s-two","agent_status":"starting","pane_id":"w1:p11"},{"name":"s-re-done","agent_status":"idle","pane_id":"w2:p1"},{"name":"s-re","agent_status":"'"${RE_HERDR:-working}"'","pane_id":"w2:p2"},{"name":"s-lost","agent_status":"idle","pane_id":"w2:p3"},{"name":"s-odd","agent_status":"working","pane_id":"w2:p4"},{"name":"cx","agent_status":"blocked","pane_id":"w2:p5"},{"name":"s-dash","agent_status":"working","pane_id":"w2:p6"},{"name":"s-auth","agent_status":"idle","pane_id":"w2:p7"},{"name":"x-esc","agent_status":"working","pane_id":"w2:p8"},{"name":"plan-e9","agent_status":"working","pane_id":"w2:p9"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"},{"pane_id":"w9:p1"},{"pane_id":"w1:p4"},{"pane_id":"w1:p5"},{"pane_id":"w1:p6"},{"pane_id":"w1:p7"},{"pane_id":"w1:p8"},{"pane_id":"w1:p9"},{"pane_id":"w1:p10"},{"pane_id":"w1:p11"},{"pane_id":"w2:p1"},{"pane_id":"w2:p2"},{"pane_id":"w2:p3"},{"pane_id":"w2:p4"},{"pane_id":"w2:p5"},{"pane_id":"w2:p6"},{"pane_id":"w2:p7"},{"pane_id":"w2:p8"},{"pane_id":"w2:p9"}]}}' ;;
  "agent wait") echo "$*" >> "${WAIT_LOG:-/dev/null}"
    [ -z "${WAIT_TIMES:-}" ] || python3 -c 'import time; print(int(time.time() * 1000))' >> "${WAIT_TIMES}"
    [ -z "${WAIT_SLEEP:-}" ] || sleep "${WAIT_SLEEP}"
    if [ -n "${WAIT_SWAP:-}" ] && [ -e "${WAIT_SWAP}.new" ]; then mv "${WAIT_SWAP}.new" "${WAIT_SWAP}"; fi   # the session changes while herdr waits
    echo "herdr: a notice on stderr" >&2
    case "${WAIT_MODE:-done}" in
      timeout) echo '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}' >&2; exit 1 ;;
      error) echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1 ;;
      *) echo "{\"result\":{\"agent\":{\"agent_status\":\"${WAIT_MODE:-done}\"}}}" ;;
    esac ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"2026-01-01-x"},{"workspace_id":"w9","label":"other"}]}}' ;;
  "agent read") [ -z "${AR_LOG:-}" ] || echo "$3" >> "${AR_LOG}"; exit 1 ;;
  "pane process-info") [ -z "${PI_LOG:-}" ] || echo "$4 $(/bin/ps -o comm= -p "$PPID")" >> "${PI_LOG}"
    s="$(awk -v p="$4" '$1 == p { print $2 }' "${PI_MAP:-/dev/null}")"
    [ -n "$s" ] || exit 1
    echo "{\"result\":{\"process_info\":{\"pane_id\":\"$4\",\"shell_pid\":$s}}}" ;;
  *) exit 1 ;;
esac
STUB
# ps: the process list in PS_LIST when the test wrote one; any other call is the real ps.
cat > "${ROOT}/bin/ps" <<'STUB'
#!/bin/sh
if [ "$*" = "-A -o pid=,ppid=,etime=,command=" ] && [ -n "${PS_LIST:-}" ]; then cat "${PS_LIST}"; exit 0; fi
exec /bin/ps "$@"
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/herdr"
# gh: PR 7's checks are green and its branch is behind the base.
# PR 8 was updated at the time in pr8.updated.
cat > "${ROOT}/bin/gh" <<STUB
#!/bin/sh
U8="${ROOT}/pr8.updated"
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${U8%/*}/gh.log"
case "$1 $2 $3" in
  "pr view https://github.com/o/r/pull/7") echo '{"mergeStateStatus":"BEHIND","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","state":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/r/pull/8") if [ "$6" = -q ]; then cat "$U8"; else echo "{\"updatedAt\":\"$(cat "$U8")\"}"; fi ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/nobin/herdr" "${ROOT}/bin/gh" "${ROOT}/nobin/gh" "${ROOT}/bin/ps"

# The board is committed, with one merge on the base branch; then one board file is edited.
G=(git -C "${P}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
touch "${P}/docs/stories/README.md"   # init's marker: dash dies without it
# The board's commits are dated, as the merge is: the items in needs you wait from them.
export GIT_AUTHOR_DATE=2026-07-05T11:00:00Z GIT_COMMITTER_DATE=2026-07-05T11:00:00Z
"${G[@]}" add docs && "${G[@]}" commit -qm board
"${G[@]}" rm -q docs/stories/s-old.md && "${G[@]}" commit -qm "finish s-old"
"${G[@]}" checkout -qb story/s-zero && "${G[@]}" commit -q --allow-empty -m work
# A fixed merge time, so no relative time in recent moves while the pty tests watch.
"${G[@]}" checkout -q - && GIT_COMMITTER_DATE=2026-07-05T12:00:00Z "${G[@]}" merge -q --no-ff -m "Merge pull request #9 from o/story/s-zero" story/s-zero
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
echo "more" >> "${P}/docs/stories/s-three.md"; echo "more" >> "${P}/docs/stories/s-two.md"

# --- Stalls. s-three's builder is working, and its story was started 2 hours ago with nothing since:
# no worktree commit, no PR, its session log last written then.
touch -t "$(mins_ago 120)" "${ROOT}/projects/p/sess-today.jsonl"
printf '%s\tstory\ts-three\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
printf '%s\tconduct\te1\tw1:p1\tok\n' "$(ago 4)" >> "${P}/.swarm/events.tsv"
# herdr's process info for a pane is logged with the program that asked for it. Here s-three's pane
# shell is 100 (PI_MAP) and ps (PS_LIST) shows no test run under it: still stalled. Elsewhere, with no
# PI_MAP, the read fails, and the stalls hold all the same.
export PI_LOG="${ROOT}/process-info.log" PS_LIST="${ROOT}/ps.list"
echo 'w1:p9 100' > "${ROOT}/pi.map"
printf '%s\n' '  100     1  02:10:00 -zsh' '  200   100  02:09:00 claude' > "${ROOT}/ps.base"; cp "${ROOT}/ps.base" "${PS_LIST}"
fresh; out="$(cd "${P}" || exit 1; PI_MAP="${ROOT}/pi.map" HERDR_ENV=1 COLUMNS=160 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
read_panes() { cut -d' ' -f1 "${PI_LOG}" | sort -u | tr '\n' ' '; }
check "only the stalled builder's pane is asked for its process info, not the conductor working under stall_minutes" \
  test "$(read_panes)" = "w1:p9 "
check "at 160 columns a working agent's card shows its state age, then the time since it started" grep -qE '● conduct-e1 +conduct +opus·high +working 4m  4m( +[^│]*)? *│' <<< "${out}"
check "at 160 columns a stalled builder keeps its !" grep -qE '! s-three +code +opus·high +stalled 120m( +[^│]*)? *│' <<< "${out}"
check "with no test run under its pane the builder still needs you" grep -qE '! look at s-three: working 120 min' <<< "${out}"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder working 2 hours with no sign of life is stalled" grep -qE '! s-three .*stalled 120m' <<< "${out}"
check "a stalled builder needs you" grep -qE '! look at s-three: working 120 min with no commit, edit, session-log write or PR update' <<< "${out}"
check "the summary counts the stall" has " · 1 stalled · " "$(sed -n 5p <<< "${out}")"
check "recent shows a start minutes ago, newest first" grep -qE '^│    4m ago  ▶ conduct e1 ' <<< "$(sed -n '/^╭─ recent/{n;p;}' <<< "${out}")"
check "recent shows hours ago" grep -qE '^│    2h ago  ▶ story s-three ' <<< "${out}"
mkdir -p "${P}/.claude/swarm"; echo "stall_minutes = 300" > "${P}/.claude/swarm/config"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "stall_minutes sets the threshold" lacks "look at s-three" "${out}"
rm "${P}/.claude/swarm/config"
# make test running under s-three's pane shell for 5 minutes is work: working, not stalled, and not
# under needs you. The frame is rendered once: herdr's agent read (shown_state's, AR_LOG) of s-three's
# pane runs once.
{ cat "${ROOT}/ps.base"; printf '%s\n' '  300   200     05:00 /bin/zsh -c make test' '  310   300     05:00 make test'; } > "${PS_LIST}"
fresh; out="$(cd "${P}" || exit 1; AR_LOG="${ROOT}/agent-read.log" PI_MAP="${ROOT}/pi.map" HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a stalled builder running make test under its pane is working" grep -qE '● s-three .*working 120m' <<< "${out}"
check "a builder running make test is not under needs you" lacks "look at s-three" "${out}"
check "a frame with a test run reads each agent's pane once: one render" test "$(grep -cx 'w1:p9' "${ROOT}/agent-read.log")" = 1
# The same run started 100 minutes ago, past 3 x stall_minutes (90), may be hung: stalled, and it needs you.
{ cat "${ROOT}/ps.base"; printf '%s\n' '  300   200  01:40:00 /bin/zsh -c make test' '  310   300  01:40:00 make test'; } > "${PS_LIST}"
fresh; out="$(cd "${P}" || exit 1; PI_MAP="${ROOT}/pi.map" HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder whose make test started past 3 x stall_minutes ago is stalled" grep -qE '! s-three .*stalled 120m' <<< "${out}"
check "a builder whose make test started past 3 x stall_minutes ago needs you" grep -qE '! look at s-three: working 120 min' <<< "${out}"
cp "${ROOT}/ps.base" "${PS_LIST}"
# A file edited a minute ago in s-three's worktree (its last commit 2 hours old) is a sign of life:
# working, not stalled. Aged past stall_minutes, it is not: stalled again.
wt="${P}-wt/s-three"; git init -q "${wt}"
GIT_COMMITTER_DATE="@$((SWARM_DASH_NOW - 7200))" git -C "${wt}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m old
echo wip > "${wt}/wip.txt"; touch -t "$(mins_ago 1)" "${wt}/wip.txt"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder with a file edited a minute ago in its worktree is working, not stalled" grep -qE '● s-three .*working' <<< "${out}"
touch -t "$(mins_ago 120)" "${wt}/wip.txt"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "the same file edited 2 hours ago leaves it stalled" grep -qE '! s-three .*stalled 120m' <<< "${out}"
rm -rf "${P}-wt"

# --- State age. aaaa…-2's builder is working (herdr's word), started 25 minutes ago, and its
# worktree's last commit is 12 minutes old: the row shows 12m right after its state, and at 160
# columns the 25m since its start after that, so 12m can only be the state age.
cp "${P}/.swarm/events.tsv" "${ROOT}/events.before-age"; cp "${P}/.swarm/findings.tsv" "${ROOT}/findings.before-age"
A=aaaaaaaaaa-bbbbbbbbbb-cccccccccc
mkdir -p "${ROOT}/proj-wt/${A}-2" && git -C "${ROOT}/proj-wt/${A}-2" init -q
GIT_COMMITTER_DATE="$(ago 12)" git -C "${ROOT}/proj-wt/${A}-2" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m work
printf '%s\tstory\t%s-2\tw1:p1\tok\n' "$(ago 25)" "${A}" >> "${P}/.swarm/events.tsv"
agedash() { (cd "${P}" || exit 1; fresh; HERDR_ENV=1 LINES=80 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true); }
out="$(COLUMNS=160 agedash)"
check "at 160 columns a working builder shows its state age, then the time since it started" grep -qE '● aaaaaaaaaa-bbbbbbbbbb-ccccccc… .* working 12m  25m( +[^│]*)? *│' <<< "${out}"
check "at 160 columns a conductor keeps its time since start after its state age" grep -qE '● conduct-e1 +conduct +opus·high +working 4m  4m( +[^│]*)? *│' <<< "${out}"
check "at 160 columns a stalled builder still shows stalled" grep -qE '! s-three +code +opus·high +stalled 120m( +[^│]*)? *│' <<< "${out}"
out="$(COLUMNS=100 agedash)"
check "at 100 columns a working builder shows its state age" grep -qE '● aaaaaaaaaa-bbbbbbbbbb-ccccccc… .* working 12m( +[^│]*)? *│$' <<< "${out}"
check "at 100 columns a stalled builder still shows stalled" grep -qE '! s-three .*stalled 120m( +[^│]*)? *│$' <<< "${out}"
check "a stalled builder still needs you, in the same words" grep -qE '! look at s-three: working 120 min with no commit, edit, session-log write or PR update' <<< "${out}"
check "a conductor below stall_minutes is working, not stalled" grep -qE '● conduct-e1 +conduct +opus·high +working 4m( +[^│]*)? *│$' <<< "${out}"
# The conductor's newest sign (its start, from its own pane) is 4 minutes old: past stall_minutes = 3.
echo "stall_minutes = 3" > "${P}/.claude/swarm/config"
out="$(COLUMNS=100 agedash)"
check "a conductor past stall_minutes is stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled 4m( +[^│]*)? *│$' <<< "${out}"
check "a stalled conductor needs you" grep -qE '! look at conduct-e1: working 4 min with no swarm action' <<< "${out}"
# The same conductor with make check running under its pane shell (500) is working, and not under needs you.
echo 'w1:p1 500' > "${ROOT}/pi.map"
{ cat "${ROOT}/ps.base"; printf '%s\n' '  500     1     08:00 -zsh' '  510   500     07:00 claude' '  520   510     02:00 make check'; } > "${PS_LIST}"
out="$(PI_MAP="${ROOT}/pi.map" COLUMNS=100 agedash)"
check "a stalled conductor running make check under its pane is working" grep -qE '● conduct-e1 +conduct +opus·high +working 4m( +[^│]*)? *│$' <<< "${out}"
check "a conductor running make check is not under needs you" lacks "look at conduct-e1" "${out}"
cp "${ROOT}/ps.base" "${PS_LIST}"
# A session log written a minute ago is a sign of life for any agent with a Claude session: the
# conductor (sess-1) and a planner (plan-e9, no story and no events.tsv line) are working. With the
# logs written 10 minutes ago, past stall_minutes, both are stalled.
printf 'w2:p9 plan-e9\n' > "${P}/.swarm/state/plan-e9"
printf '%s\tplan\tplan-e9\tclaude\topus\thigh\tsess-plan\n' "${TODAY}" >> "${P}/.swarm/agents.tsv"
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-today","status":"busy"},{"sessionId":"sess-plan","status":"busy"}]' > "${ROOT}/claude-plan.json"
for s in sess-1 sess-plan; do echo '{}' > "${ROOT}/projects/p/${s}.jsonl"; touch -t "$(mins_ago 1)" "${ROOT}/projects/p/${s}.jsonl"; done
out="$(CLAUDE_STUB_AGENTS="${ROOT}/claude-plan.json" COLUMNS=100 agedash)"
check "a conductor whose session log was written a minute ago is working" grep -qE '● conduct-e1 +conduct +opus·high +working 1m( +[^│]*)? *│$' <<< "${out}"
check "a planner whose session log was written a minute ago is working" grep -qE '● plan-e9 +plan +opus·high +working 1m( +[^│]*)? *│$' <<< "${out}"
touch -t "$(mins_ago 10)" "${ROOT}/projects/p/sess-1.jsonl" "${ROOT}/projects/p/sess-plan.jsonl"
out="$(CLAUDE_STUB_AGENTS="${ROOT}/claude-plan.json" COLUMNS=100 agedash)"
check "a conductor whose session log is older than stall_minutes is stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled 4m( +[^│]*)? *│$' <<< "${out}"
check "a planner whose session log is older than stall_minutes is stalled" grep -qE '! plan-e9 +plan +opus·high +stalled 10m( +[^│]*)? *│$' <<< "${out}"
rm "${P}/.swarm/state/plan-e9" "${ROOT}/projects/p/sess-1.jsonl" "${ROOT}/projects/p/sess-plan.jsonl"
# A nudge its pane sent a minute ago (wait's, or the lead's tell:nudge) and a tell that never reached
# anyone are not signs of life (STALL_PY's rule): the conductor stays stalled.
printf '%s\tnudge\ts-one\tw1:p1\tok\n%s\ttell:nudge\ts-one\tw1:p1\tok\n%s\ttell:findings\ts-one\tw1:p1\tfailed (exit 1)\n' "$(ago 1)" "$(ago 1)" "$(ago 1)" >> "${P}/.swarm/events.tsv"
check "a conductor whose only recent pane lines are nudges is still stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled 4m( +[^│]*)? *│$' <<< "$(COLUMNS=100 agedash)"
# The lead's board-pr step a minute ago, named after s-three (a re-scope of it), is no sign of life
# for s-three's builder: it stays stalled.
cp "${P}/.swarm/events.tsv" "${ROOT}/events.bak"
printf '%s\tboard-pr:start\ts-three\tw0:p1\tok\n' "$(ago 1)" >> "${P}/.swarm/events.tsv"
check "a board-pr line named after a story is no sign of life for its builder" grep -qE '! s-three .*stalled' <<< "$(COLUMNS=100 agedash)"
cp "${ROOT}/events.bak" "${P}/.swarm/events.tsv"
# A note the lead left the conductor a minute ago (tell:note, from the lead's pane) is no sign of
# life: with its session log older than stall_minutes it stays stalled. The same line as tell:resume is.
echo '{}' > "${ROOT}/projects/p/sess-1.jsonl"; touch -t "$(mins_ago 10)" "${ROOT}/projects/p/sess-1.jsonl"
cp "${P}/.swarm/events.tsv" "${ROOT}/events.bak"
for k in note resume; do
  cp "${ROOT}/events.bak" "${P}/.swarm/events.tsv"
  printf '%s\ttell:%s\tconduct-e1\tw0:p1\tok\n' "$(ago 1)" "${k}" >> "${P}/.swarm/events.tsv"
  out="$(COLUMNS=100 agedash)"
  if [[ ${k} == note ]]; then check "a conductor whose only recent line is a note to it is still stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled 4m( +[^│]*)? *│$' <<< "${out}"
  else check "a conductor whose only recent line is a resume tell to it is working" grep -qE '● conduct-e1 +conduct +opus·high +working 1m( +[^│]*)? *│$' <<< "${out}"; fi
done
cp "${ROOT}/events.bak" "${P}/.swarm/events.tsv"; rm "${ROOT}/projects/p/sess-1.jsonl"
# A command its own pane ran a minute ago (a review of s-one, not naming it) is a sign of life.
printf '%s\treview\ts-one\tw1:p1\tok\n' "$(ago 1)" >> "${P}/.swarm/events.tsv"
check "a line from a conductor's own pane is a sign of life" grep -qE '● conduct-e1 +conduct +opus·high +working 1m( +[^│]*)? *│$' <<< "$(COLUMNS=100 agedash)"
rm "${P}/.claude/swarm/config"

# Every process-info read came from dash.sh: its bash, or the perl of report_read's within, which runs
# the read under dash's deadline (dash_deadline). None from the render's python.
from_bash() { local n; n="$(wc -l < "${PI_LOG}")"; [[ ${n} -gt 0 && "$(grep -cE '^w[0-9]+:p[0-9]+ (.*/)?(bash|perl)$' "${PI_LOG}")" -eq ${n} ]]; }
check "every herdr process-info read comes from dash.sh, none from dash_render.py" from_bash

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
