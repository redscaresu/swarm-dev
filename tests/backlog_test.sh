#!/usr/bin/env bash
# backlog_test.sh — `swarm.sh conduct --backlog`: the backlog conductor for the ready stories with no
# epic. Its brief (scope, waves, review, merge rule by merge mode), its refusal on a board with an
# epics/backlog.md, and how `next` waits on it and collects it. herdr, gh and claude are stubs on PATH.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
# The user's settings allow swarm.sh merge, so a conductor may start under merge = agent (merge_rule_stop).
mkdir -p "${CLAUDE_CONFIG_DIR}"; echo '{"permissions":{"allow":["Bash(swarm.sh merge *)"]}}' > "${CLAUDE_CONFIG_DIR}/settings.json"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
hasnt() { if grep -qF -- "$1" <<< "$2"; then echo "has '$1'"; else echo no; fi; }
# para <pattern> <text> — the paragraph of <text> that starts on the line matching <pattern>.
para() { awk -v pat="$1" 'index($0, pat) { on = 1 } on && /^$/ { exit } on' <<< "$2"; }
item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: logs every call; each new pane is w:<n>, each tab t<n>; agent start and list track agents.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "t$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent start")      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "pane close"|"tab close") p=$3; [ "$1" = tab ] && p="w:${3#t}"
                      [ -e "$H/agents" ] && awk -v p="$p" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
git -C "${p}" init -q
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
item "${b}" epics/e.md "status: active"
item "${b}" stories/s1.md "status: ready" "kind: code" "epic: e"
item "${b}" stories/o1.md "status: ready" "kind: code"
brief="${p}/.swarm/briefs/conduct-backlog.md"

# --- unblock --startable: o1 is running (its worktree exists) and o2 is ready with no build, as a board
# PR adds one: unblock readies neither, so it prints no ready: line.
mkdir -p "${ROOT}/proj-wt/o1"
item "${b}" stories/o2.md "status: ready" "kind: code"
check "unblock --startable --backlog lists the ready story with no epic and no build, not the running one" "startable: o2" \
  "$(run unblock --startable --backlog)"
check "unblock --startable <epic> lists only that epic's ready stories with no build" "startable: s1" "$(run unblock --startable e)"
check "unblock --startable with no scope is refused" "yes" "$(has "--startable takes <epic> or --backlog" "$(run unblock --startable || true)")"
check "unblock --startable refuses a third argument and a slug that is not [a-z0-9-]" "yes|yes" \
  "$(has "--startable takes <epic> or --backlog" "$(run unblock --startable e --backlog || true)")|$(has "--startable takes <epic> or --backlog" "$(run unblock --startable ../e || true)")"
# An epic whose file is gone has finished: unblock still runs (bx, blocked on the finished fin, is
# readied), then nothing is startable; a bare backlog is such an epic, never --backlog.
item "${b}" stories/bx.md "status: blocked" "kind: code" "epic: other" "depends_on: [fin]"
check "unblock --startable of an epic whose file is gone runs unblock, then lists nothing and exits 0; a bare backlog is that, not --backlog" "ready: bx|0|" \
  "$(run unblock --startable gone)|$(run unblock --startable gone >/dev/null; echo $?)|$(run unblock --startable backlog)"
# st depends on o1, still open (running): it starts stacked on it. rp's last event is reconcile's reopen
# (its PR closed unmerged), which the lead decides on.
item "${b}" stories/st.md "status: ready" "kind: code" "depends_on: [o1]"
item "${b}" stories/rp.md "status: ready" "kind: code" "prs: https://github.com/o/r/pull/9"
printf '2026-10-22T10:00:00Z\treconcile\trp\t-\tok (reopened)\n' >> "${p}/.swarm/events.tsv"
check "unblock --startable marks a story stacked on an open parent, and one whose PR closed unmerged" \
  "startable: o2|startable: rp (its PR https://github.com/o/r/pull/9 was closed unmerged)|startable: st (stacked on o1)" \
  "$(run unblock --startable --backlog | paste -sd'|' -)"
