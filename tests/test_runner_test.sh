#!/usr/bin/env bash
# test_runner_test.sh — a dash test leaves no ci refresh behind. Its stub runs dash in a fixture
# project with a github.com origin, a build from today and no ci cache, where dash would start a
# detached dash_slow.py refresh, and a gh that hangs, so a refresh that started is still running
# when the test looks. Run through scripts/test.sh with SWARM_PROJECT naming another such project
# (a builder's real one), or alone with SWARM_SLEEP_SCALE set (test mode), it leaves no dash_slow.py
# or swarm.sh naming either; with SWARM_NO_CI_REFRESH set empty, which turns the refresh back on, it
# leaves a dash_slow.py and its swarm.sh flow, so the look can fail. The stub runs swarm.sh through a
# link under the test's marker directory, so both name the marker however the project resolved.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
M="${ROOT}/marker${RANDOM}"   # in every path the stub's dash and a refresh it starts name
# left — the PID of each dash_slow.py or swarm.sh naming M: a refresh and its flow.
left() { pgrep -f "${M}/repo/.*(dash_slow\.py|swarm\.sh)" || true; }
# reap — stop each such refresh, its flow and their gh: each process's children first, by PID.
tree() { local c; for c in $(pgrep -P "$1" || true); do tree "${c}"; done; kill -KILL "$1" 2>/dev/null || true; }
reap() { local p; for p in $(left); do tree "${p}"; done; }
trap 'reap; rm -rf "${ROOT}"' EXIT
# A pgrep that cannot list processes (a sandbox) would see no refresh, and leave the one the last
# check starts: stop before starting any.
pgrep -f . > /dev/null || { echo "FAIL pgrep cannot list processes here"; exit 1; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

mkdir -p "${M}/bin" "${M}/projects"
printf '#!/bin/sh\nexit 1\n' > "${M}/bin/herdr"
printf '#!/bin/sh\nexec sleep 30\n' > "${M}/bin/gh"
chmod +x "${M}/bin/herdr" "${M}/bin/gh"
cp "${REPO}/tests/claude_stub.sh" "${M}/bin/claude"
ln -s "${REPO}" "${M}/repo"
for p in fixture real; do
  mkdir -p "${M}/${p}/docs/stories"; touch "${M}/${p}/docs/stories/README.md"
  git -C "${M}/${p}" init -q && git -C "${M}/${p}" remote add origin "https://github.com/o/${p}.git"
  # A build from today, so a refresh's flow asks gh about its PR, and waits on it.
  mkdir "${M}/${p}/.swarm"; printf '%s\tcode\ts1\tclaude\topus\thigh\t-\n' "$(date +%F)" > "${M}/${p}/.swarm/agents.tsv"
done
cat > "${M}/dash_stub_test.sh" <<EOF
#!/usr/bin/env bash
cd "${M}/fixture" && env -u HERDR_ENV PATH="${M}/bin:\${PATH}" CLAUDE_PROJECTS_DIR="${M}/projects" \\
  bash "${M}/repo/bin/swarm.sh" dash > /dev/null 2>&1 || true
EOF

mkdir "${M}/tmp1"
SWARM_PROJECT="${M}/real" TMPDIR="${M}/tmp1" bash "${REPO}/scripts/test.sh" "${M}/dash_stub_test.sh" > /dev/null 2>&1 || true
check "a dash test run through scripts/test.sh, SWARM_PROJECT set, leaves no dash_slow.py or swarm.sh" "$(left)" ""
reap
# Run alone, as from a builder's pane, the stub must not inherit the real SWARM_PROJECT.
mkdir "${M}/tmp2"
env -u SWARM_PROJECT -u SWARM_NO_CI_REFRESH SWARM_SLEEP_SCALE=0.01 TMPDIR="${M}/tmp2" bash "${M}/dash_stub_test.sh"
check "dash in test mode (SWARM_SLEEP_SCALE set) starts no dash_slow.py or swarm.sh" "$(left)" ""
reap
mkdir "${M}/tmp3"
env -u SWARM_PROJECT SWARM_NO_CI_REFRESH='' SWARM_SLEEP_SCALE=0.01 TMPDIR="${M}/tmp3" bash "${M}/dash_stub_test.sh"
# The refresh starts its flow just after dash returns: up to 10 s for it.
for _ in $(seq 100); do pgrep -f "${M}/repo/.*swarm\.sh flow" > /dev/null && break; sleep 0.1; done
check "with SWARM_NO_CI_REFRESH set empty it leaves a dash_slow.py and its swarm.sh flow, so the looks above can fail" \
  "$(pgrep -f "${M}/repo/.*dash_slow\.py" > /dev/null && echo refresh)|$(pgrep -f "${M}/repo/.*swarm\.sh flow" > /dev/null && echo flow)" "refresh|flow"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
