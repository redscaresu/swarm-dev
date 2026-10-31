#!/usr/bin/env bash
# codex_test.sh — swarm.sh codex-review <base>: codex's review against origin/<base>, with no prompt
# and stdin from /dev/null, its output and exit passed through. One that runs past the limit
# (SWARM_CODEX_SECONDS here) is stopped, TERM then KILL, leaving nothing of it running, and the
# command dies with "codex skipped: timed out", which events.tsv records, with a reap line naming
# codex-<base or story>, and for a story, its slug= and the role of the agent running it (SWARM_AGENT)
# in the outcome's tail; one that finishes writes none. With SWARM_STORY, a prompt
# holding the story's touches and Done when replaces --base, and with SWARM_PR it ends with the
# findings declined on that PR before. codex is a stub on PATH.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# BIN is in every stub process's command line and in no other's: the marker pgrep -f looks for.
BIN="${ROOT}/bin"; P="${ROOT}/proj"; LIMIT=2; GRACE=3
trap 'pkill -KILL -f "${BIN}/" 2>/dev/null || true; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
mkdir -p "${BIN}" "${P}/.claude/swarm"; : > "${P}/.claude/swarm/config"
# The stub's child: one process with its own path in its command line, so pgrep -f can tell it. Not a
# symlink to sleep, which uutils coreutils (ubuntu 26.04) refuse to run under another name.
# shellcheck disable=SC2016 # the stub's own $1 and $0, expanded when it runs
printf '#!/bin/sh\nexec perl -e "select undef, undef, undef, shift" "$1" "$0"\n' > "${BIN}/stubsleep"; chmod +x "${BIN}/stubsleep"
# The same under another name, for a child a case leaves running on purpose, so left can tell it.
cp "${BIN}/stubsleep" "${BIN}/orphansleep"
# stubchain <n> — a chain of n sh processes, each waiting on the next, and a perl sleeping at its end,
# which touches chained beside it as it starts (printf makes the %% in ${0%%/*} one %: its dirname).
# shellcheck disable=SC2016 # the chain's own $1 and $0
printf '#!/bin/sh\nif [ "$1" -gt 0 ]; then "$0" $(($1 - 1)); else touch "${0%%/*}/chained"; exec perl -e "select undef, undef, undef, 60" "$0"; fi\n' > "${BIN}/stubchain"
chmod +x "${BIN}/stubchain"
export PATH="${BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