rm -r "${ROOT}/proj-wt/o1" "${b}/stories/o2.md" "${b}/stories/bx.md" "${b}/stories/st.md" "${b}/stories/rp.md"
# A board PR merged on GitHub: --startable reads the board as reconcile last left it and never fetches,
# so the upstream's new n1 is not listed and the checkout's upstream ref has not moved.
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q --bare "${ROOT}/up.git"; g clone -q "${ROOT}/up.git" "${ROOT}/up"
mkdir -p "${ROOT}/up/.claude/swarm" "${ROOT}/up/docs/stories"; : > "${ROOT}/up/.claude/swarm/config"
g -C "${ROOT}/up" add -A; g -C "${ROOT}/up" commit -qm init; g -C "${ROOT}/up" push -q origin HEAD
g clone -q "${ROOT}/up.git" "${ROOT}/ff"
item "${ROOT}/up/docs" stories/n1.md "status: ready" "kind: code"
g -C "${ROOT}/up" add -A; g -C "${ROOT}/up" commit -qm "board PR"; g -C "${ROOT}/up" push -q origin HEAD
was="$(git -C "${ROOT}/ff" rev-parse '@{upstream}')"
check "unblock --startable never fetches or pulls: the upstream's new story is not listed and the upstream ref is unchanged" "|same" \
  "$(cd "${ROOT}/ff" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" unblock --startable --backlog 2>/dev/null)|$([[ "$(git -C "${ROOT}/ff" rev-parse '@{upstream}')" == "${was}" ]] && echo same || echo moved)"

# --- A board with an epic named backlog: conduct --backlog starts nothing.
item "${b}" epics/backlog.md "status: active"
out="$(run conduct --backlog || echo "exit $?")"
check "with an epics/backlog.md, conduct --backlog fails naming it, and starts nothing" "yes|yes|no|no" \
  "$(has "exit 1" "${out}")|$(has "epics/backlog.md" "${out}")|$(grep -q '^agent start' "${ROOT}/herdr.log" 2>/dev/null && echo yes || echo no)|$([[ -e "${brief}" ]] && echo yes || echo no)"
out="$(run conduct backlog || echo "exit $?")"
check "conduct backlog (an epic of that name) is refused too, and starts nothing" "yes|no" \
  "$(has "exit 1" "${out}")|$(grep -q '^agent start' "${ROOT}/herdr.log" 2>/dev/null && echo yes || echo no)"
rm "${b}/epics/backlog.md"

# --- merge = human: the brief, and next waiting on it, then collecting it.
run conduct --backlog >/dev/null
bl="$(cat "${brief}" 2>/dev/null || true)"
bn="$(sed -n 's/^agent start \(conduct-backlog-[^ ]*\) .*/\1/p' "${ROOT}/herdr.log" | head -1)"
check "conduct --backlog starts conduct-backlog-<project dir>-<path hash> in a workspace labelled <project> · backlog" "yes|yes" \
  "$([[ "${bn}" =~ ^conduct-backlog-proj-[0-9a-f]{6}$ ]] && echo yes || echo "no, got: ${bn}")|$(has "workspace create --label proj · backlog " "$(cat "${ROOT}/herdr.log")")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the backlog brief names stories with no epic:, story --strict and watch --backlog" "yes|yes|yes|yes" \
  "$(has 'You are the backlog conductor: you build the ready stories on the board with no `epic:`.' "${bl}")|$(has 'Start only stories with no `epic:`, and leave every epic and its stories alone.' "${bl}")|$(has 'swarm.sh story --strict <slug>' "${bl}")|$(has 'swarm.sh watch --backlog` in the background' "${bl}")"
