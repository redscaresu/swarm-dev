#!/usr/bin/env bash
# tell_queue_test.sh — `tell b1 findings <file>` to a builder that Claude Code lists as busy (herdr:
# working) is queued, not refused: it prints queued:, exits 0 and logs the tell as queued, not ok. A
# check left in the background looks once a minute (SWARM_NOTE_WAKE_SECS, 1 here): while the builder
# stays busy nothing is sent, and once it is idle the findings go through a tell of their own, logged
# ok, so they are delivered once and count as one findings round. Two findings tells queued for one
# busy builder deliver only the newer. A look while herdr's list fails (${ROOT}/listfail) drops
# nothing, and five such looks in a row hand the tell to the lead, counted afresh by each check. A tell sent at once to an idle
# builder replaces a queued one of its kind, which is never sent after it (a pending check's .later
# keeps the queue from starting one until the direct tell is done; a nudge queued next starts the
# check that would send what is left), nor is one already on its way (b1.findings.sending.<token>, as
# the check's take leaves it): its delivery, run as the check runs it (VIA), finds it gone and sends
# nothing. A delivery that finds the builder busy again leaves it on its way, for the check to put
# back, and one that claims it sends it. One a dead check left on its way is sent by the next check,
# and a delivery never claims another check's tell (its token). A direct tell that cannot take the
# queue's lock to replace a queued one sends nothing. The newer of two tells is the one that read the
# builder's state later: an older one that stalls in its read of the pane (${ROOT}/readslow, for a
# tell run with TQ_CALLER=slow) while a newer one is sent at once or queued is dropped as replaced
# when it takes the lock, and one sent at once that read the state before the time in
# b1.findings.sent (the last sent at once) or in a queued one's line is dropped the same way, the
# queued one kept. While a tell is on its way to the builder (herdr's prompt for "fix round A" waits
# for ${ROOT}/promptslow to go, and keys.log gets a prompt once herdr returns it), a queued one its
# delivery claimed or one sent at once, a newer tell that reads the builder idle is queued behind it,
# and lands after it, its check stamped live meanwhile; a mark whose process is dead
# (b1.findings.direct.<pid>, b1.findings.claimed.<token>) holds nothing up. A queued tell to a builder whose pane closed, or
# whose name a new pane holds, is sent to no pane: it is dropped, and wait --lead prints a tell
# undelivered: line for the lead, again for a later drop of its kind. One herdr sent but never showed
# taken up (${ROOT}/nosend: no status in its reply, idle on every read) is not to be sent again as
# findings: its line says it may have arrived, and it counts as one round. One herdr refused as
# blocked before sending anything (${ROOT}/blocked), whose pane then could not be read, was never
# sent: its line says to send it again. Queued findings due a
# step-up or a top-rung hold while the story's lock is held go back in the queue. A builder at its
# prompt with a background shell (busy, its turn over) gets its queued tell; mid-turn it waits. A
# queued tell whose check died goes to the lead through wait --lead, and so does one whose delivery
# failed before claiming it three times (${ROOT}/childfail). One a newer tell replaced on its way
# while its delivery failed before claiming it (${ROOT}/childreplace) goes nowhere. The check is its
# own process, so wait --lead's resend pass still reads the pane of an agent a tell waits for. With
# goal on, findings delivered whose goal then failed (${ROOT}/goalwait) count one round, and the lead
# is told not to send them again. A tell to an agent with no pane, or whose session has ended, is
# refused once as could not reach, naming its exit by role (a builder's no-agent:, a review agent's
# no-review:, a conductor's no conductor started:, any other agent's starting command), and its pane
# first while that is open; a note to a gone conductor too. One while herdr cannot list its agents, or
# lists none, is refused as one to send again. A queued tell to a builder whose session ended reaches
# the lead once over three wait --lead polls.
# herdr and claude are stubs on PATH. herdr lists the agents in ${ROOT}/agents (`<name> <pane> <status>`)
# and logs each prompt to ${ROOT}/keys.log; claude agents --json prints ${ROOT}/claude.json, which holds
# b1's session sb.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
p="${ROOT}/proj"; Q="${p}/.swarm/tells"
# until <test...> — wait (60 s at most) until <test> succeeds.
until_ok() { local i; for ((i = 0; i < 300; i++)); do "$@" && return 0; sleep 0.2; done; return 1; }
# settle — wait (60 s at most) for the check a queued tell left to end: it removes its .later, then lets
# go of the queue's lock, which the next case may take itself.
settle() { local i; for ((i = 0; i < 300; i++)); do compgen -G "${Q}/*.later" >/dev/null || compgen -G "${Q}/*.lock" >/dev/null || return 0; sleep 0.2; done; }
# Emptied first, so a check still running ends at its next look.
trap 'rm -f "${Q}"/*.findings "${Q}"/*.nudge "${Q}"/*.resume; settle; rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home" CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/claude-config/projects"
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
mkdir -p "${HOME}" "${ROOT}/bin" "${CLAUDE_PROJECTS_DIR}/p"
cp "${HERE}/claude_stub.sh" "${ROOT}/bin/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "agent list") [ ! -f "$F/listfail" ] || exit 1
    # With childfail, a queued tell's own delivery (its tell's file is a swarm-tell-queued copy) finds no agents.
    if [ -f "$F/childfail" ] && ps -o command= -p "$PPID" | grep -q swarm-tell-queued; then exit 1; fi
    # With childreplace, a newer tell replaces it on its way (its .sending goes) as its delivery fails.
    if [ -f "$F/childreplace" ] && ps -o command= -p "$PPID" | grep -q swarm-tell-queued; then rm -f "$F"/proj/.swarm/tells/b1.findings.sending.*; exit 1; fi
    awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
    { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, $3 }
    END { print "]}}" }' "$F/agents" ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(awk -v p="$3" '$2 == p { print $3 }' "$F/agents")" ;;
  "agent prompt") case "$*" in *"fix round A"*) while [ -f "$F/promptslow" ]; do sleep 0.1; done ;; esac   # that tell stays on its way until the test lets its prompt through; any other prompt goes at once
    echo "$*" >> "$F/keys.log"   # logged once herdr has it, after any stall: keys.log's order is the order herdr got them
    if [ -f "$F/blocked" ]; then echo '{"error":{"code":"agent_blocked"}}' >&2; exit 1; fi   # refused before anything was sent
    [ -f "$F/nosend" ] || echo '{"result":{"agent":{"agent_status":"working"}}}'
    [ ! -f "$F/goalwait" ] || echo '[{"sessionId": "sb", "status": "waiting", "waitingFor": "permission prompt"}]' > "$F/claude.json" ;;
  "agent read") echo "${TQ_CALLER:--} | $*" >> "$F/reads.log"   # TQ_CALLER: lead for wait --lead's own reads
    # A tell run with TQ_CALLER=slow stalls here, after it read the builder busy, while readslow exists.
    [ "${TQ_CALLER:-}" != slow ] || while [ -f "$F/readslow" ]; do sleep 0.1; done ;;
