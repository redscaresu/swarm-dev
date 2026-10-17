#!/usr/bin/env bash
# outcomes_test.sh — `swarm.sh outcomes` against a fixture: a merged code story whose file the merge
# deleted (its slug longer than the 32 characters agents.tsv keeps), built twice, with findings fixed (old
# four-field rows and new ones) and one declined, counted apart; a docs story still on
# the board; a conductor and a codex agent (not builders, left out). gh is a stub on PATH. Then the same
# builds read from close's copies of their session logs once Claude Code deleted them. Then each build
# of a retried story gets its own PR: the last of the slug's PRs its own session log names. Last, each
# build gets its own start, tokens by type, tells, closes and escalation steps. TZ is UTC, so a build
# with no session log starts at a known time, except where a check sets another zone. Between them, a
# fourth project pins kind and story_merged per story.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; LONG="merged-story-whose-name-is-longer-than-32"; CUT="${LONG:0:32}"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/nobin"
git -C "${P}" init -q
printf -- '---\nkind: code\nrisk: high\nepic: e0\nstatus: ready\n---\n' > "${P}/docs/stories/${LONG}.md"
printf -- '---\nkind: docs\nstatus: ready\n---\n' > "${P}/docs/stories/docs-story.md"
git -C "${P}" add -A && git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm stories
git -C "${P}" rm -q "docs/stories/${LONG}.md" && git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm merged

session() { # <session id> <slug> <model> <input> <output> [pull URL...] — a session log: its worktree cwd
  # (timestamped TS when that is set), one message, then a tool result naming each URL (as gh pr create prints it)
  local u ts=""
  [[ -z "${TS:-}" ]] || ts=",\"timestamp\":\"${TS}\""
  printf '{"type":"user","cwd":"%s/repo-wt/%s"%s}\n' "${dir}" "$2" "${ts}"
  printf '{"cwd":"%s/repo-wt/%s","message":{"id":"m-%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s}}}\n' "${dir}" "$2" "$1" "$3" "$4" "$5"
  for u in "${@:6}"; do printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "${u}"; done
}
TS=2026-10-01T09:00:00.123Z session s1 "${LONG}" claude-opus-5-5 1000000 0 https://github.com/o/r/pull/7 > "${dir}/projects/p/s1.jsonl"
TS=2026-10-02T08:00:00Z session s2 docs-story claude-sonnet-5-5 0 1000000 https://github.com/o/r/pull/8 > "${dir}/projects/p/s2.jsonl"
TS=2026-10-04T09:00:00Z session s3 "${LONG}" claude-fable-5-1 1000000 0 https://github.com/o/r/pull/7 > "${dir}/projects/p/s3.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode-risky\t'"${CUT}"$'\tclaude\topus\txhigh\ts1' \
  $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts9' \
  $'2026-10-02\tdocs\tdocs-story\tclaude\tsonnet\tmedium\ts2' \
  $'2026-10-03\tcodex\tcodex\tcodex\tdefault\thigh\t-' \
  $'2026-10-04\tescalate\t'"${CUT}"$'\tclaude\tfable\txhigh\ts3' > "${P}/.swarm/agents.tsv"
# A tell is logged as tell:<kind>; a bare tell is from a log written before kinds, and counts as
# findings. A refused tell (its outcome is not ok) never reached the builder and is not counted. A
# close is counted whatever its cause (close:<cause>). Every line here is the first build's: the
# escalate build started after them.
printf '%s\n' \
  $'2026-10-01T10:00:00Z\ttell\t'"${LONG}"$'\tw:1\tok' \
  $'2026-10-01T11:00:00Z\ttell:findings\t'"${LONG}"$'\tw:1\tok' \
  $'2026-10-01T11:10:00Z\ttell:findings\t'"${LONG}"$'\tw:1\tswarm: x is still working' \
  $'2026-10-01T11:20:00Z\ttell:resume\t'"${LONG}"$'\tw:1\tok' \
  $'2026-10-02T09:00:00Z\ttell:nudge\tdocs-story\tw:1\tinterrupted' \
  $'2026-10-01T12:00:00Z\tclose\t'"${CUT}"$'\tw:1\tok' \
  $'2026-10-01T12:30:00Z\tclose:stalled\t'"${LONG}"$'\tw:1\tok' \
  $'2026-10-02T10:00:00Z\ttell:nudge\tdocs-story\tw:1\tok' \
  $'2026-10-02T10:00:00Z\treview\tdocs-story\tw:1\tok' \
  $'2026-10-02T10:00:00Z\ttell\tother\tw:1\tok' > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-01\tvacuous-test\to/r#7\ta' \
  $'2026-10-01\tmissing-check\thttps://github.com/o/r/pull/7\tb\tfixed' \
  $'2026-10-01\tout-of-scope\to/r#7\tdeclined, not counted\tdeclined' \
  $'2026-10-02\tvacuous-test\thttps://github.com/o/r/pull/8/files\tc' \
  $'2026-10-02\tvacuous-test\to/r#9\td' > "${P}/.swarm/findings.tsv"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\ncase "$4" in\n  story/%s) printf "https://github.com/o/r/pull/7\\tMERGED\\t2026-10-03T10:00:00Z\\n" ;;\n  story/docs-story) printf "https://github.com/o/r/pull/8\\tOPEN\\t\\n" ;;\nesac\n' "${LONG}" > "${dir}/bin/gh"
