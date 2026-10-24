#!/usr/bin/env bash
# grants_test.sh — swarm.sh grants: the agreed HLD over a story, epic or PR and its grants, on a
# fixture board. A story walks epic: then parent: up to an epic with hld:; a draft, superseded or
# missing HLD, a story with no epic and a parent: cycle print none; a bad grant dies with the file and
# line. A name that is no story or epic but an HLD in hld/ is that HLD (an agreed one prints itself and
# its grants, any other none); a story or epic of the same name wins; a path as the name dies with bad
# slug. gh is a stub on PATH answering a PR's files and head contents from ${FX}.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; B="${P}/docs"; FX="${ROOT}/fx"; HEAD=1111111111111111111111111111111111111111
mkdir -p "${P}/.claude/swarm" "${B}/hld" "${B}/epics" "${B}/stories" "${FX}" "${ROOT}/bin"
git -C "${P}" init -q
git -C "${P}" remote add origin https://github.com/o/r.git
fails=0

# gh: repo view names o/r (fails with ${FX}/repo-view.fail); pr view <n> answers ${FX}/pr.<n>; api
# <path> answers ${FX}/<path with / and ? as _>, else a 404. Each call is a line in ${FX}/gh.log.
printf '#!/usr/bin/env bash\nFX="%s"\n' "${FX}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${FX}/gh.log"
case "$1 $2" in
  "repo view") [ ! -e "${FX}/repo-view.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }; echo '{"nameWithOwner":"O/R"}' ;;
  "pr view") cat "${FX}/pr.$3" ;;
  *) for a in "$@"; do p="${a}"; done; p="${p//\//_}"; p="${p//\?/_}"
     if [ -e "${FX}/${p}" ]; then cat "${FX}/${p}"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

