#!/usr/bin/env bash
# watch_opened_test.sh — a conductor's watch (--epic or --backlog) returns once when a story PR of its
# own opens, `<repo> #<n> <branch> opened`, except a lead story's, a fix-main story's or one whose head
# a review agent has reviewed or started on; the lead's bare watch never says it. gh is a stub on PATH
# answering from prlist.json; every check run is still running, so a watch with nothing to say polls on.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
echo "$*" >> "$F/calls"
q=""; for a in "$@"; do [ "$p" = -q ] && q="$a"; p="$a"; done
case "$1 $2" in
  "repo view") echo o/svc; exit 0 ;;
esac
case "$2 $3" in
  "--paginate repos/o/svc/pulls?"*) out="$(jq -r "$q" "$F/prlist.json")"; printf '%s\n' "${out}"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/pulls/*) echo MERGEABLE ;;
  repos/o/svc/commits/*/check-runs*) echo '1 1' ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/gh"

# Epic e has story a, the epic other has b, and c has no epic; all three are built in svc. b's PR comes
# first, so a watch of e that does not skip it says it first. d (a lead story of e), r (of e) and the
# fix-main story's PRs are added to the list later, each for its own check.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${ROOT}/repos"
echo "repos_dir = ${ROOT}/repos" > "${p}/.claude/swarm/config"
git init -q "${ROOT}/repos/svc" && git -C "${ROOT}/repos/svc" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/other.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e\nrepo: svc\n---\n' > "${p}/docs/stories/a.md"
printf -- '---\nstatus: ready\nkind: code\nepic: other\nrepo: svc\n---\n' > "${p}/docs/stories/b.md"
printf -- '---\nstatus: ready\nkind: code\nrepo: svc\n---\n' > "${p}/docs/stories/c.md"
printf -- '---\nstatus: ready\nkind: lead\nepic: e\nrepo: svc\n---\n' > "${p}/docs/stories/d.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e\nrepo: svc\n---\n' > "${p}/docs/stories/r.md"
printf -- '---\nstatus: review\nkind: code\nrepo: svc\n---\n' > "${p}/docs/stories/fix-main-abcdef1.md"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# prs <branch>... — the open PRs: story/b, story/a and story/c, then one per <branch>, numbered on from 4.
prs() {
  local n=1 br rows=""
  for br in story/b story/a story/c "$@"; do
    rows+="${rows:+, }{\"number\": ${n}, \"head\": {\"ref\": \"${br}\", \"sha\": \"head${n}\"}, \"updated_at\": \"${now}\"}" # vacuous-test: ok, one row of the list
    n=$((n + 1))
  done
  echo "[${rows}]" > "${ROOT}/prlist.json"
}
prs
seen="${p}/.swarm/state/watch-seen"; EV="${p}/.swarm/events.tsv"
# opened_events — the events.tsv pr-opened lines' target and outcome, one per line.
opened_events() { awk -F'\t' '$2 == "pr-opened" { print $3, $5 }' "${EV}" 2>/dev/null || true; }
# unsee <n> — drop watch-seen's opened line for PR #<n>, which only a wrong earlier watch wrote, so the
# check after it stands alone.
unsee() { { grep -vx "opened o/svc#$1" "${seen}" || true; } > "${ROOT}/seen"; cp "${ROOT}/seen" "${seen}"; }

# watch_for <watch args...> — what watch printed (stdout and stderr), a |, then how it ended: its exit
# code, "polling" once it has listed the PRs three times (so two whole polls said nothing), or "timeout"
# when neither comes within WATCH_SECS, swarm.sh's start included. It polls every 0.12 s; calls then holds
# only this run's gh calls. A watch still running is stopped, then its children (its sleep); what it
# printed is read before that, as a pipe the stop cuts can print an error (head: Broken pipe) after it.
WATCH_SECS=60
watch_for() {
  local pid i end=timeout kids k out
  : > "${ROOT}/calls"; rm -f "${ROOT}/watch.out"
  (cd "${p}" && exec env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0.002 PATH="${ROOT}/bin:${PATH}" \
    bash "${SWARM}" watch "$@" > "${ROOT}/watch.out" 2>&1) &
  pid=$!
  for ((i = 0; i < WATCH_SECS * 5; i++)); do
    if ! kill -0 "${pid}" 2>/dev/null; then { wait "${pid}"; } 2>/dev/null && end=0 || end=$?; break; fi
    if [[ $(grep -c 'pulls?state=open' "${ROOT}/calls" || true) -ge 3 ]]; then end=polling; break; fi
    sleep 0.2
  done
  out="$(cat "${ROOT}/watch.out")"
  if [[ "${end}" == polling || "${end}" == timeout ]]; then
    kids="$(pgrep -P "${pid}" || true)"; kill "${pid}" 2>/dev/null || true; { wait "${pid}"; } 2>/dev/null || true
    for k in ${kids}; do kill "${k}" 2>/dev/null || true; done
  fi
  printf '%s|%s' "${out}" "${end}"
}

