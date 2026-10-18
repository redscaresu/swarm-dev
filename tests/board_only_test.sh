#!/usr/bin/env bash
# board_only_test.sh — scripts/board-only.sh on a fixture git repo: board-only for board/ paths only
# (not a board README), fast-path for a version-only plugin.json bump on main's latest, green commit,
# and the full suite for anything else, a change to the gate's own files included. Then ci.yml: only
# the gated jobs may read checks and statuses, each one's checkout fetches the base, every step after
# the gate runs only when the gate says no, and shellcheck covers the script. Last, the gate step run
# as ci.yml has it: the base's copy of the gate judges the PR, or the PR's when the base has none. gh
# is a stub on PATH answering main's latest commit from ${FX}/tip and each commit's check runs from
# ${FX}/<sha>.checks.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${REPO}/scripts/board-only.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
G="${tmp}/repo"; FX="${tmp}/fx"; SH="${GATE}"; fails=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

check() { # <name> <cond...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

mkdir -p "${tmp}/bin" "${tmp}/runner" "${FX}"
cat > "${tmp}/bin/gh" <<STUB
#!/usr/bin/env bash
FX="${FX}"
STUB
cat >> "${tmp}/bin/gh" <<'STUB'
case "$*" in
  "api repos/o/r/commits/main --jq .sha") cat "${FX}/tip" 2>/dev/null || { echo "gh: HTTP 502" >&2; exit 1; } ;;
  "api --paginate repos/o/r/commits/"*"/check-runs?per_page=100")
    a="$*"; sha="${a#*/commits/}"; cat "${FX}/${sha%%/*}.checks" 2>/dev/null || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "api --paginate repos/o/r/commits/"*"/status?per_page=100") echo '{"total_count":0,"statuses":[]}' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${tmp}/bin/gh"

# main: base0 has a story, a board README, a script, plugin.json and ci_gate.py; base adds the gate.
git init -q -b main "${G}"
mkdir -p "${G}/board/stories" "${G}/bin/lib" "${G}/.claude-plugin" "${G}/scripts"
echo story > "${G}/board/stories/a.md"; echo readme > "${G}/board/stories/README.md"; echo 'echo x' > "${G}/bin/x.sh"
echo '{"name": "p", "version": "1.0.0", "description": "d"}' > "${G}/.claude-plugin/plugin.json"
cp "${REPO}/bin/lib/ci_gate.py" "${G}/bin/lib/"
git -C "${G}" add -A; git -C "${G}" commit -qm base0
BASE0="$(git -C "${G}" rev-parse HEAD)"
cp "${GATE}" "${G}/scripts/"
git -C "${G}" add -A; git -C "${G}" commit -qm base
BASE="$(git -C "${G}" rev-parse HEAD)"

# branch <name> <shell> [from] — a branch off [from] (the base) with <shell>'s changes committed (none
# is an empty commit).
branch() {
  git -C "${G}" checkout -q -B "$1" "${3:-${BASE}}"
  (cd "${G}" && eval "$2")
  git -C "${G}" add -A; git -C "${G}" commit -q --allow-empty -m "$1"
}
# gate [VAR=value]... — ${SH} (the gate) under bash -e on the checked-out branch, as a pull request on
# base ${BASE}; prints what it wrote to GITHUB_OUTPUT.
gate() {
  : > "${tmp}/out"
  (cd "${G}" && env PATH="${tmp}/bin:${PATH}" GITHUB_EVENT_NAME=pull_request BASE_SHA="${BASE}" GITHUB_REPOSITORY=o/r \
    GITHUB_OUTPUT="${tmp}/out" RUNNER_TEMP="${tmp}/runner" "$@" bash -e "${SH}" > "${tmp}/log" 2>&1) || echo "exit $?" >> "${tmp}/out"
  cat "${tmp}/out"
}
# shellcheck disable=SC2317,SC2329 # called through check
says() { [ "$(gate "${@:2}")" = "board_only=$1" ]; }
# shellcheck disable=SC2317,SC2329 # called through check
differ() { ! cmp -s "$1" "$2"; }
checks() { echo '{"total_count":1,"check_runs":[{"name":"test","status":"'"$2"'","conclusion":'"$3"'}]}' > "${FX}/$1.checks"; }

