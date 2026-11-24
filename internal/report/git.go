package report

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// FetchSeconds is how long GitFetch lets git fetch run before it is stopped, as report.py's
// FETCH_SECONDS. BatchSSH's own git config call has the same bound, where report.py's has none.
const FetchSeconds = 60

const (
	timedOutCode = 124                 // the exit code QuietGit gives a git it stopped, as timeout(1) gives
	sshCommand   = "GIT_SSH_COMMAND"   // the user's ssh command for git, and the one QuietGit hands git
	defaultSSH   = "ssh"               // the ssh BatchSSH starts from when the user set none
	batchMode    = " -o BatchMode=yes" // what BatchSSH adds, so ssh fails rather than prompts
	noPrompt     = "GIT_TERMINAL_PROMPT=0"
)

// The information separators U+001C to U+001F, which Python's str.isspace counts as space and Go's
// unicode.IsSpace does not.
const (
	firstSeparator = '\x1c'
	lastSeparator  = '\x1f'
)

// ErrNotUTF8 is the error for git output that is not UTF-8, where report.py's text-mode run raises
// UnicodeDecodeError.
var ErrNotUTF8 = errors.New("git's output is not UTF-8")

// Completed is what QuietGit gives: git's exit code and its output as text, as report.py's
// CompletedProcess holds them.
type Completed struct {
	Code   int
	Stdout string
	Stderr string
}

// Git runs git through the repo, as report.py's quiet_git, git_fetch and batch_ssh do. One value
// keeps BatchSSH's answer per root, as report.py's lru_cache keeps it for the process. It is not
// safe for concurrent use.
type Git struct {
	repo iface.Repo
	ssh  map[string]string
}

// NewGit gives a Git that runs git through repo.
func NewGit(repo iface.Repo) *Git {
	return &Git{repo: repo, ssh: map[string]string{}}
}

// BatchSSH is the user's GIT_SSH_COMMAND, else root's core.sshCommand, else ssh, with
// -o BatchMode=yes after it. The first answer for a root is kept and given again.
func (g *Git) BatchSSH(root string) (string, error) {
	if got, ok := g.ssh[root]; ok {
		return got, nil
	}
	ssh := os.Getenv(sshCommand)
	if ssh == "" {
		got, err := g.repo.Run(iface.GitCall{Dir: root, Bound: FetchSeconds * time.Second, Args: []string{"config", "core.sshCommand"}})
		if err != nil {
			return "", err
		}
		out, err := gitText(got)
		if err != nil {
			return "", err
		}
		if !got.TimedOut {
			ssh = strings.TrimFunc(out.Stdout, gitIsSpace)
		}
	}
	if ssh == "" {
		ssh = defaultSSH
	}
	g.ssh[root] = ssh + batchMode
	return g.ssh[root], nil
}

// QuietGit runs git <args> in root so that it never prompts, even when a partial clone fetches on
// demand: no stdin, no terminal prompt (GIT_TERMINAL_PROMPT=0) and ssh in batch mode (BatchSSH).
// It stops git after seconds, and then gives exit 124 and "over <seconds> s" on stderr.
func (g *Git) QuietGit(root string, seconds int, args ...string) (Completed, error) {
	ssh, err := g.BatchSSH(root)
	if err != nil {
		return Completed{}, err
	}
	got, err := g.repo.Run(iface.GitCall{
		Dir:   root,
		Env:   []string{noPrompt, sshCommand + "=" + ssh},
		Bound: time.Duration(seconds) * time.Second,
		Args:  args,
	})
	if err != nil {
		return Completed{}, err
	}
	if got.TimedOut {
		return Completed{Code: timedOutCode, Stderr: fmt.Sprintf("over %d s", seconds)}, nil
	}
	return gitText(got)
}

// GitFetch runs git fetch -q <args> in root through QuietGit, bounded by FetchSeconds. It gives ""
// once it fetched, else the last line of stderr that is not blank, stripped, else "exit <code>".
func (g *Git) GitFetch(root string, args ...string) (string, error) {
	got, err := g.QuietGit(root, FetchSeconds, append([]string{"fetch", "-q"}, args...)...)
	if err != nil || got.Code == 0 {
		return "", err
	}
	var last string
	for _, line := range strings.FieldsFunc(got.Stderr, gitIsLineBreak) {
		if said := strings.TrimFunc(line, gitIsSpace); said != "" {
			last = said
		}
	}
	if last != "" {
		return last, nil
	}
	return fmt.Sprintf("exit %d", got.Code), nil
}

// gitText is got's output read as Python's text mode reads it: UTF-8 or ErrNotUTF8, with CRLF and a
// lone CR each turned into LF.
func gitText(got iface.GitResult) (Completed, error) {
	if !utf8.ValidString(got.Stdout) || !utf8.ValidString(got.Stderr) {
		return Completed{}, ErrNotUTF8
	}
	return Completed{Code: got.Code, Stdout: gitNewlines(got.Stdout), Stderr: gitNewlines(got.Stderr)}, nil
}

// gitNewlines turns CRLF and a lone CR into LF, as Python's universal newlines do.
func gitNewlines(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "\n")
}

// gitIsSpace reports whether Python's str.isspace holds for r: Go's unicode.IsSpace, and the
// information separators.
func gitIsSpace(r rune) bool {
	return unicode.IsSpace(r) || r >= firstSeparator && r <= lastSeparator
}

// gitIsLineBreak reports whether Python's str.splitlines ends a line at r.
func gitIsLineBreak(r rune) bool {
	switch r {
	case '\n', '\r', '\v', '\f', '\x1c', '\x1d', '\x1e', '\u0085', '\u2028', '\u2029':
		return true
	}
	return false
}
