#!/usr/bin/env bash
# runner_binary_test.sh — make test builds ./cmd/swarm once, before any test file starts, and hands it
# to every test in SWARMDEV_BIN. Each case runs make test in a copy of the tree with no .git: the
# Makefile, scripts/, cmd/ and go.mod, its cmd/swarm holding only a main.go that prints a word of this
# test's own, and test files of its own, with a go wrapper first on PATH that logs each call. Over two
# files the run passes, both files see one SWARMDEV_BIN, which prints the copy's word, not the outer
# tree's, and go ran one build.
# A make test of the copy that a test of that run starts, nested or top-level (TEST_SH_RUN unset),
# builds nothing and sees the run's binary. With no go on PATH, the run fails in one line naming go
# before any test file runs, and so does a main.go that does not compile, printing Go's error and the
# build line; both even with SWARMDEV_BIN exported by the caller. A copy with no go.mod builds
# nothing, says so in one line and unsets SWARMDEV_BIN.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
REAL_GO="$(command -v go)" || { echo "FAIL go is not on PATH, and make test needs it"; exit 1; }
# The copy's builds use go's cache under the real HOME: one under the HOME below would start empty,
# and a build from an empty cache takes many seconds.
GOCACHE="$(go env GOCACHE)"; export GOCACHE
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"   # the top-level run below finds no cap in the real ~/.swarm/test-cap
mkdir -p "${HOME}"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
# lines <pattern> <text> — how many lines of <text> match the shell pattern.
# shellcheck disable=SC2053 # $1 is a pattern
lines() { local l n=0; while IFS= read -r l; do [[ "${l}" == $1 ]] && n=$((n + 1)); done <<< "$2"; echo "${n}"; }
# ran <output> <seen file> — whether any test file of the run started: a "run" line, or a line it wrote.
ran() {
  if [[ "$(lines 'run *' "$1")" != 0 || -s "$2" ]]; then echo "a test file ran"; else echo "no test file ran"; fi
}
# builds <go log> — how many go build calls the wrapper logged there: "none" when it logged no call.
builds() { if [[ -s "$1" ]]; then lines '*build*./cmd/swarm*' "$(cat "$1")"; else echo none; fi; }

C="${ROOT}/copy"
mkdir -p "${C}/tests"
cp -R "${REPO}/Makefile" "${REPO}/scripts" "${REPO}/cmd" "${REPO}/go.mod" "${C}/"
CP="$(cd "${C}" && pwd -P)"   # the tree as scripts/test.sh names it
WORD="copy-word-${RANDOM}${RANDOM}"
# Only the main.go below: the tree's other cmd/swarm files import internal/, which the copy leaves out,
# so they would fail its build.
rm -f "${C}"/cmd/swarm/*.go
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("%s") }\n' "${WORD}" > "${C}/cmd/swarm/main.go"
# A test file of the copy writes a line to $SEEN: its name, the SWARMDEV_BIN it sees and what that prints.
# shellcheck disable=SC2016 # the test file's own shell expands these
printf '%s\n' '#!/usr/bin/env bash' 'n="$(basename "$0" _test.sh)"' \
  'printf "%s\t%s\t%s\n" "${n}" "${SWARMDEV_BIN-unset}" "$("${SWARMDEV_BIN:-false}" 2>&1)" >> "${SEEN}"' > "${C}/tests/a_test.sh"
cp "${C}/tests/a_test.sh" "${C}/tests/b_test.sh"
# nest and top write their own line, then start a make test of the copy over a_test.sh, its lines in
# <name>.seen and its go calls in <name>.go; top's has TEST_SH_RUN unset, a top-level run.
for x in nest:'' top:'-u TEST_SH_RUN'; do
  n="${x%%:*}"
  { cat "${C}/tests/a_test.sh"
    printf 'exec env %s SEEN="%s/%s.seen" GO_LOG="%s/%s.go" make -s -C "%s" test TESTS=tests/a_test.sh SERIAL= SLOW= JOBS=1\n' \
      "${x#*:}" "${ROOT}" "${n}" "${ROOT}" "${n}" "${C}"
  } > "${C}/tests/${n}_test.sh"
done
# same_bin <name> — "same" when the make test that test <name> started saw a SWARMDEV_BIN, and it is the
# one test <name> saw in run two; else what each saw, so a run that wrote no line fails too.
same_bin() {
  local inner outer
  inner="$(cut -f2 "${ROOT}/$1.seen")" || inner=""
  outer="$(awk -F'\t' -v n="$1" '$1 == n { print $2 }' "${ROOT}/two.seen")" || outer=""
  if [[ -n "${inner}" && "${inner}" == "${outer}" ]]; then echo same; else echo "saw '${inner}', run two '${outer}'"; fi
}
# The go wrapper, first on PATH for each run: it logs its arguments to $GO_LOG, then runs the real go.
mkdir -p "${ROOT}/wrap"
# shellcheck disable=SC2016 # the wrapper's own shell expands these
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "${GO_LOG:?}"\nexec "%s" "$@"\n' "${REAL_GO}" > "${ROOT}/wrap/go"
chmod +x "${ROOT}/wrap/go"
# A binary a caller exported: it prints its own word, so a test that saw it would say so.
printf '#!/bin/sh\necho caller-bin\n' > "${ROOT}/caller-bin"; chmod +x "${ROOT}/caller-bin"
# mk <case> <env>... — make test in the copy over a_test.sh and b_test.sh, with the wrapper first on PATH
# and these settings, its lines in <case>.seen and its go calls in <case>.go: its output, then its
# exit on the last line.
mk() {
  local c="$1" rc=0 o
  shift
  o="$(env PATH="${ROOT}/wrap:${PATH}" SEEN="${ROOT}/${c}.seen" GO_LOG="${ROOT}/${c}.go" "$@" \
    make -s -C "${C}" test TESTS="${TESTS:-tests/a_test.sh tests/b_test.sh}" SERIAL= SLOW= JOBS=2 2>&1)" || rc=$?
  printf '%s\n%s\n' "${o}" "${rc}"
}

# The copy's own binary, built once and seen by both files.
o="$(mk one)"
check "make test over two files in the copy passes" "$(tail -1 <<< "${o}")" 0
bin="$(cut -f2 "${ROOT}/one.seen" | sort -u)" || bin=""
check "both files see one SWARMDEV_BIN, not the one this test inherited, and it prints the copy's word" \
  "$(cut -f1 "${ROOT}/one.seen" | sort | tr '\n' ' ')|$(grep -c '' <<< "${bin}")|$([[ "${bin}" != "${SWARMDEV_BIN:-}" ]] && echo "its own")|$(cut -f3 "${ROOT}/one.seen" | sort -u)" \
  "a b |1|its own|${WORD}"
check "the run made one go build" "$(builds "${ROOT}/one.go")" 1
check "the run printed the build line" "$(lines "build: go build -o */bin/swarm ./cmd/swarm, in ${CP}" "${o}")" 1

