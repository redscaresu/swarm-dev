#!/usr/bin/env bash
# dataset_test.sh — `swarm.sh dataset` against a fixture of merged stories planned in one board PR, a
# branch whose review fix raised easy-hard's estimate before it merged (so inputs are the merged
# version, not the first draft, nor the later edit on main):
#   easy-easy  easy, and was: one build, one round, a small diff. A PR stacked on it ("Merge after",
#              "Depends on") within 7 days is no fix, and one that fixes it 8 days later is too late.
#   easy-hard  easy, but was not: two rounds, a 120-line diff, a PR 3 days later that fixes it. Its
#              touches hold a note in parentheses with a comma, and its depends_on a comment.
#   escalated  sonnet, a step-up to opus, then Fable, and an escaped finding; the board PR merged its
#              story file as CRLF,
#              gh's merge commit is not in the local history, and its PR deletes the epic's file too.
#   rebased    merged by rebase as two commits, no PR number in either: one's first paragraph runs
#              over two lines (gh's headline is the first), the other's subject has a backslash and
#              is so long gh cuts its headline with ….
#   retried    two builds with no session logs and two PRs, so outcomes gives no build a PR: gh's
#              merged PR is read for the story directly. It merged on origin after the last fetch.
#              Its first PR also merged, and an escaped finding on that one is rework of the story.
#   early      its board PR merged on origin after the last fetch, over a local draft, so only a fetch
#              before reading the board finds it (and it sorts first, so no other story fetches first).
#              Its merge commit is the root, whose diff git cannot make (as in a shallow clone), so its
#              diff and was_easy are null; its build started after the merge, so its minutes are null.
#   gone       its repo: cannot be found, so it is skipped and counted on stderr.
#   moved      gh cannot list its PRs (its GitHub repo moved), and archived gh cannot list its merged
#              PRs, while gh auth status answers: both are skipped and counted; moved keeps its line.
#   phantom    a build whose story is neither on the board nor in its history: counted too.
# A line from the last run (ancient) stays. An impossible escaped-finding day is skipped. An env value
# and a transcript line planted in the session logs, and the env value exported to the run, appear
# nowhere in the output. Then a failing gh, a failing outcomes and a run with no finished story each
# leave the file as it was. The rework query is bounded to the stories' merges plus 7 days, and when
# it fails or comes back at gh's 1000-PR cap, rework it cannot rule out is null. A fetch that fails
# says so on stderr. gh is a stub on PATH. The fixture's path is left as mktemp gives it
# (on macOS under /var, a symlink to /private/var).
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; ENV_SECRET="planted-env-value-4242"; TRANSCRIPT="planted transcript line 9137"
S="${P}/docs/stories"
mkdir -p "${P}/.swarm" "${S}" "${P}/docs/epics" "${P}/src" "${dir}/projects/p" "${dir}/bin" "${dir}/nobin" "${dir}/badpy"
git -C "${P}" init -q
commit() { # <ISO time> <subject> — commit everything at that time
  git -C "${P}" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$2"
}
lines() { seq "$1" | sed 's/^/line /'; }
story() { # <slug> <front matter lines...> — a story file, its title the last line
  local slug="$1"; shift
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${slug}"; } > "${S}/${slug}.md"
}
echo ".swarm/" > "${P}/.gitignore"; commit 2026-09-30T08:00:00Z init
INIT="$(git -C "${P}" rev-parse HEAD)"
MAIN="$(git -C "${P}" symbolic-ref --short HEAD)"
git -C "${P}" checkout -q -b board
story easy-easy "kind: code" "status: ready" "epic: e1" "depends_on: []" "touches: [src/a.txt]" "easy: true" "easy: false" "estimate_lines: 30"
story easy-hard "kind: code" "risk: low" "status: ready" "epic: e1" "depends_on: [easy-easy] # after the first" \
  "touches: [src/b.txt, src/c.txt:fn (new, small)]" "easy: true" "estimate_lines: 35"
