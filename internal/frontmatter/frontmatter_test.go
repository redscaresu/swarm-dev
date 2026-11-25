package frontmatter

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"testing"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// A story the cases read, with status ready in its front matter.
const (
	storyRel  = "docs/stories/a.md"
	storyText = "---\nstatus: ready\ntitle: A\n---\nbody\n"
	stateRel  = ".swarm/board-state/stories/a"
)

// fixture is a temp project: its PROJECT_DIR, and BOARD as its docs/ folder.
type fixture struct {
	t    *testing.T
	root string
	r    Reader
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	root := t.TempDir()
	return fixture{t: t, root: root, r: Reader{Store: store.Files{}, Board: root + "/docs", ProjectDir: root}}
}

// write makes rel under the project hold text, making its folders.
func (f fixture) write(rel, text string) string {
	f.t.Helper()
	p := filepath.Join(f.root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		f.t.Fatal(err)
	}
	return p
}

// unreadable makes rel under the project unreadable, skipping the test as root, who reads it anyway.
func (f fixture) unreadable(rel string) {
	f.t.Helper()
	if os.Geteuid() == 0 {
		f.t.Skip("root reads a file with mode 000")
	}
	if err := os.Chmod(filepath.Join(f.root, rel), 0); err != nil {
		f.t.Fatal(err)
	}
}

// read is one of the four reads, by name, of item (GetFMText reads item's bytes).
type read func(r Reader, item, key string) ([]byte, bool, error)

var reads = map[string]read{
	"FM":          Reader.FM,
	"GetFM":       Reader.GetFM,
	"GetFMOrGone": Reader.GetFMOrGone,
}

// check fails unless the read printed want, with printed set to whether want has a byte, and no error.
func check(t *testing.T, name string, out []byte, printed bool, err error, want string) {
	t.Helper()
	if err != nil || string(out) != want || printed != (want != "") {
		t.Errorf("%s = %q, %v, %v; want %q, %v, nil", name, out, printed, err, want, want != "")
	}
}

// TestStateFile: the state file's line answers for a SET_FM_KEYS key of a story or epic on the
// board, unless its @base is stale, its folder is not exactly BOARD/stories or BOARD/epics, or the
// key is not one swarm.sh writes. Each want is what bin/lib/board.sh printed on the same files
// (bash 3.2, macOS, 2026-11-24).
func TestStateFile(t *testing.T) {
	rows := []struct {
		name  string
		item  string // relative to the project
		text  string // the item's bytes
		state string // the state file's path relative to the project
		lines string // the state file's bytes
		key   string
		want  map[string]string // by read
	}{
		{
			name: "a state value wins over the file", item: storyRel, text: storyText, state: stateRel,
			lines: "status: review\nstatus@base: ready\n", key: "status",
			want: map[string]string{"FM": "review\n", "GetFM": "review\n", "GetFMOrGone": "review\n"},
		},
		{
			name: "a state value with no @base wins", item: storyRel, text: storyText, state: stateRel,
			lines: "status:   review\n", key: "status",
			want: map[string]string{"FM": "review\n", "GetFM": "review\n", "GetFMOrGone": "review\n"},
		},
		{
			name: "an empty state line prints nothing", item: storyRel, text: storyText, state: stateRel,
			lines: "status:\nstatus@base: ready\n", key: "status",
			want: map[string]string{"FM": "", "GetFM": "", "GetFMOrGone": ""},
		},
		{
			name: "a stale @base reads the file", item: storyRel, text: storyText, state: stateRel,
			lines: "status: review\nstatus@base: in-progress\n", key: "status",
			want: map[string]string{"FM": "ready\n", "GetFM": "ready\n", "GetFMOrGone": "ready\n"},
		},
		{
			name: "an epic's state file answers too", item: "docs/epics/e.md", text: storyText,
			state: ".swarm/board-state/epics/e", lines: "status: done\n", key: "status",
			want: map[string]string{"FM": "done\n", "GetFM": "done\n", "GetFMOrGone": "done\n"},
		},
		{
			name: "a key outside SET_FM_KEYS ignores its state line", item: storyRel, text: storyText,
			state: stateRel, lines: "title: B\n", key: "title",
			want: map[string]string{"FM": "A\n", "GetFM": "A\n", "GetFMOrGone": "A\n"},
		},
		{
			name: "an item under BOARD/hld ignores its state file", item: "docs/hld/a.md", text: storyText,
			state: ".swarm/board-state/hld/a", lines: "status: review\n", key: "status",
			want: map[string]string{"FM": "ready\n", "GetFM": "ready\n", "GetFMOrGone": "ready\n"},
		},
		{
			name: "BOARD/stories/./a.md reads no state file", item: "docs/stories/./a.md", text: storyText,
			state: stateRel, lines: "status: review\n", key: "status",
			want: map[string]string{"FM": "ready\n", "GetFM": "ready\n", "GetFMOrGone": "ready\n"},
		},
		{
			name: "a state file with no line for the key reads the file", item: storyRel, text: storyText,
			state: stateRel, lines: "prs: x\n", key: "status",
			want: map[string]string{"FM": "ready\n", "GetFM": "ready\n", "GetFMOrGone": "ready\n"},
		},
	}
	for _, row := range rows {
		t.Run(row.name, func(t *testing.T) {
			f := newFixture(t)
			f.write(row.item, row.text)
			f.write(row.state, row.lines)
			for name, fn := range reads {
				out, printed, err := fn(f.r, f.root+"/"+row.item, row.key)
				check(t, name, out, printed, err, row.want[name])
			}
		})
	}
}

