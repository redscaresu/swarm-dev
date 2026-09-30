#!/usr/bin/env bash
# swarm.sh — run agents in herdr panes so every one can be watched.
#
#   swarm.sh agent <tab> <name> <cwd> <role> <prompt-file>   start one agent in its own pane
#   swarm.sh story <slug>                                   build one <board>/stories/<slug>.md
#   swarm.sh conduct <epic>                                 a fresh conductor for one epic, in a workspace named for its HLD
#   swarm.sh wait <name> [timeout-ms]                       block until the agent settles
#   swarm.sh policy <role>                                  print the model and effort for a role
#   swarm.sh close <tab>                                    close <tab>, <tab>-2, ... and forget them
#   swarm.sh cost [YYYY-MM-DD]                              tokens and estimated cost per role, from the agents' logs
#   swarm.sh next                                           the chain's next step, read from the board (resumable)
#   swarm.sh unblock                                        mark ready every blocked story whose blockers are all finished
#   swarm.sh finish <slug>                                  take a merged story or epic off the board (delete or mark done)
#   swarm.sh watch [repo...]                                wait until a story PR needs the lead, print why, and exit
#   swarm.sh config [key]                                   the project's settings and where each came from, or one value
#
# The project is, first match wins: $SWARM_PROJECT; the nearest directory up from here with
# .claude/swarm/config (mapped to the main checkout when it is in a git worktree); the main checkout
# of the git repo you are in. Settings live in .claude/swarm/config (see config below). Must run
# inside herdr (HERDR_ENV=1). A story gets its own tab, named for the story. Tabs hold at most four
# panes (a 2x2 grid); a fifth agent opens "<tab>-2", and so on, so no pane gets too small to follow.
set -euo pipefail

die() { echo "swarm: $*" >&2; exit 1; }

# The framework itself: this script's repo, whose docs/method.md the briefs point at.
SWARM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# main_checkout <dir> — <dir> as it sits in its repo's main checkout, so a worktree resolves to the
# same project as the checkout it came from. Fails when <dir> is not in a git repo.
main_checkout() {
  local common top rel
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  top="$(git -C "$1" rev-parse --show-toplevel)"
  rel="${1#"${top}"}"
  echo "$(dirname "${common}")${rel}"
}

find_project() {
  local d
  if [[ -n "${SWARM_PROJECT:-}" ]]; then
    (cd "${SWARM_PROJECT}" 2>/dev/null && pwd -P) || die "SWARM_PROJECT ${SWARM_PROJECT} is not a directory"
    return
  fi
  d="$(pwd -P)"
  while [[ "${d}" != / ]]; do
    if [[ -f "${d}/.claude/swarm/config" ]]; then
      main_checkout "${d}" || echo "${d}"
      return
    fi
    d="$(dirname "${d}")"
  done
  main_checkout "$(pwd -P)" || die "not in a swarm project: no .claude/swarm/config above here and not in a git repo"
}

PROJECT_DIR="$(find_project)"
CONFIG_FILE="${PROJECT_DIR}/.claude/swarm/config"

# Settings, with their defaults. CFG_<key> is the value, SRC_<key> where it came from.
CFG_board_dir=docs
CFG_repos_dir=""        # empty: the project dir's parent
CFG_base_branches=""    # empty: origin's default branch
CFG_finished=delete
CONFIG_KEYS="board_dir repos_dir base_branches finished"
for _key in ${CONFIG_KEYS}; do printf -v "SRC_${_key}" default; done

# load_config — read CONFIG_FILE as `key = value` lines. It is parsed, never sourced, so it cannot run
# code; a `$` or backtick is refused so nobody expects it to expand. Any bad line stops the script.
load_config() {
  local n=0 line key value where
  [[ -f "${CONFIG_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$((n + 1)); where="${CONFIG_FILE}:${n}"
    line="${line%%#*}"
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]] \
      || die "${where}: expected 'key = value'"
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    [[ "${value}" != *'$'* && "${value}" != *'`'* ]] || die "${where}: ${key}: \$ and backticks are not expanded; write the value out"
    case "${key}" in
      board_dir|repos_dir)
        [[ -n "${value}" ]] || die "${where}: ${key} is empty"
        # shellcheck disable=SC2088 # a literal ~ in the file, expanded here
        [[ "${value}" == "~" || "${value}" == "~/"* ]] && value="${HOME}${value:1}" ;;
      base_branches)
        [[ "${value}" =~ ^[A-Za-z0-9._/[:space:]-]*$ ]] || die "${where}: base_branches: not branch names: ${value}" ;;
      finished)
        [[ "${value}" == delete || "${value}" == mark ]] || die "${where}: finished must be delete or mark, not '${value}'" ;;
      *) die "${where}: unknown key '${key}' (known: ${CONFIG_KEYS})" ;;
    esac
    printf -v "CFG_${key}" '%s' "${value}"
    printf -v "SRC_${key}" '%s' "${where}"
  done < "${CONFIG_FILE}"
}
load_config

