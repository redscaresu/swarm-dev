#!/usr/bin/env bash
# flow_test.sh — `swarm.sh flow` against a fixture. Epic e1 has stories a to d, b depending on a (a
# chain of 2). a runs 10:00-11:00 (its close) and b 10:20-12:00 (its session log's last entry), so
# 1, then 2, then 1 builders run: 160 build-minutes over a 120-minute span is a mean of 1.33. c and d
# have no session log or close, so they count as stories but not as running. a's PR, created at
# 10:00Z (gh stub), gets a review-agent event at 10:20Z. Epic e2's one story e has a PR created at
# 10:00Z and only a tell:findings at 10:50Z, so its wait is a proxy. Three stacked events, the last
# after --until's date. Epic e3's story g was built twice: PR #3 (14:10Z) got no review before the
# retry's PR #4 (15:10Z), whose review-agent at 15:20Z is #4's alone. The first build was never
# closed, so it ends at its session log's last entry (14:30Z), not at the retry's close (15:30Z). Epic e4's h, closed on 10-03,
# runs past --until 2026-10-02 to its cutoff, so it overlaps i on 10-02. TZ is UTC, so a build with no session log starts at a known time.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
story() { printf -- '---\nkind: code\nstatus: ready\nepic: %s\ndepends_on: [%s]\n---\n' "$2" "$3" > "${P}/docs/stories/$1.md"; }
# b's list is quoted with no space after the comma, as unblock also reads it: b depends on x and a.
story a e1 ""; story b e1 "\"x\",'a'"; story c e1 ""; story d e1 ""; story e e2 ""; story g e3 ""; story h e4 ""; story i e4 ""
session() { # <slug> <first time> <last time> [pull URL] — a session log in the slug's worktree
  printf '{"cwd":"%s/repo-wt/%s","timestamp":"%s"}\n' "${dir}" "$1" "$2"
  printf '{"timestamp":"%s","message":{"content":"%s"}}\n' "$3" "${4:-}"
}
session a 2026-10-01T10:00:00Z 2026-10-01T11:30:00Z "${U}/1" > "${dir}/projects/p/sa.jsonl"
session b 2026-10-01T10:20:00Z 2026-10-01T12:00:00Z > "${dir}/projects/p/sb.jsonl"
session e 2026-10-01T13:00:00Z 2026-10-01T13:30:00Z "${U}/2" > "${dir}/projects/p/se.jsonl"
session g 2026-10-01T14:00:00Z 2026-10-01T14:30:00Z "${U}/3" > "${dir}/projects/p/sg1.jsonl"
session g 2026-10-01T15:00:00Z 2026-10-01T15:30:00Z "${U}/4" > "${dir}/projects/p/sg2.jsonl"
session h 2026-10-01T16:00:00Z 2026-10-01T16:30:00Z > "${dir}/projects/p/sh.jsonl"
session i 2026-10-02T12:00:00Z 2026-10-02T12:30:00Z > "${dir}/projects/p/si.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode\ta\tclaude\topus\thigh\tsa' \
  $'2026-10-01\tcode\tb\tclaude\topus\thigh\tsb' \
  $'2026-10-01\tconduct\tconduct-e1\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\tc\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\td\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\te\tclaude\topus\thigh\tse' \
  $'2026-10-01\tcode\tg\tclaude\topus\thigh\tsg1' \
  $'2026-10-01\tcode\tg\tclaude\topus\thigh\tsg2' \
  $'2026-10-01\tcode\th\tclaude\topus\thigh\tsh' \
  $'2026-10-02\tcode\ti\tclaude\topus\thigh\tsi' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  $'2026-10-01T09:00:00Z\tstacked\tb\tw:1\tok' \
  $'2026-10-01T09:30:00Z\tstacked\tc\tw:1\tok' \
  $'2026-10-01T10:20:00Z\treview-agent\ta\tw:1\tok' \
  $'2026-10-01T10:50:00Z\ttell:findings\te\tw:1\tok' \
  $'2026-10-01T11:00:00Z\tclose:met\ta\tw:1\tok' \
  $'2026-10-01T15:20:00Z\treview-agent\tg\tw:1\tok' \
  $'2026-10-01T15:30:00Z\tclose\tg\tw:1\tok' \
  $'2026-10-03T09:00:00Z\tstacked\td\tw:1\tok' \
  $'2026-10-03T09:00:00Z\tclose\th\tw:1\tok' > "${P}/.swarm/events.tsv"