# A make test of the copy that a test of its run starts reuses the run's binary, nested or top-level.
o="$(TESTS="tests/nest_test.sh tests/top_test.sh" mk two)"
check "a run whose tests start a make test of the copy, nested and top-level, passes and builds once" \
  "$(tail -1 <<< "${o}")|$(builds "${ROOT}/two.go")" "0|1"
check "the nested make test builds nothing and sees the run's binary" \
  "$(builds "${ROOT}/nest.go")|$(same_bin nest)" \
  "none|same"
check "the top-level make test (TEST_SH_RUN unset) builds nothing and sees the run's binary" \
  "$(builds "${ROOT}/top.go")|$(same_bin top)" \
  "none|same"

# No go on PATH: each directory of PATH that holds a go is replaced by a copy of it, as links, without go.
nogo="" i=0
IFS=: read -r -a dirs <<< "${PATH}"
for d in "${dirs[@]}"; do
  [[ -n "${d}" && -d "${d}" ]] || continue
  if [[ -e "${d}/go" ]]; then
    i=$((i + 1)); mkdir -p "${ROOT}/nogo/${i}"
    ln -s "${d}"/* "${ROOT}/nogo/${i}/" && rm -f "${ROOT}/nogo/${i}/go"
    d="${ROOT}/nogo/${i}"
  fi
  nogo+="${nogo:+:}${d}"
done
check "the PATH with no go has make and bash, and no go" \
  "$(env PATH="${nogo}" bash -c 'command -v make > /dev/null && echo make; command -v go || echo "no go"')" $'make\nno go'
o="$(rc=0; env PATH="${nogo}" SEEN="${ROOT}/nogo.seen" SWARMDEV_BIN="${ROOT}/caller-bin" \
  make -s -C "${C}" test TESTS="tests/a_test.sh tests/b_test.sh" SERIAL= SLOW= JOBS=2 2>&1 || rc=$?; echo "${rc}")"
check "with no go on PATH, make test fails in one line naming go, and no test file runs, even with SWARMDEV_BIN exported" \
  "$([[ "$(tail -1 <<< "${o}")" != 0 ]] && echo fails)|$(lines "test.sh: ${CP} has go.mod, so make test builds ./cmd/swarm, and go is not on PATH: install Go (go.mod names the version) or put it on PATH; no test file runs without the binary" "${o}")|$(ran "${o}" "${ROOT}/nogo.seen")" \
  "fails|1|no test file ran"

# A main.go that does not compile.
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("%s" }\n' "${WORD}" > "${C}/cmd/swarm/main.go"
o="$(mk broken SWARMDEV_BIN="${ROOT}/caller-bin")"
check "with a main.go that does not compile, make test fails with Go's error, the build line and its failure, and no test file runs, even with SWARMDEV_BIN exported" \
  "$([[ "$(tail -1 <<< "${o}")" != 0 ]] && echo fails)|$(lines '*main.go:[0-9]*:[0-9]*: syntax error*' "${o}")|$(lines "build: go build -o */bin/swarm ./cmd/swarm, in ${CP}" "${o}")|$(lines "test.sh: the build of ./cmd/swarm in ${CP} failed (go build exit 1), so no test file runs" "${o}")|$(ran "${o}" "${ROOT}/broken.seen")" \
  "fails|1|1|1|no test file ran"

# A copy with no go.mod.
rm "${C}/go.mod"
o="$(mk nomod SWARMDEV_BIN="${ROOT}/caller-bin")"
check "with no go.mod, make test passes, builds nothing, says so in one line and unsets SWARMDEV_BIN" \
  "$(tail -1 <<< "${o}")|$(builds "${ROOT}/nomod.go")|$(lines "build: ${CP} has no go.mod, so this run builds no binary and unsets SWARMDEV_BIN" "${o}")|$(cut -f2 "${ROOT}/nomod.seen" | tr '\n' ' ')" \
  "0|none|1|unset unset "

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
