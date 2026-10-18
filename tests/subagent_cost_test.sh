#!/usr/bin/env bash
# subagent_cost_test.sh — `swarm.sh outcomes` splits builder subagents' cost from the builder's own, by
# model, in both shapes Claude Code writes: turns with parent_tool_use_id set inside the session log
# (fixture inline), and subagents/*.jsonl beside it (fixture split). Each has an Opus turn of its own
# and a Haiku and an Opus subagent turn. A third builder has no log, and a conductor is no builder.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/subagent"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${dir}/bin"
git -C "${P}" init -q
printf '%s\n' \
  $'2026-10-05\tcode\tinline\tclaude\topus\txhigh\tinline' \
  $'2026-10-05\tconduct\tconduct-e\tclaude\topus\thigh\tinline' \
  $'2026-10-06\tcode\tsplit\tclaude\topus\txhigh\tsplit' \
  $'2026-10-07\tcode\tnolog\tclaude\topus\txhigh\t-' > "${P}/.swarm/agents.tsv"
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${FIXTURES}" PATH="${dir}/bin:${PATH}" \
  bash "${SWARM}" outcomes | sed '/^$/,$d')"
cols() { # <column>... — those columns of every row, by header name, tab-separated
  awk -F'\t' -v want="$*" 'NR == 1 { n = split(want, w, " "); for (i = 1; i <= NF; i++) at[$i] = i; next }
    { line = ""; for (j = 1; j <= n; j++) line = line (j > 1 ? "\t" : "") $(at[w[j]]); print line }' <<< "${out}"
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "subagent cost and split by model, in both shapes" "$(cols slug subagent_cost_usd subagent_cost_by_model)" \
  $'inline\t3.00\thaiku:1.00,opus:2.00\nsplit\t3.00\thaiku:2.00,opus:1.00\nnolog\t\t'
check "the builder's own cost and tokens exclude its subagents" "$(cols slug cost_usd tokens)" \
  $'inline\t4.00\t1000000\nsplit\t2.00\t500000\nnolog\t\t'
check "one row per builder line in agents.tsv" "$(($(wc -l <<< "${out}") - 1))" \
  "$(awk -F'\t' '$2 == "code"' "${P}/.swarm/agents.tsv" | wc -l | tr -d ' ')"
check "the subagent columns come last" "$(head -1 <<< "${out}" | awk -F'\t' '{ print $(NF - 1) "\t" $NF }')" \
  $'subagent_cost_usd\tsubagent_cost_by_model'
[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
