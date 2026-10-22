#!/usr/bin/env bash
# split_critic_test.sh — /plan-epic's large-epic path with a stub agent: the lead drafts the children
# in the board PR's worktree, board-pr open refuses the split, `swarm.sh agent scope-big split-critic
# ... critic` starts the critic (the herdr stub plays it: given its brief, it writes
# .swarm/big/split-critic.json), and only then does the board PR open. A medium epic's board PR opens
# with no critic. herdr, gh and claude are stubs on PATH; origin is a local bare repo.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_PROMPT_TIMEOUT_MS=3000
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "${ROOT}/bin"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
P="${ROOT}/proj"; URL=https://github.com/o/r/pull/9
fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# herdr: each new pane is w:<n>; agent start makes the session's .jsonl and lists the agent; a prompt
# to the split critic's pane is the critic at work, writing its answer.
printf '#!/bin/sh\nH="%s"; OUT="%s/.swarm/big/split-critic.json"\n' "${ROOT}" "${P}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; label=$(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')
                      echo "t$n $label" >> "$H/tabs"; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "pane split")       next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "agent start")      sid=$(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')
                      mkdir -p "$CLAUDE_PROJECTS_DIR/p"; : > "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl"
                      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt")     if awk -v p="$3" '$2 == p && $1 == "split-critic" { f = 1 } END { exit !f }' "$H/agents"; then
                        mkdir -p "$(dirname "$OUT")"; echo '{"findings":[{"kind":"split-gap","why":"w","fix":"f"}]}' > "$OUT"; fi
                      echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2" in "pr create") echo %s ;; "pr list") echo "[]" ;; *) exit 1 ;; esac\n' "${URL}" > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh" "${ROOT}/bin/claude"

mkdir -p "${P}/.claude/swarm" "${P}/docs/epics" "${P}/docs/stories"
: > "${P}/.claude/swarm/config"; echo .swarm/ > "${P}/.gitignore"
printf -- '---\nstatus: active\n---\n\n# big\n' > "${P}/docs/epics/big.md"
printf -- '---\nstatus: active\n---\n\n# med\n' > "${P}/docs/epics/med.md"
git init -q --bare "${ROOT}/origin.git"; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" init -q -b main && git -C "${P}" add -A && git -C "${P}" commit -qm init
git -C "${P}" remote add origin "${ROOT}/origin.git" && git -C "${P}" push -q -u origin main
sw() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
critics() { grep -c $'\tcritic\tsplit-critic\t' "${P}/.swarm/agents.tsv" 2>/dev/null || true; }
echo "Check the split of docs/epics/big.md." > "${ROOT}/brief.md"; echo "The board edit." > "${ROOT}/body.md"

# --- The large epic: children drafted, the parent left at status: split.
W="$(sw board-pr start scope-big)"; touch -t 202101010000 "${W}/.git"   # so the critic's answer is newer, in the same second too
printf -- '---\nstatus: split\n---\n\n# big\n' > "${W}/docs/epics/big.md"
printf -- '---\nstatus: active\nparent: big\n---\n\n# big-a\n' > "${W}/docs/epics/big-a.md"
out="$(sw board-pr open scope-big "Split big" "${ROOT}/body.md" || true)"
is "before the critic ran, the split's board PR is refused" "yes" "$(grep -q 'start the split critic first' <<< "${out}" && echo yes || echo "no: ${out}")"
is "the refusal is the die alone, with no shell error for the missing file" "swarm: board-pr: big is split, but .swarm/big/split-critic.json holds no {findings:[...]}; start the split critic first" "${out}"
sw agent scope-big split-critic "${P}" critic "${ROOT}/brief.md" >/dev/null
is "the split critic starts as a critic agent" 1 "$(critics)"
is "the critic wrote split-critic.json" '{"findings":[{"kind":"split-gap","why":"w","fix":"f"}]}' "$(cat "${P}/.swarm/big/split-critic.json" 2>/dev/null)"
is "after the critic answered, the split's board PR opens" "${URL}" "$(sw board-pr open scope-big "Split big" "${ROOT}/body.md")"

# --- The medium epic: its board PR opens with no critic. That the medium path starts none is the
# lead's to follow: plan_epic_test's medium-no-split-critic greps it, and the large path's critic is
# enforced by board-pr open's refusal above.
W="$(sw board-pr start scope-med)"
mkdir -p "${W}/docs/stories"; printf -- '---\nkind: code\nstatus: ready\nepic: med\n---\n\n# med-a\n' > "${W}/docs/stories/med-a.md"
is "a medium epic's board PR opens" "${URL}" "$(sw board-pr open scope-med "Plan med" "${ROOT}/body.md")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
