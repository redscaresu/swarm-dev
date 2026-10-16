#!/usr/bin/env bash
# stacked_status_test.sh — `swarm.sh status` prints a Stacked section, one line per parent of a
# stacked build that needs action: merge a parent that moved, merge the base once a parent merged,
# or a lost parent; `(no builder)` when the child's builder is not open. herdr and gh are stubs on
# PATH: herdr lists the agents in ${ROOT}/agents ("<name> <pane>" lines); gh answers pr list from
# ${ROOT}/prs.json, and fails while ${ROOT}/ghfail exists. The remote is a bare repo.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/child"; UP="${ROOT}/upstream"
GIT=(git -c user.name=t -c user.email=t@t)
mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
printf '#!/bin/sh\nA="%s"; H="%s"\n' "${ROOT}/agents" "${ROOT}" | tee "${ROOT}/bin/gh" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                     END { print "]}}" }' "$A" ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:1"}]}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
esac
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
[ -e "$H/ghfail" ] && exit 1
case "$1 $2" in "pr list") cat "$H/prs.json" ;; esac
exit 0
STUB
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh" "${ROOT}/bin/claude"
echo "child w:1" > "${ROOT}/agents"
echo "w:1 child" > "${P}/.swarm/state/child"
echo '[{"state":"OPEN"}]' > "${ROOT}/prs.json"

item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; }
git init -q --bare "${ROOT}/origin.git" && git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" init -q && git -C "${P}" remote add origin "${ROOT}/origin.git"
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init && git -C "${P}" push -q origin HEAD:refs/heads/main
git clone -q "${ROOT}/origin.git" "${UP}"
"${GIT[@]}" -C "${UP}" checkout -q -b story/p && "${GIT[@]}" -C "${UP}" commit -q --allow-empty -m p1
git -C "${UP}" push -q origin story/p
git -C "${P}" fetch -q origin
git -C "${P}" worktree add -q -b story/child "${WT}" origin/story/p
item p 'status: review' 'kind: code'
item child 'status: ready' 'kind: code' 'depends_on: [p]'
STACKED=$'2026-10-01T00:00:00Z\tstacked\tchild\tw:9\tok (on p)'
echo "${STACKED}" > "${P}/.swarm/events.tsv"

status() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status 2>&1) || true; }
# stacked [outside] — status's Stacked lines, trimmed, one per line; nothing when there is no section.
# With `outside`, status runs outside herdr.
section() { awk '/^Stacked$/ { s = 1; next } s && /^  / { sub(/^  /, ""); print; next } { s = 0 }'; }
stacked() {
  if [[ "${1:-}" == outside ]]; then { (cd "${P}" && env -u HERDR_ENV PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status 2>&1) || true; } | section
  else status | section; fi
}
moves() { "${GIT[@]}" -C "${UP}" checkout -q "$1" && "${GIT[@]}" -C "${UP}" commit -q --allow-empty -m "$2" && git -C "${UP}" push -q origin "$1"; }
merges() { "${GIT[@]}" -C "${WT}" merge -q --no-edit "$1"; }
pushes() { git -C "${WT}" push -q origin story/child; }
takes() { merges "$1" && pushes; }
prs() { echo "$1" > "${ROOT}/prs.json"; }
event() { printf '2026-10-0%s\t%s\tchild\tw:9\t%s\n' "$1" "$2" "$3" >> "${P}/.swarm/events.tsv"; }

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

is "a child on its parent's head needs nothing" "" "$(stacked)"
moves story/p p2
is "p moved: the child merges origin/story/p" "child: merge origin/story/p" "$(stacked)"
with="$(status)"
: > "${P}/.swarm/events.tsv"
without="$(status)"
is "with no stacked story there is no Stacked section" "" "$(stacked)"
# The section is a blank line, Stacked and its lines: drop the heading through the next blank line.
is "the rest of status is unchanged by the section" "${without}" "$(sed '/^Stacked$/,/^$/d' <<< "${with}")"
echo "${STACKED}" > "${P}/.swarm/events.tsv"
takes origin/story/p
is "once the child merged it and pushed, the line is gone" "" "$(stacked)"

item child 'status: blocked' 'kind: code' 'depends_on: [p]'
moves story/p p3
is "a held child: p moved after its review" "child: merge origin/story/p" "$(stacked)"
: > "${ROOT}/agents"
is "with its builder not open the line says so" "child: merge origin/story/p (no builder)" "$(stacked)"
is "outside herdr, where the agents cannot be read, the line does not say so" "child: merge origin/story/p" "$(stacked outside)"
echo "child w:1" > "${ROOT}/agents"
merges origin/story/p
is "merged but not pushed: origin's story/child lacks p, so the line stays" "child: merge origin/story/p" "$(stacked)"
pushes
is "the held child pushed it: the line is gone" "" "$(stacked)"