esac
EOF
# ps: the real one, except that a process list (-A) keeps only this run's processes (their command
# lines name ${ROOT}): another test on the machine telling its own b1 would make b1 here look busy to
# wait --lead's resend_busy.
# shellcheck disable=SC2016 # the stub's own shell expands $*
printf '#!/bin/sh\ncase " $* " in *" -A "*) %s "$@" | grep -F "%s"; exit 0 ;; esac\nexec %s "$@"\n' \
  "$(command -v ps)" "${ROOT}" "$(command -v ps)" > "${ROOT}/bin/ps"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude" "${ROOT}/bin/ps"

mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q
printf 'w:9 b1\nw:10 b1\n' > "${p}/.swarm/state/b1"   # both panes this project opened, as start_agent records them
printf '2026-10-27\tcode\tb1\tclaude\topus\thigh\tsb\n' > "${p}/.swarm/agents.tsv"

# state <busy|idle> [pane] — b1 in [pane] (w:9), its session and herdr's status both <busy|idle>; - for
# no b1 at all (its pane closed).
state() {
  if [[ "${2:-w:9}" == - ]]; then : > "${ROOT}/agents"; echo '[]' > "${ROOT}/claude.json"; return; fi
  echo "[{\"sessionId\": \"sb\", \"status\": \"$1\"}]" > "${ROOT}/claude.json"
  echo "b1 ${2:-w:9} $([[ "$1" == busy ]] && echo working || echo idle)" > "${ROOT}/agents"
}
# fresh — a new case: no prompts, events, queue or lead line, the last check ended.
fresh() { settle; rm -rf "${Q}" "${p}/.swarm/lead" "${p}/.swarm/events.tsv" "${LOG}"; : > "${ROOT}/keys.log"; : > "${ROOT}/reads.log"; }
# tell <text> — tell b1 findings (or ${KIND}) holding <text>; its output, then `rc=<exit>`. With
# VIA="<pane> <from> <token>", as the check runs it to deliver a queued tell. With TQ_CALLER=slow, one
# the stub stalls in its pane read while ${ROOT}/readslow exists.
tell() {
  local rc=0 out m
  m="$(mktemp "${ROOT}/msg.XXXXXX")"; echo "$1" > "${m}"
  out="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 SWARM_NOTE_WAKE_SECS=1 SWARM_TELL_QUEUED="${VIA:-}" \
    TQ_CALLER="${TQ_CALLER:-}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell b1 "${KIND:-findings}" "${m}" 2>&1)" || rc=$?
  printf '%s rc=%s' "${out}" "${rc}"
}
prompts() { grep -c '^agent prompt ' "${ROOT}/keys.log" || true; }
sent() { grep -qF -- "$1" "${ROOT}/keys.log" && echo yes || echo no; }
# EVENT_AWK: agents.sh's EVENT_OUTCOME_AWK, read by sourcing it as swarm.sh does: outcome($5) is the
# outcome without its key=value tail (a refusal's state=).
EVENT_AWK="$(PROJECT_DIR="${ROOT}/src" bash -c 'source "$1/agents.sh"; printf %s "${EVENT_OUTCOME_AWK}"' _ "${HERE}/../bin/lib")"
# outcomes — the outcome of each tell:findings line for b1 in events.tsv, in order, joined by |.
outcomes() { awk -F'\t' "${EVENT_AWK}"' $2 == "tell:findings" && $3 == "b1" { printf "%s%s", (n++ ? "|" : ""), outcome($5) }' "${p}/.swarm/events.tsv" 2>/dev/null; }
# rounds — b1's findings rounds as findings_told counts them: its tell:findings lines logged ok, or
# whose outcome says herdr sent them, read without the round= verdict= tail.
rounds() { awk -F'\t' '$2 == "tell:findings" && $3 == "b1" { o = $5; sub(/ ~~ .*/, "", o); if (o == "ok" || o ~ /herdr sent it the brief/) n++ } END { print n + 0 }' "${p}/.swarm/events.tsv" 2>/dev/null; }
# verdicts — b1's tell:findings lines whose tail carries verdict=findings
verdicts() { awk -F'\t' '$2 == "tell:findings" && $3 == "b1" && $5 ~ / ~~ .*verdict=findings/ { n++ } END { print n + 0 }' "${p}/.swarm/events.tsv" 2>/dev/null; }
LOG="${CLAUDE_PROJECTS_DIR}/p/sb.jsonl"   # b1's session log
lead() { (cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 TQ_CALLER=lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait --lead 0 2>&1) || true; }
QUEUED="queued: b1 (busy); delivered when its turn ends, so do not tell it again"
REPLACED="replaced: b1's findings tell, by a newer one sent or queued meanwhile; not sent"

