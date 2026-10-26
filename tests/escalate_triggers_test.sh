#!/usr/bin/env bash
# escalate_triggers_test.sh — with escalate_ladder set, swarm.sh runs step-up itself on each of the four
# triggers: a close of a builder with no PR (no-pr), a wait --stall that finds it stalled (stalled), a
# third findings tell (findings-3), and checks finishing red on a second head of its PR (ci-red-2).
# With the ladder empty none does. conduct_brief names the step-ups only with the ladder on. herdr, gh
# and claude (tests/claude_stub.sh) are stubs on PATH; gh's answers come from files under the root.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TZ=UTC
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}" "${ROOT}/projects"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false)
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: logs every call; panes are w:<n>; agents lists "<name> <pane>" lines, all idle, until the
# tab closes; agent wait returns at once. With quick, a started session's first turn has ended by the
# time anyone reads it: the brief writes an assistant entry in its log, a second passes, and Claude
# Code lists it idle; a /goal writes its goal_status set entry. process-info prints pi when it exists.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/herdr"
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 10) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"}]}}' ;;
  "tab close")    : > "$H/agents" ;;
  "agent start")  [ -e "$H/startfail" ] && { echo "start refused" >&2; exit 1; }
                  echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p' > "$H/sid"
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") if [ -e "$H/quick" ] && [ -s "$H/sid" ]; then
                    sid=$(cat "$H/sid"); mkdir -p "$CLAUDE_PROJECTS_DIR/p"
                    python3 -c 'import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
t = sys.argv[1]
if t.startswith("/goal "):
    print(json.dumps({"type": "attachment", "timestamp": now, "attachment": {"type": "goal_status", "met": False, "sentinel": True, "condition": t[6:]}}))
else:
    print(json.dumps({"type": "assistant", "timestamp": now, "message": {"model": "m", "content": []}}))' "$4" >> "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl"
                    case "$4" in "/goal "*) ;; *) sleep 1; echo "[{\"sessionId\":\"$sid\",\"status\":\"idle\"}]" > "$CLAUDE_STUB_AGENTS" ;; esac
                  fi
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "pane process-info") [ -e "$H/pi" ] && cat "$H/pi" ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
# gh: story/s1 has no PR for close (prs.json), and one open PR whose head is the sha in head for
# watch. A head's one check run failed unless runs-<sha> says otherwise, and it has a commit status
# only when status-<sha> names its state.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/gh"
cat >> "${STUB_BIN}/gh" <<'EOF'
case "$*" in
  "pr list"*"--state all"*) cat "$H/prs.json" ;;
  "api --paginate repos/"*"/pulls?"*) echo "5 $(cat "$H/head") story/s1 $(($(date +%s) - 10))" ;;
  "api repos/"*"/pulls/5 "*) echo MERGEABLE ;;
  "repo view"*other*) echo o/other ;;
  "repo view"*) echo o/proj ;;
  "api --paginate"*check-runs*) sha=$(echo "$*" | sed 's|.*/commits/\([^/]*\)/.*|\1|'); c=$(cat "$H/runs-$sha" 2>/dev/null || echo failure)
    echo "{\"total_count\":1,\"check_runs\":[{\"name\":\"test\",\"status\":\"completed\",\"conclusion\":\"$c\",\"html_url\":\"https://ci/1\"}]}" ;;
  "api --paginate"*status*) sha=$(echo "$*" | sed 's|.*/commits/\([^/]*\)/.*|\1|')
    if [ -e "$H/status-$sha" ]; then echo "{\"total_count\":1,\"statuses\":[{\"context\":\"ext\",\"state\":\"$(cat "$H/status-$sha")\"}]}"
    else echo '{"total_count":0,"statuses":[]}'; fi ;;
  "api"*check-runs*) echo "1 0" ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"
# ps, on PATH only where a case puts PS_BIN there: the builder's pane shell (100) runs claude, whose
# tool shell runs make test, started 10 minutes ago.
PS_BIN="${ROOT}/ps-bin"; mkdir -p "${PS_BIN}"
cat > "${PS_BIN}/ps" <<'EOF'
#!/bin/sh
printf '%s\n' '100 1 2:00:00 -zsh' '200 100 2:00:00 claude' '300 200 10:00 /bin/zsh -c make test' '310 300 10:00 make test'
EOF
chmod +x "${PS_BIN}/ps"

