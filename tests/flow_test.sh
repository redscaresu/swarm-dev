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
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
export SWARM_GH_CACHE=""   # each run reads gh afresh, as its stub answers change between runs (gh_cache_test.sh tests the cache)
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
# ready_wait: a was unblocked at 09:52 and built at 10:00, so it waited 8 minutes; b's build started
# at 10:20, before its unblock at 10:30, so it waited 0, not -10. c and d have no ready time.
printf '%s\n' $'2026-10-01T09:52:00Z\tunblock\ta\tw:1\tok' $'2026-10-01T10:30:00Z\tunblock\tb\tw:1\tok' >> "${P}/.swarm/events.tsv"
rw() { awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next } $at["epic"] == "e1" { print $at["slug"], $at["ready_wait_min"] }'; }
check "ready_wait: a story readied at T and built at T+8 min waited 8; one built before it was readied waited 0" \
  "$(run outcomes 2>/dev/null | rw)" $'a 8\nb 0\nc \nd '
tis() { awk '/^## / { f = $0 == "## time_in_state"; next } f && NF' | cut -f1,5,6; } # epic and ready_wait
check "ready_wait: time_in_state gives each epic's median and p90 (nearest rank) in minutes" \
  "$(run flow 2>/dev/null | tis | grep -E '^(epic|e1|all)')" $'epic\tready_wait_median\tready_wait_p90\ne1\t4\t8\nall\t4\t8'
# A step-up rung of a at 11:00 keeps attempts at 1, so outcomes gives it a ready_wait of its own (68);
# time_in_state counts each story once, by its earliest build, so the median and p90 stay 4 and 8.
agents_before="$(cat "${P}/.swarm/agents.tsv")"
session a 2026-10-01T11:00:00Z 2026-10-01T11:30:00Z > "${dir}/projects/p/sa2.jsonl"
printf '%s\n' $'2026-10-01\tcode\ta\tclaude\tfable\thigh\tsa2' >> "${P}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T10:59:00Z\tescalate\ta\tw:1\tok (stalled: opus -> fable)' >> "${P}/.swarm/events.tsv"
check "ready_wait: a stepped-up story counts once, by its first build, not again by its rung" \
  "$(run flow 2>/dev/null | tis | grep -E '^(e1|all)')" $'e1\t4\t8\nall\t4\t8'
printf '%s\n' "${agents_before}" > "${P}/.swarm/agents.tsv"; rm "${dir}/projects/p/sa2.jsonl"
printf '%s\n' "${before}" > "${P}/.swarm/events.tsv"
check "a bad flag prints the usage" "$(run flow --until yesterday 2>&1 || true)" \
  "swarm: usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]"
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
    "$(run flow "${d%%=*}" "${d#*=}" 2>&1 || true)" "swarm: usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]"
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
# behind. gh's answer for m11's PR (#11) has no base branch. The project's origin is github.com/o/r, which
# git reads from s.git. m12 (#12, epic e11) is a story of s2, whose origin is not: its missing merge-in is
# not fetched. m13 (#13, epic e10) is m2's clean merge-in again. m14's (#14, epic e12) merge-in names a
# tree git does not have, so its diff against git's clean merge fails: unread, not a clean merge. m15's
# (#15, epic e12) is a hand fix whose diff against the base alone fails, by a git stub.
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
git clone -q --bare "${S}" "${dir}/s.git"; g remote add origin https://github.com/o/r.git; g config url."${dir}/s.git".insteadOf https://github.com/o/r.git
git clone -q "${dir}/s.git" "${dir}/s2"
g2 checkout -qb story/m6 origin/main~1; echo six > "${dir}/s2/six"; g2 add six; g2 commit -qm six
g2 merge -q -m "Merge remote-tracking branch 'origin/main' into story/m6" origin/main; g2 push -q origin story/m6:refs/pull/6/head
g2 checkout -qb story/m7 origin/main~1; echo seven > "${dir}/s2/f"; g2 commit -qam seven
g2 merge -q origin/main > /dev/null || true; echo 7m > "${dir}/s2/f"; g2 commit -qam "Merge branch 'main' into story/m7"
g branch -f story/m14 "$(printf 'tree %s\nparent %s\nparent %s\nauthor t <t@t> 0 +0000\ncommitter t <t@t> 0 +0000\n\n%s\n' \
  1111111111111111111111111111111111111111 "$(g rev-parse story/m2^1)" "$(g rev-parse main)" "Merge branch 'main' into story/m14" |
  g hash-object -t commit -w --literally --stdin)"
g checkout -qb story/m15 story/m2^1; g merge -q --no-ff --no-commit main > /dev/null 2>&1; echo 15 > "${S}/fifteen"; g add fifteen
g commit -qm "Merge branch 'main' into story/m15"; g checkout -q story/m9
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13; do printf -- '---\nkind: code\nstatus: ready\nepic: e9\n---\n' > "${S}/docs/stories/m${n}.md"; done
printf -- '---\nkind: code\nstatus: ready\nepic: e9\nrepo: s2\n---\n' > "${S}/docs/stories/m7.md"
printf -- '---\nkind: code\nstatus: ready\nepic: e11\nrepo: s2\n---\n' > "${S}/docs/stories/m12.md"
printf -- '---\nkind: code\nstatus: ready\nepic: e10\n---\n' > "${S}/docs/stories/m13.md"
for n in 14 15; do printf -- '---\nkind: code\nstatus: ready\nepic: e12\n---\n' > "${S}/docs/stories/m${n}.md"; done
printf '2026-10-01\tcode\tm%s\tclaude\topus\thigh\t-\n' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 > "${S}/.swarm/agents.tsv"
commits() { # <PR> <git function> <merge-in>: gh api's commits of the PR, its merge-in's parent and then its merge-in, whose message has a body
  printf '[[{"sha":"%s","commit":{"message":"c"}},{"sha":"%s","commit":{"message":"%s\\n\\nbody"}}]]' \
    "$("$2" rev-parse "$3^1")" "$("$2" rev-parse "$3")" "$("$2" log -1 --format=%s "$3")" > "${dir}/sbin/$1"
}
for n in 1 2 3 5 9 10 14 15; do commits "${n}" g "story/m${n}"; done
commits 6 g2 story/m6; commits 7 g2 story/m7; cp "${dir}/sbin/2" "${dir}/sbin/13"
printf '[[{"sha":"fedcba9876543210fedcba9876543210fedcba98","commit":{"message":"Merge origin/main into story/m12"}}]]' > "${dir}/sbin/12"
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
cat > "${dir}/sbin/git" <<EOF
#!/bin/sh
case " \$* " in *" diff "*" $(g rev-parse main) $(g rev-parse 'story/m15^{tree}') ") echo "fatal: stub: no diff" >&2; exit 128 ;; esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "${dir}/sbin/git"
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
check "merge_ins: with no PRs in the window, none read" "$(mi --since 2026-10-02 | tail -1)" "none read"
check "merge_ins: a clean merge-in alone, none conflicted" "$(mi --since 2026-10-01 --epic e10 | tail -1)" "none conflicted"
check "merge_ins: every merge-in unread, none read; an origin that is not the PR's repo is never fetched from" "$(mi --since 2026-10-01 --epic e11)" $'cause\tmerge_ins\tprs
conflict\t0\t0
behind\t0\t0
neither\t0\t0
unread\t1\t1
none read
merge ins: left out '"${U}"$'/12: fedcba987654: not in '"$(cd "${dir}/s2" && pwd -P)"$': its origin is not github.com/o/r'
check "merge_ins: a git diff that fails, against git's clean merge or the base alone, leaves its merge-in unread, naming the error" \
  "$(mi --since 2026-10-01 --epic e12 | sed 's|\(/14: [0-9a-f]*: git diff: \).*|\1...|')" $'cause\tmerge_ins\tprs
