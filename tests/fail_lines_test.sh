#!/usr/bin/env bash
# fail_lines_test.sh — swarm.sh findings names each test a PR's diff adds whose FAIL line the PR
# body lacks, as rules-unchecked, and mutation_rule tells builders to paste that line. gh is a stub
# on PATH: the PR's body (with its URL) comes from ${FX}/pr.json and its diff from ${FX}/diff.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${FX}" "${ROOT}/bin"
: > "${P}/.claude/swarm/config"
git -C "${P}" init -q
git -C "${P}" remote add origin https://github.com/o/r.git

printf '#!/bin/sh\nFX="%s"\n' "${FX}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$1 $2" in
  "repo view") echo '{"nameWithOwner":"o/r"}' ;;
  "pr view") cat "${FX}/pr.json" ;;
  "pr diff") [ ! -e "${FX}/diff.fail" ] || { echo "gh: HTTP 406: diff exceeded the maximum number of lines" >&2; exit 1; }
             cat "${FX}/diff" ;;
  api*)
    for a in "$@"; do path="${a}"; done
    case "${path}" in
      */pulls/7) echo '{"head":{"sha":"1111111111111111111111111111111111111111"}}' ;;
      */check-runs*) echo '{"check_runs":[]}' ;;
      *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
# body <text> — the PR's body.
body() { python3 -c 'import json, sys; print(json.dumps({"body": sys.argv[1], "url": sys.argv[2]}))' "$1" "${URL}" > "${FX}/pr.json"; }
# unchecked — the rules-unchecked lines findings prints, or all it printed when it failed.
unchecked() {
  local out
  out="$(cd "${P}" && PATH="${ROOT}/bin:${PATH}" env -u SWARM_PROJECT bash "${SWARM}" findings proj 7 2>&1)" \
    || { echo "findings failed: ${out}"; return; }
  grep rules-unchecked <<< "${out}" || true
}

cat > "${FX}/diff" <<'EOF'
diff --git a/foo_test.go b/foo_test.go
--- a/foo_test.go
+++ b/foo_test.go
@@ -1,2 +1,5 @@
 package foo
+func TestFoo(t *testing.T) {
+}
EOF
body "Mutation: broke the fix, the test failed."
check "a new Go test with no FAIL line in the body is rules-unchecked, with the command that logs it" \
  "  rules-unchecked: TestFoo has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"
body $'Mutation:\n    --- FAIL: TestFoo (0.00s)'
check "with its FAIL line in the body, it is not" "" "$(unchecked)"
printf '+func TestFooBar(t *testing.T) {\n+}\n' >> "${FX}/diff"
body "--- FAIL: TestFooBar (0.00s)"
check "TestFooBar's FAIL line does not count for TestFoo" \
  "  rules-unchecked: TestFoo has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

cat > "${FX}/diff" <<'EOF'
diff --git a/tests/x_test.sh b/tests/x_test.sh
--- a/tests/x_test.sh
+++ b/tests/x_test.sh
@@ -1,2 +1,3 @@
 check "an old check" "yes" "$(old)"
+check "a new check" "yes" "$(new)"
+cat > fixture <<'END'
+check "a fixture line" "yes" "$(no)"
 END
+check "a check after the heredoc" "yes" "$(x)"
EOF
body "FAIL an old check: want 'yes', got 'no'"
check "a new check line in tests/*_test.sh is matched the same way, one in a heredoc is not, and an unchanged line ends the heredoc" \
  "  rules-unchecked: a new check has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)
  rules-unchecked: a check after the heredoc has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"
body $'FAIL a new check: want \'yes\', got \'no\'\nFAIL a check after the heredoc: want'
check "with its FAIL line, the check line is not rules-unchecked" "" "$(unchecked)"
# shellcheck disable=SC2016 # the check line's $1 and ${2}, as the diff holds them
printf '+check "$1: says ${2}" "yes" "$(x)"\n+check "costs \\$5 and \\"more\\"" "yes" "$(x)"\n' >> "${FX}/diff"
body $'FAIL a new check: want\nFAIL a check after the heredoc: want\nFAIL merged: says done: want \'yes\'\nFAIL costs $5 and "more": want'
check "a check name's expansions match what they expand to, and its escapes what bash prints" "" "$(unchecked)"
body $'FAIL a new check: want\nFAIL a check after the heredoc: want\nFAIL merged: says done: want \'yes\'\nFAIL costs $6 and "more": want'
check "an escaped dollar is the dollar itself, not an expansion" \
  "  rules-unchecked: costs \\\$5 and \\\"more\\\" has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

# A heredoc whose end word the diff does not show ends with its hunk.
cat > "${FX}/diff" <<'EOF'
diff --git a/tests/x_test.sh b/tests/x_test.sh
--- a/tests/x_test.sh
+++ b/tests/x_test.sh
@@ -1,3 +1,4 @@
+cat > fixture <<'END'
 a
 b
 c
