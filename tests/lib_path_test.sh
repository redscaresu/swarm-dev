#!/usr/bin/env bash
# lib_path_test.sh — swarm.sh's python imports bin/lib's panes, stall, report and dash_legend, never a
# file of that name in the directory it runs from (a project root). Each shadow module there records
# its import in shadowed. archive_session (`_archive`) and dash run from the project; the python3 -c
# sites only herdr reaches are checked by their text: each runs under -I (no cwd on sys.path) with
# bin/lib put first.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
R="${dir}/repo"; C="${dir}/projects"
mkdir -p "${R}/.swarm" "${C}/p"
git -C "${R}" init -q
echo '{"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1}}}' > "${C}/p/s1.jsonl"
printf '2026-09-29\tcode\tstory-a\tclaude\topus\thigh\ts1\n' > "${R}/.swarm/agents.tsv"
for m in panes stall report dash_legend; do
  printf 'open("%s/shadowed", "a").write("%s\\n")\n' "${R}" "${m}" > "${R}/${m}.py"
done

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
run() { (cd "${R}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${C}" bash "${SWARM}" "$@"); }

run _archive story-a
check "_archive copies the session through bin/lib's report.py" 1 "$(find "${R}/.swarm/sessions" -name '*-s1.jsonl.gz' 2>/dev/null | wc -l | tr -d ' ')"
run dash >/dev/null 2>&1 || true
run dash --project "${R}" --project "${R}" >/dev/null 2>&1 || true
check "no module in the project root was imported" "" "$(cat "${R}/shadowed" 2>/dev/null || true)"

LIB_IMPORT='^(.*; )?from (panes|stall|report|dash_legend) import'
GUARD='sys.path.insert(0, os.environ["SWARM_LIB"]); from '
check "every bin/lib import in swarm.sh puts bin/lib first" "" \
  "$(grep -E "${LIB_IMPORT}" "${SWARM}" | grep -vF "${GUARD}" || true)"
# shellcheck disable=SC2016 # the ${SWARM_HOME} is swarm.sh's text, matched literally
check "every python3 -c that imports bin/lib runs isolated, one per import" \
  "$(grep -cF "${GUARD}" "${SWARM}")" "$(grep -cF 'SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c' "${SWARM}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
