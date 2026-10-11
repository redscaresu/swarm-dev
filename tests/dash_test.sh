#!/usr/bin/env bash
# dash_test.sh — `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and
# events.tsv, a stub herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are
# stubbed to fail, so the width comes from COLUMNS (or the default 100), except in the pty test.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
P="${ROOT}/proj"

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
REALPATH="${PATH}"
export PATH="${ROOT}/size:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
git -C "${P}" init -q
item hld/2026-01-01-x.md 'status: agreed'
item epics/e1.md 'status: active' 'hld: 2026-01-01-x'
item epics/e2.md 'status: later'
item stories/s-one.md 'status: review' 'epic: e1' 'prs: https://github.com/o/r/pull/7'
item stories/s-two.md 'status: blocked' 'epic: e1' 'blocked_by: [s-one]'
item stories/s-three.md 'status: ready' 'epic: e1'
item stories/ask.md 'status: ready' 'kind: lead'
printf 'w1:p1 conductor\nw1:p2 s-one\nw1:p3 s-gone\nw1:p4 old\nw1:p5 odd\n' > "${P}/.swarm/state/e1"
# e2's conductor wrote its report and went idle: [reported], not [idle].
printf 'w1:p8 conduct-e2\n' > "${P}/.swarm/state/e2"
# s-three's builder is working; with no sign of life on record it is never stalled (the stall block below).
printf 'w1:p9 s-three\n' > "${P}/.swarm/state/s-three"
echo "# report" > "${P}/.swarm/conduct-e2.report.md"
# A codex brief in state/ is prose, not a tab record (own_panes' rule): its pane must not show.
printf 'w1:p6 is where the brief says to look\n' > "${P}/.swarm/state/brief-x.md"
# A half-written tab record (*.tmp) is skipped, as status and tidy skip it.
printf 'w1:p7 halfway\n' > "${P}/.swarm/state/e1.tmp"
printf '2026-10-01\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-1\n2026-10-02\tcode\ts-one\tclaude\topus\thigh\tsess-2\n' > "${P}/.swarm/agents.tsv"
# Today's cost, the same as `swarm.sh cost <today>`: 1M input at $4 + 1M output at $20.
printf '%s\tcode\ts-three\tclaude\topus\thigh\tsess-today\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
echo '{"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":1000000}}}' > "${ROOT}/projects/p/sess-today.jsonl"
printf '2026-10-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
# Five findings on another PR the same day: one recent row, not five.
for i in 1 2 3 4 5; do printf '2026-10-04\tkind%s\thttps://github.com/o/r/pull/8\tfinding %s\n' "${i}" "${i}" >> "${P}/.swarm/findings.tsv"; done
printf '2026-10-03T10:00:00Z\tfinish\ts-zero\tw1:p1\tok\n2026-10-04T10:00:00Z\treview\ts-one\tw1:p1\tok\n' > "${P}/.swarm/events.tsv"

# herdr: this project's conductor (working) and builder (blocked), an empty pane (w1:p3), and
# another project's agent (w9:p1), which must not be shown.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sess-1"}},{"name":"conduct-e2","agent_status":"idle","pane_id":"w1:p8"},{"name":"s-one","agent_status":"blocked","pane_id":"w1:p2"},{"name":"foreign","agent_status":"working","pane_id":"w9:p1"},{"name":"old-done","agent_status":"idle","pane_id":"w1:p4"},{"name":"odd","agent_status":"idle","pane_id":"w1:p5","agent_session":"not-an-object"},{"name":"prose","agent_status":"working","pane_id":"w1:p6"},{"name":"halfway","agent_status":"working","pane_id":"w1:p7"},{"name":"s-three","agent_status":"working","pane_id":"w1:p9"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"},{"pane_id":"w9:p1"},{"pane_id":"w1:p4"},{"pane_id":"w1:p5"},{"pane_id":"w1:p6"},{"pane_id":"w1:p7"},{"pane_id":"w1:p8"},{"pane_id":"w1:p9"}]}}' ;;
  "agent wait") echo '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}'; exit 1 ;;
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
"${G[@]}" add docs && "${G[@]}" commit -qm board
"${G[@]}" checkout -qb story/s-zero && "${G[@]}" commit -q --allow-empty -m work
"${G[@]}" checkout -q - && "${G[@]}" merge -q --no-ff -m "Merge pull request #9 from o/story/s-zero" story/s-zero
clean="$(cd "${P}" || exit 1; PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a committed board shows no drift line" lacks "board:" "${clean}"
echo "more" >> "${P}/docs/stories/s-three.md"

