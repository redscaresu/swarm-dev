#!/usr/bin/env bash
# cost_test.sh — `swarm.sh flow`'s cost section against a fixture: two roles, a message logged twice (counted
# once), a codex agent (listed, not priced), an agent older than the `since` date (left out), the
# arguments flow refuses; then the same agents read from close's copies of their session logs once
# Claude Code deleted them; last the lead's own sessions, in the project's directory. The project and Claude's projects dir carry [x] in their names, which
# must be read as paths, not patterns.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
R="${dir}/repo[x]"; C="${dir}/projects[x]"
mkdir -p "${R}/.swarm" "${C}/p" "${dir}/bin"
git -C "${R}" init -q
# gh answers nothing, as for a repo with no GitHub remote.
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/gh"; chmod +x "${dir}/bin/gh"

usage() { # <message id> <model> <input> <cache write> <cache read> <output>
  printf '{"message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$@"
}
{ usage m1 claude-opus-5-5 1000000 0 0 1000000; usage m1 claude-opus-5-5 1000000 0 0 1000000; } > "${C}/p/s-code.jsonl"
usage m2 claude-sonnet-5 0 0 10000000 0 > "${C}/p/s-survey.jsonl"
usage m3 claude-opus-5-5 5000000 0 0 0 > "${C}/p/s-old.jsonl"
printf '%s\n' \
  $'2026-09-29\tcode\tstory-a\tclaude\topus\thigh\ts-code' \
  $'2026-09-29\tsurvey\tsurvey-lands\tclaude\tsonnet\thigh\ts-survey' \
  $'2026-09-29\tcodex\tcodex\tcodex\tdefault\thigh\t-' \
  $'2026-09-01\tcode\tstory-old\tclaude\topus\thigh\ts-old' > "${R}/.swarm/agents.tsv"

section() { sed -n '/^## cost$/,/^## /p'; } # flow's cost section
run() { (cd "${R}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${C}" PATH="${dir}/bin:${PATH}" bash "${SWARM}" "$@"); }
cost() { run flow "$@" | section; }
out="$(cost --since 2026-09-15)"
fails=0
check() { # <name> <line that must appear>
  if grep -qF -- "$2" <<< "${out}"; then echo "ok   $1"; else echo "FAIL $1: no line '$2'"; fails=$((fails + 1)); fi
}
same() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
# opus: 1M input x $4 + 1M output x $20 = $24, once despite the duplicate message
check "duplicate message counted once" "| code | 1 | claude-opus-5-5 | 1.0M | 0k | 0k | 1.0M | 24.00 |"
# sonnet: 10M cache read x $0.20 = $2
check "cache reads priced" "| survey | 1 | claude-sonnet-5 | 0k | 0k | 10.0M | 0k | 2.00 |"
check "codex listed, not priced" "| codex | 1 (1 not in the logs) | - |"
check "older than since is left out" "| **total** | 3 | | 1.0M | 0k | 10.0M | 1.0M | 26.00 |"
same "a window with no step-up prints the per-rung header and none" "$(sed -n '/^### per rung$/,$p' <<< "${out}" | head -3)" "$(printf '%s\n' '### per rung' '' none)"

# --until leaves out what came after it; --epic changes no number, and says so.
same "--until 2026-09-28 leaves out the 2026-09-29 agents" "$(cost --until 2026-09-28 | grep -F '**total**')" "| **total** | 1 | | 5.0M | 0k | 0k | 0k | 20.00 |"
same "--epic counts every agent in the window, and says so" "$(cost --since 2026-09-15 --epic e1 | grep -F '**total**')" "| **total** | 3 | | 1.0M | 0k | 10.0M | 1.0M | 26.00 |"
same "--epic says the cost is not the epic's alone" "$(cost --since 2026-09-15 --epic e1 | grep -F 'epic e1')" "Every agent in the window, not only epic e1's."

