#!/usr/bin/env bash
# dash_layout_test.sh — the frame: its panels, header, summary, --tree and --ladder, a failing
# herdr or gh, and a repo with no board.
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
printf '2026-10-01\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-1\n2026-10-02\tcode\ts-one\tclaude\topus\thigh\tsess-2\n' > "${P}/.swarm/agents.tsv"
# Today's cost, the same as `swarm.sh cost <today>`: 1M input at $4 + 1M output at $20.
printf '%s\tcode\ts-three\tclaude\topus\thigh\tsess-today\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
echo '{"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":1000000}}}' > "${ROOT}/projects/p/sess-today.jsonl"
# One escalate agent whose session ran on opus (its first message with a model), not the fable its
# policy names; the ladder shows the session's model. No docs agent: docs shows 0.
printf '2026-10-02\tescalate\tx-esc\tclaude\tfable\txhigh\tsess-esc\n' >> "${P}/.swarm/agents.tsv"
# Ahead of opus: a non-string model and a failed turn's "<synthetic>" one, both skipped.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}' '{"message":{"model":5}}' \
  '{"message":{"id":"e0","model":"<synthetic>"}}' '{"message":{"id":"e1","model":"claude-opus-5-5"}}' \
  '{"message":{"id":"e2","model":"claude-fable-5-1"}}' > "${ROOT}/projects/p/sess-esc.jsonl"
# A chore agent whose log cannot be read: it counts, with no model, and the ladder still draws.
printf '2026-10-02\tchore\tx-chore\tclaude\thaiku\tmedium\tsess-locked\n' >> "${P}/.swarm/agents.tsv"
echo '{}' > "${ROOT}/projects/p/sess-locked.jsonl"; chmod 000 "${ROOT}/projects/p/sess-locked.jsonl"
# A session log's mtime is a sign of life (the stall rule): x-esc's was written before the
# escalation block's fixed now (SWARM_DASH_NOW, 2026-10-10 noon).
touch -t 202610101100 "${ROOT}/projects/p/sess-esc.jsonl"
printf '2026-10-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
# Five findings on another PR the same day: one recent row, not five.
for i in 1 2 3 4 5; do printf '2026-10-04\tkind%s\thttps://github.com/o/r/pull/8\tfinding %s\n' "${i}" "${i}" >> "${P}/.swarm/findings.tsv"; done
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
printf '2026-10-03T10:00:00Z\tfinish\ts-zero\tw1:p1\tok\n2026-10-04T10:00:00Z\treview\ts-one\tw1:p1\tok\n' > "${P}/.swarm/events.tsv"
# Older actions, so that from 140 columns the recent log is taller than the needs-you box beside it.
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '2026-09-%02dT10:00:00Z\ttell\told-%s\tw1:p1\tok\n' "${i}" "${i}" >> "${P}/.swarm/events.tsv"; done

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
  *) exit 1 ;;
esac
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
chmod +x "${ROOT}/bin/herdr" "${ROOT}/nobin/herdr" "${ROOT}/bin/gh" "${ROOT}/nobin/gh"