fresh; state busy
check "a findings tell to a busy builder: queued, exit 0" "${QUEUED} rc=0" "$(tell "fix round one")"
check "a findings tell to a busy builder: nothing sent" 0 "$(prompts)"
check "a findings tell to a busy builder: logged as queued, not ok, so no round yet" "${QUEUED}|0" "$(outcomes)|$(rounds)"
sleep 2.5   # two looks
check "while the builder stays busy, the check sends nothing" 0 "$(prompts)"
state idle; settle
check "once the builder is idle: delivered once" 1 "$(prompts)"
check "once the builder is idle: the findings, from the conductor" "yes yes" "$(sent "From the conductor:") $(sent "fix round one")"
check "once the builder is idle: its own tell logged ok, so the round count rises once" "${QUEUED}|ok|1" "$(outcomes)|$(rounds)"
check "once the builder is idle: nothing left queued, its time recorded" "b1.findings.sent" "$(ls "${Q}" 2>/dev/null)"

fresh; state busy
tell "fix round one" >/dev/null
touch "${ROOT}/listfail"; sleep 2.5; rm -f "${ROOT}/listfail"   # two looks with no list from herdr
state idle; settle
check "a look herdr gave no agent list drops nothing: delivered once the builder is idle" "1 yes" "$(prompts) $(sent "fix round one")"

fresh; state busy
tell "fix round A" >/dev/null; tell "fix round B" >/dev/null
state idle; settle
check "two findings tells queued for a busy builder: one prompt" 1 "$(prompts)"
check "two findings tells queued for a busy builder: only the newer is delivered" "yes no" "$(sent "fix round B") $(sent "fix round A")"
check "two findings tells queued for a busy builder: one round" 1 "$(rounds)"

fresh; state busy
mkdir -p "${Q}"; echo "$(date +%s) held" > "${Q}/b1.later"   # a check pending, so this queue starts none
tell "fix round A" >/dev/null
state idle
check "findings told at once to the builder, now idle: sent" "told b1 rc=0" "$(tell "fix round B")"
rm -f "${Q}/b1.later"; state busy
KIND=nudge tell "carry on" >/dev/null   # its check would send findings still queued, the older first
state idle; settle
check "findings told at once replace the queued ones: never sent after them" "2 yes yes no" \
  "$(prompts) $(sent "fix round B") $(sent "carry on") $(sent "fix round A")"
check "findings told at once replace the queued ones: one round" 1 "$(rounds)"

fresh; state idle
mkdir -p "${Q}/b1.lock"; printf 'b1 w:9 conductor\nfix round A\n' > "${Q}/b1.findings"   # another tell holds the queue's lock
out="$(tell "fix round B")"; rmdir "${Q}/b1.lock"
check "findings told at once while the queue's lock is held: refused, nothing sent, the queued ones kept" "yes 0 yes" \
  "$([[ "${out}" == *"b1 was not told: its queue's lock ("*") could not be taken, so a findings tell queued earlier could not be replaced"*"rc=1" ]] && echo yes || echo no) $(prompts) $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no)"

# Two tells overlap. The older reads the builder busy, then stalls in its read of the pane (the stub
# waits for ${ROOT}/readslow to go) while the builder goes idle and a newer tell is sent at once. The
# older then takes the queue's lock, finds a tell of its kind sent since it read the state, and is
# dropped: never queued behind the newer one, never sent after it.
fresh; state busy; touch "${ROOT}/readslow"
TQ_CALLER=slow tell "fix round older" > "${ROOT}/older.out" &
older=$!
until_ok grep -q '^slow | agent read' "${ROOT}/reads.log" || true   # the older tell has read busy, and waits in its pane read
state idle
check "two tells overlap, the newer sent at once while the older stalls: the newer is sent" "told b1 rc=0" "$(tell "fix round newer")"
rm -f "${ROOT}/readslow"; wait "${older}" || true
check "the older, finding one sent since it read the state: replaced, not queued, no check started, exit 0" "${REPLACED} rc=0 no no" \
  "$(cat "${ROOT}/older.out") $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no) $([[ -e "${Q}/b1.later" ]] && echo yes || echo no)"
check "the older, dropped: one prompt, the newer, one round" "1 yes no 1" "$(prompts) $(sent "fix round newer") $(sent "fix round older") $(rounds)"
check "the older, dropped: logged replaced, not ok" "ok|${REPLACED}" "$(outcomes)"

# The same with the builder busy throughout: the newer tell is queued while the older stalls. The older
# finds a newer one queued since it read the state and is dropped; the newer is delivered once idle.
fresh; state busy; touch "${ROOT}/readslow"
TQ_CALLER=slow tell "fix round older" > "${ROOT}/older.out" &
older=$!
until_ok grep -q '^slow | agent read' "${ROOT}/reads.log" || true
check "two tells overlap, the newer queued while the older stalls: the newer is queued" "${QUEUED} rc=0" "$(tell "fix round newer")"
rm -f "${ROOT}/readslow"; wait "${older}" || true
check "the older, finding a newer one queued since it read the state: replaced, and the newer kept" "${REPLACED} rc=0|fix round newer" \
  "$(cat "${ROOT}/older.out")|$(tail -n +2 "${Q}/b1.findings" 2>/dev/null)"