# stub <body> — the codex on PATH: it records its args and its stdin, then runs <body>.
# shellcheck disable=SC2016 # the stub's own variables, expanded when it runs
stub() {
  printf '%s\n' '#!/usr/bin/env bash' 'd="$(dirname "$0")"' 'printf "[%s]" "$@" > "${d}/args"' 'cat > "${d}/stdin"' "$1" > "${BIN}/codex"
  chmod +x "${BIN}/codex"
}
# review — codex-review main from the project, with text on its stdin, SWARM_STORY=$STORY if STORY
# is set, SWARM_AGENT=$AGENT if AGENT is and SWARM_PR=$PR if PR is (a caller's own of any is dropped), timed: sets out, rc and took
# (seconds). Its output goes through a file, since a stub left running would hold a $(...) open for
# good, and after REVIEW_CAP seconds the stubs are KILLed, so a codex-review that hangs fails the
# timing checks instead of hanging the test.
REVIEW_CAP=20
review() {
  local t0=${SECONDS} spid
  (cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY -u SWARM_AGENT -u SWARM_PR ${STORY:+"SWARM_STORY=${STORY}"} ${AGENT:+"SWARM_AGENT=${AGENT}"} ${PR:+"SWARM_PR=${PR}"} SWARM_CODEX_SECONDS="${LIMIT}" bash "${SWARM}" codex-review main \
    <<< "typed at the prompt" > "${ROOT}/out" 2>&1) &
  spid=$!; finish "${spid}"
  took=$((SECONDS - t0)); out="$(cat "${ROOT}/out")"
}
# finish <pid> — wait for a codex-review started in the background: rc is its exit. After REVIEW_CAP
# seconds the stubs are KILLed. Stderr off, so the test prints no "Terminated" notice for it.
finish() {
  local i
  for ((i = 0; i < REVIEW_CAP * 5; i++)); do kill -0 "$1" || break; sleep 0.2; done
  kill -0 "$1" && { pkill -KILL -f "${BIN}/" || true; }
  rc=0; wait "$1" || rc=$?
} 2>/dev/null
# started — "yes" once the stub has set its TERM trap and written ready, polled for up to 10 s.
started() {
  local i
  for ((i = 0; i < 50; i++)); do [[ -e "${BIN}/ready" ]] && { echo yes; return; }; sleep 0.2; done
  echo "no stub started"
}
# gone [seconds] [pattern] — "yes" once no process matching <pattern> (${BIN}/: any stub process) is
# left, polled for up to <seconds> (2). A pgrep that cannot read the process list (exit 2 or 3, as in a
# sandbox) is a failure, never "none left".
gone() {
  local i rc
  for ((i = 0; i < ${1:-2} * 5; i++)); do
    rc=0; pgrep -f "${2:-${BIN}/}" >/dev/null || rc=$?
    case "${rc}" in 0) sleep 0.2 ;; 1) echo yes; return ;; *) echo "no: pgrep failed (exit ${rc})"; return ;; esac
  done
  echo "no: $(pgrep -fl "${2:-${BIN}/}" | tr '\n' ' ')"
}
# left <case> [pattern] — each case's last check: no stub process (or none matching <pattern>, where
# the case leaves one on purpose) outlived it. Then every stub process is KILLed, so the next case
# starts clean and a failure is the case's that left it; with <pattern>, that the KILL took the
# case's own orphan too.
left() {
  check "$1 leaves no stub process${2:+ but its orphan}" "yes" "$(gone 2 "${2:-}")"
  pkill -KILL -f "${BIN}/" 2>/dev/null || true
  [[ -z "${2:-}" ]] || check "$1 ends with its orphan KILLed" "yes" "$(gone)"
}
# markers — codex-review's markers left in the project's state dir, one per line.
markers() { compgen -G "${P}/.swarm/state/codex-review.*" || true; }
# reaps [fields] — the reap lines in the project's events.tsv, "target|outcome" (events_outcome's,
# without the tail), one per line, or with fields, each one's fields() as sorted k=v words; nothing
# before any.
reaps() {
  python3 -c 'import os, sys; sys.path.insert(0, sys.argv[1])
from events_outcome import fields, outcome
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[2])] if os.path.exists(sys.argv[2]) else []
for r in (r for r in rows if r[1] == "reap"):
    print(" ".join("%s=%s" % kv for kv in sorted(fields(r).items())) if sys.argv[3] else r[2] + "|" + outcome(r))' \
    "${SWARM%/*}/lib" "${P}/.swarm/events.tsv" "${1:-}" | no_version
}
last_event() { awk -F'\t' '$2 == "codex-review" { o = $3 "|" $5 } END { print o }' "${P}/.swarm/events.tsv" | no_version; }

# --- A codex that sleeps past the limit is stopped, with its child, and named.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 60'
review
check "a codex past the limit fails within 10 s, saying it was skipped" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -le 10 ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: timed out" "${out}")"
check "a codex past the limit writes exactly one reap line, naming codex-<base> and the timeout" "codex-main|timed out after 10 min" "$(reaps)"
check "neither the stub nor its child sleep is left" "yes" "$(gone)"
check "a timed-out codex-review leaves no marker" "" "$(markers)"
left "the timeout case"

# --- One that traps TERM and sleeps on is KILLed after the grace, with whatever it started since:
# never before the limit and the default grace (3 s, GRACE here), and with 3 s to spare after, since
# each nap of the limit and the grace adds a little to its length.
stub "trap 'echo TERM ignored' TERM; while :; do \"\${d}/stubsleep\" 60; done"
review
check "a codex that ignores TERM is stopped after the limit plus the default grace, within 3 s more" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -ge $((LIMIT + GRACE)) && ${took} -le $((LIMIT + GRACE + 3)) ]] && echo yes || echo "no, ${took}s")|$(gone)"
check "events.tsv's codex-review line says it timed out" "main|codex skipped: timed out after 10 min" "$(last_event)"
left "the TERM-trapping timeout case"