conflict\t0\t0
behind\t0\t0
neither\t0\t0
unread\t2\t2
none read
merge ins: left out '"${U}"$'/14: '"$(g rev-parse --short=12 story/m14)"$': git diff: ...
merge ins: left out '"${U}"$'/15: '"$(g rev-parse --short=12 story/m15)"$': git diff: fatal: stub: no diff'

# ci_health's flaky tests: a fifth project, its origin o/r, its PRs #1 (t1, epic e1) and #2 (t2). gh
# lists 11 of the 12 runs of o/r created 10-01 to 10-03. Run 11 was red on both attempts (e_test.sh)
# before run 10, on the same head, workflow and event, went red and then green on its rerun, its
# failed log naming a_test.sh twice, beside a byte that is not UTF-8: both flaky, as the row counts them. Run 21 (push) red on c_test.sh,
# then green; run 24 red, green, red (c_test.sh both times) and green; run 25 red (f_test.sh), green,
# then red; run 20 red on both attempts (b_test.sh), alone on its head: no flake. Run 22 red, then
# green, its log one gh cannot read; run 26's first attempt gh cannot read; run 27's log is go test's,
# with no FAIL tests/<file> line; run 23 green the first time. On 10-02, main's run 30 was red twice
# (c_test.sh both times, d_test.sh's TIMEOUT the second), then green. So c_test.sh 3 (runs 24 and 30
# once each), then by the newest d, f, a and e. Run 30's log also has a check that quotes a FAIL
# tests/z_test.sh line, and an indented and a diffed FAIL tests/y_test.sh line, none test.sh's own. t3's PR (#3, epic e1) is a retry on t1's branch,
# so under --epic runs 10 and 11 are its too, counted once. t4's and t5's PRs (#4, #5, epic e2) share
# t4's branch and its one green run 40; t6's PR (#6, epic e3) gh cannot read, beside t7's (#7, e3) on
# t4's branch. A project u, its origin o/z, has u1's PR #9 on o/r, built 10-06, its CI run 91 5
# minutes (test 4), when o/r's run 90 is a rerun.
T="${dir}/t"; TG="${dir}/tgh"; mkdir -p "${T}/.swarm" "${T}/docs/stories" "${TG}/bin"; git -C "${T}" init -q
git -C "${T}" remote add origin https://github.com/o/r.git
for s in t1:e1 t3:e1 t4:e2 t5:e2 t6:e3 t7:e3; do printf -- '---\nkind: code\nstatus: ready\nepic: %s\n---\n' "${s#*:}" > "${T}/docs/stories/${s%:*}.md"; done
printf -- '---\nkind: code\nstatus: ready\n---\n' > "${T}/docs/stories/t2.md"
printf '2026-10-01\tcode\t%s\tclaude\topus\thigh\t-\n' t1 t2 t3 t4 t5 t6 t7 > "${T}/.swarm/agents.tsv"
U="${dir}/u"; mkdir -p "${U}/.swarm" "${U}/docs/stories"; git -C "${U}" init -q; git -C "${U}" remote add origin https://github.com/o/z.git
printf -- '---\nkind: code\nstatus: ready\n---\n' > "${U}/docs/stories/u1.md"; printf '2026-10-06\tcode\tu1\tclaude\topus\thigh\t-\n' > "${U}/.swarm/agents.tsv"
trun() { # <id> <head> <workflow> <event> <conclusion> <attempt> <created> — a run, as gh run list gives it
  printf '{"databaseId":%s,"headSha":"%s","workflowName":"%s","event":"%s","status":"completed","conclusion":"%s","attempt":%s,"createdAt":"%s","startedAt":"%s","updatedAt":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$7" "$7"
}
arun() { # <id> <head> <workflow> <event> <conclusion> <attempt> <created> — a run, as GitHub's REST API lists it
  printf '{"id":%s,"head_sha":"%s","name":"%s","event":"%s","status":"completed","conclusion":"%s","run_attempt":%s,"created_at":"%s"}' "$@"
}
listing() { # <created> <total_count> <run>... — GitHub's runs for that created filter, slurped into one page
  local c="$1" n="$2"; shift 2
  local IFS=,; echo "[{\"total_count\":${n},\"workflow_runs\":[$*]}]" > "${TG}/runs-${c}"
}
for n in 1 2 4 9; do echo "{\"head\":{\"ref\":\"story/$([ "${n}" = 9 ] && echo u1 || echo "t${n}")\"}}" > "${TG}/pull-${n}"; done
cp "${TG}/pull-1" "${TG}/pull-3"; cp "${TG}/pull-4" "${TG}/pull-5"; cp "${TG}/pull-4" "${TG}/pull-7"
for n in 4 5 7 9; do echo '[[{"sha":"c4"}]]' > "${TG}/commits-${n}"; done
echo "[$(trun 40 c4 CI pull_request success 1 2026-10-01T10:00:00Z)]" > "${TG}/runs-story-t4"; echo '[{"databaseId":91,"headSha":"c4","workflowName":"CI","event":"pull_request","status":"completed","conclusion":"success","attempt":1,"createdAt":"2026-10-06T10:00:00Z","startedAt":"2026-10-06T10:00:00Z","updatedAt":"2026-10-06T10:05:00Z"}]' > "${TG}/runs-story-u1"
echo '[{"jobs":[{"name":"test","run_attempt":1,"started_at":"2026-10-06T10:00:00Z","completed_at":"2026-10-06T10:04:00Z"}]}]' > "${TG}/jobs-91-1"
echo '[[{"sha":"a1"}]]' > "${TG}/commits-1"; cp "${TG}/commits-1" "${TG}/commits-3"; echo '[[{"sha":"b1"}]]' > "${TG}/commits-2"
echo "[$(trun 11 a1 CI pull_request failure 2 2026-10-01T09:00:00Z),$(trun 10 a1 CI pull_request success 2 2026-10-01T10:00:00Z)]" > "${TG}/runs-story-t1"
echo '[]' > "${TG}/runs-story-t2"
r30="$(arun 30 m1 CI push success 3 2026-10-02T09:00:00Z)"
listing 2026-10-01..2026-10-03 12 "$(arun 11 a1 CI pull_request failure 2 2026-10-01T09:00:00Z)" "$(arun 10 a1 CI pull_request success 2 2026-10-01T10:00:00Z)" \
  "$(arun 20 b1 CI pull_request failure 2 2026-10-01T10:00:00Z)" "$(arun 21 b1 CI push success 2 2026-10-01T11:00:00Z)" \
  "$(arun 22 b1 lint pull_request success 2 2026-10-01T10:00:00Z)" "$(arun 23 b1 zizmor pull_request success 1 2026-10-01T10:00:00Z)" \
  "$(arun 24 b1 CI merge_group success 4 2026-10-01T12:00:00Z)" "$(arun 25 b1 test schedule failure 3 2026-10-01T13:00:00Z)" \
  "$(arun 26 b1 docs pull_request success 2 2026-10-01T14:00:00Z)" "$(arun 27 b1 go pull_request success 2 2026-10-01T08:00:00Z)" "${r30}"
