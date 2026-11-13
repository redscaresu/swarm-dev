# retro's memories section: the lead's memory notes not yet placed, one line per <memory>/*.md but
# MEMORY.md (Claude Code's index of them), in name order: `<file>: <name> — <description>`, from the
# note's frontmatter name: and description: lines (its file name, or "(no description: line)", when it
# has none). It reads only the *.md files in that one folder, never a subfolder or a *.jsonl session
# log beside it. An empty or missing folder prints one line that says which.
# Run by retro_report.py, with memory (the folder) among its globals.
import glob, os


def field(lines, key):
    for line in lines:
        if line.startswith(key + ":"):
            return line[len(key) + 1:].strip().strip("\"'")
    return ""


def front(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    if lines and lines[0].strip() == "---":
        end = next((i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"), len(lines))
        return lines[1:end]
    return lines


folder = memory  # noqa: F821 # retro_report.py's context
if not os.path.isdir(folder):
    print(f"no memory notes: {folder} does not exist")
else:
    notes = [p for p in sorted(glob.glob(os.path.join(glob.escape(folder), "*.md")))
             if os.path.basename(p) != "MEMORY.md" and os.path.isfile(p)]
    if not notes:
        print(f"no memory notes: {folder} holds none")
    for p in notes:
        lines = front(p)
        name = field(lines, "name") or os.path.basename(p)[:-len(".md")]
        desc = field(lines, "description") or "(no description: line)"
        print(f"{os.path.basename(p)}: {name} — {desc}")
