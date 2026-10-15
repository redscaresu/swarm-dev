#!/usr/bin/env bash
# cost_test.sh — `swarm.sh cost` against a fixture: two roles, a message logged twice (counted
# once), a codex agent (listed, not priced), an agent older than the `since` date (left out), and the
# arguments cost refuses.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
mkdir -p "${dir}/repo/.swarm" "${dir}/projects/p"
git -C "${dir}/repo" init -q

usage() { # <message id> <model> <input> <cache write> <cache read> <output>
  printf '{"message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$@"
}
{ usage m1 claude-opus-5-5 1000000 0 0 1000000; usage m1 claude-opus-5-5 1000000 0 0 1000000; } > "${dir}/projects/p/s-code.jsonl"
usage m2 claude-sonnet-5 0 0 10000000 0 > "${dir}/projects/p/s-survey.jsonl"
usage m3 claude-opus-5-5 5000000 0 0 0 > "${dir}/projects/p/s-old.jsonl"
printf '%s\n' \
  $'2026-09-29\tcode\tstory-a\tclaude\topus\thigh\ts-code' \
  $'2026-09-29\tsurvey\tsurvey-lands\tclaude\tsonnet\thigh\ts-survey' \
  $'2026-09-29\tcodex\tcodex\tcodex\tdefault\thigh\t-' \
  $'2026-09-01\tcode\tstory-old\tclaude\topus\thigh\ts-old' > "${dir}/repo/.swarm/agents.tsv"

out="$(cd "${dir}/repo" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" bash "${SWARM}" cost 2026-09-15)"
fails=0
check() { # <name> <line that must appear>
  if grep -qF -- "$2" <<< "${out}"; then echo "ok   $1"; else echo "FAIL $1: no line '$2'"; fails=$((fails + 1)); fi
}
# opus: 1M input x $4 + 1M output x $20 = $24, once despite the duplicate message
check "duplicate message counted once" "| code | 1 | claude-opus-5-5 | 1.0M | 0k | 0k | 1.0M | 24.00 |"
# sonnet: 10M cache read x $0.20 = $2
check "cache reads priced" "| survey | 1 | claude-sonnet-5 | 0k | 0k | 10.0M | 0k | 2.00 |"
check "codex listed, not priced" "| codex | 1 (1 not in the logs) | - |"
check "older than since is left out" "| **total** | 3 | | 1.0M | 0k | 10.0M | 1.0M | 26.00 |"

# --since names the same date the bare positional does
since_out="$(cd "${dir}/repo" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" bash "${SWARM}" cost --since 2026-09-15 2>&1)" || true
if [[ "${since_out}" == "${out}" ]]; then echo "ok   --since prints the same table"; else echo "FAIL --since table differs"; fails=$((fails + 1)); fi

# An argument cost does not understand is refused before any table
for args in "--since" "--since 2026-9-15" "bogus" "2026-09-15 extra"; do
  # shellcheck disable=SC2086 # word-split on purpose: each case is several arguments
  if bad="$(cd "${dir}/repo" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" bash "${SWARM}" cost ${args} 2>&1)"; then
    echo "FAIL cost ${args}: exited 0"; fails=$((fails + 1))
  elif ! grep -qF "usage: swarm.sh cost [--since YYYY-MM-DD]" <<< "${bad}" || grep -qF "**total**" <<< "${bad}"; then
    echo "FAIL cost ${args}: no usage line, or a table: ${bad}"; fails=$((fails + 1))
  else
    echo "ok   cost ${args} refused"
  fi
done

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