// TestStateFileUnreadable: a state file that is there but cannot be read fails each read with
// bash's message, naming the state file and the item.
func TestStateFileUnreadable(t *testing.T) {
	f := newFixture(t)
	item := f.write(storyRel, storyText)
	state := f.write(stateRel, "status: review\n")
	f.unreadable(stateRel)
	want := "board state: cannot read " + state + "; make it readable, or remove it to read " + item + " as committed"
	for name, fn := range reads {
		out, _, err := fn(f.r, item, "status")
		if err == nil || err.Error() != want || out != nil {
			t.Errorf("%s = %q, %v; want nil, %q", name, out, err, want)
		}
	}
}

// TestFile: what each read finds in the file itself, with no state file.
func TestFile(t *testing.T) {
	rows := []struct {
		name string
		text string
		key  string
		want map[string]string // by read; GetFMText reads the same bytes
	}{
		{
			name: "FM finds a body key that GetFM does not", text: storyText + "owner: me\n", key: "owner",
			want: map[string]string{"FM": "me\n", "GetFM": "", "GetFMOrGone": "", "GetFMText": ""},
		},
		{
			name: "a last line with no newline", text: "---\nkey: x", key: "key",
			want: map[string]string{"FM": "x", "GetFM": "x\n", "GetFMOrGone": "x\n", "GetFMText": "x\n"},
		},
		{
			name: "an empty last line with no newline", text: "---\nkey:", key: "key",
			want: map[string]string{"FM": "", "GetFM": "\n", "GetFMOrGone": "\n", "GetFMText": "\n"},
		},
		{
			name: "front matter after line 1", text: "x\n---\nkey: mid\n---\n", key: "key",
			want: map[string]string{"FM": "mid\n", "GetFM": "mid\n", "GetFMOrGone": "mid\n", "GetFMText": "mid\n"},
		},
		{
			name: "a key before the front matter", text: "key: early\n---\nkey: inside\n---\n", key: "key",
			want: map[string]string{"FM": "early\n", "GetFM": "inside\n", "GetFMOrGone": "inside\n", "GetFMText": "inside\n"},
		},
		{
			name: "only spaces are stripped", text: "---\nkey:\t x \r\n---\n", key: "key",
			want: map[string]string{"FM": "\t x \r\n", "GetFM": "\t x \r\n", "GetFMOrGone": "\t x \r\n", "GetFMText": "\t x \r\n"},
		},
		{
			name: "no line for the key", text: storyText, key: "owner",
			want: map[string]string{"FM": "", "GetFM": "", "GetFMOrGone": "", "GetFMText": ""},
		},
	}
	for _, row := range rows {
		t.Run(row.name, func(t *testing.T) {
			f := newFixture(t)
			item := f.write(storyRel, row.text)
			for name, fn := range reads {
				out, printed, err := fn(f.r, item, row.key)
				check(t, name, out, printed, err, row.want[name])
			}
			out, printed, err := f.r.GetFMText([]byte(row.text), row.key)
			check(t, "GetFMText", out, printed, err, row.want["GetFMText"])
		})
	}
}