state idle; settle
check "the older, dropped: the newer delivered once, one round" "1 yes no 1" "$(prompts) $(sent "fix round newer") $(sent "fix round older") $(rounds)"

# A tell sent at once that read the state before the time in b1.findings.sent (the last of its kind sent
# at once), or in a queued one's line, is the older: it is dropped, and a queued newer one is kept.
fresh; state idle; mkdir -p "${Q}"
after="$(python3 -c 'import time; print(time.time_ns() + 60 * 10**9)')"   # a tell that read the state after this case's does
echo "${after}" > "${Q}/b1.findings.sent"
check "findings told at once, older than the last sent at once: replaced, nothing sent" "${REPLACED} rc=0 0" "$(tell "fix round older") $(prompts)"
rm -f "${Q}/b1.findings.sent"; printf 'b1 w:9 conductor %s\nfix round newer\n' "${after}" > "${Q}/b1.findings"
check "findings told at once, older than one queued: replaced, nothing sent, the queued one kept" "${REPLACED} rc=0 0 yes" \
  "$(tell "fix round older") $(prompts) $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no)"

# order <a> <b> — yes when herdr got a prompt holding <a> before one holding <b>.
order() { local a b; a="$(grep -n -F -- "$1" "${ROOT}/keys.log" | head -1 | cut -d: -f1)"; b="$(grep -n -F -- "$2" "${ROOT}/keys.log" | head -1 | cut -d: -f1)"; [[ -n "${a}" && -n "${b}" && ${a} -lt ${b} ]] && echo yes || echo "no (${a:-none} ${b:-none})"; }

# A queued tell's delivery has claimed it and is sending it (herdr's prompt waits) when a newer tell
# reads the builder idle: the newer is queued behind it, not sent at once, and lands after it.
fresh; state busy
tell "fix round A" >/dev/null
touch "${ROOT}/promptslow"; state idle
until_ok compgen -G "${Q}/b1.findings.claimed.*" >/dev/null || true   # the check's delivery claimed it, and waits in herdr's prompt
later_time() { local t; t="$(cut -d' ' -f1 "${Q}/b1.later" 2>/dev/null)"; echo "${t:-0}"; }
t0="$(later_time)"
check "findings told at once while a queued one's delivery is sending: queued behind it, nothing sent at once" "${QUEUED} rc=0 yes 0" \
  "$(tell "fix round B") $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no) $(prompts)"
sleep 2.5; t1="$(later_time)"
check "findings told at once while a queued one's delivery is sending: its check stays stamped live through the delivery" yes \
  "$([[ ${t1} -gt ${t0} ]] && echo yes || echo "no (${t0} ${t1})")"
rm -f "${ROOT}/promptslow"; settle
check "findings told at once while a queued one's delivery is sending: the older lands first, two rounds in that order" "2 yes 2" \
  "$(prompts) $(order "fix round A" "fix round B") $(rounds)"

# The same with the older sent at once: it is marked on its way (b1.findings.direct.<pid>) until it ends.
fresh; state idle; touch "${ROOT}/promptslow"
tell "fix round A" > "${ROOT}/a.out" &
apid=$!
until_ok compgen -G "${Q}/b1.findings.direct.*" >/dev/null || true
check "findings told at once while another is being sent at once: queued behind it, nothing more sent" "${QUEUED} rc=0 yes 0" \
  "$(tell "fix round B") $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no) $(prompts)"
WAITS="queued: b1 (a findings tell is already on its way to it); sent at the next look"
until_ok grep -qF "${WAITS}" "${p}/.swarm/events.tsv" || true   # B's check looked while A was still on its way
check "a queued one's delivery that meets a tell sent at once on its way: waits for the next look, sends nothing" "yes 0" \
  "$(grep -qF "${WAITS}" "${p}/.swarm/events.tsv" && echo yes || echo no) $(prompts)"
rm -f "${ROOT}/promptslow"; wait "${apid}" || true; settle
check "findings told at once while another is being sent at once: the first lands first, its mark gone, two rounds" "told b1 rc=0|2 yes 2|no" \
  "$(cat "${ROOT}/a.out")|$(prompts) $(order "fix round A" "fix round B") $(rounds)|$(compgen -G "${Q}/b1.findings.direct.*" >/dev/null && echo yes || echo no)"

# A mark whose process is dead holds nothing up: a tell killed sending leaves a .direct, a check that
# died leaves a .claimed. The tell goes, the dead .direct is removed, the .claimed is left for the lead.
fresh; state idle; mkdir -p "${Q}"
: > "${Q}/b1.findings.direct.999999"; printf 'b1 w:9 conductor\nfix round stale\n' > "${Q}/b1.findings.claimed.t9"
check "findings told at once past marks whose processes are dead: sent, the dead .direct removed, the .claimed kept for the lead" "told b1 rc=0 1 no yes" \
  "$(tell "fix round C") $(prompts) $([[ -e "${Q}/b1.findings.direct.999999" ]] && echo yes || echo no) $([[ -e "${Q}/b1.findings.claimed.t9" ]] && echo yes || echo no)"

fresh; state idle
mkdir -p "${Q}"; printf 'b1 w:9 conductor\nfix round A\n' > "${Q}/b1.findings.sending.t1"   # on its way, as the check takes it
check "findings told at once while a queued one is on its way: sent" "told b1 rc=0" "$(tell "fix round B")"
check "the queued one's delivery, after them: sends nothing" "replaced: b1's queued findings tell, by a newer one; not sent rc=0" \
  "$(VIA="w:9 conductor t1" tell "fix round A")"
