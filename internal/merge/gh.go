package merge

// ci_gate.py's gh and graphql calls, its Err, and the constants its modes share but FIXED_WALK, which
// comes with the fixed mode (bin/lib/ci_gate.py:1-26,235-246), over iface.CodeHost. Nothing runs them
// yet: until the switch, ci_gate.py's copy decides.

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// okConclusions are the conclusions of a completed check run or status that judge counts as passing
// (OK).
var okConclusions = []string{"success", "skipped", "neutral"}

// readTries is how many of main_ci's reads in a row may fail before its wait ends in error
// (READ_TRIES).
const readTries = 3

// ci_gate main's exit codes, which merge.sh names MAIN_CI_* (CI_OK, CI_RED, CI_TIMEOUT, CI_ERROR and
// CI_COVERED).
const (
	ciOK      = 0
	ciRed     = 1
	ciTimeout = 2
	ciError   = 3
	ciCovered = 4
)

// unlistedExit is behind's exit when the compare cannot list what the base gained (UNLISTED, which
// merge.sh names BEHIND_UNLISTED).
const unlistedExit = 4

// compareFiles is the most files the compare API lists; the PR files API lists 3000 (COMPARE_FILES).
const compareFiles = 300

// transient matches a gh error worth retrying, as merge.sh's WAIT_PR_TRANSIENT does, against gh's own
// words only (TRANSIENT). Python's \b is Unicode-aware and RE2's is ASCII-only, so the edges are
// spelled out: each phrase starts and ends with a word character, and Python's word characters are
// letters, digits and the underscore, in any script.
var transient = regexp.MustCompile(`(?:^|[^\p{L}\p{N}_])(?:rate limit|timeout|timed out|connection reset|connection refused|EOF|TLS handshake|no such host|network is unreachable|stream error|HTTP (?:408|429|50[0234]))(?:[^\p{L}\p{N}_]|$)`)

// runID finds an Actions run's id in a check's URL (RUN_ID).
var runID = regexp.MustCompile(`https://github\.com/[^ ;]+/actions/runs/([0-9]+)`)

// gqlUnreadable starts graphql's Err for an answer it cannot read.
const gqlUnreadable = "unreadable GraphQL answer: "

// Err is ci_gate.py's Err: gh failed, or answered something unreadable, so the caller may read again.
type Err struct{ msg string }

func (e *Err) Error() string { return e.msg }

// errf is an Err whose text is format's, filled in with args.
func errf(format string, args ...any) error {
	return &Err{msg: fmt.Sprintf(format, args...)}
}

// notText is gh output that is not UTF-8. Python's text mode cannot decode it, so ci_gate.py's gh
// raises UnicodeDecodeError, which is not an Err, and no caller reads again. Python's text names the
// byte and its position; this one names the stream.
type notText struct{ stream string }

func (e *notText) Error() string { return "gh's " + e.stream + " is not UTF-8" }

// hostCalls makes ci_gate.py's gh calls through the one iface.CodeHost a ci_gate run has.
type hostCalls struct{ host iface.CodeHost }

// gh runs gh with args, as ci_gate.py's gh does, and gives its stdout as Python's text mode reads it:
// UTF-8, with \r\n and \r made \n. A gh that exits non-zero or that a signal kills is an Err naming
// the call and gh's last stderr line, or "exit <n>" when it wrote none, where a signal's death is
// minus its number, as Python's returncode has it. Output that is not UTF-8 is a *notText, a gh that
// cannot start an error wrapping why, and a run ctx cuts short an error wrapping ctx's cause: none of
// these is an Err, as Python raises none of them as one.
func (h hostCalls) gh(ctx context.Context, args ...string) (string, error) {
	run := h.host.Run(ctx, args...)
	call := "gh " + strings.Join(args, " ")
	switch {
	case run.NoStart != nil:
		return "", fmt.Errorf("%s: %w", call, run.NoStart)
	case run.CutShort:
		return "", fmt.Errorf("%s: cut short: %w", call, cmp.Or(context.Cause(ctx), context.Canceled))
	}
	// Python decodes stdout, then stderr, before it looks at the exit code.
	for _, s := range []struct {
		name string
		out  []byte
	}{{"stdout", run.Stdout}, {"stderr", run.Stderr}} {
		if !utf8.Valid(s.out) {
			return "", &notText{stream: s.name}
		}
	}
	code := run.Exit
	if run.Signal != 0 {
		code = -run.Signal
	}
	if code != 0 {
		line, ok := lastLine(string(run.Stderr))
		if !ok {
			line = "exit " + strconv.Itoa(code)
		}
		return "", errf("%s: %s", call, line)
	}
	return strings.ReplaceAll(strings.ReplaceAll(string(run.Stdout), "\r\n", "\n"), "\r", "\n"), nil
}

