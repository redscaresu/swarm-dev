#!/usr/bin/env bash
# dataset_test.sh — `swarm.sh dataset` against a fixture of three merged stories: easy-ok (in no epic,
# planned easy, and was: one build, no findings round, a small diff, and only another repo's PR 2 named
# after it), easy-hard (planned easy, but took two findings rounds and a fix two days after its merge)
# and escalated (sonnet, stepped up to opus, escalated to fable, with an escaped finding three days
# after its merge). gh is a stub on PATH that gives each PR's files; git holds the plan and the later
# fixes. A planted env value and transcript line must reach no line of the output.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
dir="$(cd "${dir}" && pwd -P)"
P="${dir}/repo"; U=https://github.com/o/r/pull
PLANT_ENV="planted-env-value-7f3a"; PLANT_LINE="planted transcript line 9c1e"
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${P}/src" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
commit() { # <UTC time> <message>
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$2"
}
lines() { seq "$1" > "${P}/src/$2"; }   # <n> <file>: a file of n lines

echo .swarm/ > "${P}/.gitignore"; echo "# Stories" > "${P}/docs/stories/README.md"
printf -- '---\nkind: code\neasy: true\nestimate_lines: 40\ndepends_on: []\ntouches: [src/a (new)]\n---\n\n# Easy ok\n' > "${P}/docs/stories/easy-ok.md"
printf -- '---\nkind: code\nepic: e1\neasy: true\nestimate_lines: 30\ndepends_on: [easy-ok]\ntouches: [src/b:f (x, y), src/c]\n---\n\n# Easy hard\n' > "${P}/docs/stories/easy-hard.md"
printf -- '---\nkind: code\nrisk: high\nepic: e0\neasy: false\nestimate_lines: 200\ndepends_on: []\ntouches: [src/c]\n---\n\n# Escalated\n' > "${P}/docs/stories/escalated.md"
mkdir -p "${P}/docs/epics" && printf -- '---\nstatus: active\n---\n\n# e0\n' > "${P}/docs/epics/e0.md"
git -C "${P}" add -A && commit 2026-10-01T08:00:00Z "Plan e0 and e1 (#1)"
# A later edit of the plan (attempts:, a changed estimate): the dataset reads the story as planned.
sed -i.bak 's/^estimate_lines: 40$/estimate_lines: 999/' "${P}/docs/stories/easy-ok.md" && rm "${P}/docs/stories/easy-ok.md.bak"
git -C "${P}" add -A && commit 2026-10-01T12:00:00Z "Re-plan easy-ok"
# easy-ok's PR was rebased onto main: its commit names no PR, so its diff and merge commit come from gh.
lines 10 a; git -C "${P}" rm -q docs/stories/easy-ok.md; git -C "${P}" add -A && commit 2026-10-02T10:00:00Z "Add a"
lines 12 a; git -C "${P}" add -A && commit 2026-10-02T12:00:00Z "Fix the bump for https://github.com/other/dep/pull/2 and other/dep#2 (#7)"
# A PR stacked on #2: its body names #2 only to say what it waits on, or for background, so it is no
# fix of #2.
lines 13 a; git -C "${P}" add -A && commit 2026-10-02T13:00:00Z "$(printf 'Stacked story (#8)\n\nMerge after https://github.com/o/r/pull/2, which it fixes the order of\nDepends on #2 (a fix)\nStacked on o/r#2 to fix nothing\nSee #2 for the background.\n\nFixes a typo in the README.')"
lines 20 b; git -C "${P}" rm -q docs/stories/easy-hard.md; git -C "${P}" add -A && commit 2026-10-03T10:00:00Z "Easy hard (#3)"
lines 21 b; git -C "${P}" add -A && commit 2026-10-05T10:00:00Z "Fix the regression from #3 (#4)"
lines 150 c; git -C "${P}" rm -q docs/stories/escalated.md docs/epics/e0.md; git -C "${P}" add -A && commit 2026-10-06T10:00:00Z "Escalated (#5)"
lines 11 a; git -C "${P}" add -A && commit 2026-10-12T10:00:00Z "Fix a typo from #2, ten days on (#6)"

