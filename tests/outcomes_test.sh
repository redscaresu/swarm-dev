#!/usr/bin/env bash
# outcomes_test.sh — `swarm.sh outcomes` against a fixture: a merged code story whose file the merge
# deleted (its slug longer than the 32 characters agents.tsv keeps), built twice, with findings fixed (old
# four-field rows and new ones) and one declined, which is not counted; a docs story still on
# the board; a conductor and a codex agent (not builders, left out). gh is a stub on PATH. Then the same
# builds read from close's copies of their session logs once Claude Code deleted them. Last, each build
# of a retried story gets its own PR: the last of the slug's PRs its own session log names.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; LONG="merged-story-whose-name-is-longer-than-32"; CUT="${LONG:0:32}"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/nobin"
git -C "${P}" init -q
printf -- '---\nkind: code\nrisk: high\nstatus: ready\n---\n' > "${P}/docs/stories/${LONG}.md"
printf -- '---\nkind: docs\nstatus: ready\n---\n' > "${P}/docs/stories/docs-story.md"
git -C "${P}" add -A && git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm stories
git -C "${P}" rm -q "docs/stories/${LONG}.md" && git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm merged

session() { # <session id> <slug> <model> <input> <output> [pull URL...] — a session log: its worktree cwd,
  # one message, then a tool result naming each URL (as gh pr create prints it)
  local u
  printf '{"type":"user","cwd":"%s/repo-wt/%s"}\n' "${dir}" "$2"
  printf '{"cwd":"%s/repo-wt/%s","message":{"id":"m-%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s}}}\n' "${dir}" "$2" "$1" "$3" "$4" "$5"
  for u in "${@:6}"; do printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "${u}"; done
}
session s1 "${LONG}" claude-opus-5-5 1000000 0 https://github.com/o/r/pull/7 > "${dir}/projects/p/s1.jsonl"
session s2 docs-story claude-sonnet-5-5 0 1000000 https://github.com/o/r/pull/8 > "${dir}/projects/p/s2.jsonl"
session s3 "${LONG}" claude-fable-5-1 1000000 0 https://github.com/o/r/pull/7 > "${dir}/projects/p/s3.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode-risky\t'"${CUT}"$'\tclaude\topus\txhigh\ts1' \
  $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\ts9' \
  $'2026-10-02\tdocs\tdocs-story\tclaude\tsonnet\tmedium\ts2' \
  $'2026-10-03\tcodex\tcodex\tcodex\tdefault\thigh\t-' \
  $'2026-10-04\tescalate\t'"${CUT}"$'\tclaude\tfable\txhigh\ts3' > "${P}/.swarm/agents.tsv"
# A tell is logged as tell:<kind>; a bare tell is from a log written before kinds, and counts as
# findings. A refused tell (its outcome is not ok) never reached the builder and is not counted. A
# close is counted whatever its cause (close:<cause>).
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
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\ncase "$4" in\n  story/%s) printf "https://github.com/o/r/pull/7\\tMERGED\\n" ;;\n  story/docs-story) printf "https://github.com/o/r/pull/8\\tOPEN\\n" ;;\nesac\n' "${LONG}" > "${dir}/bin/gh"
printf '#!/bin/sh\nexit 1\n' > "${dir}/nobin/gh"
chmod +x "${dir}/bin/gh" "${dir}/nobin/gh"

outcomes() { # <gh dir> [args] — the report, with that gh first on PATH
  local bin="$1"; shift
  (cd "${P}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${bin}:${PATH}" bash "${SWARM}" outcomes "$@")
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
HEAD=$'date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells_findings\ttells_nudge\ttells_resume\tcloses\tfindings_fixed\tpr\tpr_state\tattempts'
# opus 1M input = $4; sonnet 1M output = $10; fable 1M input = $10.
R1="2026-10-01	${LONG}	code	high	code-risky	opus	xhigh	4.00	1000000	2	0	1	2	2	https://github.com/o/r/pull/7	MERGED	1"
R2="2026-10-02	docs-story	docs		docs	sonnet	medium	10.00	1000000	0	1	0	0	1	https://github.com/o/r/pull/8	OPEN	1"
R3="2026-10-04	${LONG}	code	high	escalate	fable	xhigh	10.00	1000000	2	0	1	2	2	https://github.com/o/r/pull/7	MERGED	2"
check "one row per builder: full slug, kind and risk (from git once deleted), cost, tells by kind (bare as findings, refused left out), closes (close:stalled among them), findings, attempts" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "${R2}" "${R3}")"
check "--since leaves earlier rows out, and attempts still count them" \
  "$(outcomes "${dir}/bin" --since 2026-10-03)" "$(printf '%s\n' "${HEAD}" "${R3}")"
