#!/usr/bin/env bash
# flow_test.sh — `swarm.sh flow`'s throughput section against a fixture. Epic e1 has stories a to d, b depending on a (a
# chain of 2). a runs 10:00-11:00 (its close) and b 10:20-12:00 (its session log's last entry), so
# 1, then 2, then 1 builders run: 160 build-minutes over a 120-minute span is a mean of 1.33. c and d
# have no session log or close, so they count as stories but not as running. a's PR, created at
# 10:00Z (gh stub), gets a review-agent event at 10:20Z. Epic e2's one story e has a PR created at
# 10:00Z and only a tell:findings at 10:50Z, so its wait is a proxy. Three stacked events, the last
# after --until's date. Epic e3's story g was built twice: PR #3 (14:10Z) got no review before the
# retry's PR #4 (15:10Z), whose review-agent at 15:20Z is #4's alone. The first build was never
# closed, so it ends at its session log's last entry (14:30Z), not at the retry's close (15:30Z). Epic e4's h, closed on 10-03,
# runs past --until 2026-10-02 to its cutoff, so it overlaps i on 10-02. TZ is UTC, so a build with no session log starts at a known time.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
story() { printf -- '---\nkind: code\nstatus: ready\nepic: %s\ndepends_on: [%s]\n---\n' "$2" "$3" > "${P}/docs/stories/$1.md"; }
# b's list is quoted with no space after the comma, as unblock also reads it: b depends on x and a.
story a e1 ""; story b e1 "\"x\",'a'"; story c e1 ""; story d e1 ""; story e e2 ""; story g e3 ""; story h e4 ""; story i e4 ""
session() { # <slug> <first time> <last time> [pull URL] — a session log in the slug's worktree
  printf '{"cwd":"%s/repo-wt/%s","timestamp":"%s"}\n' "${dir}" "$1" "$2"
  printf '{"timestamp":"%s","message":{"content":"%s"}}\n' "$3" "${4:-}"
}
session a 2026-10-01T10:00:00Z 2026-10-01T11:30:00Z "${U}/1" > "${dir}/projects/p/sa.jsonl"
session b 2026-10-01T10:20:00Z 2026-10-01T12:00:00Z > "${dir}/projects/p/sb.jsonl"
session e 2026-10-01T13:00:00Z 2026-10-01T13:30:00Z "${U}/2" > "${dir}/projects/p/se.jsonl"
session g 2026-10-01T14:00:00Z 2026-10-01T14:30:00Z "${U}/3" > "${dir}/projects/p/sg1.jsonl"
session g 2026-10-01T15:00:00Z 2026-10-01T15:30:00Z "${U}/4" > "${dir}/projects/p/sg2.jsonl"
session h 2026-10-01T16:00:00Z 2026-10-01T16:30:00Z > "${dir}/projects/p/sh.jsonl"
session i 2026-10-02T12:00:00Z 2026-10-02T12:30:00Z > "${dir}/projects/p/si.jsonl"
printf '%s\n' \
  $'2026-10-01\tcode\ta\tclaude\topus\thigh\tsa' \
  $'2026-10-01\tcode\tb\tclaude\topus\thigh\tsb' \
  $'2026-10-01\tconduct\tconduct-e1\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\tc\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\td\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\te\tclaude\topus\thigh\tse' \
  $'2026-10-01\tcode\tg\tclaude\topus\thigh\tsg1' \
  $'2026-10-01\tcode\tg\tclaude\topus\thigh\tsg2' \
  $'2026-10-01\tcode\th\tclaude\topus\thigh\tsh' \
  $'2026-10-02\tcode\ti\tclaude\topus\thigh\tsi' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  $'2026-10-01T09:00:00Z\tstacked\tb\tw:1\tok' \
  $'2026-10-01T09:30:00Z\tstacked\tc\tw:1\tok' \
  $'2026-10-01T10:20:00Z\treview-agent\ta\tw:1\tok' \
  $'2026-10-01T10:50:00Z\ttell:findings\te\tw:1\tok' \
  $'2026-10-01T11:00:00Z\tclose:met\ta\tw:1\tok' \
  $'2026-10-01T15:20:00Z\treview-agent\tg\tw:1\tok' \
  $'2026-10-01T15:30:00Z\tclose\tg\tw:1\tok' \
  $'2026-10-03T09:00:00Z\tstacked\td\tw:1\tok' \
  $'2026-10-03T09:00:00Z\tclose\th\tw:1\tok' > "${P}/.swarm/events.tsv"
