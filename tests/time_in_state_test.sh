#!/usr/bin/env bash
# time_in_state_test.sh — `swarm.sh outcomes` splits a build's start-to-merge minutes into building,
# CI running, review wait, fixing and merge wait, and flow's time_in_state section sums them per epic,
# largest first. The fixture story tis (epic e1) was first built at 09:00 on PR #9, which took findings
# at 10:40 and was abandoned. Its rebuild starts at 10:50, commits at 10:58 and opens PR #1 at 11:00;
# findings come at 11:30, the fix is committed at 11:40, and its CI runs from 11:45 to 12:00 while the
# second round's review agent has started (11:47); a second reviewer's findings come at 11:55 with no
# commit after them, the epic's review (`review e1`) hands the PR to the merger at 12:10, a rerun runs
# from 12:15 to 12:20, and it merges at 12:30. gh gives only the last head's latest check runs (one
# cancelled while queued, with gh's year-1 start) and the PR's commits: main merged in at 11:32, before
# the fix, and a docs commit at 12:25, after the hand-off. An epic review at 11:20 names another
# story's PR alone. By precedence (fixing > CI > review wait > merge wait > building): building 10,
# review wait 30 + 5 = 35, fixing 11:30 to the 11:40 commit and 11:55 to the 12:10 review = 25, CI
# 11:45 to 11:55 and 12:15 to 12:20 = 15, merge wait 5 + 10 = 15, 100 in all; PR #9's tell, before PR #1
# was created, is not PR #1's. A retry build on PR #1 starts at 11:35 and splits its own 55 minutes;
# flow counts the PR once, by the rebuild. The retry's agents.tsv day is 10-02, so --since 2026-10-02
# leaves the earlier builds out of outcomes, but not their tells.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; U=https://github.com/o/r/pull; D=2026-10-01T
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
printf -- '---\nkind: code\nepic: e1\nstatus: review\n---\n' > "${P}/docs/stories/tis.md"
session() { # <HH:MM start> <PR> — a session log in the tis worktree that names the PR
  printf '{"type":"user","cwd":"%s/repo-wt/tis","timestamp":"%s%s:00Z"}\n' "${dir}" "${D}" "$1"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "$2"
}
session 09:00 "${U}/9" > "${dir}/projects/p/s0.jsonl"
session 10:50 "${U}/1" > "${dir}/projects/p/s1.jsonl"
session 11:35 "${U}/1" > "${dir}/projects/p/s2.jsonl"
printf '%s\n' $'2026-10-01\tcode\ttis\tclaude\topus\txhigh\ts0' $'2026-10-01\tcode\ttis\tclaude\topus\txhigh\ts1' \
  $'2026-10-02\tcode\ttis\tclaude\topus\txhigh\ts2' > "${P}/.swarm/agents.tsv"
# A refused tell never reached the builder, so it starts no fixing.
printf '%s\n' \
  "${D}10:40:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:30:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:47:00Z"$'\treview-agent\ttis\tw:1\tok' \
  "${D}11:50:00Z"$'\ttell:findings\ttis\tw:1\ttis is still working' \
  "${D}11:55:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:20:00Z"$'\treview\te1\tw:1\tok (https://github.com/o/r/pull/5)' \
  "${D}12:10:00Z"$'\treview\te1\tw:1\tok (https://github.com/o/r/pull/5 https://github.com/o/r/pull/1)' \
  "${D}12:30:00Z"$'\tmerge\ttis\tw:1\tok' > "${P}/.swarm/events.tsv"
commit() { printf '{"messageHeadline":"%s","committedDate":"%s%s:00Z"}' "$1" "${D}" "$2"; } # <headline> <HH:MM>
run() { printf '{"name":"t","startedAt":"%s","completedAt":"%s%s:00Z"}' "$1" "${D}" "$2"; }  # <start> <HH:MM end>
cat > "${dir}/prs.json" <<EOF
[{"url":"${U}/1","state":"MERGED","mergedAt":"${D}12:30:00Z","createdAt":"${D}11:00:00Z","baseRefName":"main",
  "commits":[$(commit build 10:58),$(commit "Merge origin/main into story/tis" 11:32),$(commit fix 11:40),$(commit docs 12:25)],
  "statusCheckRollup":[$(run "${D}11:45:00Z" 12:00),$(run "${D}12:15:00Z" 12:20),$(run 0001-01-01T00:00:00Z 11:20),{"context":"ci/x","state":"SUCCESS"}]},
 {"url":"${U}/9","state":"CLOSED","mergedAt":null,"createdAt":"${D}09:10:00Z","baseRefName":"main",
  "commits":[$(commit build 09:20)],"statusCheckRollup":[]}]
