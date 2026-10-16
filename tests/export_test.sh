#!/usr/bin/env bash
# export_test.sh — `swarm.sh export` against a fixture project: a one-attempt merged story whose session
# log is only close's archived copy, a retried story (#1 CLOSED, #2 MERGED, the retry on a model no enum
# knows), an escalated story (two code builds, then an escalate build with escalate, dialog, escalated
# and reset events) and a story whose front matter and agents.tsv line carry free text where an enum or
# a model belongs. gh is a stub on PATH. SENTINEL-TEXT is planted everywhere free text lives (finding
# text, a reset reason, a dialog answer, a brief, a reply, a session log, the story body, a failed
# command's message, and those passthrough cells) and must reach neither format.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
METHOD="$(dirname "${SWARM}")/../docs/method.md"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/export-fixture"; U=https://github.com/o/r/pull; S=SENTINEL-TEXT
mkdir -p "${P}/.swarm/sessions" "${P}/.swarm/briefs" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
printf -- '---\nkind: code\nrisk: high\nepic: ep1\nstatus: ready\n---\n\n# One shot\n\n%s\n' "${S}" > "${P}/docs/stories/one-shot.md"
printf -- '---\nkind: code\nepic: ep1\nstatus: ready\n---\n' > "${P}/docs/stories/retried.md"
printf -- '---\nkind: code\nepic: ep2\nstatus: ready\n---\n' > "${P}/docs/stories/escalated.md"
printf -- '---\nkind: %s\nrisk: %s\nstatus: ready\n---\n' "${S}" "${S}" > "${P}/docs/stories/tainted.md"
echo "${S}" > "${P}/.swarm/briefs/retried.md"
echo "${S}" > "${P}/.swarm/conduct-ep1.report.md"

session() { # <session id> <slug> <first timestamp> <model> [pull URL...] — a session log: its worktree
  # cwd, a brief holding the sentinel, one message's usage, then a tool result naming each URL
  local u
  printf '{"type":"user","cwd":"%s/repo-wt/%s","timestamp":"%s","message":{"content":"%s"}}\n' "${dir}" "$2" "$3" "${S}"
  printf '{"message":{"id":"m-%s","model":"%s","usage":{"input_tokens":1,"cache_creation_input_tokens":20,"cache_read_input_tokens":300,"output_tokens":4000}}}\n' "$1" "$4"
  for u in "${@:5}"; do printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "${u}"; done
}
# one-shot's log is gone from Claude Code's projects dir: only close's gzip copy is left.
session s1 one-shot 2026-10-01T09:00:00Z claude-opus-5-5 "${U}/1" | gzip -c > "${P}/.swarm/sessions/2026-10-01-one-shot-s1.jsonl.gz"
session s2 retried 2026-10-01T10:00:00Z claude-opus-5-5 "${U}/2" > "${dir}/projects/p/s2.jsonl"
session s3 retried 2026-10-02T10:00:00Z claude-mystery-7 "${U}/2" "${U}/3" > "${dir}/projects/p/s3.jsonl"
session s4 escalated 2026-10-02T11:00:00Z claude-opus-5-5 > "${dir}/projects/p/s4.jsonl"
session s5 escalated 2026-10-02T13:00:00Z claude-opus-5-5 > "${dir}/projects/p/s5.jsonl"
session s6 escalated 2026-10-03T09:01:00Z claude-fable-5-1 > "${dir}/projects/p/s6.jsonl"
session s7 tainted 2026-10-03T12:00:00Z claude-sonnet-5-5 "${U}/4" > "${dir}/projects/p/s7.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode-risky\tone-shot\tclaude\topus\txhigh\ts1' \
  $'2026-10-01\tconduct\tconduct-ep1\tclaude\topus\thigh\ts0' \
  $'2026-10-01\tcode\tretried\tclaude\topus\thigh\ts2' \
  $'2026-10-02\tcode\tretried\tclaude\tmystery-7.5\tmax\ts3' \
  $'2026-10-02\tcode\tescalated\tclaude\topus\thigh\ts4' \
  $'2026-10-02\tcode\tescalated\tclaude\topus\thigh\ts5' \
  $'2026-10-03\tescalate\tescalated\tclaude\tfable\txhigh\ts6' \
  $'2026-10-03\tdocs\ttainted\tclaude\t'"${S}"$'\t'"${S}"$'\ts7' > "${P}/.swarm/agents.tsv"