# gh: pr list answers a's, e's and g's heads; pr view answers each PR's createdAt (#3 at 14:10, #4 at 15:10).
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2 $3 $4" in\n"pr list --head story/a") printf "%s/1\\tOPEN\\t\\n" ;;\n"pr list --head story/e") printf "%s/2\\tOPEN\\t\\n" ;;\n"pr list --head story/g") printf "%s/4\\tOPEN\\t\\n%s/3\\tCLOSED\\t\\n" ;;\n"pr view %s/3 "*) echo 2026-10-01T14:10:00Z ;;\n"pr view %s/4 "*) echo 2026-10-01T15:10:00Z ;;\n"pr view "*) echo 2026-10-01T10:00:00Z ;;\nesac\nexit 0\n' "${U}" "${U}" "${U}" "${U}" "${U}" "${U}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" "$@"); }
tp() { awk '/^## / { f = $0 == "## throughput"; next } f && NF'; } # flow's throughput section
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'epic\tbuilds\tbuilders_mean\tbuilders_max\tstories\tlongest_chain\tstories_per_chain\treview_wait_min\tproxy_review_wait_min\tstacked'
before="$(cat "${P}/.swarm/events.tsv")"
check "per epic: builders at once (mean 1.33, max 2), stories per chain (4 / 2 = 2.0), a review wait of 20 or a proxy of 50, stacked starts" \
  "$(run flow | tp)" "${H}"$'
e1\t4\t1.33\t2\t4\t2\t2.0\t20\t\t3
e2\t1\t1.00\t1\t1\t1\t1.0\t\t50\t0
e3\t2\t0.67\t1\t1\t1\t1.0\t10\t\t0
e4\t2\t1.01\t2\t2\t1\t2.0\t\t\t0
all\t9\t0.97\t2\t8\t2\t4.0\t15\t50\t3'
check "--until drops the events after its date: two stacked events give 2" \
  "$(run flow --until 2026-10-02 | tp | sed -n 2p)" $'e1\t4\t1.33\t2\t4\t2\t2.0\t20\t\t2'
check "a close after --until still ends its build, at the cutoff: h runs into i's day" \
  "$(run flow --until 2026-10-02 | tp | grep '^e4')" $'e4\t2\t1.02\t2\t2\t1\t2.0\t\t\t0'
check "--since keeps the builds and events from its date" \
  "$(run flow --since 2026-10-02 | tp | tail -1)" $'all\t1\t1.00\t1\t1\t1\t1.0\t\t\t1'
check "--epic prints that epic's row alone" "$(run flow --epic e2 | tp)" "${H}"$'\ne2\t1\t1.00\t1\t1\t1\t1.0\t\t50\t0'
check "flow adds no line to events.tsv" "$(cat "${P}/.swarm/events.tsv")" "${before}"
check "a bad flag prints the usage" "$(run flow --until yesterday 2>&1 || true)" \
  "swarm: usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]"