snapshot() { (cd "${P}" && find docs .swarm -type f -print0 | sort -z | xargs -0 cksum; ls -laR docs .swarm) ; }
before="$(snapshot)"

out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
for panel in "agents" "ladder" "waiting on you" "recent"; do
  check "panel ${panel}" has "─ ${panel}" "${out}"
done
check "the header is one line: project, version, merge, cost, next, clock" grep -qE '^proj  swarm-dev [0-9.]+  merge human  today [$]24\.00  next wait conduct-e1 +[0-9]{2}:[0-9]{2}:[0-9]{2}$' <<< "$(head -1 <<< "${out}")"
check "the pipeline is one line" grep -qE '^HLDs agreed 1  ·  epics active 1 later 1  ·  stories ready 2 blocked 1 review 1$' <<< "$(sed -n 2p <<< "${out}")"
check "an uncommitted board edit is one line under the pipeline" has "board: 1 uncommitted edit in the main checkout (reconcile pulls first)" "$(sed -n 3p <<< "${out}")"
check "a conductor that wrote its report shows reported" grep -qE 'conduct-e2 .*\[reported\]' <<< "${out}"
check "agents are grouped by workspace" has "2026-01-01-x" "${out}"
check "agents are grouped by tab" has "├─ e1" "${out}"
check "the conductor shows role, model and status" grep -qE 'conduct-e1 +conduct +opus·high +\[working\]' <<< "${out}"
check "a blocked agent needs a look, with its PR" grep -qE '! s-one +code +opus·high +\[WAITING\] +https://github.com/o/r/pull/7' <<< "${out}"
check "an empty pane needs a look" grep -qE '! s-gone .*\[EMPTY\]' <<< "${out}"
check "a retired agent shows as retired" grep -qE 'old-done .*\[retired\]' <<< "${out}"
check "an odd agent record marks its row, not the panel" grep -qE '! odd .*\[unreadable: AttributeError\]' <<< "${out}"
check "a date-only row sorts after that day's timed events" python3 -c 'import sys; t = sys.stdin.read(); sys.exit(not 0 < t.index("could not fail") < t.index("finish s-zero"))' <<< "${out}"
check "a line in a brief is not a pane of this project's" lacks "prose" "${out}"
check "a *.tmp tab record is skipped" lacks "halfway" "${out}"
check "another project's agent is not shown" lacks "foreign" "${out}"
check "the ladder maps role to model and effort" has "code-risky → opus · xhigh" "${out}"
check "the ladder names codex" has "codex      → codex · high" "${out}"
check "waiting on you lists a lead story" has "lead: ask" "${out}"
check "waiting on you shows a PR's checks and merge state" has "awaiting your merge: s-one r#7 ✔ behind" "${out}"
check "waiting on you collapses blocked and later into a count" has "blocked 1 · later 1 (swarm.sh status --all lists them)" "${out}"
check "waiting on you lists no blocked item" lacks "blocked: s-two" "${out}"
check "waiting on you lists no later item" lacks "later epic: e2" "${out}"
check "recent lists the merge, newest first" grep -qE 'merged #9 story/s-zero +\[merge\]' <<< "$(grep -A1 -- '─ recent' <<< "${out}")"
check "recent lists a swarm action" grep -qE 'review s-one +\[ok\]' <<< "${out}"
check "recent lists a finding" has "a test that could not fail (#7)" "${out}"
check "recent folds a PR's findings for a day into one row" has "5 findings: finding 1; finding 2" "${out}"
check "the status line is gone" lacks "survey: [sonnet high]" "${out}"
check "a run off a terminal has no ANSI escapes" lacks $'\033' "${out}"
widest() { python3 -c 'import sys; print(max(len(l) for l in sys.stdin.read().splitlines()))'; }
check "the default width is 100" test "$(widest <<< "${out}")" -eq 100
check "below 140 columns the ladder and recent are stacked" lacks "┐ ┌─ recent" "${out}"

