#!/usr/bin/env bash
# escalated_block_test.sh — lead_block writes the lead's block to .swarm/state/board/stories/<slug>.escalated,
# never to the tracked story file: a close that holds a story (held_story) or hands it on as impossible
# leaves the committed body as it was, next still names it escalated and reads the block from state, and
# reset deletes the block. herdr and gh are stubs on PATH: herdr lists the agents in ${ROOT}/agents
# ("<name> <pane>" lines); gh answers pr list with no PRs.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; S="${P}/.swarm/state/board/stories"
mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
: > "${ROOT}/agents"
printf '#!/bin/sh\nA="%s"\n' "${ROOT}/agents" | tee "${ROOT}/bin/gh" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                     END { print "]}}" }' "$A" ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
  "pane list") echo '{"result":{"panes":[]}}' ;;
esac
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$1 $2" in "pr list") echo '[]' ;; esac
exit 0
STUB
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
GIT=(git -c user.name=t -c user.email=t@t)
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
"${GIT[@]}" init -q "${P}" && git -C "${P}" remote add origin "${ROOT}/origin.git"
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; echo; echo "**Done when:** it works."; } > "${P}/docs/stories/$1.md"; }
commit() { "${GIT[@]}" -C "${P}" add docs && "${GIT[@]}" -C "${P}" commit -q -m "$1" && git -C "${P}" push -q origin HEAD:refs/heads/main; }
item h "status: ready" "kind: code"; commit h
started() { # <slug> <pane> — its worktree on story/<slug>, pushed, and its builder open in <pane>
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/$1" "${ROOT}/proj-wt/$1"
  git -C "${ROOT}/proj-wt/$1" push -q origin "story/$1"
  echo "$2 $1" > "${P}/.swarm/state/$1"; echo "$1 $2" >> "${ROOT}/agents"
}
sw() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
body() { awk '/^---$/ && ++n <= 2 { next } n >= 2' "$1"; }   # everything after the front matter
same_body() { [[ "$(body "${P}/docs/stories/$1.md")" == "$(git -C "${P}" show "HEAD:docs/stories/$1.md" | body /dev/stdin)" ]] && echo same; }
next() { (cd "${P}" && env -u HERDR_ENV bash "${SWARM}" next); }

# A paused build holds h for the lead (held_story): kind: lead goes into the front matter, the block
# into state, and the committed body is untouched.
started h w:p1; sw close h paused >/dev/null
is "close h paused: kind: lead, the body as committed, and the block in h.escalated" "lead|same|yes" \
  "$(awk '/^kind: /{ print $2; exit }' "${P}/docs/stories/h.md")|$(same_body h)|$(grep -q '^\*\*Held (paused)\.\*\*' "${S}/h.escalated" && echo yes)"
is "next still names h escalated" "escalated h" "$(next | head -1)"
sw reset h lifted >/dev/null
is "reset h deletes h.escalated and leaves the body as committed" "gone|same" \
  "$([[ -e "${S}/h.escalated" ]] || echo gone)|$(same_body h)"

# impossible hands i on: next reads the **Impossible.** block from state, not from the story file.
# h is done first, so next has no other story to build.
sed -i.bak 's/^status: ready$/status: done/' "${P}/docs/stories/h.md"; rm "${P}/docs/stories/h.md.bak"
item i "status: ready" "kind: code"; commit i
started i w:p2; sw close i impossible >/dev/null
is "close i impossible: the body as committed, and the block in i.escalated" "same|yes" \
  "$(same_body i)|$(grep -q '^\*\*Impossible\.\*\*' "${S}/i.escalated" && echo yes)"
is "next names i escalated, its builder having called its Done when impossible (impossible_block reads state)" \
  "escalated i|yes" "$(next | head -1)|$(next | grep -qF "i's builder called its Done when impossible:" && echo yes)"
sw reset i re-scoped >/dev/null
is "reset i deletes i.escalated and leaves the body as committed" "gone|same" \
  "$([[ -e "${S}/i.escalated" ]] || echo gone)|$(same_body i)"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
