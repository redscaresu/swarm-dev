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
# story's PR alone, and a review of tis at 11:15 names PR #9 alone (closed at 10:45). By precedence (fixing > CI > review wait > merge wait > building): building 10,
# review wait 30 + 5 = 35, fixing 11:30 to the 11:40 commit and 11:55 to the 12:10 review = 25, CI
# 11:45 to 11:55 and 12:15 to 12:20 = 15, merge wait 5 + 10 = 15, 100 in all; PR #9's tell, before PR #1
# was created, is not PR #1's. A retry build on PR #1 starts at 11:35 and splits its own 55 minutes;
# flow counts the PR once, by the rebuild. The retry's agents.tsv day is 10-02, so --since 2026-10-02
# leaves the earlier builds out of outcomes, but not their tells. tis was unblocked at 05:00 and its
# epic's conductor started at 06:00, so it waited ready, held, for 180 minutes before its first build;
# its retries hold none.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; U=https://github.com/o/r/pull; D=2026-10-01T
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
# A user's diff settings must not hide the board's ready commits.
git -C "${P}" config diff.noprefix true; git -C "${P}" config color.ui always
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
  "${D}05:00:00Z"$'\tunblock\ttis\tw:1\tok' \
  "${D}06:00:00Z"$'\tconduct\te1\tw:1\tok' \
  "${D}10:40:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:30:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:47:00Z"$'\treview-agent\ttis\tw:1\tok' \
  "${D}11:50:00Z"$'\ttell:findings\ttis\tw:1\ttis is still working' \
  "${D}11:55:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:15:00Z"$'\treview\ttis\tw:1\tok (https://github.com/o/r/pull/9)' \
  "${D}11:20:00Z"$'\treview\te1\tw:1\tok (https://github.com/o/r/pull/5)' \
  "${D}12:10:00Z"$'\treview\te1\tw:1\tok (https://github.com/o/r/pull/5 https://github.com/o/r/pull/1)' \
  "${D}12:30:00Z"$'\tmerge\ttis\tw:1\tok' > "${P}/.swarm/events.tsv"