# The board is committed, with one merge on the base branch; then one board file is edited.
G=(git -C "${P}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
touch "${P}/docs/stories/README.md"   # init's marker: dash dies without it
"${G[@]}" add docs && "${G[@]}" commit -qm board
"${G[@]}" rm -q docs/stories/s-old.md && "${G[@]}" commit -qm "finish s-old"
"${G[@]}" checkout -qb story/s-zero && "${G[@]}" commit -q --allow-empty -m work
# A fixed merge time, so no relative time in recent moves while the pty tests watch.
"${G[@]}" checkout -q - && GIT_COMMITTER_DATE=2026-10-05T12:00:00Z "${G[@]}" merge -q --no-ff -m "Merge pull request #9 from o/story/s-zero" story/s-zero
fresh; clean="$(cd "${P}" || exit 1; PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a committed board shows no drift line" lacks "board:" "${clean}"
check "with no agent open and nothing held, the frame has no running-now box" lacks "running now" "${clean}"
echo "more" >> "${P}/docs/stories/s-three.md"; echo "more" >> "${P}/docs/stories/s-two.md"

# gh-calls.tsv is gh-shim's log of dash's own gh calls, made before the snapshot so the folder's entry holds.
: >> "${P}/.swarm/gh-calls.tsv"
# shellcheck disable=SC2010 # names swarm.sh wrote, filtered for the one file dash may write
snapshot() { (cd "${P}" && find docs .swarm -type f ! -name gh-calls.tsv -print0 | sort -z | xargs -0 cksum; ls -laR docs .swarm | grep -v -e gh-calls.tsv -e '^total ') ; }
before="$(snapshot)"

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
for panel in "needs you" "epics" "recent"; do
  check "panel ${panel}" has "╭─ ${panel} ─" "${out}"
done
check "the header is one line: project, version, merge, next, clock" grep -qE '^proj  swarm-dev [0-9.]+  merge human  next wait conduct-e1 +[0-9]{2}:[0-9]{2}:[0-9]{2}$' <<< "$(head -1 <<< "${out}")"
check "the speedometer is the line under the header" grep -qE '^0[.]0 merged/day over 7 days · ! [0-9]+ waiting on you, oldest [0-9hmd]+ · ✓ 0 escaped in 7 days$' <<< "$(sed -n 2p <<< "${out}")"
check "the summary line counts epics, working agents, green PRs, stalls and cost" test "$(sed -n 5p <<< "${out}")" == "1 epics active · 3 agents working · 1 PRs green, waiting · 0 stalled · \$24.00 today"
check "below 140 columns, on call and today's escalations follow the summary, on a line of their own when it is full" test "$(sed -n 6p <<< "${out}")" == "on call: fable·xhigh · 0 escalations today"
check "uncommitted board edits are one line under the summary, naming each file" test "$(sed -n 7p <<< "${out}")" == "board: 2 uncommitted edits in the main checkout: stories/s-three.md, stories/s-two.md"
check "needs you is the first panel" grep -q '^╭─ needs you ─' <<< "$(grep -m1 '^╭─' <<< "${out}")"
needs="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}")"
check "needs you lists a green PR as a merge" grep -qE '^│ ! merge r#7 \(✓ green · behind\)  s-one +│$' <<< "${needs}"
check "needs you lists a lead story with its title" has "! run lead story ask: create the read-only IAM user" "${needs}"
check "needs you lists an agent waiting on a prompt, with what its session waits for" has "! answer s-one (waiting on input): herdr agent read s-one" "${needs}"
check "needs you lists an empty pane" has "! close the empty pane s-gone: swarm.sh tidy" "${needs}"
# A long waitingFor over three lines is one line in needs you, cut at 60 characters, inside the box.
printf '%s' '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"Allow Bash to run:\n  rm -rf build && make all && make test && make install && echo done\n(y/n)"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude-long.json"
fresh; long="$(cd "${P}" || exit 1; HERDR_ENV=1 CLAUDE_STUB_AGENTS="${ROOT}/claude-long.json" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
longneeds="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${long}")"
check "a long, multi-line waitingFor is one line, cut with …" has "! answer s-one (waiting on Allow Bash to run: rm -rf build && make all && make test &&…): herdr agent read s-one" \
  "$(sed -e 's/^│ //' -e 's/ *│$//' <<< "${longneeds}" | paste -sd' ' - | tr -s ' ')"
