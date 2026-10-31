#!/usr/bin/env bash
# events_tail_flow_test.sh — flow's, outcomes' and dataset's events.tsv readers read the outcome
# through events_outcome.outcome(), so a key=value tail (events_outcome.SEP, then k=v) on every row's
# outcome changes nothing they print. Over the committed fixture (events_tail_helpers.sh), with
# synthetic events rows for what it lacks and a synthetic agents.tsv, board, session logs,
# findings.tsv, features.tsv and gh stub, TZ=UTC: flow (every section flow_report.py lists),
# outcomes and dataset print the same in the plain project and its tailed copy, and each changed
# reader prints a data row there: cost's per-rung row, features' uses, holds, idle_slots, incidents
# (a kind with no detail, and its stop under the epic an ok conduct line names), lead_queue and its
# no-agent table, merges, review_loops' rounds, throughput's builds, outcomes' findings, close cause,
# ready wait and held columns, dataset's escalations, and touches_rows.ok_events, called alone. An inline `reconcile <slug> ok (reopened)` row (no live log
# holds one) drops lead_queue's no-agent item, and does the same with a tail on it. None of
# these readers is a predicate: each prints, or returns, what it read.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"; LIB="${HERE}/../bin/lib"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
SEP="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import events_outcome; print(events_outcome.SEP, end="")' "${LIB}")"
TAIL="${SEP}k=v"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { # <text> <line> — <text> holds <line> whole; else it prints the text to stderr
  grep -qxF -- "$2" <<< "$1" && return 0
  printf "no line '%s' in:\n%s\n" "$2" "$1" >&2; return 1
}

# gh: each story's one merged PR, for outcomes (--state all) and dataset (--state merged); auth
# answers; every other call fails, so ci_health, merge_ins and rework read nothing.
U=https://github.com/o/r/pull
mkdir -p "${ROOT}/bin"
cat > "${ROOT}/bin/gh" <<EOF
#!/bin/sh
case "\$4" in   # the PR: url, mergedAt, createdAt and, for zzcl, its head's one green check
  story/zzd) pr="${U}/2 2026-10-25T11:40:00Z 2026-10-25T10:40:00Z" ;;
  story/zzak) pr="${U}/9 2026-10-26T01:00:00Z 2026-10-25T23:00:00Z" ;;
  story/zzau) pr="${U}/14 2026-10-26T07:28:00Z 2026-10-26T05:00:00Z" ;;
  story/zzcl) pr="${U}/19 2026-10-27T04:47:00Z 2026-10-27T02:00:00Z 2026-10-27T02:00:00Z/2026-10-27T02:05:00Z/SUCCESS" ;;
  *) pr="" ;;
esac
case "\$1 \$2 \$3 \$5 \$6" in
  "auth status"*) exit 0 ;;
  "pr list --head --state all") [ -n "\${pr}" ] || exit 1; set -- \${pr}; printf '%s\tMERGED\t%s\t%s\t0\t%s\t\t\t0\n' "\$1" "\$2" "\$3" "\${4:-}" ;;
  "pr list --head --state merged") [ -n "\${pr}" ] || exit 1; set -- \${pr}; printf '%s\t%s\t\tmerged\n' "\$1" "\$2" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/gh"

# The builds' session logs, which outcomes reads each build's start (as its story line logs it) and
# PR from.
mkdir -p "${CLAUDE_CONFIG_DIR}/projects/p"
for b in s1:zzd:2:2026-10-25T10:26:57Z s4:zzau:14:2026-10-26T04:21:20Z s5:zzcl:19:2026-10-27T00:03:58Z; do
  IFS=: read -r sid slug n _ <<< "${b}"
  { printf '{"type":"user","cwd":"/w/r-wt/%s","timestamp":"%s"}\n' "${slug}" "${b#*:*:*:}"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s/%s\\n"}]}}\n' "${U}" "${n}"
  } > "${CLAUDE_CONFIG_DIR}/projects/p/${sid}.jsonl"
done