# --- One that traps TERM and starts a child every few ms is KILLed with every child it started: its
# tree is frozen before the KILL, so it cannot start one behind the read, as it could behind a KILL to
# the children first (reading its children outlasts its next fork). Each child exits after 0.2 s,
# which keeps the tree small, unless its parent is no longer the stub (given as $$, so a child that
# starts after the stub is KILLed counts too): one the KILL missed sleeps on, to be seen.
# shellcheck disable=SC2016 # the stub's $$ and $0
stub 'trap : TERM; while :; do perl -e '\''select undef, undef, undef, 0.2; sleep 60 if getppid != shift'\'' "$$" "$0" & sleep 0.02; done'
review
check "a codex that keeps starting children is stopped within the limit plus the grace" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -le $((LIMIT + GRACE + 3)) ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: timed out" "${out}")"
left "the forking case"

# --- One whose TERM trap starts a chain 10 deep in the grace is KILLed to the chain's end: the freeze
# walks every level of the tree, and the chain's deepest processes are not left as orphans.
stub "trap '\"\${d}/stubchain\" 10 &' TERM; while :; do \"\${d}/stubsleep\" 60; done"
rm -f "${BIN}/chained"
review
check "a codex whose TERM trap starts a deep chain times out, the chain built to its end first" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$(has "codex skipped: timed out" "${out}")|$([[ -e "${BIN}/chained" ]] && echo yes || echo "no chained")"
left "the deep chain case"

# --- The grace is real: with a grace of 6 s, a codex that exits on its own 3 s after TERM is not
# KILLed. The other 3 s are for a loaded machine, where the trap starts late; a grace cut under 3 s
# fails it.
stub "trap 'sleep 3; touch \"\${d}/graceful\"; exit 0' TERM; while :; do \"\${d}/stubsleep\" 60; done"
SWARM_CODEX_GRACE=6 review
check "a codex that exits within the grace after TERM finishes its trap, unKILLed" "yes|yes" \
  "$(has "codex skipped: timed out" "${out}")|$([[ -e "${BIN}/graceful" ]] && echo yes || echo no)"
left "the grace case"

# --- An interrupted codex-review stops codex as its timeout does (TERM, the grace, then KILL), and
# exits only once it has.
stub "trap 'echo TERM ignored' TERM; touch \"\${d}/ready\"; while :; do \"\${d}/stubsleep\" 60; done"
rm -f "${BIN}/ready"
(cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY SWARM_CODEX_SECONDS=60 bash "${SWARM}" codex-review main < /dev/null > "${ROOT}/out" 2>&1) &
spid=$!; up="$(started)"
check "while codex runs, its marker holds the base and cwd" "main	${P}" "$(cut -f2- "${P}/.swarm/state/codex-review.${spid}" 2>&1)"
sleep 1; kill -TERM "${spid}"; finish "${spid}"
check "an interrupted codex-review leaves no marker" "" "$(markers)"
check "codex-review sent TERM exits with neither a TERM-trapping stub nor its child left" "yes|yes" "${up}|$(gone 1)"
check "events.tsv's codex-review line says it was interrupted" "main|interrupted" "$(last_event)"
left "the interrupt case"

# --- codex stays in the caller's process group, so a harness that KILLs that group (no trap runs)
# takes codex with it. codex-review runs here as a session and group leader of its own.
rm -f "${BIN}/ready"
(cd "${P}" && exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY SWARM_CODEX_SECONDS=60 bash "${SWARM}" codex-review main < /dev/null > "${ROOT}/out" 2>&1) &
spid=$!; up="$(started)"
# As a careful harness does, it STOPs the group until a read finds what the last did, then KILLs it:
# XNU's killpg can miss a member forked while it walks the group, as the looping stub's next child is.
was=""
for ((i = 0; i < 10; i++)); do
  kill -STOP -- "-${spid}" 2>/dev/null || true
  now="$(pgrep -g "${spid}" || true)"; [[ "${now}" != "${was}" ]] || break; was="${now}"
done
kill -KILL -- "-${spid}"; finish "${spid}"
check "a KILL to codex-review's process group, STOPped first (macOS's KILL alone can miss a fork), leaves neither the stub nor its child" "yes|yes" "${up}|$(gone 2)"
left "the group KILL case"

# --- SWARM_SLEEP_SCALE quickens the polling, never the timeout: at 0.01, a codex that takes 0.3 s
# under the 2 s limit still finishes.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 0.3; echo "P2: slow but done"'
SWARM_SLEEP_SCALE=0.01 review
check "at SWARM_SLEEP_SCALE=0.01 a codex inside the limit is not timed out" "exit 0|P2: slow but done" \
  "$([[ ${rc} -eq 0 ]] && echo "exit 0" || echo "exit ${rc}")|${out}"