P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
# fresh <ladder> <session state> [model] — a new project whose story s1 is built on sonnet in its worktree
# (one commit, 2 hours old) on [model] (sonnet), its builder open in pane w:1, and escalate_ladder = <ladder>.
fresh() {
  rm -rf "${ROOT}/origin.git" "${P}" "${ROOT}/proj-wt" "${ROOT}/herdr.log" "${ROOT}"/runs-* "${ROOT}"/status-* "${ROOT}/startfail" "${ROOT}/quick" "${ROOT}/sid"; : > "${ROOT}/run.log"
  "${GIT[@]}" init -q --bare "${ROOT}/origin.git"
  "${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
  mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state"
  printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
  "${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
  "${GIT[@]}" -C "${P}" worktree add -q -b story/s1 "${WT}" origin/main
  echo work > "${WT}/work.txt"; "${GIT[@]}" -C "${WT}" add work.txt
  GIT_COMMITTER_DATE="@${OLD}" "${GIT[@]}" -C "${WT}" commit -qm work
  printf '2026-10-01\tcode-sonnet\ts1\tclaude\t%s\thigh\tsess-1\n' "${3:-sonnet}" > "${P}/.swarm/agents.tsv"
  : > "${P}/.swarm/events.tsv"
  echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"
  echo "[{\"sessionId\":\"sess-1\",\"status\":\"$2\"}]" > "${CLAUDE_STUB_AGENTS}"
  echo "escalate_ladder = $1" > "${P}/.claude/swarm/config"
}
OLD=$(($(date +%s) - 7200))
echo '[]' > "${ROOT}/prs.json"
# run — swarm.sh in the project; its output also goes to run.log, which fresh empties.
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w SWARM_STALL_POLL_MS=1000 PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1) | tee -a "${ROOT}/run.log"; }
# stepped — the escalate lines' results, then each step-up that was tried and refused (said in a
# run's output, as a refused automatic step-up is not logged), comma-separated.
stepped() { { awk -F'\t' '$2 == "escalate" { print $5 }' "${P}/.swarm/events.tsv"; sed -n 's/^swarm: step-up: /refused: step-up: /p' "${ROOT}/run.log"; } | paste -sd, -; }
closes() { grep -c $'\tclose\t' "${P}/.swarm/events.tsv" || true; }
findings_tells() { printf '2026-10-18T10:0%s:00Z\ttell:findings\ts1\tw:1\tok\n' 1 2 >> "${P}/.swarm/events.tsv"; echo "fix it" > "${ROOT}/f.md"; }
heads() { local h; for h in "$@"; do echo "${h}" > "${ROOT}/head"; run watch --backlog >/dev/null || true; done; }
attempts() { sed -n 's/^attempts: *//p' "${P}/.swarm/board-state/stories/s1" 2>/dev/null || true; }
escalates() { awk -F'\t' '$2 == "escalate" { print $5 }' "${P}/.swarm/events.tsv" | paste -sd, -; }
# failed_lines — the outcomes of s1's step-up:failed events.tsv lines, comma-separated.
failed_lines() { awk -F'\t' '$2 == "step-up:failed" && $3 == "s1" { print $5 }' "${P}/.swarm/events.tsv" | paste -sd, -; }

