// Package frontmatter reads a board item's front-matter values as bin/lib/board.sh's fm, get_fm,
// get_fm_or_gone and `get_fm - <key>` print them: the item's state file first (state_value), then the
// file. It reads only through iface.Store, at each call: it has no report snapshot (board_snap_read).
// Writing state or front matter is not here.
//
// Keys are plain names ([A-Za-z_][A-Za-z0-9_]*). The Go reads a key literally, where bash's sed would
// read a BRE metacharacter in it as one; no caller passes such a key.
package frontmatter

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"slices"
	"strings"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// ErrGone is GetFMOrGone's error for an item that is gone (bash's ITEM_GONE, status 3): neither the
// path nor a symlink at it is there, as when a merge deleted it after the board was listed.
var ErrGone = errors.New("frontmatter: the item is gone")

// setFMKeys is bin/lib/board.sh's SET_FM_KEYS, in its order: the keys swarm.sh writes to an item's
// state file, and the only keys whose state line is read.
var setFMKeys = []string{
	"attempts", "kind", "escalated_from", "held_for", "held_by", "kept", "status", "prs", "protected", "unasked_plan",
}

// SetFMKeys returns a copy of bin/lib/board.sh's SET_FM_KEYS, in its order.
func SetFMKeys() []string { return slices.Clone(setFMKeys) }

// The parts of a state file's path: PROJECT_DIR/.swarm/board-state/<stories|epics>/<slug>.
const (
	stateDir    = "/.swarm/board-state"
	storiesDir  = "stories"
	epicsDir    = "epics"
	itemSuffix  = ".md"
	baseSuffix  = "@base"
	fmDelimiter = "---"
)

// Reader reads front matter as bash does with BOARD and PROJECT_DIR set to Board and ProjectDir,
// each as bash holds it: the state rule compares them as strings, never cleaned.
type Reader struct {
	Store      iface.Store
	Board      string
	ProjectDir string
}

// FM is `fm <item> <key>`: the key's state value (stateValue), else the first `<key>:` line anywhere
// in the item, its leading spaces stripped and its bytes kept, as sed prints it: with a newline, but
// none when that line is the file's last and has none. An item with no such line prints nothing. One
// that is gone prints nothing and succeeds; one that is there but cannot be read fails with the read's
// error. printed says whether any byte was printed.
func (r Reader) FM(item, key string) (out []byte, printed bool, err error) {
	if out, ok, err := r.stateValue(item, key); ok || err != nil {
		return out, len(out) > 0, err
	}
	data, err := r.Store.ReadFile(item)
	if err != nil {
		if r.gone(item) {
			return nil, false, nil
		}
		return nil, false, err
	}
	out = anywhere(data, key)
	return out, len(out) > 0, nil
}

// GetFM is `get_fm <item> <key>`: GetFMOrGone, with an item that is gone read as no value.
func (r Reader) GetFM(item, key string) (out []byte, printed bool, err error) {
	out, printed, err = r.GetFMOrGone(item, key)
	if errors.Is(err, ErrGone) {
		return nil, false, nil
	}
	return out, printed, err
}

// GetFMOrGone is `get_fm_or_gone <item> <key>`: the key's state value (stateValue), else the first
// `<key>:` line inside the item's front matter, its leading spaces stripped, with a newline as awk
// prints it. It fails with ErrGone for an item that is gone, and with the read's error for one that is
// there but cannot be read; a dangling symlink is there.
func (r Reader) GetFMOrGone(item, key string) (out []byte, printed bool, err error) {
	if out, ok, err := r.stateValue(item, key); ok || err != nil {
		return out, len(out) > 0, err
	}
	data, err := r.Store.ReadFile(item)
	if err != nil {
		if r.gone(item) {
			return nil, false, ErrGone
		}
		return nil, false, err
	}
	out = frontMatterLine(data, key)
	return out, len(out) > 0, nil
}

// GetFMText is `get_fm - <key>` with b on stdin: GetFMOrGone's front-matter scan over b, with no
// state file and no gone check, so it calls no store method. Its error is always nil, as awk reading
// stdin does not fail.
func (r Reader) GetFMText(b []byte, key string) (out []byte, printed bool, err error) {
	out = frontMatterLine(b, key)
	return out, len(out) > 0, nil
}

// frontMatterLine is get_fm's awk: the first `<key>:` line's value inside b's front matter with
// awk's newline, or nothing.
func frontMatterLine(b []byte, key string) []byte {
	value, found := frontMatterValue(b, key)
	if !found {
		return nil
	}
	return append(value, '\n')
}

