#!/usr/bin/env bash
# dataset_test.sh — `swarm.sh dataset` against a fixture of three merged stories: easy-ok (in no epic,
# planned easy, and was: one build, no findings round, a small diff, and only another repo's PR 2 named
# after it), easy-hard (planned easy, but took two findings rounds and a fix two days after its merge)
# and escalated (sonnet, stepped up to opus, escalated to fable, with an escaped finding three days
# after its merge). gh is a stub on PATH that gives each PR's files; git holds the plan and the later
# fixes (tests/fixtures/dataset.sh builds it all). A planted env value and transcript line must reach
# no line of the output.
set -euo pipefail
export TZ=UTC

dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
dir="$(cd "${dir}" && pwd -P)"
# shellcheck source=fixtures/dataset.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "$(dirname "${BASH_SOURCE[0]}")/fixtures/dataset.sh" "${dir}"

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
