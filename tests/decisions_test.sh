#!/usr/bin/env bash
# decisions_test.sh — `swarm.sh decisions` against a fixture: a builder whose story a merge deleted, a
# conductor, a codex agent, a fixed finding (an old four-field row) and a declined one, nudges and
# closes. gh is a stub on PATH. The export must be valid JSONL, null where the logs hold nothing, and
# write nothing.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; G=(git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
printf -- '---\nkind: code\nstatus: ready\n---\n# Build s-one\n' > "${P}/docs/stories/s-one.md"
echo board > "${P}/docs/README.md"
"${G[@]}" add -A && GIT_COMMITTER_DATE=2026-10-01T09:00:00 "${G[@]}" commit -qm story
printf -- '---\nkind: code\nstatus: ready\n---\n# Edited after the build\n' > "${P}/docs/stories/s-one.md"
"${G[@]}" add -A && GIT_COMMITTER_DATE=2026-10-03T09:00:00 "${G[@]}" commit -qm edit
"${G[@]}" rm -q docs/stories/s-one.md && GIT_COMMITTER_DATE=2026-10-04T09:00:00 "${G[@]}" commit -qm merged

printf '{"cwd":"%s/repo-wt/s-one","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":0}}}\n' \
  "${dir}" > "${dir}/projects/p/s1.jsonl"
printf '%s\n' \
  $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts9' \
  $'2026-10-02\tcode\ts-one\tclaude\topus\txhigh\ts1' \
  $'2026-10-02\tcodex\tcodex\tcodex\tdefault\thigh\t-' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  $'2026-10-02T10:00:00Z\tnudge\ts-one\tw:1\tok' \
  $'2026-10-02T11:00:00Z\ttell:nudge\ts-one\tw:1\tok' \
  $'2026-10-02T12:00:00Z\treview\ts-one\tw:1\tok' \
  $'2026-10-02T13:00:00Z\tclose\ts-one\tw:1\tok' \
  $'2026-10-03T13:00:00Z\tclose\tconduct-e\tw:1\tok' > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-02\tvacuous-test\to/r#7\ta test that could not fail' \
  $'2026-10-02\tout-of-scope\thttps://github.com/o/r/pull/7\tan edge case outside the story\tdeclined' > "${P}/.swarm/findings.tsv"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\n[ "$4" = story/s-one ] && printf "https://github.com/o/r/pull/7\\tMERGED\\n"\nexit 0\n' > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

decisions() { (cd "${P}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" decisions "$@"); }
# summary — each line as decision|subject|context (its first heading, null or text)|options|chosen|outcome
summary() {
  python3 -c '
import json, sys
for l in sys.stdin:
    d = json.loads(l)
    c = d["context"]
    c = None if c is None else next((x for x in c.splitlines() if x.startswith("#")), c)
    print("|".join([d["decision"], str(d["subject"]), str(c)] + [json.dumps(d[k], sort_keys=True) for k in ("options", "chosen", "outcome")]))'
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
before="$(ls -lR "${P}/.swarm")"
out="$(decisions)"
O='{"attempts": 1, "cost_usd": 4.0, "findings": 1, "merged": true, "pr": "https://github.com/o/r/pull/7", "tells_findings": 0, "tells_nudge": 1, "tells_resume": 0}'
check "one object per model choice, finding (fixed and declined), nudge and close, null where the logs hold nothing" \
  "$(summary <<< "${out}")" "$(cat <<EOF
model_choice|conduct-e|None|null|{"effort": "high", "kind": "claude", "model": "opus", "role": "conduct"}|null
model_choice|s-one|# Build s-one|null|{"effort": "xhigh", "kind": "claude", "model": "opus", "role": "code"}|${O}
model_choice|codex|None|null|{"effort": "high", "kind": "codex", "model": "default", "role": "codex"}|null
finding_accept|o/r#7|a test that could not fail|["fixed", "declined"]|"fixed"|${O}
finding_accept|https://github.com/o/r/pull/7|an edge case outside the story|["fixed", "declined"]|"declined"|${O}
nudge|s-one|None|null|"nudge"|${O}
nudge|s-one|None|null|"tell:nudge"|${O}
close|s-one|None|null|"close"|${O}
close|conduct-e|None|null|"close"|null
EOF
)"
check "it writes nothing" "$(ls -lR "${P}/.swarm")" "${before}"
check "--since leaves earlier decisions out" "$(decisions --since 2026-10-03 | summary | cut -d'|' -f1,2)" "close|conduct-e"
if decisions --since yesterday >/dev/null 2>&1; then
  echo "FAIL a bad --since is refused"; fails=$((fails + 1))
else echo "ok   a bad --since is refused"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
