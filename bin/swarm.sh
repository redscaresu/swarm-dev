#!/usr/bin/env bash
# swarm.sh — run agents in herdr panes so every one can be watched.
#
#   swarm.sh agent <tab> <name> <cwd> <role> <prompt-file>   start one agent in its own pane
#   swarm.sh story <slug>                                   build one <board>/stories/<slug>.md
#   swarm.sh conduct <epic>                                 a fresh conductor for one epic, in a workspace named for its HLD
#   swarm.sh wait <name> [timeout-ms]                       block until the agent settles
#   swarm.sh policy <role>                                  print the model and effort for a role
#   swarm.sh close <name>                                   close a story's pane, a conductor's epic tab, or a tab and its overflow
#   swarm.sh cost [YYYY-MM-DD]                              tokens and estimated cost per role, from the agents' logs
#   swarm.sh next                                           the chain's next step, read from the board (resumable)
#   swarm.sh status [--all]                                 agents that need a look, what waits on you, and the next step
#   swarm.sh unblock                                        mark ready every blocked story whose blockers are all finished
#   swarm.sh finish <slug>                                  take a merged story or epic off the board (delete or mark done)
#   swarm.sh review <slug> <pr-url>...                      a story or epic whose PRs are green and reviewed now waits on a human merge
#   swarm.sh reconcile                                      finish each review item whose PRs all merged; a closed one goes back to ready
#   swarm.sh findings <repo> <pr>                           every check-run note on a PR's head, and its open code-scanning alerts
#   swarm.sh watch [repo...]                                wait until a story or epic PR needs the lead, print why, and exit
#   swarm.sh config [key]                                   the project's settings and where each came from, or one value
#   swarm.sh base <repo>                                    the base branch a repo's stories start from and its PRs go into
#   swarm.sh version                                        the installed version, and a warning when a newer one is out
#   swarm.sh update                                         update the plugin to the newest version
#
# The project is, first match wins: $SWARM_PROJECT; the nearest directory up from here with
# .claude/swarm/config (mapped to the main checkout when it is in a git worktree); the main checkout
# of the git repo you are in. Settings live in .claude/swarm/config (see config below). Must run
# inside herdr (HERDR_ENV=1). An epic gets a tab named for it: the conductor's pane, then a pane per
# story, each named. A story outside any epic gets its own tab. Tabs hold at most four panes (a 2x2
# grid); a fifth agent opens "<tab>-2", and so on, so no pane gets too small to follow.
set -euo pipefail

die() { echo "swarm: $*" >&2; exit 1; }

# The framework itself: this script's repo, whose docs/method.md the briefs point at.
SWARM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where the newest version is published, and the plugin's name in Claude Code. SWARM_LATEST_URL is
# overridable so the tests need no network.
LATEST_URL="${SWARM_LATEST_URL:-https://raw.githubusercontent.com/redscaresu/swarm-dev/main/.claude-plugin/plugin.json}"
PLUGIN=swarm-dev@swarm-dev
MARKETPLACE=swarm-dev

plugin_version() { python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"; }

# show_version — the installed version; when a newer one is published, a warning and how to update.
# A failed lookup (offline) is not an error: /swarm must still run.
show_version() {
  local have latest
  have="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json")"
  echo "swarm-dev ${have}"
  latest="$(curl -fsSL --max-time 5 "${LATEST_URL}" 2>/dev/null | plugin_version 2>/dev/null)" || return 0
  python3 -c "import sys; v=lambda s: tuple(int(x) for x in s.split('.')); sys.exit(v(sys.argv[2]) <= v(sys.argv[1]))" \
    "${have}" "${latest}" || return 0
  cat <<EOF
WARNING: swarm-dev ${latest} is out; this is ${have}. To update, run:
  swarm.sh update
then restart Claude Code so the new version is loaded.
EOF
}

# update_plugin — fetch the newest version. Claude Code loads it on its next start.
update_plugin() {
  claude plugin marketplace update "${MARKETPLACE}"
  claude plugin update "${PLUGIN}"
  echo "Restart Claude Code to load the new version."
}

# Neither needs a project: they run before one is looked for.
case "${1:-}" in
  version) show_version; exit ;;
  update)  update_plugin; exit ;;
esac

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
CFG_merge=human         # human: no agent merges; a PR that is ready waits on the board for you
CFG_review_bot=off      # auto: the conductor also runs the repo's PR review bot (docs/review.md)
CFG_sign_commits=false  # true: every commit and merge is signed, or the agent stops
CFG_pr_per=story        # epic: stories merge into epic/<slug>, and each repo gets one PR per epic
CFG_keep_panes=false    # true: `close` leaves a finished agent's pane and tabs open to read
CONFIG_KEYS="board_dir repos_dir base_branches finished merge review_bot sign_commits pr_per keep_panes"
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
      merge)
        [[ "${value}" == human || "${value}" == agent ]] || die "${where}: merge must be human or agent, not '${value}'" ;;
      review_bot)
        [[ "${value}" == off || "${value}" == auto ]] || die "${where}: review_bot must be off or auto, not '${value}'" ;;
      sign_commits|keep_panes)
        [[ "${value}" == true || "${value}" == false ]] || die "${where}: ${key} must be true or false, not '${value}'" ;;
      pr_per)
        [[ "${value}" == story || "${value}" == epic ]] || die "${where}: pr_per must be story or epic, not '${value}'" ;;
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