# An argument flow does not understand is refused before any table
for args in "--since" "--since 2026-9-15" "bogus" "2026-09-15 extra"; do
  # shellcheck disable=SC2086 # word-split on purpose: each case is several arguments
  if bad="$(run flow ${args} 2>&1)"; then
    echo "FAIL flow ${args}: exited 0"; fails=$((fails + 1))
  elif ! grep -qF "usage: swarm.sh flow [--since YYYY-MM-DD]" <<< "${bad}" || grep -qF "**total**" <<< "${bad}"; then
    echo "FAIL flow ${args}: no usage line, or a table: ${bad}"; fails=$((fails + 1))
  else
    echo "ok   flow ${args} refused"
  fi
done

# close's copies (written by archive_session, through its _archive test hook).
live="${out}"
run _archive story-a; run _archive survey-lands
mv "${R}/.swarm/sessions/"*-s-code.jsonl.gz "${R}/.swarm/sessions/2026-01-01-story-a-s-code.jsonl.gz"
run _archive story-a
same "close keeps one copy per session, under a [x] path too" "$(find "${R}/.swarm/sessions" -name '*-s-code.jsonl.gz' | wc -l | tr -d ' ')" 1
usage m4 claude-opus-5-5 0 0 0 1000000 > "${C}/p/s-code.jsonl"
out="$(cost --since 2026-09-15)"
check "with both the live log and close's copy, the live log wins" "| code | 1 | claude-opus-5-5 | 0k | 0k | 0k | 1.0M | 20.00 |"
rm "${C}/p/s-code.jsonl" "${C}/p/s-survey.jsonl"
snap() { (cd "${R}/.swarm" && find . | sort && find . -type f ! -name gh-calls.tsv -exec cksum {} + | sort); }   # gh-calls.tsv: gh-shim logs its gh calls
before="$(snap)"
same "with only close's copies, the same totals as the live logs" "$(cost --since 2026-09-15)" "${live}"
same "reading creates no file and no events.tsv line" "$(snap)" "${before}"
rm "${R}/.swarm/sessions/"*
out="$(cost --since 2026-09-15)"
check "with neither, the agent is listed and not priced" "| code | 1 (1 not in the logs) | - | 0k | 0k | 0k | 0k | 0.00 |"