out="$(cd "${P}" || exit 1; env -u HERDR_ENV COLUMNS=160 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "COLUMNS sets the width when stty and tput cannot" test "$(widest <<< "${out}")" -eq 160
check "from 140 columns the ladder and recent sit side by side" grep -qE '─ ladder ─+┐ ┌─ recent' <<< "${out}"
check "outside a herdr pane, a herdr that answers still shows the agents" grep -qE 'conduct-e1 +conduct +opus·high +\[working\]' <<< "${out}"

out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a failing herdr degrades: agents unavailable" has "agents unavailable" "${out}"
check "a failing herdr still prints the board" has "ready 2 blocked 1" "${out}"
check "a failing gh leaves the PR URL" has "awaiting your merge: s-one https://github.com/o/r/pull/7" "${out}"
out="$(cd "${P}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "outside herdr with no working herdr: agents unavailable" has "agents unavailable" "${out}"

# --watch off a terminal prints a frame only when it changed, plain, until stopped.
(cd "${P}" && exec env -u HERDR_ENV bash "${SWARM}" dash --watch 1 > "${ROOT}/watch.out" 2>&1) &
pid=$!; sleep 3; kill -TERM "${pid}" || true; wait "${pid}" || true
w="$(cat "${ROOT}/watch.out")"
check "--watch off a terminal draws the frame" has "─ agents" "${w}"
check "--watch off a terminal does not repeat an unchanged frame" test "$(grep -c -- '─ agents' <<< "${w}")" -eq 1
check "--watch off a terminal has no ANSI escapes" lacks $'\033' "${w}"

