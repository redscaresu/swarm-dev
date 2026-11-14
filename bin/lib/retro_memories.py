# retro's memories section: the lead's swarm-dev memory notes not yet placed, one line per <memory>/*.md
# but MEMORY.md (Claude Code's index of them), in name order: `<file>: <name> — <description>`, from the
# note's frontmatter name: and description: lines (its file name, or "(no description: line)", when it
# has none). A note is listed only when it is a swarm-dev note: its front matter sets
# `project: swarm-dev`, at its top level or under metadata:, or its name: or description: contains
# "swarm" in any case. The folder can be a personal store that holds other notes too, so after the
# list one line counts the notes it skipped, and a note that should have been tagged is still noticed.
# It reads only the *.md files in that one folder, never a subfolder or a *.jsonl session log beside
# it. An empty or missing folder prints one line that says which.
# Run by retro_report.py, with memory (the folder) among its globals.
import glob, os

PROJECT = "swarm-dev"
WORD = "swarm"


def field(lines, key):
    for line in lines:
        if line.startswith(key + ":"):
            return line[len(key) + 1:].strip().strip("\"'")
    return ""


def front(lines):
    """The lines between a leading --- and the next ---, or None when the note has no front matter."""
    if lines and lines[0].strip() == "---":
        end = next((i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"), len(lines))
        return lines[1:end]
    return None


def tagged(lines):
    """True when the front matter sets project: swarm-dev at its top level or under metadata:. A blank
    or comment line leaves the block it sits in as it was, and a trailing # comment is not the value."""
    block = ""
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        top = not line[:1].isspace()
        if top:
            block = line.split(":", 1)[0].strip()
        key, _, value = line.split(" #", 1)[0].strip().partition(":")
        if key == "project" and value.strip().strip("\"'") == PROJECT and (top or block == "metadata"):
            return True
    return False


def swarm_note(fm):
    """True for a swarm-dev note: tagged, or with "swarm" in its front matter's name: or description:."""
    return tagged(fm) or WORD in f"{field(fm, 'name')}\n{field(fm, 'description')}".lower()


folder = memory  # noqa: F821 # retro_report.py's context
if not os.path.isdir(folder):
    print(f"no memory notes: {folder} does not exist")
else:
    notes = [p for p in sorted(glob.glob(os.path.join(glob.escape(folder), "*.md")))
             if os.path.basename(p) != "MEMORY.md" and os.path.isfile(p)]
    if not notes:
        print(f"no memory notes: {folder} holds none")
    skipped = 0
    for p in notes:
        with open(p, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
        fm = front(lines)
        if not swarm_note(fm or []):
            skipped += 1
            continue
        head = lines if fm is None else fm
        name = field(head, "name") or os.path.basename(p)[:-len(".md")]
        desc = field(head, "description") or "(no description: line)"
        print(f"{os.path.basename(p)}: {name} — {desc}")
    if notes:
        print(f"{skipped} other notes skipped (not tagged project: {PROJECT})")