# The lead's own sessions, in the project's directory under Claude's projects dir (its path with every
# character but letters and digits turned into -): one agents.tsv does not name counts as lead, from
# its first timestamp's day on; one it names (s-code) counts once, under its own role.
real="$(cd "${R}" && pwd -P)"; E="${C}/${real//[^A-Za-z0-9]/-}"
mkdir -p "${E}"
stamp() { printf '{"timestamp":"%s",%s\n' "$1" "$(cut -c2-)"; } # <time>: one usage line, stamped
{ echo '{"type":"summary"}'; usage m5 claude-opus-5-5 0 0 0 1000000 | stamp 2026-09-20T10:00:00.000Z; } > "${E}/s-lead.jsonl"
usage m6 claude-opus-5-5 0 0 0 1000000 | stamp 2026-09-20T09:00:00.000Z > "${E}/s-code.jsonl"
out="$(cost --since 2026-09-15)"
check "an unlisted session in the project's directory is the lead's" "| lead | 1 | claude-opus-5-5 | 0k | 0k | 0k | 1.0M | 20.00 |"
check "a listed session there counts under its own role" "| code | 1 | claude-opus-5-5 | 0k | 0k | 0k | 1.0M | 20.00 |"
check "each counted once" "| **total** | 4 | | 0k | 0k | 0k | 2.0M | 40.00 |"
out="$(TZ=UTC cost --since 2026-09-21)"
check "with --since after its first timestamp, the lead session is left out" "| **total** | 3 | | 0k | 0k | 0k | 1.0M | 20.00 |"
# --since is a local date: a session started at 23:30 UTC on the 20th started on the 21st in Paris (UTC+2).
usage m7 claude-opus-5-5 0 0 0 1000000 | stamp 2026-09-20T23:30:00.000Z > "${E}/s-late.jsonl"
out="$(TZ=Europe/Paris cost --since 2026-09-21)"
check "a lead session counts from its first timestamp's local day" "| lead | 1 | claude-opus-5-5 | 0k | 0k | 0k | 1.0M | 20.00 |"
out="$(TZ=UTC cost --since 2026-09-21)"
check "in UTC the same session started the day before" "| **total** | 3 | | 0k | 0k | 0k | 1.0M | 20.00 |"
# Run in a herdr pane whose session agents.tsv names (a conductor's, here s-code): counted once, under its role.
mkdir -p "${dir}/bin"
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"pane_id\":\"w:1\",\"agent_session\":{\"value\":\"s-code\"}},{\"pane_id\":\"w:2\",\"agent_session\":{\"value\":\"s-lead\"}}]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
pane() { (cd "${R}" && TZ=UTC PATH="${dir}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID="$1" CLAUDE_PROJECTS_DIR="${C}" bash "${SWARM}" flow "${@:2}" | section); } # <pane> [flow args]
out="$(pane w:1 --since 2026-09-15)"
check "a pane's session agents.tsv names is not a lead too" "| **total** | 5 | | 0k | 0k | 0k | 3.0M | 60.00 |"
# The calling pane's own session (s-lead, first stamped 2026-09-20) is windowed like the others.
same "the calling pane's lead session before --until is left out" "$(pane w:2 --until 2026-09-01 | grep -c '^| lead |' || true)" 0
same "the calling pane's lead session in the window counts once" "$(pane w:2 --since 2026-09-15 | grep '^| lead |')" "| lead | 2 | claude-opus-5-5 | 0k | 0k | 0k | 2.0M | 40.00 |"
# A lead session with no timestamp counts only when --since is not given: --until alone keeps it.
usage m8 claude-opus-5-5 0 0 0 1000000 > "${E}/s-nostamp.jsonl"
same "with --until alone, a lead session with no timestamp counts" "$(cost --until 2026-12-31 | grep '^| lead |')" "| lead | 3 | claude-opus-5-5 | 0k | 0k | 0k | 3.0M | 60.00 |"
same "with --since, a lead session with no timestamp is left out" "$(cost --since 2026-09-15 | grep '^| lead |')" "| lead | 2 | claude-opus-5-5 | 0k | 0k | 0k | 2.0M | 40.00 |"

# /plan-epic's split critic is a critic agent named split-critic: its tokens get a row of their own.
usage m9 claude-opus-5-5 0 0 0 1000000 > "${C}/p/s-split.jsonl"
usage m10 claude-opus-5-5 0 0 0 2000000 > "${C}/p/s-critic.jsonl"
# A builder whose story's slug is split-critic (this feature's own) is a builder, not the split critic.
usage m11 claude-opus-5-5 0 0 0 4000000 > "${C}/p/s-builder.jsonl"
printf '%s\n' $'2026-09-29\tcritic\tsplit-critic\tclaude\topus\thigh\ts-split' $'2026-09-29\tcritic\tcritic\tclaude\topus\thigh\ts-critic' \
  $'2026-09-29\tcode\tsplit-critic\tclaude\topus\thigh\ts-builder' >> "${R}/.swarm/agents.tsv"
out="$(cost --since 2026-09-15)"
check "the split critic has its own row" "| split-critic | 1 | claude-opus-5-5 | 0k | 0k | 0k | 1.0M | 20.00 |"
check "the plan critic keeps the critic row" "| critic | 1 | claude-opus-5-5 | 0k | 0k | 0k | 2.0M | 40.00 |"
check "a builder named split-critic counts under its own role" "| code | 2 | claude-opus-5-5 | 0k | 0k | 0k | 5.0M | 100.00 |"

# The per-rung block, on a ladder of sonnet, opus and fable, with outcomes' rows given as flow passes them.
# s-a steps up findings-3 and its PR reads as merged in outcomes, with no merge line; s-b steps up when
# stalled and is held for the lead; s-d steps up on red CI and its last rung closes with its PR closed;
# s-c never steps up; s-old's step-up is before the window, and a refused step-up line counts for none.
# s-e steps up findings-3 from opus in two attempts: the first fails, the second is held for the lead,
# and each step-up takes its own attempt's ending; the tokens are the story's, of both attempts. s-f does
# the same twice in one day (no agents.tsv lines, so no tokens): the first goes to the lead before the
# second starts (its story line), the second merges, and the first attempt's rung, naming the PR the
# second merged, does not make it merged. s-e's hold comes after its second story line: the second's. s-g's
# rung starts before midnight and its step-up line comes after it: merged. s-h's rung closes, its session
# naming no PR, while its first rung's PR is open: open.
G="${dir}/rung"; mkdir -p "${G}/projects/p"
for s in "r1 sonnet 1000000" "r2 opus 1000000" "r3 opus 2000000" "r4 fable 1000000" "r5 sonnet 500000" "r6 opus 1000000" "r10 opus 1000000"; do
  read -r sid model tokens <<< "${s}"   # r7 (s-d's fable rung) and s-e's but r10 have no session log
  usage "m-${sid}" "claude-${model}-5" 0 0 0 "${tokens}" > "${G}/projects/p/${sid}.jsonl"
done
printf '%s\n' $'2026-10-01\tcode-sonnet\ts-a\tclaude\tsonnet\thigh\tr1' $'2026-10-01\tcode\ts-a\tclaude\topus\thigh\tr2' \
  $'2026-10-01\tcode\ts-b\tclaude\topus\thigh\tr3' $'2026-10-01\tescalate\ts-b\tclaude\tfable\txhigh\tr4' \
  $'2026-10-01\tcode-sonnet\ts-c\tclaude\tsonnet\thigh\tr5' $'2026-10-01\tcode\ts-d\tclaude\topus\thigh\tr6' \
  $'2026-10-01\tescalate\ts-d\tclaude\tfable\txhigh\tr7' $'2026-10-01\tcode\ts-e\tclaude\topus\thigh\tr8' \
  $'2026-10-01\tescalate\ts-e\tclaude\tfable\txhigh\tr9' $'2026-10-02\tcode\ts-e\tclaude\topus\thigh\tr10' \
  $'2026-10-02\tescalate\ts-e\tclaude\tfable\txhigh\tr11' > "${G}/agents.tsv"
ev() { printf '%s\t%s\t%s\t-\t%s\n' "$@" >> "${G}/events.tsv"; } # <time> <command> <slug> <outcome>
ev 2026-09-01T10:00:00Z escalate s-old "ok (no-pr: sonnet -> opus)"
ev 2026-10-01T10:00:00Z escalate s-a "ok (findings-3: sonnet -> opus)"
ev 2026-10-01T11:00:00Z escalate s-b "ok (stalled: opus -> fable)"
ev 2026-10-01T11:30:00Z escalate s-c "step-up: s-c's builder is on fable, at or above escalate_ladder's top rung"
ev 2026-10-01T12:00:00Z escalate s-d "ok (ci-red-2: opus -> fable)"
ev 2026-10-02T09:00:00Z held s-b "ok (top-rung: findings round 2 on fable)"
ev 2026-10-01T13:00:00Z escalate s-e "ok (findings-3: opus -> fable)"
ev 2026-10-02T12:00:00Z story s-e ok
ev 2026-10-02T13:00:00Z escalate s-e "ok (findings-3: opus -> fable)"
ev 2026-10-02T15:00:00Z held s-e "ok (top-rung: findings round 2 on fable)"
ev 2026-10-03T08:00:00Z escalate s-f "ok (no-pr: sonnet -> opus)"
ev 2026-10-03T09:00:00Z escalated s-f "ok (attempts 1, 0 PRs)"
ev 2026-10-03T09:30:00Z story s-f ok
ev 2026-10-03T10:00:00Z escalate s-f "ok (no-pr: sonnet -> opus)"
ev 2026-10-03T12:00:00Z escalate s-h "ok (ci-red-2: opus -> fable)"
ev 2026-10-04T00:03:00Z escalate s-g "ok (stalled: opus -> fable)"
rows="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' date slug model attempts pr_state story_merged closes close_cause started \
  2026-10-01 s-a sonnet 1 MERGED true 1 step-up:findings-3 '' 2026-10-01 s-a opus 1 MERGED true 1 '' '' \
  2026-10-01 s-b opus 1 OPEN false 1 step-up:stalled '' 2026-10-01 s-b fable 1 OPEN false 0 '' '' \
  2026-10-01 s-c sonnet 1 OPEN false 0 '' '' \
  2026-10-01 s-d opus 1 CLOSED false 1 step-up:ci-red-2 '' 2026-10-01 s-d fable 1 CLOSED false 1 '' '' \
  2026-10-01 s-e opus 1 '' false 1 step-up:findings-3 '' 2026-10-01 s-e fable 1 '' false 1 '' '' \
  2026-10-02 s-e opus 2 OPEN false 1 step-up:findings-3 2026-10-02T12:00:00Z 2026-10-02 s-e fable 2 OPEN false 0 '' 2026-10-02T13:00:00Z \
  2026-10-03 s-f sonnet 1 CLOSED true 1 step-up:no-pr '' 2026-10-03 s-f opus 1 MERGED true 1 '' '' \
  2026-10-03 s-f sonnet 2 MERGED true 1 step-up:no-pr '' 2026-10-03 s-f opus 2 MERGED true 0 '' '' \
  2026-10-03 s-h opus 1 OPEN false 1 step-up:ci-red-2 '' 2026-10-03 s-h fable 1 '' false 1 '' '' \
  2026-10-03 s-g opus 1 MERGED true 1 step-up:stalled '' 2026-10-03 s-g fable 1 MERGED true 0 '' 2026-10-03T23:58:00Z)"
rungs() { # [until] — the cost section's per-rung block over the fixture, from --since 2026-09-15, as flow_sections runs it
  TZ=UTC SWARM_ROWS="${rows}" python3 "$(dirname "${SWARM}")/lib/flow_report.py" 2026-09-15 "${1:-9999-12-30}" "" "${G}/agents.tsv" "${G}/events.tsv" \
    "${G}/findings.tsv" x "code code-sonnet escalate" "${G}/projects" "${G}/sessions" "" "${G}/own" cost | sed -n '/^### per rung$/,$p'
}
# shellcheck disable=SC2016 # the $ is the table's, not an expansion
same "one row per step-up in the window: its trigger, tokens per rung and outcome, then each rung's reach" "$(rungs)" "$(printf '%s\n' '### per rung' '' \
  '| story | trigger | step-up | tokens per rung | outcome |' '|---|---|---|---|---|' \
  '| s-a | findings-3 | sonnet -> opus | sonnet 1.0M $10.00, opus 1.0M $20.00 | merged |' \
  '| s-b | stalled | opus -> fable | opus 2.0M $40.00, fable 1.0M $20.00 | lead |' \
  '| s-d | ci-red-2 | opus -> fable | opus 1.0M $20.00, fable - | failed |' \
  '| s-e | findings-3 | opus -> fable | opus 1.0M $20.00, fable - | failed |' \
  '| s-e | findings-3 | opus -> fable | opus 1.0M $20.00, fable - | lead |' \
  '| s-f | no-pr | sonnet -> opus | - | lead |' '| s-f | no-pr | sonnet -> opus | - | merged |' \
  '| s-h | ci-red-2 | opus -> fable | - | open |' '| s-g | stalled | opus -> fable | - | merged |' '' \
  '| rung | builds | share |' '|---|---|---|' '| sonnet | 4 | 40% |' '| opus | 9 | 90% |' '| fable | 6 | 60% |')"
# shellcheck disable=SC2016 # the $ is the table's, not an expansion
same "with --until, sessions and rungs after it are left out" "$(rungs 2026-10-01 | grep -F -e '| s-e |' -e '| opus |' -e '| fable |')" \
  "$(printf '%s\n' '| s-e | findings-3 | opus -> fable | opus -, fable - | failed |' '| opus | 4 | 80% |' '| fable | 3 | 60% |')"
rows="$(head -1 <<< "${rows}")"
# shellcheck disable=SC2016 # the $ is the table's, not an expansion
same "a step-up whose story outcomes has no row for yet reads as open" "$(rungs | grep -F '| s-a |')" \
  '| s-a | findings-3 | sonnet -> opus | sonnet 1.0M $10.00, opus 1.0M $20.00 | open |'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
