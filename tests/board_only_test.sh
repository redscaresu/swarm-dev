#!/usr/bin/env bash
# board_only_test.sh — scripts/board-only.sh on a fixture git repo: board-only for board/ paths only,
# fast-path for a version-only plugin.json bump on main's latest, green commit, and the full suite for
# anything else. Then ci.yml: each gated job's checkout fetches the base, every step after the gate
# runs only when the gate says no, and shellcheck covers the script. gh is a stub on PATH answering
# main's latest commit from ${FX}/tip and each commit's check runs from ${FX}/<sha>.checks.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${REPO}/scripts/board-only.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
G="${tmp}/repo"; FX="${tmp}/fx"; fails=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

check() { # <name> <cond...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

mkdir -p "${tmp}/bin" "${FX}"
cat > "${tmp}/bin/gh" <<STUB
#!/usr/bin/env bash
FX="${FX}"
STUB
cat >> "${tmp}/bin/gh" <<'STUB'
case "$*" in
  "api repos/o/r/commits/main --jq .sha") cat "${FX}/tip" ;;
  "api --paginate repos/o/r/commits/"*"/check-runs?per_page=100")
    a="$*"; sha="${a#*/commits/}"; cat "${FX}/${sha%%/*}.checks" 2>/dev/null || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "api --paginate repos/o/r/commits/"*"/status?per_page=100") echo '{"total_count":0,"statuses":[]}' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${tmp}/bin/gh"

# main: a story, a script and plugin.json.
git init -q -b main "${G}"
mkdir -p "${G}/board/stories" "${G}/bin" "${G}/.claude-plugin"
echo story > "${G}/board/stories/a.md"; echo 'echo x' > "${G}/bin/x.sh"
echo '{"name": "p", "version": "1.0.0", "description": "d"}' > "${G}/.claude-plugin/plugin.json"
git -C "${G}" add -A; git -C "${G}" commit -qm base
BASE="$(git -C "${G}" rev-parse HEAD)"

# branch <name> <shell> — a branch off the base with <shell>'s changes committed (none is an empty commit).
branch() {
  git -C "${G}" checkout -q -B "$1" "${BASE}"
  (cd "${G}" && eval "$2")
  git -C "${G}" add -A; git -C "${G}" commit -q --allow-empty -m "$1"
}
# gate [VAR=value]... — the gate on the checked-out branch as a pull request on base ${BASE}; prints
# what it wrote to GITHUB_OUTPUT.
gate() {
  : > "${tmp}/out"
  (cd "${G}" && env PATH="${tmp}/bin:${PATH}" GITHUB_EVENT_NAME=pull_request BASE_SHA="${BASE}" GITHUB_REPOSITORY=o/r \
    GITHUB_OUTPUT="${tmp}/out" "$@" bash "${GATE}" > "${tmp}/log" 2>&1) || echo "exit $?" >> "${tmp}/out"
  cat "${tmp}/out"
}
# shellcheck disable=SC2329 # called through check
says() { [ "$(gate "${@:2}")" = "board_only=$1" ]; }
green() { echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"'"$2"'"}]}' > "${FX}/$1.checks"; }

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

# A release: main's tip is the base and its CI is green, unless a case says otherwise.
echo "${BASE}" > "${FX}/tip"; green "${BASE}" success
bump='sed -i.bak "s/1.0.0/1.1.0/" .claude-plugin/plugin.json && rm .claude-plugin/plugin.json.bak && git rm -q board/stories/a.md'
branch release "${bump}"
check "a version-only plugin.json diff on a green, current base is fast-path" says true
echo 1111111111111111111111111111111111111111 > "${FX}/tip"
check "a base behind main runs everything" says false
echo "${BASE}" > "${FX}/tip"; green "${BASE}" failure
check "a base whose CI was red runs everything" says false
green "${BASE}" success
branch describe "${bump}"' && sed -i.bak "s/\"d\"/\"e\"/" .claude-plugin/plugin.json && rm .claude-plugin/plugin.json.bak'
check "a plugin.json diff that also changes description runs everything" says false

# ci.yml: the gate step's id and the output key the gate really writes.
git -C "${G}" checkout -q board
key="$(gate)"; key="${key%%=*}"
check "the gate writes one output key" [ "${key}" = board_only ]
if python3 - "${REPO}/.github/workflows/ci.yml" "${key}" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
jobs, job, fails = {}, None, 0
after = False
for line in open(path):
    if line.startswith("jobs:"):
        after = True
        continue
    if not after:
        continue
    m = re.match(r"  ([A-Za-z0-9_-]+):\s*$", line)
    if m:
        job = jobs.setdefault(m.group(1), [])
    elif line.startswith("      - "):
        job.append(line[8:])
    elif line.startswith("        ") and job:
        job[-1] += line.strip() + "\n"

def check(name, ok):
    global fails
    print(("ok   " if ok else "FAIL ") + name)
    fails += not ok

def field(step, k):
    m = re.search(r"^%s:\s*(.*)$" % re.escape(k), step, re.M)
    return m and m.group(1).strip()

for name in ("shellcheck", "test", "plugin-validate"):
    steps = jobs.get(name, [])
    gates = [i for i, s in enumerate(steps) if re.fullmatch(r"(bash )?scripts/board-only\.sh", field(s, "run") or "")]
    check("%s: one gate step" % name, len(gates) == 1)
    if len(gates) != 1:
        continue
    g = gates[0]
    gid = field(steps[g], "id")
    check("%s: the gate step has an id" % name, bool(gid))
    check("%s: a checkout before the gate fetches the base" % name,
          any("actions/checkout@" in s and re.search(r"^fetch-depth:\s*0\b", s, re.M) for s in steps[:g]))
    want = "steps.%s.outputs.%s != 'true'" % (gid, key)
    rest = steps[g + 1:]
    check("%s: there are steps after the gate" % name, bool(rest))
    for s in rest:
        check("%s: '%s' runs only when %s" % (name, field(s, "name"), want), field(s, "if") == want)
check("shellcheck: the shellcheck step names scripts/board-only.sh",
      any(re.search(r"^run:\s*shellcheck .*\bscripts/board-only\.sh\b", s, re.M) for s in jobs.get("shellcheck", [])))
sys.exit(fails > 0)
PY
then :; else fails=$((fails + 1)); fi

exit $((fails > 0))