commit() { printf '{"messageHeadline":"%s","committedDate":"%s%s:00Z"}' "$1" "${D}" "$2"; } # <headline> <HH:MM>
run() { printf '{"name":"t","startedAt":"%s","completedAt":"%s%s:00Z"}' "$1" "${D}" "$2"; }  # <start> <HH:MM end>
cat > "${dir}/prs.json" <<EOF
[{"url":"${U}/1","state":"MERGED","mergedAt":"${D}12:30:00Z","createdAt":"${D}11:00:00Z","closedAt":"${D}12:30:00Z","baseRefName":"main",
  "commits":[$(commit build 10:58),$(commit "Merge origin/main into story/tis" 11:32),$(commit fix 11:40),$(commit docs 12:25)],
  "statusCheckRollup":[$(run "${D}11:45:00Z" 12:00),$(run "${D}12:15:00Z" 12:20),$(run 0001-01-01T00:00:00Z 11:20),{"context":"ci/x","state":"SUCCESS"}]},
 {"url":"${U}/9","state":"CLOSED","mergedAt":null,"createdAt":"${D}09:10:00Z","closedAt":"${D}10:45:00Z","baseRefName":"main",
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
check "the five phases, then held, are the last columns of outcomes" "$(head -1 <<< "${out}" | awk -F'\t' -v OFS='\t' '{ print $(NF-5), $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF }')" \
  $'building_min\tci_min\treview_wait_min\tfixing_min\tmerge_wait_min\theld_min'
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
check "a review of the slug naming another of its PRs is not this PR's hand-off" "$(rebuild review_wait_min merge_wait_min)" "35 15"
# A review logged before reviews named their PRs (a bare ok) hands over its slug's one PR open then:
# PR #1 at 12:10, as PR #9 closed at 10:45.
E="${P}/.swarm/events.tsv"; cp "${E}" "${dir}/events.full"
sed 's|\treview\te1\tw:1\tok (https://github.com/o/r/pull/5 https://github.com/o/r/pull/1)$|\treview\ttis\tw:1\tok|' "${dir}/events.full" > "${E}"
check "a review that names no PR hands over its slug's one open PR" "$(out="$(outcomes)" rebuild review_wait_min merge_wait_min)" "35 15"
cp "${dir}/events.full" "${E}"
check "a PR with two review rounds splits its time in review into CI, review wait, fixing and merge wait" \
  "$(rebuild ci_min review_wait_min fixing_min merge_wait_min pr_to_merge_min | awk '{ print $1, $2, $3, $4, "=", $1 + $2 + $3 + $4, "of", $5 }')" \
  "15 35 25 15 = 90 of 90"
held() { awk -F'\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next } { print $at["started"], $at["held_min"] }' <<< "$1"; }
check "a story ready while its epic's conductor ran is held until its first build, and only that build" "$(held "${out}")" \
  "$(printf '%s\n' "${D}09:00:00Z"$'\t180' "${D}10:50:00Z"$'\t' "${D}11:35:00Z"$'\t')"
add_events() { cp "${dir}/events.full" "${E}"; printf '%s\n' "$@" >> "${E}"; }
first_held() { held "$(outcomes)" | head -1 | cut -f2; }
add_events "${D}07:00:00Z"$'\tunblock\ttis\tw:1\tok'
check "a story unblocked after its conductor started is held from the unblock" "$(first_held)" 120
add_events "${D}08:30:00Z"$'\tconduct\te1\tw:1\tok'
check "held counts from the start of the conductor run the build started under" "$(first_held)" 30
add_events "${D}08:00:00Z"$'\tclose\tconduct-e1\tw:1\tok' "${D}08:30:00Z"$'\tconduct\te1\tw:1\tconduct-e1 is still working'
check "a build that starts after its conductor closed holds 0, and a refused conduct starts no run" "$(first_held)" 0
cp "${dir}/events.full" "${E}"; touch -t 202610010800 "${P}/.swarm/conduct-e1.report.md"
check "a conductor's report ends its run" "$(first_held)" 0
rm "${P}/.swarm/conduct-e1.report.md"
# The next conduct logged the report's time as it removed the file, so the run still ends there.
add_events "${D}10:00:00Z"$'\treport\te1\tw:1\tok ('"${D}"'08:00:00Z)'
check "a removed report's logged time still ends its run" "$(first_held)" 0
# A long epic's conductor name is cut to 32 characters; a close by its full name still ends its run.
LONG=a-long-epic-whose-conductor-name-is-cut
sed -i.bak "s/^epic: e1$/epic: ${LONG}/" "${P}/docs/stories/tis.md" && rm "${P}/docs/stories/tis.md.bak"
add_events "${D}06:00:00Z"$'\tconduct\t'"${LONG}"$'\tw:1\tok' "${D}08:00:00Z"$'\tclose\tconduct-'"${LONG}"$'\tw:1\tok'
check "a close by a long epic's full conductor name ends its run" "$(first_held)" 0
sed -i.bak "s/^epic: ${LONG}$/epic: e1/" "${P}/docs/stories/tis.md" && rm "${P}/docs/stories/tis.md.bak"
grep -v $'\tunblock\t' "${dir}/events.full" > "${E}"
check "with no unblock or ready commit by its start, a story's held is unknown" "$(first_held)" ""
# With no epic, tis is the backlog conductor's, whose name is this project's (conductor_name).
BACKLOG="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${ROOT}/bin/swarm.sh" _conductor backlog)"
sed -i.bak '/^epic: /d' "${P}/docs/stories/tis.md"
add_events "${D}07:00:00Z"$'\tconduct\t--backlog\tw:1\tok' "${D}08:00:00Z"$'\tclose\tconduct-backlog-cleanup\tw:1\tok'
check "a story with no epic is held under the backlog conductor, which another epic's close does not end" "$(first_held)" 120
add_events "${D}07:00:00Z"$'\tconduct\t--backlog\tw:1\tok' "${D}08:00:00Z"$'\tclose\t'"${BACKLOG}"$'\tw:1\tok'
check "the backlog conductor's own close ends its run" "$(first_held)" 0
mv "${P}/docs/stories/tis.md.bak" "${P}/docs/stories/tis.md"
cp "${dir}/events.full" "${E}"
check "--since keeps the tells of builds before it in the retry's fixing" "$(out="$(outcomes --since 2026-10-02)" cols)" \
  "${D}11:35:00Z"$'\t0\t15\t5\t20\t15\t55'

# With no unblock, tis reached the board blocked at 06:30 and a commit readied it at 07:30.
board_commit() { # <status> <HH:MM>
  sed -i.bak "s/^status: .*/status: $1/" "${P}/docs/stories/tis.md" && rm "${P}/docs/stories/tis.md.bak"
  git -C "${P}" add docs/stories/tis.md
  GIT_COMMITTER_DATE="${D}$2:00Z" git -C "${P}" -c user.name=t -c user.email=t@t commit -qm "tis $1"
}
cp "${P}/docs/stories/tis.md" "${dir}/tis.md"
grep -v $'\tunblock\t' "${dir}/events.full" > "${E}"
board_commit blocked 06:30
check "a story added blocked, with no unblock or ready commit since, has no known ready time" "$(first_held)" ""
board_commit ready 07:30
check "a story readied by a board commit is held from that commit, not from its add" "$(first_held)" 90
board_commit blocked 08:00
check "a story blocked by a board commit after its last ready signal has no known ready time" "$(first_held)" ""
cp "${dir}/tis.md" "${P}/docs/stories/tis.md"
cp "${dir}/events.full" "${E}"

flow() { # [epic [since]] — the time_in_state section alone, as flow runs it, over the outcomes rows
  SWARM_ROWS="${out}" python3 "${ROOT}/bin/lib/flow_report.py" "${2:-0000-00-00}" 9999-12-30 "${1:-}" x x x x x x x "" x time_in_state
}
check "flow's epic line counts the PR once and the story's held time, in hours and shares, largest first, a tie in column order" "$(flow)" "$(printf '%s\n' \
  "## time_in_state" $'epic\tprs\thours\tlargest_first' $'e1\t1\t4.7\theld:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%' $'all\t1\t4.7\theld:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%')"
# The rebuild, dated 10-01, is the PR's first build: --since 2026-10-02 leaves the PR out, rather
# than counting the retry's 55 minutes for it.
check "a PR counts by its first build, in the window only when that build is" "$(flow "" 2026-10-02 | tail -1)" \
  $'all\t0\t0\tbuilding:0h/0% ci:0h/0% review_wait:0h/0% fixing:0h/0% merge_wait:0h/0% held:0h/0%'
# Another story of e1 that waited 3 h too but whose PR never merged: its held is not the merged PRs'.
other="$(awk -F'\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next } $at["started"] ~ /T09:00/ { $at["slug"] = "other"; print }' <<< "${out}")"
check "held counts only the stories of the PRs the phases count" "$(out="${out}"$'\n'"${other}" flow e1 | tail -1)" $'e1\t1\t4.7\theld:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%'
check "--epic prints that epic's line alone" "$(flow e1 | tail -1)" $'e1\t1\t4.7\theld:3h/64% review_wait:0.6h/12% fixing:0.4h/9% ci:0.2h/5% merge_wait:0.2h/5% building:0.2h/4%'

if [[ "${fails}" -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