check "the backlog brief has no epic file, no epic scope and no 'of this epic'" "no|no|no|no" \
  "$(hasnt "epics/backlog.md" "${bl}")|$(hasnt "Stay inside this epic" "${bl}")|$(hasnt "of this epic" "${bl}")|$(hasnt "or verify" "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the backlog brief never runs story for a started story, and reports one it could not start or whose build died" "yes|yes|yes|0" \
  "$(has 'has already started: never
run `swarm.sh story` for it again.' "${bl}")|$(has 'report it as not started, with the reason `build died`.' "${bl}")|$(has 'one line each:
`not started: <slug> (<the refusal'"'"'s first line>)`.' "${bl}")|$(grep -c 'swarm.sh story <slug>' <<< "${bl}" || true)"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = human, the backlog brief leaves the handover to the review agent, never runs swarm.sh merge, and stops only once no agent work is left" "yes|no|yes|no" \
  "$(has 'A story'"'"'s review agent hands its PR to the user itself, with `swarm.sh review`, unless an HLD' "${bl}")|$(hasnt "swarm.sh merge --" "${bl}")|$(has 'ends `finish: the backlog has no agent work left` says none is' "$(tr -s '[:space:]' ' ' <<< "${bl}")")|$(hasnt "swarm.sh review <epic>" "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = human, a refusal naming another one-off in review is reported as not started, not waited on" "yes" \
  "$(has "Report the
refused story as \`not started: <slug> (waits on <other>'s merge)\`." "${bl}")"
# startable_bl <brief> — the startable rule after a merge, after an inbox note and after each wait, and
# no wording that starts only what unblock readied.
startable_bl() {
  local b; b="$(tr -s '[:space:]' ' ' <<< "$1")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  echo "$(grep -oF 'run `swarm.sh unblock --startable --backlog`, and start each story it prints as `startable:` (every ready backlog story whose build has not started, whether or not this unblock readied it) that clashes with no running one, with `swarm.sh story --strict <slug>`. It reads the board as reconcile last left it, and never pulls. Skip a story you closed in this wave (the give-up rule starts it again in a later one), one the give-up rule says not to start again, and one a `not held:` line left `ready` for the lead. Never start a line that ends `(its PR <url> was closed unmerged)`: list it in your report for the lead.' <<< "${b}" | wc -l | tr -d ' ')|$(has 'If that last pass read a note, then run `swarm.sh unblock --startable --backlog`' "${b}")|$(grep -qE 'start what it readies|it prints as `ready:`|starts? (only )?(the )?stories (its own )?unblock readie' <<< "${b}" && echo limited || echo no)"
}
check "with merge = human, the backlog conductor starts every ready story with no epic and no build after a merge and after a note" "3|yes|no" "$(startable_bl "${bl}")"
check "the backlog conductor reports to conduct-backlog.report.md" "yes" "$(has "${p}/.swarm/conduct-backlog.report.md" "${bl}")"
nx="$(run next)"
check "with the backlog conductor alive, next waits on it" "wait ${bn}" "${nx%%$'\n'*}"
echo reported > "${p}/.swarm/conduct-backlog.report.md"; TZ=UTC touch -t 202610010800 "${p}/.swarm/conduct-backlog.report.md"
nx="$(run next)"
check "once the backlog conductor has reported, next collects it" "collect ${bn}" "${nx%%$'\n'*}"
run close "${bn}" >/dev/null
run close conduct-e >/dev/null   # next started it: e has a ready story and no conductor

# --- The epic conductor's brief: the same review paragraph, and no 'or verify'. The paragraph starts each
# PR's review agent once and leaves it alone: if a brief again waits on reviews, tells findings or logs
# them, the review agent and the conductor would both drive one PR, and these go red.
run conduct e >/dev/null
eb="$(cat "${p}/.swarm/briefs/conduct-e.md")"
check "the backlog brief's review paragraph is the epic conductor's" "same" \
  "$([[ -n "$(para "A story is reviewed only by" "${bl}")" && "$(para "A story is reviewed only by" "${bl}")" == "$(para "A story is reviewed only by" "${eb}")" ]] && echo same || echo differs)"
check "the epic conductor keeps its scope and drops 'or verify'" "yes|no" "$(has "Stay inside this epic" "${eb}")|$(hasnt "or verify" "${eb}")"
for which in bl eb; do
  rflat="$(tr -s '[:space:]' ' ' <<< "$(para "A story is reviewed only by" "${!which}")")"; all="$(tr -s '[:space:]' ' ' <<< "${!which}")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  check "the ${which} brief's review paragraph starts review-agent on watch's opened line, on queued: and for a kept: PR, and never waits on a PR or a review agent" "yes|yes|yes|yes" \
    "$(has '`<repo> #<n> story/<slug> opened`, a PR of yours has opened: start its review agent once, at once, with `'"${SWARM}"' review-agent <slug> <PR URL>`.' "${rflat}")|$(has '`queued: <repo> #<n> <branch> green <m>m with no review on <sha>`, that head has had no review: start its review agent then, the same way.' "${rflat}")|$(has 'lists as `kept:` (a close kept its PR unreviewed) gets one the same way' "${rflat}")|$(has 'Never wait on a PR or a review agent' "${rflat}")"
  check "the ${which} brief never waits on a review agent, tells findings, logs a declined finding or reviews the moment a head is green" "0|0|0|0" \
    "$(grep -c 'swarm.sh wait review-<slug>' <<< "${all}" || true)|$(grep -c 'tell <slug> findings' <<< "${all}" || true)|$(grep -c 'log-finding --declined' <<< "${all}" || true)|$(grep -c "The moment a story's PR head is green" <<< "${all}" || true)"
done
check "the conductor briefs have no batch wording" "no|no|no|no" \
  "$(hasnt batch "${eb}${bl}")|$(hasnt "later round" "${eb}${bl}")|$(hasnt "wait for any" "${eb}${bl}")|$(hasnt "Do not wait for other PRs" "${eb}${bl}")"
check "with merge = human, the epic conductor still puts the epic in review" "yes" "$(has "swarm.sh review <epic> <every PR URL still waiting>" "${eb}")"
run close conduct-e >/dev/null

# --- merge = agent: the conductor merges each pinned head.
echo "merge = agent" > "${p}/.claude/swarm/config"
run conduct --backlog >/dev/null
check "a conduct that removes an earlier run's report logs the report's time first, for outcomes' held_min" "ok (2026-10-01T08:00:00Z)|gone" \
  "$(awk -F'\t' '$2 == "report" && $3 == "backlog" { print $5 }' "${p}/.swarm/events.tsv")|$([[ -e "${p}/.swarm/conduct-backlog.report.md" ]] && echo there || echo gone)"
bl="$(cat "${brief}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the backlog conductor waits on its own one-off's merge, as an epic's does, unless it costs money" "yes" \
  "$(has 'If the refusal ends `(costs money)`, only the user merges the named story, maybe days later: do not wait for it, and report yours as `not started: <slug> (waits on <other>'"'"'s merge)`.' "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the backlog conductor also stops when CI on the base timed out or is red with no fix-main line" "yes" \
  "$(has 'that you may start is left and none is running, or when CI on the base timed out, or is red with no `fix-main:` line.' "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the backlog brief leaves the merge to the review agent, starts unblocked stories with no epic, and finishes no epic" "yes|yes|no|no" \
  "$(has "A story's review agent merges its PR itself, with \`swarm.sh merge\`: never merge a story's PR yourself." "$(tr -s '[:space:]' ' ' <<< "${bl}")")|$(has 'start each story it prints as `startable:` (every ready backlog story whose build has not started' "${bl}")|$(hasnt "of this epic" "${bl}")|$(hasnt "swarm.sh finish <epic>" "${bl}")"

check "with merge = agent, the backlog conductor starts every ready story with no epic and no build after a merge and after a note" "3|yes|no" "$(startable_bl "${bl}")"
run close "${bn}" >/dev/null
run conduct e >/dev/null
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the epic conductor still finishes the epic" "yes" "$(has '`swarm.sh finish <epic>` only on a board outside the repo' "$(cat "${p}/.swarm/briefs/conduct-e.md")")"

# --- An epic conductor's workspace: the epic's parent:, read as the template writes it (a trailing
# comment) or quoted, else the epic's own slug.
item "${b}" epics/c1.md "status: active" "parent: big-epic            # only on a child epic of a split one"
item "${b}" epics/c2.md "status: active" 'parent: "big-epic"'
item "${b}" stories/c1s.md "status: ready" "kind: code" "epic: c1"
item "${b}" stories/c2s.md "status: ready" "kind: code" "epic: c2"
item "${b}" epics/solo.md "status: active"
item "${b}" stories/solos.md "status: ready" "kind: code" "epic: solo"
: > "${ROOT}/herdr.log"
o1="$(run conduct c1 || echo "exit $?")"; o2="$(run conduct c2 || echo "exit $?")"; o3="$(run conduct solo || echo "exit $?")"
check "conduct names the workspace <project> · a commented or quoted parent:, else the epic" "yes|yes|yes|2|yes" \
  "$(has "workspace proj · big-epic (w)" "${o1}")|$(has "workspace proj · big-epic (w)" "${o2}")|$(has "workspace proj · solo (w)" "${o3}")|$(grep -c 'workspace create --label proj · big-epic ' "${ROOT}/herdr.log")|$(has "workspace create --label proj · solo " "$(cat "${ROOT}/herdr.log")")"

# --- The clash check between two backlog stories compares parts: a bare file does not clash with a
# part of it, the same part does. Built in svc, a repo beside the project with a main on its remote.
g -c init.defaultBranch=main init -q --bare "${ROOT}/svc.git"; g clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
g -C "${ROOT}/svc" commit -q --allow-empty -m init && git -C "${ROOT}/svc" push -q origin HEAD:main
item "${b}" stories/kopen.md "status: review" "kind: code" "repo: svc" "touches: [bin/swarm.sh:load_config]"
item "${b}" stories/kbare.md "status: ready" "kind: code" "repo: svc" "touches: [bin/swarm.sh]"
item "${b}" stories/kpart.md "status: ready" "kind: code" "repo: svc" "touches: [bin/swarm.sh:load_config and the dispatch]"
rc1=0; out1="$(run story --strict kbare)" || rc1=$?; rc2=0; out2="$(run story --strict kpart)" || rc2=$?
check "story --strict between backlog stories starts one whose bare file the open one names a part of, and refuses one naming the same part" \
  "0|no|fail|yes" "${rc1}|$(hasnt "kopen" "${out1}")|$([[ ${rc2} -ne 0 ]] && echo fail || echo ok)|$(has "kpart: kopen (epic none) is open and touches bin/swarm.sh:load_config" "${out2}")"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
