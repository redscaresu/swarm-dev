import calendar, collections, glob, os, re, subprocess, sys, time

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
# are compared as state_value compares them, then trimmed. An epic's state is under st_dir.
def front(path, st_dir=None):
    out, st = front_text(open(path, encoding="utf-8", errors="replace").read()), {}
    try:
        pairs(open(os.path.join(st_dir or state, os.path.basename(path)[:-3]), encoding="utf-8", errors="replace").read().split("\n"), st)
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

# A part's leading words that name no function or section: a section marker and the articles,
# compared in lower case (doc headings start with "The ...").
SKIP_WORDS = {"§", "#", "the", "a", "an"}

# first_word(part) — a part's first word past SKIP_WORDS (a function or section name); an empty
# list for a bare file, and the last word when the part has nothing past them (a section named A).
def first_word(part):
    words = part.split()
    for w in words:
        if w.lower() not in SKIP_WORDS:
            return [w]
    return words[-1:]

# overlap(a, b) — two (repo, file, part) entries clash: the same repo and file, and either both parts
# empty or the parts' first words the same. A bare file never clashes with a part of it.
def overlap(a, b):
    return a[:2] == b[:2] and first_word(a[2]) == first_word(b[2])

# slugs(value) — a front-matter value's slugs, as slug_list reads them: brackets, quotes, commas and a
# trailing # comment gone.
def slugs(value):
    return [s for s in re.split(r"[\s,\[\]\"']+", value.split("#")[0]) if s]

def deps(fm):
    return set(slugs(fm.get("depends_on", "")))

# stage_of(value) — (x, y, z) for a stage: v<x.y.z> (stage_of in board.sh: a # comment, whitespace and a
# matching pair of quotes off), None for none, "bad" for any other value.
def stage_of(value):
    v = value.split("#")[0].strip()
    m = re.fullmatch(r"(['\"])(.*)\1", v)
    v = m.group(2) if m else v
    m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", v)
    return tuple(int(n) for n in m.groups()) if m else "bad" if v else None

# ok_events(path) — {(command, target): [secs, ...]} of events.tsv's ok lines; empty with no file.
# A line's place in the file adds under a second, so two lines in one second keep their order (a
# conductor's restart logs the old run's report, then its conduct).
def ok_events(path):
    out = collections.defaultdict(list)
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except FileNotFoundError:
        return out
    for i, e in enumerate(l.split("\t") for l in lines):
        if len(e) == 5 and (e[4] == "ok" or e[4].startswith("ok (")):
            try:
                out[e[1], e[2]].append(calendar.timegm(time.strptime(e[0], "%Y-%m-%dT%H:%M:%SZ")) + i / len(lines))
            except ValueError:
                pass
    return out

def mtimes(*paths):
    return [os.path.getmtime(p) for p in paths if os.path.exists(p)]

# The events that put a story back to ready, or may have: its board edits are dated by the files' mtimes.
READIES = ("unblock", "reset", "reset:held", "reconcile", "close")