listing 2026-10-02..2026-10-03 1 "${r30}"
listing 2026-10-08..2026-10-08 5 "$(arun 60 e6 CI push success 1 2026-10-08T10:00:00Z)"   # 1 of 5 listed, none flaky
listing 2026-10-07..2026-10-07 1 "$(arun 50 e5 CI push success 2 2026-10-07T10:00:00Z)"   # its first attempt gh cannot read
listing 2026-10-06..2026-10-06 1 "$(arun 90 c9 CI push success 2 2026-10-06T10:00:00Z)"; echo '{"conclusion":"failure"}' > "${TG}/attempt-90-1"
for a in 10-1 11-1 30-1 30-2 20-1 21-1 22-1 24-1 24-3 25-1 27-1; do echo '{"conclusion":"failure"}' > "${TG}/attempt-${a}"; done
for a in 24-2 25-2; do echo '{"conclusion":"success"}' > "${TG}/attempt-${a}"; done
F=$'test-shard (1)\tRun this shard\'s tests\t2026-10-01T10:05:00Z'
printf '%s\n' "${F} "$'\xff' "${F} FAIL tests/a_test.sh 3s" "${F} FAIL a check in it" "${F} FAIL tests/a_test.sh: its job ended without a result" > "${TG}/log-10-1"
printf '%s\n' "${F} FAIL tests/c_test.sh 4s" "${F} FAIL a check: want 'FAIL tests/z_test.sh 3s', got ''" "${F}   FAIL tests/y_test.sh 3s" \
  "${F} > FAIL tests/y_test.sh 3s" > "${TG}/log-30-1"; for a in 21-1 24-1 24-3; do cp "${TG}/log-30-1" "${TG}/log-${a}"; done
printf '%s\n' "${F} FAIL tests/c_test.sh 5s" "${F} TIMEOUT tests/d_test.sh after 600s" > "${TG}/log-30-2"
printf '%s\n' "${F} FAIL tests/b_test.sh 2s" > "${TG}/log-20-1"; cp "${TG}/log-20-1" "${TG}/log-20-2"
printf '%s\n' "${F} FAIL tests/e_test.sh 2s" > "${TG}/log-11-1"; cp "${TG}/log-11-1" "${TG}/log-11-2"
printf '%s\n' "${F} FAIL tests/f_test.sh 2s" > "${TG}/log-25-1"
printf '%s\n' "${F} --- FAIL: TestThing (0.01s)" "${F} FAIL	example.com/thing	0.02s" > "${TG}/log-27-1"
# 101 reruns on 10-04, each first attempt cancelled: past flaky tests' cap of 100 gh calls. On 10-05,
# four reruns: 2003 and 2004, the newest, on one head, each a flake, 2003 on g_test.sh, and gh's rate
# limit spent on 2004's log, so 2001 and 2002 are never read.
runs=(); for i in $(seq 1000 1100); do runs+=("$(arun "${i}" "s${i}" CI push success 2 2026-10-04T10:00:00Z)"); echo '{"conclusion":"cancelled"}' > "${TG}/attempt-${i}-1"; done
listing 2026-10-04..2026-10-04 101 "${runs[@]}"
listing 2026-10-05..2026-10-05 4 "$(arun 2001 x1 CI push success 2 2026-10-05T08:00:00Z)" "$(arun 2002 x2 CI push success 2 2026-10-05T09:00:00Z)" \
  "$(arun 2003 x3 CI push success 2 2026-10-05T10:00:00Z)" "$(arun 2004 x3 CI push success 2 2026-10-05T10:30:00Z)"
for i in 2001 2002 2003 2004; do echo '{"conclusion":"failure"}' > "${TG}/attempt-${i}-1"; done
printf '%s\n' "${F} FAIL tests/g_test.sh 2s" > "${TG}/log-2003-1"
{ echo '#!/bin/sh'; echo "G=${TG}"; cat <<'EOF'; } > "${TG}/bin/gh"
echo "$*" >> "$G/gh.log"
RL="gh: API rate limit exceeded for user ID 1. (HTTP 403)"
case "$*" in
  "pr list --head story/u1"*) printf 'https://github.com/o/r/pull/9\tMERGED\t2026-10-06T12:00:00Z\t2026-10-06T10:00:00Z\t0\n' ;;
  "api repos/o/r/pulls/9") [ "${LIMITED:-}" != pulls ] || { echo "$RL" >&2; exit 1; }
    [ "${LIMITED:-}" != pull404 ] || { echo 'HTTP 404: Not Found' >&2; exit 1; }; cat "$G/pull-9" ;;
  "api --paginate --slurp repos/o/r/actions/runs/91/attempts/1/jobs?per_page=100") cat "$G/jobs-91-1" ;;
  "run view 90 "*) [ "${LIMITED:-}" != log90 ] || { echo "$RL" >&2; exit 1; }; echo 'HTTP 404: Not Found' >&2; exit 1 ;;
  "api --paginate --slurp repos/o/z/actions/runs?created="*) [ "${LIMITED:-}" != listing ] || { echo "$RL" >&2; exit 1; }; echo '[]' ;;
  "pr list --head story/t"*) printf 'https://github.com/o/r/pull/%s\tMERGED\t2026-10-01T12:00:00Z\t2026-10-01T10:00:00Z\t0\n' "${4#story/t}" ;;
  "pr view "*) echo 2026-10-01T10:00:00Z ;;
  "api repos/o/r/pulls/"*) cat "$G/pull-${2##*/}" ;;
  "api --paginate --slurp repos/o/r/pulls/"*) n="${4#repos/o/r/pulls/}"; cat "$G/commits-${n%%/*}" ;;
  "run list -R o/r --branch story/"*) cat "$G/runs-$(echo "$6" | tr / -)" ;;
  "api --paginate --slurp repos/o/r/actions/runs?created="*) c="${4#*created=}"; cat "$G/runs-${c%%&*}" 2> /dev/null || { echo 'HTTP 404: Not Found' >&2; exit 1; } ;;
  "run view 2004 "*) echo 'gh: API rate limit exceeded for user ID 1. (HTTP 403)' >&2; exit 1 ;;
  "api repos/o/r/actions/runs/"*) cat "$G/attempt-$(echo "$2" | cut -d/ -f6,8 | tr / -)" 2> /dev/null || { echo 'HTTP 404: Not Found' >&2; exit 1; } ;;
  "run view "*) cat "$G/log-$3-$7" 2> /dev/null || { echo 'HTTP 404: Not Found' >&2; exit 1; } ;;
