#!/usr/bin/env bash
# no_agent_test.sh — wait --lead's no-agent: line: a started story that no agent works on and that is not
# the user's to move wakes the lead, naming its exit, and every false case stays silent. Each poll is
# one `swarm.sh wait --lead 0`, which reads the queue exactly once. herdr is a stub listing the agents in
# ${FX}/agents, failing while ${FX}/list.fail exists; gh is a stub answering a pending head. Both log each
# call. A process that answers for a story (a tell, a wait-pr, a merge) is a fake swarm.sh that sleeps.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
busy_pid=""
other_pid=""
trap 'unbusy; [[ -z "${other_pid}" ]] || kill "${other_pid}" 2>/dev/null || true; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111
# A URL no other test's processes name: a merge or wait-pr on it anywhere on the machine silences a case.
URL=https://github.com/na-owner/na-repo/pull/41; URL2=https://github.com/na-owner/na-repo/pull/42
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin" "${ROOT}/fake" "${FX}"
git -C "${P}" init -q

printf '#!/bin/sh\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/herdr.log" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
echo "$*" >> "${LOG}"
case "$1 $2" in
  "agent list") [ ! -e "${FX}/list.fail" ] || exit 1
                [ ! -e "${FX}/list.hang" ] || sleep 90
                printf '{"result":{"agents":[%s]}}\n' "$(cat "${FX}/agents" 2>/dev/null)" ;;
  *) echo '{"result":{}}' ;;
esac
STUB
printf '#!/bin/sh\nH="%s"; LOG="%s"\n' "${H}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
case "$*" in
  "pr view"*) read -r _ || true; echo "${H}" ;;
  *check-runs*) echo '{"total_count":1,"check_runs":[{"name":"test","status":"in_progress","conclusion":null,"html_url":"u"}]}' ;;
  *status*) echo '{"total_count":0,"statuses":[]}' ;;
  *) exit 1 ;;
esac
STUB
# ps: the real one, except that a process list (-A) fails while ${FX}/ps.fail exists, and lists only this
# run's processes (its fake swarm.sh is under ${ROOT}): another copy of this test running on the machine
# starts fakes with the same slugs and URLs, which would make a story here look busy. Before the list it
# removes the file ${FX}/ps.rm names (a rung starting between the board read and the process list), and
# it leaves out the pid ${FX}/ps.hide holds (a process started after the list was read).
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase " $* " in *" -A "*) [ ! -e "%s/ps.fail" ] || exit 1\n  [ ! -e "%s/ps.rm" ] || rm -f "$(cat "%s/ps.rm")"\n  %s "$@" | grep -F "%s" | awk -v h="$(cat "%s/ps.hide" 2>/dev/null)" '"'"'h == "" || $1 != h'"'"'; exit 0 ;; esac\nexec %s "$@"\n' \
  "${FX}" "${FX}" "${FX}" "$(command -v ps)" "${ROOT}" "${FX}" "$(command -v ps)" > "${ROOT}/bin/ps"
chmod +x "${ROOT}/bin/ps"
# git: the real one, logging each show-ref (a build read from git).
printf '#!/bin/sh\ncase " $* " in *" show-ref "*) echo "$*" >> "%s" ;; esac\nexec %s "$@"\n' "${ROOT}/git.log" "$(command -v git)" > "${ROOT}/bin/git"
chmod +x "${ROOT}/bin/git"
# The fake swarm.sh a busy process runs: ps shows `bash .../swarm.sh <args>` while it sleeps.
printf 'while :; do sleep 0.2; done\n' > "${ROOT}/fake/swarm.sh"
# Another program, alive but no swarm.sh: a pid a step-up marker may name once reused.
cp "${ROOT}/fake/swarm.sh" "${ROOT}/fake/other.sh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }

story() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
# ev <command> <target> [outcome] [time] — one events.tsv line, as swarm.sh writes it.
ev() { printf '%s\t%s\t%s\t-\t%s\n' "${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "$1" "$2" "${3:-ok}" >> "${P}/.swarm/events.tsv"; }
# built <slug> — its worktree, where worktree_for puts it, and its builder in agents.tsv.
built() { mkdir -p "${ROOT}/proj-wt/$1"; printf '2026-10-01\tcode\t%s\tclaude\tsonnet\thigh\ts-%s\n' "$1" "$1" >> "${P}/.swarm/agents.tsv"; }
# listed <name>... — herdr lists each, idle, in a pane this project opened; with none, no agent.
listed() {
  local n list="" i=0
  : > "${P}/.swarm/state/tab"
  for n in "$@"; do
    i=$((i + 1))   # a pane id own_panes takes: letters and digits either side of the colon
    list+="${list:+,}{\"name\":\"${n}\",\"agent_status\":\"idle\",\"pane_id\":\"w:p${i}\"}"
    echo "w:p${i} ${n}" >> "${P}/.swarm/state/tab"
  done
  printf '%s' "${list}" > "${FX}/agents"
}
# busy <args>... — a process running `swarm.sh <args>` until unbusy.
busy() { bash "${ROOT}/fake/swarm.sh" "$@" & busy_pid=$!; }
unbusy() { [[ -z "${busy_pid}" ]] || { kill "${busy_pid}" 2>/dev/null || true; wait "${busy_pid}" 2>/dev/null || true; busy_pid=""; }; }

# fresh [config line]... — an empty board, no events, no agents, an empty seen file (a run before this one).
fresh() {
  unbusy
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/agents.tsv" "${P}/.swarm/lead" "${P}/.swarm/reviews" "${P}/.swarm/briefs" "${ROOT}/proj-wt" \
    "${FX}/list.fail" "${FX}/list.hang" "${FX}/ps.fail" "${FX}/ps.rm" "${FX}/ps.hide" "${P}/.swarm/upgrade.pid" "${P}/.swarm/board-state" "${ROOT}"/*.log
  printf '%s\n' "$@" > "${P}/.claude/swarm/config"
  listed
  mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"
  polls=0
}
# poll — one read of the lead's queue, inside herdr; output in ${ROOT}/out, exit code in ${ROOT}/rc.
# poll [VAR=value]... — one read of the lead's queue, inside herdr; output in ${ROOT}/out, exit code in
# ${ROOT}/rc.
poll() {
  polls=$((polls + 1))
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:lead "$@" \
    bash "${SWARM}" wait --lead 0 > "${ROOT}/out" 2>&1) && echo 0 > "${ROOT}/rc" || echo $? > "${ROOT}/rc"
}
out() { cat "${ROOT}/out"; }
rc() { cat "${ROOT}/rc"; }
silent() { [[ "$(out)|$(rc)" == "|1" ]]; }
no_line() { ! grep -q '^no-agent:' "${ROOT}/out"; }
# fires <slug> <exit> — the poll printed exactly that no-agent line and exited 0; else it says what it got.
fires() { [[ "$(out)|$(rc)" == "no-agent: $1, exit: $2|0" ]] || { echo "  got: $(out)|$(rc)"; return 1; }; }
last_event() { tail -1 "${P}/.swarm/events.tsv" 2>/dev/null | awk -F'\t' '{ print $2 " " $3 " " $5 }'; }
events() { awk -F'\t' '{ print $2 " " $3 }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }
# never_woke <slug> [after] — no lead-woken or no-agent events line for <slug> (after the first line
# matching [after]): a silent last poll alone does not show an earlier poll never fired.
never_woke() {
  awk -F'\t' -v s="$1" -v after="${2:-}" 'after == "" || $2 " " $3 == after { on = 1 }
    on && $3 == s && ($2 == "lead-woken" || $2 == "no-agent") { f = 1 } END { exit f }' "${P}/.swarm/events.tsv" 2>/dev/null
}
hold_x() { (cd "${P}" && env -u SWARM_PROJECT bash "${SWARM}" hold "$1" "$2" > /dev/null 2>&1); }
# rbrief <slug> <url> — review-agent's brief for <slug>'s PR <url>, its first line as review_brief writes it.
rbrief() { mkdir -p "${P}/.swarm/briefs"; printf 'Review %s, the PR of story %s, at its head %s, in this worktree.\n' "$2" "$1" "${H}" > "${P}/.swarm/briefs/review-$1.md"; }
# rhead <slug> — the head review-agent records once review-<slug> has started.
rhead() { mkdir -p "${P}/.swarm/reviews"; echo "${H}" > "${P}/.swarm/reviews/$1.head"; }
# run_exit — run the exit the no-review: line in ${ROOT}/fired names, with swarm.sh the stub below: it takes only
# `review-agent <slug> <PR URL>`, and leaves what the real one does once review-<slug> started: its ok
# line, the head on record, and review-<slug> listed beside the panes already listed.
mkdir -p "${ROOT}/stub"
printf '#!/bin/sh\nP="%s"; FX="%s"; H="%s"\n' "${P}" "${FX}" "${H}" > "${ROOT}/stub/swarm.sh"
cat >> "${ROOT}/stub/swarm.sh" <<'STUB'
[ "$#" = 3 ] && [ "$1" = review-agent ] || exit 1
case "$3" in https://*/pull/[0-9]*) ;; *) exit 1 ;; esac
printf '%s\treview-agent\t%s\t-\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" >> "${P}/.swarm/events.tsv"
mkdir -p "${P}/.swarm/reviews"; echo "${H}" > "${P}/.swarm/reviews/$2.head"
printf '%s{"name":"review-%s","agent_status":"working","pane_id":"w:p9"}' "$([ -s "${FX}/agents" ] && cat "${FX}/agents" && echo ,)" "$2" > "${FX}/agents.new"
mv "${FX}/agents.new" "${FX}/agents"; echo "w:p9 review-$2" >> "${P}/.swarm/state/tab"
STUB
chmod +x "${ROOT}/stub/swarm.sh"
run_exit() {
  local cmd
  cmd="$(sed -n 's/^no-review: .*, exit: \(.*\), or the fallback reviewer$/\1/p' "${ROOT}/fired")"
  [[ "${cmd}" == "swarm.sh review-agent "* ]] || { echo "  no review-agent exit in: $(cat "${ROOT}/fired")"; return 1; }
  PATH="${ROOT}/stub:${PATH}" bash -c "${cmd}"
}
# rev_fires <slug> <url> — the poll printed exactly that no-review line and exited 0.
rev_fires() {
  [[ "$(out)|$(rc)" == "no-review: $1 $2, exit: swarm.sh review-agent $1 $2, or the fallback reviewer|0" ]] || { echo "  got: $(out)|$(rc)"; return 1; }
}

# --- where it fires.
fresh; story na-a "kind: code" "status: ready"; ev story na-a; built na-a; listed na-a
poll; poll
check "a ready story whose builder is listed, idle, is silent" silent
check "and gets no no-agent events line" test "$(last_event)" == "story na-a ok"
listed; ev close na-a
poll
check "its builder gone after a close line wakes the next poll, naming the hold exit" fires na-a "swarm.sh restart na-a, or swarm.sh hold na-a <reason>"
check "it logs lead-woken <slug> with the kind in the outcome" test "$(last_event)" == "lead-woken na-a ok (no-agent)"
poll
check "the same no-agent line does not wake it twice" silent

fresh; story na-b "kind: code" "status: ready"; ev story na-b; built na-b
poll
check "a pane gone with no close line: the poll that sees it does not wake" silent
check "that poll writes the no-agent events line" test "$(last_event)" == "no-agent na-b ok"
poll
check "the next poll wakes on it" fires na-b "swarm.sh restart na-b, or swarm.sh hold na-b <reason>"

fresh "merge = agent"; story na-r "kind: code" "status: review" "prs: ${URL}"; ev story na-r; built na-r
ev review-agent na-r; ev close review-na-r
mkdir -p "${P}/.swarm/reviews"; printf 'head: %s\n\n## Findings\n\nNone.\n' "${H}" > "${P}/.swarm/reviews/na-r.md"
poll
check "a review story under merge = agent with no agent, merge or wait-pr fires with swarm.sh merge --head" \
  fires na-r "swarm.sh merge --head ${H} ${URL}"
check "no gh call reads it" test ! -e "${ROOT}/gh.log"

# --- where it stays silent.
fresh; story na-q "kind: code" "status: ready"; story na-d "kind: code" "status: blocked" "depends_on: [na-q]"
poll
check "a ready story not started (queued on capacity or a clash) is silent" silent
check "and gets no no-agent events line" test -z "$(events)"
# A build cleared by a close that counted it (no worktree, no branch) is a story queued for its next attempt.
fresh; story na-q "kind: code" "status: ready" "attempts: 1"; ev story na-q; ev close:stalled na-q; poll; poll
check "a ready story whose last build a close cleared is silent" silent
check "and no poll woke on it (na-q)" never_woke na-q
# reconcile reopened it (its PR closed unmerged), its builder gone with no close: unblock --startable names
# it for the lead from the reopen being its last event, so no line may hide that, kept build or not.
fresh; story na-o "kind: code" "status: ready"; ev story na-o; ev reconcile na-o "ok (reopened)"; built na-o; poll; poll
check "a story reconcile reopened is silent, its worktree kept or not" never_woke na-o
check "and its last events line is still the reopen" test "$(last_event)" == "reconcile na-o ok (reopened)"
ev story na-o; ev close na-o; poll
check "once a new build starts and its builder goes, it fires again" fires na-o "swarm.sh restart na-o, or swarm.sh hold na-o <reason>"
# An upgrade restarts only running agents: a reopened story's builder was not one, so it stays left out.
fresh; story na-o "kind: code" "status: ready" "epic: e1"; ev story na-o; ev reconcile na-o "ok (reopened)"; built na-o
poll; ev upgrade e1; poll; poll
check "reopened, then an upgrade of its epic: still silent" never_woke na-o
check "and the reopen stays the last events line for its slug" \
  test "$(awk -F'\t' '$3 == "na-o" { l = $2 " " $5 } END { print l }' "${P}/.swarm/events.tsv")" == "reconcile ok (reopened)"

fresh; story na-c "kind: code" "status: ready"; ev story na-c; built na-c; listed na-c
ev review-agent na-c; ev close review-na-c
poll; poll
check "the CI window after a push (builder listed idle, review agent closed) is silent" silent
check "and no poll woke on it (na-c)" never_woke na-c

# The 2026-10-25 events of config-keys-back, up to its review agent's close, with its builder listed.
# Its brief and head on record, so only the close keeps the review agent's absence quiet.
fresh; story config-keys-back "kind: code" "status: ready"; built config-keys-back; listed config-keys-back
rbrief config-keys-back "${URL}"; rhead config-keys-back
while IFS='|' read -r t c g o; do ev "${c}" "${g}" "${o}" "${t}"; done <<'EVENTS'
2026-10-25T10:26:57Z|story|config-keys-back|ok
2026-10-25T10:41:55Z|tell:nudge|config-keys-back|config-keys-back is still working
2026-10-25T11:12:00Z|incident|config-keys-back|wait-timeout: busy
2026-10-25T11:18:16Z|tell:nudge|config-keys-back|ok
2026-10-25T11:19:10Z|review-agent|config-keys-back|review-agent: config-keys-back's worktree has uncommitted changes
2026-10-25T11:26:41Z|review-agent|config-keys-back|ok
2026-10-25T11:27:05Z|incident|review-config-keys-back|api-error: API Error
2026-10-25T11:27:18Z|resume|review-config-keys-back|ok
2026-10-25T11:29:22Z|resume|review-config-keys-back|ok
2026-10-25T11:30:35Z|close|review-config-keys-back|ok
EVENTS
poll; poll
check "the 2026-10-25 close review-config-keys-back replayed with the builder listed is silent" silent
check "and no poll woke on it (config-keys-back)" never_woke config-keys-back

fresh "merge = human"; story na-u "kind: code" "status: review" "prs: ${URL}"; ev story na-u; built na-u; ev close na-u
poll; poll
check "a review story waiting on the user's merge with its head pending (merge = human) is silent" silent
check "and no poll woke on it (na-u)" never_woke na-u

# Of a kind an agent builds, so only its held_for: keeps it out.
fresh; story na-h "kind: code" "status: ready" "held_for: paused"; ev story na-h; built na-h; ev close na-h
poll
check "a held story gets no no-agent line" no_line
check "and no no-agent event (its held: line wakes the lead instead)" test -z "$(events | grep -x 'no-agent na-h')"
fresh; story na-l "kind: lead" "status: ready"; ev agent na-l; built na-l; ev close na-l
poll; poll
check "a kind: lead story gets no no-agent line" no_line
check "and no poll woke on it (na-l)" never_woke na-l

fresh; story na-f "kind: code" "status: ready"; ev story na-f; built na-f; ev close na-f; touch "${FX}/list.fail"
poll; poll
check "with herdr's list failing it is silent" silent
check "and writes no events line" test "$(last_event)" == "close na-f ok"
rm -f "${FX}/list.fail"; touch "${FX}/ps.fail"; poll; poll
check "with ps failing, a pending tell cannot be ruled out, so it is silent" never_woke na-f

fresh "merge = agent"; story na-m "kind: code" "status: review" "prs: ${URL}"; ev story na-m; built na-m; ev close review-na-m
busy merge --head "${H}" "${URL}"
poll
check "a review story with a swarm.sh merge <url> process running is silent" silent
unbusy; busy wait-pr "${URL}"
poll
check "and with a swarm.sh wait-pr <url> process running" silent
unbusy
poll
check "once no process answers for it, it fires, naming review-agent when no reviewed head is known" \
  fires na-m "swarm.sh review-agent na-m ${URL}"
poll
check "after the wait-pr ends, the line comes back once and then stays quiet" silent

# --- tells.
fresh; story na-t "kind: code" "status: ready"; ev story na-t; built na-t; ev close na-t
busy tell na-t findings /tmp/f.md
poll
check "a tell pending (its process running, the builder not listed) is silent" silent
unbusy; busy agent t1 na-t /tmp/wt code /tmp/brief.md
poll
check "a builder start pending (a swarm.sh agent process for it, no pane yet) is silent" silent
unbusy; ev tell:findings na-t; listed na-t
poll; poll
check "a tell answered (its ok line, the builder listed) is silent" silent
check "and no poll woke on it after the answer" never_woke na-t "tell:findings na-t"
listed
poll
check "the builder's pane gone after the answer: the first poll writes the no-agent line" test "$(out)|$(last_event)" == "|no-agent na-t ok"
poll
check "and the next one fires" fires na-t "swarm.sh restart na-t, or swarm.sh hold na-t <reason>"

# --- the lead's hold.
fresh; story na-k "kind: code" "status: ready"; ev story na-k; built na-k; ev close na-k
poll
check "the alert fires before the hold" fires na-k "swarm.sh restart na-k, or swarm.sh hold na-k <reason>"
hold_x na-k "waiting on the CI fix"
check "swarm.sh hold logs its line" test "$(last_event)" == "hold na-k ok (waiting on the CI fix)"
poll
check "a hold after the alert silences the next poll" silent
check "that poll's queue no longer lists the line" test -z "$(grep '^no-agent: na-k' "${P}/.swarm/lead/seen")"
check "that poll writes a new no-agent event for the slug" test "$(last_event)" == "no-agent na-k ok"
poll
check "with still no agent after the hold, the poll after that new event fires no-agent: again" fires na-k "swarm.sh restart na-k, or swarm.sh hold na-k <reason>"

fresh; story na-g "kind: code" "status: ready"; ev story na-g; built na-g; ev close na-g
poll; hold_x na-g "restarting it"; ev story na-g; listed na-g
poll; poll
check "a hold followed by a restored builder stays silent" silent
check "and no poll woke on it after the hold" never_woke na-g "hold na-g"

# --- the lead's restart: its exit comes first for a ready story. Stubbed: the restart line and the builder
# listed again, as swarm.sh restart leaves them (restart_test.sh runs the command itself).
fresh; story na-x "kind: code" "status: ready"; ev story na-x; built na-x; ev close na-x
poll
check "a ready story's exit names swarm.sh restart <slug>" fires na-x "swarm.sh restart na-x, or swarm.sh hold na-x <reason>"
ev restart na-x "ok (resumed session s-1)"; listed na-x
# An empty seen file, as a new lead run starts with, so only the restart keeps the line from printing again.
: > "${P}/.swarm/lead/seen"
poll
check "after a restart the next poll is silent" silent
check "and that poll's queue no longer lists the line" test -z "$(grep '^no-agent: na-x' "${P}/.swarm/lead/seen")"
check "and no poll woke on it after the restart" never_woke na-x "restart na-x"
# Where restart would refuse the story, the exit is the hold alone: held until its parents merge
# (held_by:), or its worktree gone with only its branch left.
fresh; story na-y "kind: code" "status: ready" "held_by: [na-x]"; ev story na-y; built na-y; ev close na-y
poll
check "a story held until its parents merge gets only the hold exit" fires na-y "swarm.sh hold na-y <reason>"
git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "${P}" branch story/na-z
fresh; story na-z "kind: code" "status: ready"; ev story na-z; ev close na-z
poll
check "a story with only its branch left, no worktree, gets only the hold exit" fires na-z "swarm.sh hold na-z <reason>"
git -C "${P}" branch -q -D story/na-z
fresh; story na-f2 "kind: code" "status: ready"; ev story na-f2 "start failed"; mkdir -p "${ROOT}/proj-wt/na-f2"
poll
check "a first start that failed before its builder was recorded gets only the hold exit" fires na-f2 "swarm.sh hold na-f2 <reason>"

# --- a fresh run, with no seen file.
fresh; rm -f "${P}/.swarm/lead/seen"; story na-n "kind: code" "status: ready"; ev story na-n; built na-n; ev close na-n
poll
check "a fresh run with no .swarm/lead/seen prints the line on its first read" fires na-n "swarm.sh restart na-n, or swarm.sh hold na-n <reason>"

# --- a failed step-up: its .step-up marker gets its own line, step-up failed:, once no step-up of it runs.
# marker <slug> [pid] — the .step-up marker step_up writes, with a `pid [pid]` line when [pid] is given.
# marker <slug> [pid] [closed] — a .step-up marker: its rung, a pid line with [pid], and closed with [closed].
marker() { mkdir -p "${P}/.swarm/briefs"; { echo "stalled opus fable code"; [[ -z "${2:-}" ]] || echo "pid $2"; [[ -z "${3:-}" ]] || echo closed; } > "${P}/.swarm/briefs/$1.step-up"; }
DEAD=999999999   # above every system's pid limit, so no process has it
step_fires() { [[ "$(out)|$(rc)" == "step-up failed: $1, exit: swarm.sh step-up --resume $1|0" ]]; }

fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; ev close na-s
marker na-s "${DEAD}"; ev step-up:failed na-s "ok (start failed)"
poll
check "a marker, a step-up:failed line and no builder: the first poll wakes the lead with the resume exit, and no no-agent line" step_fires na-s
check "it logs lead-woken with the kind in the outcome" test "$(last_event)" == "lead-woken na-s ok (step-up failed)"
poll
check "the same step-up failed line does not wake it twice" silent

fresh; rm -f "${P}/.swarm/lead/seen"; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; ev close na-s
marker na-s "${DEAD}"; ev step-up:failed na-s "ok (start failed)"
poll
check "a fresh run with no .swarm/lead/seen prints the step-up failed line on its first read" step_fires na-s
# Only those two kinds: a held line whose cause holds ", exit: " is noted, not printed.
fresh; rm -f "${P}/.swarm/lead/seen"; story na-h "kind: lead" "status: ready" "escalated_from: code" "held_for: paused, exit: none"
poll
check "a fresh run does not print a held line whose cause holds ', exit: '" silent

# A step-up under way: its marker, no failure line, no builder listed, and its swarm.sh _step-up (the pid
# on the marker) running, its lock held.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s
busy _step-up na-s stalled; marker na-s "${busy_pid}"; mkdir -p "${P}/.swarm/locks/step-up-na-s"
poll
check "a step-up under way (its process alive) is silent" silent
poll
check "and no poll woke on it" never_woke na-s
# A resume that rewrote the marker after the poll read ps: its pid is missing from that list but alive.
echo "${busy_pid}" > "${FX}/ps.hide"; poll; rm -f "${FX}/ps.hide"
check "a marker pid missing from the poll's ps but alive now (a resume just started) is silent" silent
# Killed after closing the builder, before it could log step-up:failed: its pid is gone, its lock left.
unbusy
poll
check "a marker whose step-up pid is gone, with no failure line and the lock still held, fires within one poll" step_fires na-s
# A pid that is alive but not a swarm.sh step-up (the pid reused) is no step-up running either.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s
bash "${ROOT}/fake/other.sh" & other_pid=$!; marker na-s "${other_pid}"
poll
kill "${other_pid}" 2>/dev/null || true; wait "${other_pid}" 2>/dev/null || true
check "a marker whose pid is now another program's fires" step_fires na-s
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; marker na-s
poll
check "a marker with no pid line fires" step_fires na-s
# A pid reused by another story's step-up is not this one's.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s
busy _step-up na-other stalled; marker na-s "${busy_pid}"
poll
check "a marker whose pid is now another story's step-up fires" step_fires na-s
unbusy
# Killed inside the close (no closed line on the marker): the pane listed under the builder's name may
# be the old builder, so the alert waits.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; marker na-s "${DEAD}"; listed na-s
poll; poll
check "a marker without a closed line whose step-up is gone but whose builder is still listed is silent" never_woke na-s
# The marker says the old builder was closed: a pane under its name is the new rung's. Left by a step-up
# killed after start_agent opened it, before start_rung could log anything: it fires.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; marker na-s "${DEAD}" closed; listed na-s
poll
check "a closed marker with a dead pid and no failure line, its pane listed (killed after the new pane opened), fires" step_fires na-s
# Or kept by start_rung, its failure logged: it fires.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; marker na-s "${DEAD}" closed; listed na-s
ev step-up:failed na-s "ok (start unclear)"
poll
check "a marker whose new rung's pane was kept (start unclear) fires, the pane listed" step_fires na-s
# A resume that then fails in its checks (a generic failure line) leaves the kept pane the new rung's.
ev step-up:failed na-s "ok (step-up: could not list the PRs on story/na-s (git or gh), so nothing was closed)"; rm -f "${P}/.swarm/lead/seen"
poll
check "a later resume failing in its checks still leaves the kept pane the new rung's: it fires" step_fires na-s
# The rung started between the board read and the pid read (start_rung removed the marker): no alert.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; ev close na-s; marker na-s "${DEAD}"
echo "${P}/.swarm/briefs/na-s.step-up" > "${FX}/ps.rm"
poll
check "a marker gone by the time its pid is read is a rung that started: silent" silent

# After a resume that worked: the marker gone, the step-up logged, the new builder listed.
fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; ev close na-s
ev step-up:failed na-s "ok (start failed)"; ev escalate na-s "ok (stalled: opus -> fable)"; ev step-up:resume na-s; listed na-s
poll
check "after a resume that worked (no marker, its builder listed) it is silent" silent
poll
check "and no poll woke on it" never_woke na-s
fresh; story na-s "kind: lead" "status: ready"; ev story na-s; built na-s; marker na-s "${DEAD}"
poll
check "a kind: lead story's marker gets no line" silent
# Only a ready story steps up: one in review keeps to the no-agent: line and its merge exit, marker or not.
fresh "merge = agent"; story na-s "kind: code" "status: review" "prs: ${URL}"; ev story na-s; built na-s; ev close review-na-s
marker na-s "${DEAD}"
poll
check "a story in review with a marker gets the no-agent: review exit, never a resume" fires na-s "swarm.sh review-agent na-s ${URL}"

# --- the review exit is never an unpinned merge, and prs: is split on commas too.
fresh "merge = agent"; story na-p "kind: code" "status: review" "prs: [${URL},${URL2}]"; ev story na-p; built na-p; ev close review-na-p
mkdir -p "${P}/.swarm/reviews"; printf 'head: %s\n\n## Findings\n' "${H}" > "${P}/.swarm/reviews/na-p.md"
busy merge --head "${H}" "${URL2}"
poll
check "a merge on the second URL of prs: [a,b] silences it" silent
unbusy; poll
check "with two PRs one head cannot pin, the exit is review-agent for each" \
  fires na-p "swarm.sh review-agent na-p ${URL}, then swarm.sh review-agent na-p ${URL2}"
# A review agent that wrote its head: line and stopped before its findings: no pass, so no merge.
fresh "merge = agent"; story na-i "kind: code" "status: review" "prs: ${URL}"; ev story na-i; built na-i; ev close review-na-i
mkdir -p "${P}/.swarm/reviews"; printf 'head: %s\n' "${H}" > "${P}/.swarm/reviews/na-i.md"; poll
check "a findings file with a head: line but no review is no pass: the exit is review-agent" \
  fires na-i "swarm.sh review-agent na-i ${URL}"
# Its PR is looked for in the story's own repo, a sibling of the project here, by that repo's origin.
git init -q "${ROOT}/na-sib"; git -C "${ROOT}/na-sib" remote add origin https://github.com/na-owner/na-sib.git
fresh "merge = agent"; story na-x "kind: code" "status: review" "repo: na-sib"; ev story na-x; ev close review-na-x; poll
check "a review story with no PR URL is never offered hold, which refuses it: find its PR in its repo, then review-agent" \
  fires na-x "gh pr list -R https://github.com/na-owner/na-sib.git --head story/na-x, then swarm.sh review-agent na-x <PR URL>"

# costs: money holds its PRs for the user's merge, however prs: is written.
fresh "merge = agent"; story na-mo "kind: code" "status: review" "costs: money" "prs: [${URL},${URL2}]"
ev story na-mo; built na-mo; ev close review-na-mo; poll; poll
check "a costs: money review story whose prs: is [a,b] with no space is the user's: silent" never_woke na-mo
fresh "merge = agent"; story na-mn "kind: code" "status: review" "costs: money"; ev story na-mn; ev close review-na-mn; poll; poll
check "a costs: money review story with no PR URL yet is the user's too: silent" never_woke na-mn

# --- no-review: a review agent that never started, or started and went, with no round under way. The
# builder is listed idle in each: the line does not wait for it to go.
fresh; story nr-a "kind: code" "status: ready"; ev story nr-a; built nr-a; listed nr-a
rbrief nr-a "${URL}"; ev review-agent nr-a "review-agent: review-nr-a did not start (its pane w:p9 is closed)"
poll
check "a failed review-agent start and no review-nr-a pane fires, naming the PR and the exit" rev_fires nr-a "${URL}"
check "it logs lead-woken with the kind no-review" test "$(last_event)" == "lead-woken nr-a ok (no-review)"
cp "${ROOT}/out" "${ROOT}/fired"
poll
check "the same no-review line does not wake it twice" silent
# The exit, run with swarm.sh stubbed.
check "the line's exit runs, and starts review-nr-a" run_exit
check "review-nr-a is listed after it" grep -q '"name":"review-nr-a"' "${FX}/agents"
poll
check "after the exit starts review-nr-a, the next poll is silent" silent
check "and that poll's queue no longer lists the line" test -z "$(grep '^no-review: nr-a' "${P}/.swarm/lead/seen")"
# Started and went: its pane gone, a findings file for an older head only, and no close line.
listed nr-a; mkdir -p "${P}/.swarm/reviews"; printf 'head: 2222222222222222222222222222222222222222\n\n## Findings\n' > "${P}/.swarm/reviews/nr-a.md"
poll
check "review-nr-a gone after an ok start and a head, with no findings for that head and no close, fires" rev_fires nr-a "${URL}"

fresh; story nr-s "kind: code" "status: ready"; ev story nr-s; built nr-s; listed nr-s review-nr-s
rbrief nr-s "${URL}"; ev review-agent nr-s; rhead nr-s
poll; poll
check "review-nr-s listed after an ok start is silent" never_woke nr-s
listed nr-s; printf 'head: %s\n\n## Findings\n\nNone.\n' "${H}" > "${P}/.swarm/reviews/nr-s.md"
poll; poll
check "review-nr-s gone, its findings file a pass on its head (review_pass), is silent" never_woke nr-s
# The builder fixing what it was told: a review start refused meanwhile is no alert.
ev tell:findings nr-s; ev review-agent nr-s "review-agent: nr-s's worktree has uncommitted changes, so it is not the PR's head"
poll; poll
check "a failed start after a tell:findings line no older than the findings file is silent" never_woke nr-s
# An ok start removes the last findings file: a tell before that start says nothing about this round,
# even in the same second (events.tsv's order tells them apart).
rm -f "${P}/.swarm/reviews/nr-s.md"; ev review-agent nr-s ok "$(awk -F'\t' '$2 == "tell:findings" { t = $1 } END { print t }' "${P}/.swarm/events.tsv")"
poll
check "review-nr-s gone after a start that follows the tell in the same second, with no findings file, fires" rev_fires nr-s "${URL}"
# An empty seen file, so a line still there would print again.
ev tell:findings nr-s; : > "${P}/.swarm/lead/seen"; poll
check "a tell after that start, with still no findings file, is a round under way: silent" silent
# A review that stopped on a moved head is no review: review_pass rejects it.
# The tell before it, likely in the same second, is the last round's: events.tsv's order says so.
fresh; story nr-m "kind: code" "status: ready"; ev story nr-m; built nr-m; listed nr-m
rbrief nr-m "${URL}"; ev tell:findings nr-m; ev review-agent nr-m; rhead nr-m
printf 'head: %s\nhead moved: a new commit\n' "${H}" > "${P}/.swarm/reviews/nr-m.md"
poll
check "review-nr-m gone after writing head moved: for its head, the last round's tell just before its start, fires" rev_fires nr-m "${URL}"

# An ok start with no head on record yet is no sign the agent went: review_agent writes it last.
fresh; story nr-h "kind: code" "status: ready"; ev story nr-h; built nr-h; listed nr-h; rbrief nr-h "${URL}"; ev review-agent nr-h
poll; poll
check "an ok start with no .head and no review-nr-h pane is silent" never_woke nr-h
# A fresh lead run (no seen file) prints the alert on its first read.
fresh; rm -f "${P}/.swarm/lead/seen"; story nr-n "kind: code" "status: ready"; ev story nr-n; built nr-n; listed nr-n
rbrief nr-n "${URL}"; ev review-agent nr-n "review-agent: review-nr-n did not start"
poll
check "a fresh run with no .swarm/lead/seen prints the no-review line on its first read" rev_fires nr-n "${URL}"

# Round 2: round 1's findings file and tell stay on record. A start that fails is no round under way.
fresh; story nr-2 "kind: code" "status: ready"; ev story nr-2 ok 2026-10-25T00:00:00Z; built nr-2; listed nr-2
rbrief nr-2 "${URL}"; ev review-agent nr-2 ok 2026-10-25T00:01:00Z; rhead nr-2
printf 'head: %s\n\n## Findings\n\n- [P2] a finding\n' "${H}" > "${P}/.swarm/reviews/nr-2.md"; touch -t 202610250002 "${P}/.swarm/reviews/nr-2.md"
ev tell:findings nr-2 ok 2026-10-25T00:03:00Z
ev review-agent nr-2 "review-agent: review-nr-2 did not start (its pane w:p9 is closed); ${P}/.swarm/reviews/nr-2.md is put back"
poll
check "round 2's start that did not start, round 1's findings and tell on record, fires" rev_fires nr-2 "${URL}"
ev review-agent nr-2 "review-agent: could not read ${URL}'s head (gh pr view --json headRefOid)"; : > "${P}/.swarm/lead/seen"
poll
check "and so does one that could not read the PR's head" rev_fires nr-2 "${URL}"

# A start refused while the conductor waits on CI (a wait-pr on the PR) is the normal handoff.
fresh; story nr-w "kind: code" "status: ready"; ev story nr-w; built nr-w; listed nr-w
rbrief nr-w "${URL}"; ev review-agent nr-w "review-agent: nr-w's worktree has uncommitted changes, so it is not the PR's head; nothing was started"
busy wait-pr "${URL}"
poll
check "a swarm.sh wait-pr on the brief's PR running is silent" silent
unbusy; poll
check "once the wait-pr ends, it fires" rev_fires nr-w "${URL}"

# A refusal that leaves the earlier start running changes nothing: that review's own end decides.
fresh; story nr-v "kind: code" "status: ready"; ev story nr-v; built nr-v; listed nr-v review-nr-v
rbrief nr-v "${URL}"; ev review-agent nr-v; rhead nr-v
ev review-agent nr-v "review-agent: review-nr-v is still reviewing (no ${P}/.swarm/reviews/nr-v.md yet); nothing was started: wait for it"
printf 'head: %s\n\n## Findings\n\nNone.\n' "${H}" > "${P}/.swarm/reviews/nr-v.md"; ev close review-nr-v; listed nr-v
poll; poll
check "a start refused as still reviewing, then that review's pass and close, is silent" never_woke nr-v
fresh; story nr-v "kind: code" "status: ready"; ev story nr-v; built nr-v; listed nr-v review-nr-v
rbrief nr-v "${URL}"; ev review-agent nr-v; rhead nr-v
ev review-agent nr-v "review-nr-v: an agent with this name is still working; wait for it, or use another name"
printf 'head: %s\n\n## Findings\n\nNone.\n' "${H}" > "${P}/.swarm/reviews/nr-v.md"; ev close review-nr-v; listed nr-v
poll; poll
check "and so is one refused because review-nr-v still held its name" never_woke nr-v

# With no earlier start in this build, a name held elsewhere is a start that failed.
fresh; story nr-x "kind: code" "status: ready"; ev story nr-x; built nr-x; listed nr-x; rbrief nr-x "${URL}"
ev review-agent nr-x "review-nr-x: an agent this project did not start (no tab record in .swarm/state) holds this name (herdr agent list); it is never retired from here. Wait for it to finish, or close its pane"
poll
check "a first start refused because another project's agent holds review-nr-x fires" rev_fires nr-x "${URL}"
fresh; story nr-x "kind: code" "status: ready"; ev story nr-x; built nr-x; listed nr-x; rbrief nr-x "${URL}"
ev review-agent nr-x; rhead nr-x; ev close review-nr-x
ev review-agent nr-x "review-nr-x: an agent with this name is still working; wait for it, or use another name"
poll
check "so does one refused after the earlier review agent was closed" rev_fires nr-x "${URL}"

# One line per story: a ready story with its builder gone gets the restart first, then no-review:.
fresh; story nr-b "kind: code" "status: ready"; ev story nr-b; built nr-b; ev close nr-b
rbrief nr-b "${URL}"; ev review-agent nr-b "review-agent: review-nr-b did not start"
poll
check "a ready story with no builder and a failed review start gets the no-agent: line alone" fires nr-b "swarm.sh restart nr-b, or swarm.sh hold nr-b <reason>"
ev restart nr-b "ok (resumed session s-1)"; listed nr-b
poll
check "once restart brings the builder back, the next poll brings the no-review: line" rev_fires nr-b "${URL}"

# A failed line's URL ends where a URL cannot go on, and counts only when prs: is empty or holds it.
fresh; story nr-u "kind: code" "status: ready"; ev story nr-u; built nr-u; listed nr-u; rbrief nr-u "${URL}"
ev review-agent nr-u "review-agent: '${URL2}x' is not a PR URL (swarm.sh review-agent <slug> <PR URL>)"
poll
check "a refused '.../pull/42x' is no URL: the brief's PR" rev_fires nr-u "${URL}"
fresh; story nr-u "kind: code" "status: ready" "prs: ${URL}"; ev story nr-u; built nr-u; listed nr-u
ev review-agent nr-u "review-agent: could not read ${URL2}'s head (gh pr view --json headRefOid)"
poll
check "a failed line naming a PR not on prs: gives prs:'s PR" rev_fires nr-u "${URL}"

fresh; story nr-p "kind: code" "status: ready"; ev story nr-p; built nr-p; listed nr-p
rbrief nr-p "${URL}"; ev review-agent nr-p "review-agent: review-nr-p did not start"
busy review-agent nr-p "${URL}"
poll
check "a swarm.sh review-agent nr-p process running is silent" silent
unbusy; poll
check "once it ends with no new line, it fires" rev_fires nr-p "${URL}"

# A preflight that failed before the brief was written: the PR from the failed line, else from prs:.
fresh; story nr-f "kind: code" "status: ready"; ev story nr-f; built nr-f; listed nr-f
ev review-agent nr-f "review-agent: could not read ${URL}'s head (gh pr view --json headRefOid)"
poll
check "a preflight failure naming the PR, with no brief, fires with that PR" rev_fires nr-f "${URL}"
fresh; story nr-g "kind: code" "status: ready" "prs: ${URL2}"; ev story nr-g; built nr-g; listed nr-g
ev review-agent nr-g "review-agent: nr-g's worktree is at ${H}, not the PR's head; nothing was started"
poll
check "a preflight failure naming no PR, with no brief, fires with the PR on prs:" rev_fires nr-g "${URL2}"
fresh; story nr-g "kind: code" "status: ready" "repo: na-sib" "prs: [${URL},${URL2}]"; ev story nr-g; built nr-g; listed nr-g
ev review-agent nr-g "review-agent: nr-g's worktree is at ${H}, not the PR's head; nothing was started"
poll
check "with two PRs on prs: and nothing naming one, the exit finds the PR first" test "$(out)|$(rc)" == \
  "no-review: nr-g, exit: gh pr list -R https://github.com/na-owner/na-sib.git --head story/nr-g, then swarm.sh review-agent nr-g <PR URL>, or the fallback reviewer|0"
# An ok start whose brief is gone, with two PRs: none can be named either.
fresh; story nr-g "kind: code" "status: ready" "repo: na-sib" "prs: [${URL},${URL2}]"; ev story nr-g; built nr-g; listed nr-g
ev review-agent nr-g; rhead nr-g; poll
check "with two PRs, an ok start and no brief, the exit finds the PR first" test "$(out)|$(rc)" == \
  "no-review: nr-g, exit: gh pr list -R https://github.com/na-owner/na-sib.git --head story/nr-g, then swarm.sh review-agent nr-g <PR URL>, or the fallback reviewer|0"
ev review-agent nr-g "review-agent: nr-g's worktree is at ${H}, not the PR's head; nothing was started"
# A brief from the review of the first PR is no sign the failed start was for it.
rbrief nr-g "${URL}"; : > "${P}/.swarm/lead/seen"; poll
check "with two PRs and a brief for one, a failed start naming none still finds the PR first" test "$(out)|$(rc)" == \
  "no-review: nr-g, exit: gh pr list -R https://github.com/na-owner/na-sib.git --head story/nr-g, then swarm.sh review-agent nr-g <PR URL>, or the fallback reviewer|0"
# A brief older than the build's start is an earlier build's PR: the exit finds the PR first.
fresh; story nr-o "kind: code" "status: ready" "repo: na-sib"; ev story nr-o; built nr-o; listed nr-o
rbrief nr-o "${URL}"; touch -t 202001010000 "${P}/.swarm/briefs/review-nr-o.md"
ev review-agent nr-o "review-agent: nr-o's worktree has uncommitted changes"
poll
check "with only a brief older than the build's start, the exit finds the PR first" test "$(out)|$(rc)" == \
  "no-review: nr-o, exit: gh pr list -R https://github.com/na-owner/na-sib.git --head story/nr-o, then swarm.sh review-agent nr-o <PR URL>, or the fallback reviewer|0"
# A reopen (its PR closed unmerged) makes the brief before it an old PR's too, its builder kept.
fresh; story nr-o "kind: code" "status: ready" "repo: na-sib"; ev story nr-o 2026-01-01T00:00:00Z; built nr-o; listed nr-o
rbrief nr-o "${URL}"; touch -t 202601020000 "${P}/.swarm/briefs/review-nr-o.md"; ev reconcile nr-o "ok (reopened)"
ev review-agent nr-o "review-agent: nr-o's worktree is at ${H}, not the PR's head; nothing was started"
poll
check "after a reopen, a brief from before it is not the PR: the exit finds the PR first" test "$(out)|$(rc)" == \
  "no-review: nr-o, exit: gh pr list -R https://github.com/na-owner/na-sib.git --head story/nr-o, then swarm.sh review-agent nr-o <PR URL>, or the fallback reviewer|0"
# In review under merge = agent with no agent at all, its no-agent: line already names review-agent.
fresh "merge = agent"; story nr-r "kind: code" "status: review" "prs: ${URL}"; ev story nr-r; built nr-r
rbrief nr-r "${URL}"; ev review-agent nr-r "review-agent: review-nr-r did not start"
poll
check "a review story with no agent gets the no-agent: line alone" fires nr-r "swarm.sh review-agent nr-r ${URL}"

# --- the state file swarm.sh wrote wins over the front matter, unless the front matter changed since.
fresh; story na-e "kind: code" "status: ready"; ev story na-e; built na-e; ev close na-e
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: blocked\nstatus@base: ready\n' > "${P}/.swarm/board-state/stories/na-e"
poll; poll
check "a story its state file says is blocked is silent though its front matter says ready" never_woke na-e
fresh; story na-e "kind: code" "status: ready"; ev story na-e; built na-e; ev close na-e
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: blocked\nstatus@base: review\n' > "${P}/.swarm/board-state/stories/na-e"
poll
check "once the front matter differs from status@base, its own status (ready) counts over the state file's" \
  fires na-e "swarm.sh restart na-e, or swarm.sh hold na-e <reason>"
fresh "merge = agent"; story na-e "kind: code" "status: review" "prs: ${URL}"; ev story na-e; built na-e; ev close review-na-e
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: ready\nstatus@base: review\n' > "${P}/.swarm/board-state/stories/na-e"
poll
check "a state file's status: ready over front matter review gives the ready exit" fires na-e "swarm.sh restart na-e, or swarm.sh hold na-e <reason>"

# --- a hung herdr: the list is killed after SWARM_LEAD_LIST_WAIT, and the other lines still wake.
fresh; story na-z "kind: lead" "status: ready" "escalated_from: code" "held_for: paused"
story na-y "kind: code" "status: ready"; ev story na-y; built na-y; ev close na-y; touch "${FX}/list.hang"
t0=${SECONDS}; poll SWARM_LEAD_LIST_WAIT=1
check "with herdr's list hung, a held story still wakes the lead, and no no-agent line is printed" \
  test "$(out)|$(rc)" == "held: na-z (paused)|0"
check "the read gives up on the list within its wait" test $((SECONDS - t0)) -lt 60

# --- a story never started costs no git read.
fresh; story na-q "kind: code" "status: ready"; poll; poll
check "a ready story with no start line is not read from git" test ! -e "${ROOT}/git.log"
fresh; story na-q "kind: code" "status: ready"; ev story na-q; ev close:stalled na-q; poll
check "one whose last build a close ended is" grep -q 'refs/heads/story/na-q' "${ROOT}/git.log"

# --- an upgrade running here stops and restarts agents: its scope stays silent, and its end is a start.
fresh; story na-v "kind: code" "status: ready" "epic: e1"; ev story na-v; built na-v; ev close na-v
busy upgrade e1; echo "${busy_pid} e1 /tmp/upgrade.log" > "${P}/.swarm/upgrade.pid"
poll; poll
check "a story in a running upgrade's epic is silent" never_woke na-v
unbusy; rm -f "${P}/.swarm/upgrade.pid"; ev upgrade e1
poll
check "the upgrade's ok line counts as a start: the next poll writes a no-agent line, silent" \
  test "$(out)|$(last_event)" == "|no-agent na-v ok"
poll
check "and the one after fires" fires na-v "swarm.sh restart na-v, or swarm.sh hold na-v <reason>"
fresh; story na-w "kind: code" "status: ready" "epic: e2"; ev story na-w; built na-w; ev close na-w
busy upgrade e1; echo "${busy_pid} e1 /tmp/upgrade.log" > "${P}/.swarm/upgrade.pid"
poll
check "a story outside the upgrade's epic still fires" fires na-w "swarm.sh restart na-w, or swarm.sh hold na-w <reason>"
unbusy
fresh; story na-u2 "kind: code" "status: ready" "epic: e1"; ev story na-u2; built na-u2; ev close na-u2; marker na-u2 "${DEAD}"
busy upgrade e1; echo "${busy_pid} e1 /tmp/upgrade.log" > "${P}/.swarm/upgrade.pid"
poll
check "a failed step-up in a running upgrade's epic still fires" step_fires na-u2
unbusy; rm -f "${P}/.swarm/upgrade.pid"

# --- the cost of a poll: one herdr list, no per-pane read, no gh call, with a ready and a review case
# live, a failed step-up's marker and a review agent that never started.
fresh "merge = agent"; story na-a "kind: code" "status: ready"; ev story na-a; built na-a; ev close na-a
story na-r "kind: code" "status: review" "prs: ${URL}"; ev story na-r; built na-r; ev close review-na-r
story na-x "kind: code" "status: ready"; ev story na-x; built na-x; marker na-x "${DEAD}"
story nr-c "kind: code" "status: ready"; ev story nr-c; built nr-c; rbrief nr-c "${URL}"; ev review-agent nr-c "review-agent: review-nr-c did not start"
# Its builder listed at work, not idle: an idle one would get the resend pass's pane read.
listed nr-c; sed 's/"idle"/"working"/' "${FX}/agents" > "${FX}/agents.new"; mv "${FX}/agents.new" "${FX}/agents"
poll
check "the marker's line comes out beside the no-agent lines" test "$(grep -c '^step-up failed: na-x, exit: swarm.sh step-up --resume na-x$' "${ROOT}/out")" == 1
check "and so does the no-review line" grep -qxF "no-review: nr-c ${URL}, exit: swarm.sh review-agent nr-c ${URL}, or the fallback reviewer" "${ROOT}/out"
poll; poll
want=""; for ((i = 0; i < polls; i++)); do want+="agent list"$'\n'; done
check "each poll makes one herdr agent list and no other herdr call" test "$(cat "${ROOT}/herdr.log")" == "${want%$'\n'}"
check "and no gh call" test ! -e "${ROOT}/gh.log"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
