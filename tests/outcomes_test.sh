#!/usr/bin/env bash
# outcomes_test.sh — `swarm.sh outcomes` against a fixture: a merged code story whose file the merge
# deleted (its slug longer than the 32 characters agents.tsv keeps), built twice; a docs story still on
# the board; a conductor and a codex agent (not builders, left out). gh is a stub on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; LONG="merged-story-whose-name-is-longer-than-32"; CUT="${LONG:0:32}"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/nobin"
git -C "${P}" init -q
printf -- '---\nkind: code\nrisk: high\nstatus: ready\n---\n' > "${P}/docs/stories/${LONG}.md"
printf -- '---\nkind: docs\nstatus: ready\n---\n' > "${P}/docs/stories/docs-story.md"
git -C "${P}" add -A && git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm stories
git -C "${P}" rm -q "docs/stories/${LONG}.md" && git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm merged

session() { # <session id> <slug> <model> <input> <output> — a session log: its worktree cwd, then one message
  printf '{"type":"user","cwd":"%s/repo-wt/%s"}\n' "${dir}" "$2"
  printf '{"cwd":"%s/repo-wt/%s","message":{"id":"m-%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s}}}\n' "${dir}" "$2" "$1" "$3" "$4" "$5"
}
session s1 "${LONG}" claude-opus-5-5 1000000 0 > "${dir}/projects/p/s1.jsonl"
session s2 docs-story claude-sonnet-5-5 0 1000000 > "${dir}/projects/p/s2.jsonl"
session s3 "${LONG}" claude-fable-5-1 1000000 0 > "${dir}/projects/p/s3.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode-risky\t'"${CUT}"$'\tclaude\topus\txhigh\ts1' \
  $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts9' \
  $'2026-10-02\tdocs\tdocs-story\tclaude\tsonnet\tmedium\ts2' \
  $'2026-10-03\tcodex\tcodex\tcodex\tdefault\thigh\t-' \
  $'2026-10-04\tescalate\t'"${CUT}"$'\tclaude\tfable\txhigh\ts3' > "${P}/.swarm/agents.tsv"
# A tell is logged as tell:<kind>; a bare tell is from a log written before kinds. Both count.
printf '%s\n' \
  $'2026-10-01T10:00:00Z\ttell\t'"${LONG}"$'\tw:1\tok' \
  $'2026-10-01T11:00:00Z\ttell:findings\t'"${LONG}"$'\tw:1\tok' \
  $'2026-10-01T12:00:00Z\tclose\t'"${CUT}"$'\tw:1\tok' \
  $'2026-10-02T10:00:00Z\ttell:nudge\tdocs-story\tw:1\tok' \
  $'2026-10-02T10:00:00Z\treview\tdocs-story\tw:1\tok' \
  $'2026-10-02T10:00:00Z\ttell\tother\tw:1\tok' > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-01\tvacuous-test\to/r#7\ta' \
  $'2026-10-01\tmissing-check\thttps://github.com/o/r/pull/7\tb' \
  $'2026-10-02\tvacuous-test\thttps://github.com/o/r/pull/8/files\tc' \
  $'2026-10-02\tvacuous-test\to/r#9\td' > "${P}/.swarm/findings.tsv"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\ncase "$4" in\n  story/%s) printf "https://github.com/o/r/pull/7\\tMERGED\\n" ;;\n  story/docs-story) printf "https://github.com/o/r/pull/8\\tOPEN\\n" ;;\nesac\n' "${LONG}" > "${dir}/bin/gh"
printf '#!/bin/sh\nexit 1\n' > "${dir}/nobin/gh"
chmod +x "${dir}/bin/gh" "${dir}/nobin/gh"

outcomes() { # <gh dir> [args] — the report, with that gh first on PATH
  local bin="$1"; shift
  (cd "${P}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${bin}:${PATH}" bash "${SWARM}" outcomes "$@")
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
HEAD=$'date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells\tcloses\tfindings_fixed\tpr\tpr_state\tattempts'
# opus 1M input = $4; sonnet 1M output = $10; fable 1M input = $10.
R1="2026-10-01	${LONG}	code	high	code-risky	opus	xhigh	4.00	1000000	2	1	2	https://github.com/o/r/pull/7	MERGED	1"
R2="2026-10-02	docs-story	docs		docs	sonnet	medium	10.00	1000000	1	0	1	https://github.com/o/r/pull/8	OPEN	1"
R3="2026-10-04	${LONG}	code	high	escalate	fable	xhigh	10.00	1000000	2	1	2	https://github.com/o/r/pull/7	MERGED	2"
check "one row per builder: full slug, kind and risk (from git once deleted), cost, tells (tell:<kind> and bare), findings, attempts" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "${R2}" "${R3}")"
check "--since leaves earlier rows out, and attempts still count them" \
  "$(outcomes "${dir}/bin" --since 2026-10-03)" "$(printf '%s\n' "${HEAD}" "${R3}")"
nopr() { awk -F'\t' -v OFS='\t' '{ $12 = 0; $13 = ""; $14 = "" } 1' <<< "$1"; }
check "a failing gh leaves pr and pr_state empty and still prints every row" \
  "$(outcomes "${dir}/nobin" 2>/dev/null)" "$(printf '%s\n' "${HEAD}" "$(nopr "${R1}")" "$(nopr "${R2}")" "$(nopr "${R3}")")"
if outcomes "${dir}/bin" --since yesterday >/dev/null 2>&1; then
  echo "FAIL a bad --since is refused"; fails=$((fails + 1))
else echo "ok   a bad --since is refused"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
