#!/usr/bin/env bash
# demo-dash.sh — `swarm.sh dash --watch` on a made-up project, for the README's recording.
# Builds a throwaway board in git, stub herdr and gh on PATH, then changes the state every few
# seconds (a PR merges, a story unblocks, a builder starts, a PR goes green) while the dash watches.
# Nothing real is read: no herdr, no GitHub, no ~/.claude.
#   asciinema rec --window-size 120x34 -c scripts/demo-dash.sh demo.cast && agg demo.cast docs/assets/dash.gif
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
D="$(mktemp -d)"; D="$(cd "${D}" && pwd -P)"
trap 'kill "${director:-0}" 2>/dev/null; rm -rf "${D}"' EXIT
P="${D}/acme-api"; B="${D}/bin"
mkdir -p "${P}/.swarm/state" "${B}" "${D}/pr" "${D}/projects/p" "${D}/tmp"
export TMPDIR="${D}/tmp" CLAUDE_PROJECTS_DIR="${D}/projects"
unset HERDR_ENV
G=(git -C "${P}" -c user.name=demo -c user.email=demo@example.com -c commit.gpgsign=false)
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
item() { # <path under docs> <title> <front-matter line>...
  local path="${P}/docs/$1" title="$2"; shift 2
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
event() { printf '%s\t%s\t%s\t%s\tok\n' "$(ago "$1")" "$2" "$3" "$4" >> "${P}/.swarm/events.tsv"; }
fresh() { rm -f "${TMPDIR}"/swarm-dash-*; }   # dash caches gh and history for a minute
merge() { # <minutes ago> <pr> <slug>: the story's PR deletes its file and merges
  "${G[@]}" checkout -qb "story/$3"
  "${G[@]}" rm -q "docs/stories/$3.md"; echo "$3" >> "${P}/src.txt"; "${G[@]}" add src.txt
  "${G[@]}" commit -qm "$3"; "${G[@]}" checkout -q main
  GIT_COMMITTER_DATE="$(ago "$1")" "${G[@]}" merge -q --no-ff -m "Merge pull request #$2 from acme/story/$3" "story/$3"
}
agents() { # <name:status:pane>... — what the stub herdr reports
  python3 -c 'import json, sys
a = [dict(zip(("name", "agent_status", "pane_id"), x.split(":", 2))) for x in sys.argv[1:]]
for x in a: x["pane_id"] = x["pane_id"].replace("-", ":")
print(json.dumps({"result": {"agents": a}}))
print(json.dumps({"result": {"panes": [{"pane_id": x["pane_id"]} for x in a]}}))' "$@" > "${D}/herdr.json"
}
pr() { printf '{"mergeStateStatus":"CLEAN","statusCheckRollup":[{"__typename":"CheckRun","status":"%s","conclusion":"%s"}]}\n' "$2" "$3" > "${D}/pr/$1"; }

cat > "${B}/herdr" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "agent list") sed -n 1p "${D}/herdr.json" ;;
  "pane list") sed -n 2p "${D}/herdr.json" ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"2026-10-01-rate-limits"}]}}' ;;
  *) exit 1 ;;
esac
STUB
cat > "${B}/gh" <<STUB
#!/bin/sh
f="${D}/pr/\${3##*/}"; [ -f "\$f" ] && cat "\$f" || exit 1
STUB
chmod +x "${B}/herdr" "${B}/gh"

git init -q -b main "${P}"
mkdir -p "${P}/.claude/swarm" && echo "stall_minutes = 240" > "${P}/.claude/swarm/config"
item hld/2026-10-01-rate-limits.md "Rate limits and an audit trail" 'status: agreed'
item epics/rate-limiting.md "Rate limiting" 'status: active' 'hld: 2026-10-01-rate-limits'
item epics/audit-log.md "Audit log" 'status: active' 'hld: 2026-10-01-rate-limits'
item epics/metrics.md "Metrics" 'status: later'
for s in rl-config rl-middleware rl-token-bucket rl-redis-store; do item "stories/${s}.md" "${s}" 'kind: code' 'epic: rate-limiting' 'status: ready'; done
item stories/rl-token-bucket.md "Token bucket per API key" 'kind: code' 'epic: rate-limiting' 'status: review' 'prs: https://github.com/acme/api/pull/41'
item stories/rl-headers.md "RateLimit-* response headers" 'kind: code' 'epic: rate-limiting' 'status: blocked' 'blocked_by: [rl-token-bucket]'
item stories/rl-docs.md "Document the limits" 'kind: docs' 'epic: rate-limiting' 'status: blocked' 'blocked_by: [rl-headers]'
for s in audit-events audit-schema; do item "stories/${s}.md" "${s}" 'kind: code' 'epic: audit-log' 'status: ready'; done
item stories/audit-export.md "Export the audit log as CSV" 'kind: code' 'epic: audit-log' 'status: ready'
item stories/rotate-staging-key.md "Rotate the staging API key" 'kind: lead' 'status: ready'
"${G[@]}" add docs && "${G[@]}" commit -qm board
merge 190 37 rl-config; merge 140 38 rl-middleware; merge 95 39 audit-events

