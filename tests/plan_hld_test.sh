#!/usr/bin/env bash
# plan_hld_test.sh — pins /plan-hld's rules (commands/plan-hld.md) with a grep each, the way
# hld_command_test.sh pins /hld's: the swarm (three surveys, one hld-lead, skeptics capped at five,
# codex, critic) in tab plan-$1 writing to .swarm/$1/, the epics grant read before the ask, epics
# carrying hld: $1, the HLD's planned: and ## Epics in one board PR, and the cleanup after its merge.
# It also pins commands/swarm.md's plan-hld and hld steps, and that the HLD skeleton holds no planned:.
# Run on other copies with `bash tests/plan_hld_test.sh <plan-hld.md> <swarm.md> <hld README.md> <hld.md>`.
# shellcheck disable=SC2016 # the patterns hold literal backticks
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-$ROOT/commands/plan-hld.md}"
S="${2:-$ROOT/commands/swarm.md}"
T="${3:-$ROOT/templates/docs/hld/README.md}"
H="${4:-$ROOT/commands/hld.md}"
fails=0
# Each file with line breaks folded to spaces, so a wrapped phrase still matches.
flat=$(tr '\n' ' ' < "$F" | tr -s ' ')
swarm=$(tr '\n' ' ' < "$S" | tr -s ' ')
hld=$(tr '\n' ' ' < "$H" | tr -s ' ')
# The template's first fenced block: the skeleton /hld step 1 copies into every new HLD.
skeleton=$(awk '/^```/ { n++; next } n == 1' "$T")

