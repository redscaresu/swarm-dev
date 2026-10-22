#!/usr/bin/env bash
# dash_wait_test.sh — wait and wait --stall on P's builders: slices, stalls, tells and a codex
# agent herdr answers for.
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
echo "more" >> "${P}/docs/stories/s-three.md"; echo "more" >> "${P}/docs/stories/s-two.md"

# s-three's builder is working, and its story was started 2 hours ago with nothing since: no
# worktree commit, no PR, its session log last written then.
mins_ago() { python3 -c 'import sys, time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 60 * int(sys.argv[1]))))' "$1"; }
touch -t "$(mins_ago 120)" "${ROOT}/projects/p/sess-today.jsonl"
printf '%s\tstory\ts-three\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
printf '%s\tconduct\te1\tw1:p1\tok\n' "$(ago 4)" >> "${P}/.swarm/events.tsv"
# wait: herdr says done at once (the stub), and s-three's session (sess-today) is busy, so a wait
# sleeps out each slice and reads the session again; herdr's word is never the answer.
printf '[{"sessionId":"sess-today","status":"busy"},{"sessionId":"sess-cut","status":"busy"}]' > "${ROOT}/claude.json"
waitfor() { (cd "${P}" || exit 1; HERDR_ENV=1 SWARM_STALL_POLL_MS="${SWARM_STALL_POLL_MS:-1000}" CLAUDE_STUB_AGENTS="${CLAUDE_STUB_AGENTS:-${ROOT}/claude.json}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait "$@" 2>&1); }
long_ago() { SWARM_WAIT_STARTED=$(( $(date +%s) - 7200 )) waitfor "$@"; }
t0=${SECONDS}
if out="$(WAIT_LOG="${ROOT}/wait.log" CLAUDE_STUB_LOG="${ROOT}/claude.log" waitfor s-three 3000)"; then rc=0; else rc=$?; fi
took=$((SECONDS - t0))
check "a bare wait on a busy, stalled builder times out with its state: no stall" test "${rc}:${out}" == "1:busy"
# The last slice is cut to the deadline, so it may be a little short of the others.
check "a bare wait polls herdr in slices" test "$(awk '$1 $2 $3 == "agentwaitw1:p9" && $4 == "--timeout" && $5 > 0 && $5 <= 1000 { n++ } END { print n, NR }' "${ROOT}/wait.log")" == "3 3"
check "each slice herdr cut short is slept out, so the wait lasts its timeout" test "${took}" -ge 2
# Slices are timed in milliseconds: a herdr wait of half a second is slept out to the slice, never
# rounded to a whole second (a gap of 0.5 s or 1.5 s between wakes).
WAIT_TIMES="${ROOT}/wait.times" WAIT_SLEEP=0.5 waitfor s-three 3000 >/dev/null || true
check "each slice lasts its STALL_POLL_MS, timed in milliseconds" test "$(awk 'NR > 1 { g = $1 - p; if (g < 900 || g > 1450) bad = 1 } { p = $1 } END { print NR, (bad ? "off" : "on time") }' "${ROOT}/wait.times")" == "3 on time"
# One read before the first wake, one after each of the 3, and one at the deadline after the last
# slice's early wake: herdr wakes at once here, so every slice is slept out.
check "a 3-slice wait lists Claude's sessions at most 5 times" test "$(grep -c '^agents --json$' "${ROOT}/claude.log")" -le 5
# wait --stall counts from when the wait began: started now, 2 hours of silence before it do not count.
if out="$(waitfor --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "wait --stall counts from its own start" test "${rc}:$(grep -c stalled <<< "${out}")" == "1:0"
# Begun 2 hours ago (the test hook), it returns on the stall with exit code 3: herdr says done, but
# the session is busy, and busy is what the stall rule reads.
if out="$(long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "wait --stall returns on a stall with exit code 3" test "${rc}" -eq 3
check "wait --stall says why" grep -qE '^stalled: working 1(19|20|21) min with no commit, edit, own work in the session log or PR update; longest-running: none named \(.*\)$' <<< "${out}"
# A nudge is wait's doing, not a sign of life: a fresh `nudge s-three` line leaves the builder stalled.
printf '%s\tnudge\ts-three\tw1:p1\tok\n' "$(ago 0)" >> "${P}/.swarm/events.tsv"
if out="$(long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "a nudge line does not lower a builder's stall age" test "${rc}" -eq 3
# A tell is a swarm action on its story when it reached the builder: its line (tell:<kind>, the slug
# as its target) lowers the stall age. A tell:nudge is a nudge, as wait's are, and a tell refused
# (the session busy) never reached the builder: neither lowers it.
printf '[{"sessionId":"sess-today","status":"idle"}]' > "${ROOT}/claude.json.told"
echo "- a finding" > "${ROOT}/findings.md"; cp "${P}/.swarm/events.tsv" "${ROOT}/events.keep"
tellstall() { # <session file> <kind> — tell s-three with its session read from <session file>, then
  # wait --stall on it (its session busy again); print "<told?>:<wait's exit>" and drop the tell's line
  local told=no rc=0
  (cd "${P}" && HERDR_ENV=1 CLAUDE_STUB_AGENTS="$1" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell s-three "$2" "${ROOT}/findings.md" >/dev/null 2>&1) && told=yes
  long_ago --stall s-three 3000 >/dev/null || rc=$?
  cp "${ROOT}/events.keep" "${P}/.swarm/events.tsv"
  echo "${told}:${rc}"
}
check "a delivered tell lowers its builder's stall age" test "$(tellstall "${ROOT}/claude.json.told" findings)" == "yes:1"
check "a tell:nudge does not lower its builder's stall age" test "$(tellstall "${ROOT}/claude.json.told" nudge)" == "yes:3"
check "a refused tell does not lower its builder's stall age" test "$(tellstall "${ROOT}/claude.json" findings)" == "no:3"
# Past stall_minutes, the session is busy before the first wake and idle on the read after it: the
# stall check takes only the read after the wake, so wait returns idle, not stalled.
cp "${ROOT}/claude.json" "${ROOT}/claude.json.flip"
printf '[{"sessionId":"sess-today","status":"idle"}]' > "${ROOT}/claude.json.flip.new"
if out="$(WAIT_SWAP="${ROOT}/claude.json.flip" CLAUDE_STUB_AGENTS="${ROOT}/claude.json.flip" long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "a builder idle on the read after the wake is idle, not stalled" test "${rc}:${out}" == "0:idle"
# An idle session has settled, and stalls are not checked.
printf '[{"sessionId":"sess-today","status":"idle"}]' > "${ROOT}/claude.json.idle"
if out="$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json.idle" long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "wait --stall returns an idle session's state" test "${rc}:${out}" == "0:idle"
# Two stories share an agent name's 32 characters; the builder is the one not done.
printf '%s\tstory\taaaaaaaaaa-bbbbbbbbbb-cccccccccc-2\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
# While that builder is a codex agent, herdr answers for it (herdr_wait): herdr's stderr notice never
# reaches the JSON parse, a step that times out is told from a real failure, and stalls are checked
# between steps.
printf '%s\tcode\taaaaaaaaaa-bbbbbbbbbb-cccccccccc\tcodex\tgpt\thigh\t-\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
if out="$(WAIT_MODE=idle waitfor --stall aaaaaaaaaa-bbbbbbbbbb-cccccccccc 3000)"; then rc=0; else rc=$?; fi
check "a codex agent's wait reads herdr's status with a notice on stderr" test "${rc}:${out}" == "0:idle"
: > "${ROOT}/wait.log"; WAIT_LOG="${ROOT}/wait.log" WAIT_MODE=timeout waitfor aaaaaaaaaa-bbbbbbbbbb-cccccccccc 3000 >/dev/null || true
check "a codex agent's step that times out is stepped past" test "$(grep -c . "${ROOT}/wait.log")" -eq 3
rc=0; : > "${ROOT}/wait.log"; WAIT_LOG="${ROOT}/wait.log" WAIT_MODE=error waitfor aaaaaaaaaa-bbbbbbbbbb-cccccccccc 3000 >/dev/null || rc=$?
check "a codex agent's step that fails for real ends the stepping, and the wait fails" test "$(grep -c . "${ROOT}/wait.log"):${rc}" == "2:1"
if out="$(WAIT_MODE=timeout long_ago --stall aaaaaaaaaa-bbbbbbbbbb-cccccccccc-2 3000)"; then rc=0; else rc=$?; fi
check "a codex builder's wait --stall returns on a stall between steps" test "${rc}:$(grep -c '^stalled: working' <<< "${out}")" == "3:1"
printf '%s\tcode\taaaaaaaaaa-bbbbbbbbbb-cccccccccc\tclaude\topus\thigh\tsess-cut\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "dash maps a cut agent name to the story not done" grep -qE 'look at aaaaaaaaaa-bbbbbbbbbb-cccccccccc: working 1(19|20|21) min' <<< "${out}"
if out="$(long_ago --stall aaaaaaaaaa-bbbbbbbbbb-cccccccccc-2 3000)"; then rc=0; else rc=$?; fi
check "wait maps a cut agent name to the story not done" test "${rc}" -eq 3
# A PR updated a minute ago is a sign of life: neither dash nor wait --stall calls it stalled.
ago 1 > "${ROOT}/pr8.updated"
# Into the front matter: dash reads keys there only.
awk 'NR > 1 && /^---$/ && !d { print "prs: https://github.com/o/r/pull/8"; d = 1 } { print }' "${P}/docs/stories/s-three.md" > "${ROOT}/s3" && mv "${ROOT}/s3" "${P}/docs/stories/s-three.md"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a recent PR update is not a stall in dash" lacks "look at s-three" "${out}"
if out="$(long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "a recent PR update is not a stall in wait --stall" test "${rc}:$(grep -c stalled <<< "${out}")" == "1:0"


[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