nopr() { awk -F'\t' -v OFS='\t' '{ $14 = 0; $15 = ""; $16 = "" } 1' <<< "$1"; }
check "a failing gh leaves pr and pr_state empty and still prints every row" \
  "$(outcomes "${dir}/nobin" 2>/dev/null)" "$(printf '%s\n' "${HEAD}" "$(nopr "${R1}")" "$(nopr "${R2}")" "$(nopr "${R3}")")"
if outcomes "${dir}/bin" --since yesterday >/dev/null 2>&1; then
  echo "FAIL a bad --since is refused"; fails=$((fails + 1))
else echo "ok   a bad --since is refused"; fi

# close's copy of a session log (written by archive_session, through its _archive test hook) stands in
# once Claude Code deletes the log: s3 (the long slug's newest build) and s2 (docs-story's).
run() { (cd "${P}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" bash "${SWARM}" "$@"); }
snap() { (cd "${P}/.swarm" && find . | sort && find . -type f -exec cksum {} + | sort); }
run _archive "${CUT}"; run _archive docs-story
check "the live log is a sign of life" "$(run _mtime docs-story | grep -c '^[0-9][0-9]*$')" 1
session s2 docs-story claude-sonnet-5-5 0 2000000 https://github.com/o/r/pull/8 > "${dir}/projects/p/s2.jsonl"
live() { awk -F'\t' -v OFS='\t' '{ $8 = "20.00"; $9 = 2000000 } 1' <<< "$1"; }
check "with both the live log and close's copy, the live log wins" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "$(live "${R2}")" "${R3}")"
rm "${dir}/projects/p/s2.jsonl" "${dir}/projects/p/s3.jsonl"
before="$(snap)"
check "with only close's copy: the same long slug, tokens and cost as the live log" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "${R2}" "${R3}")"
check "close's copy is no sign of life for the stall rule" "$(run _mtime docs-story)" ""
check "reading creates no file and no events.tsv line" "$(snap)" "${before}"
rm "${P}/.swarm/sessions/"*
# With neither, cost and tokens are empty and the slug is agents.tsv's cut name, whose story is unknown.
R3N="2026-10-04	${CUT}			escalate	fable	xhigh			0	0	0	1	0			1"
check "with neither, the cells are empty, a slug with one PR keeps it, and nothing fails" \
  "$(outcomes "${dir}/bin")" "$(printf '%s\n' "${HEAD}" "${R1}" "$(awk -F'\t' -v OFS='\t' '{ $8 = ""; $9 = "" } 1' <<< "${R2}")" "${R3N}")"
# A damaged copy (not gzip at all for s2, cut short for s3) reads as what it held before the damage:
# nothing here, so no usage and no cwd; every other row is intact.
echo 'not gzip' > "${P}/.swarm/sessions/2026-10-01-docs-story-s2.jsonl.gz"
session s3 "${LONG}" claude-fable-5-1 1000000 0 | gzip -c | head -c 20 > "${P}/.swarm/sessions/2026-10-01-${CUT}-s3.jsonl.gz"
zero() { awk -F'\t' -v OFS='\t' '{ $8 = "0.00"; $9 = 0 } 1' <<< "$1"; }
check "a damaged copy stops neither the report nor the other rows" \
  "$(outcomes "${dir}/bin" 2>&1; echo "exit $?")" "$(printf '%s\n' "${HEAD}" "${R1}" "$(zero "${R2}")" "$(zero "${R3N}")" "exit 0")"

