#!/usr/bin/env bash
# skill_test.sh — skills/swarm-dev/SKILL.md names only real commands: every `swarm.sh <sub>` is one of
# swarm.sh's commands (tests/swarm_commands.sh: dispatch's arms, version and update, which main handles
# first, and the ported commands' markers under bin/ported/), and every backticked `/<name>` is a
# plugin command or a Claude Code built-in. Its description carries the trigger phrases; its body is
# short, names no board path, and copies no line from README.md, docs/method.md or docs/reference*.md.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/swarm_commands.sh
source "$(dirname "${BASH_SOURCE[0]}")/swarm_commands.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="${REPO}/skills/swarm-dev/SKILL.md"
BUILTINS="login clear"   # Claude Code's own slash commands the skill may name
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

COMMANDS="$(swarm_commands "${REPO}")" || exit 1
# is_command <sub> — true when <sub> is one of swarm.sh's commands.
is_command() { grep -qxF -- "$1" <<< "${COMMANDS}"; }

# --- Every `swarm.sh <sub>` is a real subcommand; the whole word after it is checked, so a placeholder
# or a capital is named, and a missing one shows as (none).
bad=""
# shellcheck disable=SC2016 # the backtick is literal Markdown
while IFS= read -r sub; do
  [[ -n "${sub}" ]] && is_command "${sub}" || bad="${bad} ${sub:-(none)}"
done < <(grep -o 'swarm\.sh [^ `]*' "${SKILL}" | cut -d' ' -f2 | sort -u)
check "every swarm.sh subcommand is a swarm.sh command" "" "${bad# }"

# --- Every backticked `/<name>` (no further /) is a plugin command or a built-in.
bad=""
# shellcheck disable=SC2016 # the backticks are literal Markdown
while IFS= read -r name; do
  [[ -f "${REPO}/commands/${name}.md" || " ${BUILTINS} " == *" ${name} "* ]] || bad="${bad} /${name}"
done < <(grep -o '`/[^`/]*`' "${SKILL}" | sed 's|^`/||; s|^swarm-dev:||; s|[ `].*||' | sort -u)
check "every /command is a plugin command or a built-in" "" "${bad# }"

# --- The description carries the three trigger phrases.
desc="$(awk 'NR > 1 && /^---$/ { exit } /^description:/' "${SKILL}")"
for phrase in "how to use swarm-dev" "set up a project" "why /swarm-dev:swarm stopped"; do
  check "the description says '${phrase}'" "yes" "$(grep -qF -- "${phrase}" <<< "${desc}" && echo yes || echo no)"
done
check "the front matter names the skill swarm-dev" "yes" "$(grep -qx 'name: swarm-dev' "${SKILL}" && echo yes || echo no)"

# --- The body is short, names the board only through swarm.sh, and copies no line of the docs.
body="$(awk 'f == 2; /^---$/ && f < 2 { f++ }' "${SKILL}")"
check "the body is under 60 lines" "yes" "$([[ $(wc -l <<< "${body}") -lt 60 ]] && echo yes || echo no)"
check "the body names no docs/ or board/ path" "" \
  "$(grep -E '(^|[^A-Za-z_])(docs|board)/' <<< "${body//\$\{CLAUDE_PLUGIN_ROOT\}\/docs\//}" || true)"
copied=""
while IFS= read -r line; do
  [[ ${#line} -ge 40 ]] || continue
  if grep -qFx -- "${line}" "${REPO}/README.md" "${REPO}/docs/method.md" "${REPO}"/docs/reference*.md; then copied="${copied}${line}"$'\n'; fi
done < "${SKILL}"
check "no line of 40+ characters is copied from README.md, docs/method.md or docs/reference*.md" "" "${copied%$'\n'}"

check "docs/method.md is at most 150 lines" "yes" "$([[ $(wc -l < "${REPO}/docs/method.md") -le 150 ]] && echo yes || echo no)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