story escalated "kind: code" "risk: high" "status: ready" "epic: e1" "depends_on: []" "touches: [src/d.txt]" "easy: false" "estimate_lines: 200"
sed -i.bak 's/$/\r/' "${S}/escalated.md" && rm "${S}/escalated.md.bak"
story rebased "kind: code" "status: ready" "epic: e1" "depends_on: []" "touches: [src/e.txt]" "easy: true" "estimate_lines: 20"
story retried "kind: code" "status: ready" "epic: e1" "depends_on: []" "touches: [src/f.txt]" "easy: true" "estimate_lines: 10"
story gone "kind: code" "repo: nosuch" "status: ready" "epic: e1" "easy: true"
story moved "kind: code" "status: ready" "epic: e1" "easy: true"
story archived "kind: code" "status: ready" "epic: e1" "easy: true"
lines 20 > "${P}/docs/epics/e1.md"
commit 2026-10-01T07:00:00Z "plan e1: first draft"
sed -i.bak 's/^estimate_lines: 35$/estimate_lines: 40/' "${S}/easy-hard.md" && rm "${S}/easy-hard.md.bak"
commit 2026-10-01T07:30:00Z "plan e1: review fixes"
git -C "${P}" checkout -q "${MAIN}"
GIT_AUTHOR_DATE=2026-10-01T08:00:00Z GIT_COMMITTER_DATE=2026-10-01T08:00:00Z \
  git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false merge -q --no-ff -m "Merge pull request #1 from o/board" board
sed -i.bak 's/^estimate_lines: 40$/estimate_lines: 999/' "${S}/easy-hard.md" && rm "${S}/easy-hard.md.bak"
# escalated back to LF on main: outcomes reads a story's last version, and its meta does not take CRLF.
sed -i.bak $'s/\r$//' "${S}/escalated.md" && rm "${S}/escalated.md.bak"
commit 2026-10-01T09:00:00Z "easy-hard: in progress"
lines 10 > "${P}/src/a.txt"; rm "${S}/easy-easy.md"; commit 2026-10-02T12:00:00Z "easy one (#2)"
lines 60 > "${P}/src/b.txt"; lines 60 > "${P}/src/c.txt"; rm "${S}/easy-hard.md"; commit 2026-10-03T12:00:00Z "hard one (#3)"
lines 30 > "${P}/src/d.txt"; rm "${S}/escalated.md" "${P}/docs/epics/e1.md"; commit 2026-10-05T12:00:00Z "escalated (#4)"
echo fixed >> "${P}/src/b.txt"; commit 2026-10-06T12:00:00Z "fix the bug from #3 (#5)"
echo tidy >> "${P}/src/a.txt"; commit 2026-10-10T13:00:00Z "fixes #2 (#6)"
lines 5 > "${P}/src/e.txt"; commit 2026-10-11T10:00:00Z $'rebased: part one\nand a second line'
LONG='rebased: part \ two, a subject long enough that gh cuts its headline short'
lines 10 > "${P}/src/e.txt"; rm "${S}/rebased.md"; commit 2026-10-11T10:00:00Z "${LONG}"
REBASED="$(git -C "${P}" rev-parse HEAD)"
# retried merges on origin after the last fetch: only dataset's own fetch brings its commit.
git clone -q --bare "${P}" "${dir}/origin.git"
git -C "${P}" remote add origin "${dir}/origin.git"; git -C "${P}" fetch -q origin; git -C "${P}" remote set-head origin "${MAIN}"
git clone -q "${dir}/origin.git" "${dir}/other"
lines 7 > "${dir}/other/src/f.txt"; rm "${dir}/other/docs/stories/retried.md"; git -C "${dir}/other" add -A
GIT_AUTHOR_DATE=2026-10-12T12:00:00Z GIT_COMMITTER_DATE=2026-10-12T12:00:00Z \
  git -C "${dir}/other" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "retried (#10)"