check "the queued one's delivery, after them: one prompt, the newer, one round" "1 yes no 1" \
  "$(prompts) $(sent "fix round B") $(sent "fix round A") $(rounds)"
check "the queued one's delivery, after them: logged replaced, not ok" "ok|replaced: b1's queued findings tell, by a newer one; not sent" "$(outcomes)"
fresh; state busy
mkdir -p "${Q}"; printf 'b1 w:9 conductor\nfix round left\n' > "${Q}/b1.findings.sending.t0"   # a check died sending it
KIND=nudge tell "carry on" >/dev/null   # the next queued tell starts a check
state idle; settle
check "a tell a dead check left on its way: the next check sends it, then the rest" "2 yes yes" \
  "$(prompts) $(sent "fix round left") $(sent "carry on")"

fresh; state busy
mkdir -p "${Q}"; printf 'b1 w:9 conductor 1700000000000000000\nfix round A\n' > "${Q}/b1.findings.sending.t1"   # its line's fourth word: when it read the state
check "a queued tell's delivery that finds the builder busy again: sends nothing" "${QUEUED} rc=0 0" "$(VIA="w:9 conductor t1" tell "fix round A") $(prompts)"
check "a queued tell's delivery that finds the builder busy again: leaves it on its way, for its check to put back" yes \
  "$([[ -e "${Q}/b1.findings.sending.t1" && ! -e "${Q}/b1.findings" ]] && echo yes || echo no)"
state idle
check "a queued tell's delivery that claims it: sent, from the sender that queued it" "told b1 rc=0 1 yes" \
  "$(VIA="w:9 review t1" tell "fix round A") $(prompts) $(sent "From the review agent:")"
check "a queued tell's delivery that claims it: records its time as the last of its kind that went" 1700000000000000000 "$(cat "${Q}/b1.findings.sent" 2>/dev/null)"

fresh; state idle   # two checks overlap: a stalled one's delivery (t1) after a newer tell went on its way (t2)
mkdir -p "${Q}"; printf 'b1 w:9 conductor\nfix round newer\n' > "${Q}/b1.findings.sending.t2"
check "a delivery whose tell another check's newer one replaced: sends nothing, leaves the newer on its way" \
  "replaced: b1's queued findings tell, by a newer one; not sent rc=0 0 yes" \
  "$(VIA="w:9 conductor t1" tell "fix round older") $(prompts) $([[ -e "${Q}/b1.findings.sending.t2" ]] && echo yes || echo no)"

fresh; state busy
tell "fix round one" >/dev/null
state idle -; settle
check "a queued tell to a builder whose pane closed: sent to no pane" 0 "$(prompts)"
out="$(lead)"
U="${Q}/b1.findings.undelivered"
# alert <wait --lead's output> — yes when it is the one line for b1's dropped findings (its drop time aside).
alert() { [[ "$1" == "tell undelivered: b1 findings at "*" (b1 is no longer in pane w:9), exit: if it still applies, swarm.sh tell b1 findings ${U}.md; then rm ${U} ${U}.md" && "$1" != *$'\n'* ]] && echo yes || echo "no: $1"; }
check "a queued tell to a builder whose pane closed: wait --lead prints its line for the lead" yes "$(alert "${out}")"
check "a queued tell to a builder whose pane closed: its text is kept for the lead" "fix round one" "$(cat "${U}.md" 2>/dev/null)"
check "a queued tell to a builder whose pane closed: logged undelivered, no round" "${QUEUED}|undelivered: b1 is no longer in pane w:9|0" "$(outcomes)|$(rounds)"
state busy; tell "fix round two" >/dev/null; state idle -; settle   # dropped the same way, after the lead saw the first
check "a second drop of the kind, for the same reason, wakes the lead again with its text" "yes|fix round two" "$(alert "$(lead)")|$(cat "${U}.md" 2>/dev/null)"

fresh; state busy
tell "fix round one" >/dev/null
state idle w:10; settle   # a new b1, idle in another pane
check "a queued tell to a builder whose name a new pane holds: not sent to that pane" 0 "$(prompts)"
check "a queued tell to a builder whose name a new pane holds: wait --lead prints its line" yes "$(alert "$(lead)")"