# --- Each build's own PR, in a second project. gh answers from prs/<head with / as _>: its
# `url<TAB>state` lines, newest first as gh lists them, the first only with --limit 1.
Q="${dir}/two"; U=https://github.com/o/r/pull
mkdir -p "${Q}/.swarm" "${Q}/docs/stories" "${dir}/projects/q" "${dir}/prs" "${dir}/bin2"
git -C "${Q}" init -q
for s in retried shared late foreign; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${Q}/docs/stories/${s}.md"; done
printf -- '---\nkind: code\nepic: e1\nstatus: ready\n---\n' > "${Q}/docs/stories/in-epic.md"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2 $3" = "pr list --head" ] || exit 1\nn=99; case " $* " in *" --limit 1 "*) n=1 ;; esac\nhead -n "$n" "%s/prs/$(echo "$4" | tr / _)" 2>/dev/null\nexit 0\n' "${dir}" > "${dir}/bin2/gh"
chmod +x "${dir}/bin2/gh"
printf '%s\t%s\n' "${U}/2" MERGED "${U}/1" CLOSED > "${dir}/prs/story_retried"
printf '%s\t%s\n' "${U}/3" OPEN > "${dir}/prs/story_shared"
printf '%s\t%s\n' "${U}/4" OPEN > "${dir}/prs/story_late"
printf '%s\t%s\n' "${U}/6" OPEN > "${dir}/prs/story_foreign"
printf '%s\t%s\n' "${U}/10" OPEN > "${dir}/prs/epic_e1"
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
printf '%s\n' \
  $'2026-10-01\tcode\tretried\tclaude\topus\thigh\tr1' $'2026-10-02\tescalate\tretried\tclaude\tfable\txhigh\tr2' \
  $'2026-10-01\tcode\tshared\tclaude\topus\thigh\th1' $'2026-10-02\tcode\tshared\tclaude\topus\thigh\th2' \
  $'2026-10-03\tcode\tlate\tclaude\topus\thigh\tl1' $'2026-10-03\tescalate\tlate\tclaude\tfable\txhigh\tl2' \
  $'2026-10-03\tcode\tforeign\tclaude\topus\thigh\tf1' \
  $'2026-10-04\tcode\tin-epic\tclaude\topus\thigh\te1' $'2026-10-05\tescalate\tin-epic\tclaude\tfable\txhigh\te2' > "${Q}/.swarm/agents.tsv"
two() { # slug, model, pr, pr_state and attempts of each row
  (cd "${Q}" && env -u HERDR_ENV CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin2:${PATH}" bash "${SWARM}" outcomes | cut -f2,6,15-17)
}
check "each build gets the last of its slug's PRs its own log names (named 40000 times or once); none, or another head's, leaves it empty" \
  "$(two | grep -v in-epic)" "$(printf '%s\n' $'slug\tmodel\tpr\tpr_state\tattempts' \
    "retried	opus	${U}/1	CLOSED	1" "retried	fable	${U}/2	MERGED	2" \
    "shared	opus	${U}/3	OPEN	1" "shared	opus	${U}/3	OPEN	2" \
    "late	opus			1" "late	fable	${U}/4	OPEN	2" "foreign	opus			1")"
check "with pr_per = story, an epic story's builds take their PR from their logs too" \
  "$(two | grep in-epic | cut -f3 | paste -sd, -)" ","
mkdir -p "${Q}/.claude/swarm"; echo "pr_per = epic" > "${Q}/.claude/swarm/config"
check "with pr_per = epic, every build of an epic story gets the epic's PR, and the rest are unchanged" \
  "$(two)" "$(printf '%s\n' $'slug\tmodel\tpr\tpr_state\tattempts' \
    "retried	opus	${U}/1	CLOSED	1" "retried	fable	${U}/2	MERGED	2" \
    "shared	opus	${U}/3	OPEN	1" "shared	opus	${U}/3	OPEN	2" \
    "late	opus			1" "late	fable	${U}/4	OPEN	2" "foreign	opus			1" \
    "in-epic	opus	${U}/10	OPEN	1" "in-epic	fable	${U}/10	OPEN	2")"
printf '%s\t%s\n' "${U}/10" MERGED > "${dir}/prs/epic_e1"
check "and MERGED once the epic's PR merges" "$(two | grep in-epic | cut -f4 | paste -sd' ' -)" "MERGED MERGED"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
