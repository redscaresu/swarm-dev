#!/usr/bin/env bash
# status_section_budget_test.sh — `swarm.sh status` starts its Stacked, Waiting on you and Next sections
# only before the report deadline (report_due, bin/lib/merge.sh). A section due at or past it is not run:
# its heading reads `<section>: skipped (over N s)` with no rows under it, and the last line names it
# after the reads already cut. A section that started in time runs to its end, so the report takes at
# most the deadline plus that section. The board is status_time_limit_test.sh's: child is stacked on p,
# which moved, and p waits on your merge, so with fast stubs every section has rows. The gh stub logs
# each call to $ROOT/gh-calls and answers pr list (stacked_child's read, the only gh call status makes
# here) with an open PR, after sleeping $PR_LIST_SLEEP. herdr lists one agent in this project's pane w:1;
# its pane list sleeps $PANE_SLEEP first (exec: the sleep is the read, so the cut ends it).
# If someone drops a section's report_due check, that section runs past the deadline and prints its
# rows: the skipped-heading checks go red.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/child"; UP="${ROOT}/upstream"
GIT=(git -c user.name=t -c user.email=t@t)
STUB_SLEEP=600   # far past any bound: a status that waits out a read fails its cap
SECTION_SLEEP=3  # the one slow section's read
BOUND=5          # seconds the report may take with that section: the 1 s deadline, the section, slack

# shellcheck disable=SC2034 # merge.sh reads PROJECT_DIR as it loads
PROJECT_DIR="${ROOT}"
# shellcheck source=/dev/null
. "${REPO}/bin/lib/merge.sh"   # within, to cap a status that ignores the deadline

mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
# shellcheck disable=SC2016 # the stub's line is literal: it logs its own arguments when it runs
printf '#!/bin/sh\necho "$1 $2" >> "%s"\n' "${ROOT}/gh-calls" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$1 $2" in "pr list") sleep "${PR_LIST_SLEEP:-0}"; echo '[{"state":"OPEN"}]' ;; esac
exit 0
STUB
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"child","agent_status":"idle","pane_id":"w:1"}]}}' ;;
  "pane list") [ -z "${PANE_SLEEP:-}" ] || exec sleep "${PANE_SLEEP}"
               echo '{"result":{"panes":[{"pane_id":"w:1"}]}}' ;;
  "agent read") echo 'child is working' ;;
esac
STUB
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh" "${ROOT}/bin/claude"
echo "w:1 child" > "${P}/.swarm/state/child"

