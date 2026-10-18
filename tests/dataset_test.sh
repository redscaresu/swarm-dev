#!/usr/bin/env bash
# dataset_test.sh — `swarm.sh dataset` against a fixture of three merged stories planned in one board
# PR: easy-easy (easy, and was: one build, one findings round, a small diff), easy-hard (easy, but was
# not: two rounds, a 120-line diff and a fix 3 days later naming its PR) and escalated (sonnet, a step-up
# to opus, then Fable, and an escaped finding). A later commit edits easy-hard's story, so its inputs
# must come from the commit that added it. A commit 8 days after easy-easy's merge names its PR, too
# late to be rework. rebased (easy, and was) merged by rebase as two commits with no PR number in
# them, so only gh's merge commit and commit count find its diff; gh answers easy-easy's squash too,
# and fails for the other two, which are found by their `(#N)` subjects. An env value and a transcript line planted in the session logs, and the env
# value exported to the run, must appear nowhere in the output. gh is a stub on PATH.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="$(cd "${dir}" && pwd -P)/repo"; ENV_SECRET="planted-env-value-4242"; TRANSCRIPT="planted transcript line 9137"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${P}/src" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
commit() { # <ISO time> <subject> — commit everything at that time
  git -C "${P}" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$2"
}
lines() { seq "$1" | sed 's/^/line /'; }
echo ".swarm/" > "${P}/.gitignore"
printf -- '---\nkind: code\nstatus: ready\nepic: e1\ndepends_on: []\ntouches: [src/a.txt]\neasy: true\nestimate_lines: 30\n---\n\n# Easy and was easy\n' > "${P}/docs/stories/easy-easy.md"
printf -- '---\nkind: code\nrisk: low\nstatus: ready\nepic: e1\ndepends_on: [easy-easy]\ntouches: [src/b.txt, src/c.txt:fn]\neasy: true\nestimate_lines: 40\n---\n\n# Easy but was hard\n' > "${P}/docs/stories/easy-hard.md"
printf -- '---\nkind: code\nrisk: high\nstatus: ready\nepic: e1\ndepends_on: []\ntouches: [src/d.txt]\neasy: false\nestimate_lines: 200\n---\n\n# Escalated\n' > "${P}/docs/stories/escalated.md"
printf -- '---\nkind: code\nstatus: ready\nepic: e1\ndepends_on: []\ntouches: [src/e.txt]\neasy: true\nestimate_lines: 20\n---\n\n# Rebased\n' > "${P}/docs/stories/rebased.md"
commit 2026-10-01T08:00:00Z "plan e1 (#1)"
sed -i.bak 's/^estimate_lines: 40$/estimate_lines: 999/' "${P}/docs/stories/easy-hard.md" && rm "${P}/docs/stories/easy-hard.md.bak"
commit 2026-10-01T09:00:00Z "easy-hard: in progress"
lines 10 > "${P}/src/a.txt"; rm "${P}/docs/stories/easy-easy.md"; commit 2026-10-02T12:00:00Z "easy one (#2)"
lines 60 > "${P}/src/b.txt"; lines 60 > "${P}/src/c.txt"; rm "${P}/docs/stories/easy-hard.md"; commit 2026-10-03T12:00:00Z "hard one (#3)"
lines 30 > "${P}/src/d.txt"; rm "${P}/docs/stories/escalated.md"; commit 2026-10-05T12:00:00Z "escalated (#4)"
echo fixed >> "${P}/src/b.txt"; commit 2026-10-06T12:00:00Z "fix the bug from #3 (#5)"
echo tidy >> "${P}/src/a.txt"; commit 2026-10-10T13:00:00Z "tidy after #2 (#6)"
lines 5 > "${P}/src/e.txt"; commit 2026-10-11T10:00:00Z "rebased: part one"
lines 10 > "${P}/src/e.txt"; rm "${P}/docs/stories/rebased.md"; commit 2026-10-11T10:00:00Z "rebased: part two"
SQUASH="$(git -C "${P}" log --format=%H --grep '^easy one (#2)$')"; REBASED="$(git -C "${P}" rev-parse HEAD)"

