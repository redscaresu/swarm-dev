#!/usr/bin/env bash
# sonnet_easy_test.sh — sonnet_share picks only code stories marked easy: true. For sonnet_share 1 to
# 5, a slug that lands in the cksum sample is built as code-sonnet with easy: true (trailing spaces or
# a CRLF's \r included) and as code without.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/docs/stories" "${tmp}/.claude/swarm"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
role() { # <slug> <front-matter line>... — write the story, print its _role
  local s="$1"; shift
  { echo ---; echo "status: ready"; printf '%s\n' "$@"; echo ---; } > "${tmp}/docs/stories/${s}.md"
  (cd "${tmp}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" _role "${s}" 2>&1)
}
sampled() { # <n> — the first slug s<i> whose cksum mod n is 0
  local i=0 sum
  while :; do
    sum="$(printf 's%s' "${i}" | cksum)"; sum="${sum%% *}"
    if (( sum % $1 == 0 )); then echo "s${i}"; return; fi
    i=$((i + 1))
  done
}

for n in 1 2 3 4 5; do
  echo "sonnet_share = ${n}" > "${tmp}/.claude/swarm/config"
  s="$(sampled "${n}")"
  check "sonnet_share = ${n}: sampled ${s} is code-sonnet with easy: true, code with easy: false or none" \
    "code-sonnet|code|code" \
    "$(role "${s}" "kind: code" "easy: true")|$(role "${s}" "kind: code" "easy: false")|$(role "${s}" "kind: code")"
  check "sonnet_share = ${n}: sampled ${s} is code-sonnet with a trailing space or a CRLF after easy: true" \
    "code-sonnet|code-sonnet" \
    "$(role "${s}" "kind: code" "easy: true ")|$(role "${s}" "kind: code" $'easy: true\r')"
done

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