printf '#!/bin/sh\nexit 1\n' > "${dir}/nobin/gh"
chmod +x "${dir}/bin/gh" "${dir}/nobin/gh"

outcomes() { # <gh dir> [args] — the report, with that gh first on PATH
  local bin="$1"; shift
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${bin}:${PATH}" bash "${SWARM}" outcomes "$@" | sed '/^$/,$d')  # the rows, without the recurring kinds after them
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
# The first 17 columns, as they were before the rest were appended.
HEAD=$'date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells_findings\ttells_nudge\ttells_resume\tcloses\tfindings_fixed\tpr\tpr_state\tattempts'
HEAD+=$'\tstarted\ttokens_input\ttokens_cache_write\ttokens_cache_read\ttokens_output\tclose_cause\tescalate_at\tdialog_at\tdialog\tescalated_at\treset_at\tdrop_at'
HEAD+=$'\tepic\tmerged_at\tstory_merged\tfindings_declined\tfindings_fixed_by\tfindings_declined_by'
HEAD+=$'\tpr_created_at\tstart_to_pr_min\tpr_to_merge_min\tmain_merges'
E6=$'\t\t\t\t\t\t'   # six empty columns, each after its tab: the escalation steps
E4=$'\t\t\t\t'       # the four timing columns, empty: this gh stub gives no createdAt or commits
# opus 1M input = $4; sonnet 1M output = $10; fable 1M input = $10.
R1="2026-10-01	${LONG}	code	high	code-risky	opus	xhigh	4.00	1000000	2	0	1	2	2	https://github.com/o/r/pull/7	MERGED	1	2026-10-01T09:00:00Z	1000000	0	0	0	stalled${E6}	e0	2026-10-03T10:00:00Z	true	1	unknown:2	unknown:1${E4}"
R2="2026-10-02	docs-story	docs		docs	sonnet	medium	10.00	1000000	0	1	0	0	1	https://github.com/o/r/pull/8	OPEN	1	2026-10-02T08:00:00Z	0	0	0	1000000	${E6}			false	0	unknown:1	${E4}"
# The retry started after every finding on #7, so it takes none of them.
R3="2026-10-04	${LONG}	code	high	escalate	fable	xhigh	10.00	1000000	0	0	0	0	0	https://github.com/o/r/pull/7	MERGED	2	2026-10-04T09:00:00Z	1000000	0	0	0	${E6}	e0	2026-10-03T10:00:00Z	true	0		${E4}"
check "one row per builder: full slug, kind and risk (from git once deleted), cost, tells by kind (bare as findings, refused left out), closes (close:stalled among them), findings, attempts, start to the second, tokens by type" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "${R2}" "${R3}")"
check "--since leaves earlier rows out, and attempts still count them" \
  "$(outcomes "${dir}/bin" --since 2026-10-03)" "$(printf '%s\n' "${HEAD}" "${R3}")"
nopr() { awk -F'\t' -v OFS='\t' '{ $14 = $33 = 0; $15 = $16 = $31 = $32 = $34 = $35 = "" } 1' <<< "$1"; }
check "a failing gh leaves pr, pr_state, merged_at, story_merged and the findings empty, keeps epic, and still prints every row" \
  "$(outcomes "${dir}/nobin" 2>/dev/null)" "$(printf '%s\n' "${HEAD}" "$(nopr "${R1}")" "$(nopr "${R2}")" "$(nopr "${R3}")")"