session() { # <slug> <model> <timestamp> [pull URL] — a builder's session log, with the planted lines
  printf '{"type":"user","cwd":"%s/repo-wt/%s","timestamp":"%s"}\n' "${dir}" "$1" "$3"
  printf '{"cwd":"%s/repo-wt/%s","message":{"id":"m-%s-%s","model":"%s","usage":{"input_tokens":1000000,"output_tokens":0}}}\n' "${dir}" "$1" "$1" "$2" "$2"
  printf '{"type":"user","message":{"content":"export GH_TOKEN=%s; %s"}}\n' "${ENV_SECRET}" "${TRANSCRIPT}"
  [[ -z "${4:-}" ]] || printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "$4"
}
lead() { # <epic> — a plan-epic lead's session log: its brief names the epic's output file
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-01T07:00:00Z","message":{"content":"write .swarm/%s/lead.json. %s"}}\n' "${P}" "$1" "${TRANSCRIPT}"
}
U=https://github.com/o/r/pull
lead e1 > "${dir}/projects/p/l1.jsonl"; lead e9 > "${dir}/projects/p/l2.jsonl"
session easy-easy claude-sonnet-5-5 2026-10-02T10:00:00Z "${U}/2" > "${dir}/projects/p/s1.jsonl"
session easy-hard claude-opus-5-5 2026-10-02T11:00:00Z "${U}/3" > "${dir}/projects/p/s2.jsonl"
session escalated claude-sonnet-5-5 2026-10-03T09:00:00Z "${U}/4" > "${dir}/projects/p/s3.jsonl"
session escalated claude-opus-5-5 2026-10-04T08:00:00Z "${U}/4" > "${dir}/projects/p/s4.jsonl"
session escalated claude-fable-5-1 2026-10-04T10:00:00Z "${U}/4" > "${dir}/projects/p/s5.jsonl"
session rebased claude-sonnet-5-5 2026-10-11T09:00:00Z "${U}/7" > "${dir}/projects/p/s6.jsonl"
printf '%s\n' \
  $'2026-10-01\tlead\tlead\tclaude\topus\thigh\tl1' \
  $'2026-10-01\tlead\tlead\tclaude\tsonnet\thigh\tl2' \
  $'2026-10-02\tcode-sonnet\teasy-easy\tclaude\tsonnet\tmedium\ts1' \
  $'2026-10-02\tcode\teasy-hard\tclaude\topus\txhigh\ts2' \
  $'2026-10-03\tcode-sonnet\tescalated\tclaude\tsonnet\tmedium\ts3' \
  $'2026-10-04\tcode\tescalated\tclaude\topus\txhigh\ts4' \
  $'2026-10-04\tescalate\tescalated\tclaude\tfable\txhigh\ts5' \
  $'2026-10-11\tcode-sonnet\trebased\tclaude\tsonnet\tmedium\ts6' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  $'2026-10-02T11:00:00Z\ttell:findings\teasy-easy\tw:1\tok' \
  $'2026-10-02T13:00:00Z\ttell:findings\teasy-hard\tw:1\tok' \
  $'2026-10-02T14:00:00Z\ttell:findings\teasy-hard\tw:1\tok' \
  $'2026-10-04T08:00:00Z\tescalate\tescalated\tw:1\tok (ci-red-2: sonnet -> opus)' \
  $'2026-10-04T10:00:00Z\tescalate\tescalated\tw:1\tok (attempt 3)' \
  $'2026-10-04T10:30:00Z\tescalate\tescalated\tw:1\tfailed (exit 1)' > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-02\tmissing-check\to/r#3\ta\tfixed\tcodex' \
  $'2026-10-02\tnit-kind\to/r#3\tb\tdeclined\tcodex\tnit' \
  $'2026-10-07\tlate-bug\to/r#4\tc\tescaped\tescaped' > "${P}/.swarm/findings.tsv"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2 $3 $4" in
  "pr list --head story/easy-easy") printf "%s/2\\tMERGED\\t2026-10-02T12:00:00Z\\t2026-10-02T11:30:00Z\\t0\\n" ;;
  "pr list --head story/easy-hard") printf "%s/3\\tMERGED\\t2026-10-03T12:00:00Z\\t2026-10-02T12:00:00Z\\t0\\n" ;;
  "pr list --head story/escalated") printf "%s/4\\tMERGED\\t2026-10-05T12:00:00Z\\t2026-10-03T12:00:00Z\\t0\\n" ;;
  "pr list --head story/rebased") printf "%s/7\\tMERGED\\t2026-10-11T10:00:00Z\\t2026-10-11T09:30:00Z\\t0\\n" ;;
  "pr view %s/2 "*) printf "%s\\t1\\n" ;;
  "pr view %s/7 "*) printf "%s\\t2\\n" ;;
  *) exit 1 ;;