# require_trusted <cwd> — stop unless Claude Code already trusts <cwd>. In an untrusted folder,
# Claude Code opens its "do you trust this folder?" prompt, and the agent stalls there unseen.
# Claude Code keys trust on the git root, and for a worktree on its main checkout, so a new story
# worktree is covered once its repo is trusted. Outside git, a trusted ancestor covers it. Trust
# lives in ~/.claude.json, which every running session rewrites, so this only reads it; if the
# file cannot be read, the start goes ahead.
require_trusted() {
  local cwd="$1" in_git="" root gitdir common
  if root=$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null); then
    in_git=git
    # A linked worktree's git dir differs from the shared one: trust is keyed on the main checkout.
    # A submodule's are the same (.git/modules/<name>), so it keeps its own top level.
    gitdir=$(git -C "${cwd}" rev-parse --path-format=absolute --git-dir)
    common=$(git -C "${cwd}" rev-parse --path-format=absolute --git-common-dir)
    [[ "${gitdir}" == "${common}" ]] || root="$(dirname "${common}")"
  else
    root="$(cd "${cwd}" && pwd -P)"
  fi
  python3 - "${root}" "${CLAUDE_CONFIG_DIR:-${HOME}}/.claude.json" "${in_git}" <<'PY' \
    || die "Claude Code does not trust ${root} yet, so the agent would stall on its trust prompt. Run claude in ${root} once, accept the prompt, then try again."
import json, os, sys
root, config, in_git = sys.argv[1], sys.argv[2], sys.argv[3] == "git"
try:
    projects = json.load(open(config)).get("projects", {})
except (OSError, ValueError):
    sys.exit(0)
paths = [root]
while not in_git and os.path.dirname(paths[-1]) != paths[-1]:
    paths.append(os.path.dirname(paths[-1]))
sys.exit(0 if any(projects.get(p, {}).get("hasTrustDialogAccepted") is True for p in paths) else 1)
PY
}

# next_pane <tab-label> <cwd> — a fresh shell pane in a tab with room, creating tabs as needed.
# prune_dead_panes <state> — drop the panes herdr no longer has (closed by hand), so the next split
# targets a live pane. Left alone when herdr cannot list its panes.
prune_dead_panes() {
  local live
  live=$(herdr pane list 2>/dev/null | json "' '.join(p['pane_id'] for p in d['result']['panes'])" 2>/dev/null) || return 0
  awk -v live=" ${live} " 'index(live, " " $1 " ")' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

next_pane() {
  local label="$1" cwd="$2" name="${3:-}" n=1 state panes count pane
  mkdir -p "${STATE_DIR}"
  while :; do
    local tab_label="${label}"; [[ ${n} -gt 1 ]] && tab_label="${label}-${n}"
    state="${STATE_DIR}/${tab_label}"
    [[ -f "${state}" ]] && prune_dead_panes "${state}"
    count=0; [[ -f "${state}" ]] && count=$(wc -l < "${state}" | tr -d ' ')
    if [[ ${count} -lt ${PANES_PER_TAB} ]]; then
      if [[ ${count} -eq 0 ]]; then
        pane=$(herdr tab create --workspace "${HERDR_WORKSPACE_ID}" --cwd "${cwd}" --label "${tab_label}" --no-focus \
          | json "d['result']['root_pane']['pane_id']")
      else
        # 2x2: 2nd splits the first to the right, 3rd splits the first down, 4th splits the second down.
        read -r -a panes <<< "$(awk '{ print $1 }' "${state}" | tr '\n' ' ')"
        case ${count} in
          1) pane=$(herdr pane split "${panes[0]}" --direction right --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          2) pane=$(herdr pane split "${panes[0]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
          3) pane=$(herdr pane split "${panes[1]}" --direction down  --cwd "${cwd}" --no-focus | json "d['result']['pane']['pane_id']") ;;
        esac
      fi
      [[ -n "${pane}" ]] || die "herdr could not open a pane in tab ${tab_label}"
      [[ -z "${name}" ]] || herdr pane rename "${pane}" "${name}" >/dev/null 2>&1 || true
      echo "${pane}${name:+ ${name}}" >> "${state}"
      echo "${pane}"
      return
    fi
    n=$((n + 1))
  done
}