# The dialog with free text comes first, so the accepted one is the cycle's last. The failed tell's
# outcome is its die message.
printf '%s\n' \
  $'2026-10-01T11:00:00Z\ttell:nudge\tretried\tw:1\tok' \
  $'2026-10-01T12:00:00Z\tclose:stalled\tretried\tw:1\tok' \
  $'2026-10-02T11:30:00Z\ttell:findings\tretried\tw:1\tswarm.sh: '"${S}" \
  $'2026-10-02T12:00:00Z\ttell:findings\tretried\tw:1\tok' \
  $'2026-10-02T12:30:00Z\ttell:resume\tretried\tw:1\tok' \
  $'2026-10-02T14:00:00Z\tclose:met\tretried\tw:1\tok' \
  $'2026-10-02T12:00:00Z\tclose:stalled\tescalated\tw:1\tok' \
  $'2026-10-02T15:00:00Z\tclose\tescalated\tw:1\tok' \
  $'2026-10-03T09:00:00Z\tescalate\tescalated\tw:1\tok (attempt 3)' \
  $'2026-10-03T09:10:00Z\tdialog\tescalated\tw:1\tok ('"${S}"')' \
  $'2026-10-03T09:11:00Z\tdialog\tescalated\tw:1\tok (accepted)' \
  $'2026-10-03T10:00:00Z\tescalated\tescalated\tw:1\tok (attempts 3, 0 PRs)' \
  $'2026-10-03T11:00:00Z\treset\tescalated\tw:1\tok ('"${S}"')' > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-01\tmissing-check\t'"${U}"$'/1\t'"${S}"$'\tfixed\tcodex' \
  $'2026-10-01\tnit\to/r#1\t'"${S}"$'\tdeclined\tcode-review' \
  $'2026-10-02\tvacuous-test\to/r#3\t'"${S}"$'\tfixed\tlead' \
  $'2026-10-02\tvacuous-test\to/r#3\tx\tfixed\tcodex' > "${P}/.swarm/findings.tsv"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\ncase "$4" in\n  story/one-shot) printf "%s/1\\tMERGED\\t2026-10-01T12:00:00Z\\n" ;;\n  story/retried) printf "%s/3\\tMERGED\\t2026-10-02T16:00:00Z\\n%s/2\\tCLOSED\\t\\n" ;;\n  story/tainted) printf "%s/4\\tOPEN\\t\\n" ;;\nesac\n' "${U}" "${U}" "${U}" "${U}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

