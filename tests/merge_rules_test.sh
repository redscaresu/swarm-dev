#!/usr/bin/env bash
# merge_rules_test.sh — merge_test.sh's cases on what swarm.sh merge merges (the story or epic that
# lists the PR) and --release (the version bump, its docs gate, merge = human's release grant, the
# plugin's own upgrade), who may run it, a story marked costs, merge = human's HLD grant, and
# merge --board's epic guard. On merge_fixture.sh, as merge_test.sh is.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

# --- What is merged, and how.
fresh; item s "status: ready" "prs: ${URL}"; merge "${URL}"; refused "a story that is ready" "s is ready, not review"
# A done story (finished = mark keeps prs:) lists the URL before the epic in review that also does.
fresh; rm "${S}"; item a "status: done" "prs: ${URL}"; mkdir -p "${P}/docs/epics"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"; merge "${URL}"
is "a done story and an epic in review list the URL: the epic merges" "merge e ok|main-ci e ok|reconcile e ok (finished)" "$(events | paste -sd'|' -)"
rm -rf "${P}/docs/stories/a.md" "${P}/docs/epics"
fresh; rm "${S}"; merge "${URL}"; refused "a PR no story or epic lists" "no story or epic lists"
is "a PR no story lists: the line's target is the URL" "merge ${URL}" "$(events | cut -d' ' -f1-2)"
fresh; rm "${S}"; merge --board "${URL}"
is "--board: exits 0" 0 "${rc}"
check "--board: merged" merged
is "--board: merge and main-ci under the URL, no reconcile" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
# Another story in review, whose PR the stub also reports merged: reconcile would finish it.
fresh; item s "status: review" "prs: https://github.com/o/r/pull/8"; merge --board "${URL}"
is "--board runs no reconcile: only merge and main-ci lines" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
check "--board runs no reconcile: the other story stays in review" grep -qx 'status: review' "${S}"
fresh; rm "${S}"; echo '[{"filename":"docs/stories/s.md"},{"filename":"bin/swarm.sh"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge --board "${URL}"; refused "--board with a file off the board" "changes bin/swarm.sh, outside docs/"
fresh; rm "${S}"; echo 2 > "${FX}/nfiles"; merge --board "${URL}"; refused "--board with files missing from gh's list" "cannot list every file"
fresh; rm "${S}"; echo '[{"filename":"docs/x.sh","previous_filename":"bin/swarm.sh","status":"renamed"}]' > "${FX}/files"
merge --board "${URL}"; refused "--board with a file renamed onto the board" "changes bin/swarm.sh, outside docs/"
check "--board reads the files with --paginate" grep -q -- "--paginate repos/o/r/pulls/7/files" "${ROOT}/gh.log"
fresh; rm "${S}"; echo '{"nameWithOwner":"other/repo"}' > "${FX}/origin"
merge --board "${URL}"; refused "--board for a PR outside the board's repo" "is not in other/repo, the board's repo"
# --release: a PR into the project's base that changes only the version in .claude-plugin/plugin.json,
# in the project's own repo, merges with no story listing it and runs no reconcile; any other file or
# field, another base, or another repo, is refused. origin's default branch is main, tagged v1.2.0.
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; git -C "${P}" tag v1.2.0
git -C "${P}" push -q origin HEAD:refs/heads/main v1.2.0; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
release_pr; item s "status: review" "prs: https://github.com/o/r/pull/8"; merge --release "${URL}"
is "--release: exits 0" 0 "${rc}"
check "--release: merged" merged
is "--release: merge and main-ci under the URL, no reconcile" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
# With merge = human the lead merges a release only under HLDs that grant release (below).
# human_release [command...] — release_pr with merge = human, the command run on its fixtures, then merge --release.
human_release() { release_pr; echo "merge = human" >> "${P}/.claude/swarm/config"; "$@"; merge --release "${URL}"; }
human_release; refused "--release with merge = human and no story merged since the tag" "${URL} waits on the user's merge (merge = human, and no story was merged into main since v1.2.0, so no HLD covers it)"
release_pr; echo '[{"filename":".claude-plugin/plugin.json"},{"filename":"bin/swarm.sh"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge --release "${URL}"; refused "--release with another file" "changes bin/swarm.sh, not only .claude-plugin/plugin.json"
release_pr; echo '[{"filename":"docs/stories/s.md"}]' > "${FX}/files"
merge --release "${URL}"; refused "--release with a board file" "changes docs/stories/s.md, not only"
release_pr; echo '{"nameWithOwner":"other/repo"}' > "${FX}/origin"
merge --release "${URL}"; refused "--release for a PR outside the project's repo" "is not in other/repo, the project's repo"
release_pr; merge --release --board "${URL}"; refused "--release with --board" "do not go together"
release_pr; echo '{"name":"x","version":"1.3.0","hooks":{},"mcpServers":{"m":{"command":"sh"}}}' > "${FX}/wf.plugin.json.${H1}"
merge --release "${URL}"; refused "--release that adds mcpServers to plugin.json" "changes more of .claude-plugin/plugin.json than its version"
release_pr; echo '{"name":"x","hooks":{}}' > "${FX}/wf.plugin.json.${H1}"
merge --release "${URL}"; refused "--release that drops the version" "its version None is not MAJOR.MINOR.PATCH"
release_pr; echo '{"name":"x","version":"1.3.0","hooks":{},"strict":true}' > "${FX}/wf.plugin.json"
echo '{"name":"x","version":"1.4.0","hooks":{},"strict":1}' > "${FX}/wf.plugin.json.${H1}"
merge --release "${URL}"; refused "--release that turns true into 1" "changes more of .claude-plugin/plugin.json than its version; if main changed plugin.json after the release branch was cut, merge origin/main into it and retry"
for v in 1.2.0:"is not greater than '1.2.0' on main" 1.1.9:"is not greater than '1.2.0' on main" 1.3.0-rc:"its version '1.3.0-rc' is not MAJOR.MINOR.PATCH"; do
  release_pr; echo "{\"name\":\"x\",\"version\":\"${v%%:*}\",\"hooks\":{}}" > "${FX}/wf.plugin.json.${H1}"
  merge --release "${URL}"; refused "--release to version ${v%%:*}" "${v#*:}"
done
release_pr; echo feature > "${FX}/base"; cp "${FX}/wf.plugin.json" "${FX}/wf.plugin.json.feature"
merge --release "${URL}"; refused "--release for a PR into another branch" "goes into feature, not main, the project's base"
# A release ships its docs: bin/, commands/ or hooks/ changed since origin's tag needs README.md,
# AGENTS.md or docs/ changed too, or a "Docs: none — <reason>" line in the PR body; a commands/*.md
# change answers for itself only. The board is docs/ here: its own paths (stories, epics, hld,
# Board.base, .obsidian) are not docs, and the rest of docs/ is.
commit() { # <file>... — a commit on main that changes each file, pushed to origin
  local f; for f in "$@"; do mkdir -p "$(dirname "${P}/${f}")"; echo x >> "${P}/${f}"; git -C "${P}" add -f "${f}"; done
  git -C "${P}" -c user.name=t -c user.email=t@t commit -q -m "$*"; git -C "${P}" push -q origin HEAD:refs/heads/main
}
retag() { git -C "${P}" tag -f v1.2.0 >/dev/null; git -C "${P}" push -q -f origin v1.2.0; } # v1.2.0 on main's head
commit bin/x.sh docs/stories/x.md docs/epics/x.md docs/hld/x.md docs/Board.base docs/.obsidian/app.json
release_pr; merge --release "${URL}"; refused "--release with bin/ and only board files changed" "bin/x.sh changed since v1.2.0 but README.md, AGENTS.md and docs/ did not"
check "--release's refusal says the forms a Docs: none line takes" said "a line 'Docs: none — ' and why no doc changes (a '- ' or '* ' bullet before it, or - or -- for the dash, also do; not in a \`\`\` block or a > quote)"
# shellcheck disable=SC2016 # the backticks are a markdown fence
for b in 'Bumps the version.\r\nDocs: none \u2014 a typo in a comment\r\n' '- Docs: none -- only tests changed' '* Docs: none - a comment' \
  '```sh\nx\n```\nDocs: none \u2014 after a fence'; do
  release_pr; printf '"%s"\n' "${b}" > "${FX}/body"; merge --release "${URL}"
  is "--release with bin/ changed and '${b}': exits 0" 0 "${rc}"
done
# shellcheck disable=SC2016 # the backticks are a markdown fence
for b in 'Docs: none' 'Docs: none \u2014\r\nmore' 'Docs: none \u2014 \r\nmore' 'Docs: none --' 'Docs: none -- ' \
  'Docs: none \u2014 <reason>' 'Docs: none - -' 'Docs: none \u2014 x' '  Docs: none \u2014 indented' \
  'Template:\n```\nDocs: none \u2014 inside a fence\n```' '> Docs: none \u2014 quoted from another PR'; do
  release_pr; printf '"%s"\n' "${b}" > "${FX}/body"; merge --release "${URL}"
  refused "--release with '${b}' and no reason" "bin/x.sh changed since v1.2.0"
