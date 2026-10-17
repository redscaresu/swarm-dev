import glob, os, re, sys
stories, me, project_dir, repos_dir, state = sys.argv[1:]
project = os.path.basename(project_dir)

def pairs(lines, out, stop=None):
    seen = set()
    for line in lines:
        if line == stop:
            break
        k, sep, v = line.partition(":")
        if sep and k not in seen:
            seen.add(k); out[k] = v.strip()

# front(path) — the story's front matter, under what swarm.sh wrote to its state file (state_set),
# but for a key whose <key>@base: the file no longer has: a later edit to the file wins.
def front(path):
    lines, out, st = open(path, encoding="utf-8", errors="replace").read().split("\n"), {}, {}
    if lines[0] == "---":
        pairs(lines[1:], out, "---")
    try:
        pairs(open(os.path.join(state, os.path.basename(path)[:-3]), encoding="utf-8", errors="replace").read().split("\n"), st)
    except FileNotFoundError:
        pass
    for k, v in st.items():
        if not k.endswith("@base") and st.get(k + "@base", out.get(k, "")) == out.get(k, ""):
            out[k] = v
    return out

def entries(fm):
    repo = fm.get("repo", "")
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

fms = {os.path.basename(f)[:-3]: front(f) for f in glob.glob(os.path.join(stories, "*.md")) if not f.endswith("/README.md")}
mine = entries(fms[me])
def deps(fm):
    return set(re.split(r"[\s,\[\]\"']+", fm.get("depends_on", "").split("#")[0]))

for slug, fm in sorted(fms.items()):
    # A stacked story starts on its parents' branches: neither holds the other back.
    if slug == me or slug in deps(fms[me]) or me in deps(fm) or fm.get("epic") and fm.get("epic") == fms[me].get("epic"):
        continue
    hit = [e for e in entries(fm) if any(overlap(e, m) for m in mine)]
    if hit:
        print("\t".join([slug, fm.get("epic") or "none", "held" if fm.get("held_by") else fm.get("status") or "-",
                         ", ".join(dict.fromkeys(f + (":" + fn if fn else "") for _, f, fn in hit))]))
