#!/usr/bin/env bash
# codex_test.sh — swarm.sh codex-review <base>: codex's review against origin/<base>, with no prompt
# and stdin from /dev/null, its output and exit passed through. One that runs past the limit
# (SWARM_CODEX_SECONDS here) is stopped, TERM then KILL, leaving nothing of it running, and the
# command dies with "codex skipped: timed out", which events.tsv records. With SWARM_STORY, a prompt
# holding the story's touches and Done when replaces --base. codex is a stub on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# BIN is in every stub process's command line and in no other's: the marker pgrep -f looks for.
BIN="${ROOT}/bin"; P="${ROOT}/proj"; LIMIT=2; GRACE=3
trap 'pkill -KILL -f "${BIN}/" 2>/dev/null || true; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
mkdir -p "${BIN}" "${P}/.claude/swarm"; : > "${P}/.claude/swarm/config"
ln -s "$(command -v sleep)" "${BIN}/stubsleep"   # the stub's child, named so pgrep -f can tell it
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
# review — codex-review main from the project, with text on its stdin and SWARM_STORY=$STORY if STORY
# is set (a caller's own SWARM_STORY is dropped), timed: sets out, rc and took
# (seconds). Its output goes through a file, since a stub left running would hold a $(...) open for
# good, and after REVIEW_CAP seconds the stubs are KILLed, so a codex-review that hangs fails the
# timing checks instead of hanging the test.
REVIEW_CAP=20
review() {
  local t0=${SECONDS} spid
  (cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY ${STORY:+"SWARM_STORY=${STORY}"} SWARM_CODEX_SECONDS=${LIMIT} bash "${SWARM}" codex-review main \
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
# gone [seconds] — "yes" once no stub process is left, polled for up to <seconds> (2).
gone() {
  local i
  for ((i = 0; i < ${1:-2} * 5; i++)); do pgrep -f "${BIN}/" >/dev/null || { echo yes; return; }; sleep 0.2; done
  echo "no: $(pgrep -fl "${BIN}/" | tr '\n' ' ')"
}
# markers — codex-review's markers left in the project's state dir, one per line.
markers() { compgen -G "${P}/.swarm/state/codex-review.*" || true; }
last_event() { awk -F'\t' '$2 == "codex-review" { o = $3 "|" $5 } END { print o }' "${P}/.swarm/events.tsv"; }

# --- A codex that sleeps past the limit is stopped, with its child, and named.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 60'
review
check "a codex past the limit fails within 10 s, saying it was skipped" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -le 10 ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: timed out" "${out}")"
check "neither the stub nor its child sleep is left" "yes" "$(gone)"
check "a timed-out codex-review leaves no marker" "" "$(markers)"

# --- One that traps TERM and sleeps on is KILLed after the grace, with whatever it started since.
# Each nap of the limit and the grace adds a little to its length, so the bound has 3 s to spare.
stub "trap 'echo TERM ignored' TERM; while :; do \"\${d}/stubsleep\" 60; done"
review
check "a codex that ignores TERM is stopped within the limit plus the grace" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -le $((LIMIT + GRACE + 3)) ]] && echo yes || echo "no, ${took}s")|$(gone)"
check "events.tsv's codex-review line says it timed out" "main|codex skipped: timed out after 10 min" "$(last_event)"

# --- The grace is real, and never shorter than CODEX_GRACE: a codex that exits on its own 2.5 s
# after TERM is not KILLed.
stub "trap 'sleep 2.5; touch \"\${d}/graceful\"; exit 0' TERM; while :; do \"\${d}/stubsleep\" 60; done"
review
check "a codex that exits within the grace after TERM finishes its trap, unKILLed" "yes|yes" \
  "$(has "codex skipped: timed out" "${out}")|$([[ -e "${BIN}/graceful" ]] && echo yes || echo no)"

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

# --- codex stays in the caller's process group, so a harness that KILLs that group (no trap runs)
# takes codex with it. codex-review runs here as a session and group leader of its own.
rm -f "${BIN}/ready"
(cd "${P}" && exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  env -u SWARM_PROJECT -u HERDR_ENV -u SWARM_STORY SWARM_CODEX_SECONDS=60 bash "${SWARM}" codex-review main < /dev/null > "${ROOT}/out" 2>&1) &
spid=$!; up="$(started)"
kill -KILL -- "-${spid}"; finish "${spid}"
check "a KILL to codex-review's process group leaves neither the stub nor its child" "yes|yes" "${up}|$(gone 2)"

# --- SWARM_SLEEP_SCALE quickens the polling, never the timeout: at 0.01, a codex that takes 0.3 s
# under the 2 s limit still finishes.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 0.3; echo "P2: slow but done"'
SWARM_SLEEP_SCALE=0.01 review
check "at SWARM_SLEEP_SCALE=0.01 a codex inside the limit is not timed out" "exit 0|P2: slow but done" \
  "$([[ ${rc} -eq 0 ]] && echo "exit 0" || echo "exit ${rc}")|${out}"

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

# --- A caller's own SWARM_STORY never reaches the unscoped runs above: review drops it.
SWARM_STORY=s1 review
check "review drops a caller's SWARM_STORY" "[exec][review][--base][origin/main]" "$(cat "${BIN}/args")"

# --- A usage limit is codex's own exit, never taken for a timeout.
stub 'echo "You have hit your usage limit."; exit 1'
review
check "a usage limit exits as codex did, and the log says failed, not skipped" "1|yes|main|failed (exit 1)" \
  "${rc}|$(has "usage limit" "${out}")|$(last_event)"
check "a codex that fails leaves no marker" "" "$(markers)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