// TestGone: an item that is gone reads as no value for FM and GetFM, and as ErrGone for
// GetFMOrGone, even with a state file left for it.
func TestGone(t *testing.T) {
	f := newFixture(t)
	f.write(stateRel, "status: review\n")
	item := f.root + "/" + storyRel
	for _, name := range []string{"FM", "GetFM"} {
		out, printed, err := reads[name](f.r, item, "status")
		check(t, name, out, printed, err, "")
	}
	out, printed, err := f.r.GetFMOrGone(item, "status")
	if !errors.Is(err, ErrGone) || out != nil || printed {
		t.Errorf("GetFMOrGone = %q, %v, %v; want nil, false, ErrGone", out, printed, err)
	}
}

// TestCannotRead: a dangling symlink is there, so it and an item that cannot be read fail each read
// with the read's error, never ErrGone.
func TestCannotRead(t *testing.T) {
	rows := []struct {
		name string
		make func(f fixture) string
	}{
		{name: "a dangling symlink", make: func(f fixture) string {
			p := filepath.Join(f.root, storyRel)
			f.write("docs/stories/other.md", storyText)
			if err := os.Remove(filepath.Join(f.root, "docs/stories/other.md")); err != nil {
				f.t.Fatal(err)
			}
			if err := os.Symlink("other.md", p); err != nil {
				f.t.Fatal(err)
			}
			return p
		}},
		{name: "an item that cannot be read", make: func(f fixture) string {
			p := f.write(storyRel, storyText)
			f.unreadable(storyRel)
			return p
		}},
	}
	for _, row := range rows {
		t.Run(row.name, func(t *testing.T) {
			f := newFixture(t)
			item := row.make(f)
			for name, fn := range reads {
				out, _, err := fn(f.r, item, "status")
				if err == nil || errors.Is(err, ErrGone) || out != nil {
					t.Errorf("%s = %q, %v; want nil and a read error", name, out, err)
				}
			}
		})
	}
}

// failing is a store whose every call fails.
type failing struct{}

var errFailing = errors.New("the store was called")

func (failing) ReadFile(string) ([]byte, error)    { return nil, errFailing }
func (failing) Stat(string) (fs.FileInfo, error)   { return nil, errFailing }
func (failing) Lstat(string) (fs.FileInfo, error)  { return nil, errFailing }
func (failing) RealPath(string) (string, error)    { return "", errFailing }
func (failing) AppendLine(string, string) error    { return errFailing }
func (failing) WriteLine(string, string) error     { return errFailing }
func (failing) AppendLines(string, []string) error { return errFailing }

// TestGetFMTextCallsNoStore: `get_fm - <key>` reads only the bytes given, with no state file and no
// gone check, so a store that fails every call changes nothing.
func TestGetFMTextCallsNoStore(t *testing.T) {
	r := Reader{Store: failing{}, Board: "docs", ProjectDir: "."}
	out, printed, err := r.GetFMText([]byte(storyText), "status")
	check(t, "GetFMText", out, printed, err, "ready\n")
}