if __name__ == "__main__":
    stories, me, project_dir, repos_dir, state = sys.argv[1:]
    fms = {os.path.basename(f)[:-3]: front(f) for f in glob.glob(os.path.join(stories, "*.md")) if not f.endswith("/README.md")}
    # --idle: a blocked story an agent builds (SWARM_AGENT_KINDS; a lead story's step is no code to
    # share), with no held_by: (a review holds it), whose depends_on story an agent builds, neither
    # done nor in review (unblock stacks on a PR), has touches and shares no touches part with it
    # (overlap, as story --strict compares), and is not named in its needs: line, waits for nothing it
    # uses (idle_lines).
    if me == "--idle":
        kinds = [""] + os.environ.get("SWARM_AGENT_KINDS", "").split()
        for slug, fm in sorted(fms.items()):
            mine = entries(fm, project_dir, repos_dir)
            if fm.get("status") != "blocked" or fm.get("kind", "") not in kinds or fm.get("held_by") or not mine:
                continue
            needs = {w.strip(".") for w in re.findall(r"[\w.-]+", fm.get("needs", ""))}
            for d in sorted(deps(fm) & set(fms) - needs):
                theirs = entries(fms[d], project_dir, repos_dir)
                if fms[d].get("status") not in ("done", "review") and fms[d].get("kind", "") in kinds and theirs \
                        and not any(overlap(e, m) for e in mine for m in theirs):
                    print(f"idle: {slug} waits on {d} but shares no touches part with it and needs nothing from it")
        # A ready story next would build (buildable_story: an agent's kind, no epic or an active one,
        # and not held), with no build started (no worktree, no ok story event since it went ready) and
        # ready past SWARM_QUEUE_MINUTES (since the newest of its file's and state file's mtimes and
        # its READIES events), with no story/<slug> branch left (build_exists), that clashes by part
        # with no running build: a story in review, or any whose build started (a held stacked child
        # keeps its worktree and PR), unless one depends on the other (a stacked start). Its exit is a
        # note to its conductor while one runs (an ok conduct event with no close of its agent or
        # report event since, and no report file), else swarm.sh story --strict, which refuses a clash herdr
        # shows. events.tsv, the board and one git read per such story: no gh or herdr call.
        ev, epics = ok_events(os.path.join(project_dir, ".swarm", "events.tsv")), os.path.join(os.path.dirname(stories), "epics")
        queue = int(os.environ.get("SWARM_QUEUE_MINUTES") or 30) * 60

        def since(slug):
            return max(mtimes(os.path.join(stories, slug + ".md"), os.path.join(state, slug))
                       + [t for c in READIES for t in ev[c, slug]], default=0)

        def checkout(fm):
            # As repo_dir: the project for no repo:, or its own name when the project is a git repo.
            r = fm.get("repo", "")
            own = r == os.path.basename(project_dir) and os.path.exists(os.path.join(project_dir, ".git"))
            return project_dir if r == "" or own else os.path.join(repos_dir, r)

        def started(slug, fm):
            src = checkout(fm)
            return os.path.isdir(os.path.join(os.path.dirname(src), os.path.basename(src) + "-wt", slug)) \
                or any(t >= since(slug) for t in ev["story", slug])

        def branched(slug, fm):
            # build_exists's other half, read only for a story about to get the line: its story/<slug> branch.
            return subprocess.run(["git", "-C", checkout(fm), "show-ref", "-q", "--verify", "refs/heads/story/" + slug],
                                  capture_output=True).returncode == 0

        def conductor(epic):
            # The running conductor's agent name, else None. The backlog's is SWARM_BACKLOG_CONDUCTOR
            # (conductor_name backlog), or conduct-backlog in older logs. Imported here, as few polls get here.
            from report import agent_name
            name = agent_name("conduct-" + epic) if epic else os.environ.get("SWARM_BACKLOG_CONDUCTOR") or "conduct-backlog"
            names = {name} if epic else {name, "conduct-backlog"}
            # A report file is the latest run's: start_conductor removes the last one before it starts.
            if os.path.exists(os.path.join(project_dir, ".swarm", f"conduct-{epic or 'backlog'}.report.md")):
                return None
            start = max(ev["conduct", epic or "--backlog"], default=None)
            ends = [t for (c, who), ts in ev.items() if c.split(":")[0] == "close" and agent_name(who) in names for t in ts] \
                + ev["report", epic or "backlog"]
            return None if start is None or any(t >= start for t in ends) else name

        running = [(s, entries(fm, project_dir, repos_dir)) for s, fm in sorted(fms.items())
                   if fm.get("status") == "review" or started(s, fm)]
        for slug, fm in sorted(fms.items()):
            epic = fm.get("epic", "")
            if fm.get("status") != "ready" or fm.get("kind", "") not in kinds or fm.get("held_by") or started(slug, fm) \
                    or epic and (not os.path.exists(os.path.join(epics, epic + ".md"))
                                 or front(os.path.join(epics, epic + ".md"), os.path.join(os.path.dirname(state), "epics")).get("status") != "active") \
                    or time.time() - since(slug) < queue:
                continue
            mine = entries(fm, project_dir, repos_dir)
            if any(any(overlap(e, m) for e in theirs for m in mine) for s, theirs in running
                   if s != slug and s not in deps(fm) and slug not in deps(fms[s])) or branched(slug, fm):
                continue
            c = conductor(epic)
            print(f"idle: {slug} is ready with no build, exit: " + (f"swarm.sh tell {c} note <file>" if c else f"swarm.sh story --strict {slug}"))
        # A draft or later epic in the current stage (its stage:, or its nearest parent's, is the lowest
        # an epic on the board carries, or no epic carries one) with no unasked_plan: (the gate has its
        # recorded plan or decline) that can start: its depends_on lists something and only items gone
        # from the board or done, or a story of it is ready. idle_now drops a staged draft's line, which
        # next's stage step or the gate names. And an active epic with no stories, no depends_on that
        # holds up its planning (holds) and no scope-<epic> tab record in .swarm/state (has_records):
        # no plan runs. idle_now drops that line for an epic a resuming /plan-hld will overwrite.
        efms = {os.path.basename(f)[:-3]: front(f, os.path.join(os.path.dirname(state), "epics"))
                for f in glob.glob(os.path.join(epics, "*.md")) if not f.endswith("/README.md")}

        def stage(e):
            for _ in range(8):   # a parent: cycle ends
                v = stage_of(efms[e].get("stage", ""))
                p = (slugs(efms[e].get("parent", "")) or [""])[0]
                if v is not None or p not in efms:
                    return v
                e = p
            return None

        def open_epic(d, seen=()):
            # open_item for an epic: on the board and not done, and a split one only while an open epic
            # names it in parent: (has_child_epics; seen ends a parent: cycle).
            if d not in efms or efms[d].get("status") == "done":
                return False
            if efms[d].get("status") == "split":
                return any(c != d and c not in seen and " ".join(slugs(f.get("parent", ""))) == d
                           and open_epic(c, seen + (d,)) for c, f in efms.items())
            return True

        def gone(d):
            # Not open_deps: a slug, and neither an open story nor an open epic on the board.
            return re.fullmatch(r"[a-z0-9-]+", d) is not None and fms.get(d, {}).get("status", "done") == "done" \
                and not open_epic(d)

        def stories_of(e):
            # epic_stories: the stories naming the epic, but a lead one whose after: names it (waits_on_epic).
            return [fm for fm in fms.values() if fm.get("epic") == e
                    and not (fm.get("kind") == "lead" and e in slugs(fm.get("after", "")))]

        def holds(d):
            # dep_holds: an open story, or an open epic with no stories or one not yet in review.
            if d in fms:
                return fms[d].get("status") != "done"
            if not open_epic(d):
                return False
            sts = [fm.get("status") for fm in stories_of(d)]
            return not sts or any(s not in ("review", "done") for s in sts) or "review" not in sts

        stages = {e: stage(e) for e in efms}
        current = min((v for v in stages.values() if isinstance(v, tuple)), default=None)
        tab_dir = os.path.join(project_dir, ".swarm", "state")
        tabs = os.listdir(tab_dir) if os.path.isdir(tab_dir) else []
        for e, efm in sorted(efms.items()):
            mine = stories_of(e)
            if efm.get("status") in ("draft", "later") and stages[e] == current and not efm.get("unasked_plan") \
                    and (deps(efm) and all(gone(d) for d in deps(efm)) or any(fm.get("status") == "ready" for fm in mine)):
                print(f"idle: epic {e} can start, exit: plan it, or set it active in a board PR")
            elif efm.get("status") == "active" and not mine \
                    and not any(holds(d) for d in deps(efm) - set(slugs(efm.get("parent", "")))) \
                    and not any(re.fullmatch(re.escape("scope-" + e) + r"(-\d+)?", t) for t in tabs):
                print(f"idle: epic {e} has no plan running, exit: /swarm-dev:plan-epic {e}")
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