if outcomes "${dir}/bin" --since yesterday >/dev/null 2>&1; then
  echo "FAIL a bad --since is refused"; fails=$((fails + 1))
else echo "ok   a bad --since is refused"; fi

# close's copy of a session log (written by archive_session, through its _archive test hook) stands in
# once Claude Code deletes the log: s3 (the long slug's newest build) and s2 (docs-story's).
run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" bash "${SWARM}" "$@"); }
snap() { (cd "${P}/.swarm" && find . | sort && find . -type f -exec cksum {} + | sort); }
run _archive "${CUT}"; run _archive docs-story
check "the live log is a sign of life" "$(run _mtime docs-story | grep -c '^[0-9][0-9]*$')" 1
TS=2026-10-02T08:00:00Z session s2 docs-story claude-sonnet-5-5 0 2000000 https://github.com/o/r/pull/8 > "${dir}/projects/p/s2.jsonl"
live() { awk -F'\t' -v OFS='\t' '{ $8 = "20.00"; $9 = 2000000; $22 = 2000000 } 1' <<< "$1"; }
check "with both the live log and close's copy, the live log wins" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "$(live "${R2}")" "${R3}")"
rm "${dir}/projects/p/s2.jsonl" "${dir}/projects/p/s3.jsonl"
before="$(snap)"
check "with only close's copy: the same long slug, started, tokens by type and cost as the live log" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "${R2}" "${R3}")"
check "close's copy is no sign of life for the stall rule" "$(run _mtime docs-story)" ""
check "reading creates no file and no events.tsv line" "$(snap)" "${before}"
rm "${P}/.swarm/sessions/"*
# With neither, cost, tokens and started are empty and the slug is agents.tsv's cut name, whose story
# is unknown. The close sent to that name is still the first build's, which started before it.
R3N="2026-10-04	${CUT}			escalate	fable	xhigh			0	0	0	0	0			1						${E6}				0		${E4}"
nolog() { awk -F'\t' -v OFS='\t' '{ $8 = $9 = $18 = $19 = $20 = $21 = $22 = "" } 1' <<< "$1"; }
check "with neither, the cells are empty, a slug with one PR keeps it, and nothing fails" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "$(nolog "${R2}")" "${R3N}")"
# A damaged copy (not gzip at all for s2, cut short for s3) reads as what it held before the damage:
# nothing here, so no usage and no cwd; every other row is intact.
echo 'not gzip' > "${P}/.swarm/sessions/2026-10-01-docs-story-s2.jsonl.gz"
session s3 "${LONG}" claude-fable-5-1 1000000 0 | gzip -c | head -c 20 > "${P}/.swarm/sessions/2026-10-01-${CUT}-s3.jsonl.gz"
zero() { awk -F'\t' -v OFS='\t' '{ $8 = "0.00"; $9 = $19 = $20 = $21 = $22 = 0; $18 = "" } 1' <<< "$1"; }
check "a damaged copy stops neither the report nor the other rows" \
  "$(outcomes "${dir}/bin" 2>&1; echo "exit $?")" "$(printf '%s\n' "${HEAD}" "${R1}" "$(zero "${R2}")" "$(zero "${R3N}")" "exit 0")"

