#!/usr/bin/env bash
# rework_test.sh — outcomes' rework column and flow's reviewer rows against a fixture. gh lists the repo's
# merged PRs: a's PR #1 is fixed 3 days after it merged by fix-a's PR #2, which says it fixes #1 (rework);
# b's PR #3 is fixed 9 days after it merged by fix-b's PR #4 (past 7 days: no rework); c's PR #5 has an
# escaped finding 3 days after it merged (rework); d's PR #6 never merged (no value); e's PR #7 is fixed
# by hotfix #9, which no build made, 7 days after its merge day though more than 7x24 hours later
# (rework); f's PR #10 merged 2 days ago, so a fix may still come (no value); g's PR #11 merged at 01:00
# UTC on 2026-10-02 and has an escaped finding dated 2026-10-01, a local day: rework where that merge was
# the evening of 2026-10-01 (Los Angeles), not in UTC. a is built twice on its one PR: only the later
# build carries its rework. Then: the gh list's search, from the first merge day to 8 days after the last,
# a gh that fails (rework empty, and a notice in flow's sections), a gh list at its limit, and the reviewer
# rows of a window that leaves out a's latest build. gh is a stub on PATH. TZ is UTC unless a check sets it.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/prs"
git -C "${P}" init -q
SLUGS="a b c d e f g fix-a fix-b"
for s in ${SLUGS}; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
RECENT="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
END="$(python3 -c 'import datetime as d, sys; print(d.date.fromisoformat(sys.argv[1][:10]) + d.timedelta(days=8))' "${RECENT}")"
# gh answers a story's PRs from prs/<head with / as _> (url state mergedAt createdAt main_merges), and
# the repo's merged PRs from GH_JSON (default merged.json), writing that call's arguments to gh.args.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2 $3" = "pr list --head" ] && { cat "%s/prs/$(echo "$4" | tr / _)" 2>/dev/null; exit 0; }\n[ "$1 $2 $3 $4" = "pr list -R o/r" ] || exit 1\necho "$*" > "%s/gh.args"\nexec cat "${GH_JSON:-%s/merged.json}"\n' \
  "${dir}" "${dir}" "${dir}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"
pr() { printf '%s/%s\t%s\t%s\t2026-10-01T09:00:00Z\t0\n' "${U}" "$2" "$3" "$4" > "${dir}/prs/story_$1"; }
pr a 1 MERGED 2026-10-01T10:00:00Z
pr fix-a 2 MERGED 2026-10-04T10:00:00Z
pr b 3 MERGED 2026-10-01T10:00:00Z
pr fix-b 4 MERGED 2026-10-10T10:00:00Z
pr c 5 MERGED 2026-10-02T10:00:00Z
pr d 6 OPEN ""
pr e 7 MERGED 2026-10-01T10:00:00Z
pr f 10 MERGED "${RECENT}"
pr g 11 MERGED 2026-10-02T01:00:00Z
cat > "${dir}/merged.json" <<EOF
[{"url":"${U}/1","mergedAt":"2026-10-01T10:00:00Z","title":"a","body":""},
 {"url":"${U}/2","mergedAt":"2026-10-04T10:00:00Z","title":"Fix a","body":"Fixes #1."},
 {"url":"${U}/3","mergedAt":"2026-10-01T10:00:00Z","title":"b","body":""},
 {"url":"${U}/4","mergedAt":"2026-10-10T10:00:00Z","title":"Fix ${U}/3","body":""},
 {"url":"${U}/5","mergedAt":"2026-10-02T10:00:00Z","title":"c","body":""},
 {"url":"${U}/7","mergedAt":"2026-10-01T10:00:00Z","title":"e","body":""},
 {"url":"${U}/9","mergedAt":"2026-10-08T20:00:00Z","title":"Hotfix for #7","body":""},
 {"url":"${U}/10","mergedAt":"${RECENT}","title":"f","body":""},
 {"url":"${U}/11","mergedAt":"2026-10-02T01:00:00Z","title":"g","body":""}]
EOF
{ for s in ${SLUGS}; do printf '2026-10-01\tcode\t%s\tclaude\topus\txhigh\t-\n' "${s}"; done
  printf '2026-10-02\tescalate\ta\tclaude\tfable\txhigh\t-\n'; } > "${P}/.swarm/agents.tsv"
: > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-01\tvacuous\to/r#1\tt\tfixed\tcodex' \
  $'2026-10-01\tnit\to/r#1\tt\tdeclined\tcode-review' \
  $'2026-10-01\tnit\to/r#3\tt\tfixed\tlead' \
  $'2026-10-02\tvacuous\to/r#5\tt\tfixed\tcodex' \
  $'2026-10-05\tmissed\to/r#5\tt\tescaped\tescaped' \
  $'2026-10-01\tmissed\to/r#11\tt\tescaped\tescaped' > "${P}/.swarm/findings.tsv"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" "$@"); }
rework() { run outcomes 2>/dev/null | sed '/^$/,$d' | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i } { print $at["slug"], $at["pr"], $at["rework"] }'; }
reviewers() { run flow "$@" 2>/dev/null | awk '/^## / { f = $0 == "## reviewers"; next } f && /^$/ { f = 0 } f' | cut -f1,2,7; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "outcomes: rework is 1 for a fix 3 days later saying so, an escaped finding and a hotfix no build made 7 days later; 0 at 9 days; empty unmerged, recent or on an earlier build" \
  "$(rework)" "$(printf '%s\n' "slug pr rework" "a ${U}/1 " "b ${U}/3 0" "c ${U}/5 1" "d ${U}/6 " "e ${U}/7 1" "f ${U}/10 " "g ${U}/11 0" \
  "fix-a ${U}/2 0" "fix-b ${U}/4 0" "a ${U}/1 1")"
check "an escaped finding's local day counts from the merge's local day: g in Los Angeles" "$(TZ=America/Los_Angeles rework | grep '^g ')" "g ${U}/11 1"
check "outcomes lists the repo's merged PRs once, from its builds' first merge day to 8 days after the last" "$(cat "${dir}/gh.args")" \
  "pr list -R o/r --state merged --limit 1000 --json url,mergedAt,title,body,files --search merged:2026-10-01..${END}"
check "when gh fails, rework is empty (an escaped finding too), stderr says so, and flow's reviewers and model_fit say so" \
  "$(GH_JSON="${dir}/none" run outcomes 2>&1 >/dev/null; GH_JSON="${dir}/none" rework | grep -E '^(a|c|e) ' | tail -3
     GH_JSON="${dir}/none" run flow 2>/dev/null | grep '^rework:')" \
  "$(printf '%s\n' "rework: gh failed, so rework is left empty." "c ${U}/5 " "e ${U}/7 " "a ${U}/1 " \
     "rework: gh failed when outcomes listed the merged PRs, so rework is unknown and counts as none." \
     "rework: gh failed when outcomes listed the merged PRs, so rework is unknown and counts as none.")"
python3 -c 'import json; print(json.dumps([{"url": f"https://github.com/o/r/pull/{n}", "mergedAt": "2026-10-01T00:00:00Z"} for n in range(100, 1100)]))' > "${dir}/full.json"
check "a gh list at its limit says on stderr that rework may be undercounted" "$(GH_JSON="${dir}/full.json" run outcomes 2>&1 >/dev/null)" \
  "rework: gh listed 1000 merged PRs of o/r, its limit, so rework may be undercounted."
check "flow reviewers: rework counts against each reviewer that raised a finding on the reworked PR" \
  "$(reviewers)" "$(printf '%s\n' $'reviewer\tkind\trework' $'code-review\tall\t1' $'code-review\tnit\t1' $'codex\tall\t2' $'codex\tvacuous\t2' \
  $'lead\tall\t0' $'lead\tnit\t0' $'all\tnit\t1' $'all\tvacuous\t2' $'all\tall\t2')"
check "flow reviewers --until 2026-10-01: #1 counts though its latest build is dated after the window" \
  "$(reviewers --until 2026-10-01)" "$(printf '%s\n' $'reviewer\tkind\trework' $'code-review\tall\t1' $'code-review\tnit\t1' $'codex\tall\t1' $'codex\tvacuous\t1' \
  $'lead\tall\t0' $'lead\tnit\t0' $'all\tnit\t1' $'all\tvacuous\t1' $'all\tall\t1')"
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
