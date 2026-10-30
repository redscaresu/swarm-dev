#!/usr/bin/env bash
# flow_review_loops_test.sh — `swarm.sh flow`'s review_loops section against fixture events.tsv,
# findings.tsv and agents.tsv. s-loop starts on opus: three rounds of findings (10, 20 and 30 minutes
# from each review agent's start to its tell), the third a findings-3 step-up to fable in place of the
# tell, then a fourth round on fable that fixes nothing, handed over and merged: pass. Its PR comes
# from its review line. s-held has two rounds on opus, a step-up that failed in the second, then an
# escalated line: held-for-lead; its PR comes from its outcomes row. s-retry steps up sonnet -> opus
# before any review, restarts its review agent (the round times from the restart), then is built again
# by an escalate build on fable on 10-02 (its escalate line, then its story line) with its own PR: two
# loops, the second its rung's agents.tsv line after the opus one. s-part's findings tell finds its
# step-up failed partway: the round closes with a failed findings step-up. s-rb's findings step-up fails
# partway, is resumed (on the same round), and its lead holds it; an escalate build then passes on its
# own PR. Its first build's PR comes from that build's outcomes row (one row per agents.tsv line). s-two
# is built twice, and epic e6's reviews hand over each build's PR: both pass.
# Epic e4's review hands over s-epic's PR (from its outcomes row) with another: s-epic passes. A review
# hand-over alone is no merge: pass and merged-after-fixes need a merge line or the PR merged in outcomes,
# so s-retry's P3, handed over and never merged, and s-two's P7, closed, are open. s-same is built twice
# on one PR: each finding goes to the build whose rounds hold its round. s-nopr's rebuild has no PR
# yet: it takes none of its first build's findings. s-ref's step-up is refused before it changed
# anything: no failed step-up. s-nor only steps up, with no review: a row with no round and no end
# state. s-esc's escalate build starts late on 10-04 and is reviewed on 10-05: its start line puts it in
# a 10-04 window. Rounds count per PR: s-same's second build's review is its PR's round 2. s-agent's
# conductor-started builder (an agent line) is a build on sonnet, its own agents.tsv line, so the escalate
# build after it runs on fable with its own outcomes row's PR. s-mm merges, then is built again: the
# rebuild is its own loop. s-retry's fable round fixes one: the top rung's share. TZ is UTC.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
S="${dir}/.swarm"
mkdir -p "${S}"
P1=https://github.com/o/r/pull/1 P2=https://github.com/o/r/pull/2 P3=https://github.com/o/r/pull/3 P4=https://github.com/o/r/pull/4 P5=https://github.com/o/r/pull/5 P6=https://github.com/o/r/pull/6 P7=https://github.com/o/r/pull/7 P8=https://github.com/o/r/pull/8 P10=https://github.com/o/r/pull/10 P11=https://github.com/o/r/pull/11 P12=https://github.com/o/r/pull/12 P13=https://github.com/o/r/pull/13 P14=https://github.com/o/r/pull/14 P15=https://github.com/o/r/pull/15
printf '%s\n' $'2026-10-01\tcode\ts-loop\tclaude\topus\txhigh\ta1' $'2026-10-01\treview\treview-s-loop\tclaude\topus\thigh\ta2' \
  $'2026-10-01\tescalate\ts-loop\tclaude\tfable\txhigh\ta3' $'2026-10-01\tcode-risky\ts-held\tclaude\topus\txhigh\ta4' \
  $'2026-10-01\tcode\ts-retry\tclaude\tsonnet\thigh\ta5' $'2026-10-01\tescalate\ts-retry\tclaude\topus\txhigh\ta6' \
  $'2026-10-02\tescalate\ts-retry\tclaude\tfable\txhigh\ta7' $'2026-10-01\tcode\ts-epic\tclaude\topus\thigh\ta8' \
  $'2026-10-01\tcode\ts-part\tclaude\topus\thigh\ta9' $'2026-10-01\tcode\ts-rb\tclaude\topus\thigh\tb1' \
  $'2026-10-01\tescalate\ts-rb\tclaude\tfable\txhigh\tb2' $'2026-10-01\tescalate\ts-rb\tclaude\tfable\txhigh\tb3' \
  $'2026-10-01\tcode\ts-two\tclaude\topus\thigh\tc1' $'2026-10-01\tcode\ts-two\tclaude\topus\thigh\tc2' \
  $'2026-10-01\tcode\ts-same\tclaude\topus\thigh\td1' $'2026-10-02\tcode\ts-same\tclaude\topus\thigh\td2' \
  $'2026-10-01\tcode\ts-nopr\tclaude\topus\thigh\te1' $'2026-10-02\tcode\ts-nopr\tclaude\topus\thigh\te2' \
  $'2026-10-01\tcode\ts-ref\tclaude\topus\thigh\tf1' $'2026-10-01\tcode\ts-nor\tclaude\tsonnet\thigh\tg1' \
  $'2026-10-01\tescalate\ts-nor\tclaude\topus\txhigh\tg2' $'2026-10-01\tcode\ts-esc\tclaude\topus\thigh\th1' \
  $'2026-10-04\tescalate\ts-esc\tclaude\tfable\txhigh\th2' $'2026-10-01\tcode\ts-agent\tclaude\topus\thigh\ti1' \
  $'2026-10-01\tcode-sonnet\ts-agent\tclaude\tsonnet\thigh\ti2' $'2026-10-01\tescalate\ts-agent\tclaude\tfable\txhigh\ti3' \
  $'2026-10-01\tcode\ts-mm\tclaude\topus\thigh\tj1' $'2026-10-01\tcode\ts-mm\tclaude\topus\thigh\tj2' > "${S}/agents.tsv"