esac
EOF
chmod +x "${TG}/bin/gh"
# shellcheck disable=SC2016 # awk's own $0
flaky() { (cd "${FP:-${T}}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=ci_health CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${TG}/bin:${PATH}" \
  bash "${SWARM}" flow "$@" 2>&1 | awk '/^## / { f = $0 == "## ci_health"; next } f' | grep -E '^(test_file|tests/|flaky tests:)'); }
FH=$'test_file\tflaky_runs\tlast_seen\texample_run'
L=https://github.com/o/r/actions/runs
: > "${TG}/gh.log"
got="$(flaky --since 2026-10-01 --until 2026-10-03)"
check "ci_health: a failed log with a byte that is not UTF-8 is still read: a_test.sh is flaky, and no line says not JSON" \
  "$(grep -E 'a_test|not JSON' <<< "${got}")" $'tests/a_test.sh\t1\t2026-10-01\t'"${L}"'/10/attempts/1'
# Under an ASCII locale (UTF-8 mode off) gh() still reads gh's output as UTF-8: é kept, a log's 0xff as
# U+FFFD. A JSON answer's 0xff still fails, so gh_cache caches nothing; one on a failed call's stderr
# keeps gh's error (and its retries).
mkdir -p "${dir}/ugh"; cat > "${dir}/ugh/gh" <<'EOF'
#!/bin/sh
case "$1" in
  json) printf '{"t": "\377"}' ;;
  502) printf 'HTTP 502 \377' >&2; exit 1 ;;
  *) printf 'caf\303\251 \377' ;;
esac
EOF
chmod +x "${dir}/ugh/gh"
check "report.gh reads gh's output as UTF-8 under a locale that is not, a log's byte that is not UTF-8 as U+FFFD, a JSON answer's as not JSON, uncached, gh's error's kept" \
  "$(LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 SWARM_SLEEP_SCALE=0 SWARM_GH_CACHE="${dir}/ucache" PATH="${dir}/ugh:${PATH}" python3 -c 'import os, sys; sys.path.insert(0, sys.argv[1]); import gh_cache, report
print(ascii(report.gh("log", parse=str)))
print(ascii(gh_cache.cached("o/r", "j", lambda: report.gh("json"), lambda v: True)), report.ERROR[0], os.path.exists(gh_cache.path("o/r", "j")))
print(ascii(report.gh("502")), ascii(report.ERROR[0]))' "$(dirname "${SWARM}")/lib")" \
  "'caf\\xe9 \\ufffd'
None gh json: an answer that is not JSON False
None 'gh 502: HTTP 502 \\ufffd'"
check "ci_health: the test files a head's red attempts failed before a green one, as the row counts flakes, a run once per file, worst first; what gh did not list or could not read is named, and logs with no test file line counted" \
  "${got}" "${FH}"$'
tests/c_test.sh\t3\t2026-10-02\t'"${L}"$'/30/attempts/1
tests/d_test.sh\t1\t2026-10-02\t'"${L}"$'/30/attempts/2
tests/f_test.sh\t1\t2026-10-01\t'"${L}"$'/25/attempts/1
tests/a_test.sh\t1\t2026-10-01\t'"${L}"$'/10/attempts/1
tests/e_test.sh\t1\t2026-10-01\t'"${L}"$'/11/attempts/1
flaky tests: gh listed 11 of the 12 runs of o/r created 2026-10-01..2026-10-03, the newest; the rest are left out
flaky tests: left out '"${L}"$'/26: gh api repos/o/r/actions/runs/26/attempts/1: HTTP 404: Not Found
flaky tests: could not read '"${L}"$'/22/attempts/1: gh run view 22 -R o/r --attempt 1 --log-failed: HTTP 404: Not Found
flaky tests: 1 of the 7 flaky runs whose failed logs were read have no FAIL or TIMEOUT tests/<file> line'
check "ci_health: the flaky tests reuse the attempts health read: runs 10's and 11's, once for each of t1's and t3's PRs" \
  "$(grep -cE '^api repos/o/r/actions/runs/1[01]/attempts/1$' "${TG}/gh.log")" 4
check "ci_health: with --epic, the flaky tests of its PRs' own runs alone, a run two PRs share once" "$(flaky --since 2026-10-01 --until 2026-10-03 --epic e1)" "${FH}"$'
tests/a_test.sh\t1\t2026-10-01\t'"${L}"$'/10/attempts/1
tests/e_test.sh\t1\t2026-10-01\t'"${L}"$'/11/attempts/1'
check "ci_health: with --epic and no flaky run, none in the runs read, a run two PRs share once" "$(flaky --since 2026-10-01 --until 2026-10-03 --epic e2)" \
  "flaky tests: none in the 1 runs read"
check "ci_health: with --epic and a PR gh cannot read, no none line" "$(flaky --since 2026-10-01 --until 2026-10-03 --epic e3)" ""
check "ci_health: with no PR in the window, the project's origin is still read" "$(flaky --since 2026-10-02 --until 2026-10-03)" "${FH}"$'
tests/d_test.sh\t1\t2026-10-02\t'"${L}"$'/30/attempts/2
tests/c_test.sh\t1\t2026-10-02\t'"${L}"$'/30/attempts/1'
check "ci_health: with no --until, runs created on --since's UTC day and after; what gh cannot list is named, and no none line after it" \
  "$(TZ=Etc/GMT-14 flaky --since 2026-10-01)" "flaky tests: left out the runs of o/r created >=2026-10-01: gh api --paginate --slurp repos/o/r/actions/runs?created=%3E%3D2026-10-01&per_page=100: HTTP 404: Not Found"
: > "${TG}/gh.log"
check "ci_health: the flaky tests stop at their cap of 100 gh invocations and say how many runs they left" "$(flaky --since 2026-10-04 --until 2026-10-04)" \
  "flaky tests: stopped at its cap of 100 gh invocations: 2 of 101 runs that may be flaky not read in full"
