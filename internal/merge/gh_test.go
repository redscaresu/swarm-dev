package merge

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"syscall"
	"testing"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// fakeHost answers every Run with result and records each call's args.
type fakeHost struct {
	result iface.GhResult
	calls  [][]string
}

func (f *fakeHost) Run(_ context.Context, args ...string) iface.GhResult {
	f.calls = append(f.calls, args)
	return f.result
}

// failed is a GhResult for a gh that exited with code and wrote stderr.
func failed(code int, stderr string) iface.GhResult {
	return iface.GhResult{Stderr: []byte(stderr), Exit: code}
}

// answered is a GhResult for a gh that exited 0 and wrote stdout.
func answered(stdout string) iface.GhResult { return iface.GhResult{Stdout: []byte(stdout)} }

// isErr reports whether err is an *Err, the error a ci_gate caller reads again on.
func isErr(err error) bool {
	var e *Err
	return errors.As(err, &e)
}

// The wants are python3's: ci_gate.py's gh("api", "x y") on a stub gh that writes these bytes and
// ends this way (the PR shows the runs). If gh names the first stderr line, or the exit code when
// gh wrote a line, or a signal's death as anything but Python's negative returncode, or strips and
// splits lines other than Python's way, this goes red.
func TestGhErrorNamesTheLastStderrLine(t *testing.T) {
	cases := []struct {
		name   string
		result iface.GhResult
		want   string
	}{
		{"several lines", failed(1, "first line\n  second\n\nlast line  \n"), "gh api x y: last line"},
		{"no stderr", failed(3, ""), "gh api x y: exit 3"},
		{"only whitespace", failed(5, " \t\n"), "gh api x y: exit 5"},
		{"one line, spaced", failed(4, "  only  \n\n"), "gh api x y: only"},
		{"a break before the one line", failed(1, "\n  only"), "gh api x y: only"},
		{"breaks before the one line", failed(1, "\n\n  error: x  \n"), "gh api x y: error: x"},
		{"a last line's own indent", failed(1, "first\n  last  \n"), "gh api x y:   last"},
		{"Python's other whitespace first", failed(1, " \x1c only"), "gh api x y: only"},
		{"U+0085 and U+2028 first", failed(1, "\u0085\u2028 x\n"), "gh api x y: x"},
		{"Python's other breaks", failed(2, "one\vtwo\x1dthree  "), "gh api x y: three"},
		{"Python's other whitespace", failed(2, "a\n\x1cb\x1f \u0085"), "gh api x y: b"},
		{"a TERM death", iface.GhResult{Exit: -1, Signal: int(syscall.SIGTERM)}, "gh api x y: exit -15"},
		{"a TERM death that said why", iface.GhResult{Stderr: []byte("dying\n"), Exit: -1, Signal: int(syscall.SIGTERM)}, "gh api x y: dying"},
	}
	for _, c := range cases {
		host := &fakeHost{result: c.result}
		out, err := hostCalls{host}.gh(context.Background(), "api", "x y")
		if err == nil || err.Error() != c.want || !isErr(err) || out != "" {
			t.Errorf("%s: gh = %q, %v (an Err: %v); want the Err %q", c.name, out, err, isErr(err), c.want)
		}
		if want := [][]string{{"api", "x y"}}; !reflect.DeepEqual(host.calls, want) {
			t.Errorf("%s: gh ran %q, want %q", c.name, host.calls, want)
		}
	}
}

// Python's text mode makes \r\n and \r into \n (python3 gives 'a\nb\nc\n'). If gh hands on the bytes
// as they came, a caller splitting on \n reads other lines: this goes red.
func TestGhReadsStdoutAsTextMode(t *testing.T) {
	out, err := hostCalls{&fakeHost{result: answered("a\r\nb\rc\n")}}.gh(context.Background(), "api", "x")
	if out != "a\nb\nc\n" || err != nil {
		t.Errorf("gh = %q, %v; want %q, nil", out, err, "a\nb\nc\n")
	}
}

// ci_gate.py's gh raises UnicodeDecodeError, FileNotFoundError or the signal handler's exception for
// these, never Err, so no caller reads again. If gh makes one of them an Err, a caller retries what
// cannot pass: this goes red.
func TestGhFailuresThatAreNotErr(t *testing.T) {
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	cases := []struct {
		name   string
		ctx    context.Context
		result iface.GhResult
		want   string
	}{
		{"stdout not UTF-8", context.Background(), answered("ok\xff"), "gh's stdout is not UTF-8"},
		{"stderr not UTF-8", context.Background(), failed(1, "oops \xff\n"), "gh's stderr is not UTF-8"},
		{"no gh", context.Background(), iface.GhResult{Exit: -1, NoStart: errors.New("no gh on PATH")}, "gh api x: no gh on PATH"},
		{"cut short", cancelled, iface.GhResult{Exit: -1, CutShort: true}, "gh api x: cut short: context canceled"},
	}
	for _, c := range cases {
		_, err := hostCalls{&fakeHost{result: c.result}}.gh(c.ctx, "api", "x")
		if err == nil || err.Error() != c.want || isErr(err) {
			t.Errorf("%s: gh error = %v (an Err: %v); want %q, not an Err", c.name, err, isErr(err), c.want)
		}
	}
	_, err := hostCalls{&fakeHost{result: iface.GhResult{Exit: -1, CutShort: true}}}.gh(cancelled, "api", "x")
	if !errors.Is(err, context.Canceled) {
		t.Errorf("a cut-short gh's error %v does not wrap context.Canceled, so queued cannot tell its own stop", err)
	}
}

