#!/usr/bin/env bash
# board_pr_kinds_test.sh — board-pr open names a board PR's kind on stderr, with its stdout the URL
# alone. plan-<hld> and scope-<epic> are plan PRs and agree-<hld or epic> an agreement PR, each only
# when the name names an HLD or epic in the PR's worktree (its file name made clean); they need one
# codex-review pass. finish-<slug> and drop-<slug> (swarm.sh finish and drop), hold-<slug> and any
# other name, a story slug such as plan-hld-gaps too, are story-scope edits, holds and finishes, which
# get none. Each name runs through board-pr start and open (or finish, or drop) on a local bare
# origin, with no codex call. merge --board, which never reads the kind, is checked once: refused on
# a red head, merged on a green one, with no codex call. Then the command files: the plan and
# agreement steps keep their codex-review pass, run before board-pr open, and /epic names its
# agreement PR after the file; /swarm's board-edit paragraph and
# board_pr_merge_rule, under both merge modes, give edits, holds and finishes none.
# The gh stub is merge_fixture.sh's, behind a wrapper that answers pr create; codex is a stub that
# logs every call to codex.log.
# shellcheck disable=SC2153,SC2154,SC2016 # merge_fixture.sh sets URL, rc and the rest; the command text quotes `...` and $1
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
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# gh: pr create answers the fixture's URL; every other call is merge_fixture's stub.
mv "${ROOT}/bin/gh" "${ROOT}/bin/gh-fixture"
printf '#!/usr/bin/env bash\nLOG="%s"; URL="%s"; FIXTURE="%s"\n' "${ROOT}/gh.log" "${URL}" "${ROOT}/bin/gh-fixture" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
[ "$1 $2" != "pr create" ] || { echo "$*" >> "${LOG}"; echo "${URL}"; exit 0; }
exec "${FIXTURE}" "$@"
STUB
# codex: never the real one; any call is logged.
printf '#!/bin/sh\necho "$*" >> "%s"\n' "${ROOT}/codex.log" > "${ROOT}/bin/codex"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/codex"

# The board in docs/, committed on main and pushed to origin: the stories finish and drop take off,
# the HLDs h and 2026-10-25-Big_Plan (a file name that is not a clean slug) and the epic e.
item done-one "status: review"; item esc "status: ready" "kind: lead" "escalated_from: code"
mkdir -p "${P}/docs/hld" "${P}/docs/epics"
printf -- '---\nstatus: agreed\n---\n\n# h\n' > "${P}/docs/hld/h.md"
printf -- '---\nstatus: draft\n---\n\n# Big plan\n' > "${P}/docs/hld/2026-10-25-Big_Plan.md"
printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
printf '.swarm/\n.claude/\n' > "${P}/.gitignore"
git -C "${P}" symbolic-ref HEAD refs/heads/main; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" add -A && git -C "${P}" commit -qm init && git -C "${P}" push -q -u origin main
echo "The board edit." > "${ROOT}/body.md"

# sw <args> — swarm.sh from the main checkout, outside herdr; sets rc, stdout in sw.out, stderr in sw.err.
sw() {
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" \
    > "${ROOT}/sw.out" 2> "${ROOT}/sw.err") || rc=$?
}
# no_codex — the codex stub was not called since the case's fresh_codex.
no_codex() { [[ ! -e "${ROOT}/codex.log" ]]; }
fresh_codex() { rm -f "${ROOT}/codex.log"; }
codex_line() { echo "board-pr: $1 is a $2 PR: it needs one swarm.sh codex-review pass before it merges; skip it if you ran it"; }
none_line() { echo "board-pr: $1 is a $2 PR: no codex-review"; }

# opened <name> <kind line> [<path> <text>] — board-pr start and open under <name>, adding a story (and
# <path> with <text>): open prints the kind's line on stderr and the URL alone on stdout, and codex is
# never called.
opened() {
  local wt
  fresh_codex; sw board-pr start "$1"; is "$1: start exits 0" 0 "${rc}"
  wt="$(cat "${ROOT}/sw.out")"
  printf -- '---\nstatus: ready\n---\n\n# %s\n' "$1" > "${wt}/docs/stories/$1.md"
  [[ -z "${3:-}" ]] || printf '%b' "$4" > "${wt}/$3"
  sw board-pr open "$1" "Board edit $1" "${ROOT}/body.md"
  is "$1: open exits 0" 0 "${rc}"
  is "$1: open's stdout is the URL alone" "${URL}" "$(cat "${ROOT}/sw.out")"
  is "$1: open's stderr is the kind's line" "$2" "$(cat "${ROOT}/sw.err")"
  check "$1: no codex call" no_codex
}

