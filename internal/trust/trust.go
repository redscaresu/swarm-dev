// Package trust decides whether Claude Code trusts a folder, from the bytes of its .claude.json,
// as bin/lib/require_trusted.py decides it. It has no caller yet: bash still runs the .py.
package trust

import (
	"errors"
	"strings"
)

// The two codes Decide returns, as require_trusted.py exits.
const (
	// goAhead: the folder is trusted, or the file cannot be read or is not JSON.
	goAhead = 0
	// refuse: nothing trusts the folder, or a value the rule reads is not an object, where
	// Python's .get would raise.
	refuse = 1
)

// trustKey is the field of a folder's entry that trusts it when it is JSON true.
const trustKey = "hasTrustDialogAccepted"

// Decide returns 0 or 1 as `python3 require_trusted.py <root> <config> <git|>` exits, given the
// bytes read from <config> (data) and the error the read returned (readErr). inGit is the third
// argument's "git": the root is a git root, so its ancestors are not checked.
func Decide(data []byte, readErr error, root string, inGit bool) int {
	if readErr != nil {
		return goAhead
	}
	top, err := read(data)
	switch {
	case errors.Is(err, errTooDeep):
		return refuse
	case err != nil:
		return goAhead
	}
	config, ok := top.(map[string]any)
	if !ok {
		return refuse
	}
	projects, found := config["projects"]
	if !found {
		return refuse
	}
	folders, ok := projects.(map[string]any)
	if !ok {
		return refuse
	}
	// Python's any() stops at the first trusted path, and its .get raises at the first entry
	// that is not an object, so the order of paths decides between the two.
	for _, path := range paths(root, inGit) {
		entry, found := folders[path]
		if !found {
			continue
		}
		fields, ok := entry.(map[string]any)
		if !ok {
			return refuse
		}
		if fields[trustKey] == true {
			return goAhead
		}
	}
	return refuse
}

// paths is the root, then, outside git, each ancestor up to the one whose dirname is itself.
func paths(root string, inGit bool) []string {
	list := []string{root}
	for !inGit {
		last := list[len(list)-1]
		up := dirname(last)
		if up == last {
			break
		}
		list = append(list, up)
	}
	return list
}

// dirname is Python's os.path.dirname on POSIX: everything before the last slash, with trailing
// slashes trimmed unless it is all slashes. Unlike filepath.Dir it does not clean the path, so
// "/a//b/" gives "/a//b", and "a" gives "".
func dirname(path string) string {
	head := path[:strings.LastIndexByte(path, '/')+1]
	if trimmed := strings.TrimRight(head, "/"); trimmed != "" {
		return trimmed
	}
	return head
}