for ladder in sonnet,opus,fable ""; do
  want="ok (no-pr: sonnet -> opus)"; [[ -n "${ladder}" ]] || want=""
  fresh "${ladder}" idle; run close s1 >/dev/null || true
  check "ladder '${ladder}': a close with no PR logs idle-no-pr and steps up only with the ladder on" "1|${want}" "$(grep -c 'idle-no-pr' "${P}/.swarm/events.tsv")|$(stepped)"
  check "ladder '${ladder}': a close a step-up took the place of logs no close" "$([[ -n "${ladder}" ]] && echo 0 || echo 1)" "$(closes)"

  want="ok (stalled: sonnet -> opus)"; [[ -n "${ladder}" ]] || want=""
  fresh "${ladder}" busy; out="$(SWARM_WAIT_STARTED="${OLD}" run wait --stall s1 3000)" || true
  if [[ -n "${ladder}" ]]; then
    check "ladder '${ladder}': a stall found by wait --stall steps up, and wait says stepped up, not stalled" "yes|no|${want}" \
      "$(grep -q '^stepped up: s1' <<< "${out}" && echo yes)|$(grep -q '^stalled:' <<< "${out}" && echo yes || echo no)|$(stepped)"
    # The same builder running make test in its pane is working: no stall, so no step-up.
    fresh "${ladder}" busy; echo '{"result":{"process_info":{"pane_id":"w:1","shell_pid":100}}}' > "${ROOT}/pi"
    out="$(SWARM_WAIT_STARTED="${OLD}" PATH="${PS_BIN}:${PATH}" run wait --stall s1 3000)" || true
    rm -f "${ROOT}/pi"
    check "ladder '${ladder}': a builder running make test past stall_minutes is neither stalled nor stepped up" "busy|" "${out}|$(stepped)"
  else
    check "ladder '${ladder}': a stall found by wait --stall is stalled, and steps nothing up" "yes|${want}" \
      "$(grep -q '^stalled:' <<< "${out}" && echo yes)|$(stepped)"
  fi

  fresh "${ladder}" idle; findings_tells; out="$(run tell s1 findings "${ROOT}/f.md")" || true
  if [[ -n "${ladder}" ]]; then
    check "ladder '${ladder}': a third findings tell steps it up instead, the findings in its brief" \
      "ok (findings-3: sonnet -> opus)|yes|yes" \
      "$(stepped)|$(grep -q 'was not told: these were findings round 3' <<< "${out}" && echo yes)|$(grep -qx 'fix it' "${P}/.swarm/briefs/s1.md" && echo yes)"
    fresh "${ladder}" idle; echo "step_up_findings = 2" >> "${P}/.claude/swarm/config"
    printf '2026-10-18T10:01:00Z\ttell:findings\ts1\tw:1\tok\n' >> "${P}/.swarm/events.tsv"; echo "fix it" > "${ROOT}/f.md"
    out="$(run tell s1 findings "${ROOT}/f.md")" || true
    check "ladder '${ladder}': with step_up_findings = 2, the second findings tell steps it up" \
      "ok (findings-2: sonnet -> opus)|yes" "$(stepped)|$(grep -q 'was not told: these were findings round 2' <<< "${out}" && echo yes)"
  else
    check "ladder '${ladder}': a third findings tell is sent" "|yes" "$(stepped)|$(grep -q 'told s1' <<< "${out}" && echo yes)"
    # With the ladder off a step-up lock means nothing: a close goes on and counts the attempt.
    fresh "${ladder}" idle; mkdir -p "${P}/.swarm/locks/step-up-s1"; echo "$$" > "${P}/.swarm/locks/step-up-s1/pid"
    out="$(run close s1)" && rc=0 || rc=$?
    check "ladder '${ladder}': a held step-up lock does not stop a close" "0|no|1" \
      "${rc}|$(grep -q 'another step-up' <<< "${out}" && echo yes || echo no)|$(attempts)"
  fi

  want="ok (ci-red-2: sonnet -> opus)"; [[ -n "${ladder}" ]] || want=""
  fresh "${ladder}" idle
  heads aaaa1111; first="$(stepped)"; heads bbbb2222
  check "ladder '${ladder}': one red head steps nothing, a second steps up only with the ladder on" "|${want}" "${first}|$(stepped)"
  check "ladder '${ladder}': watch keeps red heads only with the ladder on" "$([[ -n "${ladder}" ]] && echo yes || echo no)" \
    "$([[ -s "${P}/.swarm/red-heads.tsv" ]] && echo yes || echo no)"

  if [[ -n "${ladder}" ]]; then
    # A red head of an earlier build (before its newest story line) counts nothing for this one.
    fresh "${ladder}" idle
    printf 's1 old0000 2026-10-01T10:00:00Z red\n' > "${P}/.swarm/red-heads.tsv"
    printf '2026-10-01T11:00:00Z\tstory\ts1\tw:1\tok\n' >> "${P}/.swarm/events.tsv"
    heads aaaa1111
    check "a red head from the story's earlier build does not count toward this build's two" "" "$(stepped)"
    # The PR head an earlier build left, judged red then, is not this build's red head.
    fresh "${ladder}" idle
    printf 's1 aaaa1111 2026-10-01T10:00:00Z red\n' > "${P}/.swarm/red-heads.tsv"
    printf '2026-10-01T11:00:00Z\tescalate\ts1\tw:1\tok (stalled: haiku -> sonnet)\n' >> "${P}/.swarm/events.tsv"
    heads aaaa1111 bbbb2222
    check "the head an earlier build judged red is not counted again for this one" "ok (stalled: haiku -> sonnet)" "$(stepped)"
    # A head still pending when the build was stepped up was there before this build: it never counts.
    fresh "${ladder}" idle
    printf 's1 aaaa1111 2026-10-01T10:00:00Z seen\n' > "${P}/.swarm/red-heads.tsv"
    printf '2026-10-01T11:00:00Z\tescalate\ts1\tw:1\tok (stalled: haiku -> sonnet)\n' >> "${P}/.swarm/events.tsv"
    heads aaaa1111 bbbb2222
    check "a head pending at the step-up, red after it, is not the new build's red head" "ok (stalled: haiku -> sonnet)" "$(stepped)"
    # A step-up refused after ladder_step's check (here the story is no longer ready) is said, is not
    # logged (a refusal is no sign of life), and is not tried again on the same head.
    fresh "${ladder}" idle; sed -i.bak 's/^status: ready$/status: review/' "${P}/docs/stories/s1.md"
    heads aaaa1111 bbbb2222
    { grep -v '^done bbbb2222$' "${P}/.swarm/state/watch-seen" || true; } > "${ROOT}/seen"; cp "${ROOT}/seen" "${P}/.swarm/state/watch-seen"
    heads bbbb2222
    check "a refused step-up is noted on its head, not logged, and not tried again there" "1|0|1" \
      "$(grep -c 'step-up: s1 is not status: ready' "${ROOT}/run.log")|$(grep -c $'\tstep-up\t' "${P}/.swarm/events.tsv" || true)|$(grep -c ' bbbb2222 .* refused$' "${P}/.swarm/red-heads.tsv")"
    # A head whose run was cancelled (a newer push, cancel-in-progress) is not red; the next red one,
    # the PR's head, is the second.
    fresh "${ladder}" idle; echo cancelled > "${ROOT}/runs-bbbb2222"
    heads aaaa1111 bbbb2222; first="$(stepped)"; heads cccc3333
    check "a cancelled head is not red: a third head red after it is the second" "|ok (ci-red-2: sonnet -> opus)" "${first}|$(stepped)"
    # Two red heads, both while the builder was busy fixing, then a third head still running with the
    # builder idle: it is stepped up.
    fresh "${ladder}" busy; heads aaaa1111 bbbb2222; first="$(stepped)"
    echo '[{"sessionId":"sess-1","status":"idle"}]' > "${CLAUDE_STUB_AGENTS}"
    echo success > "${ROOT}/runs-cccc3333"; echo pending > "${ROOT}/status-cccc3333"; heads cccc3333
    check "two red heads, then a third still running with the builder idle, steps up" "|ok (ci-red-2: sonnet -> opus)" "${first}|$(stepped)"
    # Two red heads while the PR's head is green leave the builder be.
    fresh "${ladder}" idle; echo success > "${ROOT}/runs-bbbb2222"; echo pending > "${ROOT}/status-bbbb2222"
    heads aaaa1111 bbbb2222; echo failure > "${ROOT}/status-bbbb2222"; echo success > "${ROOT}/runs-cccc3333"
    heads cccc3333
    check "two red heads with the PR's head green step nothing up" "" "$(stepped)"
    # So does one the builder started by hand (swarm.sh agent) inherits.
    fresh "${ladder}" idle
    printf 's1 old0000 2026-10-01T10:00:00Z red\n' > "${P}/.swarm/red-heads.tsv"
    printf '2026-10-01T11:00:00Z\tagent\ts1\tw:1\tok\n' >> "${P}/.swarm/events.tsv"
    heads aaaa1111
    check "a builder started with swarm.sh agent is a new build: earlier red heads count nothing" "" "$(stepped)"
    # Two watches that both judged one head left two red lines for it: it counts once.
    fresh "${ladder}" idle
    printf '%s\n' 's1 aaaa1111 2026-10-18T00:00:00Z red' 's1 aaaa1111 2026-10-18T00:00:00Z red' > "${P}/.swarm/red-heads.tsv"
    heads aaaa1111
    check "one red head judged twice counts once" "" "$(stepped)"
    # Two red heads on a PR whose builder is closed step nothing: that PR is the lead's.
    fresh "${ladder}" idle; : > "${ROOT}/agents"; heads aaaa1111 bbbb2222
    check "two red heads with no builder open step nothing" "" "$(stepped)"
    # A builder mid-turn (its session busy) is not stepped up under it: once it is idle, the next poll
    # of the same red head steps it up.
    fresh "${ladder}" busy; heads aaaa1111 bbbb2222; first="$(stepped)"
    echo '[{"sessionId":"sess-1","status":"idle"}]' > "${CLAUDE_STUB_AGENTS}"; heads bbbb2222
    check "ci-red-2 waits for a busy builder to go idle, then steps it up" "|ok (ci-red-2: sonnet -> opus)" "${first}|$(stepped)"
    # A red head on another watched repo's story/s1 PR is not s1's: s1's repo is the project.
    fresh "${ladder}" idle; mkdir -p "${ROOT}/other"; git -C "${ROOT}/other" init -q; git -C "${ROOT}/other" remote add origin "${ROOT}/other-origin.git"
    echo "repos_dir = ${ROOT}" >> "${P}/.claude/swarm/config"
    for h in aaaa1111 bbbb2222; do echo "${h}" > "${ROOT}/head"; run watch --backlog other >/dev/null || true; done
    rm -rf "${ROOT}/other"
    check "two red heads on another repo's story/s1 PR step nothing up" "" "$(stepped)"
    # The lead's bare watch leaves the story to its own conductor.
    fresh "${ladder}" idle
    for h in aaaa1111 bbbb2222; do echo "${h}" > "${ROOT}/head"; run watch >/dev/null || true; done
    check "a bare watch steps up nothing" "" "$(stepped)"
    # A head whose checks finished with a commit status still pending is judged once the status is in.
    fresh "${ladder}" idle; echo success > "${ROOT}/runs-aaaa1111"; echo pending > "${ROOT}/status-aaaa1111"
    heads aaaa1111; first="$(stepped)"; echo failure > "${ROOT}/status-aaaa1111"; heads bbbb2222
    check "a head pending at its checks' finish counts once its status goes red" "|ok (ci-red-2: sonnet -> opus)" "${first}|$(stepped)"

    # A step-up whose start fails, after the builder was closed, stops the close: no attempt counted,
    # nothing cleared, no escalation logged, and its .step-up marker kept for step-up --resume.
    fresh "${ladder}" idle; touch "${ROOT}/startfail"; out="$(run close s1)" && rc=0 || rc=$?
    check "a step-up whose start fails stops the close, counting and clearing nothing" "1|yes|yes||yes|" \
      "${rc}|$(grep -q '^step-up failed: s1' <<< "${out}" && echo yes)|$([[ -f "${P}/.swarm/briefs/s1.step-up" ]] && echo yes)|$(attempts)|$([[ -d "${WT}" ]] && echo yes)|$(escalates)"
    check "it logs one ok step-up:failed line, naming the failed start, for the lead's queue and flow" "ok (start failed)" "$(failed_lines)"
    check "it says wait --lead tells the lead and to leave s1 alone, and the close says the same" "yes|yes|no" \
      "$(grep -qxF "step-up failed: s1 stopped after its builder was closed. wait --lead tells the lead, whose exit is swarm.sh step-up --resume s1 once the cause is fixed; leave s1 alone: do not close, retry, tell or list it" <<< "${out}" && echo yes)|$(grep -qF "close: s1's step-up failed partway, after its builder was closed, so nothing more was closed or counted; wait --lead tells the lead, so leave s1 alone" <<< "${out}" && echo yes)|$(grep -qF 'list it for the lead' <<< "${out}" && echo yes || echo no)"
    rm -f "${ROOT}/startfail"
    # That build is not tried again: with its builder back, its third findings are sent as usual.
    echo "s1 w:1" > "${ROOT}/agents"; echo "w:1 s1" > "${P}/.swarm/state/s1"; findings_tells; out="$(run tell s1 findings "${ROOT}/f.md")" || true
    check "a build whose step-up failed partway is not stepped up again" "|yes" \
      "$(escalates)|$(grep -q 'told s1' <<< "${out}" && echo yes)"
    # With goal on, a /goal that does not set after the rung started is said on its own: the step-up
    # stands, so the close is done (no attempt, the worktree kept).
    fresh "${ladder}" idle; echo "goal = 30" >> "${P}/.claude/swarm/config"
    out="$(SWARM_PROMPT_TIMEOUT_MS=2000 run close s1 met)" && rc=0 || rc=$?
    check "a step-up whose /goal does not set still stands, and says so" "0|ok (no-pr: sonnet -> opus)|yes|no||yes" \
      "${rc}|$(stepped)|$(grep -q '/goal did not set' <<< "${out}" && echo yes)|$(grep -q 'step-up failed' <<< "${out}" && echo yes || echo no)|$(attempts)|$([[ -d "${WT}" ]] && echo yes)"
    # A rung whose first turn ended before send_goal read it (idle, with work since its brief) still
    # gets its /goal: start_rung takes <since> before start_agent sends the brief.
    fresh "${ladder}" idle; echo "goal = 30" >> "${P}/.claude/swarm/config"; touch "${ROOT}/quick"
    out="$(SWARM_PROMPT_TIMEOUT_MS=3000 run close s1 met)" && rc=0 || rc=$?
    check "a stepped-up builder idle after a short first turn gets its /goal set" "0|ok (no-pr: sonnet -> opus)|no" \
      "${rc}|$(stepped)|$(grep -q '/goal did not set' <<< "${out}" && echo yes || echo no)"
    rm -f "${ROOT}/quick"
    # A tell whose step-up fails after closing the builder is not sent, and says why.
    fresh "${ladder}" idle; touch "${ROOT}/startfail"; findings_tells; out="$(run tell s1 findings "${ROOT}/f.md")" && rc=0 || rc=$?
    check "a tell whose step-up fails partway is not sent, and says so" "1|yes|no" \
      "${rc}|$(grep -q 'its step-up failed partway' <<< "${out}" && echo yes)|$(grep -q 'told s1' <<< "${out}" && echo yes || echo no)"
    check "the tell says wait --lead tells the lead, and to leave s1 alone" "yes" \
      "$(grep -qF "tell: s1 was not told: its step-up failed partway, after its builder was closed; wait --lead tells the lead, so leave it alone" <<< "${out}" && echo yes)"
    rm -f "${ROOT}/startfail"
    # Its resume writes the brief again with the tell's findings, though the tell's file is gone.
    mv "${ROOT}/f.md" "${ROOT}/f.keep"; out="$(run step-up --resume s1)" || true; mv "${ROOT}/f.keep" "${ROOT}/f.md"
    check "a resumed step-up of a tell still pastes its findings" "ok (findings-3: sonnet -> opus)|yes|no" \
      "$(escalates)|$(grep -qx 'fix it' "${P}/.swarm/briefs/s1.md" && echo yes)|$([[ -e "${P}/.swarm/briefs/s1.findings.md" ]] && echo yes || echo no)"
    # Any other stop after the builder closed (here the brief cannot be written: a directory holds its
    # path) is logged by step_up_failed itself, with the exit status.
    fresh "${ladder}" idle; mkdir -p "${P}/.swarm/briefs/s1.md"; out="$(run close s1)" && rc=0 || rc=$?
    check "a step-up that stops after the close for any other reason logs its ok step-up:failed line too" "1|yes|ok (exit 1)|yes" \
      "${rc}|$(grep -q '^step-up failed: s1' <<< "${out}" && echo yes)|$(failed_lines)|$([[ -f "${P}/.swarm/briefs/s1.step-up" ]] && echo yes)"
    # So is one run by hand, and its resume: each logs its line and keeps its own exit status.
    fresh "${ladder}" idle; mkdir -p "${P}/.swarm/briefs/s1.md"; out="$(run step-up s1 stalled)" && rc=0 || rc=$?
    out2="$(run step-up --resume s1)" && rc2=0 || rc2=$?
    check "a step-up or resume run by hand that stops after the close for any other reason logs its line too" "1|1|ok (exit 1),ok (exit 1)|no" \
      "${rc}|${rc2}|$(failed_lines)|$(grep -q '^step-up failed:' <<< "${out}${out2}" && echo yes || echo no)"
    # A step-up that fails before it closes anything, with a status of its own (here git exits 128: the
    # worktree is no longer a git checkout), is a refusal: the close goes on and counts the attempt.
    fresh "${ladder}" idle; rm -f "${WT}/.git"
    out="$(run close s1)" && rc=0 || rc=$?
    check "a step-up that fails before closing the builder is a refusal: the close goes on" "0|no|1|" \
      "${rc}|$(grep -q 'step-up failed' <<< "${out}" && echo yes || echo no)|$(attempts)|$(escalates)"
    # One step-up of a story at a time: a lock held by a live process means another step-up may be
    # starting the next builder, so the close refuses, closing and counting nothing; one left by a
    # process that is gone is taken over.
    fresh "${ladder}" idle; mkdir -p "${P}/.swarm/locks/step-up-s1"; echo "$$" > "${P}/.swarm/locks/step-up-s1/pid"
    out="$(run close s1)" && rc=0 || rc=$?
    check "a step-up lock held by a live process: the close refuses, closing and counting nothing" "1|yes|||0|yes" \
      "${rc}|$(grep -q 'another step-up or a restart of s1 is running' <<< "${out}" && echo yes)|$(stepped)|$(attempts)|$(grep -c '^tab close' "${ROOT}/herdr.log" 2>/dev/null || true)|$([[ -d "${WT}" ]] && echo yes)"
    fresh "${ladder}" idle; mkdir -p "${P}/.swarm/locks/step-up-s1"; (exit 0) & dead=$!; wait "${dead}"; echo "${dead}" > "${P}/.swarm/locks/step-up-s1/pid"
    run close s1 >/dev/null || true
    check "a step-up lock left by a process that is gone is taken over, and released" "ok (no-pr: sonnet -> opus)|no" \
      "$(stepped)|$([[ -e "${P}/.swarm/locks/step-up-s1" ]] && echo yes || echo no)"
    # At the ladder's top rung no step-up runs: the close counts the attempt as it would with the ladder off.
    fresh "${ladder}" idle fable; run close s1 >/dev/null || true
    check "at the top rung no step-up is tried, and the close counts the attempt" "|1" "$(stepped)|$(attempts)"
    # A trigger missed once still fires later in the build: three findings tells already, a fourth steps up.
    fresh "${ladder}" idle; findings_tells; printf '2026-10-18T10:03:00Z\ttell:findings\ts1\tw:1\tok\n' >> "${P}/.swarm/events.tsv"
    run tell s1 findings "${ROOT}/f.md" >/dev/null || true
    check "findings past the third (the ladder turned on mid-build) still step up" "ok (findings-3: sonnet -> opus)" "$(stepped)"
    # A builder started by hand (swarm.sh agent) is a new build: its two earlier tells count nothing.
    fresh "${ladder}" idle; findings_tells; printf '2026-10-18T11:00:00Z\tagent\ts1\tw:1\tok\n' >> "${P}/.swarm/events.tsv"
    out="$(run tell s1 findings "${ROOT}/f.md")" || true
    check "tells before a swarm.sh agent start do not count toward the new build's" "|yes" "$(stepped)|$(grep -q 'told s1' <<< "${out}" && echo yes)"
  fi

  # The brief is written before the conductor starts, whatever the stub makes of the start.
  run conduct --backlog >/dev/null || true
  check "ladder '${ladder}': conduct_brief names the step-ups, with their thresholds, only with the ladder on" \
    "$([[ -n "${ladder}" ]] && echo 1 || echo 0)|$([[ -n "${ladder}" ]] && echo 2 || echo 0)" \
    "$(grep -c 'swarm.sh steps a build up the escalation ladder' "${P}/.swarm/briefs/conduct-backlog.md" || true)|$(grep -cE 'findings round 3 of its build|red on 2 heads of its build' "${P}/.swarm/briefs/conduct-backlog.md" || true)"
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