// python3's ci_gate.py graphql("q", o="own", n=5, b=True) runs gh api graphql -f o=own -F n=5 -F
// b=True -f query=q. If graphql sends an int or a bool as -f, or reorders the variables, this goes
// red.
func TestGraphqlTypesIntsAndBools(t *testing.T) {
	host := &fakeHost{result: answered(`{"data": {"repository": {"mergeQueue": null}}}`)}
	repo, err := hostCalls{host}.graphql(context.Background(), "q", strVar("o", "own"), intVar("n", 5), boolVar("b", true), boolVar("f", false))
	if err != nil || !reflect.DeepEqual(repo, map[string]any{"mergeQueue": nil}) {
		t.Errorf("graphql = %v, %v; want map[mergeQueue:<nil>], nil", repo, err)
	}
	want := [][]string{{"api", "graphql", "-f", "o=own", "-F", "n=5", "-F", "b=True", "-F", "f=False", "-f", "query=q"}}
	if !reflect.DeepEqual(host.calls, want) {
		t.Errorf("graphql ran\n %q\nwant\n %q", host.calls, want)
	}
}

// The wants are python3's on the same answers. If graphql reads a repository that is null or a list
// as one, or words its Err otherwise, this goes red.
func TestGraphqlNoRepository(t *testing.T) {
	for _, answer := range []string{`{"data": {"repository": null}}`, `{"data": {"repository": [1]}}`} {
		_, err := hostCalls{&fakeHost{result: answered(answer)}}.graphql(context.Background(), "q")
		if err == nil || err.Error() != "unreadable GraphQL answer: no repository" || !isErr(err) {
			t.Errorf("graphql on %s: error %v (an Err: %v); want the Err %q", answer, err, isErr(err), "unreadable GraphQL answer: no repository")
		}
	}
}

// Each answer python3's graphql calls unreadable, with its Err's text: the Go keeps the prefix, and
// Python's KeyError text where it names a missing key, but gives its own reason for the rest. If
// graphql passes one of them on as a repository, or as an error that is not an Err, this goes red.
func TestGraphqlUnreadableAnswers(t *testing.T) {
	cases := []struct {
		answer, python, want string // want is the Err's text, or "" for any with the prefix
	}{
		{"not json", "Expecting value: line 1 column 1 (char 0)", ""},
		{`[1, 2]`, "list indices must be integers or slices, not str", ""},
		{`{"errors": []}`, "'data'", "unreadable GraphQL answer: 'data'"},
		{`{"data": null}`, "'NoneType' object is not subscriptable", ""},
		{`{"data": {}}`, "'repository'", "unreadable GraphQL answer: 'repository'"},
		{"ok\xff", "'utf-8' codec can't decode byte 0xff in position 2: invalid start byte", ""},
	}
	for _, c := range cases {
		repo, err := hostCalls{&fakeHost{result: answered(c.answer)}}.graphql(context.Background(), "q")
		if err == nil || !isErr(err) || repo != nil {
			t.Errorf("graphql on %q = %v, %v (an Err: %v); want an Err, as python3's %q", c.answer, repo, err, isErr(err), gqlUnreadable+c.python)
			continue
		}
		text := err.Error()
		if !strings.HasPrefix(text, gqlUnreadable) || text == gqlUnreadable+"no repository" || (c.want != "" && text != c.want) {
			t.Errorf("graphql on %q: Err %q; want %q, or another reason after its prefix when that is empty (python3: %q)",
				c.answer, text, c.want, gqlUnreadable+c.python)
		}
	}
}

// ci_gate.py's graphql lets gh's own Err through untouched. If graphql words it over, the caller's
// TRANSIENT match reads other words: this goes red.
func TestGraphqlPassesGhsErrOn(t *testing.T) {
	_, err := hostCalls{&fakeHost{result: failed(1, "HTTP 502: Bad Gateway\n")}}.graphql(context.Background(), "q", intVar("n", 7))
	if want := "gh api graphql -F n=7 -f query=q: HTTP 502: Bad Gateway"; err == nil || err.Error() != want || !isErr(err) {
		t.Errorf("graphql error = %v (an Err: %v); want the Err %q", err, isErr(err), want)
	}
}

// The wants are python3's bool(TRANSIENT.search(s)). If transient's edges are RE2's ASCII-only \b, a
// phrase against a letter of another script reads as transient: this goes red.
func TestTransientMatchesAsPythonDoes(t *testing.T) {
	cases := map[string]bool{
		"HTTP 502: Bad Gateway":          true,
		"HTTP 501: Not Implemented":      false,
		"read: connection reset by peer": true,
		"unexpected EOF":                 true,
		"timeouts":                       false,
		"a timeout.":                     true,
		"étimeout":                       false,
		"timeouté":                       false,
		"timeout²":                       false,
		"_EOF":                           false,
		"—EOF—":                          true,
	}
	for s, want := range cases {
		if got := transient.MatchString(s); got != want {
			t.Errorf("transient on %q = %v, want %v", s, got, want)
		}
	}
}