RETRIED="$(git -C "${dir}/other" rev-parse HEAD)"
S="${dir}/other/docs/stories"; story early "kind: code" "status: ready" "epic: e1" "depends_on: []" "touches: [src/g.txt]" "easy: true" "estimate_lines: 5"
git -C "${dir}/other" add -A
GIT_AUTHOR_DATE=2026-10-12T13:00:00Z GIT_COMMITTER_DATE=2026-10-12T13:00:00Z \
  git -C "${dir}/other" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "Merge pull request #12 from o/board-early"
git -C "${dir}/other" push -q origin "${MAIN}"
S="${P}/docs/stories"; story early "kind: code" "status: draft" "epic: e1" "depends_on: []" "touches: [src/g.txt]" "easy: true" "estimate_lines: 99"
commit 2026-10-12T14:00:00Z "early: a local draft"
SQUASH="$(git -C "${P}" log --format=%H --grep '^easy one (#2)$')"

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
session early claude-sonnet-5-5 2026-10-13T05:00:00Z "${U}/11" > "${dir}/projects/p/s10.jsonl"
printf '%s\n' \
  $'2026-10-01\tlead\tlead\tclaude\topus\thigh\tl1' \
  $'2026-10-01\tlead\tlead\tclaude\tsonnet\thigh\tl2' \
  $'2026-10-02\tcode-sonnet\teasy-easy\tclaude\tsonnet\tmedium\ts1' \
  $'2026-10-02\tcode\teasy-hard\tclaude\topus\txhigh\ts2' \
  $'2026-10-03\tcode-sonnet\tescalated\tclaude\tsonnet\tmedium\ts3' \
  $'2026-10-04\tcode\tescalated\tclaude\topus\txhigh\ts4' \
  $'2026-10-04\tescalate\tescalated\tclaude\tfable\txhigh\ts5' \
  $'2026-10-11\tcode-sonnet\trebased\tclaude\tsonnet\tmedium\ts6' \
  $'2026-10-11\tcode\tretried\tclaude\topus\txhigh\ts7' \
  $'2026-10-12\tcode\tretried\tclaude\topus\txhigh\ts8' \
  $'2026-10-12\tcode\tgone\tclaude\topus\txhigh\ts9' \
  $'2026-10-13\tcode-sonnet\tearly\tclaude\tsonnet\tmedium\ts10' \
  $'2026-10-13\tcode\tmoved\tclaude\topus\txhigh\ts11' \
  $'2026-10-13\tcode\tarchived\tclaude\topus\txhigh\ts12' \
  $'2026-10-13\tcode\tphantom\tclaude\topus\txhigh\ts13' > "${P}/.swarm/agents.tsv"
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
  $'2026-02-30\tbad-day\to/r#7\tan impossible day\tescaped\tescaped' \
  $'2026-10-07\tlate-bug\to/r#4\tc\tescaped\tescaped' \
  $'2026-10-13\tfirst-pr-bug\to/r#9\td\tescaped\tescaped' > "${P}/.swarm/findings.tsv"
ANCIENT='{"results": {"merged_at": "2026-09-01T00:00:00Z"}, "slug": "ancient"}'
MOVED='{"results": {"merged_at": "2026-09-02T00:00:00Z"}, "slug": "moved"}'
printf '%s\n' "${ANCIENT}" "${MOVED}" > "${P}/.swarm/dataset.jsonl"