left "the SWARM_SLEEP_SCALE case"

# --- SWARM_CODEX_SECONDS and SWARM_CODEX_GRACE that are no whole number of seconds are ignored, never
# taken into arithmetic that fails.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 0.3; echo "P2: still reviewed"'
LIMIT=2.5 SWARM_CODEX_GRACE=2.5 review
check "a limit or grace of 2.5 is ignored, and codex still runs" "exit 0|P2: still reviewed" \
  "$([[ ${rc} -eq 0 ]] && echo "exit 0" || echo "exit ${rc}")|${out}"
left "the bad override case"

# --- A codex that finishes: its findings and exit come through, run with exactly these args. A
# marker left by a run that was KILLed (its pid dead) goes at the start.
stub 'echo "P1: x.sh:3 drops the error"; exit 0'
sh -c 'exit 0' & dead=$!; wait "${dead}" || true
printf '1\tmain\t/x\n' > "${P}/.swarm/state/codex-review.${dead}"
# A half-rewritten marker (retire writes every state file through <file>.tmp) is no pid's: kept.
printf '1\tmain\t/x\n' > "${P}/.swarm/state/codex-review.123.tmp"
review
check "a run removes a dead pid's marker, leaves none of its own and keeps a .tmp" "${P}/.swarm/state/codex-review.123.tmp" "$(markers)"
rm "${P}/.swarm/state/codex-review.123.tmp"
check "a codex that finishes passes its exit and findings through" "0|yes" "${rc}|$(has "P1: x.sh:3 drops the error" "${out}")"
check "codex runs as exec review --base origin/main, with no prompt" "[exec][review][--base][origin/main]" "$(cat "${BIN}/args")"
check "codex reads /dev/null, never the caller's stdin" "" "$(cat "${BIN}/stdin")"
left "a finished codex case"

# --- With SWARM_STORY, codex gets a prompt holding the story's touches, Done when and From review,
# and no --base. A markdown heading ends the Done when items, as a bold line does.
mkdir -p "${P}/docs/stories"
printf '%s\n' '---' 'kind: code' 'touches: [bin/a.sh:fn_one, tests/a_test.sh]' '---' '' '# S1' '' \
  '**Done when:**' '- the first item holds' '- the second item holds' '## Notes' 'prose under a heading' '' \
  '**From review:**' '- the review item holds' > "${P}/docs/stories/s1.md"
stub 'exit 0'
STORY=s1 review
args="$(cat "${BIN}/args")"
check "with SWARM_STORY, codex runs as exec review <prompt>, with no --base" "0|[exec][review][|no" \
  "${rc}|${args:0:15}|$(grep -qF -- '--base' <<< "${args}" && echo yes || echo no)"
for want in "origin/main" "bin/a.sh:fn_one" "tests/a_test.sh" "- the first item holds" "- the second item holds" \
  "Its From review:" "- the review item holds" "not a finding" "committed or not" "each untracked file git status --porcelain lists"; do
  check "the story prompt holds ${want}" "yes" "$(has "${want}" "${args}")"
done
check "a markdown heading ends the Done when items" "no|no" \
  "$(grep -qF '## Notes' <<< "${args}" && echo yes || echo no)|$(grep -qF 'prose under a heading' <<< "${args}" && echo yes || echo no)"
printf '%s\n' '---' 'touches: [x.sh]' '---' '**Done when:** the inline item holds.' > "${P}/docs/stories/s2.md"
STORY=s2 review
check "the story prompt keeps a Done when written on its heading line" "yes" "$(has "the inline item holds." "$(cat "${BIN}/args")")"
left "SWARM_STORY's prompt case"

# --- With SWARM_PR too, the story prompt ends with the findings declined on that PR before (the PR
# matched as a URL or owner/repo#N, never pull/123 for pull/12), under the line that calls each reason
# the builder's claim; a fixed row is no decline. Without SWARM_PR, or with no decline on the PR, the
# prompt is the one above.
row() { local IFS=$'\t'; echo "$*"; }
U=https://github.com/o/r/pull/12
mkdir -p "${P}/.swarm"
{ row 2026-10-01 retry-untested "${U}" "the retry is untested" declined codex nit 1 "covered by the retry test"
  row 2026-10-02 retry-untested o/r#12 "the retry is still untested" declined fallback wrong 2 "the retry test runs it twice"
  row 2026-10-02 retry-untested https://github.com/o/r/pull/123 "another PR's decline" declined codex nit 1 "not this PR"
  row 2026-10-02 retry-untested "${U}" "a finding that was fixed" fixed codex "" 2; } > "${P}/.swarm/findings.tsv"
