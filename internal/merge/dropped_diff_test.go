package merge

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"testing"
)

// droppedWant is a line a case expects droppedRemoved to give. noAfter stands for Python's None:
// the +++ line named no b/ file.
type droppedWant struct {
	file    string
	after   string
	noAfter bool
	section droppedSection
	text    string
}

// droppedDiff joins lines as git writes a diff: one newline after each.
func droppedDiff(lines ...string) []byte {
	return []byte(strings.Join(lines, "\n") + "\n")
}

// droppedHeader is the header git writes for a file changed in place, named name on both sides.
func droppedHeader(name string) []string {
	return []string{"diff --git a/" + name + " b/" + name, "index 1111111..2222222 100644", "--- a/" + name, "+++ b/" + name}
}

// droppedJoin is the lines of each part, in order.
func droppedJoin(parts ...[]string) []string {
	var all []string
	for _, p := range parts {
		all = append(all, p...)
	}
	return all
}

// droppedShow writes a line as a case compares it, every byte visible.
func droppedShow(file, after string, noAfter bool, section droppedSection, text string) string {
	named := strconv.Quote(after)
	if noAfter {
		named = "None"
	}
	return fmt.Sprintf("%q %s section %d %q", file, named, section, text)
}

func TestDroppedRemoved(t *testing.T) {
	cases := []struct {
		name string
		diff []byte
		want []droppedWant
	}{
		{
			// The -d after the body is past the hunk's three old lines, so it is not removed.
			name: "hunk with counts",
			diff: droppedDiff(droppedJoin(droppedHeader("f"), []string{"@@ -2,3 +1,0 @@", "-a", "-b", "-c", "-d"})...),
			want: []droppedWant{{file: "f", after: "f", text: "a"}, {file: "f", after: "f", text: "b"}, {file: "f", after: "f", text: "c"}},
		},
		{
			// No counts means one old line and one new: -x is the hunk's, -z is past it.
			name: "hunk without counts",
			diff: droppedDiff(droppedJoin(droppedHeader("f"), []string{"@@ -5 +5 @@ func f() {", "-x", "+y", "-z"})...),
			want: []droppedWant{{file: "f", after: "f", text: "x"}},
		},
		{
			// The \ line takes no count, so the hunk's two old lines are -a and -b.
			name: "no newline line",
			diff: droppedDiff(droppedJoin(droppedHeader("f"), []string{"@@ -1,2 +1 @@", "-a", `\ No newline at end of file`, "-b", "+c"})...),
			want: []droppedWant{{file: "f", after: "f", text: "a"}, {file: "f", after: "f", text: "b"}},
		},
		{
			// The section opened in the first hunk is still the first parent's in the second.
			name: "conflict over two hunks",
			diff: droppedDiff(droppedJoin(
				[]string{"diff --git a/f.go b/f.go", "remerge CONFLICT (content): Merge conflict in f.go"},
				droppedHeader("f.go")[1:],
				[]string{"@@ -1,4 +1,3 @@", " func f() {", "-<<<<<<< 41a4d3f (pr)", " \ta()", " \tb()"},
				[]string{"@@ -9,6 +8,1 @@ func f() {", " \tc()", "-}", "-=======", "-\td()", "->>>>>>> ad4fb0a (main)", "-tail"},
			)...),
			want: []droppedWant{
				{file: "f.go", after: "f.go", section: droppedFirst, text: "}"},
				{file: "f.go", after: "f.go", section: droppedSecond, text: "\td()"},
				{file: "f.go", after: "f.go", section: droppedOutside, text: "tail"},
			},
		},
		{
			name: "ancestor part",
			diff: droppedDiff(droppedJoin(droppedHeader("c.txt"), []string{
				"@@ -1,9 +1,3 @@", " top", "-<<<<<<< 41a4d3f (c1)", "-ours-pr", "-||||||| c47a2d3", "-ours-base",
				"-=======", "-ours-main", "->>>>>>> ad4fb0a (c2)", "+resolved", " end",
			})...),
			want: []droppedWant{
				{file: "c.txt", after: "c.txt", section: droppedFirst, text: "ours-pr"},
				{file: "c.txt", after: "c.txt", section: droppedAncestor, text: "ours-base"},
				{file: "c.txt", after: "c.txt", section: droppedSecond, text: "ours-main"},
			},
		},
		{
			// Seven = and seven > are markers, left out, but only nine change the section.
			name: "markers of size 9",
			diff: droppedDiff(droppedJoin(droppedHeader("f"), []string{
				"@@ -1,10 +1,0 @@", "-<<<<<<<<< HEAD", "-a", "-=======", "-b", "-=========", "-c",
				"->>>>>>> x", "-d", "->>>>>>>>> main", "-e",
			})...),
			want: []droppedWant{
				{file: "f", after: "f", section: droppedFirst, text: "a"},
				{file: "f", after: "f", section: droppedFirst, text: "b"},
				{file: "f", after: "f", section: droppedSecond, text: "c"},
				{file: "f", after: "f", section: droppedSecond, text: "d"},
				{file: "f", after: "f", section: droppedOutside, text: "e"},
			},
		},
		{
			// Eight | are a marker, left out, but not the seven that open the ancestor's part.
			name: "eight pipes in a size-7 section",
			diff: droppedDiff(droppedJoin(droppedHeader("f"), []string{
				"@@ -1,6 +1,0 @@", "-<<<<<<< HEAD", "-||||||||", "-a", "-=======", "-b", "->>>>>>> main",
			})...),
			want: []droppedWant{
				{file: "f", after: "f", section: droppedFirst, text: "a"},
				{file: "f", after: "f", section: droppedSecond, text: "b"},
			},
		},
		{
			// f's hunk ends inside a section; g's line is outside one.
			name: "a new diff --git line resets the section",
			diff: droppedDiff(droppedJoin(
				droppedHeader("f"), []string{"@@ -1,2 +1,0 @@", "-<<<<<<< HEAD", "-a"},
				droppedHeader("g"), []string{"@@ -1 +0,0 @@", "-x"},
			)...),
			want: []droppedWant{
				{file: "f", after: "f", section: droppedFirst, text: "a"},
				{file: "g", after: "g", section: droppedOutside, text: "x"},
			},
		},
		{
			// A file with --- /dev/null has no remerged name, so even a - line of it is not kept;
			// one with +++ /dev/null has no name in the merge.
			name: "--- /dev/null and +++ /dev/null",
			diff: droppedDiff(
				"diff --git a/new b/new", "new file mode 100644", "--- /dev/null", "+++ b/new", "@@ -0,0 +1,2 @@", "+n", "-ghost", "+m",
				"diff --git a/old b/old", "deleted file mode 100644", "--- a/old", "+++ /dev/null", "@@ -1 +0,0 @@", "-o",
			),
			want: []droppedWant{{file: "old", noAfter: true, text: "o"}},
		},
		{
			// git ends a name holding a space with a tab, which is not part of the name.
			name: "a name with a space and a trailing tab",
			diff: droppedDiff("diff --git a/a b b/a b", "--- a/a b\t", "+++ b/a b\t", "@@ -1 +0,0 @@", "-x"),
			want: []droppedWant{{file: "a b", after: "a b", text: "x"}},
		},
		{
			name: "a quoted path with a tab, a quote, a backslash and an octal é",
			diff: droppedDiff(
				`diff --git "a/t\tq\"b\\o\303\251" "b/t\tq\"b\\o\303\251"`,
				`--- "a/t\tq\"b\\o\303\251"`, `+++ "b/t\tq\"b\\o\303\251"`, "@@ -1 +0,0 @@", "-x",
			),
			want: []droppedWant{{file: "t\tq\"b\\oé", after: "t\tq\"b\\oé", text: "x"}},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := droppedRemoved(c.diff)
			if err != nil {
				t.Fatalf("droppedRemoved: %v", err)
			}
			var have, want []string
			for _, l := range got {
				have = append(have, droppedShow(string(l.file), string(l.after), !l.hasAfter, l.section, string(l.text)))
			}
			for _, w := range c.want {
				want = append(want, droppedShow(w.file, w.after, w.noAfter, w.section, w.text))
			}
			if strings.Join(have, "\n") != strings.Join(want, "\n") {
				t.Errorf("droppedRemoved gave\n%s\nwant\n%s", strings.Join(have, "\n"), strings.Join(want, "\n"))
			}
		})
	}
}