# gh: outcomes' PR list per story; dataset's merged PRs per story (as gh's @tsv writes them: a
# backslash doubled); model_fit's merged PRs of the repo.
pr() { printf '{"url":"%s/%s","mergedAt":"%s","title":"%s","body":"%s","files":[{"path":"src/x"}]}' "${U}" "$1" "$2" "$3" "${4:-}"; }
printf '[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s]\n' "$(pr 2 2026-10-02T12:00:00Z "easy one")" "$(pr 3 2026-10-03T12:00:00Z "hard one")" \
  "$(pr 8 2026-10-03T00:00:00Z "stacked child" 'Merge after https://github.com/o/r/pull/2\nDepends on the fix in #2\nStacked on #2')" \
  "$(pr 4 2026-10-05T12:00:00Z escalated)" "$(pr 5 2026-10-06T12:00:00Z "fix the bug from #3")" \
  "$(pr 6 2026-10-10T13:00:00Z "fixes #2")" "$(pr 7 2026-10-11T10:00:00Z rebased)" \
  "$(pr 9 2026-10-11T12:00:00Z "retried, first")" "$(pr 10 2026-10-12T12:00:00Z retried)" "$(pr 11 2026-10-13T00:00:00Z early)" > "${dir}/merged.json"
printf '%s\t%s\t%s\t%s\n' "${U}/2" 2026-10-02T12:00:00Z "${SQUASH}" $'squashed a\001squashed b' > "${dir}/merged-easy-easy.tsv"
printf '%s\t%s\t\t\n' "${U}/3" 2026-10-03T12:00:00Z > "${dir}/merged-easy-hard.tsv"
printf '%s\t%s\t%s\t\n' "${U}/4" 2026-10-05T12:00:00Z deadbeefdeadbeefdeadbeefdeadbeefdeadbeef > "${dir}/merged-escalated.tsv"
printf '%s\t%s\t%s\t%s\n' "${U}/7" 2026-10-11T10:00:00Z "${REBASED}" $'rebased: part one\001rebased: part \\\\ two, a subject long enough that gh cuts its h\xe2\x80\xa6' > "${dir}/merged-rebased.tsv"
printf '%s\t%s\t%s\t%s\n' "${U}/10" 2026-10-12T12:00:00Z "${RETRIED}" retried "${U}/9" 2026-10-11T12:00:00Z 0123456789012345678901234567890123456789 first \
  > "${dir}/merged-retried.tsv"
printf '%s\t%s\t%s\t%s\n' "${U}/11" 2026-10-13T00:00:00Z "${INIT}" init > "${dir}/merged-early.tsv"
cat > "${dir}/bin/gh" <<EOF
#!/bin/sh
case "\$1 \$2 \$3 \$4 \$5 \$6" in
  "pr list --head story/easy-easy --state all") printf '${U}/2\tMERGED\t2026-10-02T12:00:00Z\t2026-10-02T11:30:00Z\t0\n' ;;
  "pr list --head story/easy-hard --state all") printf '${U}/3\tMERGED\t2026-10-03T12:00:00Z\t2026-10-02T12:00:00Z\t0\n' ;;
  "pr list --head story/escalated --state all") printf '${U}/4\tMERGED\t2026-10-05T12:00:00Z\t2026-10-03T12:00:00Z\t0\n' ;;
  "pr list --head story/rebased --state all") printf '${U}/7\tMERGED\t2026-10-11T10:00:00Z\t2026-10-11T09:30:00Z\t0\n' ;;
  "pr list --head story/retried --state all") printf '${U}/10\tMERGED\t2026-10-12T12:00:00Z\t2026-10-12T10:00:00Z\t0\n${U}/9\tMERGED\t2026-10-11T12:00:00Z\t2026-10-11T10:00:00Z\t0\n' ;;
  "pr list --head story/archived --state all") printf '${U}/13\tMERGED\t2026-10-13T12:00:00Z\t2026-10-13T10:00:00Z\t0\n' ;;
  "pr list --head story/archived --state merged") exit 1 ;;
  "auth status"*) exit 0 ;;
  "pr list --head story/early --state all") printf '${U}/11\tMERGED\t2026-10-13T00:00:00Z\t2026-10-12T23:00:00Z\t0\n' ;;
  "pr list --head story/"*" --state merged") cat "${dir}/merged-\${4#story/}.tsv" 2>/dev/null; exit 0 ;;
  "pr list -R o/r --state merged") echo "\$@" > "${dir}/search.txt"
    [ ! -e "${dir}/rework-down" ] || exit 1
    if [ -e "${dir}/rework-cap" ]; then cat "${dir}/capped.json"; else cat "${dir}/merged.json"; fi ;;
  *) exit 1 ;;