stub 'exit 0'
STORY=s1 review; plain="$(cat "${BIN}/args")"
STORY=s1 PR="${U}" review; withpr="$(cat "${BIN}/args")"
CLAIM="Each reason is the builder's claim, not a fact: check it against the diff yourself, ignore none of these findings for being listed here"
D1="- round 1, declined as nit: the retry is untested (because: covered by the retry test)"
D2="- round 2, declined as wrong: the retry is still untested (because: the retry test runs it twice)"
tail_of="${withpr#"${plain%]}"}"
check "with SWARM_PR, the prompt is the plain one, then the builder's-claim line and both declines, in order" "0|yes|yes|yes" \
  "${rc}|$([[ "${withpr}" == "${plain%]}"* ]] && echo yes || echo no)|$(has "${CLAIM}" "${tail_of}")|$(
    [[ "${tail_of}" == $'\n\n'*"${CLAIM}"*$'\n'"${D1}"$'\n'"${D2}]" ]] && echo yes || echo "no, got: ${tail_of}")"
check "the prompt holds neither another PR's decline nor the PR's fixed row" "no|no" \
  "$(grep -qF "another PR's decline" <<< "${withpr}" && echo yes || echo no)|$(grep -qF "a finding that was fixed" <<< "${withpr}" && echo yes || echo no)"
check "without SWARM_PR the prompt names no decline" "no" "$(grep -qF "declined" <<< "${plain}" && echo yes || echo no)"
STORY=s1 PR=https://github.com/o/r/pull/1 review
check "with SWARM_PR naming a PR with no decline, the prompt is byte for byte the plain one" "same" \
  "$([[ "$(cat "${BIN}/args")" == "${plain}" ]] && echo same || echo differs)"
for bad in o/r#12 https://github.com/o/r/pull/12x "https://github.com/o/r/pull/12 x" https://example.com/o/r/pull/12; do
  rm -f "${BIN}/args"
  STORY=s1 PR="${bad}" review
  check "SWARM_PR='${bad}' is refused, and codex never runs" "fails|yes|no" \
    "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$(has "SWARM_PR: not a PR URL" "${out}")|$([[ -e "${BIN}/args" ]] && echo yes || echo no)"
done
SWARM_PR=bad review
check "review drops a caller's SWARM_PR" "0|[exec][review][--base][origin/main]" "${rc}|$(cat "${BIN}/args")"
left "SWARM_PR's declines case"

# --- A story's review that times out reaps codex-<story>, one line more; a codex that finishes writes none.
# An unscoped review by a conductor that times out carries its role= and no slug=.
nreaps() { reaps | wc -l | tr -d ' '; }
n0="$(nreaps)"
stub 'exit 0'
STORY=s1 review
check "a codex that finishes writes no reap line" "${n0}" "$(nreaps)"
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 60'
mkdir -p "${P}/.swarm"; printf '2026-10-30\tcode\ts1\tclaude\topus\thigh\t-\n' >> "${P}/.swarm/agents.tsv"
STORY=s1 AGENT=s1 review
check "a story's codex past the limit adds one reap line, naming codex-<story>" "$((n0 + 1))|codex-s1|timed out after 10 min" "$(nreaps)|$(reaps | tail -n 1)"
check "its reap line carries the story's slug and the role of the agent that ran it" "role=code slug=s1" "$(reaps fields | tail -n 1)"
check "a base's reap line, with no story or agent, carries neither" "" "$(reaps fields | head -n 1)"
printf '2026-10-30\tconduct\tconduct-e1\tclaude\topus\thigh\t-\n' >> "${P}/.swarm/agents.tsv"
AGENT=conduct-e1 review
check "with no SWARM_STORY, a reap line carries the agent's role and no slug read from its name" "role=conduct" "$(reaps fields | tail -n 1)"
left "the story timeout case"