@@ -20,1 +21,2 @@
+check "a check in the next hunk" "yes" "$(x)"
EOF
body "Nothing."
check "a heredoc left open at the end of a hunk does not hide the next hunk's checks" \
  "  rules-unchecked: a check in the next hunk has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

cat > "${FX}/diff" <<'EOF'
diff --git a/tests/x_test.sh b/tests/x_test.sh
--- a/tests/x_test.sh
+++ b/tests/x_test.sh
@@ -1,1 +1,3 @@
+check "empty ${2}x" "yes" "$(x)"
EOF
body "FAIL empty x: want 'yes'"
check "an expansion that prints nothing still matches its FAIL line" "" "$(unchecked)"

cat > "${FX}/diff" <<'EOF'
diff --git a/tests/x_test.sh b/tests/x_test.sh
--- a/tests/x_test.sh
+++ b/tests/x_test.sh
@@ -1,1 +1,3 @@
+n=$((1<<3))
+check "after a shift" "yes" "$(x)"
EOF
body "Nothing."
check "an arithmetic shift is no heredoc" \
  "  rules-unchecked: after a shift has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

cat > "${FX}/diff" <<'EOF'
diff --git a/main_test.go b/main_test.go
--- a/main_test.go
+++ b/main_test.go
@@ -1,1 +1,3 @@
+func TestMain(m *testing.M) { os.Exit(m.Run()) }
+func TestMainPath(t *testing.T) {}
EOF
body "Nothing."
check "TestMain is not a test, though TestMainPath is" \
  "  rules-unchecked: TestMainPath has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

# A check the diff moves is not new; the file it moves to comes first, and its indent changes.
cat > "${FX}/diff" <<'EOF'
diff --git a/tests/a_test.sh b/tests/a_test.sh
--- a/tests/a_test.sh
+++ b/tests/a_test.sh
@@ -1,1 +1,2 @@
 x=1
+  check "a moved check" "yes" "$(x)"
diff --git a/tests/b_test.sh b/tests/b_test.sh
--- a/tests/b_test.sh
+++ b/tests/b_test.sh
@@ -1,2 +1,1 @@
 y=1
-check "a moved check" "yes" "$(x)"
EOF
body "Nothing."
check "a check moved from one test file to another is not rules-unchecked" "" "$(unchecked)"

cat > "${FX}/diff" <<'EOF'
diff --git a/tests/a_test.sh b/tests/a_test.sh
--- a/tests/a_test.sh
+++ b/tests/a_test.sh
@@ -1,3 +1,3 @@
-check "moved down" "yes" "$(x)"
 x=1
+check "moved down" "yes" "$(x)"
+check "new beside it" "yes" "$(x)"
EOF
check "a new check beside one moved in the same file is rules-unchecked, the moved one is not" \
  "  rules-unchecked: new beside it has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"
# shellcheck disable=SC2016 # the check line's $(x), as the diff holds it
printf '+check "moved down" "yes" "$(x)"\n' >> "${FX}/diff"
check "a moved check added twice is new the second time" \
  "  rules-unchecked: new beside it has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)
  rules-unchecked: moved down has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

: > "${FX}/diff.fail"
out="$(cd "${P}" && PATH="${ROOT}/bin:${PATH}" env -u SWARM_PROJECT bash "${SWARM}" findings proj 7 2>&1)" && st=0 || st=$?
check "a diff gh refuses leaves a note that the FAIL lines were not checked, and exits 0" "0|yes" \
  "${st}|$(grep -qF "FAIL lines: not checked, gh pr diff failed on o/r#7" <<< "${out}" && echo yes || echo "no, got: ${out}")"
rm -f "${FX}/diff.fail"

cat > "${FX}/diff" <<'EOF'
diff --git a/foo.go b/foo.go
--- a/foo.go
+++ b/foo.go
@@ -1,1 +1,2 @@
 package foo
+func TestLooksLikeATest() {}
EOF
body "No tests here."
check "a PR that changes no test file prints no rules-unchecked line" "" "$(unchecked)"

cat > "${FX}/diff" <<'EOF'
diff --git a/web/a.test.js b/web/a.test.js
--- a/web/a.test.js
+++ b/web/a.test.js
@@ -1,1 +1,3 @@
+  it("handles \"quoted\" input", () => {});
+  test('another', () => {});
EOF
body $'FAIL handles "quoted" input'
check "a JS it or test call is matched, its escaped quotes as the test prints them" \
  "  rules-unchecked: another has no FAIL line in the PR body (log-finding --reviewer ci rules-unchecked ${URL} …)" \
  "$(unchecked)"

rule="$(sed -n '/^mutation_rule() {/,/^}/p' "${SWARM}" "$(dirname "${SWARM}")"/lib/*.sh)"
check "mutation_rule tells builders to paste each test's FAIL line into the PR body" "yes|yes" \
  "$(grep -qF "paste each test's FAIL line" <<< "${rule}" && echo yes || echo no)|$(grep -qF "into the PR body" <<< "${rule}" && echo yes || echo no)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