EOF
# gh's own --jq over that JSON, so outcomes' jq is what reads it.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\nwhile [ $# -gt 0 ]; do [ "$1" = --jq ] && q="$2"; shift; done\njq -r "$q" "%s"\n' \
  "${dir}/prs.json" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

outcomes() { # [args] — the rows, with the gh stub first on PATH
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" \
    PATH="${dir}/bin:${PATH}" bash "${ROOT}/bin/swarm.sh" outcomes "$@" | sed '/^$/,$d')
}
out="$(outcomes)"
# started, then each phase column and their sum, from the report's own header.
cols() { awk -F'\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next }
  { b = $at["building_min"]; c = $at["ci_min"]; r = $at["review_wait_min"]; f = $at["fixing_min"]; m = $at["merge_wait_min"]
    print $at["started"], b, c, r, f, m, (b == "" ? "" : b + c + r + f + m) }' <<< "${out}"; }
rebuild() { # <column>... — the rebuild's values in them
  awk -F'\t' -v c="$*" 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next }
    $at["started"] ~ /T10:50/ { n = split(c, k, " "); for (i = 1; i <= n; i++) printf "%s%s", $at[k[i]], (i < n ? " " : "\n") }' <<< "${out}"
}

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "the five phases are the last columns of outcomes" "$(head -1 <<< "${out}" | awk -F'\t' -v OFS='\t' '{ print $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF }')" \
  $'building_min\tci_min\treview_wait_min\tfixing_min\tmerge_wait_min'
# The abandoned build has no merge; the retry: fixing 11:35 to 11:40 and 11:55 to 12:10, review wait
# 11:40 to 11:45, CI 11:45 to 11:55 and 12:15 to 12:20, merge wait 12:10 to 12:15 and 12:20 to 12:30.
check "each build's minutes split by precedence, summing to its start-to-merge minutes" "$(cols)" "$(printf '%s\n' \
  "${D}09:00:00Z"$'\t\t\t\t\t\t' \
  "${D}10:50:00Z"$'\t10\t15\t35\t25\t15\t100' \
  "${D}11:35:00Z"$'\t0\t15\t5\t20\t15\t55')"
check "a findings tell on an abandoned earlier PR leaves the rebuild's first minutes building" "$(rebuild building_min)" 10
check "fixing ends at the PR's next commit after the tell, not the next check start" "$(rebuild fixing_min)" 25
check "an epic's review event hands its stories' PRs to the merger" "$(rebuild merge_wait_min)" 15
check "a fixing span with no fix commit ends at the review hand-off, not a later commit" "$(rebuild fixing_min merge_wait_min)" "25 15"
check "a check cancelled while queued (gh's year-1 start) adds no CI" "$(rebuild ci_min building_min)" "15 10"
check "an epic's review counts only for the PRs it names" "$(rebuild review_wait_min merge_wait_min)" "35 15"
check "a commit that merges main in ends no fixing" "$(rebuild fixing_min)" 25
check "--since keeps the tells of builds before it in the retry's fixing" "$(out="$(outcomes --since 2026-10-02)" cols)" \
  "${D}11:35:00Z"$'\t0\t15\t5\t20\t15\t55'

flow() { # [epic] — the time_in_state section alone, as flow runs it, over the outcomes rows
  SWARM_ROWS="${out}" python3 "${ROOT}/bin/lib/flow_report.py" 0000-00-00 9999-12-30 "${1:-}" x x x x x x x "" x time_in_state
}
check "flow's epic line counts the PR once and lists the phases largest first, a tie in column order" "$(flow)" "$(printf '%s\n' \
  "## time_in_state" $'epic\tprs\tstart_to_merge_min\tlargest_first' \
  $'e1\t1\t100\treview_wait:35 fixing:25 ci:15 merge_wait:15 building:10' \
  $'all\t1\t100\treview_wait:35 fixing:25 ci:15 merge_wait:15 building:10')"
check "--epic prints that epic's line alone" "$(flow e1 | tail -1)" $'e1\t1\t100\treview_wait:35 fixing:25 ci:15 merge_wait:15 building:10'

if [[ "${fails}" -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