esac
EOF
python3 -c 'import json; print(json.dumps([{"url": "https://github.com/o/r/pull/%d" % (1000 + i), "mergedAt": "2026-10-03T00:00:00Z",
  "title": "other", "body": "", "files": []} for i in range(1000)]))' > "${dir}/capped.json"
printf '#!/bin/sh\nexit 1\n' > "${dir}/nobin/gh"
# A python3 that fails outcomes' row reader and runs everything else.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1" in *outcomes_rows.py) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v python3)" > "${dir}/badpy/python3"
chmod +x "${dir}/bin/gh" "${dir}/nobin/gh" "${dir}/badpy/python3"

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
run() { # <PATH prefix> — the dataset run, its stdout and stderr, then its exit status
  local rc=0
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT DATASET_PLANTED="${ENV_SECRET}" CLAUDE_PROJECTS_DIR="${dir}/projects" \
    PATH="$1:${PATH}" bash "${SWARM}" dataset 2>&1) || rc=$?
  echo "exit ${rc}"
}
events_before="$(cat "${P}/.swarm/events.tsv")"
OUT="${P}/.swarm/dataset.jsonl"
check "it says where it wrote the file under .swarm/, keeps last run's lines, and counts the stories with no story, no repo or PRs gh cannot read on stderr" "$(run "${dir}/bin")" \
  "dataset: skipped 4 stories whose story, repo or PRs could not be read; their lines from the last run stay
wrote 8 stories to $(cd "${P}" && pwd -P)/.swarm/dataset.jsonl (2 kept from the last run)
exit 0"
# One line per story, its inputs and results as `key=value` (JSON values), in merge order.
show() { python3 -c '
import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l)
    if "inputs" not in d:
        continue
    i, r = d["inputs"], d["results"]
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
E5='retried kind="code" risk=null touches=["src/f.txt"] depends_on=[] estimate_lines=10 easy=true planner_model="opus"
  attempts=2 cost_usd=0.0 diff_files=1 diff_lines=7 findings_rounds=0 merged_at="2026-10-12T12:00:00Z" minutes=2160 models=["opus"] pr="https://github.com/o/r/pull/10" rework=true substantive_findings=0
  was_easy=false rule=1'
E6='early kind="code" risk=null touches=["src/g.txt"] depends_on=[] estimate_lines=5 easy=true planner_model="opus"
  attempts=1 cost_usd=2.0 diff_files=null diff_lines=null findings_rounds=0 merged_at="2026-10-13T00:00:00Z" minutes=null models=["sonnet"] pr="https://github.com/o/r/pull/11" rework=false substantive_findings=0
  was_easy=null rule=1'
shown="$(show "${OUT}")"
check "easy-and-was-easy: inputs as planned (first key wins), one round, a 10-line diff, a stacked child and a fix 8 days later are no rework" "$(sed -n 1,3p <<< "${shown}")" "${E1}"
check "easy-but-was-hard: inputs as the board PR merged them, touches and depends_on as touches_rows reads them, a fix 3 days later is rework" "$(sed -n 4,6p <<< "${shown}")" "${E2}"
check "escalated: CRLF read, every model in build order, each escalation with its trigger, an escaped finding is rework, the epic file and a merge commit not fetched left out" "$(sed -n 7,9p <<< "${shown}")" "${E3}"
check "rebase-merged: gh's merge commit and commit headlines (a two-line subject's first line, a backslash, one cut short) give the diff of both its commits" "$(sed -n 10,12p <<< "${shown}")" "${E4}"
check "a retried story whose PR outcomes gives no build: gh's newest merged PR read directly, its merge fetched, rework on its first PR, minutes from its first build's day" "$(sed -n 13,15p <<< "${shown}")" "${E5}"
check "a board PR merged since the last fetch read as merged; a merge git cannot diff: diff and was_easy null; a start after the merge: minutes null" "$(sed -n 16,18p <<< "${shown}")" "${E6}"
check "each line holds the story text the board PR merged, and last run's lines stay as they were" \
  "$(python3 -c 'import json, sys; [print(json.loads(l).get("inputs", {}).get("text", l).splitlines()[-1]) for l in open(sys.argv[1])]' "${OUT}")" \
  "$(printf '%s\n' "${ANCIENT}" "${MOVED}" '# easy-easy' '# easy-hard' '# escalated' '# rebased' '# retried' '# early')"
