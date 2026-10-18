#!/usr/bin/env bash
# subagent_cost_test.sh — `swarm.sh outcomes` splits a builder's subagents' cost from its own, by model,
# against fixture sessions in tests/fixtures/subagent/p, one in each shape Claude Code writes:
# s-inline.jsonl keeps its subagents' turns in its own log (parent_tool_use_id or isSidechain set), with
# damaged lines among them, and s-side.jsonl has them in s-side/subagents/*.jsonl beside it. Both
# builders run on Opus, with Haiku and Opus subagents. archived.jsonl is only close's copy of a deleted
# log, a builder has no log at all, and a conductor is no builder.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
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
  { print $at["slug"], $at["cost_usd"], $at["tokens"], $at["subagent_cost_usd"], $at["subagent_cost_by_model"] }' <<< "${out}"; }

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "damaged log lines stop no report" "${rc}" 0
# Opus $4 per 1M input and $20 per 1M output; Haiku $1 and $5.
# inline: own 1M in + 100k out = $6 (its turn logged twice counts once, a null token, a usage that is
# no object and a null model are skipped); haiku 1M in twice (parent_tool_use_id, isSidechain) = $2,
# opus 500k in = $2. side: own 2M in = $8; haiku 200k out = $1, opus 100k out + 250k in = $3.
# archived: own 1M in = $4, its inline subagent left out of it, and empty subagent cells: close's copy
# never holds subagents/, so the subagent cost is unknown.
check "each builder's own cost leaves out its subagents', which split by model in both shapes" "$(cols)" "$(printf '%s\n' \
  $'inline-story\t6.00\t1100000\t4.00\thaiku:2.00,opus:2.00' \
  $'side-story\t8.00\t2000000\t4.00\thaiku:1.00,opus:3.00' \
  $'no-log\t\t\t\t' \
  $'archived-story\t4.00\t1000000\t\t')"
check "one row per agents.tsv builder line" "$(($(wc -l <<< "${out}") - 1))" \
  "$(awk -F'\t' '$2 != "conduct"' "${P}/.swarm/agents.tsv" | wc -l | tr -d ' ')"

if [[ "${fails}" -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
