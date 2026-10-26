#!/usr/bin/env bash
# no_agent_test.sh — wait --lead's no-agent: line: a started story that no agent works on and that is not
# the user's to move wakes the lead, naming its exit, and every false case stays silent. Each poll is
# one `swarm.sh wait --lead 0`, which reads the queue exactly once. herdr is a stub listing the agents in
# ${FX}/agents, failing while ${FX}/list.fail exists; gh is a stub answering a pending head. Both log each
# call. A process that answers for a story (a tell, a wait-pr, a merge) is a fake swarm.sh that sleeps.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
busy_pid=""
trap 'unbusy; rm -rf "${ROOT}"' EXIT
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
# starts fakes with the same slugs and URLs, which would make a story here look busy.
printf '#!/bin/sh\ncase " $* " in *" -A "*) [ ! -e "%s/ps.fail" ] || exit 1; %s "$@" | grep -F "%s"; exit 0 ;; esac\nexec %s "$@"\n' \
  "${FX}" "$(command -v ps)" "${ROOT}" "$(command -v ps)" > "${ROOT}/bin/ps"
chmod +x "${ROOT}/bin/ps"
# git: the real one, logging each show-ref (a build read from git).
printf '#!/bin/sh\ncase " $* " in *" show-ref "*) echo "$*" >> "%s" ;; esac\nexec %s "$@"\n' "${ROOT}/git.log" "$(command -v git)" > "${ROOT}/bin/git"
chmod +x "${ROOT}/bin/git"
# The fake swarm.sh a busy process runs: ps shows `bash .../swarm.sh <args>` while it sleeps.
printf 'while :; do sleep 0.2; done\n' > "${ROOT}/fake/swarm.sh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }

story() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
# ev <command> <target> [outcome] [time] — one events.tsv line, as swarm.sh writes it.
ev() { printf '%s\t%s\t%s\t-\t%s\n' "${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "$1" "$2" "${3:-ok}" >> "${P}/.swarm/events.tsv"; }
# built <slug> — its worktree, where worktree_for puts it.
built() { mkdir -p "${ROOT}/proj-wt/$1"; }
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
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/lead" "${P}/.swarm/reviews" "${P}/.swarm/briefs" "${ROOT}/proj-wt" \
    "${FX}/list.fail" "${FX}/list.hang" "${FX}/ps.fail" "${P}/.swarm/upgrade.pid" "${P}/.swarm/board-state" "${ROOT}"/*.log
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

# --- where it fires.
fresh; story na-a "kind: code" "status: ready"; ev story na-a; built na-a; listed na-a
poll; poll
check "a ready story whose builder is listed, idle, is silent" silent
check "and gets no no-agent events line" test "$(last_event)" == "story na-a ok"
listed; ev close na-a
poll
check "its builder gone after a close line wakes the next poll, naming the hold exit" fires na-a "swarm.sh hold na-a <reason>"
check "it logs lead-woken <slug> with the kind in the outcome" test "$(last_event)" == "lead-woken na-a ok (no-agent)"
poll
check "the same no-agent line does not wake it twice" silent

fresh; story na-b "kind: code" "status: ready"; ev story na-b; built na-b
poll
check "a pane gone with no close line: the poll that sees it does not wake" silent
check "that poll writes the no-agent events line" test "$(last_event)" == "no-agent na-b ok"
poll
check "the next poll wakes on it" fires na-b "swarm.sh hold na-b <reason>"

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
check "once a new build starts and its builder goes, it fires again" fires na-o "swarm.sh hold na-o <reason>"
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
fresh; story config-keys-back "kind: code" "status: ready"; built config-keys-back; listed config-keys-back
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

fresh; story na-s "kind: code" "status: ready"; ev story na-s; built na-s; ev close na-s
mkdir -p "${P}/.swarm/briefs"; echo "stalled opus fable code" > "${P}/.swarm/briefs/na-s.step-up"
poll; poll
check "a story with a .step-up marker is silent (the marker's own line reports it)" silent
check "and no poll woke on it (na-s)" never_woke na-s

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
check "and the next one fires" fires na-t "swarm.sh hold na-t <reason>"

# --- the lead's hold.
fresh; story na-k "kind: code" "status: ready"; ev story na-k; built na-k; ev close na-k
poll
check "the alert fires before the hold" fires na-k "swarm.sh hold na-k <reason>"
hold_x na-k "waiting on the CI fix"
check "swarm.sh hold logs its line" test "$(last_event)" == "hold na-k ok (waiting on the CI fix)"
poll
check "a hold after the alert silences the next poll" silent
check "that poll's queue no longer lists the line" test -z "$(grep '^no-agent: na-k' "${P}/.swarm/lead/seen")"
check "that poll writes a new no-agent event for the slug" test "$(last_event)" == "no-agent na-k ok"
poll
check "with still no agent after the hold, the poll after that new event fires no-agent: again" fires na-k "swarm.sh hold na-k <reason>"

fresh; story na-g "kind: code" "status: ready"; ev story na-g; built na-g; ev close na-g
poll; hold_x na-g "restarting it"; ev story na-g; listed na-g
poll; poll
check "a hold followed by a restored builder stays silent" silent
check "and no poll woke on it after the hold" never_woke na-g "hold na-g"

# --- a fresh run, with no seen file.
fresh; rm -f "${P}/.swarm/lead/seen"; story na-n "kind: code" "status: ready"; ev story na-n; built na-n; ev close na-n
poll
check "a fresh run with no .swarm/lead/seen prints the line on its first read" fires na-n "swarm.sh hold na-n <reason>"

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

# --- the state file swarm.sh wrote wins over the front matter, unless the front matter changed since.
fresh; story na-e "kind: code" "status: ready"; ev story na-e; built na-e; ev close na-e
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: blocked\nstatus@base: ready\n' > "${P}/.swarm/board-state/stories/na-e"
poll; poll
check "a story its state file says is blocked is silent though its front matter says ready" never_woke na-e
fresh; story na-e "kind: code" "status: ready"; ev story na-e; built na-e; ev close na-e
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: blocked\nstatus@base: review\n' > "${P}/.swarm/board-state/stories/na-e"
poll
check "once the front matter differs from status@base, its own status (ready) counts over the state file's" \
  fires na-e "swarm.sh hold na-e <reason>"
fresh "merge = agent"; story na-e "kind: code" "status: review" "prs: ${URL}"; ev story na-e; built na-e; ev close review-na-e
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: ready\nstatus@base: review\n' > "${P}/.swarm/board-state/stories/na-e"
poll
check "a state file's status: ready over front matter review gives the ready exit" fires na-e "swarm.sh hold na-e <reason>"

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
check "and the one after fires" fires na-v "swarm.sh hold na-v <reason>"
fresh; story na-w "kind: code" "status: ready" "epic: e2"; ev story na-w; built na-w; ev close na-w
busy upgrade e1; echo "${busy_pid} e1 /tmp/upgrade.log" > "${P}/.swarm/upgrade.pid"
poll
check "a story outside the upgrade's epic still fires" fires na-w "swarm.sh hold na-w <reason>"
unbusy

# --- the cost of a poll: one herdr list, no per-pane read, no gh call, with a ready and a review case live.
fresh "merge = agent"; story na-a "kind: code" "status: ready"; ev story na-a; built na-a; ev close na-a
story na-r "kind: code" "status: review" "prs: ${URL}"; ev story na-r; built na-r; ev close review-na-r
poll; poll; poll
want=""; for ((i = 0; i < polls; i++)); do want+="agent list"$'\n'; done
check "each poll makes one herdr agent list and no other herdr call" test "$(cat "${ROOT}/herdr.log")" == "${want%$'\n'}"
check "and no gh call" test ! -e "${ROOT}/gh.log"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