ev() { printf '%sT%s:00Z\t%s\t%s\t-\t%s\n' "${DAY:-2026-10-01}" "$1" "$2" "$3" "$4" >> "${S}/events.tsv"; }
ev 10:00 story s-loop ok
ev 11:00 review-agent s-loop ok
ev 11:10 tell:findings s-loop ok
ev 12:00 review-agent s-loop ok
ev 12:20 tell:findings s-loop ok
ev 13:00 review-agent s-loop ok
ev 13:30 escalate s-loop "ok (findings-3: opus -> fable)"
ev 13:30 tell:findings s-loop "tell: s-loop was not told: these were findings round 3 of its build, so it was stepped up"
ev 15:00 review-agent s-loop ok
ev 15:15 review s-loop "ok (${P1})"
ev 15:16 merge s-loop ok
ev 10:00 review-agent s-held ok
ev 10:05 tell:findings s-held ok
ev 11:00 review-agent s-held ok
ev 11:20 tell:findings s-held ok
ev 11:30 step-up:resume s-held "step-up: s-held's opus builder is closed, but the fable builder did not start (see above)"
ev 12:00 escalated s-held "ok (attempts 2, 1 PRs)"
ev 09:00 story s-retry ok
ev 09:30 escalate s-retry "ok (no-pr: sonnet -> opus)"
ev 10:00 review-agent s-retry ok
ev 10:30 review-agent s-retry ok
ev 10:40 tell:findings s-retry ok
DAY=2026-10-02 ev 11:00 escalate s-retry "ok (attempt 2)"
DAY=2026-10-02 ev 11:00 story s-retry ok
DAY=2026-10-02 ev 12:00 review-agent s-retry ok
DAY=2026-10-02 ev 12:05 review s-retry "ok (${P3})"
ev 14:00 review-agent s-part ok
ev 14:10 tell:findings s-part "tell: s-part was not told: its step-up failed partway, after its builder was closed; list it for the lead"
ev 16:00 story s-rb ok
ev 16:10 review-agent s-rb ok
ev 16:20 tell:findings s-rb "tell: s-rb was not told: its step-up failed partway, after its builder was closed; list it for the lead"
ev 16:30 escalate s-rb "ok (findings-3: opus -> fable)"
ev 16:40 escalated s-rb "ok (attempts 1, 1 PRs)"
ev 17:00 escalate s-rb "ok (attempt 2)"
ev 17:00 story s-rb ok
ev 17:10 review-agent s-rb ok
ev 17:20 review s-rb "ok (${P6})"
ev 18:00 story s-two ok
ev 18:10 review-agent s-two ok
ev 18:30 review e6 "ok (${P7})"
ev 19:00 story s-two ok
ev 19:10 review-agent s-two ok
ev 19:15 review e6 "ok (${P8})"
ev 13:00 review-agent s-epic ok
ev 13:20 review e4 "ok (${P4} https://github.com/o/r/pull/9)"
ev 08:00 story s-same ok
ev 08:10 review-agent s-same ok
ev 08:20 tell:findings s-same ok
DAY=2026-10-02 ev 08:00 story s-same ok
DAY=2026-10-02 ev 08:10 review-agent s-same ok
DAY=2026-10-02 ev 08:30 tell:findings s-same ok
ev 09:00 story s-nopr ok
ev 09:10 review-agent s-nopr ok
ev 09:15 tell:findings s-nopr ok
DAY=2026-10-02 ev 09:00 story s-nopr ok
DAY=2026-10-02 ev 09:10 review-agent s-nopr ok
ev 20:00 step-up s-ref "step-up: escalate_ladder is empty (off), so there is no next model; nothing was closed"
ev 20:10 review-agent s-ref ok
ev 20:20 tell:findings s-ref ok
ev 21:00 escalate s-nor "ok (no-pr: sonnet -> opus)"
ev 06:00 story s-esc ok
ev 06:10 review-agent s-esc ok
ev 06:20 tell:findings s-esc ok
DAY=2026-10-04 ev 23:50 escalate s-esc "ok (attempt 2)"
DAY=2026-10-04 ev 23:50 story s-esc ok
DAY=2026-10-05 ev 00:10 review-agent s-esc ok
DAY=2026-10-05 ev 00:20 tell:findings s-esc ok
ev 05:00 story s-agent ok
ev 05:10 review-agent s-agent ok
ev 05:20 tell:findings s-agent ok
ev 05:30 agent s-agent ok
ev 05:40 review-agent s-agent ok
ev 05:50 tell:findings s-agent ok
ev 06:00 escalate s-agent "ok (attempt 2)"
ev 06:00 story s-agent ok
ev 06:10 review-agent s-agent ok
ev 06:20 merge s-agent ok
ev 03:00 story s-mm ok
ev 03:10 review-agent s-mm ok
ev 03:20 merge s-mm ok
ev 04:00 story s-mm ok
ev 04:10 review-agent s-mm ok
ev 04:20 tell:findings s-mm ok
f() { printf '%s\tbug\t%s\tx\t%s\tcodex\t%s\t%s\n' "${DAY:-2026-10-01}" "$1" "$2" "$3" "$4" >> "${S}/findings.tsv"; }
f "${P1}" fixed "" 1; f "${P1}" fixed "" 1; f "${P1}" declined nit 1
f "${P1}" fixed "" 2
f "${P1}" fixed "" 3; f "${P1}" declined nit 3; f "${P1}" declined wrong 3
f "${P2}" fixed "" 1; f "${P2}" fixed "" 2
f "${P5}" fixed "" 1; f "${P5}" fixed "" 1
f "${P10}" fixed "" 1; DAY=2026-10-02 f "${P10}" fixed "" 2; DAY=2026-10-02 f "${P10}" declined nit 2
f "${P3}" fixed "" 1
f "${P11}" fixed "" 1; DAY=2026-10-02 f "${P11}" declined nit 1
rows="$(printf '%s\t%s\t%s\t%s\t%s\n' date slug epic pr pr_state 2026-10-01 s-loop e1 '' '' 2026-10-01 s-held e2 "${P2}" OPEN \
  2026-10-01 s-epic e4 "${P4}" MERGED 2026-10-01 s-rb e5 "${P5}" OPEN 2026-10-01 s-rb e5 "${P5}" OPEN 2026-10-01 s-rb e5 "${P6}" MERGED \
  2026-10-01 s-two e6 "${P7}" CLOSED 2026-10-01 s-two e6 "${P8}" MERGED 2026-10-01 s-same e7 "${P10}" OPEN 2026-10-02 s-same e7 "${P10}" OPEN \
  2026-10-01 s-nopr e8 "${P11}" OPEN 2026-10-02 s-nopr e8 '' '' 2026-10-01 s-agent e9 "${P12}" OPEN 2026-10-01 s-agent e9 "${P12}" OPEN \
  2026-10-01 s-agent e9 "${P13}" MERGED 2026-10-01 s-mm e10 "${P14}" MERGED 2026-10-01 s-mm e10 "${P15}" OPEN)"

