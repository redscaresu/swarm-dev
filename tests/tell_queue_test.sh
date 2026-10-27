#!/usr/bin/env bash
# tell_queue_test.sh — `tell b1 findings <file>` to a builder that Claude Code lists as busy (herdr:
# working) is queued, not refused: it prints queued:, exits 0 and logs the tell as queued, not ok. A
# check left in the background looks once a minute (SWARM_NOTE_WAKE_SECS, 1 here): while the builder
# stays busy nothing is sent, and once it is idle the findings go through a tell of their own, logged
# ok, so they are delivered once and count as one findings round. Two findings tells queued for one
# busy builder deliver only the newer. A look while herdr's list fails (${ROOT}/listfail) drops
# nothing. A tell sent at once to an idle builder replaces a queued one of its kind, which is never
# sent after it (a pending check's .later keeps the queue from starting one until the direct tell is
# done; a nudge queued next starts the check that would send what is left), nor is one already on its
# way (b1.findings.sending.<token>, as the check's take leaves it): its delivery, run as the check
# runs it (VIA), finds it gone and sends nothing. A delivery that finds the builder busy again leaves
# it on its way, for the check to put back, and one that claims it sends it. One a dead check left on
# its way is sent by the next check, and a delivery never claims another check's tell (its token). A
# direct tell that cannot take the queue's lock to replace a queued one sends nothing. A queued tell
# to a builder whose pane closed, or whose name a new pane holds, is sent to no pane: it is dropped,
# and wait --lead prints a tell undelivered: line for the lead, again for a later drop of its kind.
# One herdr sent but never showed taken up (${ROOT}/nosend: no status in its reply, idle on every
# read) is not to be sent again as findings: its line says it may have arrived, and it counts as one
# round. Queued findings due a step-up or a top-rung hold while the story's lock is held go back in
# the queue.
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
# settle — wait (60 s at most) for the check a queued tell left to end: it removes its .later.
settle() { local i; for ((i = 0; i < 300; i++)); do compgen -G "${Q}/*.later" >/dev/null || return 0; sleep 0.2; done; }
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
    awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
    { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, $3 }
    END { print "]}}" }' "$F/agents" ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(awk -v p="$3" '$2 == p { print $3 }' "$F/agents")" ;;
  "agent prompt") echo "$*" >> "$F/keys.log"; [ -f "$F/nosend" ] || echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

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
fresh() { settle; rm -rf "${Q}" "${p}/.swarm/lead" "${p}/.swarm/events.tsv"; : > "${ROOT}/keys.log"; }
# tell <text> — tell b1 findings (or ${KIND}) holding <text>; its output, then `rc=<exit>`. With
# VIA="<pane> <from> <token>", as the check runs it to deliver a queued tell.
tell() {
  local rc=0 out
  echo "$1" > "${ROOT}/msg"
  out="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 SWARM_NOTE_WAKE_SECS=1 SWARM_TELL_QUEUED="${VIA:-}" \
    PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell b1 "${KIND:-findings}" "${ROOT}/msg" 2>&1)" || rc=$?
  printf '%s rc=%s' "${out}" "${rc}"
}
prompts() { grep -c '^agent prompt ' "${ROOT}/keys.log" || true; }
sent() { grep -qF -- "$1" "${ROOT}/keys.log" && echo yes || echo no; }
# outcomes — the outcome of each tell:findings line for b1 in events.tsv, in order, joined by |.
outcomes() { awk -F'\t' '$2 == "tell:findings" && $3 == "b1" { printf "%s%s", (n++ ? "|" : ""), $5 }' "${p}/.swarm/events.tsv" 2>/dev/null; }
# rounds — b1's findings rounds as findings_told counts them: its tell:findings lines logged ok, or
# whose outcome says herdr sent them.
rounds() { awk -F'\t' '$2 == "tell:findings" && $3 == "b1" && ($5 == "ok" || $5 ~ /herdr sent it the brief/) { n++ } END { print n + 0 }' "${p}/.swarm/events.tsv" 2>/dev/null; }
lead() { (cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait --lead 0 2>&1) || true; }
QUEUED="queued: b1 (busy); delivered when its turn ends, so do not tell it again"

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
check "once the builder is idle: nothing left queued" "" "$(ls "${Q}" 2>/dev/null)"

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
  "$([[ "${out}" == *"b1 was not told: its findings tell queued earlier could not be replaced"*"rc=1" ]] && echo yes || echo no) $(prompts) $([[ -e "${Q}/b1.findings" ]] && echo yes || echo no)"

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
mkdir -p "${Q}"; printf 'b1 w:9 conductor\nfix round A\n' > "${Q}/b1.findings.sending.t1"
check "a queued tell's delivery that finds the builder busy again: sends nothing" "${QUEUED} rc=0 0" "$(VIA="w:9 conductor t1" tell "fix round A") $(prompts)"
check "a queued tell's delivery that finds the builder busy again: leaves it on its way, for its check to put back" yes \
  "$([[ -e "${Q}/b1.findings.sending.t1" && ! -e "${Q}/b1.findings" ]] && echo yes || echo no)"
state idle
check "a queued tell's delivery that claims it: sent, from the sender that queued it" "told b1 rc=0 1 yes" \
  "$(VIA="w:9 conductor t1" tell "fix round A") $(prompts) $(sent "From the conductor:")"

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
check "a queued findings tell herdr sent and never showed taken up: wait --lead says it may have arrived, never to send it as findings again" yes \
  "$(grep -qF "herdr sent it the brief twice" <<< "$(lead)" && grep -qF "exit: it may have arrived, so do as that says and never send it again as findings; then rm ${U} ${U}.md" "${U}" && echo yes || echo no)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