// stateValue is state_value: the key's line from the item's state file (statePath), with awk's
// newline, or nothing when the line's value is empty; ok says the state file answered. It does not
// answer when there is no state file, it has no line for the key, the item cannot be read, or its
// <key>@base: line is not the item's front-matter value now (an edit to the item since wins). A state
// file that is there but cannot be read fails: the committed value could be stale.
func (r Reader) stateValue(item, key string) (out []byte, ok bool, err error) {
	state := r.statePath(item, key)
	if state == "" {
		return nil, false, nil
	}
	if info, err := r.Store.Stat(state); err != nil || !info.Mode().IsRegular() {
		return nil, false, nil
	}
	lines, err := r.Store.ReadFile(state)
	if errors.Is(err, fs.ErrPermission) {
		return nil, false, fmt.Errorf("board state: cannot read %s; make it readable, or remove it to read %s as committed", state, item)
	}
	if err != nil {
		return nil, false, nil
	}
	data, err := r.Store.ReadFile(item)
	if err != nil {
		return nil, false, nil
	}
	value, found, base, hasBase := stateLines(lines, key)
	if !found {
		return nil, false, nil
	}
	if hasBase {
		now, _ := frontMatterValue(data, key)
		if !bytes.Equal(now, base) {
			return nil, false, nil
		}
	}
	if len(value) == 0 {
		return nil, true, nil
	}
	return append(value, '\n'), true, nil
}

// statePath is state_path: the item's state file, PROJECT_DIR/.swarm/board-state/<stories|epics>/<slug>,
// or "" when the key is not one of SET_FM_KEYS (an empty key is not checked), the item's folder is not
// exactly BOARD/stories or BOARD/epics, its name does not end .md, or it is not a regular file, its
// symlinks followed. The folder is the path cut at its last / (${1%/*}), never cleaned, so
// BOARD/stories/./x.md has none.
func (r Reader) statePath(item, key string) string {
	if key != "" && !slices.Contains(setFMKeys, key) {
		return ""
	}
	dir, name := cutLast(item)
	if (dir != r.Board+"/"+storiesDir && dir != r.Board+"/"+epicsDir) || !strings.HasSuffix(name, itemSuffix) {
		return ""
	}
	if info, err := r.Store.Stat(item); err != nil || !info.Mode().IsRegular() {
		return ""
	}
	_, folder := cutLast(dir)
	return r.ProjectDir + stateDir + "/" + folder + "/" + strings.TrimSuffix(name, itemSuffix)
}

// gone is item_gone's test: neither the path nor a symlink at it is there ([[ -e || -L ]]), which is
// an Lstat that fails.
func (r Reader) gone(item string) bool {
	_, err := r.Store.Lstat(item)
	return err != nil
}

// cutLast splits p at its last /, as ${p%/*} and ${p##*/} do: with no /, both are p.
func cutLast(p string) (dir, name string) {
	i := strings.LastIndexByte(p, '/')
	if i < 0 {
		return p, p
	}
	return p[:i], p[i+1:]
}

// line is one line of a file, without its newline; terminated says it had one.
type line struct {
	text       []byte
	terminated bool
}

// lines splits b as awk and sed read records: at each newline, with a last line that has none kept.
func lines(b []byte) []line {
	var out []line
	for len(b) > 0 {
		i := bytes.IndexByte(b, '\n')
		if i < 0 {
			return append(out, line{text: b})
		}
		out = append(out, line{text: b[:i], terminated: true})
		b = b[i+1:]
	}
	return out
}

// valueAfter is the rest of text after prefix, its leading spaces (not tabs) stripped, when text
// starts with prefix.
func valueAfter(text []byte, prefix string) ([]byte, bool) {
	rest, ok := bytes.CutPrefix(text, []byte(prefix))
	if !ok {
		return nil, false
	}
	return bytes.TrimLeft(rest, " "), true
}

// anywhere is fm's sed and head: the first `<key>:` line anywhere in b, its value with the line's own
// newline, or nothing.
func anywhere(b []byte, key string) []byte {
	for _, l := range lines(b) {
		if value, ok := valueAfter(l.text, key+":"); ok {
			out := slices.Clone(value)
			if l.terminated {
				out = append(out, '\n')
			}
			return out
		}
	}
	return nil
}

// frontMatterValue is the first `<key>:` line's value inside b's front matter: the lines after the
// first line that is exactly ---, wherever it is, and before the second. found says there was one.
func frontMatterValue(b []byte, key string) (value []byte, found bool) {
	delimiters := 0
	for _, l := range lines(b) {
		if string(l.text) == fmDelimiter {
			delimiters++
			if delimiters == 2 {
				return nil, false
			}
			continue
		}
		if delimiters != 1 {
			continue
		}
		if value, ok := valueAfter(l.text, key+":"); ok {
			return slices.Clone(value), true
		}
	}
	return nil, false
}

// stateLines is state_read's read of a state file: the first `<key>:` line's value and the first
// `<key>@base:` line's value, each found or not.
func stateLines(b []byte, key string) (value []byte, found bool, base []byte, hasBase bool) {
	for _, l := range lines(b) {
		if !found {
			value, found = valueAfter(l.text, key+":")
		}
		if !hasBase {
			base, hasBase = valueAfter(l.text, key+baseSuffix+":")
		}
	}
	return slices.Clone(value), found, slices.Clone(base), hasBase
}
