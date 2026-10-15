#!/usr/bin/env bash
# cost_test.sh — `swarm.sh cost` against a fixture: two roles, a message logged twice (counted
# once), a codex agent (listed, not priced), and an agent older than the `since` date (left out); then
# the same agents read from close's copies of their session logs once Claude Code deleted them. The
# project and Claude's projects dir carry [x] in their names, which must be read as paths, not patterns.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
R="${dir}/repo[x]"; C="${dir}/projects[x]"
mkdir -p "${R}/.swarm" "${C}/p"
git -C "${R}" init -q

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

run() { (cd "${R}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${C}" bash "${SWARM}" "$@"); }
out="$(run cost 2026-09-15)"
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

# close's copies (written by archive_session, through its _archive test hook).
live="${out}"
run _archive story-a; run _archive survey-lands
mv "${R}/.swarm/sessions/"*-s-code.jsonl.gz "${R}/.swarm/sessions/2026-01-01-story-a-s-code.jsonl.gz"
run _archive story-a
same "close keeps one copy per session, under a [x] path too" "$(find "${R}/.swarm/sessions" -name '*-s-code.jsonl.gz' | wc -l | tr -d ' ')" 1
usage m4 claude-opus-5-5 0 0 0 1000000 > "${C}/p/s-code.jsonl"
out="$(run cost 2026-09-15)"
check "with both the live log and close's copy, the live log wins" "| code | 1 | claude-opus-5-5 | 0k | 0k | 0k | 1.0M | 20.00 |"
rm "${C}/p/s-code.jsonl" "${C}/p/s-survey.jsonl"
snap() { (cd "${R}/.swarm" && find . | sort && find . -type f -exec cksum {} + | sort); }
before="$(snap)"
same "with only close's copies, the same totals as the live logs" "$(run cost 2026-09-15)" "${live}"
same "reading creates no file and no events.tsv line" "$(snap)" "${before}"
rm "${R}/.swarm/sessions/"*
out="$(run cost 2026-09-15)"
check "with neither, the agent is listed and not priced" "| code | 1 (1 not in the logs) | - | 0k | 0k | 0k | 0k | 0.00 |"

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
