#!/usr/bin/env bash
# port_locks_test.sh — docs/port/locks.tsv lists every place the code takes a lock. It scans bin/, hooks/,
# cmd/ and internal/ (no *_test.go), found with find so it runs the same on a copy without .git, for take
# sites, and fails on one whose (file, function, expr) has no row, or that a function takes more often than
# the row's n. A row with fewer or no sites passes: a port that moves a lock to Go edits its rows.
#
# A primitive is a perl one-liner that calls mkdir; a mkdir without -p, or an ln without -s, in an if,
# until or while condition or followed on its line by `&& return` or `|| return`; a bash `set -C` (noclobber)
# create; O_EXCL; flock( or lockf(; and os.Mkdir or os.Link in Go. A lock function is a function that holds a
# primitive; a take site is a primitive or a call to a lock function in a file of the same language. A
# method's line in a top-level Go interface type is its declaration, so it is no call. A
# primitive's expr is the path it takes, as written; a call's is the call, the function and its arguments.
# Whitespace is collapsed. These are heuristics: a lock taken some other way is not found.
#
# It also checks each row has its seven fields, that the header's count of lock files matches the rows,
# and, on a fixture tree of its own, that the scan finds each primitive form and no look-alike.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TSV="docs/port/locks.tsv"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export HOME="${dir}/home"   # under its own root, as every test is (sleep_scale_test.sh); it starts no swarm.sh