rm "${P}/docs/stories/p.md"
prs '[{"state":"MERGED"}]'
moves main m2
is "p's file gone, its PR merged, main ahead: the child merges main" "child: merge origin/main (p merged)" "$(stacked)"
merges origin/main
is "main merged but not pushed: the line stays" "child: merge origin/main (p merged)" "$(stacked)"
pushes
is "the child has main's head: the line is gone" "" "$(stacked)"
prs '[]'
moves main m3
is "p's file gone with no PR: it finished, so the child merges main" "child: merge origin/main (p merged)" "$(stacked)"
prs '[{"state":"CLOSED"}]'
is "p's file gone and its PR closed unmerged (dropped): lost, not merged" "child: lost story/p" "$(stacked)"
prs '[{"state":"MERGED"}]'
printf '2026-10-01T00:00:00Z\tstacked\tchild\tw:9\tok (on p q)\n' > "${P}/.swarm/events.tsv"
is "two merged parents give one base line" "child: merge origin/main (p, q merged)" "$(stacked)"
echo "${STACKED}" > "${P}/.swarm/events.tsv"
takes origin/main

item p 'status: review' 'kind: code'
moves main m4
is "p's PR merged, file still there: the child merges main" "child: merge origin/main (p merged)" "$(stacked)"
takes origin/main
prs '[{"state":"CLOSED"}]'
is "p's PR closed unmerged: lost" "child: lost story/p" "$(stacked)"
prs '[{"state":"CLOSED"},{"state":"OPEN"}]'
is "an open PR outranks an earlier closed one" "" "$(stacked)"
touch "${ROOT}/ghfail"
is "gh fails: the parent could not be checked" "child: could not check p" "$(stacked)"
rm "${ROOT}/ghfail"
git -C "${UP}" push -q origin --delete story/p
is "p's branch gone while p is on the board: lost" "child: lost story/p" "$(stacked)"
event 2 story ok
is "the build that logged the stacked event is the current one" "child: lost story/p" "$(stacked)"
event 3 story ok
is "a later build with no stacked event (rebuilt from main) has no parents" "" "$(stacked)"
event 4 stacked 'ok (on p)'
is "a later stacked build has its parents again" "child: lost story/p" "$(stacked)"

# --- Both conductor briefs, story mode (an epic) and backlog mode, carry the stacked rule.
Q="${ROOT}/conductors"; mkdir -p "${Q}/.claude/swarm" "${Q}/docs/epics" "${Q}/docs/stories" "${ROOT}/cbin"
: > "${Q}/.claude/swarm/config"; git -C "${Q}" init -q
{ echo ---; echo 'status: active'; echo ---; echo; echo '# e'; } > "${Q}/docs/epics/e.md"
# herdr for conduct: a workspace, a tab and a pane, and an agent that starts working.
cat > "${ROOT}/cbin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "tab list")         echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")       echo '{"result":{"agents":[]}}' ;;
esac
STUB
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/cbin/gh"
chmod +x "${ROOT}/cbin/herdr" "${ROOT}/cbin/gh"
conduct() { (cd "${Q}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/cbin:${ROOT}/bin:${PATH}" bash "${SWARM}" conduct "$1" >/dev/null 2>&1) || true; }
conduct e; conduct --backlog
# shellcheck disable=SC2016 # the backticks are the brief's
for mode in e backlog; do
  b="$(tr -s ' \n' '  ' < "${Q}/.swarm/briefs/conduct-${mode}.md" 2>/dev/null || true)"
  n=0 mine='a story with `epic: e`'
  [[ "${mode}" != backlog ]] || mine='a story with no `epic:`'
  for want in "start what it readies that is yours (${mine};" 'act only on a line whose <child> is yours' \
      'If the line ends `(no builder)`, or close prints `not held:`, the child stays ready on a dead parent: do not start it, and list it in your report for the lead.' \
      '`<child>: could not check <what>`' 'and after a builder opens a PR, run `swarm.sh unblock`' 'run `swarm.sh status` and read its Stacked lines' \
      'saying to merge <ref> into its branch, re-run the tests and push, and send it with `swarm.sh tell <child> findings <file>`' \
      'On a line that ends `(no builder)`, first start a builder in the child'"'"'s worktree' '`swarm.sh agent <tab> <child> <worktree> <role> <brief>`' \
      'review the new head' 'run `swarm.sh close <child> paused`'; do
    grep -qF -- "${want}" <<< "${b}" || { echo "  conduct-${mode} lacks: ${want}"; n=$((n + 1)); }
  done
  is "the ${mode} conductor brief carries the stacked rule" 0 "${n}"
done

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
