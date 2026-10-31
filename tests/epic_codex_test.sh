#!/usr/bin/env bash
# epic_codex_test.sh — every codex run goes through codex-review, and every log-finding line and
# --declined the docs and finding_rule give names its reviewer and reason. Reads the source only.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
SH=("${SWARM}" "$(dirname "${SWARM}")"/lib/*.sh)   # swarm.sh and the bin/lib/*.sh it sources
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

# --- Every codex run goes through codex-review: the arm is the one place that runs codex's review.
REPO="$(dirname "${SWARM}")/.."
check "only codex-review runs codex exec review, and no command tells anyone to" "1|" \
  "$(cat "${SH[@]}" | grep -c 'codex exec review')|$(grep -l 'codex exec review' "${REPO}"/commands/*.md || true)"
# notreviewed <file>... — how many of the files' log-finding lines lack --reviewer, or none when they have none.
notreviewed() { if ! grep -q 'log-finding' "$@"; then echo none; else grep -h 'log-finding' "$@" | grep -vc -- '--reviewer' || true; fi; }
check "every log-finding line of method.md names --reviewer" "none" "$(notreviewed "${REPO}/docs/method.md")"
check "every log-finding line of docs/reference*.md names --reviewer" "0" "$(notreviewed "${REPO}"/docs/reference*.md)"
# bare_declined — each --declined in finding_rule's text or the outer-loop section (from its heading to
# the next ## or the end of whichever docs/reference*.md holds it) that is not followed by a reason
# (out-of-scope, nit, wrong, deferred or the <reason> placeholder), or none.
bare_declined() {
  { sed -n '/^finding_rule() {/,/^}/p' "${SH[@]}"
    awk 'FNR == 1 { on = 0 } /^## / { on = ($0 == "## The outer loop") } on' "${REPO}"/docs/reference*.md; } \
    | grep -oE -- '--declined( +[^ `]+)?' | grep -vE -- '--declined +(out-of-scope|nit|wrong|deferred|<reason>)$' || echo none
}
check "every --declined in finding_rule and the outer-loop paragraph is followed by a reason" "none" "$(bare_declined)"
check "finding_rule names out-of-scope, nit, wrong and --reviewer escaped" "yes|yes|yes|yes" \
  "$(f="$(sed -n '/^finding_rule() {/,/^}/p' "${SH[@]}")"; for w in out-of-scope nit wrong '--reviewer escaped'; do has "${w}" "${f}"; done | paste -sd'|' -)"
check "the conductors' reviewer mapping is written once, in finding_rule" "1" "$(cat "${SH[@]}" | grep -c "<who> is the reviewer that first raised it, whoever passed it on")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
