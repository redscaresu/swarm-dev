# shellcheck shell=bash
# diff_fixtures_release_gates.sh — tests/diff_run.sh's fixtures for the release gates in the plugin's
# own repo: merge --release's docs gate on a change only to the Go tree, and the patch gate's tests-only
# and port: true changes, through next and merge --release. The own-repo rules fire only when the repo
# gh names is the tree under test's plugin_repo (its plugin.json's repository), so every fixture's gh
# stub names that repo, read from ${TREE}. Each commit a fixture makes has a fixed author, committer
# and date, so both trees' runs see the same SHAs. diff_run.sh sources this file, and every other
# tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
# shellcheck disable=SC2034,SC2154 # diff_run.sh reads the FX_ settings; merge_fixture.sh sets P, FX, H1 and the rest

DIFF_GATE_FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/merge_fixture.sh"

# diff_gate_own — the tree under test's own repo, as plugin_repo reads it: plugin.json's repository,
# lower-cased, past github.com/.
diff_gate_own() {
  python3 -c 'import json, sys; print(json.load(sys.stdin)["repository"].lower().rstrip("/").split("github.com/")[-1])' \
    < "${TREE}/.claude-plugin/plugin.json"
}

# diff_gate_git_env — from here on in the fixture's build: a fixed author, committer and date for each
# commit, and no signing, whatever the user's git config says. The command runs under env -i, so none
# of it reaches the command.
diff_gate_git_env() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    GIT_AUTHOR_DATE='2026-11-01T00:00:00Z' GIT_COMMITTER_DATE='2026-11-01T00:00:00Z'
  export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=tag.gpgSign GIT_CONFIG_VALUE_0=false \
    GIT_CONFIG_KEY_1=tag.forceSignAnnotated GIT_CONFIG_VALUE_1=false GIT_CONFIG_KEY_2=commit.gpgSign GIT_CONFIG_VALUE_2=false
}

# --- next: next_test.sh's release_repo, in the own repo.

# diff_gate_next_project — a project at ${ROOT}/proj whose plugin.json says 1.2.0, tagged v1.2.0, with
# an origin at ${ROOT}/origin.git and a board in docs/. Its gh stub, ${ROOT}/bin/gh, names the own repo
# on repo view and lists one merged PR per line of ${ROOT}/prs (<commit> <head>, numbered from 1) on pr
# list --state merged, and no open PR on pr list --state open; any other call fails. The tag's commit
# is release/v1.2.0's merge. No .swarm/: next's release memo starts with the time in seconds, which
# no mask covers, and is written only where .swarm/ is, so the non-fix cache goes to
# ${ROOT}/gh-cache (SWARM_GH_CACHE) instead.
diff_gate_next_project() {
  diff_gate_git_env
  P="${ROOT}/proj"
  mkdir -p "${P}/docs/stories" "${P}/.claude-plugin" "${P}/.claude/swarm" "${P}/bin" "${ROOT}/bin"
  git init -q --bare "${ROOT}/origin.git"
  git -C "${P}" init -q; git -C "${P}" remote add origin "${ROOT}/origin.git"
  echo "# Stories" > "${P}/docs/stories/README.md"; : > "${P}/.claude/swarm/config"
  echo '{"name":"x","version":"1.2.0"}' > "${P}/.claude-plugin/plugin.json"
  git -C "${P}" add -A; git -C "${P}" commit -q -m init; git -C "${P}" tag v1.2.0
  echo "$(git -C "${P}" rev-parse HEAD) release/v1.2.0" > "${ROOT}/prs"
  { printf '#!/bin/sh\nOWN=%q PRS=%q\n' "$(diff_gate_own)" "${ROOT}/prs"
    cat <<'GH'
case "$1 $2" in
  "repo view") printf '{"nameWithOwner":"%s"}\n' "${OWN}"; exit 0 ;;
  "pr list") case "$*" in
    *"--state merged"*)
      exec awk 'BEGIN { printf "[" } { printf "%s{\"number\":%d,\"headRefName\":\"%s\",\"mergeCommit\":{\"oid\":\"%s\"}}", (NR > 1 ? "," : ""), NR, $2, $1 } END { print "]" }' "${PRS}" ;;
    *"--state open"*) echo '[]'; exit 0 ;;
  esac ;;