// A header droppedUnquote cannot read stops the read there: the lines before it come back with the
// error, as Python's generator yields them before it raises.
func TestDroppedRemovedStopsAtABadPath(t *testing.T) {
	diff := droppedDiff(droppedJoin(
		droppedHeader("f"), []string{"@@ -1 +0,0 @@", "-x"},
		[]string{`diff --git "a/\189" "b/\189"`, `--- "a/\189"`, `+++ "b/\189"`, "@@ -1 +0,0 @@", "-y"},
	)...)
	got, err := droppedRemoved(diff)
	if err == nil {
		t.Fatalf("droppedRemoved gave no error for the path \\189")
	}
	if len(got) != 1 || string(got[0].file) != "f" || string(got[0].text) != "x" {
		t.Errorf("droppedRemoved gave %d lines before the error, want f's x alone: %+v", len(got), got)
	}
}

func TestDroppedUnquote(t *testing.T) {
	cases := []struct {
		name, path, want string
	}{
		{"a digit not followed by two more is a plain escape", `"a\12x"`, "a12x"},
		{"one digit at the end is an octal byte", `"a\1"`, "a\x01"},
		{"three digits are an octal byte", `"\377x"`, "\xffx"},
		{"letter escapes, a quote and a backslash", `"\t\n\"\\"`, "\t\n\"\\"},
		{"another byte after a backslash stands for itself", `"\q"`, "q"},
		{"a backslash at the end is kept", `"a\"`, `a\`},
		{"a lone quote is both ends", `"`, ""},
		{"a path that is not quoted at both ends is kept", `"a\tb`, `"a\tb`},
		{"a path with no quotes is kept", `a\tb`, `a\tb`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := droppedUnquote([]byte(c.path))
			if err != nil {
				t.Fatalf("droppedUnquote(%s): %v", c.path, err)
			}
			if string(got) != c.want {
				t.Errorf("droppedUnquote(%s) = %q, want %q", c.path, got, c.want)
			}
		})
	}
	for _, path := range []string{`"\189"`, `"\400"`} {
		t.Run("an error for "+path, func(t *testing.T) {
			got, err := droppedUnquote([]byte(path))
			if !errors.Is(err, strconv.ErrSyntax) && !errors.Is(err, strconv.ErrRange) {
				t.Errorf("droppedUnquote(%s) = %q, %v; want an error, as Python's int(, 8) or bytearray.append raises", path, got, err)
			}
		})
	}
}