esac\n' "${U}" "${U}" "${U}" "${U}" "${U}" "${SQUASH}" "${U}" "${REBASED}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
events_before="$(cat "${P}/.swarm/events.tsv")"
got="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT DATASET_PLANTED="${ENV_SECRET}" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" dataset)"
OUT="${P}/.swarm/dataset.jsonl"
check "it says where it wrote the file, under .swarm/" "${got}" "wrote 4 stories to ${OUT}"
# One line per story, its inputs and results as `key=value` (JSON values), in merge order.
show() { python3 -c '
import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l); i, r = d["inputs"], d["results"]
    print(d["slug"], *(f"{k}={json.dumps(i[k])}" for k in ("kind", "risk", "touches", "depends_on", "estimate_lines", "easy", "planner_model")))
    print(" ", *(f"{k}={json.dumps(r[k])}" for k in sorted(r) if k != "escalations"))
    print(" ", *(json.dumps(e, sort_keys=True) for e in r["escalations"]), "was_easy=" + json.dumps(d["was_easy"]), "rule=%s" % d["was_easy_rule"])' "$1"; }
E1='easy-easy kind="code" risk=null touches=["src/a.txt"] depends_on=[] estimate_lines=30 easy=true planner_model="opus"
  attempts=1 cost_usd=2.0 diff_files=1 diff_lines=10 findings_rounds=1 merged_at="2026-10-02T12:00:00Z" minutes=120 models=["sonnet"] pr="https://github.com/o/r/pull/2" rework=false substantive_findings=0
  was_easy=true rule=1'
E2='easy-hard kind="code" risk="low" touches=["src/b.txt", "src/c.txt:fn"] depends_on=["easy-easy"] estimate_lines=40 easy=true planner_model="opus"
  attempts=1 cost_usd=4.0 diff_files=2 diff_lines=120 findings_rounds=2 merged_at="2026-10-03T12:00:00Z" minutes=1500 models=["opus"] pr="https://github.com/o/r/pull/3" rework=true substantive_findings=1
  was_easy=false rule=1'
E3='escalated kind="code" risk="high" touches=["src/d.txt"] depends_on=[] estimate_lines=200 easy=false planner_model="opus"
  attempts=3 cost_usd=16.0 diff_files=1 diff_lines=30 findings_rounds=0 merged_at="2026-10-05T12:00:00Z" minutes=3060 models=["sonnet", "opus", "fable"] pr="https://github.com/o/r/pull/4" rework=true substantive_findings=0
  {"at": "2026-10-04T08:00:00Z", "from": "sonnet", "to": "opus", "trigger": "ci-red-2"} {"at": "2026-10-04T10:00:00Z", "from": null, "to": null, "trigger": "attempt 3"} was_easy=false rule=1'
E4='rebased kind="code" risk=null touches=["src/e.txt"] depends_on=[] estimate_lines=20 easy=true planner_model="opus"
  attempts=1 cost_usd=2.0 diff_files=1 diff_lines=10 findings_rounds=0 merged_at="2026-10-11T10:00:00Z" minutes=60 models=["sonnet"] pr="https://github.com/o/r/pull/7" rework=false substantive_findings=0
  was_easy=true rule=1'
shown="$(show "${OUT}")"
check "easy-and-was-easy: inputs as planned, one build, one round, a 10-line diff, a fix 8 days later no rework" "$(sed -n 1,3p <<< "${shown}")" "${E1}"
check "easy-but-was-hard: inputs from the commit that added it, two rounds, a 120-line diff, a fix 3 days later is rework" "$(sed -n 4,6p <<< "${shown}")" "${E2}"
check "escalated: every model in build order, each escalation with its trigger, an escaped finding is rework" "$(sed -n 7,9p <<< "${shown}")" "${E3}"
check "rebase-merged: gh's merge commit and commit count give the diff of both its commits" "$(sed -n 10,12p <<< "${shown}")" "${E4}"
check "four lines, each with the story text the board PR added" \
  "$(python3 -c 'import json, sys; [print(json.loads(l)["inputs"]["text"].splitlines()[-1]) for l in open(sys.argv[1])]' "${OUT}")" \
  "$(printf '%s\n' '# Easy and was easy' '# Easy but was hard' '# Escalated' '# Rebased')"
check "the planted env value and transcript line appear nowhere in the output" \
  "$(grep -c -e "${ENV_SECRET}" -e "${TRANSCRIPT}" "${OUT}" || true)" 0
check "git status stays clean and no events.tsv line is written" \
  "$(git -C "${P}" status --porcelain; [[ "$(cat "${P}/.swarm/events.tsv")" == "${events_before}" ]] || echo events changed)" ""

if [[ ${fails} -eq 0 ]]; then echo "all dataset checks passed"; else echo "${fails} dataset check(s) failed"; exit 1; fi