# --- Each build's own PR, in a second project. gh answers from prs/<head with / as _>: its
# `url<TAB>state` lines, newest first as gh lists them, the first only with --limit 1. A head with a
# prs/<head>.json answers instead with that gh JSON put through the report's own --jq, by jq.
Q="${dir}/two"; U=https://github.com/o/r/pull
mkdir -p "${Q}/.swarm" "${Q}/docs/stories" "${dir}/projects/q" "${dir}/prs" "${dir}/bin2"
git -C "${Q}" init -q
for s in retried shared late foreign timed; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${Q}/docs/stories/${s}.md"; done
printf -- '---\nkind: code\nepic: e1\nstatus: ready\n---\n' > "${Q}/docs/stories/in-epic.md"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2 $3" = "pr list --head" ] || exit 1\nf="%s/prs/$(echo "$4" | tr / _)"\nif [ -f "$f.json" ]; then while [ "$1" != --jq ]; do shift; done; exec jq -r "$2" "$f.json"; fi\nn=99; case " $* " in *" --limit 1 "*) n=1 ;; esac\nhead -n "$n" "$f" 2>/dev/null\nexit 0\n' "${dir}" > "${dir}/bin2/gh"
chmod +x "${dir}/bin2/gh"
printf '%s\t%s\t%s\n' "${U}/2" MERGED 2026-10-02T12:00:00Z "${U}/1" CLOSED "" > "${dir}/prs/story_retried"
printf '%s\t%s\n' "${U}/3" OPEN > "${dir}/prs/story_shared"
printf '%s\t%s\n' "${U}/4" OPEN > "${dir}/prs/story_late"
printf '%s\t%s\n' "${U}/6" OPEN > "${dir}/prs/story_foreign"
printf '%s\t%s\n' "${U}/10" OPEN > "${dir}/prs/epic_e1"
# timed's PR: created 40 minutes after its first build started and merged 80 minutes later, with two
# commits that merge the base in, one that merges another branch, and one that merges nothing.
cat > "${dir}/prs/story_timed.json" <<JSON
[{"url": "${U}/30", "state": "MERGED", "mergedAt": "2026-10-05T12:00:00Z", "createdAt": "2026-10-05T10:40:00Z",
  "baseRefName": "main", "commits": [{"messageHeadline": "Add the timed thing"},
  {"messageHeadline": "Merge origin/main into story/timed"},
  {"messageHeadline": "Merge branch 'story/other' into story/timed"},
  {"messageHeadline": "Merge remote-tracking branch 'origin/main' into story/timed"}]}]
JSON
qs() { # <session id> <slug> <model> [pull URL...] — a session log for the second project
  local id="$1" slug="$2" model="$3"; shift 3
  session "${id}" "${slug}" "${model}" 1000000 0 "$@" > "${dir}/projects/q/${id}.jsonl"
}
# The retry's brief names the first attempt's PR before it opens its own, so the last one counts. The
# foreign build names only another head's PR; a build in the epic names a story PR it never opened.
qs r1 retried claude-opus-5-5 "${U}/1"; qs r2 retried claude-fable-5-1 "${U}/1" "${U}/2/files"
qs h1 shared claude-opus-5-5 "${U}/3"; qs h2 shared claude-opus-5-5 "${U}/3"
# A long session names its PR thousands of times; each URL reaches the report once, or the rows would
# pass the size an environment string may have (128 KiB on Linux, about 1 MiB in all on macOS).
printf '{"type":"user","message":{"content":"%s"}}\n' "$(printf "${U}/3 %.0s" $(seq 40000))" >> "${dir}/projects/q/h2.jsonl"
qs l1 late claude-opus-5-5; qs l2 late claude-fable-5-1 "${U}/4"
qs f1 foreign claude-opus-5-5 "${U}/1"
qs e1 in-epic claude-opus-5-5 "${U}/5"; qs e2 in-epic claude-fable-5-1
TS=2026-10-05T10:00:00Z qs t1 timed claude-opus-5-5 "${U}/30"; TS=2026-10-05T11:00:00Z qs t2 timed claude-fable-5-1 "${U}/30"
TS=2026-10-05T10:40:20Z qs t3 timed claude-fable-5-1 "${U}/30"
printf '%s\n' \
  $'2026-10-01\tcode\tretried\tclaude\topus\thigh\tr1' $'2026-10-02\tescalate\tretried\tclaude\tfable\txhigh\tr2' \
  $'2026-10-01\tcode\tshared\tclaude\topus\thigh\th1' $'2026-10-02\tcode\tshared\tclaude\topus\thigh\th2' \
  $'2026-10-03\tcode\tlate\tclaude\topus\thigh\tl1' $'2026-10-03\tescalate\tlate\tclaude\tfable\txhigh\tl2' \
  $'2026-10-03\tcode\tforeign\tclaude\topus\thigh\tf1' \
  $'2026-10-04\tcode\tin-epic\tclaude\topus\thigh\te1' $'2026-10-05\tescalate\tin-epic\tclaude\tfable\txhigh\te2' \
  $'2026-10-05\tcode\ttimed\tclaude\topus\thigh\tt1' $'2026-10-05\tescalate\ttimed\tclaude\tfable\txhigh\tt2' \
  $'2026-10-05\tescalate\ttimed\tclaude\tfable\txhigh\tt3' > "${Q}/.swarm/agents.tsv"
