#!/usr/bin/env bash
# pr_contents_test.sh — pr_contents, the shell's reader of a file at a PR's ref, and the three that read
# through it: merge --board's epic guard (merge_read), swarm.sh grants (pr_hld) and merge --release
# (release_check). On merge_fixture.sh, with a stub of gh's contents API in front of its gh: a read of
# <path> at <ref> answers ${FX}/ct/<ref as gh was asked for it>/<path as gh was asked for it>, byte for
# byte; with .500 beside it a 500, and with neither a 404, each with a JSON body on stdout as gh prints
# one. With ${FX}/gone.fail, merge_gone's read of the PR's files fails. The consumers run from a copy
# of the plugin whose pr_contents first logs "<ref> <path>" to ${FX}/spy, so a consumer that stops
# calling it fails.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

# The contents stub. .github/ goes to the fixture's gh (ci_gate reads the workflows there), and so
# does every other call.
mv "${ROOT}/bin/gh" "${ROOT}/bin/gh-fixture"
printf '#!/usr/bin/env bash\nFX="%s"; CT="%s"; LOG="%s"; NEXT="%s"\n' "${FX}" "${FX}/ct" "${ROOT}/gh.log" "${ROOT}/bin/gh-fixture" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
for a in "$@"; do path="${a}"; done
case "$1 ${path}" in
  "api repos/"*/contents/.github/*) ;;
  "api repos/"*/contents/*)
    echo "$*" >> "${LOG}"
    f="${path#repos/*/*/contents/}"; ref="${f##*\?ref=}"; f="${CT}/${ref}/${f%\?ref=*}"
    if [ -f "${f}" ]; then cat "${f}"; exit 0; fi
    if [ -e "${f}.500" ]; then echo '{"message":"Server Error"}'; echo "gh: Internal Server Error (HTTP 500)" >&2; exit 1; fi
    echo '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  # merge_gone's read (--slurp) fails with ${FX}/gone.fail; ci_gate's read of the same files does not.
  "api repos/"*/pulls/*/files*) case " $* " in *" --slurp "*) [ ! -e "${FX}/gone.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; } ;; esac ;;
esac
exec "${NEXT}" "$@"
STUB
chmod +x "${ROOT}/bin/gh"

# The spy: a copy of the plugin whose pr_contents logs each call, then reads as the real one does.
mkdir -p "${ROOT}/plugin"
cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${ROOT}/plugin/"
# shellcheck disable=SC2016 # expanded in the copy's merge.sh, as swarm.sh loads it
{ echo 'eval "real_$(declare -f pr_contents)"'
  printf 'pr_contents() { printf "%%s %%s\\n" "$2" "$3" >> %q; real_pr_contents "$@"; }\n' "${FX}/spy"; } >> "${ROOT}/plugin/bin/lib/merge.sh"
SWARM="${ROOT}/plugin/bin/swarm.sh"

# serve_at <ref> <path> <text> — <path> at <ref>: <text>, byte for byte.
serve_at() { mkdir -p "$(dirname "${FX}/ct/$1/$2")"; printf '%s' "$3" > "${FX}/ct/$1/$2"; }
# item_at <ref> <path> <front-matter line>... — a board file at <ref> with that front matter.
item_at() { serve_at "$1" "$2" "$(printf -- '---\n'; printf '%s\n' "${@:3}"; printf -- '---\n\n# x')"; }
# err_at <ref> <path> — a 500 on <path> at <ref>.
err_at() { mkdir -p "$(dirname "${FX}/ct/$1/$2")"; : > "${FX}/ct/$1/$2.500"; }
# via <ref> <path> — the spy saw pr_contents read <path> at <ref>.
via() { grep -qxF -- "$1 $2" "${FX}/spy" 2>/dev/null; }

# --- pr_contents on its own, from the repo's merge.sh: 0 with the bytes, 1 on a 404, 2 on a 500.
# pc <ref> <path> — pr_contents o/r <ref> <path>, the stub on PATH; sets rc, its stdout in
# ${ROOT}/pc.out and its stderr in ${ROOT}/pc.err.
pc() {
  rc=0
  PATH="${ROOT}/bin:${PATH}" PROJECT_DIR="${P}" bash -c '. "$1/bin/lib/merge.sh"; pr_contents o/r "$2" "$3"' _ "${REPO}" "$1" "$2" \
    > "${ROOT}/pc.out" 2> "${ROOT}/pc.err" || rc=$?
}
fresh
serve_at "${H1}" docs/a.md $'---\nstatus: active\n---\n\n'   # two trailing newlines, which a $(...) would drop
pc "${H1}" docs/a.md
is "pr_contents, ok: exits 0" 0 "${rc}"
check "pr_contents, ok: the file's bytes on stdout" cmp -s "${FX}/ct/${H1}/docs/a.md" "${ROOT}/pc.out"
pc "${H1}" docs/none.md
is "pr_contents, a 404: exits 1" 1 "${rc}"
check "pr_contents, a 404: nothing on stdout" test ! -s "${ROOT}/pc.out"
err_at "${H1}" docs/b.md; pc "${H1}" docs/b.md
is "pr_contents, a 500: exits 2" 2 "${rc}"
check "pr_contents, a 500: gh's error on stderr" grep -qxF "gh: Internal Server Error (HTTP 500)" "${ROOT}/pc.err"
check "pr_contents, a 500: nothing on stdout" test ! -s "${ROOT}/pc.out"
serve_at "${H1}" 'docs/a%23b%3Fc.md' odd
pc "${H1}" 'docs/a#b?c.md'
is "pr_contents, a path holding # and ?: exits 0" 0 "${rc}"
is "pr_contents, a path holding # and ?: reads that file" odd "$(cat "${ROOT}/pc.out")"
check "pr_contents, a path holding # and ?: asks for it quoted" grep -qxF "api -H Accept: application/vnd.github.raw repos/o/r/contents/docs/a%23b%3Fc.md?ref=${H1}" "${ROOT}/gh.log"
serve_at 'r%23s%2Bt' docs/a.md refd
pc 'r#s+t' docs/a.md
is "pr_contents, a ref holding # and +: exits 0" 0 "${rc}"
is "pr_contents, a ref holding # and +: reads that file" refd "$(cat "${ROOT}/pc.out")"
check "pr_contents, a ref holding # and +: asks for it quoted" grep -qxF "api -H Accept: application/vnd.github.raw repos/o/r/contents/docs/a.md?ref=r%23s%2Bt" "${ROOT}/gh.log"

# --- merge_read, through merge --board's epic guard on a board PR that changes docs/epics/e1.md: read
# at the base branch (main) and the head (${H1}).
E=docs/epics/e1.md
NT="--board: ${URL} sets e1 active with no ticket ("
UK="so whether ${URL} sets e1 active with no ticket is unknown"
# board_pr [status] — fresh, no story s, and a board PR whose one file is e1, its status [status]
# (modified by default).
board_pr() { fresh; rm "${S}"; echo "[{\"filename\":\"${E}\",\"status\":\"${1:-modified}\"}]" > "${FX}/files"; }
# guard_read <case> <ref>... — the case read e1 at each <ref> through pr_contents.
guard_read() { local r; for r in "${@:2}"; do check "$1: reads e1 at ${r} through pr_contents" via "${r}" "${E}"; done; }
board_pr; item_at main "${E}" "status: active"; item_at "${H1}" "${E}" "status: active"; merge --board "${URL}"
is "--board, e1 active at both ends: exits 0" 0 "${rc}"
check "--board, e1 active at both ends: merged" merged
guard_read "--board, e1 active at both ends" main "${H1}"
board_pr; item_at "${H1}" "${E}" "status: active"; merge --board "${URL}"
refused "--board, a 404 on e1 at the base: absent, so set active with no ticket" "${NT}"
guard_read "--board, a 404 on e1 at the base" main "${H1}"
board_pr removed; item_at main "${E}" "status: draft"; merge --board "${URL}"
is "--board, a 404 at the head on e1, which the PR removes: exits 0" 0 "${rc}"
check "--board, a 404 at the head on e1, which the PR removes: merged" merged
guard_read "--board, a 404 at the head on e1, which the PR removes" "${H1}"
board_pr removed; item_at main "${E}" "status: draft"; : > "${FX}/gone.fail"; merge --board "${URL}"
refused "--board, a 404 at the head on e1, which the PR removes, when its file list cannot be read: unreadable" "--board: gh cannot read ${E} at 1111111, ${UK}"
guard_read "--board, a 404 at the head on e1, when its file list cannot be read" "${H1}"
board_pr; item_at main "${E}" "status: draft"; merge --board "${URL}"
refused "--board, a 404 at the head on e1, which the PR keeps: unreadable" "--board: gh cannot read ${E} at 1111111, ${UK}"
guard_read "--board, a 404 at the head on e1, which the PR keeps" "${H1}"
board_pr removed; item_at main "${E}" "status: draft"; err_at "${H1}" "${E}"; merge --board "${URL}"
refused "--board, a 500 at the head on e1, which the PR removes: unreadable" "--board: gh cannot read ${E} at 1111111, ${UK}"
guard_read "--board, a 500 at the head on e1" "${H1}"
board_pr; item_at "${H1}" "${E}" "status: active"; err_at main "${E}"; merge --board "${URL}"
refused "--board, a 500 on e1 at the base: unreadable" "--board: gh cannot read ${E} at main, ${UK}"
guard_read "--board, a 500 on e1 at the base" main

# --- pr_hld, through swarm.sh grants on a PR that story s lists: s is under epic g, under the agreed
# HLD h granting merge. The PR's own board files are read at its head (${H1}).
mkdir -p "${P}/docs/hld" "${P}/docs/epics"
printf -- '---\nstatus: agreed\ngrants: [merge]\n---\n\n# h\n' > "${P}/docs/hld/h.md"
printf -- '---\nstatus: active\nhld: h\n---\n\n# g\n' > "${P}/docs/epics/g.md"
UNDER_H="$(printf '%s\nmerge' "${P}/docs/hld/h.md")"
# grants_pr <path> <status> — fresh, s under g and listing the PR, whose one file is <path>, its
# status <status>.
grants_pr() {
  fresh; item s "status: review" "prs: ${URL}" "epic: g"
  echo "[{\"filename\":\"$1\",\"status\":\"$2\"}]" > "${FX}/files"
}
# grants — swarm.sh grants ${URL} in the project; sets rc, its output in ${ROOT}/out.
grants() {
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" \
    bash "${SWARM}" grants "${URL}" > "${ROOT}/out" 2>&1) || rc=$?
}
# The PR adds epic n under h: under h only when n is read at the head and kept.
grants_pr docs/epics/n.md added; item_at "${H1}" docs/epics/n.md "status: draft" "hld: h"; grants
is "grants, an epic the head has: exits 0" 0 "${rc}"
is "grants, an epic the head has: keeps it, so the PR is under h" "${UNDER_H}" "$(cat "${ROOT}/out")"
check "grants, an epic the head has: reads it at the head through pr_contents" via "${H1}" docs/epics/n.md
# The PR deletes story old, under g on the board: a 404 at the head drops it, and the board's copy
# keeps the PR under h.
grants_pr docs/stories/old.md removed; item old "status: ready" "epic: g"; grants
is "grants, a story absent at the head: exits 0" 0 "${rc}"
is "grants, a story absent at the head: drops it, so the PR is under h" "${UNDER_H}" "$(cat "${ROOT}/out")"
check "grants, a story absent at the head: reads it at the head through pr_contents" via "${H1}" docs/stories/old.md
rm "${P}/docs/stories/old.md"
grants_pr docs/epics/n.md added; err_at "${H1}" docs/epics/n.md; grants
is "grants, a 500 on an epic at the head: exits 1" 1 "${rc}"
check "grants, a 500 on an epic at the head: dies naming the file and gh's error" \
  grep -qxF "swarm: grants: gh cannot read docs/epics/n.md at ${URL}'s head: gh: Internal Server Error (HTTP 500)" "${ROOT}/out"
check "grants, a 500 on an epic at the head: reads it through pr_contents" via "${H1}" docs/epics/n.md
rm -rf "${P}/docs/hld" "${P}/docs/epics"

# --- release_check, through merge --release on a PR that bumps .claude-plugin/plugin.json from
# 1.2.0 to 1.3.0: read at origin's main (${MAIN}) and at the head (${H1}).
# The tag is a plain ref, so no tag.gpgSign in the machine's git config turns it into one that needs a message.
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; git -C "${P}" update-ref refs/tags/v1.2.0 HEAD
git -C "${P}" push -q origin HEAD:refs/heads/main v1.2.0; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
MAIN="$(git -C "${ROOT}/origin.git" rev-parse main)"
J=.claude-plugin/plugin.json
# bump [head version] — release_pr, plugin.json at main 1.2.0 and at the head [head version] (1.3.0).
bump() {
  release_pr
  serve_at "${MAIN}" "${J}" '{"name":"x","version":"1.2.0","hooks":{}}'
  serve_at "${H1}" "${J}" "{\"name\":\"x\",\"version\":\"${1:-1.3.0}\",\"hooks\":{}}"
}
# release_read <case> <ref>... — the case read plugin.json at each <ref> through pr_contents.
release_read() { local r; for r in "${@:2}"; do check "$1: reads plugin.json at ${r} through pr_contents" via "${r}" "${J}"; done; }
bump; merge --release "${URL}"
is "--release, 1.2.0 to 1.3.0: exits 0" 0 "${rc}"
check "--release, 1.2.0 to 1.3.0: merged" merged
release_read "--release, 1.2.0 to 1.3.0" "${MAIN}" "${H1}"
bump 1.1.9; merge --release "${URL}"
refused "--release, 1.2.0 to 1.1.9: compares the two" "its version 1.1.9 is not greater than '1.2.0' on main"
release_read "--release, 1.2.0 to 1.1.9" "${MAIN}" "${H1}"
bump; rm "${FX}/ct/${MAIN}/${J}"; merge --release "${URL}"
refused "--release, a 404 on plugin.json at main" "--release: there is no ${J} on main at ${MAIN:0:7}"
release_read "--release, a 404 on plugin.json at main" "${MAIN}"
bump; rm "${FX}/ct/${MAIN}/${J}"; err_at "${MAIN}" "${J}"; merge --release "${URL}"
refused "--release, a 500 on plugin.json at main" "--release: gh cannot read ${J} on main at ${MAIN:0:7}"
release_read "--release, a 500 on plugin.json at main" "${MAIN}"
bump; rm "${FX}/ct/${H1}/${J}"; merge --release "${URL}"
refused "--release, a 404 on plugin.json at the head" "--release: there is no ${J} at 1111111"
release_read "--release, a 404 on plugin.json at the head" "${H1}"
bump; rm "${FX}/ct/${H1}/${J}"; err_at "${H1}" "${J}"; merge --release "${URL}"
refused "--release, a 500 on plugin.json at the head" "--release: gh cannot read ${J} at 1111111"
release_read "--release, a 500 on plugin.json at the head" "${H1}"

finish pr_contents