# --watch on a terminal: a pty, 30x120, its size read with the real stty. ptywatch.py runs
# `dash --watch <seconds>`, resizes the pty to 30x150 and sends SIGWINCH at <resize-at> seconds (0:
# never), types q at <q-at>, and kills the watch if it is still running 5 seconds later.
cat > "${ROOT}/ptywatch.py" <<'PY'
import fcntl, os, pty, select, signal, struct, sys, termios, time
swarm, out_path, every, resize_at, q_at = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
def size(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
pid, fd = pty.fork()
if pid == 0:
    size(0, 30, 120)
    os.execvp("bash", ["bash", swarm, "dash", "--watch", every])
out, start, resized, typed, status = b"", time.time(), False, False, None
while status is None:
    now = time.time() - start
    if resize_at and not resized and now > resize_at:
        size(fd, 30, 150); os.kill(pid, signal.SIGWINCH); resized = True
    if not typed and now > q_at:
        os.write(fd, b"q"); typed = True
    if now > q_at + 5:
        os.kill(pid, signal.SIGKILL)
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            out += os.read(fd, 65536)
        except OSError:
            pass
    done, st = os.waitpid(pid, os.WNOHANG)
    if done:
        status = st
open(out_path, "wb").write(out)
sys.exit(os.waitstatus_to_exitcode(status))
PY
ptywatch() { # <out> <seconds> <resize-at> <q-at>
  (cd "${P}" && env -u HERDR_ENV PATH="${ROOT}/bin:${REALPATH}" python3 -I "${ROOT}/ptywatch.py" "${SWARM}" "$@")
}
plain() { python3 -c 'import re, sys; print(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", sys.stdin.read().replace("\r", "")))' < "$1"; }
frames() { grep -o -- '┌─ agents' | wc -l | tr -d ' '; }

# Nothing changes for 3.5 seconds at --watch 1: one full frame, the header line rewritten each second.
if ptywatch "${ROOT}/pty.out" 1 0 3.5; then rc=0; else rc=$?; fi
w="$(cat "${ROOT}/pty.out")"; text="$(plain "${ROOT}/pty.out")"
check "--watch on a terminal quits on q" test "${rc}" -eq 0
check "--watch enters the alternate screen and hides the cursor" test "${w:0:14}" == $'\033[?1049h\033[?25l'
check "--watch shows the cursor and leaves the alternate screen on exit" test "${w: -14}" == $'\033[?25h\033[?1049l'
check "--watch homes the cursor and clears below the frame" has $'\033[K\033[J' "${w}"
check "--watch draws an unchanged frame once" test "$(frames <<< "${text}")" -eq 1
check "--watch rewrites the header line while nothing changes" test "$(grep -o $'\033\\[H' <<< "${w}" | wc -l | tr -d ' ')" -ge 3
check "--watch measures the terminal with stty (120 columns)" grep -qE '^└─{118}┘$' <<< "${text}"
# At --watch 30, a resize at 2 seconds redraws at once, at the new width, before the q at 4.
ptywatch "${ROOT}/pty2.out" 30 2 4 || true
text="$(plain "${ROOT}/pty2.out")"
check "--watch redraws at once on SIGWINCH" test "$(frames <<< "${text}")" -eq 2
check "--watch re-measures on SIGWINCH (150 columns, two columns)" grep -qE '─ ladder ─+┐ ┌─ recent ─+┐$' <<< "${text}"
# A render that fails shows its error in the frame, and the watch keeps going.
mkdir -p "${ROOT}/badpy"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\nif [ -n "${DASH_PROJECT:-}" ]; then echo "render boom" >&2; exit 1; fi\nexec "%s" "$@"\n' "$(command -v python3)" > "${ROOT}/badpy/python3"
chmod +x "${ROOT}/badpy/python3"
(cd "${P}" && exec env -u HERDR_ENV PATH="${ROOT}/badpy:${PATH}" bash "${SWARM}" dash --watch 1 > "${ROOT}/badwatch.out" 2>&1) &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q "render boom" "${ROOT}/badwatch.out" && break; sleep 1; done
sleep 2; alive=no
if kill -0 "${pid}" 2>/dev/null; then alive=yes; fi
kill -TERM "${pid}" || true; wait "${pid}" || true
w="$(cat "${ROOT}/badwatch.out")"
check "--watch shows a failed render's error" has "render boom" "${w}"
check "--watch keeps going after a failed render" test "${alive}" == yes
check "--watch refuses a bad interval" bash -c "cd '${P}' && ! bash '${SWARM}' dash --watch 0 2>/dev/null"

check "dash changes nothing under the board or .swarm" test "$(snapshot)" == "${before}"

# --- Stalls. s-three's builder is working, and its story was started 2 hours ago with nothing since:
# no worktree commit, no PR. After the snapshot, since a stall's age changes every minute.
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
printf '%s\tstory\ts-three\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder working 2 hours with no sign of life is stalled?" grep -qE '! s-three .*\[stalled\?\]' <<< "${out}"
check "a stalled builder waits on you" grep -qE 'stalled\? s-three: working 1(19|20|21) min with no commit or PR update' <<< "${out}"
mkdir -p "${P}/.claude/swarm"; echo "stall_minutes = 300" > "${P}/.claude/swarm/config"
out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "stall_minutes sets the threshold" lacks "stalled?" "${out}"
rm "${P}/.claude/swarm/config"
# wait: herdr's wait keeps timing out; the stall check between steps ends it, with exit code 3.
waitfor() { (cd "${P}" || exit 1; HERDR_ENV=1 SWARM_STALL_POLL_MS=1000 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait s-three 5000 2>&1); }
if out="$(waitfor)"; then rc=0; else rc=$?; fi
check "wait returns on a stall with exit code 3" test "${rc}" -eq 3
check "wait says why" grep -qE '^stalled: working 1(19|20|21) min with no commit or PR update$' <<< "${out}"
# A PR updated a minute ago is a sign of life: neither dash nor wait calls it stalled.
ago 1 > "${ROOT}/pr8.updated"
echo "prs: https://github.com/o/r/pull/8" >> "${P}/docs/stories/s-three.md"
out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a recent PR update is not a stall in dash" lacks "stalled?" "${out}"
if out="$(waitfor)"; then rc=0; else rc=$?; fi
check "a recent PR update is not a stall in wait" test "${rc}:$(grep -c stalled <<< "${out}")" == "1:0"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