export_() { # [args] — the export, stderr to err
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" export "$@") 2> "${dir}/err"
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

HEAD="project slug epic kind risk role model effort started tokens_input tokens_cache_write tokens_cache_read tokens_output"
HEAD+=" cost_usd tells_findings tells_nudge tells_resume findings_fixed findings_declined findings_fixed_by findings_declined_by"
HEAD+=" escalate_at dialog_at dialog escalated_at reset_at drop_at close_cause pr pr_state merged_at attempt story_merged"
HEAD="${HEAD// /	}"
T=$'1\t20\t300\t4000'; E6=$'\t\t\t\t\t'   # the four tokens; the six escalation steps (five tabs between them)
# opus and fable 1/20/300/4000 tokens = $0.08, sonnet $0.04, a model with no price $0.00.
R1="export-fixture	one-shot	ep1	code	high	code-risky	opus	xhigh	2026-10-01T09:00:00Z	${T}	0.08	0	0	0	1	1	codex:1	code-review:1	${E6}		${U}/1	MERGED	2026-10-01T12:00:00Z	1	true"
R2="export-fixture	retried	ep1	code		code	opus	high	2026-10-01T10:00:00Z	${T}	0.08	0	1	0	0	0			${E6}	stalled	${U}/2	CLOSED		1	true"
R3="export-fixture	retried	ep1	code		code	mystery-7.5	max	2026-10-02T10:00:00Z	${T}	0.00	1	0	1	2	0	codex:1 lead:1		${E6}	met	${U}/3	MERGED	2026-10-02T16:00:00Z	2	true"
R4="export-fixture	escalated	ep2	code		code	opus	high	2026-10-02T11:00:00Z	${T}	0.08	0	0	0	0	0			${E6}	stalled				1	false"
R5="export-fixture	escalated	ep2	code		code	opus	high	2026-10-02T13:00:00Z	${T}	0.08	0	0	0	0	0			${E6}					2	false"
R6="export-fixture	escalated	ep2	code		escalate	fable	xhigh	2026-10-03T09:01:00Z	${T}	0.08	0	0	0	0	0			2026-10-03T09:00:00Z	2026-10-03T09:11:00Z	accepted	2026-10-03T10:00:00Z	2026-10-03T11:00:00Z						3	false"
R7="export-fixture	tainted				docs			2026-10-03T12:00:00Z	${T}	0.04	0	0	0	0	0			${E6}		${U}/4	OPEN		1	false"

tsv="$(export_ --format tsv)"
check "tsv: exactly the documented header, and every column of every row pinned" \
  "${tsv}" "$(printf '%s\n' "${HEAD}" "${R1}" "${R2}" "${R3}" "${R4}" "${R5}" "${R6}" "${R7}")"
W="swarm.sh export: row 7:"
check "a passthrough cell that fails its type is emptied with a warning on stderr that does not repeat it" \
  "$(cat "${dir}/err")" "$(printf '%s\n' "${W} kind is not a valid enum, left empty" "${W} risk is not a valid enum, left empty" \
    "${W} model is not a valid model, left empty" "${W} effort is not a valid enum, left empty")"

jsonl="$(export_)"
# Each jsonl object, its values written back as tsv (null empty, true/false as words, floats to two
# places), and its keys, must be the tsv's.
back() { python3 -c '
import json, sys
for l in sys.stdin:
    o = json.loads(l)
    print("\t".join("" if v is None else str(v).lower() if isinstance(v, bool) else f"{v:.2f}" if isinstance(v, float) else str(v) for v in o.values()))' <<< "$1"; }
check "jsonl (the default) gives the same values" "$(back "${jsonl}")" "$(tail -n +2 <<< "${tsv}")"
check "jsonl keys are the tsv header, in order" \
  "$(python3 -c 'import json, sys; print("\n".join("\t".join(json.loads(l)) for l in sys.stdin))' <<< "${jsonl}" | sort -u)" "${HEAD}"
check "jsonl values are typed: ints, floats, bools, null, strings" \
  "$(python3 -c 'import json, sys; print(" ".join(sorted({f"{k}={type(v).__name__}" for l in sys.stdin for k, v in json.loads(l).items() if k in ("attempt", "cost_usd", "story_merged", "drop_at", "pr", "tokens_output")})))' <<< "${jsonl}")" \
  "attempt=int cost_usd=float drop_at=NoneType pr=NoneType pr=str story_merged=bool tokens_output=int"

builders="$(awk -F'\t' 'NF == 7 && $2 ~ /^(code|code-risky|code-sonnet|docs|chore|verify|escalate)$/' "${P}/.swarm/agents.tsv" | wc -l | tr -d ' ')"
check "one row per agents.tsv builder line, in either format" "$(wc -l <<< "${jsonl}" | tr -d ' ') $(($(wc -l <<< "${tsv}") - 1))" "${builders} ${builders}"
check "--since drops earlier rows and keeps attempt numbers" \
  "$(export_ --format tsv --since 2026-10-02)" "$(printf '%s\n' "${HEAD}" "${R3}" "${R4}" "${R5}" "${R6}" "${R7}")"

check "SENTINEL-TEXT reaches neither format" "$(grep -c "${S}" <<< "${tsv}${jsonl}" || true)" 0
check "nor stderr" "$(grep -c "${S}" "${dir}/err" || true)" 0

for args in "--format csv" "--since 2026-1-1" "bogus" "--format" "--since"; do
  # shellcheck disable=SC2086 # each word is an argument
  if export_ ${args} >/dev/null; then echo "FAIL export ${args} is refused"; fails=$((fails + 1))
  else check "export ${args} is refused with the usage line" "$(cat "${dir}/err")" "swarm: usage: swarm.sh export [--since YYYY-MM-DD] [--format jsonl|tsv]"; fi
done
snap() { (cd "${P}/.swarm" && find . | sort && find . -type f -exec cksum {} + | sort); }
before="$(snap)"; export_ >/dev/null; export_ --format tsv >/dev/null
check "export creates and changes no file under .swarm, events.tsv included" "$(snap)" "${before}"

documented="$(awk '/^`swarm.sh export/ { s = 1; next } s && /^`swarm.sh / { exit } s && /^\| `[a-z_]+` \|/ { print }' "${METHOD}" | cut -d'`' -f2)"
check "docs/method.md lists every exported column, in the header's order" "${documented}" "$(tr '\t' '\n' <<< "${HEAD}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