check "ci_health: the cap's 100 invocations: the listing and 99 runs' attempts" "$(grep -c '^api ' "${TG}/gh.log")" 100
: > "${TG}/gh.log"
check "ci_health: the flaky tests stop at gh's rate limit, keeping what they read, a group's first log too" "$(flaky --since 2026-10-05 --until 2026-10-05)" "${FH}"$'
tests/g_test.sh\t1\t2026-10-05\t'"${L}"$'/2003/attempts/1
flaky tests: stopped at gh\'s rate limit (gh: API rate limit exceeded for user ID 1. (HTTP 403)): 4 of 4 runs that may be flaky not read in full'
check "ci_health: and make no call after it" "$(grep -cE 'runs/200[12]' "${TG}/gh.log" || true)" 0
check "ci_health: a run whose attempts gh cannot read leaves no none line" "$(flaky --since 2026-10-07 --until 2026-10-07)" \
  "flaky tests: left out ${L}/50: gh api repos/o/r/actions/runs/50/attempts/1: HTTP 404: Not Found"
check "ci_health: a listing cut short leaves no none line" "$(flaky --since 2026-10-08 --until 2026-10-08)" \
  "flaky tests: gh listed 1 of the 5 runs of o/r created 2026-10-08..2026-10-08, the newest; the rest are left out"
check "ci_health: the repo of a PR gh could not read is still listed" "$(FP="${U}" LIMITED=pull404 flaky --since 2026-10-06 --until 2026-10-06)" \
  "flaky tests: could not read ${L}/90/attempts/1: gh run view 90 -R o/r --attempt 1 --log-failed: HTTP 404: Not Found"
# shellcheck disable=SC2016 # awk's own $0
check "ci_health: the flaky tests read after ci time, so a rate limit they hit leaves its table whole" \
  "$(cd "${U}" && env -u HERDR_ENV -u SWARM_PROJECT LIMITED=log90 SWARM_FLOW_SECTIONS=ci_health CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${TG}/bin:${PATH}" \
    bash "${SWARM}" flow --since 2026-10-06 --until 2026-10-06 2>&1 | awk '/^## / { f = $0 == "## ci_health"; next } f' | grep -E '^(o/r'$'\t''|ci time:|flaky tests: stopped)')" \
  $'o/r\t1\t5.0\ttest\t4.0\t0\t\t\t\t\nflaky tests: stopped at gh\'s rate limit (gh: API rate limit exceeded for user ID 1. (HTTP 403)): 1 of 1 runs that may be flaky not read in full'
check "ci_health: a rate limit while listing a later repo keeps the earlier repo's runs, and says which repo it did not list" \
  "$(FP="${U}" LIMITED=listing flaky --since 2026-10-06 --until 2026-10-06)" \
  "flaky tests: stopped at gh's rate limit (gh: API rate limit exceeded for user ID 1. (HTTP 403)): the runs of o/z not listed; 1 of 1 runs that may be flaky not read in full"
check "ci_health: a rate limit health spent leaves the listings unread, and no none line" "$(FP="${U}" LIMITED=pulls flaky --since 2026-10-06 --until 2026-10-06)" \
  "flaky tests: stopped at gh's rate limit (gh: API rate limit exceeded for user ID 1. (HTTP 403)): the runs of o/r, o/z not listed"

# idle_slots: e9's conductor runs from 09:00; its story ia is ready at 10:00 (unblock) and built at 10:10,
# while ib builds 09:30-11:00 (its close). Epic e10 has no conductor: ic is ready 12:00, built 12:20.
# ib's agents.tsv day is the 30th, so --since 2026-10-01 leaves it out of flow's windowed stories.
I="${dir}/idle"; mkdir -p "${I}/.swarm" "${I}/docs/stories"; git -C "${I}" init -q
ist() { printf -- '---\nkind: code\nstatus: ready\nepic: %s\ntouches: [%s]\n---\n' "$2" "$3" > "${I}/docs/stories/$1.md"; }
ist ia e9 src/a.sh; ist ib e9 src/b.sh; ist ic e10 src/c.sh
mkdir -p "${I}/docs/epics"   # every epic here is active but e14 (later) and e26 (split)
for e in e9 e10 e11 e12 e13 e15 e16 e17 e18 e19 e20 e21 e22 e23 e24 e25 e28 e29 e30 e31 e32 e33 e34 e35 e36 e37; do printf -- '---\nstatus: active\n---\n' > "${I}/docs/epics/${e}.md"; done
mkdir -p "${I}/.swarm/board-state/stories"; echo 'status: review' > "${I}/.swarm/board-state/stories/ib"   # closed: in review
for x in ia:10:10 ib:09:30 ic:12:20; do
  printf '{"cwd":"%s/idle-wt/%s","timestamp":"2026-10-01T%s:00Z"}\n{"timestamp":"2026-10-01T%s:00Z"}\n' "${dir}" "${x%%:*}" "${x#*:}" "${x#*:}" \
    > "${dir}/projects/p/s${x%%:*}.jsonl"
done
printf '%s\n' "2026-10-01${B}ia${O}sia" "2026-09-30${B}ib${O}sib" "2026-10-01${B}ic${O}sic" > "${I}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T09:00:00Z\tconduct\te9\tw:1\tok' $'2026-10-01T10:00:00Z\tunblock\tia\tw:1\tok' \
  $'2026-10-01T11:00:00Z\tclose\tib\tw:1\tok' $'2026-10-01T12:00:00Z\tunblock\tic\tw:1\tok' > "${I}/.swarm/events.tsv"
idle() { (cd "${I}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=idle_slots CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
  bash "${SWARM}" flow "$@" 2>&1 | grep -v -e '^## idle_slots$' -e '^sed: '); }   # sed warns on a byte that is not UTF-8
IH=$'epic\tidle_min\tno_conductor_min\tmost_ready'
check "idle_slots: a ready story with no build under its conductor is idle; one with no conductor counts under no conductor" \
  "$(idle)" "${IH}"$'\ne10\t0\t20\t1\ne9\t10\t0\t1\nall\t10\t20\t1'
check "idle_slots: --epic prints that epic's row alone" "$(idle --epic e9)" "${IH}"$'\ne9\t10\t0\t1'
ist ia e9 src/a.sh:f; ist ib e9 "src/b.sh, src/a.sh:f"
check "idle_slots: a ready story that clashes with a running build (touches) is not idle, a build from before --since too" \
  "$(idle --since 2026-10-01 --epic e9)" "${IH}"$'\ne9\t0\t0\t1'
