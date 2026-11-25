package plugin

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// testdata is the folder of case files, one plugin.json text each.
const testdata = "testdata"

// versionCase is one file under testdata/ and what Version returns for it.
type versionCase struct {
	file string // its name under testdata/
	why  string // the check it stands for; "config_test.sh: <name>" for a JSON tests/config_test.sh feeds plugin_version
	want string // the version, when ok
	ok   bool
}

// cases is every file under testdata/. TestCasesAreTheFiles fails on a file with no row and a row
// with no file, so bash_compare_test.go compares every one.
var cases = []versionCase{
	{"pretty-printed.json", "config_test.sh: plugin_version: pretty-printed", "1.2.3", true},
	{"minified.json", "config_test.sh: plugin_version: minified", "1.2.3", true},
	{"not-first-key.json", "config_test.sh: plugin_version: version not the first key", "0.9.1", true},
	{"nested-before.json", "config_test.sh: plugin_version: a nested object's version before the top-level one is not taken", "1.0.0", true},
	{"nested-after.json", "config_test.sh: plugin_version: a nested object's version after the top-level one is not taken", "1.0.0", true},
	{"string-with-braces.json", "config_test.sh: plugin_version: a string with braces, a colon and an escaped quote before the version", "2.0.0", true},
	{"two-versions.json", "config_test.sh: plugin_version: two top-level versions: the last, as json.load", "1.0.1", true},
	{"only-nested.json", "config_test.sh: plugin_version: only a nested version exits 1, printing nothing", "", false},
	{"numeric.json", "config_test.sh: plugin_version: a numeric version exits 1, printing nothing", "", false},
	{"empty.json", "config_test.sh: plugin_version: empty input exits 1, printing nothing", "", false},
	{"cut-off.json", "config_test.sh: plugin_version: a file cut off before its top-level object closes exits 1, printing nothing", "", false},

	{"version-in-array.json", "a version string and a version key inside an array are not taken", "1.0.0", true},
	{"array-value.json", "an array as the version's value spoils it", "", false},
	{"object-value.json", "an object as the version's value spoils it", "", false},
	{"true-value.json", "true as the version's value spoils it", "", false},
	{"null-value.json", "null as the version's value spoils it", "", false},
	{"integer-value.json", "a whole number as the version's value spoils it", "", false},
	{"later-bad-version.json", "a later top-level version that is not a string spoils an earlier string", "", false},
	{"later-good-version.json", "a later top-level version string wins over an earlier object", "1.0.1", true},
	{"escape-u-a.json", `\u0041 is kept as A`, "1.A", true},
	{"escape-u-key.json", `a key spelled with a \u escape is still version`, "1.0.0", true},
	{"escape-u-e-acute.json", `\u00e9 (é) is past ASCII: the value no longer counts`, "", false},
	{"escape-u-nul.json", `\u0000 (NUL): the value no longer counts`, "", false},
	{"escape-u-short.json", `a \u escape with fewer than four hex digits`, "", false},
	{"escape-unknown.json", `\x is no JSON escape`, "", false},
	{"escapes-json.json", `the one-letter escapes: \" \\ \/ \b \f \t`, "a\"b\\c/d\be\ff\tg", true},
	{"nul-after-close.json", "a NUL byte after the close ends the text, so the junk past it is not read", "1.0.0", true},
	{"nul-mid-string.json", "a NUL byte mid-string ends the text inside the string", "", false},
	{"missing-comma.json", "a missing comma: the next string is not a key", "", false},
	{"bare-word.json", "a bare word as a value is skipped, as json.load would refuse it", "1.0.0", true},
	{"bare-key.json", "a bare word as the key is no key", "", false},
	{"utf8-bom.json", "a UTF-8 BOM before the object: the text does not open an object", "", false},
	{"trailing-junk.json", "junk after the close", "", false},
	{"whitespace-after-close.json", "space, tab, CR and LF after the close", "1.0.0", true},
	{"whitespace-before-open.json", "space, tab, CR and LF before the open", "1.0.0", true},
	{"empty-object.json", "an empty object has no version", "", false},
	{"top-level-array.json", "a top-level array is no object", "", false},
	{"unpaired-brackets.json", "a [ closed by }", "", false},
	{"unterminated-string.json", "a string that never closes", "", false},
	{"escaped-lf-at-end.json", `a version ending in an escaped LF keeps it`, "1.0.0\n", true},
	{"two-escaped-lf-at-end.json", `a version ending in two escaped LFs keeps both`, "1.0.0\n\n", true},
	{"escaped-lf-inside.json", `an escaped LF inside a version`, "1.0\n.0", true},
	{"escaped-cr-at-end.json", `a version ending in an escaped CR keeps it`, "1.0.0\r", true},
}

// readCase is the bytes of one case file.
func readCase(t *testing.T, file string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(testdata, file))
	if err != nil {
		t.Fatalf("read the case: %v", err)
	}
	return b
}

// TestCasesAreTheFiles: the table and testdata/ name the same files. If someone adds a case file
// with no row, or a row whose file is gone, this goes red.
func TestCasesAreTheFiles(t *testing.T) {
	entries, err := os.ReadDir(testdata)
	if err != nil {
		t.Fatal(err)
	}
	var files, rows []string
	for _, e := range entries {
		files = append(files, e.Name())
	}
	for _, c := range cases {
		rows = append(rows, c.file)
	}
	slices.Sort(rows)
	if !slices.Equal(files, rows) {
		t.Fatalf("testdata/ holds %q, but the cases name %q", files, rows)
	}
}

// TestVersion: Version returns each case's own value. If someone changes a rule Version follows,
// the case for it goes red, even while the bash still matches.
func TestVersion(t *testing.T) {
	for _, c := range cases {
		t.Run(c.file, func(t *testing.T) {
			got, ok := Version(readCase(t, c.file))
			if got != c.want || ok != c.ok {
				t.Errorf("%s: Version = %q, %v; want %q, %v", c.why, got, ok, c.want, c.ok)
			}
		})
	}
}
