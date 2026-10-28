#!/usr/bin/env bash
# nudge_idle_test.sh — nobody sends a nudge to an agent that is still working. Every nudge instruction
# gives one form, run in the background: the conductor brief's
# `swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>`, and commands/swarm.md's the
# same without --stall. wait --idle exits 0 only when the wait prints idle or done. The test renders the
# conductor briefs (an epic's and the backlog's), counts the spans that tell a nudge there and in
# swarm.md, and checks each is its file's form. Then it runs each distinct form, its placeholders filled
# and its wait cut to a few seconds from the default hour, against stub builders. One busy past the
# wait's timeout, one whose session is gone (wait exits 0 on gone) and, for the brief's form, one whose
# wait --stall ends stalled and one whose stall finds another step-up running (stepping up:, exit 0)
# get no tell attempt: no tell:nudge row in events.tsv, no herdr prompt. An idle one is told. A form that
# drops the wait, its && or --idle tries a tell on a builder that is not idle (tell queues it or
# refuses it, and logs the row either way), so the test goes red.
# herdr, claude and gh are stubs on PATH, and so is swarm.sh, which runs this checkout's.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
p="${ROOT}/proj"; Q="${p}/.swarm/tells"
# A tell the form should never have sent leaves a check behind it: empty its queue, so the check ends at
# its next look, and wait (20 s at most) for its .later to go before removing the tree.
cleanup() {
  local i
  rm -f "${Q:?}"/*.nudge
  for ((i = 0; i < 100; i++)); do compgen -G "${Q}/*.later" >/dev/null || break; sleep 0.2; done
  rm -rf "${ROOT:?}"
}
trap cleanup EXIT
export HOME="${ROOT}/home" CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
mkdir -p "${HOME}" "${ROOT}/bin" "${CLAUDE_PROJECTS_DIR}"
cp "${HERE}/claude_stub.sh" "${ROOT}/bin/claude"
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: logs every call. A conductor start gets panes and tabs; agent list prints ${ROOT}/agents
# (`<name> <pane> <status>`); agent wait wakes at once, so wait reads the session's state each slice;
# agent prompt is logged to ${ROOT}/keys.log.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       echo '{"result":{"root_pane":{"pane_id":"w:90"}}}' ;;
  "tab list")         echo '{"result":{"tabs":[]}}' ;;
  "pane list")        echo '{"result":{"panes":[]}}' ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, $3 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "agent get")        printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(awk -v p="$3" '$2 == p { print $3 }' "$H/agents")" ;;
  "agent wait")       echo '{"result":{"agent":{"agent_status":"done"}}}' ;;
  "agent read")       echo '⏺ Working on the story.' ;;
  "agent prompt")     echo "$*" >> "$H/keys.log"; echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
printf '#!/bin/sh\nexec bash "%s" "$@"\n' "${SWARM}" > "${ROOT}/bin/swarm.sh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude" "${ROOT}/bin/gh" "${ROOT}/bin/swarm.sh"

GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
item() { # <path> <front-matter line>...
  local path="$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
mkdir -p "${p}/.claude/swarm" "${p}/.swarm/state"
printf 'repos_dir = %s\n' "${ROOT}" > "${p}/.claude/swarm/config"
"${GIT[@]}" init -q "${p}"
mkdir -p "${p}/docs/stories"; : > "${p}/docs/stories/README.md"   # the mark of a board
item "${p}/docs/epics/e.md" "status: active"
run() { (cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }

# --- The conductor briefs, written before the conductor starts, whatever the stub makes of the start.
run conduct e >/dev/null || true
run conduct --backlog >/dev/null || true
: > "${ROOT}/agents"
BRIEF_E="${p}/.swarm/briefs/conduct-e.md"; BRIEF_B="${p}/.swarm/briefs/conduct-backlog.md"
check "both conductor briefs are written" "yes|yes" "$([[ -s "${BRIEF_E}" ]] && echo yes)|$([[ -s "${BRIEF_B}" ]] && echo yes)"

# forms <file> <wait> — "<spans in the form> of <spans that tell a nudge>", over <file> with its lines
# joined, the form being `swarm.sh <wait> <x> && swarm.sh tell <x> nudge <file>` followed by " in the
# background". A span is the text between two backticks; one tells a nudge when it holds `tell <x> nudge`.
forms() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = " ".join(open(sys.argv[1]).read().split())
spans = re.findall(r"`([^`]*)`", text)
nudges = [s for s in spans if re.search(r"\btell \S+ nudge\b", s)]
form = re.compile(r"swarm\.sh %s (<[a-z]+>) && swarm\.sh tell \1 nudge <[^>]+>" % re.escape(sys.argv[2]))
good = [s for s in nudges if form.fullmatch(s) and ("`%s` in the background" % s) in text]
print("%d of %d" % (len(good), len(nudges)))
PY
}
SWARM_MD="${HERE}/../commands/swarm.md"
# The epic brief's three (the clash, stacked and give-up rules), the backlog's the same, and the lead's
# four in swarm.md (the unsent-brief and conflict arms, and the restart rule's two).
check "every nudge instruction in the epic conductor brief is wait --stall --idle, then tell, in the background" "3 of 3" "$(forms "${BRIEF_E}" "wait --stall --idle")"
check "every nudge instruction in the backlog conductor brief is wait --stall --idle, then tell, in the background" "3 of 3" "$(forms "${BRIEF_B}" "wait --stall --idle")"
check "every nudge instruction in commands/swarm.md is wait --idle, then tell, in the background" "4 of 4" "$(forms "${SWARM_MD}" "wait --idle")"

# --- Run the forms. Builders, each in a pane this project recorded: nb-busy busy throughout, nb-stall
# busy with no sign of life in its worktree for two hours, nb-gone listed by herdr with no Claude
# session left, nb-idle idle.
"${GIT[@]}" init -q "${ROOT}/svc"
item "${p}/docs/stories/nb-stall.md" "status: ready" "kind: code" "repo: svc" "epic: e"
old=$(($(date +%s) - 7200))
"${GIT[@]}" init -q "${ROOT}/svc-wt/nb-stall"
GIT_COMMITTER_DATE="@${old}" "${GIT[@]}" -C "${ROOT}/svc-wt/nb-stall" commit -q --allow-empty -m old
n=1
for b in nb-busy nb-stall nb-gone nb-idle; do
  printf 'w:%s %s\n' "${n}" "${b}" > "${p}/.swarm/state/${b}"
  printf '2026-10-28\tcode\t%s\tclaude\topus\thigh\ts-%s\n' "${b}" "${b}" >> "${p}/.swarm/agents.tsv"
  n=$((n + 1))
done
printf 'nb-busy w:1 working\nnb-stall w:2 working\nnb-gone w:3 idle\nnb-idle w:4 idle\n' > "${ROOT}/agents"
echo '[{"sessionId":"s-nb-busy","status":"busy"},{"sessionId":"s-nb-stall","status":"busy"},{"sessionId":"s-nb-idle","status":"idle"}]' > "${CLAUDE_STUB_AGENTS}"

# distinct <file> — the distinct forms <file> gives, each placeholder made <slug> or <file>, one per line.
distinct() {
  python3 - "$1" <<'PY'
import re, sys
text = " ".join(open(sys.argv[1]).read().split())
seen = []
for s in re.findall(r"`([^`]*)`", text):
    if re.search(r"\btell \S+ nudge\b", s):
        s = re.sub(r"<(slug|child)>", "<slug>", s)
        s = re.sub(r"nudge <[^>]+>$", "nudge <file>", s)
        if s not in seen:
            seen.append(s)
print("\n".join(seen))
PY
}
distinct "${BRIEF_E}" > "${ROOT}/forms-brief"; distinct "${SWARM_MD}" > "${ROOT}/forms-lead"
check "the epic brief gives one nudge form, and swarm.md one" "1|1" "$(grep -c . "${ROOT}/forms-brief")|$(grep -c . "${ROOT}/forms-lead")"

WAIT_MS=3000
CONFIG="${p}/.claude/swarm/config"; BASE_CONFIG="$(cat "${CONFIG}")"
LOCK="${p}/.swarm/locks/step-up-nb-stall"
# nudge <form> <builder> [env...] — run <form> for <builder> as its sender would, from the project, with
# its wait cut to WAIT_MS: "<the first 8 characters it printed>|exit <rc>".
nudge() {
  local cmd="$1" b="$2" rc=0 out; shift 2
  echo "merge origin/main in and push (${b})" > "${ROOT}/nudge-${b}.md"
  # The wait's timeout, after its slug. Split, not ${cmd/.../...}: bash 5.2 reads & in a replacement as
  # the matched text, which would mangle the &&.
  [[ "${cmd}" != *" && "* ]] || cmd="${cmd%% && *} ${WAIT_MS} && ${cmd#* && }"
  cmd="${cmd//<slug>/${b}}"; cmd="${cmd//<file>/${ROOT}/nudge-${b}.md}"
  out="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 SWARM_NOTE_WAKE_SECS=1 SWARM_STALL_POLL_MS=1000 \
    PATH="${ROOT}/bin:${PATH}" "$@" bash -c "${cmd}" 2>/dev/null)" || rc=$?
  printf '%s|exit %s' "$(head -1 <<< "${out}" | cut -c1-8)" "${rc}"
}
# tells <builder> — the outcome of each tell:nudge row for <builder>, joined by |.
tells() { awk -F'\t' -v b="$1" '$2 == "tell:nudge" && $3 == b { printf "%s%s", (n++ ? "|" : ""), $5 }' "${p}/.swarm/events.tsv"; }
# prompts <builder> — herdr prompts that carried <builder>'s nudge.
prompts() { grep -c "(${1})" "${ROOT}/keys.log" || true; }
# fresh — each case's own rows: no events, prompts or queued nudges, the config as set up.
fresh() { : > "${p}/.swarm/events.tsv"; : > "${ROOT}/keys.log"; rm -f "${Q:?}"/*.nudge; echo "${BASE_CONFIG}" > "${CONFIG}"; }

# common <form> — the cases every form meets: busy to the timeout, a gone session, idle.
common() {
  fresh
  check "a builder busy past the wait's timeout: the wait fails, and no tell is tried" "busy|exit 1||0" \
    "$(nudge "$1" nb-busy)|$(tells nb-busy)|$(prompts nb-busy)"
  check "a builder whose session is gone: wait --idle exits 5, and no tell is tried" "gone|exit 5||0" \
    "$(nudge "$1" nb-gone)|$(tells nb-gone)|$(prompts nb-gone)"
  check "an idle builder is told the nudge" "idle|exit 0|ok|1" \
    "$(nudge "$1" nb-idle)|$(tells nb-idle)|$(prompts nb-idle)"
}
while IFS= read -r form; do
  [[ -n "${form}" ]] || continue
  echo "     brief form: ${form}"
  common "${form}"
  check "a builder whose wait ends stalled: no tell is tried" "stalled:|exit 3||0" \
    "$(nudge "${form}" nb-stall SWARM_WAIT_STARTED="${old}")|$(tells nb-stall)|$(prompts nb-stall)"
  # With the ladder on, the stall finds another step-up of nb-stall running (its lock held by this
  # shell): wait prints stepping up: and exits 0, and --idle makes that 5.
  fresh; echo "escalate_ladder = sonnet,opus" >> "${CONFIG}"
  mkdir -p "${LOCK}"; echo "$$" > "${LOCK}/pid"
  check "a stall another step-up already handles (stepping up:, exit 0): wait --idle exits 5, and no tell is tried" "stepping|exit 5||0" \
    "$(nudge "${form}" nb-stall SWARM_WAIT_STARTED="${old}")|$(tells nb-stall)|$(prompts nb-stall)"
  rm -f "${LOCK:?}/pid"; rmdir "${LOCK}"
done < "${ROOT}/forms-brief"
while IFS= read -r form; do
  [[ -n "${form}" ]] || continue
  echo "     swarm.md form: ${form}"
  common "${form}"
done < "${ROOT}/forms-lead"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