check "the planted env value and transcript line appear nowhere in the output" \
  "$(grep -c -e "${ENV_SECRET}" -e "${TRANSCRIPT}" "${OUT}" || true)" 0
check "the rework query asks gh for the stories' merges up to 7 days after the last" "$(grep -o 'merged:[^ ]*' "${dir}/search.txt")" \
  "merged:2026-10-02..2026-10-20"
check "git status stays clean and no events.tsv line is written" \
  "$(git -C "${P}" status --porcelain; [[ "$(cat "${P}/.swarm/events.tsv")" == "${events_before}" ]] || echo events changed)" ""

written="$(cat "${OUT}")"
same() { [[ "$(cat "${OUT}")" == "${written}" ]] && echo same || echo changed; }
check "a failing gh dies and leaves the file as it was" \
  "$(run "${dir}/nobin" | grep -c -e '^swarm: dataset: gh is not answering (see gh auth status)' -e '^exit 1$'; same)" "2
same"
check "a failing outcomes dies and leaves the file as it was" \
  "$(run "${dir}/badpy:${dir}/bin" | grep -c -e 'outcomes: reading the logs failed' -e '^exit 1$'; same)" "2
same"
cp "${P}/.swarm/agents.tsv" "${dir}/agents.tsv"; head -2 "${dir}/agents.tsv" > "${P}/.swarm/agents.tsv"
check "a run that finds no finished story keeps every line" "$(run "${dir}/bin" | tail -1; same)" "exit 0
same"
cp "${dir}/agents.tsv" "${P}/.swarm/agents.tsv"

# Rework when gh's list of merged PRs fails, or comes back at its cap: escaped findings still mark it,
# and what they do not mark is null, with was_easy null where only rework could decide it.
fit() { python3 -c '
import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l)
    if "inputs" in d:
        print(d["slug"], json.dumps(d["results"]["rework"]), json.dumps(d["was_easy"]))' "${OUT}"; }
UNKNOWN="easy-easy null null
easy-hard null false
escalated true false
rebased null null
retried true false
early null null"
touch "${dir}/rework-down"
check "a failing rework query leaves rework null unless an escaped finding marks it" "$(run "${dir}/bin" | grep -c 'only escaped findings mark rework'; fit)" "1
${UNKNOWN}"
rm "${dir}/rework-down"; touch "${dir}/rework-cap"
check "a rework query at gh's cap leaves rework null unless an escaped finding marks it" "$(run "${dir}/bin" | grep -c 'only escaped findings mark rework'; fit)" "1
${UNKNOWN}"
rm "${dir}/rework-cap"
git -C "${P}" remote set-url origin "${dir}/no-such-origin.git"
check "a fetch that fails says so on stderr" "$(run "${dir}/bin" | grep -c "^dataset: git fetch origin failed in $(cd "${P}" && pwd -P), so its origin/HEAD may be stale$")" 1
git -C "${P}" remote set-url origin "${dir}/origin.git"

if [[ ${fails} -eq 0 ]]; then echo "all dataset checks passed"; else echo "${fails} dataset check(s) failed"; exit 1; fi