# A second project, in UTC-7: epic `all` (j) is an epic beside the project row; j's agents.tsv day is
# --until's (local), but its session starts at 03:00Z the next UTC day, still inside the local cutoff;
# k's agents.tsv date does not parse and it has no session log, so it is left out.
Q="${dir}/q"; mkdir -p "${Q}/.swarm" "${Q}/docs/stories"; git -C "${Q}" init -q
printf -- '---\nkind: code\nstatus: ready\nepic: all\n---\n' > "${Q}/docs/stories/j.md"
printf '{"cwd":"%s/q-wt/j","timestamp":"2026-10-03T03:00:00Z"}\n{"timestamp":"2026-10-03T03:30:00Z"}\n' "${dir}" > "${dir}/projects/p/sj.jsonl"
printf '%s\n' $'2026-10-02\tcode\tj\tclaude\topus\thigh\tsj' $'2026-10-01x\tcode\tk\tclaude\topus\thigh\t-' > "${Q}/.swarm/agents.tsv"
# j's stacked event at 03:10Z on the 3rd is 20:10 on the 2nd locally, so --until 2026-10-02 keeps it.
printf '%s\n' $'2026-10-03T03:10:00Z\tstacked\tj\tw:1\tok' > "${Q}/.swarm/events.tsv"
check "an epic named all keeps its row; a build and its event late on --until's local day count; a bad date is left out" \
  "$(cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT TZ=America/Los_Angeles CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
    bash "${SWARM}" flow --until 2026-10-02 2>&1 | tp)" "${H}"$'
all\t1\t1.00\t1\t1\t1\t1.0\t\t\t1
all\t1\t1.00\t1\t1\t1\t1.0\t\t\t1'

# A third project. m's first build (logged 10:00-11:50Z) takes its own close at 12:00Z; its log-less
# retry starts when it ended and takes the next close (15:30Z), while z runs 12:00-15:30Z beside it.
# n's two log-less builds on one day take a close each (12:00Z, 18:00Z), so both run. p's first build
# (10:00-11:00Z) is never closed and its two log-less retries find no close after it: the third must
# not start at 00:00 and take the stray close at 08:00Z.
R="${dir}/r"; mkdir -p "${R}/.swarm" "${R}/docs/stories"; git -C "${R}" init -q
for x in m:e6 z:e6 n:e7 p:e8; do printf -- '---\nkind: code\nstatus: ready\nepic: %s\n---\n' "${x#*:}" > "${R}/docs/stories/${x%%:*}.md"; done
lg() { printf '{"cwd":"%s/r-wt/%s","timestamp":"2026-10-01T%s:00Z"}\n{"timestamp":"2026-10-01T%s:00Z"}\n' "${dir}" "$1" "$2" "$3" > "${dir}/projects/p/s$1.jsonl"; }
lg m 10:00 11:50; lg z 12:00 15:30; lg p 10:00 11:00
B=$'\tcode\t'; O=$'\tclaude\topus\thigh\t'
printf '%s\n' "2026-10-01${B}m${O}sm" "2026-10-01${B}m${O}-" "2026-10-01${B}z${O}sz" "2026-10-01${B}n${O}-" "2026-10-01${B}n${O}-" \
  "2026-10-01${B}p${O}sp" "2026-10-01${B}p${O}-" "2026-10-01${B}p${O}-" > "${R}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T08:00:00Z\tclose\tp\tw:1\tok' $'2026-10-01T12:00:00Z\tclose\tm\tw:1\tok' \
  $'2026-10-01T12:00:00Z\tclose\tn\tw:1\tok' $'2026-10-01T15:30:00Z\tclose\tm\tw:1\tok' \
  $'2026-10-01T18:00:00Z\tclose\tn\tw:1\tok' > "${R}/.swarm/events.tsv"
check "each close goes to one build of its slug, in agents.tsv order, and a log-less retry starts when the slug's last known build ended" \
  "$(cd "${R}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" flow 2>&1 | tp)" "${H}"$'
