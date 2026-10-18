#!/usr/bin/env bash
# subagent_cost_test.sh — `swarm.sh outcomes` splits a builder's subagents' cost from its own, by model,
# against fixture sessions in tests/fixtures/subagent/p, one in each shape Claude Code writes:
# s-inline.jsonl keeps its subagents' turns in its own log (parent_tool_use_id or isSidechain set), with
# damaged lines among them, and s-side.jsonl has them in s-side/subagents/*.jsonl beside it. Both
# builders run on Opus, with Haiku and Opus subagents. archived.jsonl is only close's copy of a deleted
# log, with an inline subagent turn, a builder has no log at all, and a conductor is no builder.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"
mkdir -p "${P}/.swarm/sessions" "${dir}/nobin"
gzip -c "${ROOT}/tests/fixtures/subagent/archived.jsonl" > "${P}/.swarm/sessions/2026-10-04-archived-story-s-archived.jsonl.gz"
git -C "${P}" init -q
printf '#!/bin/sh\nexit 1\n' > "${dir}/nobin/gh" && chmod +x "${dir}/nobin/gh"
printf '%s\n' \
  $'2026-10-01\tcode\tinline-story\tclaude\topus\txhigh\ts-inline' \
  $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts-inline' \
  $'2026-10-02\tcode\tside-story\tclaude\topus\txhigh\ts-side' \
  $'2026-10-03\tcode\tno-log\tclaude\topus\txhigh\t-' \
  $'2026-10-04\tcode\tarchived-story\tclaude\topus\txhigh\ts-archived' > "${P}/.swarm/agents.tsv"

rc=0
out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${ROOT}/tests/fixtures/subagent" \
  PATH="${dir}/nobin:${PATH}" bash "${ROOT}/bin/swarm.sh" outcomes | sed '/^$/,$d')" || rc=$?
# slug, then each named column, from the report's own header.
cols() { awk -F'\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next }
  { print $at["slug"], $at["cost_usd"], $at["tokens"], $at["subagent_cost_usd"], $at["subagent_cost_by_model"], $at["subagent_tokens"] }' <<< "${out}"; }

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "damaged log lines stop no report" "${rc}" 0
# Opus $4 per 1M input and $20 per 1M output; Haiku $1 and $5.
# inline: own 1M in + 100k out = $6 (its turn logged twice counts once; a null token, a usage that is
# no object, a null model and a list for a model are skipped); haiku 1M in twice (parent_tool_use_id,
# isSidechain) = $2, opus 500k in = $2, an unpriced model 1k in = $0 (as other), 2,501,000 subagent tokens. side: own 2M in = $8; haiku 200k out =
# $1, opus 100k out + 250k in = $3, 550k subagent tokens. archived (close's copy, no subagents/): own
# 1M in = $4, and its inline Haiku subagent 1M in = $1 in the subagent cells.
check "each builder's own cost and tokens leave out its subagents', which split by model in both shapes" "$(cols)" "$(printf '%s\n' \
  $'inline-story\t6.00\t1100000\t4.00\thaiku:2.00,opus:2.00,other:0.00\t2501000' \
  $'side-story\t8.00\t2000000\t4.00\thaiku:1.00,opus:3.00\t550000' \
  $'no-log\t\t\t\t\t' \
  $'archived-story\t4.00\t1000000\t1.00\thaiku:1.00\t1000000')"
# Every priced turn of each fixture: inline $10, side $12, archived $5.
check "cost_usd plus subagent_cost_usd is every turn the logs hold, close's copy too" "$(awk -F'\t' -v OFS='\t' \
  'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next } $at["cost_usd"] != "" { printf "%s\t%.2f\n", $at["slug"], $at["cost_usd"] + $at["subagent_cost_usd"] }' <<< "${out}")" \
  "$(printf '%s\n' $'inline-story\t10.00' $'side-story\t12.00' $'archived-story\t5.00')"
check "a subagent model with no price, a tab, colon and comma in its name, goes under other" \
  "$(cut -f5 <<< "$(cols)" | head -1)" "haiku:2.00,opus:2.00,other:0.00"
check "one row per agents.tsv builder line" "$(($(wc -l <<< "${out}") - 1))" \
  "$(awk -F'\t' '$2 != "conduct"' "${P}/.swarm/agents.tsv" | wc -l | tr -d ' ')"


# outcomes_join skips a row of the wrong width (a tab from a damaged log) with a warning, and prints the rest.
good="2026-10-01$(printf '\tx%.0s' {1..10})"$'\t1\t-'"$(printf '\t%.0s' {1..16})"
rc=0
joined="$(SWARM_FINDING_REVIEWERS=codex SWARM_META="" SWARM_ROWS="${good}"$'\n'"${good}"$'\textra' \
  python3 "${ROOT}/bin/lib/outcomes_join.py" "${dir}/none.tsv" "${P}" "${dir}/none.tsv" 2> "${dir}/err" | sed '/^$/,$d')" || rc=$?
check "a row of the wrong width is skipped with one warning, and the report goes on" \
  "${rc} $(($(wc -l <<< "${joined}") - 1)) $(grep -c 'skipped a row of 30 columns, not 29' "${dir}/err")" "0 1 1"

if [[ "${fails}" -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