check "a long, multi-line waitingFor keeps the needs-you box whole" test "$(sed '1d;$d' <<< "${longneeds}" | grep -cvE '^│ .* │$')" -eq 0
check "needs you lists only actionable items" test "$(grep -c '^│ ! ' <<< "${needs}")" -eq "$(($(wc -l <<< "${needs}") - 2))"
check "needs you lists no blocked item" lacks "s-two" "${needs}"
check "needs you lists no later item" lacks "e2" "${needs}"
check "blocked and later are one count line below the epics" grep -qE '^⏸ 1 blocked · 1 later  \(swarm.sh status --all lists them\)$' <<< "${out}"
epicp="$(sed -n '/^╭─ epics/,/^╰/p' <<< "${out}")"
check "an epic row shows progress, counting a finished story from git" grep -qE '^│ ! e1 +█{3}░{9}  1/4   1 review · 1 ready · 1 blocked +│$' <<< "${epicp}"
check "the conductor sits under its epic with role, model and status" grep -qE '^│   ● conduct-e1 +conduct +opus·high +working +│$' <<< "${epicp}"
check "an agent waiting on a prompt is marked ! with its waitingFor" grep -qE '^│   ! s-one +code +opus·high +waiting on input' <<< "${epicp}"
check "an epic's open PR sits under it" grep -qE '^│   ✓ r#7 +green · behind  s-one +│$' <<< "${epicp}"
check "an empty pane is marked !" grep -qE '! s-gone .*empty pane' <<< "${epicp}"
check "an odd agent record marks its row, not the panel" grep -qE '! odd .*unreadable: AttributeError' <<< "${epicp}"
check "a conductor that wrote its report shows under its later epic" grep -qE '✓ conduct-e2 .*reported' <<< "$(sed -n '/e2 (later)/,$p' <<< "${epicp}")"
check "an agent with no epic is grouped last" grep -qE '● aaaaaaaaaa-bbbbbbbbbb-ccccccc… .*working' <<< "$(sed -n '/no epic/,$p' <<< "${epicp}")"
check "a retired agent collapses into a count" grep -qE '^│ \+1 idle  \(--tree lists them\) +│$' <<< "${epicp}"
check "a collapsed agent is not listed" lacks "old-done" "${out}"
check "the workspace tree is not the main view" lacks "2026-01-01-x" "${out}"
check "the ladder is hidden by default" lacks "─ ladder" "${out}"
check "a date-only row sorts after that day's timed events" python3 -c 'import sys; t = sys.stdin.read(); sys.exit(not 0 < t.index("could not fail") < t.index("finish s-zero"))' <<< "${out}"
check "a line in a brief is not a pane of this project's" lacks "prose" "${out}"
check "a *.tmp tab record is skipped" lacks "halfway" "${out}"
check "another project's agent is not shown" lacks "foreign" "${out}"
recent="$(sed -n '/^╭─ recent/,/^╰/p' <<< "${out}")"
check "recent lists the newest first, with its icon and a relative time" grep -qE '^│ +[0-9]+d ago  ⇡ merged #9 story/s-zero ' <<< "$(sed -n 2p <<< "${recent}")"
check "recent shows an older action in days" grep -qE '^│ +[0-9]+d ago  · review s-one ' <<< "${recent}"
check "an agent in a state dash does not know shows ? and the word" grep -qE '^│   \? s-two +\? +\? +starting +│$' <<< "${epicp}"
check "recent lists a finding" grep -qE '✎ a test that could not fail \(#7\)' <<< "${recent}"
check "recent folds a PR's findings for a day into one row" has "5 findings: finding 1; finding 2" "${recent}"
check "recent's time and icon columns line up" test "$(sed '1d;$d' <<< "${recent}" | grep -cvE '^│ [ 0-9a-z]{9}  . ')" -eq 0
check "the legend is the last lines" test "$(tail -2 <<< "${out}" | paste -sd' ' -)" == "● working   ○ ready   ◐ review / CI running   ✓ done / green   ✗ failing   ⏸ blocked ! needs you (session gone or unknown)   ? unknown"
check "boxes have rounded corners" grep -qE '^╰─+╯$' <<< "${out}"
check "a run off a terminal has no ANSI escapes" lacks $'\033' "${out}"
widest() { python3 -c 'import sys; print(max(len(l) for l in sys.stdin.read().splitlines()))'; }
check "the default width is 100" test "$(widest <<< "${out}")" -eq 100

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --tree --ladder 2>&1 || true)"
check "--tree groups the agents by workspace" grep -qE '^│ 2026-01-01-x +│$' <<< "${out}"
check "--tree groups the agents by tab" has "├─ e1" "${out}"
check "--tree lists a retired agent" grep -qE 'old-done .*retired' <<< "${out}"
check "--tree shows a story's PR on its builder" grep -qE '! s-one .*waiting on input  https://g' <<< "${out}"
check "--ladder maps role to model and effort" has "code-risky → opus · xhigh" "${out}"
check "--ladder names codex" has "codex      → codex · high" "${out}"
check "--ladder counts a role's agents, with its sessions' models" has "code       → opus · high  2 opus " "${out}"
check "--ladder names the model a session ran on, not the policy's" has "escalate   → fable · xhigh  1 opus " "${out}"
check "--ladder shows 0 for a role with no agents" grep -qE "docs       → sonnet · medium  0( |$)" <<< "${out}"
check "--ladder has no verify row" lacks "verify" "${out}"
check "--ladder counts an agent whose log cannot be read, with no model" grep -qE "chore      → haiku · medium  1 +(│|[a-z-]+ *→)" <<< "${out}"
check "--ladder cells are as wide as the longest row: two a row at 100 columns, every role aligned" python3 -c '
import sys
t = sys.stdin.read().splitlines()
rows = t[next(i for i, l in enumerate(t) if "╭─ ladder" in l) + 1:]
rows = rows[:next(i for i, l in enumerate(rows) if l.startswith("╰"))]
cols = {tuple(i for i, c in enumerate(l) if c == "→") for l in rows[:-1]}
sys.exit(not (len(cols) == 1 and len(next(iter(cols))) == 2))' <<< "${out}"
check "below 140 columns the ladder and recent are stacked" lacks "╮ ╭─ recent" "${out}"

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a failing herdr degrades: agents unavailable" has "agents unavailable" "${out}"
check "a failing herdr still prints the epics" grep -qE '^│ . e1 +█' <<< "${out}"
check "a failing gh leaves the PR URL" has "! merge s-one: https://github.com/o/r/pull/7" "${out}"
check "dash never asks gh about a done item's PR" lacks "pull/9" "$(cat "${ROOT}/gh.log")"
# The gh and cost cache lasts a minute and serves a one-shot dash too: a failing gh is not asked.
fresh; (cd "${P}" && PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash >/dev/null 2>&1) || true
out="$(cd "${P}" || exit 1; PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a one-shot dash reuses the cached PR state" has "! merge r#7 (✓ green · behind)" "${out}"
# gh gets 5 seconds a PR: one that hangs is left out, and dash still draws.
mkdir -p "${ROOT}/slowgh"
printf '#!/bin/sh\nexec sleep 60\n' > "${ROOT}/slowgh/gh"; chmod +x "${ROOT}/slowgh/gh"
fresh; t0=$(date +%s)
out="$(cd "${P}" || exit 1; PATH="${ROOT}/slowgh:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a hanging gh is cut off after 5 seconds" test $(( $(date +%s) - t0 )) -lt 15
check "a hanging gh leaves the PR URL" has "! merge s-one: https://github.com/o/r/pull/7" "${out}"
fresh; out="$(cd "${P}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "outside herdr with no working herdr: agents unavailable" has "agents unavailable" "${out}"

