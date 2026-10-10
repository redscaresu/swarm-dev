#!/usr/bin/env bash
# lessons_test.sh — the outer loop: `swarm.sh log-finding` logs fixed findings by kind, and
# `swarm.sh lessons` names a kind fixed in 3+ distinct recent PRs that the brief has no rule for, and
# a brief that has grown too long. (Whether a rule PR was declined is /swarm's check, by PR title.)
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)"
trap 'rm -rf "${dir}"' EXIT
git -C "${dir}" init -q
mkdir -p "${dir}/.claude/swarm"
: > "${dir}/.claude/swarm/config"
fails=0
sw() { (cd "${dir}" && env -u SWARM_PROJECT bash "${SWARM}" "$@" 2>&1); }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

check "a kind must be kebab-case" "yes" "$(has "must be short kebab-case" "$(sw log-finding 'Vacuous Test' o/r#1 x || true)")"
check "nothing recorded yet" "yes" "$(has "no lessons" "$(sw lessons)")"

# vacuous-test in three distinct PRs (one PR twice); denylist in two.
for pr in o/r#1 o/r#1 o/r#2 o/r#3; do sw log-finding vacuous-test "${pr}" "a test that passes with its fix removed" >/dev/null; done
for pr in o/r#4 o/r#5; do sw log-finding denylist "${pr}" "a scrub that lists what to remove" >/dev/null; done
out="$(sw lessons)"
check "a kind in 3 distinct PRs is a candidate" "yes" "$(has "candidate vacuous-test: fixed in 3 PRs" "${out}")"
check "a kind in 2 PRs is not yet" "no" "$(grep -q "candidate denylist" <<< "${out}" && echo yes || echo no)"
check "--all lists every kind with its all-time and recent PR counts" "yes|yes" \
  "$(has "vacuous-test	3 PR(s)	3 in the last 90 days" "$(sw lessons --all)")|$(has "denylist	2 PR(s)" "$(sw lessons --all)")"

# A rule in the brief, tagged with its kind, retires the candidate.
printf 'Prove each test can fail. <!-- lesson: vacuous-test -->\n' > "${dir}/.claude/swarm/brief.md"
check "a kind the brief already rules is no longer a candidate" "no" \
  "$(grep -q "candidate vacuous-test" <<< "$(sw lessons)" && echo yes || echo no)"

for pr in o/r#4 o/r#5 o/r#6; do sw log-finding denylist "${pr}" "a scrub that lists what to remove" >/dev/null; done
check "denylist is now a candidate" "yes" "$(has "candidate denylist" "$(sw lessons)")"

# A malformed date never counts as recent.
for pr in o/r#60 o/r#61 o/r#62; do printf 'soon\tbad-date\t%s\tx\n' "${pr}" >> "${dir}/.swarm/findings.tsv"; done
check "a malformed date is not counted" "no" "$(grep -q "candidate bad-date" <<< "$(sw lessons)" && echo yes || echo no)"

# A kind last fixed long ago is not news: no candidate.
for pr in o/r#20 o/r#21 o/r#22; do printf '2020-01-01\told-kind\t%s\tlong ago\n' "${pr}" >> "${dir}/.swarm/findings.tsv"; done
check "a kind not fixed recently is not a candidate" "no" "$(grep -q "candidate old-kind" <<< "$(sw lessons)" && echo yes || echo no)"

# One PR written three ways counts once.
for pr in https://github.com/O/R/pull/12 https://github.com/o/r/pull/12/files o/r#12; do sw log-finding same-pr "${pr}" "x" >/dev/null; done
check "one PR written three ways counts once" "yes" "$(has "same-pr	1 PR(s)" "$(sw lessons --all)")"

# Unquoted text is kept whole, and a carriage return cannot split a row.
sw log-finding unquoted o/r#30 several words of text >/dev/null
check "unquoted text is kept whole" "several words of text" "$(tail -1 "${dir}/.swarm/findings.tsv" | cut -f4)"
sw log-finding cr-test o/r#31 "$(printf 'a\rb\r')" >/dev/null
check "a carriage return is flattened" "0" "$(grep -c $'\r' "${dir}/.swarm/findings.tsv" || true)"
check "an unknown flag is refused" "yes" "$(has "usage: swarm.sh lessons" "$(sw lessons -a || true)")"

# A PR must be a URL or owner/repo#N; shorthand that could double-count is refused.
check "a shorthand PR is refused" "yes" "$(has "must be a PR URL or owner/repo#N" "$(sw log-finding k '#12' x || true)")"

# Only PRs inside the window count: two old fixes plus one new one is not a candidate.
for pr in o/r#40 o/r#41; do printf '2020-01-01\tmixed\t%s\told\n' "${pr}" >> "${dir}/.swarm/findings.tsv"; done
sw log-finding mixed o/r#42 "new" >/dev/null
check "old PRs do not count toward the threshold" "no" "$(grep -q "candidate mixed" <<< "$(sw lessons)" && echo yes || echo no)"

# A stray non-UTF-8 byte in the log does not break lessons.
printf '%s\tbytes\to/r#50\tbad \xff byte\n' "$(date +%F)" >> "${dir}/.swarm/findings.tsv"
check "a non-UTF-8 byte does not break lessons" "yes" "$(has "bytes	1 PR(s)" "$(sw lessons --all)")"

# A PR URL with junk after the number is refused, not counted as a different PR.
check "a malformed PR URL is refused" "yes" "$(has "must be a PR URL" "$(sw log-finding k https://github.com/o/r/pull/1x2 x || true)")"

check "a brief read from the working tree says so" "yes" "$(has "read from the working tree" "$(sw lessons)")"
check "a future-dated row is not counted" "no" "$(printf '2999-01-01\tfuture\to/r#70\tx\n2999-01-01\tfuture\to/r#71\tx\n2999-01-01\tfuture\to/r#72\tx\n' >> "${dir}/.swarm/findings.tsv"; grep -q "candidate future" <<< "$(sw lessons)" && echo yes || echo no)"
check "a basic-format date is not counted as recent" "no" "$(printf '20260101\tbasic\to/r#80\tx\n20260101\tbasic\to/r#81\tx\n20260101\tbasic\to/r#82\tx\n' >> "${dir}/.swarm/findings.tsv"; grep -q "candidate basic" <<< "$(sw lessons)" && echo yes || echo no)"
check "a blank finding is refused with the usage" "yes" "$(has "usage: swarm.sh log-finding" "$(sw log-finding k o/r#1 '   ' || true)")"
check "a whitespace-only finding is refused" "yes" "$(has "usage: swarm.sh log-finding" "$(sw log-finding k o/r#1 "$(printf '\t\n')" || true)")"
check "an overlong kind is refused" "yes" "$(has "32 characters at most" "$(sw log-finding "$(printf 'a%.0s' {1..40})" o/r#1 x || true)")"

# A lead's memory tagged `lesson: <kind>` in its frontmatter is a candidate until the brief rules it.
mem="${dir}/memory"; mkdir -p "${mem}"
printf -- '---\nname: m\nmetadata:\n  type: feedback\n  lesson: mem-kind\n---\nbody\n' > "${mem}/tagged.md"
printf -- '---\nname: u\n---\nlesson: body-kind\n' > "${mem}/untagged.md"
printf -- '---\nname: v\nlesson: vacuous-test\n---\n' > "${mem}/ruled.md"
out="$(SWARM_MEMORY_DIR="${mem}" sw lessons)"
check "a tagged memory is a candidate" "yes" "$(has "candidate mem-kind: from the lead's memory ${mem}/tagged.md" "${out}")"
check "a tag in a memory's body is ignored" "no" "$(grep -q "body-kind" <<< "${out}" && echo yes || echo no)"
check "a memory whose kind the brief rules is not a candidate" "no" "$(grep -q "ruled.md" <<< "${out}" && echo yes || echo no)"
printf -- '---\nlesson: denylist\n---\n' > "${mem}/dup.md"
check "a kind already a finding candidate is listed once" "1" "$(SWARM_MEMORY_DIR="${mem}" sw lessons | grep -c "candidate denylist")"
check "the memory dir defaults to Claude Code's per-project path" "yes" \
  "$(mkdir -p "${dir}/cp/$(cd "${dir}" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')/memory" && cp "${mem}/tagged.md" "$_/" && has "candidate mem-kind" "$(CLAUDE_PROJECTS_DIR="${dir}/cp" sw lessons)")"
check "CLAUDE_CONFIG_DIR moves the default memory dir" "yes" \
  "$(mkdir -p "${dir}/cfg/projects/$(cd "${dir}" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')/memory" && cp "${mem}/tagged.md" "$_/" && has "candidate mem-kind" "$(CLAUDE_CONFIG_DIR="${dir}/cfg" sw lessons)")"
mkdir "${mem}/dir.md"; ln -s "${dir}/nowhere" "${mem}/dangling.md"
check "an unreadable memory entry does not break the report" "yes" "$(has "candidate mem-kind" "$(SWARM_MEMORY_DIR="${mem}" sw lessons)")"
rm -rf "${mem}" "${dir}/cp" "${dir}/cfg"

# A brief over the cap is flagged.
head -c 5000 /dev/zero | tr '\0' 'x' >> "${dir}/.claude/swarm/brief.md"
check "a long brief is flagged" "yes" "$(has "long brief" "$(sw lessons)")"

# Tabs and newlines in a finding cannot break the log's columns.
sw log-finding tab-test o/r#7 "$(printf 'a\tb\nc')" >/dev/null
check "a finding's tabs and newlines are flattened" "4" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"

# Recurring: with the rule on origin/HEAD since a date, only findings after it count. The findings that
# made the kind a candidate must not flag the rule as failing the day it lands.
r="$(mktemp -d)"; G=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
"${G[@]}" init -q --bare "${r}/origin.git"; "${G[@]}" clone -q "${r}/origin.git" "${r}/p" 2>/dev/null
mkdir -p "${r}/p/.claude/swarm" "${r}/p/.swarm"; : > "${r}/p/.claude/swarm/config"
printf 'Prove it. <!-- lesson: vacuous-test -->\n' > "${r}/p/.claude/swarm/brief.md"
(cd "${r}/p" && "${G[@]}" add -A && GIT_COMMITTER_DATE="2026-01-01T00:00:00" "${G[@]}" commit -q -m rule \
  && "${G[@]}" push -q origin main && "${G[@]}" remote set-head origin -a >/dev/null)
rs() { (cd "${r}/p" && env -u SWARM_PROJECT bash "${SWARM}" "$@" 2>&1); }
for n in 1 2 3; do printf '2025-12-0%s\tvacuous-test\to/r#%s\tbefore the rule\n' "${n}" "${n}" >> "${r}/p/.swarm/findings.tsv"; done
check "findings from before the rule landed do not make it recurring" "no" "$(grep -q "recurring vacuous-test" <<< "$(rs lessons)" && echo yes || echo no)"
for n in 4 5 6; do rs log-finding vacuous-test "o/r#${n}" "after the rule" >/dev/null; done
check "findings after the rule landed make it recurring" "yes" "$(has "recurring vacuous-test: fixed in 3 PRs since its brief rule landed on 2026-01-01" "$(rs lessons)")"
# A rule since removed from the brief is never reported as failing.
printf 'nothing\n' > "${r}/p/.claude/swarm/brief.md"
(cd "${r}/p" && "${G[@]}" commit -qam prune && "${G[@]}" push -q origin main)
check "a removed rule is not reported as recurring" "no" "$(grep -q "recurring vacuous-test" <<< "$(rs lessons)" && echo yes || echo no)"
rm -rf "${r}"

# A project in a subdirectory of its repo finds its rule's adoption date (the pathspec is from the top).
r="$(mktemp -d)"
"${G[@]}" init -q --bare "${r}/origin.git"; "${G[@]}" clone -q "${r}/origin.git" "${r}/repo" 2>/dev/null
mkdir -p "${r}/repo/svc/.claude/swarm" "${r}/repo/svc/.swarm"; : > "${r}/repo/svc/.claude/swarm/config"
printf 'Prove it. <!-- lesson: sub-kind -->\n' > "${r}/repo/svc/.claude/swarm/brief.md"
(cd "${r}/repo" && "${G[@]}" add -A && GIT_COMMITTER_DATE="2026-01-01T00:00:00" "${G[@]}" commit -q -m rule \
  && "${G[@]}" push -q origin main && "${G[@]}" remote set-head origin -a >/dev/null)
for n in 1 2 3; do (cd "${r}/repo/svc" && env -u SWARM_PROJECT bash "${SWARM}" log-finding sub-kind "o/r#${n}" "after" >/dev/null); done
check "a subdirectory project finds its rule's adoption date" "yes" \
  "$(has "recurring sub-kind: fixed in 3 PRs since its brief rule landed on 2026-01-01" "$(cd "${r}/repo/svc" && env -u SWARM_PROJECT bash "${SWARM}" lessons 2>&1)")"
# Memory is keyed on the repo root, so a subdirectory project reads the root's memory.
mkdir -p "${r}/cp/$(cd "${r}/repo" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')/memory"
printf -- '---\nlesson: root-kind\n---\n' > "${r}/cp/$(cd "${r}/repo" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')/memory/m.md"
check "a subdirectory project reads the repo root's memory" "yes" \
  "$(has "candidate root-kind" "$(cd "${r}/repo/svc" && CLAUDE_PROJECTS_DIR="${r}/cp" env -u SWARM_PROJECT bash "${SWARM}" lessons 2>&1)")"
rm -rf "${r}"

# lessons_file: rules read from AGENTS.md. Only its tagged rule lines are pasted into briefs, so only
# those count toward the brief's size cap; the rest of AGENTS.md does not.
r="$(mktemp -d)"
"${G[@]}" init -q --bare "${r}/origin.git"; "${G[@]}" clone -q "${r}/origin.git" "${r}/p" 2>/dev/null
mkdir -p "${r}/p/.claude/swarm" "${r}/p/.swarm"; printf 'lessons_file = AGENTS.md\n' > "${r}/p/.claude/swarm/config"
{ printf 'Prove it. <!-- lesson: agents-kind -->\n'; head -c 5000 /dev/zero | tr '\0' 'x'; echo; } > "${r}/p/AGENTS.md"
printf 'Prove it. <!-- lesson: brief-kind -->\n' > "${r}/p/.claude/swarm/brief.md"
(cd "${r}/p" && "${G[@]}" add -A && GIT_COMMITTER_DATE="2026-01-01T00:00:00" "${G[@]}" commit -q -m rules && "${G[@]}" push -q origin main && "${G[@]}" remote set-head origin -a >/dev/null)
for k in agents-kind brief-kind; do for n in 1 2 3; do rs log-finding "${k}" "o/r#${n}" "x" >/dev/null; done; done
out="$(rs lessons)"
check "a rule in lessons_file retires its kind" "no" "$(grep -q "candidate agents-kind" <<< "${out}" && echo yes || echo no)"
check "a rule the brief still tags rules its kind too" "no" "$(grep -q "candidate brief-kind" <<< "${out}" && echo yes || echo no)"
check "config prints lessons_file as an absolute path" "yes" "$(has "$(cd "${r}/p" && pwd -P)/AGENTS.md" "$(rs config lessons_file)")"
check "lessons_file's untagged text does not count toward the cap" "no" "$(grep -q "long brief" <<< "${out}" && echo yes || echo no)"
head -c 5000 /dev/zero | tr '\0' 'y' >> "${r}/p/.claude/swarm/brief.md"
(cd "${r}/p" && "${G[@]}" commit -qam long && "${G[@]}" push -q origin main)
check "the brief is still capped when lessons_file is elsewhere" "yes" "$(has "long brief: origin/HEAD:.claude/swarm/brief.md" "$(rs lessons)")"
for n in 4 5 6; do rs log-finding brief-kind "o/r#${n}" "after the rule" >/dev/null; done
check "a rule only in the brief still gets its recurring check" "yes" "$(has "recurring brief-kind" "$(rs lessons)")"
printf 'short\n' > "${r}/p/.claude/swarm/brief.md"
for n in $(seq 40); do printf 'Rule %s %s <!-- lesson: k%s -->\n' "${n}" "$(head -c 120 /dev/zero | tr '\0' 'z')" "${n}"; done >> "${r}/p/AGENTS.md"
(cd "${r}/p" && "${G[@]}" commit -qam rules && "${G[@]}" push -q origin main)
check "lessons_file's pasted rules count toward the cap" "yes" "$(has "plus lessons_file's rules" "$(rs lessons)")"
(cd "${r}/p" && "${G[@]}" rm -q .claude/swarm/brief.md && "${G[@]}" commit -qm nobrief && "${G[@]}" push -q origin main)
check "no brief at all prints no working-tree note" "no" "$(grep -q "brief.md on origin/HEAD" <<< "$(rs lessons)" && echo yes || echo no)"
check "a lessons_file no agent reads is refused" "yes" \
  "$(printf 'lessons_file = docs/rules.md\n' > "${r}/p/.claude/swarm/config"; has "must be one every agent reads" "$(rs lessons || true)")"
rm -rf "${r}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