e6\t3\t1.64\t2\t2\t1\t2.0\t\t\t0
e7\t2\t1.00\t1\t1\t1\t1.0\t\t\t0
e8\t3\t1.00\t1\t1\t1\t1.0\t\t\t0
all\t8\t1.56\t3\t4\t1\t4.0\t\t\t0'
for d in --since=9999-12-31 --until=2026-02-30; do
  check "flow ${d%%=*} ${d#*=}, not a real date with a day after it, prints the usage" \
    "$(run flow "${d%%=*}" "${d#*=}" 2>&1 || true)" "swarm: usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>]"
done
for gone in decisions export; do
  out="$(run "${gone}" 2>&1)" && code=0 || code=$?
  check "${gone} is gone: it exits non-zero printing the usage" "${code} $(grep -c 'swarm.sh flow' <<< "${out}")" "2 1"
done

# merge_ins: a fourth project whose own repo holds most PRs' merge-ins. Story m1 (PR #1) changed f and
# so did main, so its merge-in conflicts on f; m2 (#2) changed only b, so it merged in clean while
# behind; m3 (#3) branched from main's tip and its merge-in (made by hand) brought nothing, and
# outcomes counts 2 merge-ins where gh lists 1. gh cannot read m4's PR (#4). m5 (#5) merged main in
# clean, then the builder changed h and added a file whose name holds a tab before committing. m6's
# merge-in (#6, behind) is only in origin's refs/pull/6/head, so it is fetched; m7 (#7) is a story of
# repo s2, where its merge-in conflicts on f. m8's (#8) merge-in is nowhere, so its fetch fails, and gh
# gives an option as its second's sha. m9's (#9) says it merges main in, but has one parent. m10's (#10)
# differs from git's clean merge only on x, a path it leaves as main has it: another strategy's merge,
# behind. gh's answer for m11's PR (#11) has no base branch.
S="${dir}/s"; mkdir -p "${S}/.swarm" "${S}/docs/stories" "${dir}/sbin"
g() { git -C "${S}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g2() { git -C "${dir}/s2" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g init -q -b main; echo a > "${S}/f"; g add f; g commit -qm base
g checkout -qb story/m1; echo c > "${S}/f"; g commit -qam c
g checkout -qb story/m2 main; echo b > "${S}/b"; g add b; g commit -qm b
g checkout -qb story/m5 main; echo h > "${S}/h"; g add h; g commit -qm h
g checkout -q main; echo m > "${S}/f"; g commit -qam m
g checkout -qb story/m3; echo n > "${S}/n"; g add n; g commit -qm n
g checkout -q story/m1; g merge -q main > /dev/null || true; echo cm > "${S}/f"; g commit -qam "Merge branch 'main' into story/m1"
g checkout -q story/m2; g merge -q -m "Merge remote-tracking branch 'origin/main' into story/m2" main
g checkout -q story/m5; g merge -q --no-commit main 2> /dev/null; echo hand > "${S}/h"; echo e > "${S}/e"$'\t'vil; g add -A
g commit -qm "Merge branch 'main' into story/m5"
g checkout -qb story/m10 main~1; echo x > "${S}/x"; g add x; g commit -qm x; g checkout -q main
g branch -f story/m10 "$(g commit-tree 'main^{tree}' -p story/m10 -p main -m "Merge branch 'main' into story/m10")"
g checkout -qb story/m9 main; g commit -q --allow-empty -m "Merge branch 'main' into story/m9"
g branch -f story/m3 "$(g commit-tree 'story/m3^{tree}' -p story/m3 -p main -m 'Merge origin/main into story/m3')"
git clone -q --bare "${S}" "${dir}/s.git"; g remote add origin "${dir}/s.git"; git clone -q "${dir}/s.git" "${dir}/s2"
g2 checkout -qb story/m6 origin/main~1; echo six > "${dir}/s2/six"; g2 add six; g2 commit -qm six
g2 merge -q -m "Merge remote-tracking branch 'origin/main' into story/m6" origin/main; g2 push -q origin story/m6:refs/pull/6/head
g2 checkout -qb story/m7 origin/main~1; echo seven > "${dir}/s2/f"; g2 commit -qam seven
g2 merge -q origin/main > /dev/null || true; echo 7m > "${dir}/s2/f"; g2 commit -qam "Merge branch 'main' into story/m7"
for n in 1 2 3 4 5 6 7 8 9 10 11; do printf -- '---\nkind: code\nstatus: ready\nepic: e9\n---\n' > "${S}/docs/stories/m${n}.md"; done
printf -- '---\nkind: code\nstatus: ready\nepic: e9\nrepo: s2\n---\n' > "${S}/docs/stories/m7.md"
printf '2026-10-01\tcode\tm%s\tclaude\topus\thigh\t-\n' 1 2 3 4 5 6 7 8 9 10 11 > "${S}/.swarm/agents.tsv"
commits() { # <PR> <git function> <merge-in>: gh api's commits of the PR, its merge-in's parent and then its merge-in, whose message has a body
  printf '[[{"sha":"%s","commit":{"message":"c"}},{"sha":"%s","commit":{"message":"%s\\n\\nbody"}}]]' \
    "$("$2" rev-parse "$3^1")" "$("$2" rev-parse "$3")" "$("$2" log -1 --format=%s "$3")" > "${dir}/sbin/$1"
}
for n in 1 2 3 5 9 10; do commits "${n}" g "story/m${n}"; done
commits 6 g2 story/m6; commits 7 g2 story/m7
printf '[[{"sha":"0123456789abcdef0123456789abcdef01234567","commit":{"message":"Merge origin/main into story/m8"}},{"sha":"--output=x","commit":{"message":"Merge origin/main into story/m8"}}]]' > "${dir}/sbin/8"
cat > "${dir}/sbin/gh" <<EOF
#!/bin/sh
n="\${4#story/m}"; n="\${n#repos/o/r/pulls/}"; n="\${n%%/*}"; p="\${2#repos/o/r/pulls/}"
case "\$1 \$2 \$3 \$4" in
  "pr list --head story/m"[34]) printf '${U}/%s\tMERGED\t2026-10-01T12:00:00Z\t2026-10-01T10:00:00Z\t2\n' "\$n" ;;
  "pr list --head story/m"*) printf '${U}/%s\tMERGED\t2026-10-01T12:00:00Z\t2026-10-01T10:00:00Z\t1\n' "\$n" ;;
  "api repos/o/r/pulls/4 "*) echo "HTTP 404: Not Found" >&2; exit 1 ;;
  "api repos/o/r/pulls/11 "*) echo '{"base":{}}' ;;
  "api repos/o/r/pulls/"*) echo '{"base":{"ref":"main"}}' ;;
  "api --paginate --slurp repos/o/r/pulls/"*/commits*) cat "${dir}/sbin/\$n" ;;
  "api "*) exit 1 ;;