loops() { # [since [epic [until]]] — the review_loops section, as flow_sections runs it
  SWARM_FINDING_REVIEWERS="codex" SWARM_LADDER=sonnet,opus,fable SWARM_ROWS="${rows}" python3 "${ROOT}/bin/lib/flow_report.py" \
    "${1:-0000-00-00}" "${3:-9999-12-30}" "${2:-}" "${S}/agents.tsv" "${S}/events.tsv" "${S}/findings.tsv" x "code code-risky code-sonnet escalate" x x "" x review_loops \
    | grep -v '^## review_loops$'
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(loops)"
check "each round's model, minutes, fixed and declined, and the step-up on the round that took it" "$(grep $'^s-loop\t' <<< "${out}" | head -4)" \
  "$(printf '%s\n' $'s-loop\t'"${P1}"$'\t1\topus\t10\t2\t1\t-' $'s-loop\t'"${P1}"$'\t2\topus\t20\t1\t0\t-' \
    $'s-loop\t'"${P1}"$'\t3\topus\t30\t1\t2\tfindings-3: opus -> fable ok' $'s-loop\t'"${P1}"$'\t4\tfable\t15\t0\t0\t-')"
check "a failed step-up shows on its round, and its PR comes from the outcomes row" "$(grep $'^s-held\t' <<< "${out}" | head -2)" \
  "$(printf '%s\n' $'s-held\t'"${P2}"$'\t1\topus\t5\t1\t0\t-' $'s-held\t'"${P2}"$'\t2\topus\t20\t1\t0\t?: opus -> fable failed')"
row() { awk -F'\t' -v s="$1" '$1 == s && NF == 8' <<< "${2:-${out}}"; }   # <slug> [output] — its round rows
end() { sed -n '/^story\tpr\trounds\tend$/,/^$/p' <<< "$1" | grep $'^'"$2"$'\t'; }
check "end states: pass or merged-after-fixes once merged (a merge line, or merged in outcomes); held-for-lead after an escalated line; else open" \
  "$(end "${out}" 's-[a-z]*')" "$(printf '%s\t%s\t%s\t%s\n' s-agent "${P12}" 1 open s-agent "${P12}" 2 open s-agent "${P13}" 1 pass s-epic "${P4}" 1 pass s-esc - 1 open s-esc - 1 open s-held "${P2}" 2 held-for-lead \
    s-loop "${P1}" 4 pass s-mm "${P14}" 1 pass s-mm "${P15}" 1 open s-nopr "${P11}" 1 open s-nopr - 1 open s-part - 1 open s-rb "${P5}" 1 held-for-lead s-rb "${P6}" 1 pass \
    s-ref - 1 open s-retry - 1 open s-retry "${P3}" 1 open s-same "${P10}" 1 open s-same "${P10}" 2 open s-two "${P7}" 1 open s-two "${P8}" 1 pass)"
check "a step-up before review shows on round 1; a restarted review agent times the round from the restart; an escalate build is its own loop, on its model, with its own PR" \
  "$(row s-retry)" "$(printf '%s\n' $'s-retry\t-\t1\topus\t10\t0\t0\tno-pr: sonnet -> opus ok before review' $'s-retry\t'"${P3}"$'\t1\tfable\t5\t1\t0\t-')"
check "a tell whose step-up failed partway closes its round, with a failed findings step-up" "$(row s-part)" \
  $'s-part\t-\t1\topus\t10\t0\t0\tfindings: ? -> ? failed'
check "a resumed findings step-up stays on its round; each build is its own loop, held or not, with its own outcomes row's PR" \
  "$(row s-rb)" "$(printf '%s\n' $'s-rb\t'"${P5}"$'\t1\topus\t10\t2\t0\tfindings: ? -> ? failed, findings-3: opus -> fable ok' $'s-rb\t'"${P6}"$'\t1\tfable\t10\t0\t0\t-')"
check "the window keeps a story's builds with a loop line in it" "$(end "$(loops 2026-10-02)" s-retry)" $'s-retry\t'"${P3}"$'\t1\topen'
check "an escalate build's start line puts its loop in the window" "$(row s-esc "$(loops 2026-10-04 "" 2026-10-04)")" $'s-esc\t-\t1\tfable\t10\t0\t0\t-'
check "an epic's review of an earlier build's PR closes that build's round" "$(row s-two)" \
  "$(printf '%s\n' $'s-two\t'"${P7}"$'\t1\topus\t20\t0\t0\t-' $'s-two\t'"${P8}"$'\t1\topus\t5\t0\t0\t-')"
check "an epic's review closes the round of each story whose PR it names" "$(row s-epic)" $'s-epic\t'"${P4}"$'\t1\topus\t20\t0\t0\t-'
check "rounds count per PR: a second build on a PR starts after the first's rounds, and takes the findings of its own" "$(row s-same)" \
  "$(printf '%s\n' $'s-same\t'"${P10}"$'\t1\topus\t10\t1\t0\t-' $'s-same\t'"${P10}"$'\t2\topus\t20\t1\t1\t-')"
check "an agent line starts a build on its own agents.tsv line, and the builds after it take theirs" "$(row s-agent)" \
  "$(printf '%s\n' $'s-agent\t'"${P12}"$'\t1\topus\t10\t0\t0\t-' $'s-agent\t'"${P12}"$'\t2\tsonnet\t10\t0\t0\t-' $'s-agent\t'"${P13}"$'\t1\tfable\t10\t0\t0\t-')"
check "a merge ends only its loop: a later build of the story is its own loop" "$(row s-mm)" \
  "$(printf '%s\n' $'s-mm\t'"${P14}"$'\t1\topus\t10\t0\t0\t-' $'s-mm\t'"${P15}"$'\t1\topus\t10\t0\t0\t-')"
check "a rebuild with no PR yet takes none of its first build's findings" "$(row s-nopr)" \
  "$(printf '%s\n' $'s-nopr\t'"${P11}"$'\t1\topus\t5\t1\t1\t-' $'s-nopr\t-\t1\topus\t-\t0\t0\t-')"
check "a step-up refused before it changed anything is no step-up" "$(row s-ref)" $'s-ref\t-\t1\topus\t10\t0\t0\t-'
check "a loop with no round shows its step-ups on a row with no round, and no end state" "$(row s-nor)|$(end "${out}" s-nor)" \
  $'s-nor\t-\t-\topus\t-\t0\t0\tno-pr: sonnet -> opus ok before review|'
# 14 PRs (each once, loops with no PR left out): rounds 1 (ten), 2 (three) and 4; round 3 on: 30 + 15
# minutes; 12 fixes: 8, 3 and 1 by round, one on fable (s-retry's); 6 fixes over 4 rounds up to a step-up (s-loop's rounds 1-3,
# s-rb's round 1), none over the 2 after (s-loop's round 4, s-retry's first build's round); s-held's,
# s-part's and s-rb's failed step-ups, s-ref's refused one not among them.
check "the totals match the fixtures" "$(tail -2 <<< "${out}")" \
  "$(printf '%s\n' $'prs\trounds_median\trounds_p90\tmin_round3_on\tfixes\tround1\tround2\tround3_on\ttop_rung\tstepped_up\tfixes_per_round_before\tfixes_per_round_after\tfailed_step_ups' \
    $'14\t1\t2\t45\t12\t67%\t25%\t8%\t8%\t3\t1.5\t0\t3')"
check "prs, rounds_median and rounds_p90 count each PR once, and no loop with no PR" "$(tail -1 <<< "${out}" | cut -f1-3)" $'14\t1\t2'
check "a fixed finding on a top-rung round gives top_rung its share" "$(tail -1 <<< "${out}" | cut -f9)" "8%"
check "--epic keeps that epic's stories" "$(loops "" e2 | cut -f1 | sort -u | tr '\n' ' ')" " 1 prs s-held story "
check "--since past the loops leaves them out, in one line" "$(loops 2026-10-06)" "no review loop in the window"

# decline-only cases, in logs of their own so the totals above keep their fixtures: s-dec's builder
# declined round 1's findings and pushed nothing, so its review --head wrote a decline-only line, and
# the review and merge after it close no round 2; s-nodec has the same lines without it; s-sent's
# findings tell failed after herdr sent it (review_rounds counts it as a round, this reader does not), so
# its round is still open when its decline-only line comes, and that line closes it; s-dec2's round 2
# findings went that way too, after a review-agent:next this reader skips, so its decline-only line
# names round 2 and the build gets a second round with no minutes.
D="${dir}/decline"; mkdir -p "${D}"; : > "${D}/findings.tsv"
printf '%s\n' $'2026-10-01\tcode\ts-dec\tclaude\topus\thigh\tk1' $'2026-10-01\tcode\ts-nodec\tclaude\topus\thigh\tk2' \
  $'2026-10-01\tcode\ts-sent\tclaude\topus\thigh\tk3' $'2026-10-01\tcode\ts-dec2\tclaude\topus\thigh\tk4' > "${D}/agents.tsv"
P21=https://github.com/o/r/pull/21 P22=https://github.com/o/r/pull/22 P23=https://github.com/o/r/pull/23 P24=https://github.com/o/r/pull/24
sent='may or may not have the brief: herdr sent it the brief, but no turn started; the findings count as delivered, a findings round of its build, so do not send them again'
dev() { printf '2026-10-01T07:%s:00Z\t%s\t%s\t-\t%s\n' "$1" "$2" "$3" "$4" >> "${D}/events.tsv"; }
for s in s-dec s-nodec s-sent s-dec2; do
  case "${s}" in s-dec) dpr="${P21}" ;; s-nodec) dpr="${P22}" ;; s-sent) dpr="${P23}" ;; *) dpr="${P24}" ;; esac
  dev 00 story "${s}" ok; dev 10 review-agent "${s}" ok
  if [[ "${s}" == s-sent ]]; then dev 20 tell:findings "${s}" "${sent}"; else dev 20 tell:findings "${s}" ok; fi
  if [[ "${s}" == s-dec2 ]]; then dev 22 review-agent:next "${s}" "ok (round 2)"; dev 25 tell:findings "${s}" "${sent}"; fi
  case "${s}" in s-nodec) ;; s-dec2) dev 30 decline-only "${s}" "ok (round 2)" ;; *) dev 30 decline-only "${s}" "ok (round 1)" ;; esac
  dev 30 review "${s}" "ok (${dpr})"; dev 31 merge "${s}" ok
