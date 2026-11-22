---
kind: code
status: later
epic: board-store
depends_on: [store-file-reads]
needs: store-file-reads: ReadFile, Stat and Lstat on iface.Store, with fs.ErrNotExist and fs.ErrPermission wrapped
touches: [internal/frontmatter/frontmatter.go (new), internal/frontmatter/frontmatter_test.go (new)]
estimate_lines: 300
---

# fm, get_fm and get_fm_or_gone are Go, stdin form included: the state file first, then the file as bash reads it

Needs store-file-reads. A new rules package internal/frontmatter that reads only through iface.Store. It ports fm (bin/lib/board.sh:7-11), get_fm and get_fm_or_gone (:3253-3262), with state_path, state_name, state_value, state_read, item_gone and gone_ok (:169-248). It takes the store, BOARD and PROJECT_DIR as bash holds them, the item path as given and the key. The state file is PROJECT_DIR/.swarm/board-state/<stories|epics>/<slug>. It is read only for a SET_FM_KEYS key (:3175, copied as a Go list), for a .md item that is a regular file, and when the item's folder is exactly BOARD/stories or BOARD/epics. That folder is the path cut at its last / (${1%/*}), compared as a string; never filepath.Dir, which cleans. A state file that is there but cannot be read fails with `board state: cannot read <state>; make it readable, or remove it to read <file> as committed`. state_read takes the first `<key>:` and `<key>@base:` lines, leading spaces stripped. It falls through when there is no key line, or when @base differs from the item's first front-matter value (n == 1, between the first two --- lines). An empty state value prints nothing and succeeds. Otherwise FM prints the first `^<key>: *` line anywhere in the file, with only spaces stripped and its bytes kept. When that is the file's last line and has no newline, FM prints the value with no newline, as sed does on GNU and on BSD (checked on macOS). GetFM prints the first such line inside the front matter, with awk's newline. GetFMOrGone is GetFM, but returns ErrGone, which the package exports, for an item that is gone (ITEM_GONE, :169); GetFM and FM read a gone item as no value and succeed. A dangling symlink counts as there (Lstat), and an item that cannot be read fails. GetFMText(b, key) is `get_fm - <key>`, the stdin form 24 call sites use (16 in bin/lib/board.sh, 8 in bin/lib/lifecycle.sh; bin/lib/board.sh:330, :2121): get_fm's front-matter scan over the bytes given, with no state file and no gone check. Each returns the exact bytes bash prints, whether anything was printed, and the error. Keys are plain names ([A-Za-z_][A-Za-z0-9_]*); no caller passes a key holding a BRE metacharacter. The Go has no report snapshot: it reads the files at each call, and frontmatter-compare holds it to the bash's snapshot answers too (contradictions: snapshot). Its tests read no bash: the SET_FM_KEYS check is frontmatter-compare's, so they need no tests.tsv row. No non-test file names a SWARM_ token. Writing state or front matter is port-board-writers'. The reviewer reads the bash against the Go rule by rule (P6). port: true.

**Done when:**
- Go unit tests pin each of these: a state value wins over the file; an empty state line prints nothing and succeeds; a stale @base reads the file; a state file that cannot be read fails with the exact message; a key outside SET_FM_KEYS ignores its state line; an item under BOARD/hld ignores its state file; FM finds a body key that GetFM does not; a missing item gives FM and GetFM nothing with success, and GetFMOrGone ErrGone; a dangling symlink and an item that cannot be read fail; GetFMText, given a store that fails every call, still returns the front-matter value of its bytes.
- A last line `key: x` with no newline gives FM `x` with no newline, and GetFM `x` and a newline.
- An item path <board>/stories/./x.md reads no state file, as ${1%/*} leaves the . in: a test pins it, and switching to filepath.Dir on a copy without .git makes it red.
- Mutation, on a copy without .git: drop the @base comparison and its test goes red; make FM print nothing for an unterminated last line and its test goes red; make GetFMOrGone succeed for a gone item and its test goes red.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass, the layer checks among them.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
