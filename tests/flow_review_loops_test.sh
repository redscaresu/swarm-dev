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
# Epic e4's review hands over s-epic's PR (from its outcomes row) with another: s-epic passes. TZ is UTC.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
S="${dir}/.swarm"
mkdir -p "${S}"
P1=https://github.com/o/r/pull/1 P2=https://github.com/o/r/pull/2 P3=https://github.com/o/r/pull/3 P4=https://github.com/o/r/pull/4 P5=https://github.com/o/r/pull/5 P6=https://github.com/o/r/pull/6 P7=https://github.com/o/r/pull/7 P8=https://github.com/o/r/pull/8
printf '%s\n' $'2026-10-01\tcode\ts-loop\tclaude\topus\txhigh\ta1' $'2026-10-01\treview\treview-s-loop\tclaude\topus\thigh\ta2' \
  $'2026-10-01\tescalate\ts-loop\tclaude\tfable\txhigh\ta3' $'2026-10-01\tcode-risky\ts-held\tclaude\topus\txhigh\ta4' \
  $'2026-10-01\tcode\ts-retry\tclaude\tsonnet\thigh\ta5' $'2026-10-01\tescalate\ts-retry\tclaude\topus\txhigh\ta6' \
  $'2026-10-02\tescalate\ts-retry\tclaude\tfable\txhigh\ta7' $'2026-10-01\tcode\ts-epic\tclaude\topus\thigh\ta8' \
  $'2026-10-01\tcode\ts-part\tclaude\topus\thigh\ta9' $'2026-10-01\tcode\ts-rb\tclaude\topus\thigh\tb1' \
  $'2026-10-01\tescalate\ts-rb\tclaude\tfable\txhigh\tb2' $'2026-10-01\tescalate\ts-rb\tclaude\tfable\txhigh\tb3' \
  $'2026-10-01\tcode\ts-two\tclaude\topus\thigh\tc1' $'2026-10-01\tcode\ts-two\tclaude\topus\thigh\tc2' > "${S}/agents.tsv"
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
f() { printf '2026-10-01\tbug\t%s\tx\t%s\tcodex\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "${S}/findings.tsv"; }
f "${P1}" fixed "" 1; f "${P1}" fixed "" 1; f "${P1}" declined nit 1
f "${P1}" fixed "" 2
f "${P1}" fixed "" 3; f "${P1}" declined nit 3; f "${P1}" declined wrong 3
f "${P2}" fixed "" 1; f "${P2}" fixed "" 2
f "${P5}" fixed "" 1; f "${P5}" fixed "" 1
rows=$'date\tslug\tepic\tpr\n2026-10-01\ts-loop\te1\t\n2026-10-01\ts-held\te2\t'"${P2}"$'\n2026-10-01\ts-epic\te4\t'"${P4}"$'\n2026-10-01\ts-rb\te5\t'"${P5}"$'\n2026-10-01\ts-rb\te5\t'"${P5}"$'\n2026-10-01\ts-rb\te5\t'"${P6}"$'\n2026-10-01\ts-two\te6\t'"${P7}"$'\n2026-10-01\ts-two\te6\t'"${P8}"

loops() { # [since [epic]] — the review_loops section, as flow_sections runs it
  SWARM_FINDING_REVIEWERS="codex" SWARM_LADDER=sonnet,opus,fable SWARM_ROWS="${rows}" python3 "${ROOT}/bin/lib/flow_report.py" \
    "${1:-0000-00-00}" 9999-12-30 "${2:-}" "${S}/agents.tsv" "${S}/events.tsv" "${S}/findings.tsv" x "code code-risky escalate" x x "" x review_loops \
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
check "end states: a last round with nothing fixed is pass; an escalated line is held-for-lead" "$(sed -n '/^story\tpr\trounds\tend$/,/^$/p' <<< "${out}")" \
  "$(printf '%s\n' $'story\tpr\trounds\tend' $'s-epic\t'"${P4}"$'\t1\tpass' $'s-held\t'"${P2}"$'\t2\theld-for-lead' $'s-loop\t'"${P1}"$'\t4\tpass' $'s-part\t-\t1\topen' $'s-rb\t'"${P5}"$'\t1\theld-for-lead' $'s-rb\t'"${P6}"$'\t1\tpass' $'s-retry\t-\t1\topen' $'s-retry\t'"${P3}"$'\t1\tpass' $'s-two\t'"${P7}"$'\t1\tpass' $'s-two\t'"${P8}"$'\t1\tpass' '')"
check "a step-up before review shows on round 1; a restarted review agent times the round from the restart; an escalate build is its own loop, on its model, with its own PR" \
  "$(grep $'^s-retry\t' <<< "${out}")" \
  "$(printf '%s\n' $'s-retry\t-\t1\topus\t10\t0\t0\tno-pr: sonnet -> opus ok before review' $'s-retry\t'"${P3}"$'\t1\tfable\t5\t0\t0\t-' \
    $'s-retry\t-\t1\topen' $'s-retry\t'"${P3}"$'\t1\tpass')"
check "a tell whose step-up failed partway closes its round, with a failed findings step-up" "$(grep $'^s-part\t' <<< "${out}" | head -1)" \
  $'s-part\t-\t1\topus\t10\t0\t0\tfindings: ? -> ? failed'
check "a resumed findings step-up stays on its round; each build is its own loop, held or not, with its own outcomes row's PR" \
  "$(grep $'^s-rb\t' <<< "${out}")" \
  "$(printf '%s\n' $'s-rb\t'"${P5}"$'\t1\topus\t10\t2\t0\tfindings: ? -> ? failed, findings-3: opus -> fable ok' $'s-rb\t'"${P6}"$'\t1\tfable\t10\t0\t0\t-' \
    $'s-rb\t'"${P5}"$'\t1\theld-for-lead' $'s-rb\t'"${P6}"$'\t1\tpass')"
check "the window keeps a story's builds with a loop line in it" "$(loops 2026-10-02 | sed -n '/^story\tpr\trounds/,/^$/p')" \
  "$(printf '%s\n' $'story\tpr\trounds\tend' $'s-retry\t'"${P3}"$'\t1\tpass' '')"
check "an epic's review of an earlier build's PR closes that build's round" "$(grep $'^s-two\t' <<< "${out}")" \
  "$(printf '%s\n' $'s-two\t'"${P7}"$'\t1\topus\t20\t0\t0\t-' $'s-two\t'"${P8}"$'\t1\topus\t5\t0\t0\t-' \
    $'s-two\t'"${P7}"$'\t1\tpass' $'s-two\t'"${P8}"$'\t1\tpass')"
check "an epic's review closes the round of each story whose PR it names" "$(grep $'^s-epic\t' <<< "${out}" | head -1)" \
  $'s-epic\t'"${P4}"$'\t1\topus\t20\t0\t0\t-'
# rounds 1 (eight PRs), 2 and 4; round 3 on: 30 + 15 minutes; 8 fixes: 5, 2 and 1 by round, none on fable;
# 6 fixes over 4 rounds up to a step-up (s-loop's rounds 1-3, s-rb's round 1), none over the 2 after
# (s-loop's round 4, s-retry's first build's round); s-held's, s-part's and s-rb's failed step-ups.
check "the totals match the fixtures" "$(tail -2 <<< "${out}")" \
  "$(printf '%s\n' $'prs\trounds_median\trounds_p90\tmin_round3_on\tfixes\tround1\tround2\tround3_on\ttop_rung\tstepped_up\tfixes_per_round_before\tfixes_per_round_after\tfailed_step_ups' \
    $'10\t1\t2\t45\t8\t63%\t25%\t13%\t0%\t3\t1.5\t0\t3')"
check "--epic keeps that epic's stories" "$(loops "" e2 | cut -f1 | sort -u | tr '\n' ' ')" " 1 prs s-held story "
check "--since past the loops leaves them out, in one line" "$(loops 2026-10-03)" "no review loop in the window"

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