printf 'w1:p1 conductor\nw1:p2 rl-token-bucket\nw1:p3 rl-redis-store\n' > "${P}/.swarm/state/rate-limiting"
printf 'w1:p5 conductor\nw1:p6 audit-schema\n' > "${P}/.swarm/state/audit-log"
T="$(date +%F)"
printf '%s\tconduct\tconduct-rate-limiting\tclaude\topus\thigh\ts1\n%s\tcode\trl-redis-store\tclaude\topus\thigh\ts1\n%s\tcode\trl-token-bucket\tclaude\topus\thigh\ts1\n%s\tconduct\tconduct-audit-log\tclaude\topus\thigh\ts1\n%s\tcode-risky\taudit-schema\tclaude\topus\txhigh\ts1\n' "$T" "$T" "$T" "$T" "$T" > "${P}/.swarm/agents.tsv"
echo '{"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":2000000,"output_tokens":1500000}}}' > "${D}/projects/p/s1.jsonl"
printf '%s\tvacuous-test\thttps://github.com/acme/api/pull/38\ta test that passed with its fix removed\n' "$T" > "${P}/.swarm/findings.tsv"
event 60 conduct rate-limiting w1:p0; event 58 story rl-token-bucket w1:p1; event 57 story rl-redis-store w1:p1
event 40 conduct audit-log w1:p0; event 39 story audit-schema w1:p5; event 12 tell rl-token-bucket w1:p1
event 3 review rl-token-bucket w1:p1
pr 41 COMPLETED SUCCESS
agents conduct-rate-limiting:working:w1-p1 rl-token-bucket:idle:w1-p2 rl-redis-store:working:w1-p3 \
  conduct-audit-log:working:w1-p5 audit-schema:working:w1-p6

# The director: one change every few seconds while the dash watches.
(
  exec >/dev/null 2>&1
  sleep 4; merge 0 41 rl-token-bucket; event 0 close rl-token-bucket w1:p1; fresh
  agents conduct-rate-limiting:working:w1-p1 rl-redis-store:working:w1-p3 conduct-audit-log:working:w1-p5 audit-schema:working:w1-p6
  sleep 3; sed -i.bak -e 's/^status: blocked/status: ready/' -e '/^blocked_by/d' "${P}/docs/stories/rl-headers.md"; rm -f "${P}"/docs/stories/*.bak
  "${G[@]}" commit -qam "unblock rl-headers"; event 0 unblock rl-headers w1:p1; fresh
  sleep 2; echo 'w1:p4 rl-headers' >> "${P}/.swarm/state/rate-limiting"; event 0 story rl-headers w1:p1
  printf '%s\tcode\trl-headers\tclaude\topus\thigh\ts1\n' "$T" >> "${P}/.swarm/agents.tsv"
  agents conduct-rate-limiting:working:w1-p1 rl-redis-store:working:w1-p3 rl-headers:working:w1-p4 conduct-audit-log:working:w1-p5 audit-schema:working:w1-p6
  sleep 3; pr 42 IN_PROGRESS ""
  python3 - "${P}/docs/stories/audit-schema.md" <<'PY'
import sys; p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("status: ready", "status: review\nprs: https://github.com/acme/api/pull/42"))
PY
  "${G[@]}" commit -qam "audit-schema in review"; event 0 review audit-schema w1:p5; fresh
  agents conduct-rate-limiting:working:w1-p1 rl-redis-store:working:w1-p3 rl-headers:working:w1-p4 conduct-audit-log:working:w1-p5 audit-schema:idle:w1-p6
  sleep 4; pr 42 COMPLETED SUCCESS
  printf '%s\tdocs-misstate-code\thttps://github.com/acme/api/pull/42\tthe schema comment named a column that was renamed\n' "$T" >> "${P}/.swarm/findings.tsv"; fresh
) &
director=$!

cd "${P}"
HERDR_ENV=1 PATH="${B}:${PATH}" bash "${SWARM}" dash --watch 1 &
dash=$!
# SIGKILL, so the last frame stays on screen for the recording instead of the screen being restored.
sleep "${DEMO_SECONDS:-20}"; kill -9 "${dash}" 2>/dev/null; wait "${dash}" 2>/dev/null || true