esac
exit 1
GH
  } > "${ROOT}/bin/gh"
  chmod +x "${ROOT}/bin/gh"
  cd "${P}"
}
# diff_gate_planned <slug> [<front-matter line>]... — docs/stories/<slug>.md (kind: code, then those
# lines), committed alone as board/plan-<slug>'s merge: the base its story PR merges onto.
diff_gate_planned() {
  local s="$1"; shift
  { echo ---; echo 'kind: code'; [[ $# -eq 0 ]] || printf '%s\n' "$@"; echo ---; } > "docs/stories/${s}.md"
  git add "docs/stories/${s}.md"; git commit -q -m "Plan ${s}"
  echo "$(git rev-parse HEAD) board/plan-${s}" >> "${ROOT}/prs"
}
# diff_gate_story_pr <slug> <file>... — each <file> written, docs/stories/<slug>.md deleted, and the lot
# committed as story/<slug>'s merge.
diff_gate_story_pr() {
  local s="$1" f; shift
  for f in "$@"; do mkdir -p "$(dirname "${f}")"; echo x > "${f}"; done
  git rm -q "docs/stories/${s}.md"; git add -A; git commit -q -m "Merge story/${s}"
  echo "$(git rev-parse HEAD) story/${s}" >> "${ROOT}/prs"
}
# diff_gate_next — the command: the tree's swarm.sh next, once main is pushed and origin/HEAD is main.
diff_gate_next() {
  git push -q origin HEAD:main; git fetch -q origin; git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  FX_CWD="${P}"; FX_GH="${ROOT}/bin/gh"; FX_ENV=("SWARM_GH_CACHE=${ROOT}/gh-cache")
  FX_CMD=(bash "${TREE}/bin/swarm.sh" next)
}

# A story PR with neither fix: nor port:, its whole diff under tests/ once its own story file is deleted.
fx_gate_next_tests_only() {
  diff_gate_next_project; diff_gate_planned t1; diff_gate_story_pr t1 tests/a_test.sh; diff_gate_next
}
# A port: true story PR that changes bin/x and the one tests/ file its touches list at the base.
fx_gate_next_port_listed() {
  diff_gate_next_project; diff_gate_planned p1 'port: true' 'touches: [bin/x:f, tests/a_test.sh:case a]'
  diff_gate_story_pr p1 bin/x tests/a_test.sh; diff_gate_next
}
# A port: true story PR that also changes tests/b_test.sh, which its touches do not list.
fx_gate_next_port_unlisted() {
  diff_gate_next_project; diff_gate_planned p2 'port: true' 'touches: [bin/x, tests/a_test.sh]'
  diff_gate_story_pr p2 bin/x tests/a_test.sh tests/b_test.sh; diff_gate_next
}
# A port: true story PR that changes tests/b_test.sh and adds it to its own story's touches: the
# base's touches count, so it is still unlisted.
fx_gate_next_port_self_listed() {
  diff_gate_next_project; diff_gate_planned p3 'port: true' 'touches: [bin/x]'
  mkdir -p tests; echo x > bin/x; echo x > tests/b_test.sh
  printf -- '---\nkind: code\nport: true\ntouches: [bin/x, tests/b_test.sh]\n---\n' > docs/stories/p3.md
  git add -A; git commit -q -m "Merge story/p3"
  echo "$(git rev-parse HEAD) story/p3" >> "${ROOT}/prs"
  diff_gate_next
}
# A story with neither fix: nor port: that changes bin/x.
fx_gate_next_neither() {
  diff_gate_next_project; diff_gate_planned s9; diff_gate_story_pr s9 bin/x; diff_gate_next
}
# port: x, a value other than true.
fx_gate_next_port_x() {
  diff_gate_next_project; diff_gate_planned p8 'port: x' 'touches: [bin/x]'; diff_gate_story_pr p8 bin/x; diff_gate_next
}

# --- merge --release: merge_rules_test.sh's release cases, in the own repo.

# diff_gate_release_project — merge_fixture.sh's project under ${ROOT} with its release origin: main
# tagged v1.2.0, holding a done docs/retros/v1.3.0.md, and gh naming the own repo. The command runs in
# the project with the stubs as gh and herdr and the claude stub first on PATH, under merge_fixture.sh's
# merge() env (no poll, the zero waits), so no poll count follows the clock.
diff_gate_release_project() {
  export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
  # shellcheck source=tests/merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
  . "${DIFF_GATE_FIXTURE}"
  diff_gate_git_env
  release_origin
  DIFF_GATE_URL="https://github.com/$(diff_gate_own)/pull/7"
  FX_CWD="${P}"; FX_GH="${ROOT}/bin/gh"; FX_HERDR="${ROOT}/bin/herdr"
  FX_ENV=("PATH=${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0
    SWARM_MERGE_CI_SECONDS=60 SWARM_RELEASE_WAIT=0 "GIT_CONFIG_COUNT=${GIT_CONFIG_COUNT}"
    "GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0}" "GIT_CONFIG_VALUE_0=${GIT_CONFIG_VALUE_0}"
    "GIT_CONFIG_KEY_1=${GIT_CONFIG_KEY_1}" "GIT_CONFIG_VALUE_1=${GIT_CONFIG_VALUE_1}"
    "GIT_CONFIG_KEY_2=${GIT_CONFIG_KEY_2}" "GIT_CONFIG_VALUE_2=${GIT_CONFIG_VALUE_2}")
}
# diff_gate_main <message> <file>... — a commit on main that writes each <file>, pushed to origin;
# prints it.
diff_gate_main() {
  local m="$1" f; shift
  for f in "$@"; do mkdir -p "$(dirname "${P}/${f}")"; echo x >> "${P}/${f}"; git -C "${P}" add -f "${f}"; done
  git -C "${P}" commit -q -m "${m}"; git -C "${P}" push -q origin HEAD:refs/heads/main; git -C "${P}" rev-parse HEAD
}
# diff_gate_retag — v1.2.0 moved to main's head, on origin too.
diff_gate_retag() { git -C "${P}" tag -f v1.2.0 > /dev/null; git -C "${P}" push -q -f origin v1.2.0; }
# diff_gate_release <minor|patch> — the release PR, after merge_fixture.sh's release_pr: 1.2.0 to 1.3.0,
# or to 1.2.1 with the stub's merged PRs ${DIFF_GATE_PRS}; and the command, merge --release on it.
diff_gate_release() {
  mkdir -p "${P}/docs/stories"; release_pr; echo "{\"nameWithOwner\":\"$(diff_gate_own)\"}" > "${FX}/origin"
  if [[ "$1" == patch ]]; then
    echo '{"name":"x","version":"1.2.1","hooks":{}}' > "${FX}/wf.plugin.json.${H1}"; echo "${DIFF_GATE_PRS}" > "${FX}/prlist"
  fi
  FX_CMD=(bash "${TREE}/bin/swarm.sh" merge --release "${DIFF_GATE_URL}")
}
# diff_gate_port_patch <touches> — port-a's story, port: true with <touches>, landed on main and tagged
# v1.2.0; then its PR, squash-merged as #9, changing bin/f.sh, tests/a_test.sh and tests/b_test.sh and
# deleting the story; then merge --release of a patch. No doc changed, so the docs gate, which runs
# after the retro gate, refuses the release: the run stops before the merge, and a retro gate that
# passes leaves its pass line alone on stdout.
diff_gate_port_patch() {
  local c
  diff_gate_release_project
  { echo ---; echo 'kind: code'; echo 'port: true'; echo "touches: $1"; echo ---; } > "${P}/docs/stories/port-a.md"
  git -C "${P}" add -f docs/stories/port-a.md; git -C "${P}" commit -q -m "Plan port-a"; git -C "${P}" push -q origin HEAD:refs/heads/main
  diff_gate_retag
  git -C "${P}" rm -q docs/stories/port-a.md
  c="$(diff_gate_main "port-a (#9)" bin/f.sh tests/a_test.sh tests/b_test.sh)"
  DIFF_GATE_PRS="[{\"number\":1,\"headRefName\":\"release/v1.2.0\",\"mergeCommit\":{\"oid\":\"$(git -C "${P}" rev-parse 'v1.2.0^{commit}')\"}},{\"number\":9,\"headRefName\":\"story/port-a\",\"mergeCommit\":{\"oid\":\"${c}\"}}]"
  diff_gate_release patch
}

# The docs gate: since the tag, main changed only cmd/x/main.go, go.mod and internal/guard/x.go, with
# no doc and no Docs: none line; a minor, with its retro. The head's one check failed, so a docs gate
# that passes stops at the CI read that comes next, not at the merge.
fx_gate_release_go_docs() {
  diff_gate_release_project; diff_gate_main "Go tree" cmd/x/main.go go.mod internal/guard/x.go > /dev/null
  diff_gate_release minor; checks "${FX}/${H1}.checks" "$(run test completed failure)"
}
# The patch gate: a port: true story's PR whose tests/ files its touches all list at the base.
fx_gate_release_port_listed() { diff_gate_port_patch '[bin/f.sh, tests/a_test.sh, tests/b_test.sh:case b]'; }
# The patch gate: a port: true story's PR that changes tests/b_test.sh, which its touches do not list.
fx_gate_release_port_unlisted() { diff_gate_port_patch '[bin/f.sh, tests/a_test.sh]'; }