# id, on the board as ready since its unblock at 13:00 and never built, waits to --until's midnight: 11 hours.
ist id e9 src/d.sh; printf '%s\n' $'2026-10-01T13:00:00Z\tunblock\tid\tw:1\tok' >> "${I}/.swarm/events.tsv"
check "idle_slots: a story ready on the board with no build yet is idle to the window's end" "$(idle --until 2026-10-01 --epic e9)" "${IH}"$'\ne9\t660\t0\t1'
# ie's file says blocked, but its board-state says ready, so it waits beside id. ig builds from 13:00
# on, never closed, touching src/d.sh in repo other: no clash with id's and ie's src/d.sh here.
printf -- '---\nkind: code\nstatus: blocked\nepic: e9\ntouches: [src/d.sh]\n---\n' > "${I}/docs/stories/ie.md"
echo 'status: ready' > "${I}/.swarm/board-state/stories/ie"
printf '%s\n' $'2026-10-01T13:00:00Z\tunblock\tie\tw:1\tok' >> "${I}/.swarm/events.tsv"
printf -- '---\nkind: code\nstatus: ready\nepic: e9\nrepo: other\ntouches: [src/d.sh]\n---\n' > "${I}/docs/stories/ig.md"
printf '{"cwd":"%s/idle-wt/ig","timestamp":"2026-10-01T13:00:00Z"}\n' "${dir}" > "${dir}/projects/p/sig.jsonl"
printf '%s\n' "2026-10-01${B}ig${O}sig" >> "${I}/.swarm/agents.tsv"
check "idle_slots: a story readied in board-state counts as ready; the same file in another repo is no clash" \
  "$(idle --until 2026-10-01 --epic e9)" "${IH}"$'\ne9\t660\t0\t2'
# ih (e11, no conductor) was unblocked at 09:00, but the board's commit readying it at 20:00 is later: 4 hours, not 15.
printf '%s\n' $'2026-10-01T09:00:00Z\tunblock\tih\tw:1\tok' >> "${I}/.swarm/events.tsv"; ist ih e11 src/h.sh
git -C "${I}" add docs/stories/ih.md
GIT_COMMITTER_DATE=2026-10-01T20:00:00Z git -C "${I}" -c user.name=t -c user.email=t@t commit -qm ih --date 2026-10-01T20:00:00Z
check "idle_slots: a story is ready from the later of its unblock and the board's commit to its status" \
  "$(idle --until 2026-10-01 --epic e11)" "${IH}"$'\ne11\t0\t240\t1'
# ij (e12, no conductor) is committed ready on a side branch at 18:00 and merged at 22:00: it waits 2 hours, not 6.
ist ij e12 src/j.sh; git -C "${I}" add docs/stories/ij.md
tree="$(git -C "${I}" write-tree)"; head="$(git -C "${I}" rev-parse HEAD)"
commit_at() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "${I}" -c user.name=t -c user.email=t@t commit-tree "${tree}" "${@:2}"; }
side="$(commit_at 2026-10-01T18:00:00Z -p "${head}" -m ij)"
git -C "${I}" update-ref HEAD "$(commit_at 2026-10-01T22:00:00Z -p "${head}" -p "${side}" -m merge)"
check "idle_slots: a story readied on a board branch is ready from the merge, not the branch commit" \
  "$(idle --until 2026-10-01 --epic e12)" "${IH}"$'\ne12\t0\t120\t1'
# il (e13, no conductor), unblocked 13:50 and built 14:00, is sent back to ready by its close at 15:00
# (close --drop leaves no unblock or board commit): 10 minutes, then 15:00 to midnight.
ist il e13 src/l.sh
printf '{"cwd":"%s/idle-wt/il","timestamp":"2026-10-01T14:00:00Z"}\n' "${dir}" > "${dir}/projects/p/sil.jsonl"
printf '%s\n' "2026-10-01${B}il${O}sil" >> "${I}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T13:50:00Z\tunblock\til\tw:1\tok' $'2026-10-01T15:00:00Z\tclose\til\tw:1\tok' >> "${I}/.swarm/events.tsv"
check "idle_slots: a story a close sent back to ready waits again from that close" \
  "$(idle --until 2026-10-01 --epic e13)" "${IH}"$'\ne13\t0\t550\t1'
# in is ready from 23:00, but its epic e14 is later: no conductor will run it.
ist in e14 src/n.sh; printf -- '---\nstatus: later\n---\n' > "${I}/docs/epics/e14.md"
printf '%s\n' $'2026-10-01T23:00:00Z\tunblock\tin\tw:1\tok' >> "${I}/.swarm/events.tsv"
check "idle_slots: a ready story in a later epic is not waiting" "$(idle --until 2026-10-01 --epic e14)" "no story of epic e14 was ready in the window"
# io (e15) is unblocked at 10:00 and its build has no session log yet: built, not waiting.
ist io e15 src/o.sh; printf '%s\n' "2026-10-01${B}io${O}-" >> "${I}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T10:00:00Z\tunblock\tio\tw:1\tok' >> "${I}/.swarm/events.tsv"
check "idle_slots: a build with no session log still counts as a build" "$(idle --until 2026-10-01 --epic e15)" "no story of epic e15 was ready in the window"
# ip (e16)'s log-less build is closed at 15:00, sending it back to ready: it waits from then to midnight.
ist ip e16 src/p.sh; printf '%s\n' "2026-10-01${B}ip${O}-" >> "${I}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T10:00:00Z\tunblock\tip\tw:1\tok' $'2026-10-01T15:00:00Z\tclose\tip\tw:1\tok' >> "${I}/.swarm/events.tsv"
check "idle_slots: a close after a build with no session log sends its story back to ready" \
  "$(idle --until 2026-10-01 --epic e16)" "${IH}"$'\ne16\t0\t540\t1'
sl() { printf '{"cwd":"%s/idle-wt/%s","timestamp":"2026-10-01T%s:00Z"}\n' "${dir}" "$2" "$3" > "${dir}/projects/p/s$1.jsonl"; } # <session> <slug> <HH:MM>
ag() { printf '%s\n' "2026-10-01${B}$1${O}$2" >> "${I}/.swarm/agents.tsv"; }                                        # <slug> <session or ->
ev() { printf '2026-10-01T%s:00Z\t%s\t%s\tw:1\t%s\n' "$1" "$2" "$3" "${4:-ok}" >> "${I}/.swarm/events.tsv"; }        # <HH:MM> <command> <slug> [outcome]
# it (e17) builds 10:00-11:00, then again with no session log: that retry starts when the build before
# ended, not at 00:00, so iu, clashing with it and waiting 12:00-12:10, is not idle.
ist it e17 src/t.sh; ist iu e17 src/t.sh; sl it it 10:00; sl iu iu 12:10; ag it sit; ag it -; ag iu siu
ev 11:00 close it; ev 12:00 unblock iu
check "idle_slots: a same-day retry with no session log keeps its order after the build it followed" \
  "$(idle --until 2026-10-01 --epic e17)" "${IH}"$'\ne17\t0\t0\t1'
# iy (e21) builds at 10:00, fails at 15:00, and retries with no session log: built, not waiting.
ist iy e21 src/y.sh; sl iy iy 10:00; ag iy siy; ag iy -; ev 09:00 unblock iy; ev 15:00 close iy
check "idle_slots: a retry with no session log after a close that sent its story back is a build" \
  "$(idle --until 2026-10-01 --epic e21)" "${IH}"$'\ne21\t0\t60\t1'