check "watch --epic says its own story's PR opened, skipping another epic's, and exits 0" "o/svc #2 story/a opened|0" "$(watch_for --epic e)"
check "watch --epic reads nothing of the PR it says opened past the list" "0" "$(grep -cE 'pulls/2|commits/head2' "${ROOT}/calls" || true)"
check "watch --epic records the PR as opened in watch-seen" "opened o/svc#2" "$(grep '^opened ' "${seen}")"
check "watch --epic logs one pr-opened line with the slug and the PR's URL" "a https://github.com/o/svc/pull/2" "$(opened_events)"
check "the stall rule's sign_time skips the pr-opened line" "None" "$(SWARM_LIB="${SWARM%/*}/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from stall import sign_time
print(sign_time(sys.argv[1].split("\t")))' "$(tail -1 "${EV}")")"
check "a second watch --epic polls on, saying nothing: not its own PR again, nor another epic's" "|polling" "$(watch_for --epic e)"
check "a second watch --epic logs no second pr-opened line" "a https://github.com/o/svc/pull/2" "$(opened_events)"
check "watch --backlog says a no-epic story's PR opened, and exits 0" "o/svc #3 story/c opened|0" "$(watch_for --backlog)"
check "a second watch --backlog polls on, not saying it again" "|polling" "$(watch_for --backlog)"

# A lead story's PR is the lead's: its epic's watch never says it opened.
prs story/d
check "watch --epic never says a lead story's PR opened" "|polling" "$(watch_for --epic e)"
# A fix-main story is in every conductor's scope, and the backlog's: no watch says its PR opened.
prs story/d story/fix-main-abcdef1
check "watch --epic never says a fix-main story's PR opened" "|polling" "$(watch_for --epic e)"
# A watch --epic that wrongly said it opened recorded it: drop that line, so this check stands alone.
unsee 5
check "watch --backlog never says a fix-main story's PR opened" "|polling" "$(watch_for --backlog)"
# A PR whose head (head6) a review agent reviewed (its findings file's head: line) or started on (the
# head on record) was reviewed before this watch looked: it is not said opened.
prs story/d story/fix-main-abcdef1 story/r
mkdir -p "${p}/.swarm/reviews"; printf 'head: head6\n## Findings\nNone.\n' > "${p}/.swarm/reviews/r.md"
check "watch --epic does not say a PR opened whose head has a findings file" "|polling" "$(watch_for --epic e)"
rm -f "${p}/.swarm/reviews/r.md"; echo head6 > "${p}/.swarm/reviews/r.head"; unsee 6
check "watch --epic does not say a PR opened whose head a review agent started on" "|polling" "$(watch_for --epic e)"
# A rebuilt story: its old PR's review (head5old, file and head on record, never removed) stays, and its
# new PR, at head6, is said opened.
printf 'head: head5old\n## Findings\nNone.\n' > "${p}/.swarm/reviews/r.md"; echo head5old > "${p}/.swarm/reviews/r.head"; unsee 6
check "watch --epic says a rebuilt story's new PR opened, its old PR's review left in place" "o/svc #6 story/r opened|0" "$(watch_for --epic e)"

# The lead's bare watch leaves the review starts to the conductors: no opened line, none recorded,
# none logged.
rm -f "${seen}"; logged="$(opened_events)"
check "the bare watch polls on, saying no PR opened and recording none" "|polling|0" \
  "$(watch_for)|$(grep -c '^opened ' "${seen}" || true)"
check "the bare watch logs no pr-opened line" "${logged}" "$(opened_events)"

# An events.tsv watch cannot write (a directory in its place): it says the PR opened and exits 0 as before.
mv "${EV}" "${ROOT}/events.keep"; mkdir "${EV}"
check "watch --epic with events.tsv unwritable says the PR opened and exits 0" "o/svc #2 story/a opened|0" "$(watch_for --epic e)"
rmdir "${EV}"; mv "${ROOT}/events.keep" "${EV}"

if [[ ${fails} -gt 0 ]]; then echo "${fails} check(s) failed"; exit 1; fi
echo "all passed"
