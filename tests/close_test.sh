#!/usr/bin/env bash
# close_test.sh — close shuts every tab that carries the agent's label, one id per herdr call, even
# when two tabs share it, and archives the agent's session log once; closing the open builder of a
# ready story counts a failed build. herdr and gh are stubs on PATH: herdr records each tab close and
# lists the agents in ${ROOT}/agents ("<name> <pane>" lines); gh answers pr list from ${ROOT}/prs.json.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; CLOSED="${ROOT}/closed"
mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
git -C "${P}" init -q
: > "${CLOSED}"
: > "${ROOT}/agents"
printf '#!/bin/sh\nA="%s"; CLOSED="%s"; H="%s"\n' "${ROOT}/agents" "${CLOSED}" "${ROOT}" | tee "${ROOT}/bin/gh" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "tab list") echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"scope-x"},{"tab_id":"w:t2","label":"scope-x"},{"tab_id":"w:t3","label":"other"}]}}' ;;
  "tab close") printf '<%s>\n' "$3" >> "${CLOSED}" ;;
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                     END { print "]}}" }' "$A" ;;
  "agent rename") awk -v p="$3" -v n="$4" '$2 == p { $1 = n } { print }' "$A" > "$A.tmp" && mv "$A.tmp" "$A" ;;
  "pane list") echo '{"result":{"panes":[]}}' ;;
esac
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "$H/gh.log"
[ -e "$H/ghfail" ] && exit 1
case "$1 $2" in "pr list") cat "$H/prs.json" ;; esac
exit 0
STUB
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"
echo "w:p1 lead-x" > "${P}/.swarm/state/scope-x"
# scope-x has a Claude session (an older line for the same name came first), and so does lead-x, the
# agent in its tab; codex-y has none.
mkdir -p "${CLAUDE_CONFIG_DIR}/projects/p"
printf '{"type":"user","cwd":"/x"}\n' > "${CLAUDE_CONFIG_DIR}/projects/p/sx.jsonl"
printf '{"type":"user","cwd":"/l"}\n' > "${CLAUDE_CONFIG_DIR}/projects/p/lx.jsonl"
printf '%s\n' $'2026-10-01\tplan\tscope-x\tclaude\topus\thigh\told' $'2026-10-02\tplan\tscope-x\tclaude\topus\thigh\tsx' \
  $'2026-10-02\tlead\tlead-x\tclaude\topus\thigh\tlx' $'2026-10-02\tcodex\tcodex-y\tcodex\tdefault\thigh\t-' > "${P}/.swarm/agents.tsv"
close() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "$1" >"${ROOT}/close.out" 2>&1) || true; }

close scope-x

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
check "both tabs with the label are closed, one id per call" test "$(sort "${CLOSED}" | tr '\n' ' ')" = "<w:t1> <w:t2> "
check "another label's tab is left open" bash -c "! grep -qx '<w:t3>' '${CLOSED}'"
check "the tab record is removed" test ! -e "${P}/.swarm/state/scope-x"
archives() { find "${P}/.swarm/sessions" -type f 2>/dev/null | wc -l | tr -d ' '; }
check "close archives the agent's newest session, gzip'd" \
  test "$(gunzip -c "${P}/.swarm/sessions/"*-scope-x-sx.jsonl.gz 2>/dev/null)" = '{"type":"user","cwd":"/x"}'
check "closing its tab archives the agent left in it too" \
  test "$(gunzip -c "${P}/.swarm/sessions/"*-lead-x-lx.jsonl.gz 2>/dev/null)" = '{"type":"user","cwd":"/l"}'
check "the two archives are the only files there" test "$(archives)" = 2
check "the archives are readable by their owner only" test "$(find "${P}/.swarm/sessions" -name "*.jsonl.gz" -perm 600 | wc -l | tr -d ' ')" = 2
# Dated earlier, so a second copy would get a new name rather than overwrite this one.
mv "${P}/.swarm/sessions/"*-scope-x-sx.jsonl.gz "${P}/.swarm/sessions/2026-01-01-scope-x-sx.jsonl.gz"
close scope-x
check "closing it again, another day, archives nothing more" test "$(archives)" = 2
close codex-y
check "an agent with no session archives nothing" test "$(archives)" = 2