start_agent() {
  local tab="$1" name cwd="$3" role="$4" prompt_file="$5" pane_name="${6:-$2}" kind model effort pane
  name="$(agent_name "$2")"   # the one place names are mapped, so `wait <same name>` always finds it
  [[ -f "${prompt_file}" ]] || die "no prompt file ${prompt_file}"
  read -r kind model effort <<< "$(policy "${role}")"
  # Before the pane opens, so a refusal leaves no empty pane behind.
  if [[ "${kind}" == claude ]]; then require_trusted "${cwd}"; fi
  free_agent_name "${name}"
  pane=$(next_pane "${tab}" "${cwd}" "${pane_name}")
  # A freshly split pane is not always an available shell yet (agent_pane_busy): retry once.
  local try out
  for try in 1 2; do
    if [[ "${kind}" == codex ]]; then
      # No update check: codex's startup prompt to upgrade takes the pane, and the brief then
      # lands in a bare shell.
      out=$(herdr agent start "${name}" --kind codex --pane "${pane}" --timeout 60000 -- \
        -s read-only -c "model_reasoning_effort=\"${effort}\"" -c check_for_update_on_startup=false 2>&1) && break
    else
      # merge = human: no agent can run `gh pr merge`. `gh api` could still merge, so the briefs say it too.
      local guard=()
      [[ "${CFG_merge}" == human ]] && guard=(--disallowedTools "Bash(gh pr merge:*)")
      out=$(herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- \
        --model "${model}" --effort "${effort}" --permission-mode auto ${guard[@]+"${guard[@]}"} 2>&1) && break
    fi
    if [[ ${try} -eq 2 ]]; then
      # Close the pane rather than leave an empty shell; next_pane prunes it from the tab record.
      herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
      die "${name}: herdr could not start the agent: ${out}"
    fi
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

# API_ERROR_NUDGES: how many times one `wait` re-prompts an agent whose turn died on an API error.
# Enough to ride out a dropped stream; few enough that a hard error (a bad key) still surfaces.
API_ERROR_NUDGES=3

# ended_on_api_error <name> — true when the agent's last event (Claude Code marks each with ⏺)
# is an API error, such as "The response stopped arriving". The agent then sits idle, its work
# unfinished, and nothing else will wake it.
ended_on_api_error() {
  herdr agent read "$1" --source recent-unwrapped 2>/dev/null | grep '⏺' | tail -1 | grep -q '⏺ API Error'
}

# wait_agent <name> <timeout-ms> — block until the agent settles and print its status. An agent idle
# after an API error has not settled: tell it to carry on, and wait again.
wait_agent() {
  local name="$1" timeout="$2" status nudges=0
  while :; do
    status=$(herdr agent wait "${name}" --timeout "${timeout}" | json "d['result']['agent']['agent_status']")
    if [[ "${status}" != idle || ${nudges} -ge ${API_ERROR_NUDGES} ]] || ! ended_on_api_error "${name}"; then
      break
    fi
    nudges=$((nudges + 1))
    echo "swarm: ${name} stopped on an API error; telling it to carry on (${nudges}/${API_ERROR_NUDGES})" >&2
    herdr agent prompt "${name}" "Your last turn ended on an API error. Carry on from where you stopped." \
      --wait --until working --timeout 60000 >/dev/null 2>&1 || true
  done
  echo "${status}"
}

# The merge, signing and review rules, shared by the briefs.
merge_rule() {
  if [[ "${CFG_merge}" == human ]]; then echo "Never merge, by any route (a human merges)."
  else echo "Never merge (the lead merges)."; fi
}
sign_rule() { echo "Sign every commit and merge with -S. If signing fails, stop and report that you are blocked; never commit unsigned."; }
sign_rule_if_on() { [[ "${CFG_sign_commits}" != true ]] || printf '\n\n%s' "$(sign_rule)"; }
review_bot_rule() {
  [[ "${CFG_review_bot}" == auto ]] || return 0
  printf '\n\nThen run the PR review bot of the repo as %s/docs/review.md says, and clear its findings the same way.' "${SWARM_HOME}"
}
conduct_merge_rule() {
  if [[ "${CFG_merge}" == human ]]; then
    cat <<'RULE'
Never merge a PR, by any route: not `gh pr merge`, not `gh api`, not the web page. A human merges.
When a story's PR is green and reviewed, run `swarm.sh review <slug> <PR URL>` and
`swarm.sh close <slug>`, then carry on with stories that do not wait on it. A story that does wait
stays blocked until the human merges and `/swarm` reconciles the board. When every story left
in the epic is in review and the epic's **Done when** will hold once they merge, run
`swarm.sh review <epic> <every PR URL still waiting>`: the epic leaves the board once they all merge.
RULE
  else
    cat <<'RULE'
Merge a PR only when it is green, then run `swarm.sh unblock` and `swarm.sh close <slug>` to close
that story's tab. If a merged story is still open on the board once you have pulled (its file is
there and not `status: done`), run `swarm.sh finish <slug>` first. When the epic's **Done when**
holds, take the epic off the board with `swarm.sh finish <epic>`.
RULE
  fi
}

# The brief every story builder gets. The story file is the task; these are the rules.
story_brief() {
  local slug="$1" src="$2" base="$3" epic_branch="${4:-}" story_ref cleanup rel epic check extra="" before
  if [[ -n "${epic_branch}" ]]; then
    story_ref="${BOARD}/stories/${slug}.md"
    [[ ${BOARD_IN_REPO} == 1 && "${src}" == "${PROJECT_DIR}" ]] && story_ref="${BOARD#"${PROJECT_DIR}/"}/stories/${slug}.md"
    cleanup="Do not touch the story file; the conductor takes it off the board."
  elif [[ "${src}" == "${PROJECT_DIR}" && ${BOARD_IN_REPO} == 1 ]]; then
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
  if [[ -n "${epic_branch}" ]]; then
    before="reply"
    cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} $(merge_rule) Never touch real cloud or
