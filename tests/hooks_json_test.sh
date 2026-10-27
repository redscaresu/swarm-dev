#!/usr/bin/env bash
# hooks_json_test.sh — hooks/hooks.json parses, and every entry that runs agent-state.sh or
# user-caught-reminder.sh has a timeout of 30 seconds or more. Each does well under a second of work
# on a quiet machine, but under swarm load (2026-10-27: load 17, Defender and Spotlight scanning
# about 40 worktrees) both timed out at 5 s, Claude Code dropped their output, and herdr kept a stale
# working or idle state. Only a JSON number counts: an entry with no timeout, or with "30" as a
# string, fails, as the file names each one as a number.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export HOME="${dir}/home"   # under its own root, so parallel runs share no ~
MIN_TIMEOUT=30
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# One `<event> <script> <ok|short> <timeout>` line per entry that runs one of the two hooks: ok when
# its timeout is a number of at least MIN_TIMEOUT. The timeout is as JSON has it, or `none`. An entry
# with no command (a `type: prompt` hook) is not one of them. Exits 1 when the file does not parse,
# NaN and Infinity included: Python takes them, but they are not JSON.
rc=0
entries="$(python3 -I -c '
import json, re, sys
def not_json(word):
    raise ValueError("%s is not JSON" % word)
try:
    hooks = json.load(open(sys.argv[1]), parse_constant=not_json)["hooks"]
except (ValueError, KeyError, TypeError) as e:
    sys.exit("hooks.json does not parse: %s" % e)
for event, groups in hooks.items():
    for group in groups:
        for h in group["hooks"]:
            m = re.search(r"/hooks/(agent-state|user-caught-reminder)\.sh", h.get("command", ""))
            if m:
                t = h.get("timeout")
                ok = isinstance(t, (int, float)) and not isinstance(t, bool) and t >= int(sys.argv[2])
                print(event, m.group(1) + ".sh", "ok" if ok else "short", "none" if t is None else json.dumps(t))' \
  "${REPO}/hooks/hooks.json" "${MIN_TIMEOUT}")" || rc=$?
check "hooks.json parses" [ "${rc}" -eq 0 ]

for script in agent-state.sh user-caught-reminder.sh; do
  check "hooks.json runs ${script}" grep -q " ${script} " <<< "${entries}"
done

while read -r event script verdict timeout; do
  [ -n "${event}" ] || continue
  check "${event}'s ${script} has a timeout of at least ${MIN_TIMEOUT} s (it has ${timeout})" [ "${verdict}" = ok ]
done <<< "${entries}"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