# --- A close that ends a failed build: the story is ready, of an agent's kind, its builder is open
# under its name and none of its PRs merged. attempts: goes up by one, and the worktree, local and
# origin story/<slug> and the open PR go. Any other close counts and clears nothing.
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
GIT=(git -c user.name=t -c user.email=t@t)
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
git -C "${P}" remote add origin "${ROOT}/origin.git"
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init && git -C "${P}" push -q origin HEAD:refs/heads/main
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; }
started() { # <slug> [pane] — its worktree on story/<slug>, pushed, and an untracked file; with a pane, its builder open there
  local wt="${ROOT}/proj-wt/$1"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/$1" "${wt}"
  "${GIT[@]}" -C "${wt}" commit -q --allow-empty -m "$1" && git -C "${wt}" push -q origin "story/$1"
  touch "${wt}/untracked"
  [[ -z "${2:-}" ]] || { echo "$2 $1" > "${P}/.swarm/state/$1"; echo "$1 $2" >> "${ROOT}/agents"; }
}
left() { # <slug> — which of its worktree, local story/<slug> and origin's are still there
  local o=""
  [[ ! -d "${ROOT}/proj-wt/$1" ]] || o+=" worktree"
  ! git -C "${P}" show-ref -q --verify "refs/heads/story/$1" || o+=" branch"
  ! git -C "${ROOT}/origin.git" show-ref -q --verify "refs/heads/story/$1" || o+=" origin"
  echo "${o# }"
}
attempts() { awk '/^---$/ && ++n == 2 { exit } n == 1 && sub(/^attempts: */, "")' "${P}/docs/stories/$1.md" 2>/dev/null || true; }   # front matter only
U="https://github.com/o/proj/pull"
echo "[{\"number\":1,\"state\":\"OPEN\",\"url\":\"${U}/1\"},{\"number\":2,\"state\":\"CLOSED\",\"url\":\"${U}/2\"}]" > "${ROOT}/prs.json"
item s1 "status: ready" "kind: code"; started s1 w:p1
close s1
is "closing a ready story's open builder writes attempts: 1" "1" "$(attempts s1)"
is "and removes its worktree, local story/s1 and origin's" "" "$(left s1)"
is "and closes its open PR, and only that one, with a comment naming the attempt" "1|0|yes" \
  "$(grep -c "^pr close ${U}/1 --comment .*attempt 1 at s1" "${ROOT}/gh.log")|$(grep -c "^pr close ${U}/2" "${ROOT}/gh.log")|$(grep -q "^pr list -R ${ROOT}/origin.git --head story/s1 --state all --json number,state,url,autoMergeRequest$" "${ROOT}/gh.log" && echo yes)"
close s1
is "closing it again leaves 1" "1" "$(attempts s1)"
echo '[]' > "${ROOT}/prs.json"
mkdir -p "${P}/.claude/swarm"; echo "keep_panes = true" > "${P}/.claude/swarm/config"
item k1 "status: ready" "kind: code"; started k1 w:p2
close k1
is "with keep_panes, closing it writes attempts: 1, clears it, and retires the builder" "1||k1-done w:p2" \
  "$(attempts k1)|$(left k1)|$(grep ' w:p2$' "${ROOT}/agents")"
close k1
is "with keep_panes, closing it again leaves 1" "1" "$(attempts k1)"
: > "${P}/.claude/swarm/config"
# A worktree whose directory was deleted by hand is still registered: it is pruned, so the branch goes.
item w1 "status: ready" "kind: code"; started w1 w:p11; rm -rf "${ROOT}/proj-wt/w1"
close w1
is "a worktree deleted by hand is pruned, so its local and origin branches go too" "1|" "$(attempts w1)|$(left w1)"
# attempts: is read from the front matter alone, never from a body line that starts the same way.
item b1 "status: ready" "kind: code"; echo "attempts: 3" >> "${P}/docs/stories/b1.md"; started b1 w:p12
close b1
is "a body line 'attempts: 3' is not the count: the first failure writes attempts: 1" "1|yes" \
  "$(attempts b1)|$(grep -qx 'attempts: 3' "${P}/docs/stories/b1.md" && echo yes)"
item r1 "status: review" "kind: code"; started r1 w:p3
item m1 "status: ready" "kind: code"; started m1 w:p4
item g1 "status: ready" "kind: code"; started g1 w:p5
item n1 "status: ready" "kind: code"; started n1
item h1 "status: ready" "kind: code"; started h1; echo "w:p6 h1" > "${P}/.swarm/state/h1"   # its pane closed by hand
item q1 "status: ready" "kind: code"; started q1 w:p13
item v1 "status: ready" "kind: verify"; started v1 w:p14
started d1 w:p7
started conduct-x w:p8; started hld-x w:p9; started plan-x w:p10
close r1; close v1; close d1; close n1; close h1; for s in conduct-x hld-x plan-x; do close "${s}"; done
echo "[{\"number\":3,\"state\":\"MERGED\",\"url\":\"${U}/3\"},{\"number\":4,\"state\":\"OPEN\",\"url\":\"${U}/4\"}]" > "${ROOT}/prs.json"
close m1
# Merged but queued: still open, with auto-merge set.
echo "[{\"number\":5,\"state\":\"OPEN\",\"url\":\"${U}/5\",\"autoMergeRequest\":{\"mergeMethod\":\"SQUASH\"}}]" > "${ROOT}/prs.json"
close q1
rm "${ROOT}/prs.json"; touch "${ROOT}/ghfail"
close g1
rm "${ROOT}/ghfail"
is "a gh call that fails is said on stderr" "1" "$(grep -c "g1: could not list the PRs on story/g1" "${ROOT}/close.out")"
for s in r1:"a story in review" v1:"a ready verify story (no PR tells its pass from a failure)" d1:"a deleted story" m1:"a story whose PR merged" q1:"a story whose open PR has auto-merge set" \
         g1:"a story whose gh call fails" \
         n1:"a ready story with no builder open" h1:"a ready story whose builder's pane was closed by hand" \
         conduct-x:"conduct-x" hld-x:"hld-x" plan-x:"plan-x"; do
  is "closing ${s#*:} writes nothing and removes no worktree or branch" "|worktree branch origin" "$(attempts "${s%%:*}")|$(left "${s%%:*}")"
done
is "no story file is written for a name with none" "" "$(cd "${P}/docs/stories" && ls d1.md conduct-x.md hld-x.md plan-x.md 2>/dev/null)"
is "no PR is closed but s1's" "1" "$(grep -c '^pr close' "${ROOT}/gh.log")"
if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