credentials. This project opens one PR per epic, so open no PR: commit on your branch,
story/${slug}, and push it; the conductor merges it into \`${epic_branch}\`. Run
\`codex exec review --base origin/${epic_branch}\` before committing; fix real findings, decline
nits with a reason, and converge on one clean pass. If codex reports a usage limit, do not wait for
it to reset: carry on without it and say so. Run the repo's tests and make them pass. When your
branch is pushed, reply with the branch, what changed in three lines, and the codex findings, then
stop.
EOF
  else
    before="open the PR"
    cat <<EOF
Implement ${story_ref}. Its **Done when** is the acceptance.

Title your commit and PR with a plain description of the change.

Rules: read AGENTS.md first. ${cleanup} $(merge_rule) Never touch real cloud or
credentials. Open the PR against \`${base}\`. Run \`codex exec review --base origin/${base}\` before
committing; fix real findings, decline nits with a reason, converge on one clean pass, and record the
loop in the PR body. If codex reports a usage limit, do not wait for it to reset: carry on without it
and write "codex skipped: usage limit" in the PR body. If \`gh pr view --json mergeable\` says
CONFLICTING, merge origin/${base} into your branch, resolve it (keep both sides of any list), re-run
the tests and push: a conflicted PR runs no checks and waits forever. When CI is green, reply with
the PR URL, what changed in three lines, and the codex findings, then stop.
EOF
  fi
  epic="$(fm "${BOARD}/stories/${slug}.md" epic)"
  check=""; [[ -n "${epic}" && -f "${BOARD}/epics/${epic}.md" ]] && check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || extra+="Before you ${before}, also run the epic's check from the worktree root, and make it pass: \`${check}\`"$'\n'
  [[ "${CFG_sign_commits}" != true ]] || extra+="$(sign_rule)"$'\n'
  [[ -z "${extra}" ]] || printf '%s' "${extra}"
  if [[ -f "${PROJECT_BRIEF}" ]]; then
    echo
    cat "${PROJECT_BRIEF}"
  fi
}

# agent_kind — true for a kind a swarm agent may build; an empty kind means code. Anything else,
# lead or a typo, stays with the lead, so an unknown kind can never reach an agent.
agent_kind() {
  case "$1" in ""|code|docs|chore|verify) return 0 ;; *) return 1 ;; esac
}

build_story() {
  local slug="$1" story="${BOARD}/stories/$1.md" kind risk repo src role wt branch prompt base epic from epic_branch
  [[ -f "${story}" ]] || die "no story ${story}"
  grep -q '^status: ready$' "${story}" || die "${slug} is not status: ready"
  kind=$(sed -n 's/^kind: *//p' "${story}" | head -1); kind="${kind:-code}"
  case "${kind}" in
    code|docs|chore|verify) ;;
    lead) die "${slug} is kind: lead — real cloud, credentials or a human step; the lead runs it, not a swarm agent" ;;
    operator) die "${slug} is kind: operator, which is now kind: lead: change it, and mark the user's step **You:**" ;;
    *) die "${slug} has kind: ${kind}; an agent builds only code, docs, chore or verify" ;;
  esac
  risk=$(sed -n 's/^risk: *//p' "${story}" | head -1)
  repo=$(sed -n 's/^repo: *//p' "${story}" | head -1)   # a repo in repos_dir; empty is the project's own
  role="${kind}"; [[ "${kind}" == code && "${risk}" == high ]] && role=code-risky
  policy "${role}" >/dev/null
  src="$(repo_dir "${repo}")" || die "${slug}: ${src}"
  # Before the epic branch and the worktree exist, so a refusal leaves nothing to clean up.
  require_trusted "${src}"
  base="$(base_for "${src}")"
  epic="$(fm "${story}" epic)"; from="origin/${base}"; epic_branch=""
  if [[ "${CFG_pr_per}" == epic && -n "${epic}" ]]; then
    [[ -f "${BOARD}/epics/${epic}.md" ]] || die "${slug}: no epic ${BOARD}/epics/${epic}.md"
    epic_branch="$(epic_branch_for "${src}" "${epic}" "${base}")"; from="origin/${epic_branch}"
    add_epic_repo "${epic}" "${repo:-$(basename "${PROJECT_DIR}")}"
  fi
  branch="story/${slug}"; wt="$(worktree_for "${src}" "${slug}")"
  git -C "${src}" worktree add -q -b "${branch}" "${wt}" "${from}"
  prompt="${PROJECT_DIR}/.swarm/briefs/${slug}.md"; mkdir -p "$(dirname "${prompt}")"
  story_brief "${slug}" "${src}" "${base}" "${epic_branch}" > "${prompt}"
  # An epic's story gets a pane in the epic's tab; a one-off gets a tab of its own.
  start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}"
}

# epic_branch_for <repo-dir> <epic> <base> — epic/<epic>, fetched from origin; pushed there from
# <base> the first time a story of the epic is built in that repo.
epic_branch_for() {
  local src="$1" b="epic/$2"
  if ! git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" 2>/dev/null; then
    git -C "${src}" push -q origin "refs/remotes/origin/$3:refs/heads/${b}" || die "${src}: cannot push ${b}"
    git -C "${src}" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}"
  fi
  echo "${b}"
}

# add_epic_repo <epic> <repo> — list <repo> on the epic's repos: line, the repos with an epic
# branch. It is how a fresh conductor finds the branches, and how `next` sees a stalled epic.
add_epic_repo() {
  local f="${BOARD}/epics/$1.md"
  [[ " $(fm "${f}" repos) " == *" $2 "* ]] && return 0
  awk -v r="$2" '
    /^---$/ { n++ }
    n == 1 && /^repos:/ { print $0 " " r; d = 1; next }
    n == 2 && !d { print "repos: " r; d = 1 }
    { print }' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
}

# The brief a conductor gets: one epic, from a fresh session, so its context holds only that epic.
conduct_brief() {
  local epic="$1"
  cat <<EOF
You are the conductor for the epic ${BOARD}/epics/${epic}.md. Read AGENTS.md (and STATUS.md if there
is one), ${SWARM_HOME}/docs/method.md and the epic first.

EOF
  if [[ "${CFG_pr_per}" == epic ]]; then conduct_epic_mode "${epic}"; else conduct_story_mode "${epic}"; fi
  cat <<EOF

Stay inside this epic: start no story outside it, and leave the HLD and other epics alone. A
story whose \`kind\` is set and is not code, docs, chore or verify (a \`lead\` story: real cloud, credentials, a human step) is not yours to run; list it
for the user. Stop when the epic's **Done when** holds or when nothing ready is left.

Your last act, after everything else: write your report (what merged, what is left, what waits on
the user) to ${PROJECT_DIR}/.swarm/conduct-${epic}.report.md, then reply with the same. The lead
treats that file as the only sign you have finished: being idle while you wait on your own
background work is not.
EOF
}

# The green rule every conductor follows, whatever it opens PRs for.
green_rule() {
  cat <<EOF
A PR is green only when every check on its head has passed and you have triaged the output of
\`${SWARM_HOME}/bin/swarm.sh findings <repo> <pr>\`: the notes on every check run, whatever its
conclusion, and open code-scanning alerts. Fix each real one; rebut the rest with a reason in the
PR (scanners often flag a name, not a value). Never change code only to silence a scanner, and
never dismiss an alert.$(review_bot_rule)
EOF
}

# pr_per = story: a PR per story.
conduct_story_mode() {
  local epic="$1"
  cat <<EOF
Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) to merge, as method.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap,
start each with \`${SWARM_HOME}/bin/swarm.sh story <slug>\`, wait with \`swarm.sh wait\` and
\`swarm.sh watch --epic ${epic}\` in the background, and review each PR. Each story's base branch is in its brief,
.swarm/briefs/<slug>.md.

$(green_rule)

$(conduct_merge_rule)$(sign_rule_if_on)
EOF
}

# pr_per = epic: stories merge into epic/<epic>, and each repo gets one PR for the whole epic.
conduct_epic_mode() {
  local epic="$1" check sign="" merge_step tick='`'
  check="$(fm "${BOARD}/epics/${epic}.md" check)"
  [[ -z "${check}" ]] || check=" and the epic check ${tick}${check}${tick}"
  [[ "${CFG_sign_commits}" != true ]] || sign=" -S"
  if [[ "${CFG_merge}" == human ]]; then
    merge_step="Never merge a PR, by any route: not \`gh pr merge\`, not \`gh api\`, not the web page. A human