item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; }
git init -q --bare "${ROOT}/origin.git" && git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" init -q && git -C "${P}" remote add origin "${ROOT}/origin.git"
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init && git -C "${P}" push -q origin HEAD:refs/heads/main
git clone -q "${ROOT}/origin.git" "${UP}"
"${GIT[@]}" -C "${UP}" checkout -q -b story/p && "${GIT[@]}" -C "${UP}" commit -q --allow-empty -m p1
git -C "${UP}" push -q origin story/p
git -C "${P}" fetch -q origin
git -C "${P}" worktree add -q -b story/child "${WT}" origin/story/p
"${GIT[@]}" -C "${UP}" commit -q --allow-empty -m p2 && git -C "${UP}" push -q origin story/p   # p moved
item p 'status: review' 'kind: code' 'prs: https://github.com/o/r/pull/1'
item child 'status: blocked' 'kind: code' 'depends_on: [p]'
printf '2026-10-01T00:00:00Z\tstacked\tchild\tw:9\tok (on p)\n' > "${P}/.swarm/events.tsv"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
holds() {
  if awk -v a="$3" -v b="$4" "BEGIN { exit !($2) }"; then echo "ok   $1"
  else echo "FAIL $1: $2 with a=$3, b=$4"; fails=$((fails + 1)); fi
}
# status <name> <deadline> <env...> — status with SWARM_REPORT_SECONDS=<deadline> and SWARM_REPORT_TIMES=1,
# its stdout in $ROOT/<name>.out and its stderr in $ROOT/<name>.err, cut after an hour past the deadline
# (within) so a status that waits out a stub fails a check rather than the file's time limit. Each
# VAR=value goes to env after the run's own, so HERDR_ENV=0 runs it outside herdr.
status() {
  local name="$1" deadline="$2"; shift 2
  : > "${ROOT}/gh-calls"
  (cd "${P}" && within "$((deadline + 3600))" env HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" \
    SWARM_REPORT_SECONDS="${deadline}" SWARM_REPORT_TIMES=1 "$@" bash "${SWARM}" status \
    > "${ROOT}/${name}.out" 2> "${ROOT}/${name}.err") || true
}
# value <name> <section> — the seconds the run's `time: <section>` line gives.
value() { awk -v s="$2" '$1 == "time:" && $2 == s { print $3 }' "${ROOT}/$1.err"; }

# --- Fast stubs and an hour's deadline: every section's rows, and no skipped line.
status fast 3600
is "fast stubs, an hour's deadline: every section prints its rows and no skipped line" \
"Agents: 0 need a look or are working, 1 idle or done
  (swarm.sh status --all lists them all)

Stacked
  child: merge origin/story/p

Waiting on you
  awaiting your merge: p https://github.com/o/r/pull/1
  1 blocked stories wait on others (swarm.sh status --all lists them)

Next
  gate
  only you can move the board now:
    blocked: child (by p)
    awaiting your merge: p https://github.com/o/r/pull/1" "$(cat "${ROOT}/fast.out")"

# --- herdr's pane list sleeps past a 1 s deadline: it is cut, and every section after Agents is
# skipped, named on the last line after it, with no rows and no gh call.
status cut 1 PANE_SLEEP="${STUB_SLEEP}"
is "pane list cut at 1 s: Stacked, Waiting on you and Next say skipped (over 1 s), with no rows; the last line names the cut read, then them" \
"Agents: herdr gave no pane list, so their states are not available

Stacked: skipped (over 1 s)

Waiting on you: skipped (over 1 s)

Next: skipped (over 1 s)

skipped (over 1 s): herdr pane list, Stacked, Waiting on you, Next" "$(cat "${ROOT}/cut.out")"
is "pane list cut at 1 s: the gh stub logs no call after the cut" "" "$(cat "${ROOT}/gh-calls")"

# --- Stacked's pr list sleeps SECTION_SLEEP s past a 1 s deadline, outside herdr (no Agents reads), so
# Stacked starts in time and runs to its end, its read cut; Waiting on you and Next, due past the
# deadline, are skipped. The report (report_start to its last line, status's `time: total`; swarm.sh's
# startup before it is outside the deadline) ends within the deadline plus that one section.
# Which of Stacked's reads the deadline cuts (git fetch, ls-remote or pr list) depends on the host's
# speed, so the row's words do too: the check is that Stacked ran and gave child's row.
# A host loaded enough to take over 1 s to reach Stacked, or 5 s in all, would fail this on its own
# speed, so the run is tried up to SECTION_TRIES times and the last try's results count. A dropped or
# always-true deadline check fails every try: it changes what status prints, not how long it takes.
SECTION_TRIES=3
section_checks() {
  local last total named=no
  SECTION_GOT="$(sed -n '/^Stacked/,/^$/p' "${ROOT}/section.out" | sed '/^$/d' | awk 'NR == 1 { h = $0 } NR == 2 { r = substr($0, 1, 9) } END { print h "|" r }')"
  SECTION_LATER="$(grep -E '^(Waiting on you|Next)' "${ROOT}/section.out" || true)"
  last="$(tail -n 1 "${ROOT}/section.out")"
  [[ "${last}" != "skipped (over 1 s): "*", Waiting on you, Next" || "${last}" == *Stacked* ]] || named=yes
  SECTION_LAST="${last}"; SECTION_NAMED="${named}"
  total="$(value section total)"; SECTION_TOTAL="${total:-0}"
  [[ "${SECTION_GOT}" == "Stacked|  child: " && "${named}" == yes ]] &&
    awk -v a="${SECTION_TOTAL}" -v b="${BOUND}" 'BEGIN { exit !(a > 0 && a < b) }'
}
for ((try = 1; try <= SECTION_TRIES; try++)); do
  status section 1 HERDR_ENV=0 PR_LIST_SLEEP="${SECTION_SLEEP}"
  if section_checks; then break; fi
  echo "note: a slow Stacked, try ${try} of ${SECTION_TRIES}: Stacked '${SECTION_GOT}', total ${SECTION_TOTAL} s"
done
is "a slow Stacked: it started in time, so it prints its heading and child's row" "Stacked|  child: " "${SECTION_GOT}"
is "a slow Stacked: Waiting on you and Next, due past the deadline, are skipped" \
"Waiting on you: skipped (over 1 s)
Next: skipped (over 1 s)" "${SECTION_LATER}"
is "a slow Stacked: the last line names the cut reads, then Waiting on you and Next, not Stacked (got: ${SECTION_LAST})" yes "${SECTION_NAMED}"
holds "a slow Stacked: the report ends within the 1 s deadline plus that one section (under ${BOUND} s)" \
  "a > 0 && a < b" "${SECTION_TOTAL}" "${BOUND}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