done
release_pr; echo '{"name":"x","version":"1.2.5","hooks":{}}' > "${FX}/wf.plugin.json"
merge --release "${URL}"; refused "--release with no tag for the base's version" "no v1.2.5 tag on origin to compare against: tag main's last release v1.2.5, or give the PR body a line 'Docs: none — '"
# v1.2.5 on a commit that is not on main.
git -C "${P}" tag v1.2.5 "$(git -C "${P}" -c user.name=t -c user.email=t@t commit-tree -m side "HEAD^{tree}")"; git -C "${P}" push -q origin v1.2.5
release_pr; echo '{"name":"x","version":"1.2.5","hooks":{}}' > "${FX}/wf.plugin.json"
merge --release "${URL}"; refused "--release with the base's tag off the base" "the tag v1.2.5 is not on origin/main"
# origin's tag is read, never fetched over the local one.
git -C "${P}" tag -f v1.2.0 HEAD >/dev/null; local_tag="$(git -C "${P}" rev-parse v1.2.0)"
release_pr; merge --release "${URL}"; refused "--release with a local tag that differs from origin's" "bin/x.sh changed since v1.2.0"
is "--release leaves the local tag where it was" "${local_tag}" "$(git -C "${P}" rev-parse v1.2.0)"
commit docs/method.md
release_pr; merge --release "${URL}"
is "--release with bin/ and docs/method.md beside the board in docs/ changed: exits 0" 0 "${rc}"
retag; commit bin/y.sh commands/y.md
release_pr; merge --release "${URL}"; refused "--release with bin/ and commands/*.md changed and no other docs" "bin/y.sh, commands/y.md changed since v1.2.0"
retag; commit hooks/x.sh
release_pr; merge --release "${URL}"; refused "--release with only hooks/ changed" "hooks/x.sh changed since v1.2.0"
retag; commit commands/x.sh
release_pr; merge --release "${URL}"; refused "--release with only a non-.md file under commands/ changed" "commands/x.sh changed since v1.2.0"
retag; commit commands/x.md
release_pr; merge --release "${URL}"
is "--release with only commands/*.md changed: exits 0" 0 "${rc}"
retag; commit hooks/x.sh README.md
release_pr; merge --release "${URL}"
is "--release with hooks/ and README.md changed: exits 0" 0 "${rc}"
# An annotated v1.2.0 made in another clone, whose tag object a --no-tags checkout never fetches.
git clone -q "${ROOT}/origin.git" "${ROOT}/other"; git -C "${P}" config remote.origin.tagOpt --no-tags
git -C "${ROOT}/other" -c user.name=t -c user.email=t@t tag -a -f -m v1.2.0 v1.2.0 >/dev/null; git -C "${ROOT}/other" push -q -f origin v1.2.0
commit bin/y.sh README.md
release_pr; merge --release "${URL}"
is "--release against an annotated tag it has not fetched: exits 0" 0 "${rc}"
git -C "${P}" config --unset remote.origin.tagOpt
# With merge = human, --release merges only when every story deleted on main since the tag (main's
# own commits, a merge's deletions against its first parent), read as it was just before, is under
# an agreed HLD granting release: its epic as that commit had it, the HLD as origin's main has it. A
# story done on the board since the tag counts too. The docs gate holds whatever the grant says.
front() { { echo ---; printf '%s\n' "${@:2}"; echo ---; } > "${P}/$1"; } # <file> <front-matter line>...
gt() { git -C "${P}" -c user.name=t -c user.email=t@t "$@"; }
push() { gt push -q origin HEAD:refs/heads/main; }
landed() { front "$@"; gt add -f "$1"; gt commit -q -m "$1"; push; } # <file> <front-matter line>... — committed on main
gone() { gt rm -q "$@"; gt commit -q -m "rm $*"; push; } # <file>... — deleted on main, as a story's PR deletes its story
merge_in() { gt update-ref HEAD "$(gt commit-tree -p HEAD -p "$1" -m "merge $1" "${2:-HEAD}^{tree}")"; push; } # <commit> [tree] — merged into main
dropped() { local side; side="$(gt commit-tree -p HEAD -m side "HEAD^{tree}")"; gt rm -q "$1"; merge_in "${side}" "$(gt write-tree)"; } # <file> — a merge deletes it
# branch_merged <slug> <rev> — a PR from story/<slug> merged as <rev>.
branch_merged() { printf '[{"mergeCommit":{"oid":"%s"}}]' "$(gt rev-parse "$2^{commit}")" > "${FX}/prlist.$1"; }
retag; landed docs/hld/ship.md "status: agreed" "grants: [merge, release]"; landed docs/epics/shipped.md "hld: ship"
landed docs/stories/shipped-a.md "epic: shipped"; gone docs/stories/shipped-a.md
landed docs/stories/shipped-b.md "epic: shipped"; gone docs/stories/shipped-b.md docs/epics/shipped.md
human_release
is "--release with merge = human, every story since the tag under an HLD granting release, its epic gone: exits 0" 0 "${rc}"
check "--release with merge = human, every story under an HLD granting release: merged" merged
# kept: its PR left its file on main, so reconcile marked it done in its state and cleared its prs:.
# mark_done marks a story so; unmark_done takes the state off, and it reads as its file says (ready).
mark_done() { mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: done\nstatus@base: ready\n' > "${P}/.swarm/board-state/stories/$1"; }
unmark_done() { rm -f "${P}/.swarm/board-state/stories/$1"; }
landed docs/stories/kept.md "status: ready" "epic: none-such"; mark_done kept
human_release branch_merged kept HEAD; refused "--release with merge = human and a story reconcile marked done since the tag, under no HLD" "story kept, done on the board since v1.2.0, is under no agreed HLD that grants release"
human_release branch_merged kept v1.2.0
is "--release with merge = human and a story reconcile marked done before the tag, under no HLD: exits 0" 0 "${rc}"
human_release touch "${FX}/prlist.kept.fail"
refused "--release with merge = human, a story reconcile marked done under no HLD, and gh unable to list its PRs" "story kept, done on the board (gh cannot list its PRs, so it may have merged since v1.2.0), is under no agreed HLD that grants release"
unmark_done kept
# The board is read as origin's main has it: the checkout may not have pulled.
landed docs/hld/ship.md "status: agreed" "grants: [merge]"; front docs/hld/ship.md "status: agreed" "grants: [merge, release]"
human_release; refused "--release with merge = human, the HLD granting release in the checkout but not on main" "story shipped-b, merged since v1.2.0, is under no agreed HLD that grants release"
landed docs/hld/ship.md "status: agreed" "grants:" "  - release"
human_release; refused "--release with merge = human and an HLD whose grants: is a block list" "the grants: of hld/ship.md, over story shipped-b, cannot be read"
gone docs/hld/ship.md
human_release; refused "--release with merge = human and the HLD deleted on main" "story shipped-b, merged since v1.2.0, is under no agreed HLD that grants release"
landed docs/hld/ship.md "status: agreed" "grants: [merge, release]"
# A done story on main under an HLD that does not grant release, which the checkout has not pulled:
# absent there, or with an older epic: under one that does.
landed docs/hld/plain.md "status: agreed" "grants: [merge]"; landed docs/epics/plain.md "hld: plain"; landed docs/epics/shipping.md "hld: ship"
landed docs/stories/stale.md "status: ready" "epic: plain"; mark_done stale; rm "${P}/docs/stories/stale.md"
human_release branch_merged stale HEAD; refused "--release with merge = human and a done story on main the checkout lacks, under no HLD granting release" "story stale, done on the board since v1.2.0, is under no agreed HLD that grants release"
front docs/stories/stale.md "status: ready" "epic: shipping"
human_release branch_merged stale HEAD; refused "--release with merge = human and a done story whose epic: in the checkout is older than main's" "story stale, done on the board since v1.2.0, is under no agreed HLD that grants release"
front docs/stories/stale.md "status: ready" "epic: plain"; unmark_done stale
landed docs/stories/stray.md "epic: none-such"; gone docs/stories/stray.md
human_release; refused "--release with merge = human and a story since the tag under no HLD" "${URL} waits on the user's merge (merge = human, and story stray, merged since v1.2.0, is under no agreed HLD that grants release)"
retag; landed docs/epics/shipped.md "hld: ship"; landed docs/stories/shipped-d.md "epic: shipped"; gone docs/stories/shipped-d.md docs/epics/shipped.md
landed docs/stories/merged-away.md "epic: none-such"; dropped docs/stories/merged-away.md
human_release; refused "--release with merge = human and a story a merge commit deleted under no HLD" "story merged-away, merged since v1.2.0, is under no agreed HLD that grants release"
retag; landed docs/epics/shipped.md "hld: ship"; landed docs/stories/shipped-e.md "epic: shipped"; gone docs/stories/shipped-e.md docs/epics/shipped.md
landed "docs/stories/naïve.md" "epic: none-such"; gone "docs/stories/naïve.md"
human_release; refused "--release with merge = human and a story with a non-ASCII name under no HLD" "story naïve, merged since v1.2.0, is under no agreed HLD that grants release"
# A story branch cut before old was deleted merges main back in, then merges into main after the tag:
# its merge of main deletes old against the branch, but old left main before the tag.
landed docs/stories/old.md "epic: none-such"; side="$(gt commit-tree -p HEAD -m side "HEAD^{tree}")"; gone docs/stories/old.md
retag; landed docs/epics/shipped.md "hld: ship"; landed docs/stories/shipped-f.md "epic: shipped"; gone docs/stories/shipped-f.md docs/epics/shipped.md
merge_in "$(gt commit-tree -p "${side}" -p HEAD -m "merge main into the branch" "HEAD^{tree}")"
human_release
is "--release with merge = human and a story main deleted before the tag, which a branch's merge of main deletes again: exits 0" 0 "${rc}"
# The one story since the tag kept its file: reconcile marked it done, and gh shows its PR merged.
retag; landed docs/epics/shipped.md "hld: ship"
landed docs/stories/kept.md "status: ready" "epic: shipped"; mark_done kept
human_release branch_merged kept HEAD
is "--release with merge = human and only a story reconcile marked done since the tag, under an HLD granting release: exits 0" 0 "${rc}"
unmark_done kept; gone docs/epics/shipped.md
retag; landed docs/epics/shipped.md "hld: ship"; landed docs/stories/shipped-c.md "epic: shipped"; gone docs/stories/shipped-c.md docs/epics/shipped.md
commit bin/z.sh
human_release; refused "--release with merge = human, covered, with bin/ changed and no docs" "bin/z.sh changed since v1.2.0 but README.md, AGENTS.md and docs/ did not"
retag
# The base moves between the release check and the merge: the check runs again on the new base. A
# story landed there under no HLD granting release is refused, though the first check passed.
# held <command>... — run it (commits on main), then put origin's main back; prints the commit, for moved.
held() { local was; was="$(gt rev-parse HEAD)"; "$@"; gt rev-parse HEAD; gt push -q -f origin "${was}:refs/heads/main"; }
# moved <sha> — origin's main moves to <sha> once the head's checks are read.
moved() { echo "git -C '${ROOT}/origin.git' update-ref refs/heads/main $1" > "${FX}/on-checks"; }
landed docs/epics/shipped.md "hld: ship"; landed docs/stories/shipped-g.md "epic: shipped"; gone docs/stories/shipped-g.md docs/epics/shipped.md
was="$(gt rev-parse HEAD)"; late="$(held eval 'landed docs/stories/late.md "epic: none-such"; gone docs/stories/late.md')"
human_release moved "${late}"
refused "--release with merge = human and a story under no HLD landed on main between the check and the merge" "story late, merged since v1.2.0, is under no agreed HLD that grants release"
check "--release with main moved after the check: says so, and checks again" said "origin/main moved from ${was:0:7} to ${late:0:7} since the release check, so it runs again"
retag
fetched() { echo "git -C '${P}' update-ref refs/remotes/origin/main $1" > "${FX}/on-contents"; } # <sha> — the local origin/main moves mid-check
landed docs/epics/shipped.md "hld: ship"; landed docs/stories/shipped-h.md "epic: shipped"; gone docs/stories/shipped-h.md docs/epics/shipped.md
was="$(gt rev-parse HEAD)"; late="$(held eval 'landed docs/stories/late2.md "epic: none-such"; gone docs/stories/late2.md')"
human_release fetched "${late}"
is "--release with origin/main moved locally mid-check: the checks read the commit fetched first, and it merges" "0 yes" "${rc} $(merged && echo yes)"
check "--release reads the base's plugin.json at the commit it fetched" grep -q "contents/.claude-plugin/plugin.json?ref=${was}" "${ROOT}/gh.log"
push; retag
# A release of the plugin's own repo (plugin.json's repository), once its tag and published release
# are on the merge commit or after it: the marketplace and the plugin are updated, then the new
# version's upgrade starts once in each swarm project herdr runs an agent in, found by the agent's
# restore wrapper's SWARM_PROJECT (an external board's builder runs in a story repo with no config)
# or else its cwd, and the user is asked to restart the lead in each.
OWN_REPO="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["repository"].lower().rstrip("/").split("github.com/")[-1])' < "${REPO}/.claude-plugin/plugin.json")"
HOME_DIR="$(cd "${REPO}" && pwd)"   # the plugin under test, the old version here
OWN="https://github.com/${OWN_REPO}/pull/7"; NEW="${CLAUDE_CONFIG_DIR}/plugins/cache/swarm-dev/swarm-dev/1.3.0/bin/swarm.sh"
mkdir -p "${NEW%/*}" "${ROOT}/proj2/.claude/swarm" "${ROOT}/proj3/.claude/swarm" "${ROOT}/story" "${CLAUDE_CONFIG_DIR}/swarm-dev/resume"
git -C "${ROOT}/proj2" init -q; : > "${ROOT}/proj2/.claude/swarm/config"; : > "${ROOT}/proj3/.claude/swarm/config"; git -C "${ROOT}/story" init -q
printf "env.update(SWARM_PROJECT='%s', SWARM_RESUME='x')\n" "${ROOT}/proj3" > "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/sess-3.py"
# The new version's swarm.sh: logs each call, and "old PATH" when the old version's bin/ or gh-shim is
# on its PATH, with or without a trailing slash; fails in a project holding upgrade.fail; hangs in one
# holding upgrade.hang; starts nothing in one holding upgrade.busy.
# shellcheck disable=SC2016 # expanded when the stubs run
printf '#!/bin/sh\necho "${SWARM_PROJECT} $*" >> "%s"\ncase ":${PATH}:" in *":%s/bin:"*|*":%s/bin/:"*|*":%s/bin/gh-shim:"*|*":%s/bin/gh-shim/:"*) echo "old PATH" >> "%s" ;; esac
[ ! -e "${SWARM_PROJECT}/upgrade.fail" ] || exit 1
[ ! -e "${SWARM_PROJECT}/upgrade.hang" ] || sleep 5
[ ! -e "${SWARM_PROJECT}/upgrade.busy" ] || { echo "swarm.sh upgrade already runs here (pid 9, log x); this one started nothing"; exit 0; }
echo "log ${SWARM_PROJECT}/.swarm/upgrade-1.3.0.log"\n' "${ROOT}/upgrade.log" "${HOME_DIR}" "${HOME_DIR}" "${HOME_DIR}" "${HOME_DIR}" "${ROOT}/upgrade.log" > "${NEW}"
own_release() {
  release_pr; rm -f "${ROOT}/claude.log" "${ROOT}/upgrade.log"; echo "{\"nameWithOwner\":\"${OWN_REPO}\"}" > "${FX}/origin"
  printf '{"object":{"sha":"%s"}}' "${M}" > "${FX}/tagref"; echo '{"draft":false}' > "${FX}/release"; echo '{"status":"behind"}' > "${FX}/compare.main"
}
upgraded() { paste -sd'|' - < "${ROOT}/upgrade.log" 2>/dev/null; }
cp "${ROOT}/agents" "${ROOT}/agents.keep"
printf 'conduct-e w:c %s\nt w:b %s/docs\nu w:u %s\nv w:v %s\nw w:w %s sess-3\n' "${P}" "${P}" "${ROOT}/proj2" "${ROOT}" "${ROOT}/story" > "${ROOT}/agents"
own_release; merge --release "${OWN}"
is "--release of the plugin's repo: exits 0" 0 "${rc}"
is "--release of the plugin's repo: updates the marketplace, then the plugin" "plugin marketplace update swarm-dev|plugin update swarm-dev@swarm-dev" "$(paste -sd'|' - < "${ROOT}/claude.log")"
is "--release of the plugin's repo: the new version's upgrade, once in each project with agents, an external board's too" "${P} upgrade|${ROOT}/proj2 upgrade|${ROOT}/proj3 upgrade" "$(upgraded)"
check "--release of the plugin's repo: prints the upgrade's log" said "log ${P}/.swarm/upgrade-1.3.0.log"
check "--release of the plugin's repo: asks for the lead's restart in each project" said "Restart the lead session in ${P}, ${ROOT}/proj2, ${ROOT}/proj3 (/exit, then claude --continue)"
check "--release of the plugin's repo: the upgrade runs without the old version's bin/ or gh-shim on PATH" bash -c "! grep -q 'old PATH' '${ROOT}/upgrade.log'"
own_release; touch "${ROOT}/proj2/upgrade.busy"; merge --release "${OWN}"; rm "${ROOT}/proj2/upgrade.busy"
check "--release where another upgrade runs: warns, naming the new version's upgrade" said "warning: another swarm.sh upgrade runs in ${ROOT}/proj2, so 1.3.0's started nothing: once it ends, run SWARM_PROJECT=${ROOT}/proj2 ${NEW} upgrade"
check "--release where another upgrade runs: its lead is still asked to restart" said "Restart the lead session in ${P}, ${ROOT}/proj2, ${ROOT}/proj3 ("
own_release; touch "${ROOT}/proj2/upgrade.hang"; merge SWARM_UPGRADE_START_WAIT=1 --release "${OWN}"; rm "${ROOT}/proj2/upgrade.hang"
check "--release where an upgrade hangs: warns, naming the new version's upgrade" said "warning: swarm.sh upgrade in ${ROOT}/proj2 did not start within 1s: run SWARM_PROJECT=${ROOT}/proj2 ${NEW} upgrade"
is "--release where an upgrade hangs: moves on to the next" "${P} upgrade|${ROOT}/proj2 upgrade|${ROOT}/proj3 upgrade" "$(upgraded)"
check "--release where an upgrade hangs: still asks for the restart" said "Restart the lead session in ${P}, ${ROOT}/proj2, ${ROOT}/proj3 ("
own_release; merge PATH="${HOME_DIR}/bin/:${HOME_DIR}/bin:${HOME_DIR}/bin/gh-shim/:${ROOT}/bin:${PATH}" --release "${OWN}"
check "--release with the old bin/ and gh-shim on PATH twice, with a trailing slash: the upgrade's PATH has neither" bash -c "grep -q upgrade '${ROOT}/upgrade.log' && ! grep -q 'old PATH' '${ROOT}/upgrade.log'"
own_release; touch "${P}/upgrade.fail"; merge --release "${OWN}"; rm "${P}/upgrade.fail"
is "--release with a failed upgrade in one project: exits 0" 0 "${rc}"
check "--release with a failed upgrade in one project: warns, naming the new version's upgrade" said "warning: swarm.sh upgrade in ${P} failed (exit 1): run SWARM_PROJECT=${P} ${NEW} upgrade"
is "--release with a failed upgrade in one project: moves on to the next" "${P} upgrade|${ROOT}/proj2 upgrade|${ROOT}/proj3 upgrade" "$(upgraded)"
check "--release with a failed upgrade in one project: still asks for the restart" said "Restart the lead session in ${P}, ${ROOT}/proj2, ${ROOT}/proj3 ("
cp "${ROOT}/agents.keep" "${ROOT}/agents"
own_release; merge --release "${OWN}"
is "--release of the plugin's repo, no agent's cwd known: upgrades this project" "${P} upgrade" "$(upgraded)"
check "--release of the plugin's repo, no agent's cwd known: asks for this lead's restart" said "Restart the lead session in ${P} (/exit, then claude --continue)"
check "--release of the plugin's repo, no agent's cwd known: says why only this project" said "warning: herdr lists no agent in a swarm project, so only ${P} is upgraded"
own_release; touch "${ROOT}/agents.fail"; merge --release "${OWN}"; rm "${ROOT}/agents.fail"
check "--release when herdr's list fails: says so, and upgrades this project" bash -c "grep -qF 'warning: herdr agent list failed or took over 30s, so only ${P} is upgraded' '${ROOT}/out' && [ \"\$(cat '${ROOT}/upgrade.log')\" = '${P} upgrade' ]"
own_release; touch "${ROOT}/agents.garbage"; merge --release "${OWN}"; rm "${ROOT}/agents.garbage"
check "--release when herdr's list is not JSON: says so" said "warning: herdr's agent list could not be read, so only ${P} is upgraded"
own_release; touch "${FX}/update.fail"; merge --release "${OWN}"
is "--release with a failed plugin update: exits 0" 0 "${rc}"
check "--release with a failed plugin update: warns, naming the new version's upgrade" said "warning: updating the plugin to 1.3.0 failed, so no agent was moved: run swarm.sh update, then ${NEW} upgrade"
check "--release with a failed plugin update: no upgrade, no restart line" bash -c "[ ! -e '${ROOT}/upgrade.log' ] && ! grep -q Restart '${ROOT}/out'"
own_release; mv "${NEW}" "${NEW}.away"; merge --release "${OWN}"; mv "${NEW}.away" "${NEW}"
is "--release whose update left no new swarm.sh: exits 0" 0 "${rc}"
check "--release whose update left no new swarm.sh: warns" said "warning: the plugin update left no ${NEW}, so no agent was moved"
check "--release whose update left no new swarm.sh: no restart line" bash -c "! grep -q Restart '${ROOT}/out'"
own_release; printf '{"object":{"sha":"%s"}}' "${H2}" > "${FX}/tagref"; merge --release "${OWN}"
check "--release whose tag is on a later commit: updates the plugin" grep -q "plugin update" "${ROOT}/claude.log"
own_release; printf '{"object":{"sha":"%s"}}' "${H2}" > "${FX}/tagref"; echo '{"status":"ahead"}' > "${FX}/compare.main"; merge --release "${OWN}"
check "--release whose tag is on a branch cut after the merge: warns, and no plugin update" bash -c "grep -q 'no tag v1.3.0 on the base at or after aaaaaaa' '${ROOT}/out' && [ ! -e '${ROOT}/claude.log' ]"
own_release; checks "${FX}/${M}.checks" "$(run test in_progress)"; wfruns "${FX}/${M}.runs" "$(run ci in_progress "" "${M}")"; merge SWARM_MERGE_CI_SECONDS=0.5 --release "${OWN}"
check "--release whose base CI is not green: warns that the plugin was not updated, naming the new version's upgrade" said "warning: CI on the base is not green, so the plugin was not updated: once v1.3.0 is published, run swarm.sh update, then ${NEW} upgrade"
check "--release whose base CI is not green: no plugin update" test ! -e "${ROOT}/claude.log"
own_release; printf '{"object":{"sha":"%s"}}' "${H2}" > "${FX}/tagref"; echo '{"status":"diverged"}' > "${FX}/compare.${M}"; merge --release "${OWN}"
is "--release whose tag is on another branch's commit: exits 0" 0 "${rc}"
check "--release whose tag is on another branch's commit: warns, and no plugin update" bash -c "grep -q 'no tag v1.3.0 on the base at or after aaaaaaa' '${ROOT}/out' && [ ! -e '${ROOT}/claude.log' ]"
own_release; echo '{"draft":true}' > "${FX}/release"; merge --release "${OWN}"
check "--release whose GitHub release is a draft: no plugin update" test ! -e "${ROOT}/claude.log"
own_release; printf '{"object":{"sha":"%s"}}' "${H2}" > "${FX}/tagref"; echo '{"draft":true}' > "${FX}/release"; merge SWARM_RELEASE_WAIT=2 --release "${OWN}"
is "--release waiting on a draft: the tag's commit is compared once, however many polls" "1|1" "$(grep -c "compare/${M}\.\.\.${H2}" "${ROOT}/gh.log")|$(grep -c "compare/main\.\.\.${H2}" "${ROOT}/gh.log")"
check "--release waiting on a draft: polled more than once" bash -c "[ \$(grep -c 'git/ref/tags/v1.3.0' '${ROOT}/gh.log') -gt 1 ]"
# The merge commit sits on the base the release check read, else the release shipped commits no check
# read: refused, naming them, and the plugin is not updated.
was="$(gt rev-parse HEAD)"; late="$(held commit bin/late.sh README.md)"
own_release; moved "${late}"; parent "${late}"; merge --release "${OWN}"
is "--release with main moved after the check, checked again: exits 0" 0 "${rc}"
check "--release with main moved after the check, checked again: says so" said "origin/main moved from ${was:0:7} to ${late:0:7} since the release check, so it runs again"
check "--release with main moved after the check, checked again: merges onto it and updates the plugin" bash -c "grep -q '^pr merge' '${ROOT}/gh.log' && grep -q 'plugin update' '${ROOT}/claude.log'"
was="${late}"; late="$(held eval 'commit bin/late2.sh; commit bin/late3.sh')"; shipped="$(gt log --format=%h "${was}..${late}" | paste -sd' ' -)"
own_release; echo "git -C '${ROOT}/origin.git' update-ref refs/heads/main ${late}" > "${FX}/on-merge"; parent "${late}"; merge --release "${OWN}"
is "--release whose merge commit's parent is not the base it checked: exits 0" 0 "${rc}"
check "--release whose merge commit's parent is not the base it checked: names the unchecked commits" said "warning: aaaaaaa's first parent is ${late:0:7}, not ${was:0:7}, the base the release check read, so it ships ${shipped} unchecked"
check "--release whose merge commit's parent is not the base it checked: says why the plugin was not updated" said "refused: the release ships commits no release check read, so the plugin was not updated and no agent was moved: once they are checked, run swarm.sh update, then ${NEW} upgrade"
check "--release whose merge commit's parent is not the base it checked: no plugin update, no upgrade" bash -c "[ ! -e '${ROOT}/claude.log' ] && [ ! -e '${ROOT}/upgrade.log' ]"
check "--release whose merge commit's parent is not the base it checked: logs the refusal" logged "merge ${OWN} unchecked: aaaaaaa's first parent is ${late:0:7}, not ${was:0:7}"
# reported <target> — the warning that the merge commit's parent is H2, its events.tsv line, and no plugin advice.
reported() { said "warning: aaaaaaa's first parent is 2222222, not " && logged "merge $1 unchecked: aaaaaaa's first parent is 2222222, not " && ! said "refused:"; }
own_release; parent "${H2}"; checks "${FX}/${M}.checks" "$(run test in_progress)"; wfruns "${FX}/${M}.runs" "$(run ci in_progress "" "${M}")"; merge SWARM_MERGE_CI_SECONDS=0.5 --release "${OWN}"
check "--release with base CI not green and another parent: reports and logs the unchecked commits, with no plugin advice" reported "${OWN}"
own_release; rm "${FX}/commit.${M}"; merge --release "${OWN}"
check "--release whose merge commit's parent gh cannot read: warns, and no plugin update" bash -c "grep -qF 'warning: gh cannot read the first parent of aaaaaaa' '${ROOT}/out' && grep -qF 'refused: the release ships commits no release check read' '${ROOT}/out' && [ ! -e '${ROOT}/claude.log' ]"
own_release; echo '{"nameWithOwner":"o/r"}' > "${FX}/origin"; parent "${H2}"; merge --release "${URL}"
is "--release of another repo: exits 0" 0 "${rc}"
check "--release of another repo whose merge commit has another parent: reports and logs the unchecked commits, with no plugin advice" reported "${URL}"
check "--release of another repo: no plugin update, no upgrade" bash -c "[ ! -e '${ROOT}/claude.log' ] && [ ! -e '${ROOT}/upgrade.log' ]"
check "--release of another repo: says why" said "o/r is not this plugin's repo (${OWN_REPO}), so the plugin is not updated"
fresh; echo '{"squashMergeAllowed":false,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' > "${FX}/repo"; merge "${URL}"
check "squash off, merge commits on: --merge" grep -qxF "pr merge 7 --repo o/r --merge --match-head-commit ${H1}" "${ROOT}/gh.log"

# --- Who may merge: outside herdr (above), the lead's own pane, and with merge = agent a conductor.
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"; refused "a builder's pane" "pane w:b is one this project started"
fresh "merge = human"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"; refused "a conductor's pane with merge = human" "pane w:c"
fresh "merge = agent"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"
is "a conductor's pane with merge = agent: exits 0" 0 "${rc}"
fresh "merge = agent"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"; refused "a builder's pane with merge = agent" "pane w:b"
fresh; mkdir -p "${P}/.swarm/state/a-directory"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"
refused "a builder's pane beside a directory in .swarm/state" "pane w:b"
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"
is "the lead's own pane beside a directory in .swarm/state: exits 0" 0 "${rc}"; rmdir "${P}/.swarm/state/a-directory"
fresh "merge = agent"; printf 'conduct-e-done w:c\nt w:b\n' > "${ROOT}/agents"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"
refused "a retired conductor's pane" "pane w:c"; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"
is "the lead's own pane: exits 0" 0 "${rc}"
fresh; merge HERDR_ENV=1 "${URL}"; refused "herdr with no HERDR_PANE_ID" "no HERDR_PANE_ID"
fresh; touch "${ROOT}/agents.fail"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"; refused "herdr that cannot list its agents" "herdr cannot list"
rm "${ROOT}/agents.fail"
fresh; chmod 000 "${P}/.swarm/state/e"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"; refused "an unreadable tab record" "cannot read"
chmod 644 "${P}/.swarm/state/e"
fresh; rm "${S}"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b --board "${URL}"; refused "--board from a builder's pane" "pane w:b"
fresh "merge = agent"; rm "${S}"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"
is "--board from a conductor's pane with merge = agent: exits 0" 0 "${rc}"
# A review agent's pane: its tab record names review-<slug>, the newest agents.tsv line for that name
# has role review, and herdr's agent in the pane holds that name. It merges its own story's PR only,
# never with --board or --release, under merge = human only where an HLD grants merge.
# reviewer <name> [role] — pane w:r is <name>'s: a tab record of its own, herdr's agent, and the one
# agents.tsv line, with <role> (default review).
reviewer() {
  printf 'w:r %s\n' "$1" > "${P}/.swarm/state/r"
  printf 'conduct-e w:c\nt w:b\n%s w:r\n' "$1" > "${ROOT}/agents"
  printf '2026-10-26\t%s\t%s\tclaude\tsonnet\thigh\t-\n' "${2:-review}" "$1" > "${P}/.swarm/agents.tsv"
}
# own_pr <slug> [config line]... — fresh, with story <slug> in review listing the PR in place of s, and
# none of these cases' other stories.
own_pr() { fresh "${@:2}"; rm -f "${S}" "${P}"/docs/stories/{a,b,t,x,a-done}.md; item "$1" "status: review" "prs: ${URL}"; }
# human_pr <grants> — own_pr a with merge = human, story a under epic g, g under agreed HLD h granting
# <grants>, and a.md the file the PR changes, so pr_hld finds h.
human_pr() {
  own_pr a "merge = human"; mkdir -p "${P}/docs/hld" "${P}/docs/epics"
  printf -- '---\nstatus: agreed\ngrants: [%s]\n---\n\n# h\n' "$1" > "${P}/docs/hld/h.md"
  printf -- '---\nstatus: active\nhld: h\n---\n\n# g\n' > "${P}/docs/epics/g.md"
  item a "status: review" "prs: ${URL}" "epic: g"; echo '[{"filename":"docs/stories/a.md","status":"modified"}]' > "${FX}/files"
}
own_pr a; reviewer review-a; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
is "review-a's pane, story a's PR, merge = agent: exits 0" 0 "${rc}"
check "review-a's pane, story a's PR, merge = agent: gh pr merge ran" merged
own_pr b; item a "status: review" "prs: https://github.com/o/r/pull/8"; reviewer review-a; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "review-a's pane, story b's PR" "review-a merges only a PR on story a's prs: line, and ${URL} is not on it"
for o in --board --release; do
  own_pr a; reviewer review-a; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${o}" "${URL}"
  refused "review-a's pane with ${o}" "review-a merges only story a's PR, never with ${o}"
done
human_pr merge; reviewer review-a; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
is "merge = human, review-a's pane, story a's PR under grants: [merge]: exits 0" 0 "${rc}"
check "merge = human, review-a's pane, story a's PR under grants: [merge]: gh pr merge ran" merged
human_pr stories; reviewer review-a; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "merge = human, review-a's pane, story a's PR under no merge grant" "${URL} waits on the user's merge (merge = human, and no HLD grants merge for it)"
rm -rf "${P}/docs/hld" "${P}/docs/epics"
# A builder's pane, for its own story's PR too.
own_pr t; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"; refused "a builder's pane, its story's PR, merge = agent" "pane w:b is one this project started"
own_pr t "merge = human"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"; refused "a builder's pane, its story's PR, merge = human" "pane w:b is one this project started"
# A pane named review-<slug> whose record is not a review agent's.
own_pr x; reviewer review-x code; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "a pane named review-x whose agents.tsv role is code (story review-x's builder), story x's PR" "pane w:r is one this project started"
own_pr a; reviewer review-a; rm "${P}/.swarm/agents.tsv"; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "a pane named review-a with no agents.tsv line" "pane w:r is one this project started"
own_pr a-done; reviewer review-a-done; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "a review-a-done pane, though its agents.tsv role is review and story a-done lists the PR" "pane w:r is one this project started"
# A record left stale: herdr's agent in the pane has exited, or retire_agent renamed it there but
# could not rewrite the record.
own_pr a; reviewer review-a; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "a review-a record whose pane herdr lists no agent in" "pane w:r is one this project started"
own_pr a; reviewer review-a; printf 'conduct-e w:c\nt w:b\nreview-a-done w:r\n' > "${ROOT}/agents"; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "a review-a record whose pane herdr names review-a-done" "pane w:r is one this project started"
own_pr a; reviewer review-a; echo 'w:r t' >> "${P}/.swarm/state/e"; merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
refused "a review-a pane that another tab record names t" "pane w:r is one this project started"
# Back to fresh's board, tab records and agents.
own_pr s; rm -f "${P}/.swarm/state/r" "${P}/.swarm/agents.tsv"
printf 'w:c conduct-e\nw:b t\n' > "${P}/.swarm/state/e"; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"

# --- A story marked costs: money is the user's to merge: with merge = agent, merge holds it whoever
# calls, status lists it for the user, and the conductor's and plan-epic's briefs say so.
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "costs: money with merge = agent" "held: s costs money"
check "costs: money: s stays in review" grep -qx 'status: review' "${S}"
# The value in any case, quoted, or with a comment holds it; another value whose comment names money does not.
for v in "Money" "'money'" "money  # a CI job on real cloud" "[money]"; do
  fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: ${v}"
  merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "costs: ${v} with merge = agent" "held: s costs money"
done
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: none # no money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; is "costs: none # no money merges" 0 "${rc}"
# A block list, as Obsidian's Properties saves one, is read as its items.
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs:" "  - money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "costs: as a block list (  - money) with merge = agent" "held: s costs money"
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs:" "# why it costs" "" "  - money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "costs: as a block list with a comment and a blank line in it" "held: s costs money"
# prs: entries glued by a comma with no space are two entries.
fresh "merge = agent"; item s "status: review" "prs: [https://github.com/o/r/pull/8,${URL}]" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "a costs: money story whose prs: glues its URLs with a comma" "held: s costs money"
# A story it cannot read fails closed: whether it costs money is unknown.
fresh "merge = agent"; item a "status: ready"; chmod 000 "${P}/docs/stories/a.md"; item s "status: review" "prs: ${URL}" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "a story on the board that cannot be read" "cannot be read, so whether it costs money is unknown"
chmod 644 "${P}/docs/stories/a.md"; rm -f "${P}/docs/stories/a.md"
# A value it does not know fails closed, naming it.
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: maybe"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "costs: maybe with merge = agent" "held: s has costs: maybe, not money or none"
fresh "merge = agent"; printf 'costs: money\n' >> "${S}"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"
is "the same story without costs: (only its body says costs: money) merges" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
# Any story listing the PR holds it, whichever item is in review; an epic's costs: is ignored.
fresh "merge = agent"; rm "${S}"; item a "status: done" "prs: ${URL}" "costs: money"; mkdir -p "${P}/docs/epics"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "an epic in review listing a costs: money story's PR" "held: a costs money"
fresh "merge = agent"; rm "${S}" "${P}/docs/stories/a.md"
printf -- '---\nstatus: review\ncosts: money\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"
is "an epic's costs: money is ignored: it merges" "merge e ok|main-ci e ok|reconcile e ok (finished)" "$(events | paste -sd'|' -)"
# A stacked child's PR carries its open parent's commits: a costs: money parent holds it.
fresh "merge = agent"; item s "status: blocked" "depends_on: [p]" "prs: ${URL}"
item p "status: review" "costs: money" "prs: https://github.com/o/r/pull/8"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "a child stacked on a costs: money parent" "held: p costs money"
# status tags any review line whose PR is held, an epic's too.
(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status > "${ROOT}/out" 2>&1) || true
check "status tags an epic in review whose PR is held: awaiting your merge (costs money): epic e" said "awaiting your merge (costs money): epic e ${URL}"
rm -rf "${P}/docs/epics" "${P}/docs/stories/p.md"
# --board (or --release) is no way round it, nor another spelling of the URL.
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"; refused "--board for a costs: money story's PR" "held: s costs money"
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board https://github.com/O/R/pull/07; refused "--board for a costs: money story's PR spelt /O/R/pull/07" "held: s costs money"
# Nor a board PR that lifts a hold: one changing a costs: line, or a block-list line under one.
fresh "merge = agent"; rm "${S}"
printf 'diff --git a/docs/stories/t.md b/docs/stories/t.md\n--- a/docs/stories/t.md\n+++ b/docs/stories/t.md\n@@ -2,3 +2,3 @@\n status: review\n-costs: money\n+costs: none\n' > "${FX}/diff"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"; refused "--board whose diff changes a costs: line" "changes a costs: line in docs/stories/t.md"
fresh "merge = agent"; rm "${S}"
printf 'diff --git a/docs/stories/t.md b/docs/stories/t.md\n--- a/docs/stories/t.md\n+++ b/docs/stories/t.md\n@@ -2,4 +2,4 @@\n status: review\n costs:\n-  - money\n+  - none\n' > "${FX}/diff"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"; refused "--board whose diff changes a costs: block-list line" "changes a costs: line in docs/stories/t.md"
fresh "merge = agent"; rm "${S}"
printf 'diff --git a/docs/stories/t.md b/docs/stories/t.md\n--- a/docs/stories/t.md\n+++ b/docs/stories/t.md\n@@ -5,6 +5,6 @@ costs:\n   # two\n   # three\n   # four\n-  - money\n+  - none\n status: review\n' > "${FX}/diff"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"; refused "--board whose diff changes a block-list line past the context, named by the hunk header" "changes a costs: line in docs/stories/t.md"
fresh "merge = agent"; rm "${S}"
printf 'diff --git a/docs/stories/t.md b/docs/stories/t.md\n--- a/docs/stories/t.md\n+++ b/docs/stories/t.md\n@@ -2,6 +2,6 @@\n status: review\n costs:\n # why it costs\n \n-  - money\n+  - none\n' > "${FX}/diff"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"; refused "--board whose diff changes a block-list line below a comment and a blank line" "changes a costs: line in docs/stories/t.md"
# review's held line names a parent that costs money.
fresh "merge = agent"; item s "status: blocked" "depends_on: [p]"; item p "status: ready" "costs: money"
(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" review s "${URL}" > "${ROOT}/out" 2>&1) || true
check "review's held line says (costs money) when a parent costs money" said "held: s waits for p (costs money) to merge"
fresh "merge = agent"; item s "status: blocked" "depends_on: [p]"; item p "status: ready"; chmod 000 "${P}/docs/stories/p.md"
(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" review s "${URL}" > "${ROOT}/out" 2>&1) || true
check "review's held line says (costs money) when a parent cannot be read" said "held: s waits for p (costs money) to merge"
chmod 644 "${P}/docs/stories/p.md"; rm -f "${P}/docs/stories/p.md"
# --- With merge = human the lead merges a story or board PR only under an agreed HLD that grants
# merge, and then under merge = agent's holds; a pane this project started is refused all the same.
WAIT="waits on the user's merge (merge = human, and no HLD grants merge for it)"
fresh "merge = human"; item s "status: review" "prs: ${URL}" "costs: money"; merge "${URL}"
refused "with merge = human, the lead's swarm.sh merge of a story under no HLD" "${URL} ${WAIT}"
# hld <name> <grants> <epic> — an agreed HLD granting <grants>, and an active epic whose hld: names it,
# on the board and, at any ref, as gh reads it (merge --board's epic guard reads it at both ends).
hld() {
  mkdir -p "${P}/docs/hld" "${P}/docs/epics"
  printf -- '---\nstatus: agreed\ngrants: [%s]\n---\n\n# %s\n' "$2" "$1" > "${P}/docs/hld/$1.md"
  printf -- '---\nstatus: active\nhld: %s\n---\n\n# %s\n' "$1" "$3" > "${P}/docs/epics/$3.md"
  cp "${P}/docs/epics/$3.md" "${FX}/wf.$3.md"
}
# granted <grants> [front-matter line]... — merge = human, and s in review under epic g, under HLD h.
granted() { fresh "merge = human"; hld h "$1" g; item s "status: review" "prs: ${URL}" "epic: g" "${@:2}"; }
# no_grant_read — pr_hld never ran: merge read the PR once (its own pr view) and read no board file at
# a head (pr_hld reads each epic or story the PR touches through contents/, as grant_read shows).
no_grant_read() { [[ "$(grep -c '^pr view' "${ROOT}/gh.log")" == 1 ]] && ! grep -q '/contents/docs/' "${ROOT}/gh.log"; }
grant_read() { grep -q "repos/o/r/contents/docs/stories/s.md?ref=${H1}" "${ROOT}/gh.log"; }
granted stories; merge "${URL}"; refused "merge = human, a story PR under an HLD with no merge grant" "${URL} ${WAIT}"
granted merge; merge "${URL}"
is "merge = human, the same story PR under grants: [merge] merges" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
check "merge = human, the same story PR under grants: [merge]: the grant read s.md at the head" grant_read
granted merge; checks "${FX}/${H1}.checks" "$(run test completed failure)"; merge "${URL}"
refused "merge = human, a red head under grants: [merge]" "the head 1111111 is not green: test (failure)"
check "merge = human, a red head under grants: [merge]: no HLD read" no_grant_read
granted merge; echo '[]' > "${FX}/files.fail"; merge "${URL}"
refused "merge = human, a PR whose files cannot be listed" "cannot tell which HLD ${URL} is under, so it waits on the user's merge"
check "merge = human, a PR whose files cannot be listed: pr_hld says why" said "grants: cannot list every file ${URL} changes"
granted merge "costs: money"; merge "${URL}"; refused "merge = human, a costs: money story under grants: [merge]" "held: s costs money"
granted merge; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"; refused "merge = human, a conductor's pane under grants: [merge]" "pane w:c"
granted "merge, deploy"; merge "${URL}"; refused "merge = human, an HLD with a grant swarm.sh does not know" "hld/h.md cannot be read, so ${URL} waits on the user's merge"
check "merge = human, an HLD with a grant swarm.sh does not know: hld_grants says why" said "grants must be epics, stories, merge or release"
granted merge; printf -- '---\nstatus: agreed\ngrants:\n  - merge\n---\n\n# h\n' > "${P}/docs/hld/h.md"; merge "${URL}"
refused "merge = human, an HLD whose grants: is a block list" "hld/h.md cannot be read, so ${URL} waits on the user's merge"
check "merge = human, an HLD whose grants: is a block list: hld_grants says why" said "grants must be a one-line [..] list"
# merge's own refusals come first, before any HLD is read.
fresh "merge = human"; item s "status: ready" "prs: ${URL}"; merge "${URL}"
refused "merge = human, a story PR not in review" "s is ready, not review"
check "merge = human, a story PR not in review: no HLD read" no_grant_read
granted merge; rm "${S}"; echo '[{"filename":"docs/epics/g.md"},{"filename":"bin/swarm.sh"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge --board "${URL}"; refused "merge = human, a granted board PR with a file off the board" "changes bin/swarm.sh, outside docs/"
check "merge = human, a granted board PR with a file off the board: no HLD read" no_grant_read
# Board PRs: through the epics they touch.
granted merge; rm "${S}"; hld h2 merge g2
echo '[{"filename":"docs/epics/g.md","status":"modified"},{"filename":"docs/epics/g2.md","status":"modified"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge --board "${URL}"; refused "merge = human, a board PR touching epics under two HLDs" "${URL} ${WAIT}"
granted merge; rm "${S}"; echo '[{"filename":"docs/epics/g.md","status":"modified"}]' > "${FX}/files"; merge --board "${URL}"
is "merge = human, a board PR under one HLD granting merge merges" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
granted merge; rm "${S}"; echo '[{"filename":"docs/epics/g.md","status":"modified"}]' > "${FX}/files"
printf 'diff --git a/docs/epics/g.md b/docs/epics/g.md\n--- a/docs/epics/g.md\n+++ b/docs/epics/g.md\n@@ -2,3 +2,3 @@\n status: active\n-costs: money\n+costs: none\n' > "${FX}/diff"
merge --board "${URL}"; refused "merge = human, a board PR under grants: [merge] that changes a costs: line" \
  "changes a costs: line in docs/epics/g.md"
check "merge = human, a board PR under grants: [merge] that changes a costs: line: the whole line, with no mode in it" \
  grep -qxF "swarm: merge: held: ${URL} changes a costs: line in docs/epics/g.md; the user merges it" "${ROOT}/out"
rm -rf "${P}/docs/hld" "${P}/docs/epics"

# --- merge --board refuses a PR that sets an epic active with no ticket (epic_unticketed), under
# either merge mode. gh reads each epic and hld: HLD at the base branch (main) and at the head SHA
# from wf.<file>.<ref>; the stub keys them by basename, so no HLD shares an epic's name.
NT="active with no ticket (agreed:, parent:, hld: of an agreed HLD granting epics, or lead_epics = on); commit it as status: draft first, then run /swarm-dev:epic"
# A refusal it cannot decide still names the epic: "<why>, so whether <url> sets <epic> ${UK} <epic>".
UK="active with no ticket is unknown; commit it as status: draft first, then run /swarm-dev:epic"
# epr <epics> [config line]... — fresh with the config lines, no story s, and a board PR changing
# docs/epics/<epic>.md for each of the space-separated <epics>, in that order.
epr() {
  local e list=""
  fresh "${@:2}"; rm "${S}"
  for e in $1; do list+="${list:+,}{\"filename\":\"docs/epics/${e}.md\",\"status\":\"modified\"}"; done
  echo "[${list}]" > "${FX}/files"; wc -w <<< "$1" | tr -d ' ' > "${FX}/nfiles"
}
# fx_at <file> <ref> <front-matter line>... — <file> (a basename) as gh reads it at <ref>.
fx_at() { { echo ---; printf '%s\n' "${@:3}"; echo ---; } > "${FX}/wf.$1.$2"; }
# guarded <case> <epic> — refused naming <epic> and /swarm-dev:epic <epic>.
guarded() { refused "$1" "${URL} sets $2 ${NT} $2"; }
hld_read() { grep -qF "repos/o/r/contents/docs/hld/$1.md?ref=main" "${ROOT}/gh.log"; }
board_merged() { is "$1: exits 0" 0 "${rc}"; check "$1: merged" merged; }
epr e1; fx_at e1.md "${H1}" "status: active"; merge --board "${URL}"; guarded "--board, a new active epic with no ticket" e1
epr e1; fx_at e1.md main "status: draft"; fx_at e1.md "${H1}" "status: active"; merge --board "${URL}"
guarded "--board, a draft-to-active flip with no ticket" e1
# hld_guarded <case> <HLD> — e1 active under hld: <HLD>, absent at the base: refused, the HLD read at main.
hld_guarded() {
  fx_at e1.md "${H1}" "status: active" "hld: $2"; merge --board "${URL}"; guarded "$1" e1
  check "$1: reads the HLD at the base branch" hld_read "$2"
}
epr e1; fx_at hd.md main "status: draft" "grants: [epics]"; fx_at hd.md "${H1}" "status: agreed" "grants: [epics]"
hld_guarded "--board, hld: an HLD draft at the base, agreed at the head" hd
epr e1; fx_at hx.md main "status: agreed" "grants: [epics]"; echo 2 > "${FX}/nfiles"
echo '[{"filename":"docs/epics/e1.md","status":"modified"},{"filename":"docs/hld/hx.md","status":"removed"}]' > "${FX}/files"
hld_guarded "--board, hld: an agreed HLD the head deletes" hx
epr e1; fx_at hx.md main "status: agreed" "grants: [epics]"; fx_at hx.md "${H1}" "status: superseded" "grants: [epics]"
hld_guarded "--board, hld: an agreed HLD the head supersedes" hx
epr e1; fx_at hx.md main "status: agreed" "grants: [epics]"; fx_at hx.md "${H1}" "status: agreed" "grants: [merge]"
hld_guarded "--board, hld: an agreed HLD whose epics grant the head removes" hx
epr e1; fx_at hb.md main "status: agreed" "grants: [bogus]"; fx_at e1.md "${H1}" "status: active" "hld: hb"; merge --board "${URL}"
refused "--board, hld: an HLD with a bad grant value" "--board: docs/hld/hb.md at the base, line 3: grants must be epics, stories, merge or release, so whether ${URL} sets e1 ${UK} e1"
check "--board, hld: an HLD with a bad grant value: reads the HLD at the base branch" hld_read hb
epr "a-ok b-no"; fx_at a-ok.md "${H1}" "status: active" "agreed: 2026-01-01"; fx_at b-no.md "${H1}" "status: active"
merge --board "${URL}"; guarded "--board, a ticketed and an unticketed active epic" b-no
check "--board, a ticketed and an unticketed active epic: does not name the ticketed one" bash -c "! grep -qF a-ok '${ROOT}/out'"
epr "a-no b-ok"; fx_at a-no.md "${H1}" "status: active"; fx_at b-ok.md "${H1}" "status: active" "parent: old"; fx_at old.md main "status: active"
merge --board "${URL}"; guarded "--board, an unticketed and a ticketed active epic" a-no
check "--board, an unticketed and a ticketed active epic: does not name the ticketed one" bash -c "! grep -qF b-ok '${ROOT}/out'"
epr e1; fx_at e1.md "${H1}" "status: active"; : > "${FX}/wf.e1.md.${H1}.fail"; merge --board "${URL}"
refused "--board, a 502 on the epic's read at the head" "--board: gh cannot read docs/epics/e1.md at 1111111, so whether ${URL} sets e1 ${UK} e1"
epr e1; fx_at e1.md "${H1}" "status: active"; : > "${FX}/wf.e1.md.main"; : > "${FX}/wf.e1.md.main.fail"; merge --board "${URL}"
refused "--board, a 502 on the epic's read at the base" "--board: gh cannot read docs/epics/e1.md at main, so whether ${URL} sets e1 ${UK} e1"
epr e1; fx_at e1.md main "status: draft"; fx_at e1.md "${H1}" "status: active" "agreed: 2026-01-01"; merge --board "${URL}"
board_merged "--board, an epic set active with agreed:"
# A parent: is a ticket only when it names another epic, active or split at the base (wf.<parent>.md.main).
parent_read() { grep -qF "repos/o/r/contents/docs/epics/$1.md?ref=main" "${ROOT}/gh.log"; }
epr e1; fx_at e1.md "${H1}" "status: active" "parent: old"; fx_at old.md main "status: active"; merge --board "${URL}"
board_merged "--board, parent: an epic on main"
check "--board, parent: an epic on main: reads it at the base branch" parent_read old
epr e1; fx_at e1.md "${H1}" "status: active" "parent: bogus"; merge --board "${URL}"; guarded "--board, parent: an epic on no branch" e1
check "--board, parent: an epic on no branch: reads it at the base branch" parent_read bogus
epr "e1 kid"; fx_at e1.md "${H1}" "status: active" "parent: kid"; fx_at kid.md "${H1}" "status: draft"; merge --board "${URL}"
guarded "--board, parent: an epic the same PR adds" e1
check "--board, parent: an epic the same PR adds: reads it at the base branch" parent_read kid
epr e1; fx_at e1.md "${H1}" "status: active" "parent: old"; : > "${FX}/wf.old.md.main"; : > "${FX}/wf.old.md.main.fail"; merge --board "${URL}"
refused "--board, parent: a 502 on the parent's read at the base" "--board: gh cannot read docs/epics/old.md at main, so whether ${URL} sets e1 ${UK} e1"
epr e1; fx_at e1.md "${H1}" "status: active" "parent: dr"; fx_at dr.md main "status: draft"; merge --board "${URL}"
guarded "--board, parent: a draft epic on the base" e1
# A base status other than active, later, review, split or done needs a ticket, as a draft does.
epr e1; fx_at e1.md main "depends_on: []"; fx_at e1.md "${H1}" "status: active"; merge --board "${URL}"
guarded "--board, a base epic with no status: line set active" e1
# A 404 at the head is absent only for a path the PR removes or renames away (its file list, read
# --slurp): one it keeps there means gh cannot read the head, as for a fork's.
gone_read() { grep -qF -- "--paginate --slurp repos/o/r/pulls/7/files" "${ROOT}/gh.log"; }
epr e1; fx_at e1.md main "status: draft"; merge --board "${URL}"
refused "--board, a head 404 on an epic the PR keeps" "--board: gh cannot read docs/epics/e1.md at 1111111, so whether ${URL} sets e1 ${UK} e1"
check "--board, a head 404 on an epic the PR keeps: reads the PR's removed files" gone_read
epr e1; echo '[{"filename":"docs/epics/e1.md","status":"removed"}]' > "${FX}/files"; fx_at e1.md main "status: active"; merge --board "${URL}"
board_merged "--board, an epic the PR removes"
epr e2; echo '[{"filename":"docs/epics/e2.md","previous_filename":"docs/epics/e1.md","status":"renamed"}]' > "${FX}/files"
fx_at e2.md "${H1}" "status: draft"; fx_at e1.md main "status: draft"; merge --board "${URL}"; board_merged "--board, an epic the PR renames away"
# The guard runs after the head's CI check: a red head costs no contents read.
epr e1; fx_at e1.md "${H1}" "status: active"; checks "${FX}/${H1}.checks" "$(run test completed failure)"; merge --board "${URL}"
refused "--board, a red head that sets an epic active" "the head 1111111 is not green: test (failure)"
check "--board, a red head that sets an epic active: no contents read" bash -c "! grep -q '/contents/' '${ROOT}/gh.log'"
epr e1; fx_at hok.md main "status: agreed" "grants: [epics]"; fx_at hok.md "${H1}" "status: agreed" "grants: [epics]"
fx_at e1.md "${H1}" "status: active" "hld: hok"; merge --board "${URL}"
board_merged "--board, hld: an HLD agreed with grants: [epics] at both ends"
check "--board, hld: an HLD agreed with grants: [epics] at both ends: reads the HLD at the base branch" hld_read hok
epr e1 "lead_epics = on"; fx_at e1.md "${H1}" "status: active"; merge --board "${URL}"; board_merged "--board, lead_epics = on, with no ticket"
epr e1; fx_at e1.md main "status: later"; fx_at e1.md "${H1}" "status: active"; merge --board "${URL}"; board_merged "--board, later to active"
epr e1; fx_at e1.md main "status: active"; fx_at e1.md "${H1}" "status: active" "depends_on: []"; merge --board "${URL}"
board_merged "--board, a PR that changes no epic's status"
# Under merge = human the HLD grants merge, not epics: merge_grant lets the lead through (the active
# epic's PR merges), so the flip's refusal is the guard's own.
epr g "merge = human"; hld hm merge g; fx_at hm.md main "status: agreed" "grants: [merge]"; fx_at hm.md "${H1}" "status: agreed" "grants: [merge]"
fx_at g.md main "status: active" "hld: hm"; fx_at g.md "${H1}" "status: active" "hld: hm"; merge --board "${URL}"
board_merged "--board, merge = human, an active epic's PR under grants: [merge]"
epr g "merge = human"; fx_at hm.md main "status: agreed" "grants: [merge]"; fx_at hm.md "${H1}" "status: agreed" "grants: [merge]"
fx_at g.md main "status: draft" "hld: hm"; fx_at g.md "${H1}" "status: active" "hld: hm"; merge --board "${URL}"
guarded "--board, merge = human, a draft-to-active flip under grants: [merge]" g
check "--board, merge = human, a draft-to-active flip under grants: [merge]: reads the HLD at the base branch" hld_read hm
rm -rf "${P}/docs/hld" "${P}/docs/epics"
# Under no HLD merge_grant refuses too, but the guard runs first: its line is the one said.
epr e1 "merge = human"; fx_at e1.md main "status: draft"; fx_at e1.md "${H1}" "status: active"; merge --board "${URL}"
guarded "--board, merge = human, a draft-to-active flip under no HLD" e1
check "--board, merge = human, a draft-to-active flip under no HLD: not merge_grant's refusal" bash -c "! grep -qF 'waits on the user' '${ROOT}/out'"
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status > "${ROOT}/out" 2>&1) || true
check "status lists it as awaiting your merge (costs money) under merge = agent" said "awaiting your merge (costs money): s ${URL}"
# conduct writes the brief before it opens a workspace, which a failing herdr then refuses.
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"; touch "${ROOT}/agents.fail"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
for c in e --backlog; do
  b="${P}/.swarm/briefs/conduct-${c#--}.md"; rm -f "${b}"
  (cd "${P}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" conduct "${c}" >/dev/null 2>&1) || true
  check "the ${c#--} conductor's brief (merge = agent) names costs: money" grep -qF 'costs: money' "${b}"
  check "the ${c#--} conductor's brief (merge = agent) leaves such a PR for the user" grep -qF 'Leave the PR for the user' "${b}"
  # shellcheck disable=SC2016 # the backticks are the brief's
  check "the ${c#--} conductor's brief (merge = agent) hands such a PR over and closes its builder, as merge = human does" \
    grep -qF 'run `swarm.sh review <slug> <PR URL>` and `swarm.sh close <slug>`, never `swarm.sh merge`' "${b}"
  # shellcheck disable=SC2016 # the backticks are the brief's
  check "the ${c#--} conductor's brief (merge = agent) reports, not waits, on a strict refusal ending (costs money)" \
    grep -qF 'If the refusal ends `(costs money)`, only the user merges the named story, maybe days later: do not wait for it' "${b}"
  check "the ${c#--} conductor's brief (merge = agent) closes a held child's builder when its held line says (costs money)" \
    grep -qF 'leave its builder open, unless that line' "${b}"
  check "the ${c#--} conductor's brief (merge = agent) treats any held: refusal from merge as the user's" \
    grep -qF 'refuses any other PR with' "${b}"
done
check "the epic conductor's brief (merge = agent) never finishes the epic under a story still in review" \
  grep -qF 'Never finish the epic while a story' "${P}/.swarm/briefs/conduct-e.md"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the epic conductor's brief (merge = agent) puts such an epic in review, so reconcile finishes it after the user's merge" \
  grep -qF 'run `swarm.sh review <epic> <every PR URL still waiting>`' "${P}/.swarm/briefs/conduct-e.md"
rm -rf "${P}/docs/epics" "${ROOT}/agents.fail"
# step <from> <to> — plan-epic.md from the line holding <from> up to the one holding <to>.
step() { awk -v from="$1" -v to="$2" 'index($0, to) { on = 0 } index($0, from) { on = 1 } on' "${REPO}/commands/plan-epic.md"; }
check "plan-epic's small path names costs: money" grep -qF 'costs: money' <<< "$(step '**0. Size**' '**1. Survey**')"
check "plan-epic's decompose brief names costs: money" grep -qF 'costs: money' <<< "$(step '**2. Decompose**' '**3. Verify**')"
# shellcheck disable=SC2016 # the backticks are plan-epic's
check "plan-epic's critic brief names costs: money" grep -qF 'costs: money' <<< "$(step 'one `critic`' '**Then report**')"

finish merge-rules