# --- Plan and agreement PRs: one codex-review pass, which the line names.
opened plan-h "$(codex_line plan-h plan)"
opened scope-e "$(codex_line scope-e plan)"
opened agree-e "$(codex_line agree-e agreement)"
opened agree-2026-10-25-big-plan "$(codex_line agree-2026-10-25-big-plan agreement)"
# A new epic agreed in its own PR: /epic moves the draft into the worktree, so only the PR has it.
opened agree-new "$(codex_line agree-new agreement)" docs/epics/new.md "---\nstatus: active\nagreed: $(date +%F)\n---\n\n# new\n"
# --- A story slug that starts like a plan PR names no HLD or epic: a story-scope edit.
opened plan-hld-gaps "$(none_line plan-hld-gaps "story-scope edit")"
opened scope-creep "$(none_line scope-creep "story-scope edit")"
# --- Holds and story-scope edits: no codex-review.
opened hold-s "$(none_line hold-s hold)"
opened rescope-s "$(none_line rescope-s "story-scope edit")"
opened stage-v0-29-0 "$(none_line stage-v0-29-0 "story-scope edit")"
opened check-vacuous-test "$(none_line check-vacuous-test "story-scope edit")"

# --- Finish PRs, through swarm.sh finish and drop: the kind's line on stderr, the board PR on stdout.
fresh_codex; sw finish done-one
is "finish: exits 0" 0 "${rc}"
is "finish: stderr is the kind's line" "$(none_line finish-done-one finish)" "$(cat "${ROOT}/sw.err")"
is "finish: stdout is the board PR and its merge --board" \
  "deleted: docs/stories/done-one.md in the board PR ${URL}|land it: swarm.sh merge --board ${URL}" "$(paste -sd'|' - < "${ROOT}/sw.out")"
check "finish: no codex call" no_codex
fresh_codex; sw drop esc "no longer needed"
is "drop: exits 0" 0 "${rc}"
is "drop: stderr is the kind's line" "$(none_line drop-esc finish)" "$(cat "${ROOT}/sw.err")"
is "drop: stdout is the board PR and its merge --board" \
  "deleted: docs/stories/esc.md in the board PR ${URL}|land it: swarm.sh merge --board ${URL}|dropped: esc" "$(paste -sd'|' - < "${ROOT}/sw.out")"
check "drop: no codex call" no_codex

# --- merge --board on a board PR (rescope-s's file): refused while its head is red, merged once it is
# green, with no codex call. Once, not per kind: merge --board never reads the kind.
fresh_codex; fresh; rm "${S}"; echo '[{"filename":"docs/stories/rescope-s.md","status":"added"}]' > "${FX}/files"
checks "${FX}/${H1}.checks" "$(run test completed failure)"
merge --board "${URL}"; refused "merge --board on a red head" "is not green"
fresh; rm "${S}"; echo '[{"filename":"docs/stories/rescope-s.md","status":"added"}]' > "${FX}/files"
merge --board "${URL}"
is "merge --board on a green head exits 0" 0 "${rc}"
check "merge --board on a green head merges" merged
check "merge --board calls no codex" no_codex

# --- The command files. flat <file> — the file on one line, runs of whitespace as one space.
flat() { tr '\n' ' ' < "${REPO}/$1" | tr -s ' '; }
# step <file> <n> — step <n>. of a numbered command file, flattened, up to the next step.
step() { awk -v n="$2" '$0 ~ "^"n"\\. " { on = 1 } on && $0 ~ "^[0-9]+\\. " && $0 !~ "^"n"\\. " { exit } on' "${REPO}/$1" | tr '\n' ' ' | tr -s ' '; }
has() { grep -qF -- "$2" <<< "$1"; }
check "hld.md step 5 runs one codex-review pass, then opens agree-<name>" \
  has "$(step commands/hld.md 5)" 'run one `swarm.sh codex-review` pass there and fix what it finds, then run `swarm.sh board-pr open agree-<name> "<title>" <body-file>`, which commits with the brief'"'"'s trailers and signing'
check "epic.md step 5 runs one codex-review pass, then opens agree-<name>" \
  has "$(step commands/epic.md 5)" 'run one `swarm.sh codex-review` pass there and fix what it finds, then run `swarm.sh board-pr open agree-<name> "<title>" <body-file>`, which commits with the brief'"'"'s trailers and signing'