# --- A SWARM_STORY that names no story, names a story with no Done when item, or is no slug fails,
# naming why, before codex starts.
printf '%s\n' '---' 'touches: [x.sh]' '---' '**Done when:**' '' '**From review:**' '- a review item' > "${P}/docs/stories/s3.md"
mkdir -p "${P}/docs/epics"; cp "${P}/docs/stories/s1.md" "${P}/docs/epics/e1.md"
for c in "missing|${P}/docs/stories/missing.md" "s3|has no **Done when** with an item" "../epics/e1|bad slug '../epics/e1'"; do
  rm -f "${BIN}/args"
  STORY="${c%%|*}" review
  check "SWARM_STORY=${c%%|*} fails naming why, and codex never runs" "fails|yes|no" \
    "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$(has "${c#*|}" "${out}")|$([[ -e "${BIN}/args" ]] && echo yes || echo no)"
done
left "a bad SWARM_STORY case"

# --- A caller's own SWARM_STORY never reaches the unscoped runs above: review drops it.
SWARM_STORY=s1 review
check "review drops a caller's SWARM_STORY" "[exec][review][--base][origin/main]" "$(cat "${BIN}/args")"
left "a caller's SWARM_STORY case"

# --- A usage limit is codex's own exit, never taken for a timeout.
stub 'echo "You have hit your usage limit."; exit 1'
review
check "a usage limit exits as codex did, and the log says failed, not skipped" "1|yes|main|failed (exit 1)" \
  "${rc}|$(has "usage limit" "${out}")|$(last_event)"
check "a codex that fails leaves no marker" "" "$(markers)"
left "the usage limit case"

# --- A child of codex left holding its output does not hold codex-review: tee gets the grace after
# codex exits, then is stopped, and what codex printed comes through.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/orphansleep" 60 & echo "P2: y.sh:1 leaks"; exit 0'
review
check "a codex whose child keeps its output open returns within the grace, its findings through" "0|yes|yes" \
  "${rc}|$([[ ${took} -le $((GRACE + 3)) ]] && echo yes || echo "no, ${took}s")|$(has "P2: y.sh:1 leaks" "${out}")"
# Its orphansleep is the case's own orphan, left on purpose: every other stub process must be gone.
left "a child holding the output case" "${BIN}/(codex|stubsleep)"

# --- On the timeout too, tee is stopped: a grandchild of codex that left its tree (so stop_codex
# misses it) and holds codex's output cannot keep codex-review's stdout open. Read through a pipe,
# as a caller's $(...) would.
# shellcheck disable=SC2016 # the stub's variable
stub '( "${d}/orphansleep" 60 & ); "${d}/stubsleep" 60'
t0=${SECONDS}
(cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY SWARM_CODEX_SECONDS="${LIMIT}" bash "${SWARM}" codex-review main 2>&1 \
  < /dev/null | cat > "${ROOT}/out") &
spid=$!; finish "${spid}"
check "a timed-out codex whose grandchild holds its output still ends codex-review's stdout within the grace" "yes|yes" \
  "$([[ $((SECONDS - t0)) -le $((LIMIT + GRACE + 3)) ]] && echo yes || echo "no, $((SECONDS - t0))s")|$(has "codex skipped: timed out" "$(cat "${ROOT}/out")")"
# Its grandchild orphansleep left the tree on purpose: the stub and its stubsleep, still in the tree
# stop_codex stops, must be gone.
left "a grandchild holding the output case" "${BIN}/(codex|stubsleep)"

# --- codex's log and fifo are in a directory of the run's own, mode 700, gone once it ends.
mkdir -p "${ROOT}/tmp"
# shellcheck disable=SC2016 # the stub's variable
stub 'ls -ld "${TMPDIR}"/swarm-codex.* | cut -c1-10; ls "${TMPDIR}"/swarm-codex.*/ | tr "\n" " "; exit 0'
TMPDIR="${ROOT}/tmp" review
check "codex's log and fifo are in a private directory (drwx------), removed when the run ends" "yes|yes|" \
  "$(has "drwx------" "${out}")|$(has "fifo log" "${out}")|$(compgen -G "${ROOT}/tmp/swarm-codex.*" || true)"
left "the private directory case"

# --- A run that fails before codex starts (here mktemp, with no TMPDIR to write in) leaves no marker.
stub 'exit 0'
(cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY TMPDIR="${ROOT}/no-such-dir" bash "${SWARM}" codex-review main \
  < /dev/null > "${ROOT}/out" 2>&1) &
spid=$!; finish "${spid}"
check "a codex-review whose temp file cannot be made fails and leaves no marker" "fails|" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$(markers)"
left "a failed mktemp case"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