// lastLine is the last line of Python's s.strip().splitlines(), and false when there is none. Python's
// whitespace counts U+001C to U+001F beyond Go's unicode.IsSpace, and its line breaks are \n, \r,
// \v, \f, U+001C to U+001E, U+0085, U+2028 and U+2029, with \r\n as one.
func lastLine(s string) (string, bool) {
	space := func(r rune) bool { return unicode.IsSpace(r) || (r >= 0x1c && r <= 0x1f) }
	brk := func(r rune) bool {
		return strings.ContainsRune("\n\r\v\f\x1c\x1d\x1e\u0085\u2028\u2029", r)
	}
	s = strings.TrimFunc(s, space)
	if s == "" {
		return "", false
	}
	i := strings.LastIndexFunc(s, brk)
	if i < 0 {
		return s, true
	}
	_, size := utf8.DecodeRuneInString(s[i:])
	return s[i+size:], true
}

// gqlVar is one variable of a GraphQL read: its name, its value as Python's %s prints it, and whether
// graphql passes it typed, with -F, or as a string, with -f.
type gqlVar struct {
	name, value string
	typed       bool
}

// intVar is an int variable, which graphql passes typed, as ci_gate.py's isinstance(x, int) has it.
func intVar(name string, v int) gqlVar {
	return gqlVar{name: name, value: strconv.Itoa(v), typed: true}
}

// boolVar is a bool variable. Python's isinstance(True, int) is true, so graphql passes it typed too,
// printed True or False: not the true or false that gh's -F turns into a JSON bool.
func boolVar(name string, v bool) gqlVar {
	value := "False"
	if v {
		value = "True"
	}
	return gqlVar{name: name, value: value, typed: true}
}

// strVar is a string variable, which graphql passes as a string.
func strVar(name, v string) gqlVar { return gqlVar{name: name, value: v} }

// graphql makes one GraphQL read, as ci_gate.py's graphql does: gh api graphql with each of vars in
// order, then the query, giving the answer's data.repository object. gh's own errors pass through as
// gh gives them. An answer that is not UTF-8 or not JSON, or that has no data or data.repository, is
// an Err that starts "unreadable GraphQL answer: ". ci_gate.py's goes on with Python's exception text,
// and this one with its own reason. A data.repository that is not an object is the Err "unreadable
// GraphQL answer: no repository", word for word.
//
// It reads the answer with encoding/json, which refuses the NaN, Infinity and -Infinity that
// json.loads takes, so such an answer is unreadable here, and gives every number as a float64.
func (h hostCalls) graphql(ctx context.Context, query string, vars ...gqlVar) (map[string]any, error) {
	args := []string{"api", "graphql"}
	for _, v := range vars {
		flag := "-f"
		if v.typed {
			flag = "-F"
		}
		args = append(args, flag, v.name+"="+v.value)
	}
	out, err := h.gh(ctx, append(args, "-f", "query="+query)...)
	var bad *notText
	switch {
	case errors.As(err, &bad):
		return nil, errf("%s%s", gqlUnreadable, bad)
	case err != nil:
		return nil, err
	}
	var answer any
	if err := json.Unmarshal([]byte(out), &answer); err != nil {
		return nil, errf("%s%s", gqlUnreadable, err)
	}
	data, err := member(answer, "data", "the answer")
	if err != nil {
		return nil, err
	}
	repo, err := member(data, "repository", "data")
	if err != nil {
		return nil, err
	}
	if obj, ok := repo.(map[string]any); ok {
		return obj, nil
	}
	return nil, errf("%sno repository", gqlUnreadable)
}

// member is v[key], as Python's subscript reads it in graphql: an Err when v, which what names, is not
// an object, and Python's KeyError text, the key in quotes, when it has no such key.
func member(v any, key, what string) (any, error) {
	obj, ok := v.(map[string]any)
	if !ok {
		return nil, errf("%s%s is not an object", gqlUnreadable, what)
	}
	got, ok := obj[key]
	if !ok {
		return nil, errf("%s'%s'", gqlUnreadable, key)
	}
	return got, nil
}