esac
EOF
chmod +x "${dir}/sbin/gh"
# shellcheck disable=SC2016 # awk's own $0
mi() { (cd "${S}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=merge_ins CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/sbin:${PATH}" \
  bash "${SWARM}" flow --epic e9 "$@" 2>&1 | awk '/^## / { f = $0 == "## merge_ins"; next } f && NF'); }
check "merge_ins: a conflict or a hand fix names its files (control characters dropped), a clean one behind (one fetched, one another strategy's), one that brought nothing, in its story's repo; why each is unread, a one-parent merge, an option for a sha and no base branch among them" \
  "$(mi --since 2026-10-01)" $'cause\tmerge_ins\tprs
conflict\t3\t3
behind\t3\t3
neither\t1\t1
unread\t7\t5
file\tconflicts
f\t2
evil\t1
h\t1
merge ins: left out '"${U}"$'/11: gh api repos/o/r/pulls/11: an answer with no base branch
merge ins: left out '"${U}"$'/3: gh lists 1 of the 2 merge-ins outcomes counted
merge ins: left out '"${U}"$'/4: gh api repos/o/r/pulls/4: HTTP 404: Not Found
merge ins: fetched refs/pull/6/head into '"$(cd "${S}" && pwd -P)"$'
merge ins: left out '"${U}"$'/8: 0123456789ab: not in '"$(cd "${S}" && pwd -P)"$': git fetch origin refs/pull/8/head: fatal: couldn\'t find remote ref refs/pull/8/head
merge ins: left out '"${U}"$'/8: gh gives \'--output=x\' as a merge-in\'s sha
merge ins: left out '"${U}"$'/9: '"$(g rev-parse --short=12 story/m9)"$': 1 parent(s), not a merge of two'
check "merge_ins: under --epic with no --since, every PR of the epic, as epic_totals counts them" "$(mi --until 2026-12-31 | sed -n 1,2p)" $'cause\tmerge_ins\tprs\nconflict\t3\t3'
check "merge_ins: with no PRs in the window, none conflicted" "$(mi --since 2026-10-02 | tail -1)" "none conflicted"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
