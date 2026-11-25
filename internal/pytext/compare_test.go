package pytext

import (
	"bufio"
	"bytes"
	"context"
	"encoding/hex"
	"fmt"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// pythonDecode reads one hex line per case on stdin and writes, for each, the hex of the UTF-8 of
// bytes.decode("utf-8", "replace") and of bytes.decode("utf-8", "ignore"), tab-separated.
const pythonDecode = `import sys
for line in sys.stdin:
    b = bytes.fromhex(line.strip())
    r = b.decode("utf-8", "replace").encode("utf-8").hex()
    i = b.decode("utf-8", "ignore").encode("utf-8").hex()
    sys.stdout.write(r + "\t" + i + "\n")
`

// pythonTimeout bounds the one python3 run, which decodes every case.
const pythonTimeout = 2 * time.Minute

// maxReported caps the mismatches a failing run prints, so a broken decoder shows a sample.
const maxReported = 20

// decodeCase is one input and the name a mismatch reports it under.
type decodeCase struct {
	name string
	in   string
}

// namedCases are the classes the story names, each bare and with valid text around it.
var namedCases = []decodeCase{
	{"empty", ""},
	{"ascii", "plain text"},
	{"valid 2, 3 and 4 bytes", "é € \U0001F600"},
	{"an encoded U+FFFD is valid", "\xef\xbf\xbd"},
	{"truncated 2: lead alone", "\xc3"},
	{"truncated 3: lead alone", "\xe2"},
	{"truncated 3: lead and one", "\xe2\x82"},
	{"truncated 4: lead alone", "\xf0"},
	{"truncated 4: lead and one", "\xf0\x9f"},
	{"truncated 4: lead and two", "\xf0\x9f\x98"},
	{"truncated 3 then a full 3", "\xe2\x82\xe2\x82\xac"},
	{"truncated 4 then ascii", "\xf0\x9f\x98A"},
	{"two truncated 3s", "\xe2\x82\xe2\x82"},
	{"overlong 2: C0", "\xc0\xaf"},
	{"overlong 2: C1", "\xc1\xbf"},
	{"overlong 3", "\xe0\x80\xaf"},
	{"overlong 3, top", "\xe0\x9f\xbf"},
	{"overlong 4", "\xf0\x80\x80\xaf"},
	{"overlong 4, top", "\xf0\x8f\xbf\xbf"},
	{"surrogate D800", "\xed\xa0\x80"},
	{"surrogate DFFF", "\xed\xbf\xbf"},
	{"surrogate pair", "\xed\xa0\xbd\xed\xb8\x80"},
	{"last before surrogates", "\xed\x9f\xbf"},
	{"U+10FFFF is valid", "\xf4\x8f\xbf\xbf"},
	{"above U+10FFFF: F4 90", "\xf4\x90\x80\x80"},
	{"above U+10FFFF: F5", "\xf5\x80\x80\x80"},
	{"above U+10FFFF: F7", "\xf7\xbf\xbf\xbf"},
	{"5-byte form", "\xf8\x88\x80\x80\x80"},
	{"6-byte form", "\xfc\x84\x80\x80\x80\x80"},
	{"FE", "\xfe"},
	{"FF", "\xff"},
	{"lone continuation 80", "\x80"},
	{"lone continuation BF", "\xbf"},
	{"continuations in a run", "\x80\x81\xbf"},
	{"a valid 2 then a stray continuation", "\xc3\xa9\xa9"},
}

// around is the valid text each named case is also wrapped in: ASCII, and a multibyte character
// each side, so a decoder that eats a neighbour of a bad sequence shows.
var around = [][2]string{{"a", "z"}, {"é", "€"}, {"\U0001F600", "\U0001F600"}}

// secondBytes are the bytes on either side of each second-byte range the leads table sets.
var secondBytes = []byte{0x00, 0x41, 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xC2, 0xE0, 0xF0, 0xFF}

// tails follow a lead and second byte in the sweep: nothing, ASCII, one or two continuations, a
// new lead.
var tails = []string{"", "A", "\x80", "\x80\x80", "\xbf\xbf", "\xc3\xa9"}

// cases is every input the comparison runs: the named cases bare and wrapped, every pair of bytes,
// and every lead byte with each boundary second byte and each tail.
func cases() []decodeCase {
	var out []decodeCase
	for _, c := range namedCases {
		out = append(out, c)
		for _, a := range around {
			out = append(out, decodeCase{c.name + " in " + a[0] + "…" + a[1], a[0] + c.in + a[1]})
		}
	}
	for x := 0; x < 256; x++ {
		for y := 0; y < 256; y++ {
			out = append(out, decodeCase{fmt.Sprintf("pair %02X %02X", x, y), string([]byte{byte(x), byte(y)})})
		}
	}
	for x := 0; x < 256; x++ {
		for _, y := range secondBytes {
			for _, t := range tails {
				in := string([]byte{byte(x), y}) + t
				out = append(out, decodeCase{fmt.Sprintf("sweep %X", in), in})
			}
		}
	}
	return out
}

// runPython decodes each case with python3 and returns, per case, the hex of the replace and ignore
// results.
func runPython(t *testing.T, cs []decodeCase) [][2]string {
	t.Helper()
	path, err := exec.LookPath("python3")
	if err != nil {
		t.Fatalf("the comparison needs python3 on PATH, as the helpers it matches do: %v", err)
	}
	var in bytes.Buffer
	for _, c := range cs {
		in.WriteString(hex.EncodeToString([]byte(c.in)) + "\n")
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, "-I", "-c", pythonDecode)
	cmd.Stdin = &in
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	got, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 failed: %v: %s", err, stderr.String())
	}
	var out [][2]string
	sc := bufio.NewScanner(bytes.NewReader(got))
	for sc.Scan() {
		r, i, ok := strings.Cut(sc.Text(), "\t")
		if !ok {
			t.Fatalf("python3 printed %q, want two tab-separated hex fields", sc.Text())
		}
		out = append(out, [2]string{r, i})
	}
	if len(out) != len(cs) {
		t.Fatalf("python3 printed %d lines for %d cases", len(out), len(cs))
	}
	return out
}

// TestDecodeMatchesPython runs bytes.decode and the Go over every case and compares the UTF-8 of
// the two, byte for byte, for errors="replace" and errors="ignore".
func TestDecodeMatchesPython(t *testing.T) {
	cs := cases()
	want := runPython(t, cs)
	bad := 0
	for k, c := range cs {
		for j, f := range []struct {
			name string
			fn   func([]byte) string
		}{{"DecodeReplace", DecodeReplace}, {"DecodeIgnore", DecodeIgnore}} {
			got := hex.EncodeToString([]byte(f.fn([]byte(c.in))))
			if got == want[k][j] {
				continue
			}
			if bad++; bad <= maxReported {
				t.Errorf("%s(%s, % x) = %s, Python gives %s", f.name, c.name, c.in, got, want[k][j])
			}
		}
	}
	if bad > maxReported {
		t.Errorf("and %d more mismatches", bad-maxReported)
	}
	t.Logf("compared %d inputs under replace and ignore", len(cs))
}