# abs_path <path> — <path>, relative to the project dir unless it is absolute.
abs_path() { if [[ "$1" == /* ]]; then echo "$1"; else echo "${PROJECT_DIR}/$1"; fi; }
BOARD="$(abs_path "${CFG_board_dir}")"
[[ -d "${BOARD}" ]] && BOARD="$(cd "${BOARD}" && pwd -P)"   # so a board_dir with .. is compared as the real path
REPOS_DIR="$(dirname "${PROJECT_DIR}")"; [[ -z "${CFG_repos_dir}" ]] || REPOS_DIR="$(abs_path "${CFG_repos_dir}")"
PROJECT_IS_GIT=0; [[ -e "${PROJECT_DIR}/.git" ]] && PROJECT_IS_GIT=1
# A builder can change the board in its own PR only when the board is in the project's repo.
BOARD_IN_REPO=0; [[ ${PROJECT_IS_GIT} == 1 && "${BOARD}/" == "${PROJECT_DIR}/"* ]] && BOARD_IN_REPO=1

STATE_DIR="${PROJECT_DIR}/.swarm/state"
# Project rules every builder gets after the standard ones: commit trailers, secrets, ADR rules.
PROJECT_BRIEF="${PROJECT_DIR}/.claude/swarm/brief.md"
PANES_PER_TAB=4

show_config() {
  local key v
  if [[ -n "${1:-}" ]]; then
    case "$1" in
      board_dir) echo "${BOARD}" ;;
      repos_dir) echo "${REPOS_DIR}" ;;
      project) echo "${PROJECT_DIR}" ;;
      *) [[ " ${CONFIG_KEYS} " == *" $1 "* ]] || die "unknown key '$1' (known: project ${CONFIG_KEYS})"
         v="CFG_$1"; echo "${!v}" ;;
    esac
    return
  fi
  echo "project = ${PROJECT_DIR}"
  for key in ${CONFIG_KEYS}; do
    v="CFG_${key}"; local s="SRC_${key}"
    case "${key}" in board_dir) v=BOARD ;; repos_dir) v=REPOS_DIR ;; esac
    echo "${key} = ${!v}    (${!s})"
  done
}

# repo_dir <name> — where a story's repo is: the project itself when <name> is empty or the
# project's own name, else <repos_dir>/<name>. Fails, printing why, when there is no such repo.
repo_dir() {
  local name="$1" dir
  if [[ -z "${name}" || ( "${name}" == "$(basename "${PROJECT_DIR}")" && ${PROJECT_IS_GIT} == 1 ) ]]; then
    [[ ${PROJECT_IS_GIT} == 1 ]] || { echo "no repo: named, and the project ${PROJECT_DIR} is not a git repo"; return 1; }
    echo "${PROJECT_DIR}"; return
  fi
  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad repo '${name}'"; return 1; }
  dir="${REPOS_DIR}/${name}"
  [[ -e "${dir}/.git" ]] || { echo "no repo at ${dir}"; return 1; }
  echo "${dir}"
}

# worktree_for <repo-dir> <slug> — where a story's worktree goes: beside its repo, in <repo>-wt/.
worktree_for() { echo "$(dirname "$1")/$(basename "$1")-wt/$2"; }

# base_for <repo-dir> — the branch a story starts from and merges into, fetched: the first
# base_branches entry origin has, or origin's default branch when the list is empty. Each is asked
# of origin itself, not the clone's cached refs, which a single-branch clone or a changed default
# would get wrong. Never a guess.
base_for() {
  local src="$1" b head branches
  if [[ -n "${CFG_base_branches// /}" ]]; then
    read -r -a branches <<< "${CFG_base_branches}"
    for b in "${branches[@]}"; do
      git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" 2>/dev/null && { echo "${b}"; return; }
    done
    die "${src}: origin has none of base_branches (${CFG_base_branches})"
  fi
  if ! git -C "${src}" remote set-head origin --auto >/dev/null 2>&1 \
     || ! head="$(git -C "${src}" symbolic-ref -q --short refs/remotes/origin/HEAD)"; then
    die "${src}: cannot tell origin's default branch; set base_branches"
  fi
  b="${head#origin/}"
  git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" || die "${src}: cannot fetch ${b}"
  echo "${b}"
}

# The model and effort for each role. This is the one place the policy lives
# (docs/method.md § Model and effort explains the reasoning).
#   design:    hld, hld-review, hld-lead
#   planning:  survey, lead, skeptic, critic, codex
#   building:  code, code-risky, docs, chore, verify
#   conducting: conduct
policy() {
  case "$1" in
    hld)        echo "claude fable high" ;;    # co-writes the HLD with the user, who waits on every turn
    hld-review) echo "claude fable xhigh" ;;   # attacks the finished draft before it is agreed
    hld-lead)   echo "claude fable xhigh" ;;   # HLD into epics: one call that shapes everything below it
    survey)     echo "claude sonnet high" ;;   # reads and cites; feeds the lead, so not low
    lead)       echo "claude opus xhigh" ;;    # one decomposition decides the whole epic
    skeptic)    echo "claude opus high" ;;     # the only gate a story passes before it is built
    critic)     echo "claude opus high" ;;
    codex)      echo "codex default high" ;;   # a different model family, read-only
    code)       echo "claude opus high" ;;
    code-risky) echo "claude opus xhigh" ;;    # Layer 3, teardown, safety or hygiene paths
    docs|chore) echo "claude sonnet medium" ;;
    verify)     echo "claude sonnet medium" ;; # run tests or commands and report
    escalate)   echo "claude fable xhigh" ;;   # only after a story failed twice, or an unreconcilable epic
    conduct)    echo "claude opus high" ;;     # dispatches, reviews, merges one epic; a fresh session each time
    *) die "unknown role '$1' (hld hld-review hld-lead survey lead skeptic critic codex code code-risky docs chore verify escalate conduct)" ;;
  esac
}

# agent_name <name> — the herdr agent name for anything started or waited on. start_agent and
# `wait` both map through here, so every caller agrees: lowercase, [a-z0-9_-], starting with a letter, at most 32 characters.
agent_name() {
  local n
  n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
  [[ "${n}" =~ ^[a-z] ]] || n="s${n}"
  printf '%s' "${n:0:32}"
}

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

require_herdr() { [[ "${HERDR_ENV:-}" == 1 ]] || die "not running inside a herdr pane (HERDR_ENV != 1)"; }

# next_pane <tab-label> <cwd> — a fresh shell pane in a tab with room, creating tabs as needed.
next_pane() {
  local label="$1" cwd="$2" n=1 state panes count pane
  mkdir -p "${STATE_DIR}"
  while :; do
    local tab_label="${label}"; [[ ${n} -gt 1 ]] && tab_label="${label}-${n}"
    state="${STATE_DIR}/${tab_label}"
    count=0; [[ -f "${state}" ]] && count=$(wc -l < "${state}" | tr -d ' ')
    if [[ ${count} -lt ${PANES_PER_TAB} ]]; then
      if [[ ${count} -eq 0 ]]; then
        pane=$(herdr tab create --workspace "${HERDR_WORKSPACE_ID}" --cwd "${cwd}" --label "${tab_label}" --no-focus \
          | json "d['result']['root_pane']['pane_id']")
      else
        # 2x2: 2nd splits the first to the right, 3rd splits the first down, 4th splits the second down.
        read -r -a panes <<< "$(tr '\n' ' ' < "${state}")"
        case ${count} in
          1) pane=$(herdr pane split "${panes[0]}" --direction right --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          2) pane=$(herdr pane split "${panes[0]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          3) pane=$(herdr pane split "${panes[1]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
        esac
      fi
      echo "${pane}" >> "${state}"
      echo "${pane}"
      return
    fi
    n=$((n + 1))
  done
}

start_agent() {
  local tab="$1" name cwd="$3" role="$4" prompt_file="$5" kind model effort pane
  name="$(agent_name "$2")"   # the one place names are mapped, so `wait <same name>` always finds it
  [[ -f "${prompt_file}" ]] || die "no prompt file ${prompt_file}"
  read -r kind model effort <<< "$(policy "${role}")"
  pane=$(next_pane "${tab}" "${cwd}")
  # A freshly split pane is not always an available shell yet (agent_pane_busy): retry once.
  local try
  for try in 1 2; do
    if [[ "${kind}" == codex ]]; then
      herdr agent start "${name}" --kind codex --pane "${pane}" --timeout 60000 -- \
        -s read-only -c "model_reasoning_effort=\"${effort}\"" >/dev/null && break
    else
      herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- \
        --model "${model}" --effort "${effort}" --permission-mode auto >/dev/null && break
    fi
    [[ ${try} -eq 2 ]] && die "${name}: herdr could not start the agent in pane ${pane}"
    sleep 3
  done
  deliver_prompt "${name}" "${prompt_file}"
  record_agent "${role}" "${name}" "${kind}" "${model}" "${effort}" "${pane}"
  echo "${name} ${pane} ${kind}:${model}:${effort}"
}

# AGENTS_LOG: one line per agent started (date, role, name, kind, model, effort, session), so
# `cost` can attribute every token to a role. Beside state/, not in it: state/ holds tab records.
AGENTS_LOG="${PROJECT_DIR}/.swarm/agents.tsv"

# session_for_pane <pane> — the Claude session id herdr reports for the agent in <pane>, or nothing.
session_for_pane() {
  herdr agent list 2>/dev/null | json "next(((a.get('agent_session') or {}).get('value','') for a in d['result']['agents'] if a.get('pane_id')=='$1'),'')" 2>/dev/null || true
}

record_agent() {
  local role="$1" name="$2" kind="$3" model="$4" effort="$5" pane="$6" session
  session="$(session_for_pane "${pane}")"
  mkdir -p "$(dirname "${AGENTS_LOG}")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "${role}" "${name}" "${kind}" "${model}" "${effort}" "${session:--}" >> "${AGENTS_LOG}"
}

# cost [since] — tokens and estimated cost per role, for every agent this project's swarm started
# (and the calling session, as "lead", when run inside herdr). Usage comes from Claude Code's own
# session logs, deduplicated by message id; codex agents are listed but not priced (not logged here).
cost_report() {
  local lead=""
  [[ "${HERDR_ENV:-}" == 1 ]] && lead="$(session_for_pane "${HERDR_PANE_ID:-}")"
  [[ -f "${AGENTS_LOG}" || -n "${lead}" ]] || die "no agents recorded yet in ${AGENTS_LOG}"
  python3 - "${AGENTS_LOG}" "${1:-0000-00-00}" "${lead}" "${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}" <<'PY'
import glob, json, os, sys
log, since, lead, projects = sys.argv[1:5]
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}
agents = []
if os.path.exists(log):
    for line in open(log):
        f = line.rstrip("\n").split("\t")
        if len(f) == 7 and f[0] >= since:
            agents.append({"role": f[1], "kind": f[3], "session": f[6]})
if lead:
    agents.append({"role": "lead", "kind": "claude", "session": lead})
rows, seen = {}, set()
for a in agents:
    r = rows.setdefault(a["role"], {"agents": 0, "models": set(), "tok": [0, 0, 0, 0], "usd": 0.0, "unpriced": 0})
    r["agents"] += 1
    paths = glob.glob(os.path.join(projects, "*", a["session"] + ".jsonl")) if a["session"] != "-" else []
    if a["kind"] != "claude" or not paths:
        r["unpriced"] += 1
        continue
    for line in open(paths[0], errors="ignore"):
        try:
            m = json.loads(line).get("message") or {}
        except ValueError:
            continue
        u, mid = m.get("usage"), m.get("id")
        if not u or not mid or mid in seen:
            continue
        seen.add(mid)
        t = [u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)]
        model = m.get("model", "?")
        r["models"].add(model)
        r["tok"] = [x + y for x, y in zip(r["tok"], t)]
        price = next((v for k, v in PRICES.items() if k in model), None)
        if price:
            r["usd"] += sum(x * p for x, p in zip(t, price)) / 1e6
def n(x):
    return f"{x/1e6:.1f}M" if x >= 1e6 else f"{x/1e3:.0f}k"
print("| role | agents | model | input | cache write | cache read | output | est. $ |")
print("|---|---|---|---|---|---|---|---|")
tot = [0, 0, 0, 0]; usd = 0.0
for role, r in sorted(rows.items(), key=lambda kv: -kv[1]["usd"]):
    tot = [x + y for x, y in zip(tot, r["tok"])]; usd += r["usd"]
    note = f" ({r['unpriced']} not in the logs)" if r["unpriced"] else ""
    print(f"| {role} | {r['agents']}{note} | {', '.join(sorted(r['models'])) or '-'} | " + " | ".join(n(x) for x in r["tok"]) + f" | {r['usd']:.2f} |")
print(f"| **total** | {sum(r['agents'] for r in rows.values())} | | " + " | ".join(n(x) for x in tot) + f" | {usd:.2f} |")
print("\nList prices; on a subscription this is plan usage, not a bill. Codex agents are not priced.")
PY
}

# deliver_prompt <name> <prompt-file> — submit the brief and confirm the agent acted on it.
# `agent start` returns once the agent is ready, but a slow starter (Fable at xhigh) could
# still drop a prompt sent at once, leaving it idle at an empty prompt while every later
# `wait` returned immediately. So the submission waits until herdr sees the agent working
# (or blocked on a question), retries once, and fails loudly rather than reporting success.
deliver_prompt() {
  local name="$1" prompt_file="$2" status
  for _ in 1 2; do
    status=$(herdr agent prompt "${name}" "$(cat "${prompt_file}")" --wait --until working --until blocked \
      --timeout 60000 2>/dev/null | json "d.get('result',{}).get('agent',{}).get('agent_status','')" 2>/dev/null || true)
    case "${status}" in
      working|blocked) return 0 ;;
    esac
    sleep 5
  done
  die "${name}: the brief was not taken up after 2 attempts (status '${status:-none}'); see herdr agent read ${name}"
}

# The brief every story builder gets. The story file is the task; these are the rules.
story_brief() {
  local slug="$1" src="$2" base="$3" story_ref cleanup rel
  if [[ "${src}" == "${PROJECT_DIR}" && ${BOARD_IN_REPO} == 1 ]]; then
    # The board is in this repo: the PR takes the story off it.
    rel="${BOARD#"${PROJECT_DIR}/"}/stories"
    story_ref="${rel}/${slug}.md"
    if [[ "${CFG_finished}" == mark ]]; then
      cleanup="In your PR, set \`status: done\` in ${rel}/${slug}.md, and change nothing else under ${rel}/."
    else
      cleanup="Delete ${rel}/${slug}.md in your PR, and nothing else under ${rel}/."
    fi
  else
    # The board is elsewhere: read the story there, and leave it for the lead.
    story_ref="${BOARD}/stories/${slug}.md (this worktree is $(basename "${src}"))"
    cleanup="Do not touch the story file; the lead takes it off the board after your PR merges."
  fi
  cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit and PR with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} Never merge (the lead merges). Never touch real cloud or
credentials. Open the PR against \`${base}\`. Run \`codex exec review --base origin/${base}\` before
committing; fix real findings, decline nits with a reason, converge on one clean pass, and record the
loop in the PR body. If codex reports a usage limit, do not wait for it to reset: carry on without it
and write "codex skipped: usage limit" in the PR body. If \`gh pr view --json mergeable\` says
CONFLICTING, merge origin/${base} into your branch, resolve it (keep both sides of any list), re-run
the tests and push: a conflicted PR runs no checks and waits forever. When CI is green, reply with
the PR URL, what changed in three lines, and the codex findings, then stop.
EOF
  if [[ -f "${PROJECT_BRIEF}" ]]; then
    echo
    cat "${PROJECT_BRIEF}"
  fi
}

build_story() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind risk repo src role wt branch prompt base
  [[ -f "${story}" ]] || die "no story ${story}"
  grep -q '^status: ready$' "${story}" || die "${slug} is not status: ready"
  kind=$(sed -n 's/^kind: *//p' "${story}" | head -1); kind="${kind:-code}"
  case "${kind}" in
    lead)     die "${slug} is kind: lead — real cloud or credentials; the lead runs it, not a swarm agent" ;;
    operator) die "${slug} is kind: operator — a human step, not an agent's" ;;
  esac
  risk=$(sed -n 's/^risk: *//p' "${story}" | head -1)
  repo=$(sed -n 's/^repo: *//p' "${story}" | head -1)   # a repo in repos_dir; empty is the project's own
  role="${kind}"; [[ "${kind}" == code && "${risk}" == high ]] && role=code-risky
  policy "${role}" >/dev/null
  src="$(repo_dir "${repo}")" || die "${slug}: ${src}"
  base="$(base_for "${src}")"
  branch="story/${slug}"; wt="$(worktree_for "${src}" "${slug}")"
  git -C "${src}" worktree add -q -b "${branch}" "${wt}" "origin/${base}"
  prompt="${PROJECT_DIR}/.swarm/briefs/${slug}.md"; mkdir -p "$(dirname "${prompt}")"
  story_brief "${slug}" "${src}" "${base}" > "${prompt}"
  start_agent "${slug}" "${slug}" "${wt}" "${role}" "${prompt}"
}