session() { # <slug> <model> [extra line] — a session log: worktree cwd, a timestamp TS, 1M input tokens, its PR
  printf '{"type":"user","cwd":"%s/repo-wt/%s","timestamp":"%s"}\n' "${dir}" "$1" "${TS}"
  printf '{"message":{"id":"m-%s-%s","model":"%s","usage":{"input_tokens":1000000,"output_tokens":0}}}\n' "$1" "${TS}" "$2"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "${PR}"
  [[ -z "${3:-}" ]] || printf '%s\n' "$3"
}
lead() { # <epic> — a plan-epic lead's session log, its brief naming the epic
  printf '{"type":"user","cwd":"%s","message":{"content":"You are scoping docs/epics/%s.md; read it first."}}\n' "${P}" "$1"
}
lead e0 > "${dir}/projects/p/l0.jsonl"; lead e1 > "${dir}/projects/p/l1.jsonl"
PR="${U}/2" TS=2026-10-02T09:00:00Z session easy-ok claude-sonnet-5-5 > "${dir}/projects/p/s1.jsonl"
PR="${U}/3" TS=2026-10-03T08:00:00Z session easy-hard claude-opus-5-5 \
  "{\"type\":\"user\",\"message\":{\"content\":\"${PLANT_LINE} SECRET=${PLANT_ENV}\"}}" > "${dir}/projects/p/s2.jsonl"
PR="${U}/5" TS=2026-10-04T09:00:00Z session escalated claude-sonnet-5-5 > "${dir}/projects/p/s3.jsonl"
PR="${U}/5" TS=2026-10-05T09:00:00Z session escalated claude-opus-5-5 > "${dir}/projects/p/s4.jsonl"
PR="${U}/5" TS=2026-10-05T12:00:00Z session escalated claude-fable-5-1 > "${dir}/projects/p/s5.jsonl"
printf '%s\n' \
  $'2026-09-30\tlead\tlead\tclaude\tsonnet\thigh\tl0' \
  $'2026-09-30\tlead\tlead\tclaude\topus\thigh\tl1' \
  $'2026-10-02\tcode-sonnet\teasy-ok\tclaude\tsonnet\tmedium\ts1' \
  $'2026-10-03\tcode\teasy-hard\tclaude\topus\thigh\ts2' \
  $'2026-10-04\tcode-sonnet\tescalated\tclaude\tsonnet\tmedium\ts3' \
  $'2026-10-05\tcode\tescalated\tclaude\topus\thigh\ts4' \
  $'2026-10-05\tescalate\tescalated\tclaude\tfable\txhigh\ts5' > "${P}/.swarm/agents.tsv"
printf '%s\n' \
  $'2026-10-02T00:00:00Z\treset\tother\tw:1\tSECRET='"${PLANT_ENV} ${PLANT_LINE}" \
  $'2026-10-03T09:00:00Z\ttell:findings\teasy-hard\tw:1\tok' \
  $'2026-10-03T09:30:00Z\ttell:findings\teasy-hard\tw:1\tok' \
  $'2026-10-04T15:00:00Z\tescalate\tescalated\tw:1\tok (findings-3: sonnet -> opus)' \
  $'2026-10-05T11:59:00Z\tescalate\tescalated\tw:1\tok (attempt 3)' \
  $'2026-10-05T12:30:00Z\tescalate\tescalated\tw:1\trefused '"${PLANT_ENV}" > "${P}/.swarm/events.tsv"
# The first row's day is impossible: it is skipped, never a crash.
printf '%s\n' \
  $'2026-02-30\tmissing-check\to/r#5\tan impossible day\tescaped\tescaped' \
  $'2026-10-03\tvacuous-test\to/r#3\ta\tfixed\tcodex' \
  $'2026-10-03\tnaming\to/r#3\tb\tdeclined\tcodex\tnit' \
  $'2026-10-09\tmissing-check\to/r#5\tc\tescaped\tescaped' > "${P}/.swarm/findings.tsv"