# epic.md step 1 names the agreement PR after the resolved file, never the title: board_pr_kind
# matches the name against the epic files, and an epic's title often differs from its file name.
named() {
  has "$(step commands/epic.md 1)" 'by argument, by slug or by title, `<slug>` is its name without `.md`, whatever the title says now' \
    && has "$(step commands/epic.md 1)" '`<name>` below is `<slug>` made clean the same way'
}
check "epic.md step 1 names agree-<name> after the file, never the title" named
# agreed <file> <what> — step 1 stops while <what>'s agreement PR is open and writes a closed one's
# draft back before board-pr done, and step 5 clears it once it merged or closed.
agreed() {
  has "$(step "commands/$1" 1)" "An open PR means the user agreed this $2 and it waits on that PR: tell them so with its URL, and stop." \
    && has "$(step "commands/$1" 1)" "A closed one: write the $2 back from the branch first, as \`status: draft\`" \
    && has "$(step "commands/$1" 5)" 'Once that PR has merged or closed, `swarm.sh board-pr done agree-<name>` removes its worktree and branch'
}
check "hld.md: step 1 stops on an open agree- PR, step 5 runs board-pr done" agreed hld.md HLD
check "epic.md: step 1 stops on an open agree- PR, step 5 runs board-pr done" agreed epic.md epic
# unread <file> — step 1 finishes step 5 from the worktree when the branch has no PR, stops when git
# or gh cannot read the agreement, and fetches the branch before the closed path reads origin's ref.
unread() {
  has "$(step "commands/$1" 1)" "No PR on the branch means step 5's \`board-pr open\` failed after the draft moved: the draft is in the worktree \`<repo>-wt/_board-agree-<name>\`, so finish step 5 from there" \
    && has "$(step "commands/$1" 1)" 'or `gh pr list` fails, stop and tell the user; do not resume co-writing.' \
    && has "$(step "commands/$1" 1)" 'run `git fetch origin board/agree-<name>`, then `git diff --name-only origin/<base>...origin/board/agree-<name>`'
}
check "hld.md: step 1 handles a branch with no PR, a failed read, and fetches the closed branch" unread hld.md
check "epic.md: step 1 handles a branch with no PR, a failed read, and fetches the closed branch" unread epic.md
check "plan-epic.md's small path runs one codex-review pass" has "$(flat commands/plan-epic.md)" 'run one `swarm.sh codex-review` pass over them in that worktree'
check "plan-epic.md's split runs one codex-review pass" has "$(flat commands/plan-epic.md)" 'Then commit (in the worktree), run one `swarm.sh codex-review` pass'
check "plan-epic.md's full path opens scope-\$1 with one codex-review pass" has "$(flat commands/plan-epic.md)" 'open the board PR `scope-$1` with one `swarm.sh codex-review` pass'
check "plan-hld.md runs one codex-review pass before board-pr open plan-\$1" \
  has "$(flat commands/plan-hld.md)" 'run one `swarm.sh codex-review` pass there, then `swarm.sh board-pr open plan-$1'
# /swarm's board-edit paragraph: its sentences that name codex-review give edits, holds and finishes none.
edits="$(awk '/^When the board is in the project.s repo, make each board edit/ { on = 1 } on && /^$/ { exit } on' "${REPO}/commands/swarm.md" | tr '\n' ' ' | tr -s ' ')"
is "swarm.md's board-edit paragraph: no codex-review for an edit, a hold or a finish" \
  'An edit, a hold (`hold-<slug>`) or a finish PR gets no `swarm.sh codex-review`: it lands on green CI alone.|Only a plan PR (`plan-<hld>`, `scope-<epic>`) or an agreement PR (`agree-<hld or epic>`) gets one codex-review pass before it merges; `board-pr open` names the PR'"'"'s kind on stderr.' \
  "$(python3 -c 'import re, sys; print("|".join(s for s in re.split(r"(?<=\.) ", sys.argv[1]) if "codex" in s))' "${edits}")"
# board_pr_merge_rule, the conductor brief's line, under both merge modes.
rule() { bash -c 'source "$1"; CFG_merge="$2"; board_pr_merge_rule' _ "${REPO}/bin/lib/build.sh" "$1"; }
is "board_pr_merge_rule with merge = agent: no codex-review, merge --board on green" \
  'Run no `swarm.sh codex-review` on it: land it with `swarm.sh merge --board <url>` once its checks are green.' "$(rule agent)"
is "board_pr_merge_rule with merge = human: no codex-review, the user lands it" \
  'Run no `swarm.sh codex-review` on it. With merge = human you cannot land that PR: list it in your report for the user.' "$(rule human)"

finish "board PR kinds"