merges. When every PR is green and reviewed, run \`swarm.sh review ${epic} <every PR URL>\`."
  else
    merge_step="Merge each PR once it is green, then run \`swarm.sh finish ${epic}\`."
  fi
  cat <<EOF
This project opens one PR per epic, not per story. \`${SWARM_HOME}/bin/swarm.sh story <slug>\`
starts each builder on story/<slug>, branched from epic/${epic}; builders push their branch and open
no PR. Drive the epic's stories (${BOARD}/stories/*.md with \`epic: ${epic}\`) as method.md
§ Building describes: pick waves of \`ready\` stories whose \`touches\` do not overlap, start each,
and wait with \`swarm.sh wait <slug>\` in the background.

When a builder reports, review its branch. Then, one story at a time, merge it into the epic branch
in a worktree of epic/${epic} beside its repo (../<repo>-wt/epic-${epic}):
\`git merge --no-ff${sign} origin/story/<slug>\`, run the repo's tests${check} there,
and push epic/${epic}. Then run \`swarm.sh finish <slug>\`, \`swarm.sh unblock\` and
\`swarm.sh close <slug>\`, and go on to the next wave.

When the epic's stories are all finished (a fresh conductor may start here; the epic's \`repos:\`
line lists every repo with an epic branch), review the whole epic: in each repo's epic worktree,
\`codex exec review --base origin/<base>\`, where \`swarm.sh base <repo>\` prints the base. Fix real
findings on the epic branch and rebut the rest. Then open one PR per repo from epic/${epic} into its
base, written for a reader who knows nothing of how it was built: what changes and why, with no
waves, stories or board names. If a PR from epic/${epic} is already open, update its body instead,
keeping any structure someone wrote by hand. Wait on the PRs with \`swarm.sh watch --epic ${epic}\`
in the background.

$(green_rule)

${merge_step}$(sign_rule_if_on)
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

# conductor_report <agent> — where a conductor writes its report as its last act.
conductor_report() { echo "${PROJECT_DIR}/.swarm/conduct-$(conduct_epic "$1").report.md"; }

# conduct_epic <agent> — the epic a conductor's agent name is for. The name may be cut at 32
# characters, so it is matched against the conductors started here (their briefs), which outlive
# the epic's own file. Two long epics can share a cut name; the newest brief is the one running.
conduct_epic() {
  local f e want
  want="$(agent_name "$1")"
  # shellcheck disable=SC2012 # newest first; brief names are epic slugs, [a-z0-9-]
  while IFS= read -r f; do
    e="$(basename "${f}" .md)"; e="${e#conduct-}"
    [[ "$(agent_name "conduct-${e}")" == "${want}" ]] && { echo "${e}"; return; }
  done < <(ls -t "${PROJECT_DIR}/.swarm/briefs"/conduct-*.md 2>/dev/null)
  echo "${want#conduct-}"
}

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
  # On exit, not after start_agent: a conductor that fails to start dies, and left the tab empty.
  # shellcheck disable=SC2064 # expand now; the tab id is herdr's, [a-zA-Z0-9:]
  [[ -z "${placeholder}" ]] || trap "herdr tab close '${placeholder}' >/dev/null 2>&1 || true" EXIT
  HERDR_WORKSPACE_ID="${ws}" start_agent "${epic}" "conduct-${epic}" "${PROJECT_DIR}" conduct "${prompt}" conductor
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

# epic_has_open_stories <epic> — true while any story of <epic> is still on the board and not done.
epic_has_open_stories() {
  local s
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] && open_item "${s}" && return 0
  done < <(board stories)
  return 1
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
#   conduct <epic>    an active epic has a story an agent can build, or (pr_per = epic) every story
#                     merged into its epic branch and no PR yet
#   resume <slug>     a one-off already started (its worktree exists): wait for it, then review
#   story <slug>      a ready story outside any epic
#   plan-epic <epic>  an active epic has no stories yet
#   plan-hld <hld>    an agreed HLD has no epics listed under ## Epics
#   hld <hld>         an HLD is still a draft
#   gate              only the user can move the board: lead stories, blocked
#                     stories, later stories and epics, and PRs awaiting the user's merge
#   done              nothing open; start the next HLD with /hld <title>
next_step() {
  local f slug epic kind story_epic src buildable="" waiting=""
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    # Any status: idle is not finished. Only the conductor's report file says it is done.
    # A retired conductor (renamed <name>-done, -done2 ...) has finished: never wait on it.
    slug=$(herdr agent list 2>/dev/null | json "next((a['name'] for a in d['result']['agents'] if a.get('name','').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done')),'')" 2>/dev/null || true)
    if [[ -n "${slug}" ]]; then
      if [[ -f "$(conductor_report "${slug}")" ]]; then
        echo "collect ${slug}"; echo "the conductor ${slug} has finished and written its report"
      else
        echo "wait ${slug}"; echo "the conductor ${slug} is still working (it has not written its report)"
      fi
      return
    fi
  fi
  # Stories an agent can build: ready, and of a kind an agent builds. "<epic> <slug>" per line.
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == ready ]] || continue
    kind=$(fm "${f}" kind)
    agent_kind "${kind}" || continue
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
  if [[ "${CFG_pr_per}" == epic ]]; then
    # Stories went into the epic branch (repos: says where) and none is left, but the epic is still
    # active, not in review: its conductor stopped before the PRs. A fresh one picks it up there.
    while IFS= read -r f; do
      [[ "$(fm "${f}" status)" == active && -n "$(fm "${f}" repos)" ]] || continue
      epic=$(basename "${f}" .md)
      epic_has_open_stories "${epic}" && continue
      echo "conduct ${epic}"; echo "every story of ${epic} is in its epic branch, and the epic has no PR yet"; return
    done < <(board epics)
  fi
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
  waiting="$(waiting_on_user)"
  if [[ -n "${waiting}" ]]; then
    echo "gate"; echo "only you can move the board now:"; printf '%s\n' "${waiting}"; return
  fi
  echo "done"; echo "nothing is open; start the next HLD with /hld <title>"
}

# waiting_on_user — one line per board item only the user can move: lead stories, blocked and later
# items, and PRs awaiting the user's merge. Shared by next_step's gate and status.
waiting_on_user() {
  local f kind slug waiting=""
  while IFS= read -r f; do
    kind=$(fm "${f}" kind); slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      ready) agent_kind "${kind}" || waiting+="  ${kind}: ${slug}"$'\n' ;;
      blocked) waiting+="  blocked: ${slug} (by $(fm "${f}" blocked_by))"$'\n' ;;
      later) waiting+="  later story: ${slug}"$'\n' ;;
      review) waiting+="  awaiting your merge: ${slug} $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board stories)
  while IFS= read -r f; do
    case "$(fm "${f}" status)" in
      later) waiting+="  later epic: $(basename "${f}" .md)"$'\n' ;;
      review) waiting+="  awaiting your merge: epic $(basename "${f}" .md) $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board epics)
  printf '%s' "${waiting%$'\n'}"
}

# open_item <file> — true while a board item is still open: its file exists and is not status: done.
open_item() { [[ -f "$1" && "$(fm "$1" status)" != "done" ]]; }

# unblock — a finished story is deleted or marked done, so a blocked story whose every blocked_by slug
# is no open story or epic, and names no hand step, is ready. Prints each story it flips.
unblock() {
  local story slug blockers b open
  while IFS= read -r story; do
    grep -q '^status: blocked$' "${story}" || continue
    blockers=$(sed -n 's/^blocked_by: *\[\(.*\)\]$/\1/p' "${story}" | tr ',' ' ')
    [[ -n "${blockers// /}" ]] || continue   # blocked for a reason no merge clears
    open=0
    for b in ${blockers}; do
      # Open while its story exists, its epic exists, or it is not a plain slug (a hand step such
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

# item_file <slug> — the story or epic file for <slug>.
item_file() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "bad slug '$1'"
  if [[ -f "${BOARD}/stories/$1.md" ]]; then echo "${BOARD}/stories/$1.md"
  elif [[ -f "${BOARD}/epics/$1.md" ]]; then echo "${BOARD}/epics/$1.md"
  else die "no story or epic '$1' in ${BOARD}"; fi
}

# set_status <file> <status> [prs] — in the front matter, set the status line and replace the prs
# line with [prs], or drop it when [prs] is empty.
set_status() {
  awk -v st="$2" -v prs="${3:-}" '
    /^---$/ { n++ }
    n == 1 && /^prs: / { next }
    n == 1 && !d && /^status: / { print "status: " st; if (prs != "") print "prs: " prs; d = 1; next }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# review <slug> <pr-url>... — the item's PRs are green and reviewed and wait on a human merge.
mark_review() {
  local f url
  f="$(item_file "${1:?slug}")"; shift
  [[ $# -gt 0 ]] || die "review: name the PR URLs"
  for url in "$@"; do
    [[ "${url}" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$ ]] || die "review: not a PR URL: ${url}"
  done
  set_status "${f}" review "$*"
  echo "review: $(basename "${f}" .md) $*"
}

# reconcile — for each item in review: finish it once every PR it lists has merged; send it back to
# ready, saying which, if any closed without merging; otherwise leave it waiting.
reconcile() {
  local f slug url state closed waiting urls merged=() merged_prs=()
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == review ]] || continue
    slug="$(basename "${f}" .md)"
    read -r -a urls <<< "$(fm "${f}" prs)"
    if [[ ${#urls[@]} -eq 0 ]]; then echo "in review with no prs: line: ${slug}"; continue; fi
    closed=""; waiting=0
    for url in "${urls[@]}"; do
      if ! state="$(gh pr view "${url}" --json state | json "d['state']")"; then
        echo "cannot read ${url}; ${slug} stays in review"; waiting=1; continue
      fi
      case "${state}" in
        MERGED) ;;
        CLOSED) closed+=" ${url}" ;;
        *) waiting=1 ;;
      esac
    done
    if [[ -n "${closed}" ]]; then
      set_status "${f}" ready
      echo "back to ready: ${slug} (closed without merging:${closed})"
    elif [[ ${waiting} -eq 0 ]]; then
      merged+=("${slug}"); merged_prs+=("${urls[*]}")
    fi
  done < <(board stories; board epics)
  [[ ${#merged[@]} -gt 0 ]] || return 0
  local i committed
  if [[ ${BOARD_IN_REPO} == 1 ]]; then
    # The board is in the project repo, and a merged PR may itself have taken the item off it. Our
    # review edit would block that pull, so undo just that edit first, and redo it if the pull fails.
    for slug in "${merged[@]}"; do
      f="$(item_file "${slug}")"
      if committed="$(git -C "${PROJECT_DIR}" show "HEAD:${f#"${PROJECT_DIR}"/}" 2>/dev/null)"; then
        set_status "${f}" "$(sed -n 's/^status: *//p' <<< "${committed}" | head -1)"
      fi
    done
    if git -C "${PROJECT_DIR}" rev-parse -q --verify '@{upstream}' >/dev/null \
      && ! git -C "${PROJECT_DIR}" pull -q --ff-only; then
      for i in "${!merged[@]}"; do set_status "$(item_file "${merged[i]}")" review "${merged_prs[i]}"; done
      die "reconcile: cannot pull ${PROJECT_DIR}; pull it by hand, then run reconcile again"
    fi
  fi
  for slug in "${merged[@]}"; do
    f="${BOARD}/stories/${slug}.md"; [[ -f "${f}" ]] || f="${BOARD}/epics/${slug}.md"
    [[ -f "${f}" && "$(fm "${f}" status)" != "done" ]] || { echo "merged: ${slug}"; continue; }
    finish_item "${slug}"
  done
}

# findings <repo> <pr> — what a green check can hide: the notes (annotations) on every check run of
# the PR's head, whatever its conclusion, and the PR's open code-scanning alerts.
findings() {
  local src full sha
  src="$(repo_dir "${1:?repo}")" || die "findings: ${src}"
  [[ "${2:?pr}" =~ ^[0-9]+$ ]] || die "findings: not a PR number: $2"
  full="$(gh repo view "$(git -C "${src}" remote get-url origin)" --json nameWithOwner | json "d['nameWithOwner']")" \
    || die "no GitHub origin for ${src}"
  sha="$(gh api "repos/${full}/pulls/$2" | json "d['head']['sha']")" || die "cannot read ${full}#$2"
  echo "${full}#$2 at ${sha:0:7}"
  local id name
  while IFS=$'\t' read -r id name; do
    [[ -n "${id}" ]] || continue
    gh api "repos/${full}/check-runs/${id}/annotations?per_page=100" | python3 -c '
import json, sys
for a in json.load(sys.stdin):
    msg = (a.get("message") or "").splitlines() or [""]
    print("  check %s: %s %s:%s %s" % (sys.argv[1], a.get("annotation_level"), a.get("path"), a.get("start_line"), msg[0]))' "${name}"
  done < <(gh api "repos/${full}/commits/${sha}/check-runs?per_page=100" | python3 -c '
import json, sys
for c in json.load(sys.stdin)["check_runs"]:
    if c["output"].get("annotations_count"):
        print("%s\t%s (%s)" % (c["id"], c["name"], c.get("conclusion")))')
  local alerts
  if alerts="$(gh api "repos/${full}/code-scanning/alerts?ref=refs/pull/$2/merge&state=open&per_page=100" 2>/dev/null)"; then
    python3 -c '
import json, sys
for a in json.load(sys.stdin):
    r, inst = a["rule"], a["most_recent_instance"]
    loc, msg = inst["location"], (inst["message"]["text"].splitlines() or [""])[0]
    sev = r.get("security_severity_level") or r.get("severity")
    print("  alert #%s %s %s %s:%s %s" % (a["number"], sev, r.get("id"), loc.get("path"), loc.get("start_line"), msg))' <<< "${alerts}"
  else
    echo "  code scanning: not available on ${full}"
  fi
}

# watch [--epic <slug>] [repo...] — block until a story/* or epic/* PR in these repos needs the lead, print
# one line saying which and why, and exit 0. With --epic, only that epic's PRs count (epic/<slug> and
# its stories' story/<slug> branches), and the default repos are its stories' repos: a conductor
# must not wake for another epic's PR on the same board. A PR needs the lead when its checks on a new head have all finished,
# when it conflicts with its base (a conflicted PR runs no checks, so waiting on checks never ends),
# or when its head has had no check at all for WATCH_STALL_SECS (default 600). A herdr agent
# blocked on a prompt also needs the lead. Each head is reported once (state in .swarm/state).
watch_prs() {
  local epic="" stories=("${BOARD}"/stories/*.md) epic_heads="" f
  if [[ "${1:-}" == --epic ]]; then
    epic="${2:?watch --epic needs an epic slug}"; shift 2
    [[ -f "${BOARD}/epics/${epic}.md" ]] || die "watch: no epic ${BOARD}/epics/${epic}.md"
    stories=(); epic_heads="epic/${epic}"
    for f in "${BOARD}"/stories/*.md; do
      [[ -f "${f}" && "$(fm "${f}" epic)" == "${epic}" ]] || continue
      stories+=("${f}"); epic_heads="${epic_heads} story/$(basename "${f}" .md)"
    done
  fi
  local repos=("$@") seen="${STATE_DIR}/watch-seen" stall="${WATCH_STALL_SECS:-600}" repo n sha br mergeable age total pending
  # Default: the project (when it is a repo) plus every repo a story names, so a new repo needs no edit here.
  if [[ ${#repos[@]} -eq 0 ]]; then
    local own=""; [[ ${PROJECT_IS_GIT} == 1 ]] && own="$(basename "${PROJECT_DIR}")"
    read -r -a repos <<< "${own} $( (( ${#stories[@]} )) && sed -n 's/^repo: *//p' "${stories[@]}" 2>/dev/null | sort -u | tr '\n' ' ')"
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
        [[ -z "${epic_heads}" || " ${epic_heads} " == *" ${br} "* ]] || continue
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
        -q '.[]|select(.headRefName|startswith("story/") or startswith("epic/"))|"\(.number) \(.headRefOid) \(.headRefName) \(.mergeable) \((now - (.updatedAt|fromdateiso8601))|floor)"')
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

# status [--all] — one summary for the user: the agents that need a look or are working, what is
# waiting on them, and what `next` would do; idle agents and blocked stories are only counted unless
# --all. A pane with no agent in it is shown as empty: a start that failed. Panes closed by hand are
# left out.
status_report() {
  local all="${1:-}" agents panes waiting
  if [[ "${HERDR_ENV:-}" == 1 ]] && agents=$(herdr agent list 2>/dev/null) && panes=$(herdr pane list 2>/dev/null); then
    python3 - "${STATE_DIR}" "${agents}" "${panes}" "${all}" <<'PY'
import glob, json, os, sys
state, agents_json, panes_json, show_all = sys.argv[1:5]
try:
    agents = {a.get("pane_id"): a for a in json.loads(agents_json)["result"]["agents"]}
    live = {p["pane_id"] for p in json.loads(panes_json)["result"]["panes"]}
except (ValueError, KeyError):
    print("Agents\n  (herdr gave no agent list)"); sys.exit(0)
rows, seen = [], set()
for path in sorted(glob.glob(os.path.join(state, "*"))):
    if not os.path.isfile(path) or path.endswith(".tmp"):
        continue
    for line in open(path):
        f = line.split()
        if not f or f[0] not in live or f[0] in seen:
            continue
        seen.add(f[0])
        pane, name = f[0], (f[1] if len(f) > 1 else "-")
        a = agents.get(pane)
        if a is None:
            what = "EMPTY: no agent started in this pane; close it"
        else:
            name = a.get("name") or name
            st = a.get("agent_status") or "unknown"
            if st == "working":
                what = "working"
            elif st == "blocked":
                what = f"WAITING on a question: herdr agent read {name}"
            elif name.endswith("-done") or "-done" in name[-7:]:
                what = "done (retired)"
            elif st in ("idle", "done"):
                what = "idle: finished, or waiting for its next step"
            else:
                what = st
        rows.append((name, what, f"{os.path.basename(path)} {pane}"))
quiet = [r for r in rows if r[1].startswith(("idle", "done"))]
shown = rows if show_all == "--all" else [r for r in rows if r not in quiet]
counts = [f"{len(rows) - len(quiet)} need a look or are working", f"{len(quiet)} idle or done"]
print("Agents: " + ", ".join(counts) if rows else "Agents: none open")
width = max((len(r[0]) for r in shown), default=0)
for name, what, where in shown:
    print(f"  {name:<{width}}  {what}  [{where}]")
if quiet and show_all != "--all":
    print("  (swarm.sh status --all lists them all)")
PY
  else
    echo "Agents: not inside herdr, so their states are not available"
  fi
  echo; echo "Waiting on you"
  waiting="$(waiting_on_user)"
  if [[ "${all}" != --all ]]; then
    local blocked
    blocked=$(grep -c '^  blocked:' <<< "${waiting}" || true)
    waiting="$(grep -v '^  blocked:' <<< "${waiting}" || true)"
    [[ "${blocked}" -eq 0 ]] || waiting+="${waiting:+$'\n'}  ${blocked} blocked stories wait on others (swarm.sh status --all lists them)"
  fi
  if [[ -n "${waiting}" ]]; then printf '%s\n' "${waiting}"; else echo "  nothing"; fi
  echo; echo "Next"
  next_step | sed 's/^/  /'
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

# close_agent <name> — close what was opened for <name>: its pane, or its tab when that was the
# tab's last pane. A conductor's name closes its epic's tabs, with any story panes left in them.
# With keep_panes = true, everything stays open to read, and the agent is only retired.
close_agent() {
  local state pane epic
  if [[ "${CFG_keep_panes}" == true ]]; then retire_agent "$1"; return; fi
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    pane="$(awk -v n="$1" 'NF > 1 && $2 == n { print $1; exit }' "${state}")"
    [[ -n "${pane}" ]] || continue
    if [[ $(wc -l < "${state}") -le 1 ]]; then close_tabs "$(basename "${state}")"; return; fi
    herdr pane close "${pane}" >/dev/null
    awk -v p="${pane}" '$1 != p' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
    echo "closed pane $1"; return
  done
  if [[ "$(agent_name "$1")" == conduct-* ]]; then
    epic="$(conduct_epic "$1")"
    close_tabs "${epic}"
  fi
  close_tabs "$1"
}

# free_agent_name <name> — herdr refuses a name already in use (agent_name_taken). With
# keep_panes = true a finished agent keeps its name, so a second run reusing it (a second epic's
# `lead`) failed and left an empty pane. Retire a finished holder; refuse a working one. Runs
# before any pane opens.
free_agent_name() {
  local status
  status=$(agent_status "$1")
  case "${status}" in
    "") return 0 ;;
    working|blocked) die "$1: an agent with this name is still ${status}; wait for it, or use another name" ;;
  esac
  retire_agent "$1" >/dev/null
  [[ -z "$(agent_status "$1")" ]] || die "$1: the name is still taken after retiring it; close its pane (herdr agent list), or use another name"
}

# agent_status <name> — herdr's status for the agent called <name>, or nothing if there is none.
agent_status() {
  herdr agent list 2>/dev/null | json "next((a.get('agent_status','') or 'unknown' for a in d['result']['agents'] if a.get('name')=='$1'),'')" 2>/dev/null || true
}

# retire_agent <name> — leave <name>'s pane open, but free its name for the next agent (a story
# retried, a new conductor for the epic): herdr renames the agent <name>-done, and the pane keeps
# its slot in the tab's state under that name, so no later agent is split into it.
retire_agent() {
  local name state new i
  name="$(agent_name "$1")"
  # A name reused more than once already has a <name>-done; take the first free suffix.
  new="${name:0:27}-done"
  for i in 2 3 4 5 6 7 8 9; do
    [[ -z "$(agent_status "${new}")" ]] && break
    new="${name:0:26}-done${i}"
  done
  herdr agent rename "${name}" "${new}" >/dev/null 2>&1 || true
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    awk -v n="$1" 'NF > 1 && $2 == n { $2 = n "-done" } { print }' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
  done
  echo "kept $1 open (keep_panes)"
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
    close)  require_herdr; close_agent "${1:?name}" ;;
    unblock) unblock ;;
    next)   next_step ;;
    status) status_report "${1:-}" ;;
    cost)   cost_report "${1:-}" ;;
    watch)  watch_prs "$@" ;;
    finish) finish_item "${1:?slug}" ;;
    review) mark_review "$@" ;;
    reconcile) reconcile ;;
    findings) findings "${1:?repo}" "${2:?pr}" ;;
    config) show_config "${1:-}" ;;
    base)   src="$(repo_dir "${1:-}")" || die "${src}"; base_for "${src}" ;;
    _base)  base_for "${1:?repo dir}" ;;                          # test hook: the base branch for a repo
    _name)  agent_name "${1:?slug}"; echo ;;                      # test hook: the agent name for a slug
    _label) tab_label "${1:?name}" ;;                             # test hook: the tab label for an agent name
    _trusted) require_trusted "${1:?cwd}"; echo trusted ;;        # test hook: whether Claude Code trusts a folder
    _pane)  require_herdr; next_pane "${1:?tab}" "${2:?cwd}" "${3:-}" ;;   # layout test hook: a pane, no agent
    wait)   require_herdr; wait_agent "$(agent_name "${1:?name}")" "${2:-3600000}" ;;
    *) sed -n '2,26p' "$0"; exit 2 ;;
  esac
}

main "$@"; exit