# project <dir> <events.tsv> [<tail>] — events_project's stand-in, with a builder line per story the
# fixture builds (zzak stepped up to fable), those stories and a ready zze on the board, a finding,
# and a feature list counting hold and story lines.
project() {
  events_project "$@"
  printf '%s\n' $'2026-10-25\tcode\tzzd\tclaude\topus\txhigh\ts1' $'2026-10-25\tcode\tzzak\tclaude\topus\txhigh\ts2' \
    $'2026-10-25\tcode\tzzak\tclaude\tfable\txhigh\ts3' $'2026-10-26\tcode\tzzau\tclaude\topus\txhigh\ts4' \
    $'2026-10-27\tcode\tzzcl\tclaude\topus\txhigh\ts5' > "$1/.swarm/agents.tsv"
  local s
  for s in zzd zzak zzau zzcl; do printf -- '---\nkind: code\nstatus: review\n---\n\n# %s\n' "${s}" > "$1/docs/stories/${s}.md"; done
  printf -- '---\nkind: code\nstatus: ready\ntouches: [src/e.txt]\n---\n\n# zze\n' > "$1/docs/stories/zze.md"
  printf '%s\n' $'feature\tlanded\tmetric\tbaseline\tsources' $'holds\t2026-10-01\tflow: holds\t0\tevent:hold event:story' > "$1/docs/features.tsv"
  # A finding on zzau's PR: outcomes and review_loops read findings.tsv in the same scripts as events.tsv.
  printf '%s\n' $'2026-10-26\tbug\to/r#14\tsynthetic\tfixed\tcodex\t\t1' > "$1/.swarm/findings.tsv"
  # An empty gh-calls log gh-shim cannot write: its rows would carry the hour each run made them.
  : > "$1/.swarm/gh-calls.tsv" && chmod 444 "$1/.swarm/gh-calls.tsv"
}
swarm() { env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@"; }
# The window ends before the fixture's last day, so nothing open is timed to the clock.
flow() { swarm flow --since 2026-10-01 --until 2026-10-28; }
lead_queue() { SWARM_FLOW_SECTIONS=lead_queue flow; }
dataset() { swarm dataset >/dev/null && cat .swarm/dataset.jsonl; }
ok_events() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import touches_rows
for k, v in sorted(touches_rows.ok_events(sys.argv[2]).items()): print(*k, *v, sep="\t")' "${LIB}" .swarm/events.tsv; }
section() { awk -v h="## $2" '$0 == h { on = 1; next } /^## / { on = 0 } on' <<< "$1"; }
column() { # <outcomes output> <slug> <column> — that column of the slug's first row
  awk -F'\t' -v s="$2" -v c="$3" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == c) n = i; next } $2 == s { print $n; exit }' <<< "$1"
}

# The fixture, with synthetic rows in time order for what it lacks: zzan's ok story line an hour after
# its hold (which ends the hold); a bare ok review of zzau before its review that names the PR (a
# review from before reviews named PRs, which goes to the one PR open then); an ok conduct of epic
# zzsyn, then an incident of its conductor whose outcome is a kind with no `: <detail>` (every fixture
# incident has one, and the fixture's only ok conduct is the backlog's, which incidents skips).
EVENTS="${ROOT}/events.tsv"
printf '%s\n' $'2026-10-26T01:08:11Z\tstory\tzzan\twa:pa\tok' $'2026-10-26T05:30:00Z\treview\tzzau\twa:pa\tok' \
  $'2026-10-28T10:00:00Z\tconduct\tzzsyn\twa:pa\tok' $'2026-10-28T10:05:00Z\tincident\tconduct-zzsyn\t-\tapi-error' \
  | sort -s -t $'\t' -k1,1 "${EVENTS_FIXTURE}" - > "${EVENTS}"

P="${ROOT}/plain/proj"; Q="${ROOT}/tailed/proj"
project "${P}" "${EVENTS}"
project "${Q}" "${EVENTS}" "${TAIL}"
check "the tailed copy ends every row's outcome in ${SEP}k=v" \
  test "$(grep -c "	[^	]*${SEP}k=v\$" "${Q}/.swarm/events.tsv")" = "$(wc -l < "${EVENTS}" | tr -d ' ')"
check "flow prints the same over the fixture and its tailed copy" same_output "${P}" "${Q}" flow
check "outcomes prints the same over the fixture and its tailed copy" same_output "${P}" "${Q}" swarm outcomes
check "dataset writes the same over the fixture and its tailed copy" same_output "${P}" "${Q}" dataset
check "touches_rows.ok_events reads the same over the fixture and its tailed copy" same_output "${P}" "${Q}" ok_events