# iz (e22) waits 09:00-10:00, builds, fails at 11:00 and waits again until its retry at 13:00.
ist iz e22 src/z.sh; sl iz1 iz 10:00; sl iz2 iz 13:00; ag iz siz1; ag iz siz2; ev 09:00 unblock iz; ev 11:00 close iz
check "idle_slots: each wait counts, the one between a failed build and its retry too" \
  "$(idle --until 2026-10-01 --epic e22)" "${IH}"$'\ne22\t0\t180\t1'
# iv (e18) waits 09:00-10:00, builds, is reviewed at 11:00 and its builder closed at 12:00: in review,
# not ready. Its story says ready with no event to date it, so only that first wait counts; a
# reconcile that reopens it at 20:00 readies it from then.
ist iv e18 src/v.sh; sl iv iv 10:00; ag iv siv; ev 09:00 unblock iv; ev 11:00 review iv "ok (https://github.com/o/r/pull/9)"; ev 12:00 close iv
check "idle_slots: the close after a review leaves the story in review, not ready" "$(idle --until 2026-10-01 --epic e18)" "${IH}"$'\ne18\t0\t60\t1'
ev 20:00 reconcile iv 'ok (reopened)'
check "idle_slots: a reconcile that reopens a story readies it" "$(idle --until 2026-10-01 --epic e18)" "${IH}"$'\ne18\t0\t300\t1'
# iw (e19) the same, reset at 22:00; ix (e20) the same, dropped by a second close at 13:00.
ist iw e19 src/w.sh; sl iw iw 10:00; ag iw siw; ev 09:00 unblock iw; ev 11:00 kept iw "ok (https://github.com/o/r/pull/9)"; ev 12:00 close iw
check "idle_slots: the close after a kept event leaves the story in review" "$(idle --until 2026-10-01 --epic e19)" "${IH}"$'\ne19\t0\t60\t1'
ev 22:00 reset:held iw 'ok (lifted)'
check "idle_slots: a reset readies a story" "$(idle --until 2026-10-01 --epic e19)" "${IH}"$'\ne19\t0\t180\t1'
ist ix e20 src/x.sh; sl ix ix 10:00; ag ix six; ev 09:00 unblock ix; ev 11:00 review ix "ok (https://github.com/o/r/pull/9)"; ev 12:00 close ix; ev 13:00 close ix
check "idle_slots: a second close after a review (the drop) sends the story back to ready" \
  "$(idle --until 2026-10-01 --epic e20)" "${IH}"$'\ne20\t0\t720\t1'
# jq (e23, repo other) waits 10:00-10:30 touching src/q.sh and Makefile, a file in repo other under the
# repos dir, while jr (repo other) builds 09:00-12:00 touching Makefile: a clash.
mkdir -p "${dir}/other"; : > "${dir}/other/Makefile"
for x in jq:'src/q.sh, Makefile' jr:Makefile; do
  printf -- '---\nkind: code\nstatus: ready\nepic: e23\nrepo: other\ntouches: [%s]\n---\n' "${x#*:}" > "${I}/docs/stories/${x%%:*}.md"
done
sl jq jq 10:30; sl jr jr 09:00; ag jq sjq; ag jr sjr; ev 10:00 unblock jq; ev 12:00 close jr
check "idle_slots: touches resolve a bare file under the repos dir, as the clash rule does" \
  "$(idle --until 2026-10-01 --epic e23)" "${IH}"$'\ne23\t0\t0\t1'
# ka (e24) builds from 10:00 with no close; its PR closed unmerged and reconcile reopened it at 11:00
# while that build still runs: not waiting.
ist ka e24 src/ka.sh; sl ka ka 10:00; ag ka ska; ev 11:00 reconcile ka 'ok (reopened)'
check "idle_slots: a story whose own build still runs is not waiting" "$(idle --until 2026-10-01 --epic e24)" "no story of epic e24 was ready in the window"
# kb (e25) is of a kind no agent builds, kc's epic e26 is split, kd's epic e27 has no file: next builds none of them.
printf -- '---\nkind: research\nstatus: ready\nepic: e25\ntouches: [src/kb.sh]\n---\n' > "${I}/docs/stories/kb.md"
ist kc e26 src/kc.sh; printf -- '---\nstatus: split\n---\n' > "${I}/docs/epics/e26.md"; ist kd e27 src/kd.sh
ev 23:00 unblock kb; ev 23:00 unblock kc; ev 23:00 unblock kd
check "idle_slots: a ready story next would not build (another kind, an epic not active or missing) is not waiting" \
  "$(for e in e25 e26 e27; do idle --until 2026-10-01 --epic "${e}"; done)" "$(for e in e25 e26 e27; do echo "no story of epic ${e} was ready in the window"; done)"
# ma (e28) builds from 09:00 and merges at 10:00: reconcile closes its builder and logs only its finish.
# mb, clashing with it, waits 10:00-10:30 with nothing running.
ist ma e28 src/m.sh; ist mb e28 src/m.sh; sl ma ma 09:00; sl mb mb 10:30; ag ma sma; ag mb smb
ev 10:00 reconcile ma 'ok (finished by its PR)'; ev 10:00 unblock mb
check "idle_slots: reconcile's finish ends a merged story's build" "$(idle --until 2026-10-01 --epic e28)" "${IH}"$'\ne28\t0\t30\t1'
# mc (e29): its kept event and its builder's close share 11:00:00, and close --drop at 13:00 sends it back.
ist mc e29 src/mc.sh; sl mc mc 10:00; ag mc smc; ev 09:00 unblock mc; ev 11:00 kept mc "ok (https://github.com/o/r/pull/9)"; ev 11:00 close mc; ev 13:00 close mc
check "idle_slots: a kept event and its close in one second, then the drop, send the story back" \
  "$(idle --until 2026-10-01 --epic e29)" "${IH}"$'\ne29\t0\t720\t1'