check "dash changes nothing under the board or .swarm" test "$(snapshot)" == "${before}"

# --- A git repo with no board: dash and dash --watch stop at once and name swarm.sh init.
N="${ROOT}/noboard"; mkdir -p "${N}"; git -C "${N}" init -q
for args in "" "--watch 1"; do
  # shellcheck disable=SC2086 # args is split on purpose
  # perl's alarm kills it after 5 seconds (exit 142): macOS has no timeout(1).
  if out="$(fresh; cd "${N}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/nobin:${PATH}" perl -e 'alarm 5; exec @ARGV' bash "${SWARM}" dash ${args} 2>&1 </dev/null)"; then rc=0; else rc=$?; fi
  check "dash${args:+ }${args} with no board exits 1 within 5 s" test "${rc}" -eq 1
  check "dash${args:+ }${args} with no board says no board and names swarm.sh init" grep -q 'no board.*swarm.sh init' <<< "${out}"
  check "dash${args:+ }${args} with no board does not say nothing needs you" lacks "nothing needs you" "${out}"
done
# A board with nothing in progress or waiting: nothing needs you, and exit 0.
mkdir -p "${N}/docs/stories"; touch "${N}/docs/stories/README.md"
if out="$(fresh; cd "${N}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1)"; then rc=0; else rc=$?; fi
check "dash on an empty board exits 0" test "${rc}" -eq 0
check "dash on an empty board says nothing needs you" has "nothing needs you" "${out}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