# Each reader prints a row the plain fixture's outcomes make (so the same above is no two empty runs).
out="$(cd "${P}" && flow)"; rows="$(cd "${P}" && swarm outcomes 2>/dev/null)"
check "cost: zzak's step-up rung" has "$(section "${out}" cost)" "| zzak | stalled | opus -> fable | opus -, fable - | merged |"
check "features: the hold and story ok lines" has "$(section "${out}" features | cut -f1-4)" $'holds\t6\tflow: holds\t0'
check "holds: zzan's hold, ended by its ok story line" has "$(section "${out}" holds)" \
  $'zzan\t-\tclashes with zzao (epic zzap), open, on .github/workflows/ci.yml:shellcheck step\t60'
check "idle_slots: zze ready from its unblock, under the backlog conductor until its report" \
  has "$(section "${out}" idle_slots)" $'all\t144\t4988\t2'
check "incidents: the stalled line" has "$(section "${out}" incidents)" $'2026-10-25\tstalled\t1'
check "incidents: a kind with no detail" has "$(section "${out}" incidents)" $'2026-10-28\tapi-error\t1'
check "incidents: that stop goes to the epic whose ok conduct line started its conductor" \
  has "$(section "${out}" incidents)" $'zzsyn\tapi-error\t1'
check "lead_queue: zzep's no-agent item, from its close to its wake" has "$(section "${out}" lead_queue)" $'2026-10-27\t1\t6\t6\t0\t-'
check "merges: zzd's reconcile and zzai's finish" has "$(section "${out}" merges)" $'2026-10-25\t2'
check "review_loops: zzau's three rounds, its bare ok review one" has "$(section "${out}" review_loops)" $'zzau\thttps://github.com/o/r/pull/14\t3\tpass'
check "throughput: the builds, closed by their ok closes" has "$(section "${out}" throughput)" $'all\t5\t0.55\t1\t4\t1\t4.0\t\t\t1'
check "outcomes: zzau's finding, read beside the events" test "$(column "${rows}" zzau findings_fixed)" = 1
check "outcomes: zzau's PR is handed over at its bare ok review, the one PR open then (fixing ends there)" \
  test "$(column "${rows}" zzau review_wait_min)/$(column "${rows}" zzau fixing_min)/$(column "${rows}" zzau merge_wait_min)" = 23/7/118
check "outcomes: zzcl's green to its first ok review-agent round" test "$(column "${rows}" zzcl green_to_review_min)" = 1
check "outcomes: zzak's close by its step-up" test "$(column "${rows}" zzak close_cause)" = step-up:stalled
check "outcomes: zzau's ready wait from its unblock, held 0 after the backlog's report" \
  test "$(column "${rows}" zzau ready_wait_min)/$(column "${rows}" zzau held_min)" = 101/0
check "dataset: zzak's step-up" has "$(cd "${P}" && dataset | python3 -c 'import json, sys
for l in sys.stdin: print(json.loads(l)["slug"], json.dumps(json.loads(l)["results"]["escalations"]))')" \
  'zzak [{"at": "2026-10-25T23:45:23Z", "from": "opus", "to": "fable", "trigger": "stalled"}]'
check "ok_events: the hold and report lines, whose outcomes are ok (...)" \
  test "$(cd "${P}" && ok_events | cut -f1,2 | grep -E '^(hold|report)'$'\t')" = $'hold\tzzan\nreport\tbacklog'

# An inline reconcile <slug> ok (reopened) after zzep's builder closed: the no-agent item its wake
# would close is dropped, with and without a tail on that row alone (a tail on every row would also
# hide the wake from a raw read, and drop the item the same way).
reopened() { # [<tail>] — the fixture with the reconcile row, <tail> on it
  awk -F'\t' -v t="${1:-}" '{ print } $2 == "close" && $3 == "zzep" { print "2026-10-27T12:15:00Z\treconcile\tzzep\twa:pa\tok (reopened)" t }' \
    "${EVENTS}"
}
reopened > "${ROOT}/reopened.tsv"; reopened "${TAIL}" > "${ROOT}/reopened-tailed.tsv"
R="${ROOT}/reopened/proj"; T="${ROOT}/reopened-tailed/proj"
project "${R}" "${ROOT}/reopened.tsv"
project "${T}" "${ROOT}/reopened-tailed.tsv"
check "the reopened row drops lead_queue's no-agent table" \
  test "$(cd "${R}" && lead_queue | grep -c '^no_agent_day')" = 0
check "lead_queue is the same with the reopened row, with and without a tail" same_output "${R}" "${T}" lead_queue

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