# md (e30) builds at 10:00; two closes in one second (11:00) end it and its log-less retry, so me,
# clashing with md and waiting 12:00-12:20, is not blocked. md waits again from 11:00 (the retry
# that close ended is no build since), until me's build, clashing with it, starts at 12:20.
ist md e30 src/md.sh; ist me e30 src/md.sh; sl md md 10:00; sl me me 12:20; ag md smd; ag md -; ag me sme
ev 11:00 close md; ev 11:00 close md; ev 12:00 unblock me
check "idle_slots: two closes in one second end two builds" "$(idle --until 2026-10-01 --epic e30)" "${IH}"$'\ne30\t0\t80\t2'
# mf (e31) builds 10:00, closes at 11:00 and retries in that same second, closing at 12:00, then goes
# to review. mg, clashing with mf and waiting 11:10-11:20, is blocked by the retry.
ist mf e31 src/mf.sh; ist mg e31 src/mf.sh; sl mf1 mf 10:00; sl mf2 mf 11:00; sl mg mg 11:20; ag mf smf1; ag mf smf2; ag mg smg
echo 'status: review' > "${I}/.swarm/board-state/stories/mf"; ev 11:00 close mf; ev 12:00 close mf; ev 11:10 unblock mg
check "idle_slots: a close at its retry's first second ends the build before it" "$(idle --until 2026-10-01 --epic e31)" "${IH}"$'\ne31\t0\t0\t1'
# mh (e32) is ready from 09:50; a build starts and closes at 10:00, sending it back: it waits again from then.
ist mh e32 src/mh.sh; sl mh mh 10:00; ag mh smh; ev 09:50 unblock mh; ev 10:00 close mh
check "idle_slots: a build the readying close ended, however short, is no build since" "$(idle --until 2026-10-01 --epic e32)" "${IH}"$'\ne32\t0\t850\t1'
# A story whose slug runs past 32 characters (e33), unblocked at 10:00, builds with no session log:
# agents.tsv keeps agent_name's cut of it. It is built, not waiting.
long="a-story-whose-slug-runs-past-thirty-two"; ist "${long}" e33 src/long.sh; ag "${long:0:32}" -; ev 10:00 unblock "${long}"
check "idle_slots: a long slug's log-less build is its own build" "$(idle --until 2026-10-01 --epic e33)" "no story of epic e33 was ready in the window"
# mi (e34) is reset at 10:00, with no unblock, and first built at 10:10: it waited those 10 minutes.
ist mi e34 src/mi.sh; sl mi mi 10:10; ag mi smi; ev 10:00 reset mi 'ok (retry)'
check "idle_slots: a reset before a story's first build starts that wait" "$(idle --until 2026-10-01 --epic e34)" "${IH}"$'\ne34\t0\t10\t1'
# A merged story whose slug runs past 32 characters (e35) built first with no session log (agents.tsv's
# cut name, closed 10:00), then from 10:00 with one. mj, clashing with it, waits 11:00-11:30: blocked.
long2="another-story-whose-slug-is-over-32"; ist "${long2}" e35 src/long2.sh; ist mj e35 src/long2.sh
git -C "${I}" add "docs/stories/${long2}.md"; git -C "${I}" -c user.name=t -c user.email=t@t commit -qm "${long2}"
git -C "${I}" rm -q "docs/stories/${long2}.md"; git -C "${I}" -c user.name=t -c user.email=t@t commit -qm "${long2} merged"
sl long2 "${long2}" 10:00; sl mj mj 11:30; ag "${long2:0:32}" -; ag "${long2:0:32}" slong2; ag mj smj
ev 10:00 close "${long2:0:32}"; ev 11:00 unblock mj
check "idle_slots: a merged long slug's touches are read by its full slug, whichever build named it first" \
  "$(idle --until 2026-10-01 --epic e35)" "${IH}"$'\ne35\t0\t0\t1'
# mk (e36) builds first with no session log, closed at 11:00, and again from 13:00 with one: one
# story waiting 11:00-13:00, counted once.
ist mk e36 src/mk.sh; sl mk mk 13:00; ag mk -; ag mk smk; ev 11:00 close mk
check "idle_slots: a wait two spans cover counts its story once" "$(idle --until 2026-10-01 --epic e36)" "${IH}"$'\ne36\t0\t120\t1'
# A story whose slug runs past 32 characters (e37) builds with no session log (no epic in outcomes'
# row) and closes at 11:00, back to ready: it waits from then, under its board epic.
long3="a-third-story-whose-slug-is-over-32"; ist "${long3}" e37 src/long3.sh; ag "${long3:0:32}" -; ev 11:00 close "${long3:0:32}"
check "idle_slots: a long slug with a log-less build keeps its board epic" "$(idle --until 2026-10-01 --epic e37)" "${IH}"$'\ne37\t0\t780\t1'
# On the 2nd, with the board's ready stories gone: the backlog's ik (no epic) is ready from 10:00 under
# the backlog conductor (09:00 on); epic backlog-cleanup's conductor closing at 12:00 does not end it.
# im, built 11:00-11:30 and touching ik's file, is a merged story whose text has a byte that is not UTF-8.
# It has no status line, so outcomes' board log, which reads -G^status: patches and would fail on
# that byte, never prints its commits.
rm "${I}"/docs/stories/*.md
printf -- '---\nkind: code\nstatus: ready\ntouches: [src/k.sh]\n---\n' > "${I}/docs/stories/ik.md"
printf -- '---\nkind: code\ntouches: [src/k.sh]\n---\n\xff\n' > "${I}/docs/stories/im.md"
git -C "${I}" add docs/stories/im.md; git -C "${I}" -c user.name=t -c user.email=t@t commit -qm im
git -C "${I}" rm -q docs/stories/im.md; git -C "${I}" -c user.name=t -c user.email=t@t commit -qm 'im merged'
printf '{"cwd":"%s/idle-wt/im","timestamp":"2026-10-02T11:00:00Z"}\n' "${dir}" > "${dir}/projects/p/sim.jsonl"
printf '%s\n' "2026-10-01${B}im${O}sim" >> "${I}/.swarm/agents.tsv"   # dated the 1st: flow's own sed never reads its text
printf '%s\n' $'2026-10-02T09:00:00Z\tconduct\t--backlog\tw:1\tok' $'2026-10-02T10:00:00Z\tunblock\tik\tw:1\tok' \
  $'2026-10-02T11:30:00Z\tclose\tim\tw:1\tok' $'2026-10-02T12:00:00Z\tclose\tconduct-backlog-cleanup\tw:1\tok' >> "${I}/.swarm/events.tsv"
check "idle_slots: only the backlog's own conductor ends its run, and a merged story's bytes that are not UTF-8 still read" \
  "$(idle --since 2026-10-02 --until 2026-10-02)" "${IH}"$'\nall\t810\t0\t1'

# A git that refuses show: im's text is lost, so it clashes with nothing (14 hours idle), and idle_slots says so once.
mkdir -p "${dir}/gitfail"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\nfor a; do [ "$a" = show ] && { echo "fatal: show refused" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$(command -v git)" > "${dir}/gitfail/git"
chmod +x "${dir}/gitfail/git"
out="$(cd "${I}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=idle_slots CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/gitfail:${dir}/bin:${PATH}" \
  bash "${SWARM}" flow --since 2026-10-02 --until 2026-10-02 2>&1)"
check "idle_slots: a git call that fails warns once on stderr" \
  "$(grep -c '^warning: idle_slots: git show in .* failed (fatal: show refused): what it reads is left out$' <<< "${out}"; grep '^all' <<< "${out}")" $'1\nall\t840\t0\t1'

check "idle_slots: with nothing ready, a line says so in place of a zero row" \
  "$(idle --since 2026-09-01 --until 2026-09-01; idle --since 2026-10-02 --epic nope)" $'no story was ready in the window\nno story of epic nope was ready in the window'

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