branch board 'echo more >> board/stories/a.md; echo new > board/stories/b.md'
check "a diff of board/ paths only is board-only" says true
check "a push event runs everything" says false GITHUB_EVENT_NAME=push
check "a failed git diff runs everything" says false BASE_SHA=dead000000000000000000000000000000000000
branch mixed 'echo more >> board/stories/a.md; echo more >> bin/x.sh'
check "a mixed diff runs everything" says false
branch out 'git mv board/stories/a.md bin/a.md'
check "a rename out of board/ runs everything" says false
branch in 'git mv bin/x.sh board/x.sh'
check "a rename into board/ runs everything" says false
branch empty ':'
check "an empty diff runs everything" says false
branch readme 'echo more >> board/stories/README.md'
check "a change to board/stories/README.md runs everything" says false
branch epics 'mkdir board/epics && echo readme > board/epics/README.md'
check "a change to board/epics/README.md runs everything" says false

# A gate whose case arm takes every path still runs everything for a PR that changes the gate's files.
# shellcheck disable=SC2016 # the sed pattern names the script's own ${p} and ${BOARD}
sed 's/\*) verdict false "${p} is outside ${BOARD}" ;;/*) ;;/' "${GATE}" > "${tmp}/loose.sh"
check "the loose gate's case arm takes every path" differ "${GATE}" "${tmp}/loose.sh"
branch loose 'echo more >> bin/x.sh'
SH="${tmp}/loose.sh" check "the loose gate takes bin/x.sh" says true
for f in scripts/board-only.sh .github/workflows/ci.yml tests/board_only_test.sh; do
  branch "own-${f//\//-}" "mkdir -p \"\$(dirname ${f})\" && echo '# more' >> ${f}"
  SH="${tmp}/loose.sh" check "the loose gate runs everything for a change to ${f}" says false
done

# A release: main's tip is the base and its CI is green, unless a case says otherwise.
echo "${BASE}" > "${FX}/tip"; checks "${BASE}" completed '"success"'
bump='sed -i.bak "s/1.0.0/1.1.0/" .claude-plugin/plugin.json && rm .claude-plugin/plugin.json.bak && git rm -q board/stories/a.md'
branch release "${bump}"
check "a version-only plugin.json diff on a green, current base is fast-path" says true
echo 1111111111111111111111111111111111111111 > "${FX}/tip"
check "a base behind main runs everything" says false
rm "${FX}/tip"
check "gh failing to read main's tip runs everything" says false
echo "${BASE}" > "${FX}/tip"; checks "${BASE}" completed '"failure"'
check "a base whose CI was red runs everything" says false
checks "${BASE}" in_progress null
check "a base whose CI is still running runs everything" says false
checks "${BASE}" completed '"success"'
branch describe "${bump}"' && sed -i.bak "s/\"d\"/\"e\"/" .claude-plugin/plugin.json && rm .claude-plugin/plugin.json.bak'
check "a plugin.json diff that also changes description runs everything" says false
branch semver "echo '{\"name\": \"p\", \"version\": \"1.2\", \"description\": \"d\"}' > .claude-plugin/plugin.json"
check "a version that is not MAJOR.MINOR.PATCH runs everything" says false
branch older "echo '{\"name\": \"p\", \"version\": \"0.9.0\", \"description\": \"d\"}' > .claude-plugin/plugin.json"
check "a version not greater than the base's runs everything" says false
branch invalid "echo '{' > .claude-plugin/plugin.json"
check "plugin.json that is not JSON on the PR runs everything" says false
branch missing 'git rm -q .claude-plugin/plugin.json'
check "plugin.json deleted on the PR runs everything" says false