# gh: pr list answers a's, e's and g's heads; pr view answers each PR's createdAt (#3 at 14:10, #4 at 15:10).
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2 $3 $4" in\n"pr list --head story/a") printf "%s/1\\tOPEN\\t\\n" ;;\n"pr list --head story/e") printf "%s/2\\tOPEN\\t\\n" ;;\n"pr list --head story/g") printf "%s/4\\tOPEN\\t\\n%s/3\\tCLOSED\\t\\n" ;;\n"pr view %s/3 "*) echo 2026-10-01T14:10:00Z ;;\n"pr view %s/4 "*) echo 2026-10-01T15:10:00Z ;;\n"pr view "*) echo 2026-10-01T10:00:00Z ;;\nesac\nexit 0\n' "${U}" "${U}" "${U}" "${U}" "${U}" "${U}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" "$@"); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'epic\tbuilds\tbuilders_mean\tbuilders_max\tstories\tlongest_chain\tstories_per_chain\treview_wait_min\tproxy_review_wait_min\tstacked'
before="$(cat "${P}/.swarm/events.tsv")"
check "per epic: builders at once (mean 1.33, max 2), stories per chain (4 / 2 = 2.0), a review wait of 20 or a proxy of 50, stacked starts" \
  "$(run flow)" "${H}"$'
e1\t4\t1.33\t2\t4\t2\t2.0\t20\t\t3
e2\t1\t1.00\t1\t1\t1\t1.0\t\t50\t0
e3\t2\t0.67\t1\t1\t1\t1.0\t10\t\t0
e4\t2\t1.01\t2\t2\t1\t2.0\t\t\t0
all\t9\t0.97\t2\t8\t2\t4.0\t15\t50\t3'
check "--until drops the events after its date: two stacked events give 2" \
  "$(run flow --until 2026-10-02 | sed -n 2p)" $'e1\t4\t1.33\t2\t4\t2\t2.0\t20\t\t2'
check "a close after --until still ends its build, at the cutoff: h runs into i's day" \
  "$(run flow --until 2026-10-02 | grep '^e4')" $'e4\t2\t1.02\t2\t2\t1\t2.0\t\t\t0'
check "--since keeps the builds and events from its date" \
  "$(run flow --since 2026-10-02 | tail -1)" $'all\t1\t1.00\t1\t1\t1\t1.0\t\t\t1'
check "flow and features add no line to events.tsv" "$(run features >/dev/null; cat "${P}/.swarm/events.tsv")" "${before}"
check "a bad flag prints the usage" "$(run flow --until yesterday 2>&1 || true)" \
  "swarm: usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD]"
# A second project, in UTC-7: epic `all` (j) is an epic beside the project row; j's agents.tsv day is
# --until's (local), but its session starts at 03:00Z the next UTC day, still inside the local cutoff;
# k's agents.tsv date does not parse and it has no session log, so it is left out.
Q="${dir}/q"; mkdir -p "${Q}/.swarm" "${Q}/docs/stories"; git -C "${Q}" init -q
printf -- '---\nkind: code\nstatus: ready\nepic: all\n---\n' > "${Q}/docs/stories/j.md"
printf '{"cwd":"%s/q-wt/j","timestamp":"2026-10-03T03:00:00Z"}\n{"timestamp":"2026-10-03T03:30:00Z"}\n' "${dir}" > "${dir}/projects/p/sj.jsonl"
printf '%s\n' $'2026-10-02\tcode\tj\tclaude\topus\thigh\tsj' $'2026-10-01x\tcode\tk\tclaude\topus\thigh\t-' > "${Q}/.swarm/agents.tsv"
check "an epic named all keeps its row; a build late on --until's local day counts; a bad date is left out" \
  "$(cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT TZ=America/Los_Angeles CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
    bash "${SWARM}" flow --until 2026-10-02 2>&1)" "${H}"$'
all\t1\t1.00\t1\t1\t1\t1.0\t\t\t0
all\t1\t1.00\t1\t1\t1\t1.0\t\t\t0'
for gone in decisions export; do
  out="$(run "${gone}" 2>&1)" && code=0 || code=$?
  check "${gone} is gone: it exits non-zero printing the usage" "${code} $(grep -c 'swarm.sh flow' <<< "${out}")" "2 1"
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