# The brief a conductor gets: one epic, from a fresh session, so its context holds only that epic.
conduct_brief() {
  local epic="$1"
  cat <<EOF
You are the conductor for the epic ${BOARD}/epics/${epic}.md. Read AGENTS.md (and STATUS.md if there
is one), ${SWARM_HOME}/docs/method.md and the epic first.

Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) to merge, as method.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap,
start each with \`${SWARM_HOME}/bin/swarm.sh story <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch\` in the background, review each PR, merge it only when its head is green, then run
\`swarm.sh unblock\` and \`swarm.sh close <slug>\` to close that story's tab. If a merged story is
still open on the board once you have pulled (its file is there and not \`status: done\`), run
\`swarm.sh finish <slug>\` first. Each story's base branch is in its brief, .swarm/briefs/<slug>.md.

Stay inside this epic: start no story outside it, and leave the HLD and other epics alone. A
\`kind: lead\` story (real cloud, credentials) or a \`kind: operator\` one is not yours to run; list it
for the user. Stop when the epic's **Done when** holds (take the epic off the board: \`swarm.sh finish ${epic}\`) or
when nothing ready is left.

Your last act, after everything else: write your report (what merged, what is left, what waits on
the user) to ${PROJECT_DIR}/.swarm/conduct-${epic}.report.md, then reply with the same. The lead
treats that file as the only sign you have finished: being idle while you wait on your own
background work is not.
EOF
}

# hld_workspace <label> — the herdr workspace labelled <label>, created if there is none. Every epic
# of one HLD shares it; a new workspace's placeholder tab is closed once the caller has added its own.
hld_workspace() {
  local label="$1" ws
  ws=$(herdr workspace list | json "next((w['workspace_id'] for w in d['result']['workspaces'] if w.get('label')=='${label}'),'')")
  if [[ -z "${ws}" ]]; then
    ws=$(herdr workspace create --label "${label}" --cwd "${PROJECT_DIR}" --no-focus \
      | json "d['result']['workspace']['workspace_id']+' '+d['result']['tab']['tab_id']")
  fi
  echo "${ws}"
}

# conductor_report <agent> — where a conductor writes its report as its last act. The agent name
# may be cut at 32 characters, so it is resolved to the full tab label (conduct-<epic>) first.
conductor_report() { echo "${PROJECT_DIR}/.swarm/$(tab_label "$1").report.md"; }

start_conductor() {
  local epic="$1" epic_file="${BOARD}/epics/$1.md" hld prompt ws placeholder
  [[ "${epic}" =~ ^[a-z0-9-]+$ ]] || die "bad epic '${epic}'"
  [[ -f "${epic_file}" ]] || die "no epic ${epic_file}"
  hld=$(sed -n 's/^hld: *//p' "${epic_file}" | head -1); hld="${hld:-${epic}}"
  [[ "${hld}" =~ ^[a-z0-9-]+$ ]] || die "${epic}: bad hld '${hld}'"
  prompt="${PROJECT_DIR}/.swarm/briefs/conduct-${epic}.md"; mkdir -p "$(dirname "${prompt}")"
  conduct_brief "${epic}" > "${prompt}"
  rm -f "$(conductor_report "conduct-${epic}")"   # a report left by an earlier run is not this one's
  read -r ws placeholder <<< "$(hld_workspace "${hld}")"
  HERDR_WORKSPACE_ID="${ws}" start_agent "conduct-${epic}" "conduct-${epic}" "${PROJECT_DIR}" conduct "${prompt}"
  [[ -z "${placeholder}" ]] || herdr tab close "${placeholder}" >/dev/null
  echo "workspace ${hld} (${ws})"
}

# fm <file> <key> — the first front-matter value for <key>, or nothing.
fm() { sed -n "s/^$2: *//p" "$1" | head -1; }

# board <dir> — the item files in <board>/<dir>/, never the README.
board() {
  local f
  for f in "${BOARD}/$1"/*.md; do
    [[ -e "${f}" && "$(basename "${f}")" != README.md ]] && echo "${f}"
  done
  return 0
}

# epic_has_stories <epic> — true when any story names <epic>.
epic_has_stories() {
  local s
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] && return 0
  done < <(board stories)
  return 1
}

# next_step — what the chain does next, read from the board alone, so a run can stop anywhere and
# pick up again. Prints "<action> <arg>" on the first line and why on the second. In order:
#   collect <agent>   a conductor has written its report: read it, then close its tab
#   wait <agent>      a conductor exists and has not reported (idle between its own steps counts)
#   conduct <epic>    an active epic has a story an agent can build
#   resume <slug>     a one-off already started (its worktree exists): wait for it, then review
#   story <slug>      a ready story outside any epic
#   plan-epic <epic>  an active epic has no stories yet
#   plan-hld <hld>    an agreed HLD has no epics listed under ## Epics
#   hld <hld>         an HLD is still a draft
#   gate              only the user can move the board: operator and lead stories, blocked
#                     stories, later stories and epics
#   done              nothing open; start the next HLD with /hld <title>
next_step() {
  local f slug epic kind story_epic src buildable="" waiting=""
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    # Any status: idle is not finished. Only the conductor's report file says it is done.
    slug=$(herdr agent list 2>/dev/null | json "next((a['name'] for a in d['result']['agents'] if a.get('name','').startswith('conduct-')),'')" 2>/dev/null || true)
    if [[ -n "${slug}" ]]; then
      if [[ -f "$(conductor_report "${slug}")" ]]; then
        echo "collect ${slug}"; echo "the conductor ${slug} has finished and written its report"
      else
        echo "wait ${slug}"; echo "the conductor ${slug} is still working (it has not written its report)"
      fi
      return
    fi
  fi
  # Stories an agent can build: ready, and neither lead nor operator. "<epic> <slug>" per line.
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == ready ]] || continue
    kind=$(fm "${f}" kind)
    [[ "${kind}" == lead || "${kind}" == operator ]] && continue
    buildable+="$(fm "${f}" epic) $(basename "${f}" .md)"$'\n'
  done < <(board stories)
  # A one-off keeps status: ready until its PR merges, so an existing worktree means it has started.
  while read -r story_epic slug; do
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    src="$(repo_dir "$(fm "${BOARD}/stories/${story_epic}.md" repo)")" || continue
    [[ -d "$(worktree_for "${src}" "${story_epic}")" ]] || continue
    echo "resume ${story_epic}"; echo "${story_epic} has already started: wait for its agent, then review its PR"; return
  done <<< "${buildable}"
  # An active epic's stories first: finish what is started before anything new.
  while read -r story_epic slug; do
    [[ -n "${slug}" && "$(fm "${BOARD}/epics/${story_epic}.md" status 2>/dev/null)" == active ]] || continue
    echo "conduct ${story_epic}"; echo "${slug} is ready in the active epic ${story_epic}"; return
  done <<< "${buildable}"
  while read -r story_epic slug; do
    # A one-off: `read` puts the lone slug in story_epic.
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    echo "story ${story_epic}"; echo "${story_epic} is ready and belongs to no epic"; return
  done <<< "${buildable}"
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == active ]] || continue
    epic=$(basename "${f}" .md)
    epic_has_stories "${epic}" && continue
    echo "plan-epic ${epic}"; echo "the active epic ${epic} has no stories yet"; return
  done < <(board epics)
  while IFS= read -r f; do
    slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      agreed)
        if [[ $(awk '/^## Epics/{e=1;next} /^## /{e=0} e && /^[-*] /{n++} END{print n+0}' "${f}") -eq 0 ]]; then
          echo "plan-hld ${slug}"; echo "the agreed HLD ${slug} has no epics yet"; return
        fi ;;
      draft) echo "hld ${slug}"; echo "the HLD ${slug} is still a draft"; return ;;
    esac
  done < <(board hld)
  while IFS= read -r f; do
    kind=$(fm "${f}" kind); slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      ready) [[ "${kind}" == lead || "${kind}" == operator ]] && waiting+="  ${kind}: ${slug}"$'\n' ;;
      blocked) waiting+="  blocked: ${slug} (by $(fm "${f}" blocked_by))"$'\n' ;;
      later) waiting+="  later story: ${slug}"$'\n' ;;
    esac
  done < <(board stories)
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == later ]] && waiting+="  later epic: $(basename "${f}" .md)"$'\n'
  done < <(board epics)
  if [[ -n "${waiting}" ]]; then
    echo "gate"; echo "only you can move the board now:"; printf '%s' "${waiting}"; return
  fi
  echo "done"; echo "nothing is open; start the next HLD with /hld <title>"
}

# open_item <file> — true while a board item is still open: its file exists and is not status: done.
open_item() { [[ -f "$1" && "$(fm "$1" status)" != "done" ]]; }

# unblock — a finished story is deleted or marked done, so a blocked story whose every blocked_by slug
# is no open story or epic, and names no operator step, is ready. Prints each story it flips.
unblock() {
  local story slug blockers b open
  while IFS= read -r story; do
    grep -q '^status: blocked$' "${story}" || continue
    blockers=$(sed -n 's/^blocked_by: *\[\(.*\)\]$/\1/p' "${story}" | tr ',' ' ')
    [[ -n "${blockers// /}" ]] || continue   # blocked for a reason no merge clears
    open=0
    for b in ${blockers}; do
      # Open while its story exists, its epic exists, or it is not a plain slug (an operator step such
      # as "operator:planted-leak-proof" is cleared by hand, never by a merge).
      if open_item "${BOARD}/stories/${b}.md" || open_item "${BOARD}/epics/${b}.md" || [[ ! "${b}" =~ ^[a-z0-9-]+$ ]]; then open=1; fi
    done
    [[ ${open} -eq 0 ]] || continue
    sed -i.bak -e 's/^status: blocked$/status: ready/' -e '/^blocked_by:/d' "${story}" && rm -f "${story}.bak"
    echo "ready: $(basename "${story}" .md)"
  done < <(board stories)
}

# finish <slug> — take a merged story or epic off the board: delete its file, or with
# finished = mark set its status to done and keep it.
finish_item() {
  local slug="$1" f
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "bad slug '${slug}'"
  for f in "${BOARD}/stories/${slug}.md" "${BOARD}/epics/${slug}.md"; do
    [[ -f "${f}" ]] || continue
    if [[ "${CFG_finished}" == mark ]]; then
      awk '!d && /^status: /{print "status: done"; d=1; next} {print}' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
      echo "done: ${f}"
    else
      rm "${f}"; echo "deleted: ${f}"
    fi
    return
  done
  die "no story or epic '${slug}' in ${BOARD}"
}

# watch [repo...] — block until a story/* PR in these repos needs the lead, print one line saying
# which and why, and exit 0. A PR needs the lead when its checks on a new head have all finished,
# when it conflicts with its base (a conflicted PR runs no checks, so waiting on checks never ends),
# or when its head has had no check at all for WATCH_STALL_SECS (default 600). A herdr agent
# blocked on a prompt also needs the lead. Each head is reported once (state in .swarm/state).
watch_prs() {
  local repos=("$@") seen="${STATE_DIR}/watch-seen" stall="${WATCH_STALL_SECS:-600}" repo n sha br mergeable age total pending
  # Default: the project (when it is a repo) plus every repo a story names, so a new repo needs no edit here.
  if [[ ${#repos[@]} -eq 0 ]]; then
    local own=""; [[ ${PROJECT_IS_GIT} == 1 ]] && own="$(basename "${PROJECT_DIR}")"
    read -r -a repos <<< "${own} $(sed -n 's/^repo: *//p' "${BOARD}"/stories/*.md 2>/dev/null | sort -u | tr '\n' ' ')"
  fi
  # Each repo as owner/name, from its own origin: repos on one board need not share an owner.
  local full=() r src
  for r in "${repos[@]}"; do
    src="$(repo_dir "${r}")" || die "watch ${r}: ${src}"
    r="$(gh repo view "$(git -C "${src}" remote get-url origin)" --json nameWithOwner -q .nameWithOwner)" \
      || die "no GitHub origin for ${src}"
    [[ " ${full[*]-} " == *" ${r} "* ]] || full+=("${r}")
  done
  repos=("${full[@]}")
  mkdir -p "${STATE_DIR}"; touch "${seen}"
  while :; do
    for repo in "${repos[@]}"; do
      while read -r n sha br mergeable age; do
        [[ -n "${n}" ]] || continue
        if [[ "${mergeable}" == CONFLICTING ]] && ! grep -qx "conflict ${sha}" "${seen}"; then
          echo "conflict ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} CONFLICTS with its base"; return 0
        fi
        grep -qx "done ${sha}" "${seen}" && continue
        read -r total pending < <(gh api "repos/${repo}/commits/${sha}/check-runs" \
          -q '"\(.check_runs|length) \([.check_runs[]|select(.status!="completed")]|length)"')
        if [[ "${total:-0}" -gt 0 && "${pending}" == 0 ]]; then
          echo "done ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} checks finished on ${sha:0:7}"; return 0
        fi
        if [[ "${total:-0}" == 0 && "${age}" -gt "${stall}" ]] && ! grep -qx "stall ${sha}" "${seen}"; then
          echo "stall ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} has had no checks for ${age}s"; return 0
        fi
      done < <(gh pr list -R "${repo}" --state open --json number,headRefName,headRefOid,mergeable,updatedAt \
        -q '.[]|select(.headRefName|startswith("story/"))|"\(.number) \(.headRefOid) \(.headRefName) \(.mergeable) \((now - (.updatedAt|fromdateiso8601))|floor)"')
    done
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
      local blocked
      blocked=$(herdr agent list 2>/dev/null | json "','.join(a['name'] for a in d['result']['agents'] if a.get('agent_status')=='blocked' and a.get('name'))" 2>/dev/null || true)
      if [[ -n "${blocked}" ]] && ! grep -qx "blocked ${blocked}" "${seen}"; then
        echo "blocked ${blocked}" >> "${seen}"; echo "agent(s) blocked on a prompt: ${blocked}"; return 0
      fi
    fi
    sleep 60
  done
}

# tab_label <name> — the tab label an agent name came from. Agent names stop at 32 characters
# (agent_name), tab labels do not, so `next` can hand back a name that is not the label. The first
# state file whose agent name matches wins: the base tab sorts before its "-2", "-3" overflow.
tab_label() {
  local want state
  want="$(agent_name "$1")"
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" && "$(agent_name "$(basename "${state}")")" == "${want}" ]] || continue
    basename "${state}"; return
  done
  echo "$1"
}

# close_tabs <label> — close every tab this script opened under <label>, and its state. A tab may be
# in another workspace (a conductor's is its HLD's): its first pane id, "<workspace>:<pane>", says which.
close_tabs() {
  local label state tab_label id ws
  label="$(tab_label "$1")"
  for state in "${STATE_DIR}/${label}" "${STATE_DIR}/${label}"-*; do
    [[ -f "${state}" ]] || continue
    tab_label="$(basename "${state}")"
    ws="$(head -1 "${state}")"; ws="${ws%%:*}"; ws="${ws:-${HERDR_WORKSPACE_ID}}"
    id=$(herdr tab list --workspace "${ws}" | python3 -c "
import json,sys
for t in json.load(sys.stdin)['result']['tabs']:
    if t.get('label') == sys.argv[1]: print(t['tab_id'])" "${tab_label}")
    [[ -n "${id}" ]] && herdr tab close "${id}" >/dev/null
    rm -f "${state}"
    echo "closed ${tab_label}"
  done
}

# Everything runs from main, called on the last line with `exit` beside it: bash reads a
# script as it executes, so a `git pull` that rewrites this file during a long `wait` would
# otherwise make it resume reading the new file mid-line.
main() {
  cmd="${1:-}"; shift || true
  case "${cmd}" in
    policy) policy "${1:?role}" ;;
    agent)  require_herdr; start_agent "$@" ;;
    story)  require_herdr; build_story "${1:?slug}" ;;
    conduct) require_herdr; start_conductor "${1:?epic}" ;;
    close)  require_herdr; close_tabs "${1:?tab}" ;;
    unblock) unblock ;;
    next)   next_step ;;
    cost)   cost_report "${1:-}" ;;
    watch)  watch_prs "$@" ;;
    finish) finish_item "${1:?slug}" ;;
    config) show_config "${1:-}" ;;
    _base)  base_for "${1:?repo dir}" ;;                          # test hook: the base branch for a repo
    _name)  agent_name "${1:?slug}"; echo ;;                      # test hook: the agent name for a slug
    _label) tab_label "${1:?name}" ;;                             # test hook: the tab label for an agent name
    _pane)  require_herdr; next_pane "${1:?tab}" "${2:?cwd}" ;;   # layout test hook: a pane, no agent
    wait)   require_herdr; herdr agent wait "$(agent_name "${1:?name}")" --timeout "${2:-3600000}" | json "d['result']['agent']['agent_status']" ;;
    *) sed -n '2,21p' "$0"; exit 2 ;;
  esac
}

main "$@"; exit
