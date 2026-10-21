import glob, os, re, sys

# pairs(lines, out, stop) — each key's first value, as board.sh's awk reads it: leading spaces dropped.
def pairs(lines, out, stop=None):
    for line in lines:
        if line == stop:
            break
        k, sep, v = line.partition(":")
        if sep and k not in out:
            out[k] = v.lstrip(" ")

# front_text(text) — a story's own front matter, each key's first value as pairs leaves it; CRLF
# tolerated. dataset imports it for a story's text from git.
def front_text(text):
    lines, out = [l.rstrip("\r") for l in text.split("\n")], {}
    if lines[0] == "---":
        pairs(lines[1:], out, "---")
    return out

# front(path) — the story's front matter, under what swarm.sh wrote to its state file (state_set),
# but for a key whose <key>@base: the file no longer has: a later edit to the file wins. The values
# are compared as state_value compares them, then trimmed.
def front(path):
    out, st = front_text(open(path, encoding="utf-8", errors="replace").read()), {}
    try:
        pairs(open(os.path.join(state, os.path.basename(path)[:-3]), encoding="utf-8", errors="replace").read().split("\n"), st)
    except FileNotFoundError:
        pass
    for k, v in st.items():
        if not k.endswith("@base") and st.get(k + "@base", out.get(k, "")) == out.get(k, ""):
            out[k] = v
    return {k: v.strip() for k, v in out.items()}

def entries(fm, project_dir, repos_dir):
    # A (repo, file, function) per entry of fm's touches; flow's model_fit imports it to read a story's files.
    repo, project = fm.get("repo", ""), os.path.basename(project_dir)
    raw, parts, cur, depth = fm.get("touches", "").strip().strip("[]"), [], "", 0
    for c in raw:
        if c == "(":
            depth += 1
        elif c == ")":
            depth = max(depth - 1, 0)
        elif depth == 0 and c == ",":
            parts.append(cur); cur = ""
        elif depth == 0:
            cur += c
    parts.append(cur)
    out = []
    for p in (p.strip() for p in parts):
        m = re.match(r"([A-Za-z0-9._-]+): (.*)", p)
        r, p = (m.group(1), m.group(2).strip()) if m else (None, p)
        if not p:
            continue
        head, fr = p.split(":", 1)[0].strip(), repo if r is None else r   # a file's repo: its prefix, else the story's
        if out and "/" not in head and "." not in head \
                and not os.path.isfile(os.path.join(project_dir if fr in ("", project) else os.path.join(repos_dir, fr), head)):
            r = out[-1][0] if r is None else r
            out.append(("" if r == project else r, out[-1][1], p))
            continue
        r = fr
        f, _, fn = p.partition(":")
        out.append(("" if r == project else r, f.strip(), fn.strip()))
    return out

def overlap(a, b):
    return a[:2] == b[:2] and (not a[2] or not b[2] or a[2] == b[2])

def deps(fm):
    return set(re.split(r"[\s,\[\]\"']+", fm.get("depends_on", "").split("#")[0]))

if __name__ == "__main__":
    stories, me, project_dir, repos_dir, state = sys.argv[1:]
    fms = {os.path.basename(f)[:-3]: front(f) for f in glob.glob(os.path.join(stories, "*.md")) if not f.endswith("/README.md")}
    # --idle: a blocked story an agent builds (SWARM_AGENT_KINDS; a lead story's step is no code to
    # share), with no needs: line and no held_by: (a review holds it), whose depends_on story an agent
    # builds, neither done nor in review (unblock stacks on a PR), has touches and shares no file
    # with it, waits for nothing it uses (idle_lines).
    if me == "--idle":
        kinds = [""] + os.environ.get("SWARM_AGENT_KINDS", "").split()
        for slug, fm in sorted(fms.items()):
            files = {e[:2] for e in entries(fm, project_dir, repos_dir)}
            if fm.get("status") != "blocked" or fm.get("kind", "") not in kinds or fm.get("held_by") or fm.get("needs") or not files:
                continue
            for d in sorted(deps(fm) & set(fms)):
                theirs = {e[:2] for e in entries(fms[d], project_dir, repos_dir)}
                if fms[d].get("status") not in ("done", "review") and fms[d].get("kind", "") in kinds and theirs and not files & theirs:
                    print(f"idle: {slug} waits on {d} but shares no touches with it")
        sys.exit()
    mine = entries(fms[me], project_dir, repos_dir)
    for slug, fm in sorted(fms.items()):
        # A stacked story starts on its parents' branches: neither holds the other back.
        if slug == me or slug in deps(fms[me]) or me in deps(fm) or fm.get("epic") and fm.get("epic") == fms[me].get("epic"):
            continue
        hit = [e for e in entries(fm, project_dir, repos_dir) if any(overlap(e, m) for m in mine)]
        if hit:
            print("\t".join([slug, fm.get("epic") or "none", "held" if fm.get("held_by") else fm.get("status") or "-",
                             ", ".join(dict.fromkeys(f + (":" + fn if fn else "") for _, f, fn in hit))]))