# item <file> <front-matter line>... — a board item with that front matter and a body.
item() { local f="$1" t; t="$(basename "$1" .md)"; shift; { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${t}"; } > "${f}"; }
item "${B}/hld/2026-01-01-a.md" "title: A" "status: agreed" "grants: [merge, stories]"
item "${B}/hld/2026-01-01-b.md" "title: B" "status: agreed" "grants: [release]"
item "${B}/hld/draft.md" "status: draft" "grants: [merge]"
item "${B}/hld/old.md" "status: superseded" "grants: [merge]"
item "${B}/hld/bad.md" "title: Bad" "status: agreed" "grants: [merge, deploy]"
item "${B}/hld/blk.md" "title: Block" "status: agreed" "grants:" "  - merge"
item "${B}/hld/blk2.md" "title: Block" "status: agreed" "grants:" "" "# the grants" "  - merge"
item "${B}/hld/open.md" "title: Open" "status: agreed" "grants: [merge," "  deploy]"
item "${B}/epics/top.md" "status: split" "hld: 2026-01-01-a"
item "${B}/epics/child.md" "status: active" "parent: top"
item "${B}/epics/top-b.md" "status: active" "hld: 2026-01-01-b"
item "${B}/epics/e-draft.md" "status: active" "hld: draft"
item "${B}/epics/e-old.md" "status: active" "hld: old"
item "${B}/epics/e-gone.md" "status: active" "hld: no-such-hld"
item "${B}/epics/e-bad.md" "status: active" "hld: bad"
item "${B}/epics/e-blk.md" "status: active" "hld: blk"
item "${B}/epics/e-blk2.md" "status: active" "hld: blk2"
item "${B}/epics/e-open.md" "status: active" "hld: open"
item "${B}/epics/cyc-a.md" "status: active" "parent: cyc-b"
item "${B}/epics/cyc-b.md" "status: active" "parent: cyc-a"
item "${B}/stories/s-child.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/3"
item "${B}/stories/s-hld.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/4"
item "${B}/stories/s-cross.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/12"
item "${B}/stories/s-draft.md" "status: ready" "epic: e-draft"
item "${B}/stories/s-old.md" "status: ready" "epic: e-old"
item "${B}/stories/s-gone.md" "status: ready" "epic: e-gone"
item "${B}/stories/s-orphan.md" "status: ready" "epic: no-such-epic"
item "${B}/stories/s-cyc.md" "status: ready" "epic: cyc-a"
item "${B}/stories/s-bad.md" "status: ready" "epic: e-bad"
item "${B}/stories/s-blk.md" "status: ready" "epic: e-blk"
item "${B}/stories/s-blk2.md" "status: ready" "epic: e-blk2"
item "${B}/stories/s-open.md" "status: ready" "epic: e-open"
item "${B}/stories/s-cfg.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/15"
# No epic: in the front matter; a body line naming one is not read.
item "${B}/stories/s-none.md" "status: ready"
echo "epic: child" >> "${B}/stories/s-none.md"

# grants <arg> — swarm.sh grants in the project, its output (stdout and stderr) in ${ROOT}/out
# (a walk that loops is ended by make test's per-file timeout).
grants() {
  rc=0
  (cd "${PROJ:-${P}}" && env -u SWARM_PROJECT -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" \
    bash "${SWARM}" grants "$1" > "${ROOT}/out" 2>&1) || rc=$?
}
expect() { # <name> <arg> <expected output>
  grants "$2"
  if [[ ${rc} -eq 0 && "$(cat "${ROOT}/out")" == "$3" ]]; then echo "ok   $1"
  else echo "FAIL $1 (exit ${rc}):"; sed 's/^/     /' "${ROOT}/out"; fails=$((fails + 1)); fi
}

A="${B}/hld/2026-01-01-a.md"
expect child-epic-parent-hld s-child "$(printf '%s\nmerge\nstories' "${A}")"
expect epic-itself child "$(printf '%s\nmerge\nstories' "${A}")"
expect draft-hld-none s-draft none
expect superseded-hld-none s-old none
expect missing-hld-file-none s-gone none
expect missing-epic-none s-orphan none
expect no-epic-none s-none none
expect parent-cycle-ends s-cyc none
# An HLD named directly: an agreed one prints itself and its grants, none for no grants, a draft or
# superseded one prints none, a bad grant dies with its file and line, and a story or epic of the
# same name wins.
item "${B}/hld/2026-01-01-c.md" "title: C" "status: agreed"
item "${B}/hld/clash.md" "title: Clash" "status: agreed" "grants: [release]"
item "${B}/stories/clash.md" "status: ready" "epic: child"
expect hld-arg-agreed 2026-01-01-a "$(printf '%s\nmerge\nstories' "${A}")"
expect hld-arg-no-grants-none 2026-01-01-c "$(printf '%s\nnone' "${B}/hld/2026-01-01-c.md")"
expect hld-arg-draft-none draft none
expect hld-arg-superseded-none old none
item "${B}/hld/2026-01-01-d.md" "title: D" "status: agreed" "grants: [epics, merge]"
expect hld-arg-epics-and-merge 2026-01-01-d "$(printf '%s\nepics\nmerge' "${B}/hld/2026-01-01-d.md")"
item "${B}/hld/clash-e.md" "title: Clash E" "status: agreed" "grants: [release]"
item "${B}/epics/clash-e.md" "status: active" "parent: top"
expect hld-arg-and-epic-same-name-epic-wins clash-e "$(printf '%s\nmerge\nstories' "${A}")"
expect hld-arg-and-story-same-name-story-wins clash "$(printf '%s\nmerge\nstories' "${A}")"
grants bad
if [[ ${rc} -ne 0 ]] && grep -qF "${B}/hld/bad.md:4: grants must be epics, stories, merge or release" "${ROOT}/out"; then
  echo "ok   hld-arg-bad-grant-dies-with-file-and-line"
else echo "FAIL hld-arg-bad-grant-dies-with-file-and-line (exit ${rc}):"; sed 's/^/     /' "${ROOT}/out"; fails=$((fails + 1)); fi
grants ../epics/x
if [[ ${rc} -ne 0 ]] && grep -qF "bad slug" "${ROOT}/out"; then echo "ok   path-arg-dies-bad-slug"
else echo "FAIL path-arg-dies-bad-slug (exit ${rc}):"; sed 's/^/     /' "${ROOT}/out"; fails=$((fails + 1)); fi

# story PRs: #3 changes code; #4 changes an HLD too, so it is under none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":1}" > "${FX}/pr.3"
echo '[{"filename":"bin/x.sh"}]' > "${FX}/repos_o_r_pulls_3_files_per_page=100"
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.4"
echo '[{"filename":"bin/x.sh"},{"filename":"docs/hld/2026-01-01-a.md"}]' > "${FX}/repos_o_r_pulls_4_files_per_page=100"
expect story-pr https://github.com/o/r/pull/03 "$(printf '%s\nmerge\nstories' "${A}")"
expect story-pr-touching-hld-none https://github.com/o/r/pull/4 none
expect story-pr-host-case-touching-hld-none https://GitHub.com/O/r/pull/4 none
expect story-pr-host-case https://GitHub.com/O/r/pull/3 "$(printf '%s\nmerge\nstories' "${A}")"
# pr_stories reads it as #4, but its files cannot be listed by that spelling: none.
expect story-pr-odd-spelling-none 'https://github.com/o/r/pull/4,' none

grants s-bad
if [[ ${rc} -ne 0 ]] && grep -qF "${B}/hld/bad.md:4: grants must be epics, stories, merge or release" "${ROOT}/out"; then
  echo "ok   bad-grant-dies-with-file-and-line"
else echo "FAIL bad-grant-dies-with-file-and-line (exit ${rc}):"; sed 's/^/     /' "${ROOT}/out"; fails=$((fails + 1)); fi

# dies <name> <slug> <hld> — swarm.sh grants <slug> fails, naming line 4 of <hld> as no one-line list.
dies() {
  grants "$2"
  if [[ ${rc} -ne 0 ]] && grep -qF "${B}/hld/$3:4: grants must be a one-line [..] list" "${ROOT}/out"; then echo "ok   $1"
  else echo "FAIL $1 (exit ${rc}):"; sed 's/^/     /' "${ROOT}/out"; fails=$((fails + 1)); fi
}
dies block-list-grants-dies-with-file-and-line s-blk blk.md
dies block-list-after-blank-and-comment-dies s-blk2 blk2.md
dies open-bracket-grants-dies s-open open.md

# board PR #7 touches epics under two HLDs: none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.7"
echo '[{"filename":"docs/epics/child.md"},{"filename":"docs/epics/top-b.md"}]' > "${FX}/repos_o_r_pulls_7_files_per_page=100"
cp "${B}/epics/child.md" "${FX}/repos_o_r_contents_docs_epics_child.md_ref=${HEAD}"
cp "${B}/epics/top-b.md" "${FX}/repos_o_r_contents_docs_epics_top-b.md_ref=${HEAD}"
expect board-pr-two-hlds-none https://github.com/o/r/pull/7 none

# board PR #8 adds a story under a new child epic and deletes s-child (read at the base): all under A.
echo '[{"filename":"docs/epics/grandchild.md"},{"filename":"docs/stories/new.md"},{"filename":"docs/stories/s-child.md"}]' > "${FX}/repos_o_r_pulls_8_files_per_page=100"
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":3}" > "${FX}/pr.8"
item "${FX}/repos_o_r_contents_docs_epics_grandchild.md_ref=${HEAD}" "status: active" "parent: child"
item "${FX}/repos_o_r_contents_docs_stories_new.md_ref=${HEAD}" "status: ready" "epic: grandchild"
expect board-pr-one-hld https://github.com/o/r/pull/8 "$(printf '%s\nmerge\nstories' "${A}")"

# board PR #9 moves child under top-b at its head: the board's child and the head's differ, so none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":1}" > "${FX}/pr.9"
echo '[{"filename":"docs/epics/child.md"}]' > "${FX}/repos_o_r_pulls_9_files_per_page=100"
item "${FX}/repos_o_r_contents_docs_epics_child.md_ref=${HEAD}" "status: active" "parent: top-b"
expect board-pr-rehomed-none https://github.com/o/r/pull/9 none

# board PR #10 touches an HLD: none, though its story is under A.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.10"
echo '[{"filename":"docs/hld/2026-01-01-a.md"},{"filename":"docs/stories/s-child.md"}]' > "${FX}/repos_o_r_pulls_10_files_per_page=100"
expect board-pr-touching-hld-none https://github.com/o/r/pull/10 none

# board PR #11 changes epics/child.md outside the board (docs/): none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":1}" > "${FX}/pr.11"
echo '[{"filename":"epics/child.md"}]' > "${FX}/repos_o_r_pulls_11_files_per_page=100"
expect board-pr-outside-board-none https://github.com/o/r/pull/11 none

# story PR #12 (s-cross, under A) also changes top-b, an epic under B: none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.12"
echo '[{"filename":"bin/x.sh"},{"filename":"docs/epics/top-b.md"}]' > "${FX}/repos_o_r_pulls_12_files_per_page=100"
expect story-pr-touching-other-hld-none https://github.com/o/r/pull/12 none

# With no origin, or no nameWithOwner for it, story PR #3's files cannot be checked: none.
git -C "${P}" remote remove origin
expect no-origin-none https://github.com/o/r/pull/3 none
git -C "${P}" remote add origin https://github.com/o/r.git
: > "${FX}/repo-view.fail"
expect no-repo-name-none https://github.com/o/r/pull/3 none
rm "${FX}/repo-view.fail"

# board PR #13 adds we#ird.md under child and deletes s-child: the # is read as itself, so both are A.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.13"
echo '[{"filename":"docs/stories/we#ird.md"},{"filename":"docs/stories/s-child.md"}]' > "${FX}/repos_o_r_pulls_13_files_per_page=100"
item "${FX}/repos_o_r_contents_docs_stories_we%23ird.md_ref=${HEAD}" "status: ready" "epic: child"
expect board-pr-odd-name https://github.com/o/r/pull/13 "$(printf '%s\nmerge\nstories' "${A}")"

# board PR #14 touches ghost.md, on neither the board nor the head, beside s-child (A): none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.14"
echo '[{"filename":"docs/stories/ghost.md"},{"filename":"docs/stories/s-child.md"}]' > "${FX}/repos_o_r_pulls_14_files_per_page=100"
expect board-pr-no-version-none https://github.com/o/r/pull/14 none

# story PR #15 (s-cfg, under A) also changes .claude/swarm/config: none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.15"
echo '[{"filename":"bin/x.sh"},{"filename":".claude/swarm/config"}]' > "${FX}/repos_o_r_pulls_15_files_per_page=100"
expect story-pr-touching-config-none https://github.com/o/r/pull/15 none

# board PR #16 deletes s-child (A) and changes docs/README.md, a board file that is no epic or story: none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.16"
echo '[{"filename":"docs/stories/s-child.md"},{"filename":"docs/README.md"}]' > "${FX}/repos_o_r_pulls_16_files_per_page=100"
expect board-pr-other-board-file-none https://github.com/o/r/pull/16 none

# board PR #17 changes bin/x.sh beside s-child (A): no story lists it, so none.
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.17"
echo '[{"filename":"bin/x.sh"},{"filename":"docs/stories/s-child.md"}]' > "${FX}/repos_o_r_pulls_17_files_per_page=100"
expect board-pr-code-file-none https://github.com/o/r/pull/17 none

# a PR in another repo is under none.
expect other-repo-none https://github.com/x/y/pull/7 none

# /plan-hld's board PRs, each at head h<n>. A PR that sets plan's planned: and ## Epics links and adds
# two epics with hld: plan is under plan; any other change to the HLD, a second HLD, deleting it, or an
# epic under another HLD is under none.
# hld <file> <front-matter line>... — an HLD whose ## Epics (holding ${EPICS}, then ${AFTER}) sits
# between two sections, with ${BEFORE} at the end of the first.
hld() {
  local f="$1"; shift
  { echo ---; printf '%s\n' "$@"; echo ---
    printf '\n# Plan\n\n## Design\nthe design\n%s\n## Epics\n%s\n%s## Open questions\nnone\n' "${BEFORE:-}" "${EPICS:-}" "${AFTER:-}"; } > "${f}"
}
# pr <n> <path>... — PR #<n>, at head h<n>, changes <path>s.
pr() {
  local n="$1" p l=""; shift
  for p in "$@"; do l+="${l:+,}{\"filename\":\"${p}\"}"; done
  echo "{\"headRefOid\":\"h${n}\",\"changedFiles\":$#}" > "${FX}/pr.${n}"
  echo "[${l}]" > "${FX}/repos_o_r_pulls_${n}_files_per_page=100"
}
at() { local p="$2"; echo "${FX}/repos_o_r_contents_${p//\//_}_ref=h$1"; }   # at <n> <path> — <path>'s copy at #<n>'s head
# planned <n> <hld> [hld: of the second epic] — PR #<n> plans <hld>: its planned: and ## Epics at the
# head, and epics p-one and p-two added with hld: <hld>.
planned() {
  local h="$2" g
  pr "$1" docs/epics/p-one.md docs/epics/p-two.md "docs/hld/$2.md"
  item "$(at "$1" docs/epics/p-one.md)" "status: active" "hld: ${h}"
  item "$(at "$1" docs/epics/p-two.md)" "status: active" "hld: ${3:-${h}}"
  g="$(get "${B}/hld/$2.md" grants)"
  EPICS=$'- [p-one](../epics/p-one.md)\n- [p-two](../epics/p-two.md)\n' \
    hld "$(at "$1" "docs/hld/$2.md")" "title: Plan" "status: $(get "${B}/hld/$2.md" status)" "planned: 2026-10-24" ${g:+"grants: ${g}"}
}
get() { sed -n "s/^$2: //p" "$1" | head -1; }   # get <file> <key> — its first <key>: value
hld "${B}/hld/plan.md" "title: Plan" "status: agreed" "grants: [merge]"
hld "${B}/hld/plan-nm.md" "title: Plan" "status: agreed"
hld "${B}/hld/plan-draft.md" "title: Plan" "status: draft" "grants: [merge]"

# Both grant outputs: under merge = human the plan PR merges with grants: [merge] and waits without it.
planned 30 plan; planned 31 plan-nm
grants https://github.com/o/r/pull/30; a="$(cat "${ROOT}/out")"; r30=${rc}
grants https://github.com/o/r/pull/31; b="$(cat "${ROOT}/out")"
if [[ ${r30} -eq 0 && ${rc} -eq 0 && "${a}" == "$(printf '%s\nmerge' "${B}/hld/plan.md")" && "${b}" == "$(printf '%s\nnone' "${B}/hld/plan-nm.md")" ]]; then
  echo "ok   plan-pr-merge-grant-or-none"
else echo "FAIL plan-pr-merge-grant-or-none (exit ${r30}, ${rc}):"; printf '%s\n%s\n' "${a}" "${b}" | sed 's/^/     /'; fails=$((fails + 1)); fi
planned 32 plan-draft
expect plan-pr-draft-hld-none https://github.com/o/r/pull/32 none
# The draft HLD alone, its epics untouched: none.
pr 33 docs/hld/plan-draft.md; cp "$(at 32 docs/hld/plan-draft.md)" "$(at 33 docs/hld/plan-draft.md)"
expect plan-pr-draft-hld-only-none https://github.com/o/r/pull/33 none
planned 34 plan; sed -i.bak 's/^status: agreed$/status: superseded/' "$(at 34 docs/hld/plan.md)"
expect plan-pr-status-change-none https://github.com/o/r/pull/34 none
planned 35 plan; sed -i.bak 's/^grants: \[merge\]$/grants: [merge, release]/' "$(at 35 docs/hld/plan.md)"
expect plan-pr-grants-change-none https://github.com/o/r/pull/35 none
planned 36 plan; sed -i.bak 's/^the design$/another design/' "$(at 36 docs/hld/plan.md)"
expect plan-pr-body-line-outside-epics-none https://github.com/o/r/pull/36 none
# plan and plan-nm, each changed as a plan PR would.
planned 37 plan; planned 99 plan-nm; cp "$(at 99 docs/hld/plan-nm.md)" "$(at 37 docs/hld/plan-nm.md)"
pr 37 docs/epics/p-one.md docs/epics/p-two.md docs/hld/plan-nm.md docs/hld/plan.md
expect plan-pr-second-hld-none https://github.com/o/r/pull/37 none
planned 38 plan; rm "$(at 38 docs/hld/plan.md)"
expect plan-pr-deleting-hld-none https://github.com/o/r/pull/38 none
planned 39 plan 2026-01-01-b
expect plan-pr-epic-under-other-hld-none https://github.com/o/r/pull/39 none
# A # heading ends ## Epics too: a changed line under the # Appendix that follows it is none.
AFTER=$'# Appendix\nthe appendix\n' hld "${B}/hld/plan-app.md" "title: Plan" "status: agreed" "grants: [merge]"
AFTER=$'# Appendix\nthe appendix\n' planned 40 plan-app; sed -i.bak 's/^the appendix$/a new appendix/' "$(at 40 docs/hld/plan-app.md)"
expect plan-pr-line-under-higher-heading-none https://github.com/o/r/pull/40 none
# A ## Epics line in a code fence is no heading: an HLD with a fence is none, so a changed line after
# the fenced ## Epics is not let through.
BEFORE=$'```\n## Epics\nfenced line\n```\n' hld "${B}/hld/plan-fence.md" "title: Plan" "status: agreed" "grants: [merge]"
BEFORE=$'```\n## Epics\nfenced line\n```\n' planned 41 plan-fence; sed -i.bak 's/^fenced line$/a new fenced line/' "$(at 41 docs/hld/plan-fence.md)"
expect plan-pr-fenced-epics-line-none https://github.com/o/r/pull/41 none
# planned: and ## Epics set on agreed plan with no epic beside them: none.
planned 42 plan; pr 42 docs/hld/plan.md
expect plan-pr-agreed-hld-only-none https://github.com/o/r/pull/42 none
# A story PR under A (s-hld43) that touches A's file and code, its head unread: none.
item "${B}/stories/s-hld43.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/43"
pr 43 bin/x.sh docs/hld/2026-01-01-a.md; echo '{"headRefOid":"","changedFiles":2}' > "${FX}/pr.43"
expect story-pr-touching-hld-no-head-none https://github.com/o/r/pull/43 none
# The plan PR also adds a story under p-one: none.
planned 44 plan; pr 44 docs/epics/p-one.md docs/epics/p-two.md docs/hld/plan.md docs/stories/p-story.md
item "$(at 44 docs/stories/p-story.md)" "status: ready" "epic: p-one"
expect plan-pr-with-story-none https://github.com/o/r/pull/44 none
# s-p45 (under plan, through p-board) lists a plan PR that also changes epics/stray.md outside the board: none.
item "${B}/epics/p-board.md" "status: active" "hld: plan"
item "${B}/stories/s-p45.md" "status: review" "epic: p-board" "prs: https://github.com/o/r/pull/45"
planned 45 plan; pr 45 docs/epics/p-one.md docs/hld/plan.md epics/stray.md
expect plan-pr-with-file-outside-board-none https://github.com/o/r/pull/45 none
# The plan PR moves top-b, an epic under B on the board, to hld: plan: none.
planned 46 plan; pr 46 docs/epics/top-b.md docs/hld/plan.md
item "$(at 46 docs/epics/top-b.md)" "status: active" "hld: plan"
expect plan-pr-rehoming-epic-none https://github.com/o/r/pull/46 none
# unread <name> <pr> — swarm.sh grants <pr> prints none and reads no file at the PR's head.
unread() {
  : > "${FX}/gh.log"; grants "$2"
  if [[ ${rc} -eq 0 && "$(cat "${ROOT}/out")" == none ]] && ! grep -q /contents/ "${FX}/gh.log"; then echo "ok   $1"
  else echo "FAIL $1 (exit ${rc}):"; sed 's/^/     /' "${ROOT}/out" "${FX}/gh.log"; fails=$((fails + 1)); fi
}
# The finish PR deletes plan; #4 touches A's file and code; #32 plans a draft HLD.
pr 48 docs/hld/plan.md
unread finish-pr-none-head-unread https://github.com/o/r/pull/48
unread story-pr-touching-hld-head-unread https://github.com/o/r/pull/4
unread plan-pr-draft-hld-head-unread https://github.com/o/r/pull/32

# A board at the repo's root (board_dir = .): its hld/, epics/ and stories/ are the PR's paths as they are.
R="${ROOT}/rootproj"; mkdir -p "${R}/.claude/swarm" "${R}/hld" "${R}/epics" "${R}/stories"
git -C "${R}" init -q; git -C "${R}" remote add origin https://github.com/o/r.git
echo "board_dir = ." > "${R}/.claude/swarm/config"
cp "${A}" "${R}/hld/"; cp "${B}/epics/top.md" "${B}/epics/child.md" "${R}/epics/"
item "${R}/stories/r-story.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/21"
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.21"
echo '[{"filename":"bin/x.sh"},{"filename":"hld/2026-01-01-a.md"}]' > "${FX}/repos_o_r_pulls_21_files_per_page=100"
PROJ="${R}" expect root-board-story-pr-touching-hld-none https://github.com/o/r/pull/21 none
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":1}" > "${FX}/pr.22"
echo '[{"filename":"stories/r-new.md"}]' > "${FX}/repos_o_r_pulls_22_files_per_page=100"
item "${FX}/repos_o_r_contents_stories_r-new.md_ref=${HEAD}" "status: ready" "epic: child"
PROJ="${R}" expect root-board-board-pr https://github.com/o/r/pull/22 "$(printf '%s\nmerge\nstories' "${R}/hld/2026-01-01-a.md")"
# A plan PR on the root board: hld/plan.md (as #30 changes it) and epics/p-one.md under it.
cp "${B}/hld/plan.md" "${R}/hld/"; pr 47 epics/p-one.md hld/plan.md
item "$(at 47 epics/p-one.md)" "status: active" "hld: plan"; cp "$(at 30 docs/hld/plan.md)" "$(at 47 hld/plan.md)"
PROJ="${R}" expect root-board-plan-pr https://github.com/o/r/pull/47 "$(printf '%s\nmerge' "${R}/hld/plan.md")"

# A board outside the repo: story PR #18 changes .claude/swarm/brief.md, so none; #19 changes code only.
O="${ROOT}/outproj"; OB="${ROOT}/outboard"; mkdir -p "${O}/.claude/swarm" "${OB}/hld" "${OB}/epics" "${OB}/stories"
git -C "${O}" init -q; git -C "${O}" remote add origin https://github.com/o/r.git
echo "board_dir = ${OB}" > "${O}/.claude/swarm/config"
cp "${A}" "${OB}/hld/"; cp "${B}/epics/top.md" "${B}/epics/child.md" "${OB}/epics/"
item "${OB}/stories/o-brief.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/18"
item "${OB}/stories/o-code.md" "status: review" "epic: child" "prs: https://github.com/o/r/pull/19"
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":2}" > "${FX}/pr.18"
echo '[{"filename":"bin/x.sh"},{"filename":".claude/swarm/brief.md"}]' > "${FX}/repos_o_r_pulls_18_files_per_page=100"
echo "{\"headRefOid\":\"${HEAD}\",\"changedFiles\":1}" > "${FX}/pr.19"
echo '[{"filename":"bin/x.sh"}]' > "${FX}/repos_o_r_pulls_19_files_per_page=100"
PROJ="${O}" expect outside-board-story-pr-touching-swarm-dir-none https://github.com/o/r/pull/18 none
PROJ="${O}" expect outside-board-story-pr https://github.com/o/r/pull/19 "$(printf '%s\nmerge\nstories' "${OB}/hld/2026-01-01-a.md")"

[[ ${fails} -eq 0 ]]