func TestDroppedClean(t *testing.T) {
	const r = "\ufffd"
	cases := []struct {
		name, in, want string
	}{
		{"a 3-byte lead and one continuation", "\xe2\x82\x41", r + "A"},
		{"two bytes that never lead", "\xff\xfe\x41", r + r + "A"},
		{"a 4-byte lead and two continuations", "\xf0\x9f\x98\x41", r + "A"},
		{"ed takes only 80 to 9f", "\xed\xa0\x80\x41", r + r + r + "A"},
		{"e0 takes only a0 to bf", "\xe0\x80\x41", r + r + "A"},
		{"f4 takes only 80 to 8f", "\xf4\x90\x80\x80\x41", r + r + r + r + "A"},
		{"c0 never leads", "\xc0\xaf\x41", r + r + "A"},
		{"a cut sequence at the end", "\xe2\x82", r},
		{"control bytes taken off, U+0085 kept", "A\x00\t\n\x1f\x7fB\xc2\x85", "AB\u0085"},
		{"whole characters kept", "é€😀", "é€😀"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := droppedClean([]byte(c.in)); got != c.want {
				t.Errorf("droppedClean(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestDroppedCut(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"301 characters holding é cut to 300", "é" + strings.Repeat("a", 300), "é" + strings.Repeat("a", 299)},
		{"300 characters kept", "é" + strings.Repeat("a", 299), "é" + strings.Repeat("a", 299)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := droppedCut(c.in)
			if got != c.want {
				t.Errorf("droppedCut gave %d characters (%d bytes), want %d", len([]rune(got)), len(got), len([]rune(c.want)))
			}
		})
	}
}