# gh answers pr list from the case below, and pr view from prs/<n>.json: the PR's files and merge commit.
mkdir -p "${dir}/prs"
view() { # <n> <merge commit subject> <path:additions:deletions>...
  local f files=""
  for f in "${@:3}"; do IFS=: read -r p a d <<< "${f}"; files+="${files:+,}{\"path\":\"${p}\",\"additions\":${a},\"deletions\":${d}}"; done
  printf '{"files":[%s],"mergeCommit":{"oid":"%s"}}\n' "${files}" "$(git -C "${P}" log --format=%H --fixed-strings --grep "$2" -1)" > "${dir}/prs/$1.json"
}
view 2 "Add a" src/a:10:0 docs/stories/easy-ok.md:0:9
view 3 "Easy hard (#3)" src/b:20:0 docs/stories/easy-hard.md:0:9
# escalated is its epic's last story, so its PR deletes the epic too: neither board file counts.
view 5 "Escalated (#5)" src/c:150:0 docs/stories/escalated.md:0:10 docs/epics/e0.md:0:5
cat > "${dir}/bin/gh" <<STUB
#!/bin/sh
[ -z "\${GH_FAIL:-}" ] || exit 1
if [ "\$1 \$2" = "pr view" ]; then cat "${dir}/prs/\${3##*/}.json"; exit; fi
[ "\$1 \$2" = "pr list" ] || exit 1
case "\$4 \$6" in
  "story/retried merged") [ -z "\${MERGED_FAIL:-}" ] || exit 1; printf '[{"url":"${U}/22","mergedAt":"2026-10-08T10:00:00Z"}]\n'; exit ;;
  "story/retried all") printf '${U}/22\tMERGED\t2026-10-08T10:00:00Z\t2026-10-08T09:00:00Z\t0\n${U}/21\tCLOSED\t\t2026-10-07T09:00:00Z\t0\n'; exit ;;
esac
case "\$4" in
  story/easy-ok) n=2 c=2026-10-02T09:30:00Z m=2026-10-02T10:00:00Z ;;
  story/easy-hard) n=3 c=2026-10-03T08:30:00Z m=2026-10-03T10:00:00Z ;;
  story/escalated) n=5 c=2026-10-04T10:00:00Z m=2026-10-06T10:00:00Z ;;
  *) exit 0 ;;
esac
[ -z "\${BAD_MERGE:-}" ] || [ "\$n" != 2 ] || m=2026-10-02T25:00:00Z
printf '${U}/%s\tMERGED\t%s\t%s\t0\n' "\$n" "\$m" "\$c"
STUB
chmod +x "${dir}/bin/gh"

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
dataset() { # [VAR=value...] — run swarm.sh dataset with the stub gh, then print its exit status
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SECRET="${PLANT_ENV}" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" "$@" bash "${SWARM}" dataset 2>&1) && echo "exit 0" || echo "exit $?"
}
out="$(dataset)"
F="${P}/.swarm/dataset.jsonl"
check "it says what it wrote" "${out}" "$(printf 'wrote 3 finished stories to %s\nexit 0' "${F}")"
# One summary line per story: slug | inputs | results | was_easy.
summary() {
  python3 -c '
import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l); i, r = d["inputs"], d["results"]
    print(" | ".join(json.dumps(x) for x in (d["slug"], d["pr"],
      [i["kind"], i["risk"], i["touches"], i["depends_on"], i["estimate_lines"], i["easy"], i["planner_model"], i["text"].splitlines()[-1]],
      [r["diff_lines"], r["diff_files"], r["attempts"], r["findings_rounds"], r["findings_fixed"], r["rework"], r["cost_usd"], r["minutes"], r["models"]],
      r["escalations"], [d["was_easy"], d["was_easy_rule"]])))' "$1"
}
check "three lines in merge order, each with the plan as added, its results, models, escalation triggers and was_easy" "$(summary "${F}")" "$(cat <<'EOF'
"easy-ok" | "https://github.com/o/r/pull/2" | ["code", null, ["src/a (new)"], [], 40, true, null, "# Easy ok"] | [10, 1, 1, 0, 0, false, 2.0, 60, ["sonnet"]] | [] | [true, 1]
"easy-hard" | "https://github.com/o/r/pull/3" | ["code", null, ["src/b:f (x, y)", "src/c"], ["easy-ok"], 30, true, "opus", "# Easy hard"] | [20, 1, 1, 2, 1, true, 4.0, 120, ["opus"]] | [] | [false, 1]
"escalated" | "https://github.com/o/r/pull/5" | ["code", "high", ["src/c"], [], 200, false, "sonnet", "# Escalated"] | [150, 1, 3, 0, 0, true, 16.0, 2940, ["sonnet", "opus", "fable"]] | [{"at": "2026-10-04T15:00:00Z", "trigger": "findings-3", "from": "sonnet", "to": "opus"}, {"at": "2026-10-05T11:59:00Z", "trigger": "attempt 3", "from": null, "to": "fable"}] | [false, 1]
EOF
)"
check "the planted env value and transcript line appear nowhere in the output" \
  "$(grep -c -e "${PLANT_ENV}" -e "${PLANT_LINE}" "${F}" || true)" 0
