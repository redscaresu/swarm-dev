#!/usr/bin/env bash
# flow_panes_test.sh — `swarm.sh flow`'s panes section (bin/lib/flow_panes.py) against a fixture
# events.tsv, its times in minutes before now, each line with its pane and version=0.30.1 unless it says
# otherwise. A handover is a review-finished line, then a review line, from the review agent's pane.
# s-a hands over at -130, merges at -120 and its pane closes at -110: merge, 10. s-b hands over at -150
# and closes at -105: handover, 45. s-c hands over at -60 and never closes (a builder's pane-closed line
# of s-c is no close of its review pane): open, 60. s-dee's pane is retired, so its close names
# review-s-dee-long-st-done, and its merge names the PR URL its review line gave: merge, 5, paired by
# slug= and pane=. s-e closes on a 0.30.0 `close review-s-e` line: handover, 20. s-k's retired pane p10
# hands over at -75 and stays open; its new pane p11 hands over at -72 and closes at -65, with a 0.30.1
# `close review-s-k` line after its pane-closed line, which closes no other pane: p10 open, 75, and p11
# closed, 7. s-m merges at -140 and reads `merged elsewhere` at -100, its pane never closed: merge,
# open, 140 from the first merge. s-h hands over twice in one pane and its close follows the second by
# 10 minutes. s-r's first review pane (p7) hands over at -100 and stays open while a second one (p8)
# hands over at -88; p7 closes at -80: p7 is handover 20, closed, and p8 open, 88. s-f's review agent
# starts and closes with no handover, and the lead's own review line for it has no review-finished line
# before it: no review pane. s-g's handover is from 0.30.0, which logged no pane-closed lines, and never
# closes: unlogged. Then a log with s-c's lines alone, no close line in it at all: s-c still reads open
# and counts. TZ is UTC.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories"
git -C "${P}" init -q
U=https://github.com/o/r/pull
# write_events <file> [slug...]: the fixture's lines in time order, or only those of the slugs given.
write_events() {
  python3 - "$@" "${U}" <<'PY2'
import datetime, sys
now = datetime.datetime.now(datetime.timezone.utc)
path, keep, u = sys.argv[1], set(sys.argv[2:-1]), sys.argv[-1]
lines = [  # minutes, command, target, pane, outcome, slug it belongs to
    (-400, "review-finished", "s-g", "w1:p1", "ok ~~ verdict=pass", "s-g"),
    (-400, "review", "s-g", "w1:p1", f"ok ({u}/7) ~~ version=0.30.0", "s-g"),
    (-300, "pane-closed", "b1", "w1:p0", "ok ~~ pane=w1:p9 slug=b1 role=builder", "b1"),
    (-160, "review-finished", "s-m", "w1:p12", "ok ~~ verdict=pass", "s-m"),
    (-160, "review", "s-m", "w1:p12", f"ok ({u}/12)", "s-m"),
    (-140, "merge", "s-m", "w1:p12", "ok", "s-m"),
    (-100, "merge", "s-m", "w1:p0", "merged elsewhere", "s-m"),
    (-150, "review-finished", "s-b", "w1:p3", "ok ~~ verdict=pass", "s-b"),
    (-150, "review", "s-b", "w1:p3", f"ok ({u}/2) ~~ round=1 verdict=pass", "s-b"),
    (-130, "review-finished", "s-a", "w1:p2", "ok ~~ verdict=pass", "s-a"),
    (-130, "review", "s-a", "w1:p2", f"ok ({u}/1)", "s-a"),
    (-125, "merge", "s-a", "w1:p2", "the head abc1234 is not green: test failed", "s-a"),
    (-120, "merge", "s-a", "w1:p2", "ok", "s-a"),
    (-110, "pane-closed", "review-s-a", "w1:p0", "ok ~~ pane=w1:p2 slug=s-a role=review", "s-a"),
    (-105, "pane-closed", "review-s-b", "w1:p0", "ok ~~ pane=w1:p3 slug=s-b role=review", "s-b"),
    (-100, "review-finished", "s-h", "w1:p5", "ok ~~ verdict=pass", "s-h"),
    (-100, "review", "s-h", "w1:p5", f"ok ({u}/8)", "s-h"),
    (-100, "review-finished", "s-r", "w1:p7", "ok ~~ verdict=pass", "s-r"),
    (-100, "review", "s-r", "w1:p7", f"ok ({u}/9)", "s-r"),
    (-95, "review-finished", "s-dee-long-story-slug", "w1:p4", "ok ~~ verdict=pass", "s-dee-long-story-slug"),
    (-95, "review", "s-dee-long-story-slug", "w1:p4", f"ok ({u}/4)", "s-dee-long-story-slug"),
    (-90, "merge", f"{u}/4", "w1:p0", "ok", "s-dee-long-story-slug"),
    (-88, "review-finished", "s-r", "w1:p8", "ok ~~ verdict=pass", "s-r"),
    (-88, "review", "s-r", "w1:p8", f"ok ({u}/9)", "s-r"),
    (-85, "pane-closed", "review-s-dee-long-st-done", "w1:p0", "ok ~~ pane=w1:p4 slug=s-dee-long-story-slug role=review", "s-dee-long-story-slug"),
    (-80, "review-finished", "s-e", "w1:p6", "ok ~~ verdict=pass", "s-e"),
    (-80, "review", "s-e", "w1:p6", f"ok ({u}/5)", "s-e"),
    (-80, "pane-closed", "review-s-r-done", "w1:p0", "ok ~~ pane=w1:p7 slug=s-r role=review", "s-r"),
    (-75, "review-finished", "s-k", "w1:p10", "ok ~~ verdict=pass", "s-k"),
    (-75, "review", "s-k", "w1:p10", f"ok ({u}/11)", "s-k"),
    (-72, "review-finished", "s-k", "w1:p11", "ok ~~ verdict=pass", "s-k"),
    (-72, "review", "s-k", "w1:p11", f"ok ({u}/11)", "s-k"),
    (-200, "review-agent", "s-f", "w1:p0", "ok", "s-f"),
    (-190, "pane-closed", "review-s-f", "w1:p0", "ok ~~ pane=w1:p13 slug=s-f role=review", "s-f"),
    (-70, "review", "s-f", "w1:p0", f"ok ({u}/6)", "s-f"),
    (-60, "review-finished", "s-c", "w1:p1", "ok ~~ verdict=pass", "s-c"),
    (-60, "review", "s-c", "w1:p1", f"ok ({u}/3)", "s-c"),
    (-60, "close", "review-s-e", "w1:p0", "ok ~~ version=0.30.0", "s-e"),
    (-65, "pane-closed", "review-s-k", "w1:p0", "ok ~~ pane=w1:p11 slug=s-k role=review", "s-k"),
    (-65, "close", "review-s-k", "w1:p0", "ok", "s-k"),
    (-50, "review-finished", "s-h", "w1:p5", "ok ~~ verdict=pass", "s-h"),
    (-50, "review", "s-h", "w1:p5", f"ok ({u}/8)", "s-h"),
    (-40, "pane-closed", "review-s-h", "w1:p0", "ok ~~ pane=w1:p5 slug=s-h role=review", "s-h"),
    (-30, "pane-closed", "s-c", "w1:p0", "ok ~~ pane=w1:p1 slug=s-c role=builder", "b1"),
]
with open(path, "w") as out:
    for m, cmd, target, pane, outcome, slug in sorted(lines, key=lambda line: line[0]):   # stable: a minute keeps its order
        if keep and slug not in keep:
            continue
        if "version=" not in outcome:
            outcome += (" " if " ~~ " in outcome else " ~~ ") + "version=0.30.1"
        t = (now + datetime.timedelta(minutes=m)).strftime("%Y-%m-%dT%H:%M:%SZ")
        out.write(f"{t}\t{cmd}\t{target}\t{pane}\t{outcome}\n")
PY2
}
write_events "${P}/.swarm/events.tsv"