fails=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# The scan: one line per take site, "<file>\t<function>\t<expr>", for the files named. A site outside any
# function has function "-".
# Read with read -d '', as bash 3.2 cannot parse this program's quotes inside $( ).
SCAN_AWK=""
IFS= read -r -d '' SCAN_AWK <<'AWK' || true
function lang_of(f, first) {
  if (f ~ /\.py$/) return "py"
  if (f ~ /\.go$/) return "go"
  if (f ~ /\.sh$/ || first ~ /^#!.*sh([ \t]|$)/) return "sh"
  return ""
}
function trim(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
# mask(t) — t with every character inside a quote, and every comment, replaced by x, so a match on the
# result is shell code. $( ) inside double quotes is code.
function mask(t,    out, i, c, n, top, st, dep) {
  out = ""; n = length(t); top = 1; st[1] = "c"; dep[1] = 0
  for (i = 1; i <= n; i++) {
    c = substr(t, i, 1)
    if (st[top] == "s") { if (c == "'") { top--; out = out c } else out = out "x"; continue }
    if (st[top] == "d") {
      if (c == "\\") { out = out "xx"; i++; continue }
      if (c == "\"") { top--; out = out c; continue }
      if (c == "$" && substr(t, i + 1, 1) == "(") { top++; st[top] = "c"; dep[top] = 0; out = out "$("; i++; continue }
      out = out "x"; continue
    }
    if (c == "\\") { out = out substr(t, i, 2); i++; continue }
    if (c == "'") { top++; st[top] = "s"; out = out c; continue }
    if (c == "\"") { top++; st[top] = "d"; out = out c; continue }
    if (c == "#" && (i == 1 || substr(t, i - 1, 1) ~ /[ \t;]/)) { while (i <= n) { out = out "x"; i++ }; break }
    if (c == "(") dep[top]++
    if (c == ")") { if (dep[top] > 0) dep[top]--; else if (top > 1) top-- }
    out = out c
  }
  return out
}
# words(t, p) — the shell words of the command that starts at p in t, up to an unquoted ; & | ) } or #:
# W[1..NW], with R[i] set for a redirection or its target. WE is where the command ends.
function words(t, p,    n, c, w, q, dep, bdep, redir) {
  NW = 0; n = length(t); redir = 0
  while (1) {
    while (p <= n && substr(t, p, 1) ~ /[ \t]/) p++
    if (p > n) break
    c = substr(t, p, 1)
    if (c ~ /[;&|)#]/ || (c == "}" && (p == n || substr(t, p + 1, 1) ~ /[ \t;]/))) break
    w = ""; q = ""; dep = 0; bdep = 0
    if (match(substr(t, p), /^[0-9]*[<>][<>&|]?/)) { w = substr(t, p, RLENGTH); p += RLENGTH; if (p > n || substr(t, p, 1) ~ /[ \t]/) { NW++; W[NW] = w; R[NW] = 1; redir = 1; continue } }
    while (p <= n) {
      c = substr(t, p, 1)
      if (q == "'") { w = w c; if (c == "'") q = ""; p++; continue }
      if (q == "\"") { if (c == "\\") { w = w substr(t, p, 2); p += 2; continue }; w = w c; if (c == "\"") q = ""; p++; continue }
      if (c == "\\") { w = w substr(t, p, 2); p += 2; continue }
      if (c == "'" || c == "\"") { q = c; w = w c; p++; continue }
      if (c == "(") dep++
      else if (c == ")") { if (dep == 0) break; dep-- }
      else if (c == "{" && substr(w, length(w)) == "$") bdep++
      else if (c == "}") { if (bdep == 0) break; bdep-- }
      else if (dep == 0 && bdep == 0 && c ~ /[ \t;&|<>]/) break
      w = w c; p++
    }
    NW++; W[NW] = w; R[NW] = (redir || w ~ /^[0-9]*[<>]/); redir = 0
  }
  WE = p
}
# operand(first, last) — a mkdir's first or an ln's last operand, "" when an option rules it out (opt).
function operand(opt, last,    i, o) {
  o = ""
  for (i = 1; i <= NW; i++) {
    if (R[i]) continue
    if (W[i] ~ /^-/) { if (W[i] ~ opt) return ""; continue }
    if (o == "" || last) o = W[i]
  }
  return o
}
# keyword(m) — true when the last of if, elif, while, until, then, do and else in m opens a condition.
function in_cond(m,    k, s) {
  k = ""
  while (match(m, /(^|[^A-Za-z0-9_])(if|elif|while|until|then|do|else)([^A-Za-z0-9_]|$)/)) {
    s = substr(m, RSTART, RLENGTH); gsub(/[^a-z]/, "", s); k = s; m = substr(m, RSTART + RLENGTH - 1)
  }
  return k == "if" || k == "elif" || k == "while" || k == "until"
}
# arg1(s) — s's text up to its first top-level comma or close paren.
function arg1(s,    i, c, d) {
  d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(") d++
    else if (c == ")") { if (d == 0) break; d-- }
    else if (c == "," && d == 0) break
  }
  return trim(substr(s, 1, i - 1))
}
function argn(s, k,    i, c, d, from, got) {
  d = 0; from = 1; got = 1
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(") d++
    else if (c == ")") { if (d == 0) break; d-- }
    else if (c == "," && d == 0) { if (got == k) break; got++; from = i + 1 }
  }
  return trim(substr(s, from, i - from))
}
# more(i, s) — s, a call's text after its open paren on line i, with the lines after it in the same file
# appended until its parens close (at most 5), for a call that spans lines.
function more(i, s,    k, j, c, d) {
  for (k = 1; k <= 5 && i + k <= N && F[i + k] == F[i]; k++) {
    d = 0
    for (j = 1; j <= length(s); j++) { c = substr(s, j, 1); if (c == "(") d++; else if (c == ")") { if (d == 0) return s; d-- } }
    s = s " " L[i + k]
  }
  return s
}
function call_text(s,    i, c, d) {
  d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(") d++
    else if (c == ")") { d--; if (d == 0) break }
  }
  return trim(substr(s, 1, i))
}
function site(i, expr) { if (expr != "") { NS++; SF[NS] = F[i]; SFN[NS] = FN[i]; SX[NS] = trim(expr); LOCKFN[LG[i], FN[i]] = 1 } }
function emit(i, expr) { if (expr != "") print F[i] "\t" FN[i] "\t" trim(expr) }

FNR == 1 { lg = lang_of(FILENAME, $0); cur = "-"; sp = 0; hd = ""; open = ""; cont = 0; ifc = 0 }
lg == "" { next }
{
  t = $0
  if (lg == "sh" && N > 0 && F[N] == FILENAME && cont) { L[N] = substr(L[N], 1, length(L[N]) - 1) " " t; cont = (t ~ /\\$/); next }
  N++; F[N] = FILENAME; L[N] = t; LG[N] = lg; DATA[N] = 0; cont = (lg == "sh" && t ~ /\\$/)
  if (lg == "sh") {
    if (hd != "") { DATA[N] = 1; FN[N] = cur; s = t; sub(/^\t+/, "", s); if (s == hd) hd = ""; next }
    if (t !~ /<<</ && match(t, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*/)) { hd = substr(t, RSTART, RLENGTH); sub(/^<<-?[ \t]*['"]?/, "", hd) }
    if (match(t, /^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\)/)) {
      cur = substr(t, 1, RLENGTH); sub(/^function[ \t]+/, "", cur); sub(/[ \t]*\(\)$/, "", cur)
      open = (substr(t, RLENGTH + 1) ~ /^[ \t]*\(/) ? ")" : "}"
      FN[N] = cur
      if (t ~ /[})][ \t;]*$/ && t !~ /\(\)[ \t]*[{(][ \t]*$/) cur = "-"
      next
    }
    FN[N] = cur
    if ((open == "}" && t ~ /^\}/) || (open == ")" && t ~ /^\)[ \t]*$/)) cur = "-"
  } else if (lg == "py") {
    if (t ~ /^[ \t]*(#|$)/) { FN[N] = sp ? SN[sp] : "-"; next }
    ind = match(t, /[^ \t]/) - 1
    while (sp > 0 && ind <= SI[sp]) sp--
    if (match(t, /^[ \t]*(async[ \t]+)?def[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
      s = substr(t, RSTART, RLENGTH); sub(/.*def[ \t]+/, "", s); sp++; SI[sp] = ind; SN[sp] = s
    }
    FN[N] = sp ? SN[sp] : "-"
  } else {
    if (match(t, /^func[ \t]+(\([^)]*\)[ \t]*)?[A-Za-z_][A-Za-z0-9_]*/)) { s = substr(t, RSTART, RLENGTH); sub(/.*[ \t)]/, "", s); cur = s }
    FN[N] = cur
    # IFC: the line is inside a top-level interface type, whose method lines declare and never call.
    if (t ~ /^type[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+interface[ \t]*\{[ \t]*$/) ifc = 1
    else if (t ~ /^\}/) { cur = "-"; ifc = 0 }
    IFC[N] = ifc
  }
}

END {
  for (i = 1; i <= N; i++) {
    t = L[i]
    if (LG[i] == "go" ? t ~ /^[ \t]*\/\// : t ~ /^[ \t]*#/) continue
    # Any language: O_EXCL, and flock(/lockf( on an open file (an unlock is no take).
    # One site per O_EXCL, named by the first argument of the last open( before it on the line.
    s = t
    while (match(s, /(^|[^A-Za-z0-9_])O_EXCL([^A-Za-z0-9_]|$)/)) {
      seg = substr(s, 1, RSTART); s = substr(s, RSTART + 6); x = ""
      while (match(seg, /[A-Za-z_.]*[Oo]pen[A-Za-z]*\(/)) { x = arg1(substr(seg, RSTART + RLENGTH)); seg = substr(seg, RSTART + RLENGTH) }
      site(i, x != "" ? x : "O_EXCL")
    }
    if (t ~ /(^|[^A-Za-z0-9_])([Ff]lock|lockf)\(/ && t !~ /LOCK_UN/) {
      match(t, /([Ff]lock|lockf)\(/); site(i, arg1(substr(t, RSTART + RLENGTH)))
    }
    if (LG[i] == "go") {
      s = t; while (match(s, /os\.Mkdir\(/)) { site(i, arg1(more(i, substr(s, RSTART + RLENGTH)))); s = substr(s, RSTART + RLENGTH) }
      s = t; while (match(s, /os\.Link\(/)) { site(i, argn(more(i, substr(s, RSTART + RLENGTH)), 2)); s = substr(s, RSTART + RLENGTH) }
    }
    if (LG[i] != "sh" || DATA[i]) continue
    # perl one-liners that call mkdir.
    if (index(t, "perl") && index(t, "mkdir")) {
      off = 0; s = t
      while (match(s, /perl([ \t]+-[A-Za-z]+)*[ \t]+('[^']*'|"[^"]*")/)) {
        p = RSTART + RLENGTH; scr = substr(s, RSTART, RLENGTH)
        if (scr ~ /(^|[^A-Za-z0-9_])mkdir([^A-Za-z0-9_]|$)/) { words(s, p); x = operand("^$", 0); site(i, x) }
        s = substr(s, p)
      }
    }
    if (!(index(t, "mkdir") || index(t, "ln") || index(t, "set"))) continue
    m = mask(t)
    # A condition can start on an earlier line that ends with && or || (if a &&, then mkdir on the next).
    ctx = ""
    for (k = i - 1; k > 0 && F[k] == F[i] && FN[k] == FN[i] && L[k] ~ /(&&|\|\|)[ \t]*$/; k--) ctx = mask(L[k]) " " ctx
    # mkdir without -p and ln without -s, in a condition or followed by && return / || return.
    s = m; off = 0
    while (match(s, /(^|[^A-Za-z0-9_.\/$-])(mkdir|ln)([ \t]|$)/)) {
      p = off + RSTART; if (substr(s, RSTART, 1) !~ /[ml]/) p++
      cmd = (substr(m, p, 1) == "m") ? "mkdir" : "ln"
      words(t, p + length(cmd))
      x = (cmd == "mkdir") ? operand("p|^--parents$", 0) : operand("s|^--symbolic$", 1)
      if (x != "" && (in_cond(ctx substr(m, 1, p - 1)) || substr(m, WE) ~ /(&&|\|\|)[ \t]*return([^A-Za-z0-9_]|$)/)) site(i, x)
      off = p + length(cmd) - 1; s = substr(m, off + 1)
    }
    # bash noclobber: the file the next > after set -C creates, or only O_EXCL-like when one does.
    if (match(m, /(^|[^A-Za-z0-9_])set[ \t]+(-[A-Za-z]*C[A-Za-z]*|-o[ \t]+noclobber)([^A-Za-z0-9_]|$)/)) {
      s = substr(m, RSTART + RLENGTH); p = RSTART + RLENGTH
      if (match(s, />[^>&|]/)) { words(t, p + RSTART); site(i, W[1]) } else site(i, "set -C")
    }
  }
  # Calls to the lock functions, in files of the same language as the function's.
  for (i = 1; i <= N; i++) {
    t = L[i]
    if (LG[i] == "go" ? t ~ /^[ \t]*\/\// : t ~ /^[ \t]*#/) continue
    if ((LG[i] == "sh" && DATA[i]) || (LG[i] == "go" && IFC[i])) continue
    m = (LG[i] == "sh") ? "" : t
    for (k in LOCKFN) {
      split(k, kp, SUBSEP); if (kp[1] != LG[i] || kp[2] == "-" || !index(t, kp[2])) continue
      fname = kp[2]
      if (LG[i] == "sh") {
        if (m == "") m = mask(t)
        s = m; off = 0
        while ((q = index(s, fname)) > 0) {
          p = off + q; before = (p == 1) ? "" : substr(m, p - 1, 1); after = substr(m, p + length(fname), 1)
          if ((before == "" || before ~ /[ \t;&|({!]/) && (after == "" || after ~ /[ \t;)&|]/) && substr(m, p + length(fname)) !~ /^[ \t]*\(\)/) {
            words(t, p + length(fname)); x = fname
            for (j = 1; j <= NW; j++) if (!R[j]) x = x " " W[j]
            emit(i, x)
          }
          off = p + length(fname) - 1; s = substr(m, off + 1)
        }
      } else {
        s = t; off = 0
        while (match(s, "(^|[^A-Za-z0-9_])" fname "\\(")) {
          p = off + RSTART; if (substr(s, RSTART, length(fname)) != fname) p++
          pre = substr(t, 1, p - 1)
          if (pre !~ /(def|func)[ \t]+$/ && pre !~ /func[ \t]*\([^)]*\)[ \t]*$/) emit(i, call_text(substr(t, p)))
          off = p + length(fname) - 1; s = substr(t, off + 1)
        }
      }
    }
  }
  for (j = 1; j <= NS; j++) print SF[j] "\t" SFN[j] "\t" SX[j]
}
AWK

# scan <root> — the take sites under <root>'s bin/, hooks/, cmd/ and internal/, sorted.
scan() {
  local d files=()
  while IFS= read -r d; do files+=("${d}"); done < <(cd "$1" && for d in bin hooks cmd internal; do
    [[ ! -d "${d}" ]] || find "${d}" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '*_test.go'
  done | LC_ALL=C sort)
  [[ ${#files[@]} -gt 0 ]] || return 0
  (cd "$1" && awk "${SCAN_AWK}" "${files[@]}") | LC_ALL=C sort
}

# The scan on a fixture tree: each primitive form and each call form is found, and no look-alike is.
F="${dir}/fixture"
mkdir -p "${F}/bin/lib" "${F}/internal/x" "${F}/hooks"
cat > "${F}/bin/lib/a.sh" <<'SH'
# lk <base> — a comment that names mkdir "$1" || return 1 and lk "x"
lk() {
  if perl -e 'mkdir shift or exit 1' "$1.lock"; then return 0; fi
}
pl() {
  mkdir -p "$1"
  if ! mkdir "$1/x" 2>/dev/null; then return 1; fi
  mkdir "$1/y"
  if [[ -d "$1" ]] &&
    mkdir "$1/z" 2>/dev/null; then :; fi
  until ln "$1.tmp" \
    "$1" 2>/dev/null; do sleep 1; done
  ln -s a b || return 1
  echo "mkdir z" || return 1
  (set -C; echo x > "$1.later") 2>/dev/null || return 1
  perl -e '@s = stat shift' "$1" || return 1
}
user() {
  lk "${d}/s" || return 1
  x="$(pl "$2")"
  echo "lk is not called here"   # lk "commented"
  python3 - <<'PY'
}
lk("in a heredoc")
PY
}
SH
cat > "${F}/bin/lib/b.py" <<'PY'
def take(path):
    fd = os.open(path, os.O_CREAT | os.O_EXCL)
    a = os.open(path, os.O_EXCL); b = os.open(other, os.O_EXCL)
    fcntl.flock(fd, fcntl.LOCK_EX)
    fcntl.flock(fd, fcntl.LOCK_UN)
def use():
    os.mkdir(d)
    take(p)
PY
cat > "${F}/internal/x/x.go" <<'GO'
func Take(p string) error {
	_ = os.MkdirAll(p, 0o755)
	_ = os.Mkdir(
		p+".d",
		0o755)
	return os.Link(tmp, p+".pid")
}
func use() { _ = Take(dir) }
type Taker interface {
	Take(p string) error
}
GO
printf 'func T(t *testing.T) { os.Mkdir("x", 0o755) }\n' > "${F}/internal/x/x_test.go"
printf '{"mkdir": "x"}\n' > "${F}/hooks/hooks.json"
want="$(printf '%s\n' \
  $'bin/lib/a.sh\tlk\t"$1.lock"' \
  $'bin/lib/a.sh\tpl\t"$1"' \
  $'bin/lib/a.sh\tpl\t"$1.later"' \
  $'bin/lib/a.sh\tpl\t"$1/x"' \
  $'bin/lib/a.sh\tpl\t"$1/z"' \
  $'bin/lib/a.sh\tuser\tlk "${d}/s"' \
  $'bin/lib/a.sh\tuser\tpl "$2"' \
  $'bin/lib/b.py\ttake\tfd' \
  $'bin/lib/b.py\ttake\tother' \
  $'bin/lib/b.py\ttake\tpath' \
  $'bin/lib/b.py\ttake\tpath' \
  $'bin/lib/b.py\tuse\ttake(p)' \
  $'internal/x/x.go\tTake\tp+".d"' \
  $'internal/x/x.go\tTake\tp+".pid"' \
  $'internal/x/x.go\tuse\tTake(dir)' | LC_ALL=C sort)"
got="$(scan "${F}")"
if [[ "${got}" == "${want}" ]]; then echo "ok   the scan finds each primitive and call form on the fixture, and no look-alike"
else fail "the scan on the fixture: want"$'\n'"${want}"$'\n'"got"$'\n'"${got}"; fi

# The rows: seven fields each, n a whole number, and the header's count of lock files matches them.
[[ -f "${ROOT}/${TSV}" ]] || { echo "FAIL ${TSV} is missing"; exit 1; }
bad="$(awk -F'\t' '!/^#/ && NF && (NF != 7 || $7 !~ /^[1-9][0-9]*$/ || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "") {
  print "line " NR ": " $0 }
  !/^#/ && NF { k = $4 "\t" $5 "\t" $6; if (k in seen) print "line " NR " repeats the file, function and expr of line " seen[k] ": " $0; else seen[k] = NR }' "${ROOT}/${TSV}")"
if [[ -z "${bad}" ]]; then echo "ok   every row of ${TSV} has lock, protocol, stale, file, function, expr and n"
else while IFS= read -r l; do fail "${TSV} ${l}: want lock, protocol, stale, file, function, expr and n (a whole number), tab-separated"; done <<< "${bad}"; fi
said="$(sed -nE 's/^# ([0-9]+) lock files.*/\1/p' "${ROOT}/${TSV}" | head -1)"
counted="$(awk -F'\t' '!/^#/ && NF { n = split($1, l, / \+ /); for (i = 1; i <= n; i++) if (l[i] !~ /^<caller.s path>/) seen[l[i]] = 1 }
  END { c = 0; for (k in seen) c++; print c }' "${ROOT}/${TSV}")"
if [[ "${said}" == "${counted}" ]]; then echo "ok   the header's count of lock files (${said}) matches the rows"
else fail "${TSV}'s header says '${said:-no count}' lock files, the rows name ${counted}: change its '# <n> lock files' line"; fi

# The code: each take site has a row, and no function takes one more often than its row's n.
scan "${ROOT}" > "${dir}/sites"
checked="$(awk -F'\t' 'NR == FNR { if (!/^#/ && NF) n[$4 "\t" $5 "\t" $6] += $7; next }
  { c[$0]++ }
  END {
    for (k in c) {
      split(k, f, "\t")
      if (!(k in n)) printf "%s lacks the lock taken in %s %s at %s: add the row <lock>\t<protocol>\t<stale>\t%s\t%s\t%s\t%d\n", T, f[1], f[2], f[3], f[1], f[2], f[3], c[k]
      else if (c[k] > n[k] + 0) printf "%s says %s %s takes %s %d time(s), the code takes it %d: set the row to %s\t%s\t%s\t%d\n", T, f[1], f[2], f[3], n[k], c[k], f[1], f[2], f[3], c[k]
    }
  }' T="${TSV}" "${ROOT}/${TSV}" "${dir}/sites" | LC_ALL=C sort)"
sites="$(wc -l < "${dir}/sites" | tr -d ' ')"
if [[ -z "${checked}" ]]; then echo "ok   ${TSV} has a row for each of the ${sites} take sites the scan finds"
else while IFS= read -r l; do fail "${l}"; done <<< "${checked}"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