done
dout="$(SWARM_FINDING_REVIEWERS="codex" SWARM_ROWS="$(printf 'date\tslug\tepic\tpr\tpr_state')" python3 "${ROOT}/bin/lib/flow_report.py" \
  0000-00-00 9999-12-30 "" "${D}/agents.tsv" "${D}/events.tsv" "${D}/findings.tsv" x "code" x x "" x review_loops)"
check "decline-only cases: a review after a decline-only line closes no round, and the loop ends decline-only" \
  "$(row s-dec "${dout}")|$(end "${dout}" s-dec)" $'s-dec\t'"${P21}"$'\t1\topus\t10\t0\t0\t-|s-dec\t'"${P21}"$'\t1\tdecline-only'
check "decline-only cases: the same lines with no decline-only line close round 2 and end pass" \
  "$(end "${dout}" s-nodec)" $'s-nodec\t'"${P22}"$'\t2\tpass'
check "decline-only cases: a decline-only line closes a round still open (its tell failed after herdr sent it), and the loop ends decline-only" \
  "$(row s-sent "${dout}")|$(end "${dout}" s-sent)" $'s-sent\t'"${P23}"$'\t1\topus\t20\t0\t0\t-|s-sent\t'"${P23}"$'\t1\tdecline-only'
check "decline-only cases: a decline-only line naming round 2 after a round this reader did not see gives the build two rounds, the second with no minutes, and end decline-only" \
  "$(row s-dec2 "${dout}")|$(end "${dout}" s-dec2)" $'s-dec2\t'"${P24}"$'\t1\topus\t10\t0\t0\t-\ns-dec2\t'"${P24}"$'\t2\topus\t-\t0\t0\t-|s-dec2\t'"${P24}"$'\t2\tdecline-only'

# flow passes escalate_ladder: with none, top_rung is -.
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/.claude/swarm"
git -C "${P}" init -q
cp "${S}/events.tsv" "${S}/findings.tsv" "${P}/.swarm/"
top() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=review_loops bash "${ROOT}/bin/swarm.sh" flow | tail -1 | cut -f9); }
check "with no escalate_ladder, top_rung is -" "$(top)" "-"
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
check "flow passes escalate_ladder: the top rung is its last model" "$(top)" "0%"

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