has() { # <name> <pattern> [text]
  if grep -qE -- "$2" <<< "${3-$flat}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
hasnt() { # <name> <pattern> [text]
  if grep -qE -- "$2" <<< "${3-$flat}"; then echo "FAIL $1"; fails=$((fails + 1)); else echo "ok   $1"; fi
}
hasF() { # <name> <fixed string> — for a pattern full of regex characters
  if grep -qF -- "$2" <<< "$flat"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

has description '^--- description: Use when asked to plan an agreed HLD into epics\.'
has agreed-only 'Read origin.s HLD, `git show origin/<base>:<board>/hld/\$1\.md`, .* never `<wt>`.s copy, which on a resume carries the earlier run.s `planned:`\. Stop, saying why, when it is not `status: agreed`'
has planned-refused 'when its `planned:` has a value \(it was planned already; an empty one, `""` or a bare `# comment` is none'
has empty-arg 'If `\$1` is empty, list the agreed HLDs .* and ask which'
has fetch-first 'Run `git fetch origin` first: the checks below read origin.s board, and `board-pr start` makes `<wt>` from it'
has reads-origin 'Without `<wt>`, run `swarm\.sh board-pr start plan-\$1`, which makes `<wt>` from origin.s base'
has refuses-carried 'or when an epic on origin already names it: .* An epic names it when its front matter.s `hld:` is `\$1` itself, read as `next` reads it \(the lines between the file.s first two `---`; .* a body line is not read, and `parent:` is not followed\)'
has carried-origin 'git ls-tree -r --name-only origin/<base> -- .<board>/epics/. \| while read -r f; do git show "origin/<base>:\$f" \| awk'
# The loop's front-matter awk and the hld: pattern round 4 checked against slug_list, as a fixed
# string: a quoted heredoc, so nothing in it is escaped twice.
want=$(cat <<'EOF'
awk '/^---$/ && ++n == 2 { exit } n == 1' | grep -qE "^hld: *\[?[\"']?<name>[\"']?\]?[[:space:]]*(#.*)?\$" && echo "$f" done where `<name>` is `$1` with each `.` written `\.`
EOF
)
hasF carried-front-matter "$want"
has resume-hld-changed 'On a resume, stop too when origin.s HLD changed since `<wt>` was started, which `git -C <wt> diff --quiet "\$\(git -C <wt> merge-base HEAD origin/<base>\)" origin/<base> -- <board>/hld/\$1\.md` reports by failing: that run.s agents and its `grants` read the old HLD'
has resumed-wt-kept 'On a stop, remove a `<wt>` you just started with `swarm\.sh board-pr done plan-\$1`; a resumed one holds the earlier run.s work, so leave it and say so'
has three-surveys 'role `survey`, three in parallel'
has one-hld-lead 'one `hld-lead`, role `hld-lead`'
has skeptic-cap 'role `skeptic` \(capped at five'
has codex 'one `codex`, role `codex`'
has critic 'one `critic`, role `critic`'
has agent-tab 'swarm\.sh agent plan-\$1 <name> "<project>" <role>'
has agents-in-project 'start each agent in `<project>`, as `/plan-epic` does, so its one write lands inside its working directory'
has output-dir '`<project>/\.swarm/\$1/<name>\.json`'
# The grants are read before the ask: the grants line comes before the "ask before" line.
has grants-before-ask 'Before the ask, run `SWARM_PROJECT=<wt> swarm\.sh grants \$1`, which reads `<wt>`.s HLD.*ask before `board-pr open`'
has active-under-epics 'lists `epics`, the HLD lets you write the epics `status: active`'
has draft-otherwise 'Without it, write each epic `status: draft`'
has own-epics 'An epic file there that already carries `hld: \$1` is this plan.s own, from the run you resume: overwrite it'
has slug-clash 'Any other file of that slug in `docs/epics/` or `docs/stories/` would overwrite an unrelated epic or story, and a PR that changes an epic the board already has is no plan: rename that epic first'
has hld-on-epic '[Ff]ront matter `status:` as above, `hld: \$1`'
# The plan PR's exact shape, the one plan_head and epic_links (bin/lib/board.sh) put under the HLD.
has planned 'set the HLD.s front matter to one `planned: YYYY-MM-DD` line, today.s date and nothing after it'
has epics-link 'the lines under its last `## Epics` to one `- \[<slug>\]\(\.\./epics/<slug>\.md\)` per epic, the same slug in the text and the path and nothing else on the line, replacing what a run you resume wrote rather than adding to it'
has hld-top-unchanged 'Change no line of the HLD above `## Epics`, write nothing after the links, and change nothing else on the board: the PR adds its epics, each carrying `hld: \$1`, and touches no other file'
has board-pr-start 'swarm\.sh board-pr start plan-\$1'
has board-pr-open 'swarm\.sh board-pr open plan-\$1'
has codex-review 'one `swarm\.sh codex-review` pass'
has log-finding 'swarm\.sh log-finding --reviewer skeptic\|codex\|critic'
has board-pr-done 'swarm\.sh board-pr done plan-\$1'
has done-on-close 'Once it has merged, or been closed unmerged, run `swarm\.sh board-pr done plan-\$1`'
has close 'swarm\.sh close plan-\$1'
has whole-plan-in-wt 'The whole plan runs on origin.s copy of the board in the plan worktree'
has write-early 'Every brief begins: \*You are decomposing[^*]*Write your findings early to `<output>\.partial` and update it as you go, so a timed-out turn loses one item, not all, then rename it to the output file as your last step: only the output file means you finished'
has resume-partial 'A `\.partial` file is an unfinished run, not a result: start the agent, which carries on from it\.'
has stale-partial 'Delete a `\.partial` that is not newer than the same file first: it belongs to a previous plan'
has start-from-partial 'If `<output>\.partial` exists, a run was cut off: start from it and carry on, do not redo it\. Write your findings early'
has partial-is-writable 'write nothing (except|but) your output file and its `\.partial`, never commit'
has only-files-hld 'with its `\.json\.partial` the only files it may write'
has brief-reads-wt 'You are decomposing the agreed HLD `<wt>/docs/hld/\$1\.md`; read it first\. `<wt>` is origin.s copy of the project: read the code, epics and stories there, not in `<project>`, where you run'
has resume-mtime 'newer than `<wt>/\.git`'
has stop-when-open 'If the board PR `plan-\$1` is already open \(`gh pr list --head board/plan-\$1 --state open --json url --jq .\.\[\]\.url.` prints a URL\), report its URL and stop'
has resume-new-wt-origin-ref 'When `<wt>` is new, because the earlier run.s was removed, .* compare against origin.s last change to the HLD instead: `git log -1 --format=%ct origin/<base> -- <board>/hld/\$1\.md`\. An output newer than that commit.s time'
has resume-worktree 'If `<wt>` exists, run `swarm\.sh board-pr done plan-\$1` first\. .* `<wt> has uncommitted changes`, and `no PR on board/plan-\$1 has its tip \.\.\., and it has commits past origin/<base>`\. On either, resume in `<wt>`, and still run the checks below: origin can have moved since that run'
has other-refusal-stops 'On any other refusal \(a gh error, a tip that differs from origin.s, a locked worktree, the branch checked out elsewhere\), stop and report it'

has swarm-plan-hld-step '- `plan-hld <hld>`: follow `/plan-hld <hld>`' "$swarm"
has swarm-hld-step '- `hld <hld>`: .{0,120}`swarm\.sh finish <hld>`' "$swarm"
has swarm-finish-agent-merge 'Under `merge = agent`, merge the PR it opens with `swarm\.sh merge --board <url>`, as any board PR; under `merge = human`, hand it to the user: the finish PR is then the user.s, grant or not' "$swarm"
has swarm-plan-done 'Once that PR has merged or been closed, run `swarm\.sh board-pr done plan-<hld>` and `swarm\.sh close plan-<hld>`' "$swarm"
has hld-plans-next '`/swarm-dev:swarm` plans it into epics next: once its board PR has merged, or at once on a board outside the project.s repo' "$hld"
has swarm-gate-rerun 'run `/plan-hld <hld>` again: it clears the worktree of a plan PR that merged or closed, and resumes in one that stopped before `board-pr open`' "$swarm"
has swarm-finish-gate 'When the gate lists `finish PR awaiting merge: <hld>`, read the PR .* once it has merged or closed, run `swarm\.sh board-pr done finish-<hld>`' "$swarm"
has swarm-finish-done 'swarm\.sh board-pr done finish-<hld>' "$swarm"

hasnt skeleton-no-planned '^planned:' "$skeleton"
has skeleton-found '^status: draft \| agreed \| superseded$' "$skeleton"

# The carried-epic loop, run as the file holds it (its placeholders filled) over a clone whose
# origin/main has four epics: it prints the two whose front matter hld: is the HLD (bare, and quoted
# with a comment), and not the one that names it in its body nor the one with no front matter.
git init -q "${iso}/o" && git -C "${iso}/o" -c user.name=t -c user.email=t@t -c commit.gpgsign=false checkout -q -b main
mkdir -p "${iso}/o/docs/epics"
printf -- '---\nstatus: active\nhld: h\n---\n\n# a\n' > "${iso}/o/docs/epics/a.md"
printf -- '---\nstatus: active\nhld: other\n---\n\n# b\nhld: h\n' > "${iso}/o/docs/epics/b.md"
printf -- 'hld: h\n\n# c\n' > "${iso}/o/docs/epics/c.md"
printf -- '---\nstatus: active\nhld: "h" # note\n---\n\n# d\n' > "${iso}/o/docs/epics/d.md"
git -C "${iso}/o" add -A && git -C "${iso}/o" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m epics
git clone -q "${iso}/o" "${iso}/c"
sed -n '/^      git ls-tree/,/^      done$/p' "$F" | sed 's/<base>/main/g; s#<board>#docs#g; s/<name>/h/g' > "${iso}/loop.sh"
got="$(cd "${iso}/c" && bash "${iso}/loop.sh" || true)"
if [ "$got" = $'docs/epics/a.md\ndocs/epics/d.md' ]; then echo "ok   carried-loop-runs"; else echo "FAIL carried-loop-runs: got '${got//$'\n'/ }'"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ]