rows_of() { # <project> <slug regex> — the rows of the slugs that match, every column
  (cd "$1" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin2:${PATH}" bash "${SWARM}" outcomes | awk -F'\t' -v re="^($2)$" 'NR > 1 && $2 ~ re')
}
two() { # slug, model, pr, pr_state and attempts of each row
  (cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin2:${PATH}" bash "${SWARM}" outcomes | cut -f2,6,15-17)
}
check "each build gets the last of its slug's PRs its own log names (named 40000 times or once); none, or another head's, leaves it empty" \
  "$(two | grep -v 'in-epic\|timed')" "$(printf '%s\n' $'slug\tmodel\tpr\tpr_state\tattempts' \
    "retried	opus	${U}/1	CLOSED	1" "retried	fable	${U}/2	MERGED	2" \
    "shared	opus	${U}/3	OPEN	1" "shared	opus	${U}/3	OPEN	2" \
    "late	opus			1" "late	fable	${U}/4	OPEN	2" "foreign	opus			1")"
check "merged_at is the merged PR's alone, and story_merged is true on every row of a slug with a MERGED PR, false with none" \
  "$(rows_of "${Q}" 'retried|shared' | cut -f2,15,31,32)" "$(printf '%s\n' \
    "retried	${U}/1		true" "retried	${U}/2	2026-10-02T12:00:00Z	true" "shared	${U}/3		false" "shared	${U}/3		false")"
# Findings on the PR both builds of shared name: one row of each width, then one from before the
# second build and one from before either. Each goes to the latest build on the PR started on or
# before its day, so none is counted twice, and the one before both builds counts for neither.
printf '%s\n' \
  $'2026-10-02\tvacuous-test\to/r#3\ta' \
  $'2026-10-02\tout-of-scope\to/r#3\tb\tdeclined' \
  $'2026-10-02\tmissing-check\thttps://github.com/o/r/pull/3\tc\tfixed\tcodex' \
  $'2026-10-02\tnit\to/r#3\td\tdeclined\tcode-review' \
  $'2026-10-01\tmissing-check\to/r#3\te\tfixed\tcodex' \
  $'2026-09-30\tmissing-check\to/r#3\tf\tfixed\tcodex' > "${Q}/.swarm/findings.tsv"
check "findings fixed and declined, by reviewer (unknown for 4- and 5-field rows), each counted on one build" \
  "$(rows_of "${Q}" shared | cut -f14,33-35)" "$(printf '%s\n' $'1\t0\tcodex:1\t' $'2\t2\tcodex:1 unknown:1\tcode-review:1 unknown:1')"
rm "${Q}/.swarm/findings.tsv"
check "pr_created_at, minutes from start to PR and from PR to merge, and base merges; a retry started after its PR was created, even by 20 seconds, has no start_to_pr_min; no PR leaves all four empty" \
  "$(rows_of "${Q}" 'timed|late' | grep -v /pull/4 | cut -f2,15,18,36-39)" "$(printf '%s\n' $'late\t\t\t\t\t\t' \
    "timed	${U}/30	2026-10-05T10:00:00Z	2026-10-05T10:40:00Z	40	80	2" \
    "timed	${U}/30	2026-10-05T11:00:00Z	2026-10-05T10:40:00Z		80	2" \
    "timed	${U}/30	2026-10-05T10:40:20Z	2026-10-05T10:40:00Z		80	2")"
check "an epic story's builds take their PR from their logs too, never the epic branch's PR" \
  "$(two | grep in-epic | cut -f3 | paste -sd, -)" ","

# --- Kind and story_merged per story, in a fourth project with the same gh: an escalated story
# (kind: lead with escalated_from:, either a kind or the no-kind-line value) keeps the kind it was
# built as, and one the user holds stays lead; a slug with only a closed PR has not merged; a story
# whose repo: names no repo here is unknown.
F="${dir}/four"; mkdir -p "${F}/.swarm" "${F}/docs/stories"; git -C "${F}" init -q
printf -- '---\nkind: lead\nescalated_from: code\nstatus: ready\n---\n' > "${F}/docs/stories/esc-code.md"
printf -- '---\nkind: lead\nescalated_from: code (default)\nstatus: ready\n---\n' > "${F}/docs/stories/esc-default.md"
printf -- '---\nkind: lead\nstatus: ready\n---\n' > "${F}/docs/stories/held.md"
printf -- '---\nkind: code\nstatus: ready\n---\n' > "${F}/docs/stories/closed-only.md"
printf -- '---\nkind: code\nrepo: nowhere\nstatus: ready\n---\n' > "${F}/docs/stories/norepo.md"
printf '%s\t%s\t%s\n' "${U}/20" CLOSED "" > "${dir}/prs/story_closed-only"
printf '%s\t%s\t%s\n' "${U}/21" MERGED 2026-10-02T12:00:00Z > "${dir}/prs/story_norepo"
for s in esc-code esc-default held closed-only norepo; do printf '2026-10-01\tcode\t%s\tclaude\topus\thigh\tx-%s\n' "${s}" "${s}"; done > "${F}/.swarm/agents.tsv"
check "kind: lead with escalated_from: reports the kind it came from, without (default); a slug with only a closed PR is false; no repo is unknown" \
  "$(rows_of "${F}" '[a-z-]+' | cut -f2,3,15,31,32)" "$(printf '%s\n' \
    $'esc-code\tcode\t\t\tfalse' $'esc-default\tcode\t\t\tfalse' $'held\tlead\t\t\tfalse' \
    "closed-only	code	${U}/20		false" $'norepo\tcode\t\t\t')"

# --- Each build's own start, tokens by type, tells, closes and escalation steps, in a third project.
# A retried story; a story whose second build has no session log; a story built twice as code, then
# escalated twice: a reset ends the first cycle, whose dialog is answered late (nearer the second
# build's start than the first's), and a drop the second. Before the first, an escalate build whose
# brief was never taken up (no log, no escalate line) takes no cycle. Last, a story escalated twice whose
# first build's log is gone keeps its cycle: the second build's log started nearer the first escalate
# than midnight does, but nearer still to its own. Its slug is over 32 characters, so the log-less
# build is known only by the cut name agents.tsv keeps, while events.tsv names the full slug; a tell to
# it still goes to its own builds, not to another story's whose slug starts with the same 32. A
# reset's or drop's reason never shows, and a line whose time does not parse goes to no build.
A="${dir}/three"; LOST="lost-log-escalated-twice-with-a-slug-longer-than-32"; LCUT="${LOST:0:32}"; TWIN="${LCUT}twin"
mkdir -p "${A}/.swarm" "${dir}/projects/a"; git -C "${A}" init -q
as() { # <session id> <slug> <first timestamp> — a session log: one input, cache write, cache read and output count each
  printf '{"type":"user","cwd":"%s/repo-wt/%s","timestamp":"%s"}\n' "${dir}" "$2" "$3"
  printf '{"timestamp":"2026-10-09T00:00:00Z","message":{"id":"m-%s","model":"claude-opus-5-5","usage":{"input_tokens":1,"cache_creation_input_tokens":20,"cache_read_input_tokens":300,"output_tokens":4000}}}\n' "$1"
}
as ta1 retried 2026-10-01T10:00:00Z > "${dir}/projects/a/ta1.jsonl"; as ta2 retried 2026-10-01T14:00:00Z > "${dir}/projects/a/ta2.jsonl"
as tn1 nolog 2026-10-01T10:00:00Z > "${dir}/projects/a/tn1.jsonl"
as tc1 esc 2026-10-02T01:00:00Z > "${dir}/projects/a/tc1.jsonl"; as tc2 esc 2026-10-02T03:00:00Z > "${dir}/projects/a/tc2.jsonl"
as te1 esc 2026-10-02T10:00:00Z > "${dir}/projects/a/te1.jsonl"; as te2 esc 2026-10-02T20:00:00Z > "${dir}/projects/a/te2.jsonl"
as tl2 "${LOST}" 2026-10-04T14:00:00Z > "${dir}/projects/a/tl2.jsonl"
as tw1 "${TWIN}" 2026-10-05T10:00:00Z > "${dir}/projects/a/tw1.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode\tretried\tclaude\topus\thigh\tta1' $'2026-10-01\tcode\tretried\tclaude\topus\thigh\tta2' \
  $'2026-10-01\tcode\tnolog\tclaude\topus\thigh\ttn1' \
  $'2026-10-02\tcode\tesc\tclaude\topus\thigh\ttc1' $'2026-10-02\tcode\tesc\tclaude\topus\thigh\ttc2' \
  $'2026-10-02\tescalate\tesc\tclaude\tfable\txhigh\tte0' \
  $'2026-10-02\tescalate\tesc\tclaude\tfable\txhigh\tte1' $'2026-10-02\tescalate\tesc\tclaude\tfable\txhigh\tte2' \
  $'2026-10-03\tcode\tnolog\tclaude\topus\thigh\ttn9' \
  $'2026-10-04\tescalate\t'"${LCUT}"$'\tclaude\tfable\txhigh\ttl1' $'2026-10-04\tescalate\t'"${LCUT}"$'\tclaude\tfable\txhigh\ttl2' \
  $'2026-10-05\tcode\t'"${LCUT}"$'\tclaude\topus\thigh\ttw1' > "${A}/.swarm/agents.tsv"
# A failed drop (not ok) neither ends the first cycle nor fills drop_at. The 03:00Z nudge is before
# the log-less build's day starts in a zone five hours behind UTC.
printf '%s\n' \
  $'2026-10-01T11:00:00Z\ttell:findings\tretried\tw:1\tok' \
  $'2026-10-01T12:00:00Z\tclose:stalled\tretried\tw:1\tok' \
  $'2026-10-01T15:00:00Z\ttell:findings\tretried\tw:1\tok' \
  $'not-a-time\ttell:findings\tretried\tw:1\tok' \
  $'2026-10-02T09:59:00Z\tescalate\tesc\tw:1\tok (attempt 3)' \
  $'2026-10-02T10:01:00Z\tdialog\tesc\tw:1\tok (dismissed)' \
  $'2026-10-02T12:00:00Z\tescalated\tesc\tw:1\tok (attempts 3, 2 PRs)' \
  $'2026-10-02T17:00:00Z\tdrop\tesc\tw:1\tfailed (exit 1)' \
  $'2026-10-02T18:00:00Z\tdialog\tesc\tw:1\tok (accepted)' \
  $'2026-10-02T18:30:00Z\treset\tesc\tw:1\tok (SENTINEL-REASON)' \
  $'2026-10-02T19:59:00Z\tescalate\tesc\tw:1\tok (attempt 3)' \
  $'2026-10-02T20:01:00Z\tdialog\tesc\tw:1\tok (anything else)' \
  $'2026-10-02T21:00:00Z\tescalated\tesc\tw:1\tok (attempts 3, 2 PRs)' \
  $'not-a-time\tescalated\tesc\tw:1\tok (attempts 3, 2 PRs)' \
  $'2026-10-02T22:00:00Z\tdrop\tesc\tw:1\tok (SENTINEL-REASON)' \
  $'2026-10-03T03:00:00Z\ttell:nudge\tnolog\tw:1\tok' \
  $'2026-10-03T09:00:00Z\ttell:findings\tnolog\tw:1\tok' \
  $'2026-10-04T10:00:00Z\tescalate\t'"${LOST}"$'\tw:1\tok (attempt 2)' \
  $'2026-10-04T11:00:00Z\tescalated\t'"${LOST}"$'\tw:1\tok (attempts 2, 1 PRs)' \
  $'2026-10-04T12:00:00Z\treset\t'"${LOST}"$'\tw:1\tok (SENTINEL-REASON)' \
  $'2026-10-04T13:59:30Z\tescalate\t'"${LOST}"$'\tw:1\tok (attempt 2)' \
  $'2026-10-04T15:00:00Z\tescalated\t'"${LOST}"$'\tw:1\tok (attempts 2, 1 PRs)' \
  $'2026-10-05T11:00:00Z\ttell:findings\t'"${LOST}"$'\tw:1\tok' > "${A}/.swarm/events.tsv"
three() { (cd "${A}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/nobin:${PATH}" bash "${SWARM}" outcomes); }
out="$(three)"
check "a retried slug's tells, closes and close cause count per build, not per slug" \
  "$(awk -F'\t' '$2 == "retried"' <<< "${out}" | cut -f10,13,23)" "$(printf '%s\n' $'1\t1\tstalled' $'1\t0\t')"
check "started is each session's first timestamp, and empty with no log" \
  "$(tail -n +2 <<< "${out}" | cut -f2,18 | paste -sd' ' -)" \
  "$(printf '%s\n' "retried	2026-10-01T10:00:00Z" "retried	2026-10-01T14:00:00Z" "nolog	2026-10-01T10:00:00Z" \
    "esc	2026-10-02T01:00:00Z" "esc	2026-10-02T03:00:00Z" "esc	" "esc	2026-10-02T10:00:00Z" "esc	2026-10-02T20:00:00Z" "nolog	" "${LCUT}	" "${LOST}	2026-10-04T14:00:00Z" "${TWIN}	2026-10-05T10:00:00Z" | paste -sd' ' -)"
check "the four tokens columns are the log's per-type usage and sum to tokens" \
  "$(awk -F'\t' 'NR > 1 && $18 != ""' <<< "${out}" | cut -f9,19-22 | sort -u)" $'4321\t1\t20\t300\t4000'
check "a build with no log takes the tells logged from 00:00 UTC on its day" \
  "$(awk -F'\t' '$2 == "nolog"' <<< "${out}" | cut -f10,11 | paste -sd' ' -)" $'0\t0 1\t1'
check "and from 00:00 local time, in a zone five hours behind UTC" \
  "$(TZ=EST5 three | awk -F'\t' '$2 == "nolog"' | cut -f10,11 | paste -sd' ' -)" $'0\t1 1\t0'
check "escalation steps go to the escalate build whose cycle was open, by event order; a build that never took up its brief takes none, and one whose log is gone keeps its own, known by its cut name; the last dialog of a cycle counts, and an answer other than accepted or dismissed is empty" \
  "$(tail -n +2 <<< "${out}" | cut -f2,5,24-29)" "$(printf '%s\n' "retried	code${E6}" "retried	code${E6}" "nolog	code${E6}" \
    "esc	code${E6}" "esc	code${E6}" "esc	escalate${E6}" \
    "esc	escalate	2026-10-02T09:59:00Z	2026-10-02T18:00:00Z	accepted	2026-10-02T12:00:00Z	2026-10-02T18:30:00Z	" \
    "esc	escalate	2026-10-02T19:59:00Z	2026-10-02T20:01:00Z		2026-10-02T21:00:00Z		2026-10-02T22:00:00Z" \
    "nolog	code${E6}" \
    "${LCUT}	escalate	2026-10-04T10:00:00Z			2026-10-04T11:00:00Z	2026-10-04T12:00:00Z	" \
    "${LOST}	escalate	2026-10-04T13:59:30Z			2026-10-04T15:00:00Z		" "${TWIN}	code${E6}")"
check "a reset's or drop's reason is nowhere in the report" "$(grep -c SENTINEL-REASON <<< "${out}" || true)" 0
check "a tell to a slug over 32 characters goes to its own build, not to a story sharing its first 32" \
  "$(tail -n +2 <<< "${out}" | cut -f2,10 | grep "^${LCUT}" | paste -sd' ' -)" "${LCUT}	0 ${LOST}	1 ${TWIN}	0"
check "a line whose time does not parse goes to no build" \
  "$(grep -c not-a-time <<< "${out}" || true) $(awk -F'\t' '$2 == "retried"' <<< "${out}" | cut -f10 | paste -sd' ' -)" "0 1 1"

# verify is no longer a role policy knows, but agents.tsv keeps the verify builds made before it went:
# outcomes and flow still read them as builds, and a conductor's row is still left out.
V="${dir}/verify"; mkdir -p "${V}/.swarm"; git -C "${V}" init -q
printf '%s\n' $'2026-10-13\tverify\told-check\tclaude\thaiku\tmedium\t-' $'2026-10-13\tconduct\tconduct-e\tclaude\topus\thigh\t-' > "${V}/.swarm/agents.tsv"
vrun() { (cd "${V}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/nobin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
check "a past verify build is still a row in outcomes" "$(vrun outcomes | tail -n +2 | cut -f2,5)" $'old-check\tverify'
check "and flow counts it as a build" "$(vrun flow | tail -1 | cut -f1,2)" $'all\t1'

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