# With the ladder on, the next findings round is a step-up's (round 3 of the build, sonnet,opus,fable)
# or a top-rung hold's (round 2 on the top rung: b1 runs opus, sonnet,opus), and a step-up, restart or
# hold of b1 holds the story's lock: the queued findings go back in the queue, never to the lead,
# until the lock is gone.
for how in "a step-up:sonnet,opus,fable:2" "a top-rung hold:sonnet,opus:1"; do
  what="${how%%:*}" ladder="${how#*:}" prior="${how##*:}" ladder="${ladder%:*}"
  fresh; state busy
  echo "escalate_ladder = ${ladder}" > "${p}/.claude/swarm/config"
  for ((r = 1; r <= prior; r++)); do printf '2026-10-27T09:0%s:00Z\ttell:findings\tb1\t-\tok\n' "${r}" >> "${p}/.swarm/events.tsv"; done
  mkdir -p "${p}/.swarm/locks/step-up-b1"; echo "$$" > "${p}/.swarm/locks/step-up-b1/pid"
  tell "fix round three" >/dev/null
  state idle
  # Its delivery meets the lock (its tell's own line says so), then the check puts it back or drops it.
  until_ok grep -q $'\ttell:findings\tb1\t.*of it is running' "${p}/.swarm/events.tsv" || true
  back_or_dropped() { [[ -e "${Q}/b1.findings" ]] || compgen -G "${Q}/*.undelivered" >/dev/null; }
  until_ok back_or_dropped || true
  check "queued findings due ${what} while the story's lock is held: not sent, queued again, no line for the lead" "0 yes no" \
    "$(prompts) $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no) $(compgen -G "${Q}/*.undelivered" >/dev/null && echo yes || echo no)"
  : > "${p}/.claude/swarm/config"; rm -rf "${p}/.swarm/locks"; settle
  check "queued findings due ${what} while the story's lock was held: sent once it is gone" "1 yes" "$(prompts) $(sent "fix round three")"
done

fresh; state busy
tell "fix round one" >/dev/null
touch "${ROOT}/nosend"; state idle; settle; rm -f "${ROOT}/nosend"   # herdr sends it, and no turn ever shows
check "a queued findings tell herdr sent and never showed taken up: sent twice, as any tell, and one round" "2 1" "$(prompts) $(rounds)"
check "a queued findings tell herdr sent and never showed taken up: its one round's line carries verdict=findings" 1 "$(verdicts)"
check "a queued findings tell herdr sent and never showed taken up: wait --lead says it may have arrived, never to send it as findings again" yes \
  "$(grep -qF "herdr sent it the brief twice" <<< "$(lead)" && grep -qF "exit: it may have arrived, so do as that says and never send it again as findings; then rm ${U} ${U}.md" "${U}" && echo yes || echo no)"

# A queued delivery herdr refuses as blocked before sending anything, whose pane then cannot be read
# (the stub's read prints nothing): herdr sent nothing, so the lead is told to send it again if it
# still applies, not that it may have arrived.
fresh; state busy
tell "fix round blocked" >/dev/null
touch "${ROOT}/blocked"; state idle; settle; rm -f "${ROOT}/blocked"
check "a queued tell herdr refused as blocked before sending it, its pane unreadable: to the lead as never sent, to send again" "yes|fix round blocked|0" \
  "$([[ "$(lead)" == "tell undelivered: b1 findings at "*"(b1: herdr did not send it the brief: it is blocked on a question (agent_blocked); answer it, see herdr agent read b1; its pane could not be read), exit: if it still applies, swarm.sh tell b1 findings ${U}.md; then rm ${U} ${U}.md" ]] && echo yes || echo no)|$(cat "${U}.md" 2>/dev/null)|$(rounds)"
check "a queued findings tell herdr never sent counts no round: no line carries verdict=findings" 0 "$(verdicts)"

# A builder at its prompt with a test running in the background: Claude Code lists it busy, its session
# log ends on the reply that ended its turn. Mid-turn (its log ends on a prompt) the tell waits.
fresh; state busy
printf '%s\n' '{"type":"user","message":{"content":"run the tests in the background"}}' > "${LOG}"
tell "fix round background" >/dev/null
sleep 2.5   # a look or two mid-turn
check "a builder busy mid-turn: its queued tell waits" 0 "$(prompts)"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"The tests run in the background."}]}}' >> "${LOG}"
settle
check "a builder at its prompt with a background shell (busy, its turn over): gets the queued tell" "1 yes" "$(prompts) $(sent "fix round background")"

# A check that dies (its pane closed, a restart, an update) leaves its queued tell to wait --lead.
fresh; state busy
tell "fix round stranded" >/dev/null
read -r _ _ pid < "${Q}/b1.later"
dead() { ! kill -0 "$1" 2>/dev/null; }
kill -9 "${pid}" 2>/dev/null; until_ok dead "${pid}" || true
out="$(lead)"
check "a queued tell whose check died: wait --lead hands it to the lead, never sent" "yes|fix round stranded|no|0" \
  "$([[ "${out}" == "tell undelivered: b1 findings at "*" (its queue's check has stopped (its process ended: a closed pane, a restart or a plugin update), so it was never sent), exit: if it still applies, swarm.sh tell b1 findings ${U}.md; then rm ${U} ${U}.md" ]] && echo yes || echo "no: ${out}")|$(cat "${U}.md" 2>/dev/null)|$([[ -e "${Q}/b1.findings" ]] && echo yes || echo no)|$(prompts)"

# A tell a delivery claimed (.claimed.<token>) whose check then stopped: wait --lead hands it to the lead as
# one that may have arrived, never to be sent again.
fresh; state busy
mkdir -p "${Q}"; printf 'b1 w:9 conductor\nfix round claimed\n' > "${Q}/b1.findings.claimed.t3"   # no check holds .later
check "a tell claimed when its check stopped: wait --lead says it may have arrived, never to send it again" "yes|fix round claimed" \
  "$([[ "$(lead)" == "tell undelivered: b1 findings at "*" (its check stopped while a delivery of it ran, so b1 may or may not have the brief), exit: it may have arrived, so do as that says and never send it again as findings; then rm ${U} ${U}.md" ]] && echo yes || echo no)|$(cat "${U}.md" 2>/dev/null)"

# The same with a newer tell queued behind the claimed one: the lead has one line per kind, and it is the
# newer's, never sent, not the older's over it.
fresh; state busy
mkdir -p "${Q}"; printf 'b1 w:9 conductor\nfix round claimed older\n' > "${Q}/b1.findings.claimed.t3"; printf 'b1 w:9 conductor\nfix round newer queued\n' > "${Q}/b1.findings"
check "a stopped check's claimed tell with a newer one queued behind it: the lead sees the newer, never sent" "yes|fix round newer queued" \
  "$([[ "$(lead)" == "tell undelivered: b1 findings at "*" (its queue's check has stopped (its process ended: a closed pane, a restart or a plugin update), so it was never sent), exit: if it still applies, swarm.sh tell b1 findings ${U}.md; then rm ${U} ${U}.md" ]] && echo yes || echo no)|$(cat "${U}.md" 2>/dev/null)"

# herdr giving the check no agent list look after look: after TELL_LIST_TRIES (5) looks in a row it hands
# the tell to the lead, never sent.
fresh; state busy
tell "fix round no list" >/dev/null
touch "${ROOT}/listfail"; settle; rm -f "${ROOT}/listfail"
check "a queued tell whose check never gets an agent list: to the lead after five looks, never sent" "yes|fix round no list|no|0" \
  "$([[ "$(lead)" == "tell undelivered: b1 findings at "*" (herdr gave its check no agent list for 5 looks in a row, so it was never sent), exit: if it still applies, swarm.sh tell b1 findings ${U}.md; then rm ${U} ${U}.md" ]] && echo yes || echo no)|$(cat "${U}.md" 2>/dev/null)|$([[ -e "${Q}/b1.findings" ]] && echo yes || echo no)|$(prompts)"

# Each check counts those looks afresh: a count a check that ended left behind (its queue emptied
# before a look got a list) does not hand the next check's tell to the lead short of five.
fresh; state busy
mkdir -p "${Q}"; echo 4 > "${Q}/b1.listfail"   # left by a check that ended one look short of five
tell "fix round fresh count" >/dev/null
touch "${ROOT}/listfail"; sleep 2.5; rm -f "${ROOT}/listfail"   # a look or two with no list: five with the count left, else one or two
state idle; settle
check "a new check counts looks with no agent list afresh: a count a check that ended left does not hand its tell to the lead" "1 yes no" \
  "$(prompts) $(sent "fix round fresh count") $(compgen -G "${Q}/*.undelivered" >/dev/null && echo yes || echo no)"

# A delivery whose own tell fails before it claims the tell (here herdr cannot list its agents for it)
# puts it back, TELL_QUEUE_TRIES (3) times, then hands it to the lead.
fresh; state busy
tell "fix round unreachable" >/dev/null
touch "${ROOT}/childfail"; state idle; settle; rm -f "${ROOT}/childfail"
check "a queued tell whose delivery fails before claiming it: three tries, then to the lead, never sent" "3|yes|0" \
  "$(no_version < "${p}/.swarm/events.tsv" | awk -F'\t' '$2 == "tell:findings" && $3 == "b1" && $5 == "tell: b1 was not told: herdr could not list its agents; tell it again" { n++ } END { print n + 0 }')|$([[ "$(lead)" == "tell undelivered: b1 findings at "*"; its delivery failed before sending it 3 times), exit: if it still applies, swarm.sh tell b1 findings ${U}.md; then rm ${U} ${U}.md" ]] && echo yes || echo no)|$(prompts)"

# A delivery that fails before claiming its tell while a newer tell replaces it on its way
# (${ROOT}/childreplace): nothing goes to the lead, so the older findings are never offered again.
fresh; state busy
tell "fix round older" >/dev/null
touch "${ROOT}/childreplace"; state idle; settle; rm -f "${ROOT}/childreplace"
check "a delivery that fails before claiming a tell a newer one replaced on its way: nothing to the lead, nothing sent" "no|0" \
  "$(compgen -G "${Q}/*.undelivered" >/dev/null && echo yes || echo no)|$(prompts)"

# The check is its own process (swarm.sh _tell-queue-check), so wait --lead's resend pass still reads the
# pane of an agent herdr lists idle while a tell waits for it (its session busy).
fresh; state busy
printf '2026-10-27T09:00:00Z\tstory\tb1\t-\tok\n' > "${p}/.swarm/events.tsv"   # its brief went in
tell "fix round later" >/dev/null
echo "b1 w:9 idle" > "${ROOT}/agents"   # herdr: idle; its session: busy
lead >/dev/null
check "a tell queued for an agent: wait --lead's resend pass still reads its pane" yes \
  "$(grep -q '^lead | agent read w:9' "${ROOT}/reads.log" && echo yes || echo no)"

# With goal on, queued findings that reach the builder and then hit a goal failure count as a round, and
# the lead is told they were delivered, never to send them again.
fresh; state busy; echo "goal = 4" > "${p}/.claude/swarm/config"
tell "fix round goal" >/dev/null
touch "${ROOT}/goalwait"; state idle; settle; rm -f "${ROOT}/goalwait"; : > "${p}/.claude/swarm/config"
check "queued findings delivered whose goal then failed: one prompt, one round, and the lead told not to resend" "1 1 yes" \
  "$(prompts) $(rounds) $([[ "$(lead)" == "tell goal failed: b1 findings at "*" (b1: the findings were delivered, but its builder is waiting on permission prompt, so no /goal was sent"*"), exit: the findings were delivered and count as a round, and only their goal failed, so never send them again; then rm ${U} ${U}.md" ]] && echo yes || echo no)"

# A tell to an agent with no pane, or whose session has ended (gone), is refused once as could not
# reach, naming its exit by its role: a story's builder's wait --lead no-agent: line, a review agent's
# no-review: line, a conductor's next no conductor started: line, and for any other agent (skeptic-e1)
# the command that started it. A note to a conductor whose pane is open and whose session is gone is
# refused too, and its inbox stays empty. review-x is a story's builder (its agents.tsv role and story
# file), whatever its name says; conduct-e2 has no agents.tsv line, so its name decides. herdr lists
# another project's agent meanwhile: a list with no agents at all proves nothing.
printf '2026-10-27\treview\treview-b1\tclaude\topus\thigh\tsr\n2026-10-27\tconduct\tconduct-e1\tclaude\topus\thigh\tsc\n2026-10-27\tcode\treview-x\tclaude\topus\thigh\tsx\n2026-10-27\tskeptic\tskeptic-e1\tclaude\topus\thigh\tsk\n' >> "${p}/.swarm/agents.tsv"
printf 'w:11 review-b1\nw:12 conduct-e1\nw:13 review-x\nw:14 conduct-e2\nw:15 skeptic-e1\n' > "${p}/.swarm/state/e1"
printf -- '---\nstatus: ready\n---\n' > "${p}/docs/stories/b1.md"; cp "${p}/docs/stories/b1.md" "${p}/docs/stories/review-x.md"
# tell_to <name> <kind> — tell <name> <kind> a file; its output, then `rc=<exit>`.
tell_to() {
  local rc=0 out m
  m="$(mktemp "${ROOT}/msg.XXXXXX")"; echo "look again" > "${m}"
  out="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell "$1" "$2" "${m}" 2>&1)" || rc=$?
  printf '%s rc=%s' "${out}" "${rc}"
}
# told <name> <kind> — each tell:<kind> outcome events.tsv logged for <name>, without its tail, joined by |.
told() { awk -F'\t' -v c="tell:$2" -v n="$1" "${EVENT_AWK}"' $2 == c && $3 == n { printf "%s%s", (k++ ? "|" : ""), outcome($5) }' "${p}/.swarm/events.tsv" 2>/dev/null; }
FINAL="this refusal is final, so do not tell it again"
NOAGENT="swarm.sh wait --lead's no-agent: line names its exit"
NOREVIEW="swarm.sh wait --lead's no-review: line names its exit"
NOCOND="swarm.sh next starts a new conductor, or its no conductor started: line says why not"
OTHER="it is no story's builder, review agent or conductor, so no swarm.sh line names its exit: start it again with the command that started it, or tell the user"
NOPANE="no agent this project started holds the name"
GONE="its Claude session has ended (gone)"
for c in "b1 findings ${NOAGENT}" "review-b1 nudge ${NOREVIEW}" "conduct-e1 note ${NOCOND}" "review-x nudge ${NOAGENT}" "conduct-e2 note ${NOCOND}" "skeptic-e1 nudge ${OTHER}"; do
  read -r who kind exit <<< "${c}"
  fresh; echo '[]' > "${ROOT}/claude.json"; echo "other w:99 idle" > "${ROOT}/agents"   # no pane of this project's holds it
  check "a ${kind} tell to ${who} with no pane: one could-not-reach refusal naming its exit, exit 1" \
    "swarm: could not reach ${who}: ${NOPANE}; ${FINAL}: ${exit} rc=1" "$(tell_to "${who}" "${kind}")"
  check "a ${kind} tell to ${who} with no pane: one tell:${kind} event, the refusal" \
    "could not reach ${who}: ${NOPANE}; ${FINAL}: ${exit}" "$(told "${who}" "${kind}")"
done
for c in "b1 w:9 findings ${NOAGENT}" "review-b1 w:11 nudge ${NOREVIEW}" "conduct-e1 w:12 note ${NOCOND}" "skeptic-e1 w:15 nudge ${OTHER}"; do
  read -r who pane kind exit <<< "${c}"
  fresh; echo '[]' > "${ROOT}/claude.json"; echo "${who} ${pane} idle" > "${ROOT}/agents"   # its pane open, its session gone
  open="its pane ${pane} is still open: read it (herdr agent read ${who}) and close it; after that, ${exit}"
  check "a ${kind} tell to ${who}, its session gone: one could-not-reach refusal naming its open pane, then its exit, exit 1" \
    "swarm: could not reach ${who}: ${GONE}; ${FINAL}: ${open} rc=1" "$(tell_to "${who}" "${kind}")"
  check "a ${kind} tell to ${who}, its session gone: one tell:${kind} event, the refusal, no ok, nothing sent" \
    "could not reach ${who}: ${GONE}; ${FINAL}: ${open}|0" "$(told "${who}" "${kind}")|$(prompts)"
done
check "a note to a conductor whose session is gone: its inbox gets nothing" no \
  "$(compgen -G "${p}/.swarm/inbox/*" >/dev/null && echo yes || echo no)"
rm -f "${p}/docs/stories/b1.md" "${p}/docs/stories/review-x.md"
AGAIN="swarm: tell: b1 was not told: herdr could not list its agents; tell it again rc=1"
fresh; state idle; touch "${ROOT}/listfail"
check "a tell while herdr cannot list its agents: refused as one to send again, never as could not reach" \
  "${AGAIN}|0" "$(tell_to b1 findings)|$(prompts)"
rm -f "${ROOT}/listfail"
fresh; state idle -
check "a tell while herdr lists no agents at all: refused as one to send again, never as could not reach" \
  "${AGAIN}|0" "$(tell_to b1 findings)|$(prompts)"
fresh; state busy
check "a tell to a live busy builder: queued, exit 0, no refusal logged" "${QUEUED} rc=0|${QUEUED}" "$(tell "fix round live")|$(told b1 findings)"

# A queued findings tell whose builder's session then ends goes to the lead once: three wait --lead
# polls print one tell undelivered: line, and log no further tell:findings line after the first.
fresh; state busy
tell "fix round gone" >/dev/null
echo '[]' > "${ROOT}/claude.json"; echo "b1 w:9 idle" > "${ROOT}/agents"; settle
polls="$(lead)"; n1="$(told b1 findings | tr '|' '\n' | grep -c . || true)"
polls="${polls}"$'\n'"$(lead)"$'\n'"$(lead)"; n3="$(told b1 findings | tr '|' '\n' | grep -c . || true)"
check "a queued tell to a builder whose session ended: three wait --lead polls, one tell undelivered: line, no new tell:findings line" \
  "1 ${n1}" "$(grep -c '^tell undelivered: b1 findings ' <<< "${polls}" || true) ${n3}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