panes() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=panes bash "${SWARM}" flow "$@" | grep -v '^## panes$'); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(panes)"
rows="$(sed -n '1,/^$/p' <<< "${out}" | sed '/^$/d')"
check "one row per review pane, in start order: from its merge or handover to its pane's first close, open with its minutes so far" \
  "${rows}" "$(printf '%s\n' $'story\tfrom\tminutes\tpane' \
    $'s-g\thandover\t-\tunlogged' \
    $'s-b\thandover\t45\tclosed' \
    $'s-m\tmerge\t140\topen' \
    $'s-a\tmerge\t10\tclosed' \
    $'s-r\thandover\t20\tclosed' \
    $'s-dee-long-story-slug\tmerge\t5\tclosed' \
    $'s-r\thandover\t88\topen' \
    $'s-e\thandover\t20\tclosed' \
    $'s-k\thandover\t75\topen' \
    $'s-k\thandover\t7\tclosed' \
    $'s-c\thandover\t60\topen' \
    $'s-h\thandover\t10\tclosed')"
check "after a blank line, over_30 counts the rows past 30 minutes, the open one too, never an unlogged one" \
  "$(sed -n '/^$/,$p' <<< "${out}")" $'\nover_30\n5'
check "a window with no merge or handover prints the header and over_30 0" \
  "$(panes --until 2020-01-01)" $'story\tfrom\tminutes\tpane\n\nover_30\n0'
write_events "${P}/.swarm/events.tsv" s-c
[[ "$(cut -f2 "${P}/.swarm/events.tsv" | tr '\n' ' ')" == "review-finished review " ]] || { echo "FAIL the s-c fixture is not its two lines"; exit 1; }
check "an open pane past 30 minutes counts in a log with no close line at all" \
  "$(panes)" $'story\tfrom\tminutes\tpane\ns-c\thandover\t60\topen\n\nover_30\n1'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