# ci.yml: the gate step's id and the output key the gate really writes.
git -C "${G}" checkout -q board
key="$(gate)"; key="${key%%=*}"
check "the gate writes one output key" [ "${key}" = board_only ]
if python3 - "${REPO}/.github/workflows/ci.yml" "${key}" "${tmp}/step.sh" <<'PY'
import re, sys
path, key, out = sys.argv[1:4]
top, jobs, section, job, fails = {}, {}, None, None, 0
for raw in open(path).read().split("\n"):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    if not raw.startswith(" "):
        section = raw.split(":")[0]
        top[section] = []
    elif section != "jobs":
        top[section].append(raw.strip())
    elif re.match(r"  \S", raw):
        job = jobs.setdefault(raw.strip().rstrip(":"), {"head": [], "steps": []})
    elif raw.startswith("      - "):
        job["steps"].append([raw[8:]])
    elif raw.startswith("        ") and job["steps"]:
        job["steps"][-1].append(raw[8:])
    else:
        job["head"].append(re.sub(r"\s+#.*$", "", raw.strip()))

def check(name, ok):
    global fails
    print(("ok   " if ok else "FAIL ") + name)
    fails += not ok

def field(step, k):
    """A step's key at its top level: the value, or a | block's lines."""
    for i, line in enumerate(step):
        if line.startswith(k + ":"):
            v = line[len(k) + 1:].strip()
            if v != "|":
                return v
            block = []
            for m in step[i + 1:]:
                if not m.startswith("  "):
                    break
                block.append(m[2:])
            return "\n".join(block)
    return None

GATED = ("shellcheck", "test", "plugin-validate")
check("the workflow grants only contents: read", top.get("permissions") == ["contents: read"])
check("gitleaks gets no checks or statuses",
      "gitleaks" in jobs and not {"checks: read", "statuses: read"} & set(jobs["gitleaks"]["head"]))
runs = []
for name in GATED:
    job = jobs.get(name, {"head": [], "steps": []})
    check("%s: grants contents, checks and statuses read" % name,
          {"contents: read", "checks: read", "statuses: read"} <= set(job["head"]))
    steps = job["steps"]
    gates = [i for i, s in enumerate(steps) if 'git show "${BASE_SHA}:scripts/board-only.sh"' in (field(s, "run") or "")]
    check("%s: one gate step runs the base's copy" % name, len(gates) == 1)
    if len(gates) != 1:
        continue
    g = gates[0]
    gid = field(steps[g], "id")
    runs.append(field(steps[g], "run"))
    check("%s: the gate step has an id" % name, bool(gid))
    check("%s: a checkout before the gate fetches the base" % name,
          any((field(s, "uses") or "").startswith("actions/checkout@")
              and re.search(r"^\s*fetch-depth:\s*0\b", "\n".join(s), re.M) for s in steps[:g]))
    want = "steps.%s.outputs.%s != 'true'" % (gid, key)
    rest = steps[g + 1:]
    check("%s: there are steps after the gate" % name, bool(rest))
    for s in rest:
        check("%s: '%s' runs only when %s" % (name, field(s, "name"), want), field(s, "if") == want)
check("the three gate steps run the same commands", len(runs) == len(GATED) and len(set(runs)) == 1)
check("shellcheck: the shellcheck step names scripts/board-only.sh",
      any(re.search(r"^shellcheck .*\bscripts/board-only\.sh\b", field(s, "run") or "") for s in jobs.get("shellcheck", {}).get("steps", [])))
open(out, "w").write(runs[0] + "\n" if runs else "exit 1\n")
sys.exit(fails > 0)
PY
then :; else fails=$((fails + 1)); fi

# The gate step as ci.yml runs it, under bash -e as Actions does.
SH="${tmp}/step.sh"
branch broken "echo more >> board/stories/a.md; printf 'echo board_only=true >> \"\$GITHUB_OUTPUT\"\n' > scripts/board-only.sh"
check "the gate step judges a PR that breaks the gate with the base's copy" says false
branch first "echo more >> board/stories/a.md; mkdir -p scripts && cp '${GATE}' scripts/" "${BASE0}"
check "the gate step runs the PR's copy when the base has none" says false BASE_SHA="${BASE0}"
branch board2 'echo more >> board/stories/a.md'
check "the gate step says board-only for a board-only PR" says true

exit $((fails > 0))
