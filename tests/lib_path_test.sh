#!/usr/bin/env bash
# lib_path_test.sh — swarm.sh's python imports bin/lib's panes, stall, report and dash_legend, never a
# file of that name in the directory it runs from (a project root). archive_session (`_archive`) runs
# from a project root holding shadow modules, each of which records its import in shadowed. The other
# python3 -c sites run only under herdr, so each is checked by its text: a site that imports from
# bin/lib runs under -I (no cwd on sys.path), sets SWARM_LIB, and puts it first on sys.path before its
# first import.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
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
check "no module in the project root was imported" "" "$(cat "${R}/shadowed" 2>/dev/null || true)"

# sites — one line per python3 -c '...' site in swarm.sh or bin/lib/*.sh that imports from bin/lib
# without the guard, naming its file, line and what it lacks; and any bin/lib import outside such a site.
sites() {
  python3 -I - "${SWARM}" "$(dirname "${SWARM}")"/lib/*.sh <<'PY'
import os, re, sys
LIB = re.compile(r"(?m)(^|; )from (panes|stall|report|dash_legend) import")
GUARD = 'sys.path.insert(0, os.environ["SWARM_LIB"]); '
for path in sys.argv[1:]:
    text = open(path).read()
    name = os.path.basename(path)
    seen = 0
    for m in re.finditer(r"(?m)^(.*?)python3((?: -[A-Za-z])*) -c '([^']*)'", text):
        body = m.group(3)
        first = LIB.search(body)
        if not first:
            continue
        seen += len(LIB.findall(body))
        line = text.count("\n", 0, m.start()) + 1
        if "-I" not in m.group(2).split():
            print(f"{name}:{line}: python3 -c without -I")
        if 'SWARM_LIB="${SWARM_HOME}/bin/lib"' not in m.group(1):
            print(f"{name}:{line}: no SWARM_LIB on the command")
        if not body[:first.start() + len(first.group(1))].endswith(GUARD):
            print(f"{name}:{line}: its first bin/lib import does not insert SWARM_LIB just before it")
    if seen != len(LIB.findall(text)):
        print(f"{name}: a bin/lib import outside a python3 -c site")
PY
}
check "each python3 -c site that imports bin/lib runs under -I with bin/lib first" "" "$(sites)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
