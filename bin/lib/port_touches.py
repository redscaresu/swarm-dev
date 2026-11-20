# port_touches.py <project dir> <repos dir> <story text> — for non_fix_change (board.sh, port_unlisted):
# reads the tests/ paths a change touches on stdin, NUL-separated as git diff-tree -z prints them, and
# prints the first one that is not a file of the project's own repo in the story's touches, or nothing.
# The touches are read as touches_rows.py's entries() reads them, so a file another repo's entry names
# (`other: tests/x.sh`) does not count. Paths are compared byte for byte, exactly.
import os, sys
from touches_rows import entries, front_text

project_dir, repos_dir, text = sys.argv[1:4]
# front() trims each value the same way for a story file on disk.
fm = {k: v.strip() for k, v in front_text(text).items()}
listed = {os.fsencode(f) for r, f, _ in entries(fm, project_dir, repos_dir) if r == ""}
for path in sys.stdin.buffer.read().split(b"\0"):
    if path and path not in listed:
        sys.stdout.buffer.write(path + b"\n")
        break