check "the file is under .swarm/ and git status stays clean" "$(git -C "${P}" status --porcelain)" ""

# A merge time that does not parse leaves that story's minutes null and stops nothing.
check "a merge time that does not parse gives null minutes and still writes every line" \
  "$(dataset BAD_MERGE=1 | tail -1; python3 -c 'import json, sys; print([json.loads(l)["results"]["minutes"] for l in open(sys.argv[1])])' "${F}")" \
  "$(printf 'exit 0\n[None, 120, 2940]')"
before="$(cksum < "${F}")"
check "when gh cannot be read, it refuses, says so, and leaves the file as it was" \
  "$(dataset GH_FAIL=1; cksum < "${F}")" \
  "$(printf 'gh could not read the PRs of easy-hard, easy-ok, escalated; %s is left as it was: check gh auth status and run it again\nexit 1\n%s' "${F}" "${before}")"

# --- A story retried on two PRs whose builds left no session log, so no build owns a PR, and a story
# whose repo is not cloned here.
printf -- '---\nkind: code\neasy: true\n---\n\n# Retried\n' > "${P}/docs/stories/retried.md"
printf -- '---\nkind: code\nrepo: elsewhere\n---\n\n# Uncloned\n' > "${P}/docs/stories/uncloned.md"
git -C "${P}" add -A && commit 2026-10-07T08:00:00Z "Plan retried and uncloned (#20)"
lines 5 d; git -C "${P}" rm -q docs/stories/retried.md; git -C "${P}" add -A && commit 2026-10-08T10:00:00Z "Retried (#22)"
view 22 "Retried (#22)" src/d:5:0 docs/stories/retried.md:0:6
printf '%s\n' \
  $'2026-10-07\tcode\tretried\tclaude\topus\thigh\tgone1' \
  $'2026-10-08\tcode\tretried\tclaude\topus\thigh\tgone2' \
  $'2026-10-07\tcode\tuncloned\tclaude\topus\thigh\tgone3' >> "${P}/.swarm/agents.tsv"
retried() { grep '"slug": "retried"' "${F}" || true; }
check "a retried story whose builds own no PR reads its merged PR from gh; a story whose repo is not here is skipped, counted on stderr" \
  "$(dataset; summary "${F}" | grep '^"retried"')" \
  "$(printf '%s\n' "skipped 1 story whose repo is not here: uncloned" "wrote 4 finished stories to ${F}" "exit 0" \
    '"retried" | "https://github.com/o/r/pull/22" | ["code", null, [], [], null, true, null, "# Retried"] | [5, 1, 2, 0, 0, false, null, null, ["opus"]] | [] | [false, 1]')"
before="$(retried)"
check "when gh gives no merged PR for it, the story keeps its line from the last run" \
  "$(dataset MERGED_FAIL=1; retried)" \
  "$(printf '%s\n' "skipped 1 story whose repo is not here: uncloned" "retried: merged, but gh gave no merged PR; kept its previous line" \
    "wrote 4 finished stories to ${F}" "exit 0" "${before}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
