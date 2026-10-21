import calendar, json, re, subprocess, sys, time, urllib.parse
OK = ("success", "skipped", "neutral")
READ_TRIES = 3   # main_ci's reads in a row that may fail before the wait ends in error

class Err(Exception):
    """gh failed, or answered something unreadable: main_ci reads again."""

class Unread(Exception):
    """A workflow written in YAML this does not read: never retried, never skipped."""

def gh(*args):
    p = subprocess.run(("gh",) + args, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    if p.returncode:
        raise Err("gh %s: %s" % (" ".join(args), (p.stderr.strip().splitlines() or ["exit %d" % p.returncode])[-1]))
    return p.stdout

def docs(path):
    """Each JSON document gh prints for path, one per page; none is an error."""
    s, dec, i, out = gh("api", "--paginate", path), json.JSONDecoder(), 0, []
    while True:
        while i < len(s) and s[i].isspace():
            i += 1
        if i == len(s):
            break
        try:
            d, i = dec.raw_decode(s, i)
        except ValueError:
            raise Err("unreadable answer for " + path)
        out.append(d)
    if not out:
        raise Err("no answer for " + path)
    return out

def pages(path, key):
    items, total = [], None
    for d in docs(path):
        if not (isinstance(d, dict) and isinstance(d.get(key), list) and isinstance(d.get("total_count"), int)):
            raise Err("unreadable answer for " + path)
        items += d[key]
        total = d["total_count"] if total is None else total
    if len(items) < total:
        raise Err("%s: read %d of %d" % (path, len(items), total))
    return items

def judge(runs, red, wait, ok):
    for r in runs:
        if r.get("status") != "completed":
            wait.append("%s (%s)" % (r.get("name"), r.get("status")))
        elif r.get("conclusion") not in OK:
            red.append("%s (%s) %s" % (r.get("name"), r.get("conclusion"), r.get("html_url")))
        else:
            ok.append("%s (%s)" % (r.get("name"), r.get("conclusion")))

def checks(repo, sha, required=(), need_run=True, done=None):
    runs = pages("repos/%s/commits/%s/check-runs?per_page=100" % (repo, sha), "check_runs")
    sts = pages("repos/%s/commits/%s/status?per_page=100" % (repo, sha), "statuses")
    if done is not None:   # when each run and status last finished or changed, for age
        done += [r.get("completed_at") for r in runs] + [s.get("updated_at") for s in sts]
    red, wait, ok = [], ([] if runs or not need_run else ["no check runs"]), []
    judge(runs, red, wait, ok)
    for s in sts:
        if s.get("state") == "pending":
            wait.append("%s (pending)" % s.get("context"))
        elif s.get("state") != "success":
            red.append("%s (%s) %s" % (s.get("context"), s.get("state"), s.get("target_url")))
        else:
            ok.append("%s (success)" % s.get("context"))
    # A required check bound to an app (not None or -1, any source) needs a run from that app.
    have = {(r.get("name"), (r.get("app") or {}).get("id")) for r in runs}
    names = {n for n, _ in have} | {s.get("context") for s in sts}
    wait += ["%s (required, absent)" % c for c, app in required
             if (c not in names if app in (None, -1) else (c, app) not in have)]
    return red, wait, ok

# The ruleset rule types --admin may pass: the review it stands in for, the status checks admin
# re-checks, and rules about pushes and branches that a PR's merge never meets.
ADMIN_RULES = ("pull_request", "required_status_checks", "deletion", "non_fast_forward", "creation")
# Classic protection's fields --admin may pass, on the same grounds; enforce_admins makes GitHub
# refuse --admin itself. Any other field that is set (enabled, or a non-empty value) is refused.
ADMIN_CLASSIC = ("url", "required_status_checks", "required_pull_request_reviews", "enforce_admins",
                 "allow_force_pushes", "allow_deletions", "block_creations", "allow_fork_syncing")

def base_rules(repo, base, method):
    """What base's rulesets and classic branch protection require: the status checks, each as
    (context, the app that must report it or None); whether the head must be up to date (strict);
    and the rules besides those and the review, which --admin would skip, the review's own thread
    resolution and merge methods (method is the one merge will use) among them. The branch is one
    path segment, / encoded."""
    req, strict, skip, b = [], False, [], urllib.parse.quote(base, safe="")
    for d in docs("repos/%s/rules/branches/%s?per_page=100" % (repo, b)):
        if not isinstance(d, list):
            raise Err("unreadable rules for " + base)
        for rule in d:
            if rule["type"] == "required_status_checks":
                p = rule["parameters"]
                req += [(c["context"], c.get("integration_id")) for c in p["required_status_checks"]]
                strict = strict or bool(p.get("strict_required_status_checks_policy"))
            elif rule["type"] == "pull_request":
                p = rule.get("parameters") or {}
                if p.get("required_review_thread_resolution"):
                    skip.append("ruleset rule pull_request's required_review_thread_resolution")
                if "allowed_merge_methods" in p and method not in p["allowed_merge_methods"]:
                    skip.append("ruleset rule pull_request's allowed_merge_methods (%s, not %s)"
                                % (", ".join(p["allowed_merge_methods"]) or "none", method))
            elif rule["type"] not in ADMIN_RULES:
                skip.append("ruleset rule " + rule["type"])
    try:
        prot = json.loads(gh("api", "repos/%s/branches/%s/protection" % (repo, b)))
    except Err as e:
        # Only this 404 means unprotected: a token that cannot read protection gets Not Found.
        if "Branch not protected (HTTP 404)" in str(e):
            return req, strict, skip
        raise
    rsc = prot.get("required_status_checks") or {}
    req += [(c, None) for c in rsc.get("contexts", [])] + [(c["context"], c.get("app_id")) for c in rsc.get("checks", [])]
    for k, v in prot.items():
        if k not in ADMIN_CLASSIC and (v.get("enabled") if isinstance(v, dict) and "enabled" in v else v):
            skip.append("branch protection " + k)
    return req, strict or bool(rsc.get("strict")), skip

def admin(repo, base, sha, method):
    """Why --admin may not merge sha into base with method, or nothing: it must stand in for the
    review only."""
    req, strict, skip = base_rules(repo, base, method)
    why = ["%s, which --admin would skip" % r for r in skip]
    red, wait, _ = checks(repo, sha, req)
    why += red + wait
    if strict:
        behind = json.loads(gh("api", "repos/%s/compare/%s...%s" % (repo, urllib.parse.quote(base, safe=""), sha)))["behind_by"]
        if behind:
            why.append("%s requires the head up to date, and it is %d commit(s) behind %s" % (base, behind, base))
    return why

def unq(s):
    """A scalar, unquoted. An anchor (&a) or alias (*a) is not read: as a literal glob it would
    match nothing and skip the workflow."""
    s = s.strip()
    if s and s[0] in "&*":
        raise Unread("%s: YAML anchors and aliases are not read" % s)
    return s.strip("'\"")

def flow(v):
    v = v.strip()
    if v.startswith("{") or v.startswith("[") != v.endswith("]"):
        raise Unread("%s: a {flow mapping} or a [list] over several lines is not read" % v)
    if any("," in q for q in re.findall(r"'[^']*'|\"[^\"]*\"", v)):
        raise Unread("%s: a quoted entry holding a comma is not read" % v)
    return [unq(x) for x in v.strip("[]").split(",") if unq(x)]

def push_filters(text):
    """on: push's filters ({} for none), or None when there is no push trigger. Reads the forms
    workflows use: on: push, on: [push, ...], and a block of events with block or [flow] lists."""
    lines = [re.sub(r"(^|\s)#.*", "", l).rstrip() for l in text.splitlines()]
    top = [i for i, l in enumerate(lines) if re.match(r"""^(on|"on"|'on'|true)\s*:""", l)]
    if not top:
        raise Unread("no on: key")
    v = lines[top[0]].split(":", 1)[1]
    if v.strip():
        return {} if "push" in flow(v) else None
    block = []
    for l in lines[top[0] + 1:]:
        if l and not l[0].isspace() and not l.startswith("-"):
            break
        if l.strip():
            block.append(l)
    ind = lambda l: len(l) - len(l.lstrip())
    for j, l in enumerate(block):
        k = l.strip()
        if ind(l) != ind(block[0]):
            continue
        if k.startswith("-"):
            if unq(k[1:]) == "push":
                return {}
            continue
        key, _, rest = k.partition(":")
        if unq(key) != "push":
            continue
        if rest.strip() not in ("", "{}", "null", "~"):
            raise Unread("push: %s is not read" % rest.strip())
        f, key = {}, None
        for c in block[j + 1:]:
            if ind(c) <= ind(l):
                break
            c = c.strip()
            if c.startswith("-") and key:
                f[key].append(unq(c[1:]))
            elif ":" in c:
                key, _, rest = c.partition(":")
                key = unq(key)
                f[key] = flow(rest)
            else:
                raise Unread("push: %s is not read" % c)
        return f
    return None

def glob(p):
    """A GitHub filter pattern as a regex: * stops at /, ** does not, **/ is zero or more directories,
    ? and + repeat what precedes."""
    out = ""
    for t in re.findall(r"\*\*/|\*\*|\*|\[[^\]]*\]|[?+]|[^*?+\[]+", p):
        out += {"**/": "(?:.*/)?", "**": ".*", "*": "[^/]*"}.get(t, t if t[0] in "?+[" else re.escape(t))
    return re.compile(out + r"\Z")

def match(s, pats):
    """Whether s matches a filter list: the last pattern it matches decides, ! negating."""
    hit = False
    for p in pats:
        neg = p.startswith("!")
        if glob(p[1:] if neg else p).match(s):
            hit = not neg
    return hit

def covers(f, base, files):
    """Whether pushing files (None: not all known) to base runs a workflow whose push filters are f.
    An unknown file list covers any path filter, so the wait fails closed."""
    if f is None:
        return False
    if "branches" in f and not match(base, f["branches"]):
        return False
    if "branches-ignore" in f and match(base, f["branches-ignore"]):
        return False
    if not ("branches" in f or "branches-ignore" in f) and ("tags" in f or "tags-ignore" in f):
        return False
    if files is not None:
        if "paths" in f and not any(match(x, f["paths"]) for x in files):
            return False
        if "paths-ignore" in f and all(match(x, f["paths-ignore"]) for x in files):
            return False
    return True

def pr_files(repo, n, changed):
    """Every path PR n changes, a renamed file's old one too, or None when fewer than its changed
    count come back (the API lists 3000 at most)."""
    got = []
    for d in docs("repos/%s/pulls/%s/files?per_page=100" % (repo, n)):
        if not isinstance(d, list):
            raise Err("unreadable files for #" + n)
        got += d
    if len(got) != changed:
        return None
    try:
        return [p for f in got for p in (f["filename"], f.get("previous_filename")) if p]
    except (KeyError, TypeError, AttributeError) as e:
        raise Err("unreadable files for #%s: %r" % (n, e))

def expected(repo, sha, base, n, changed):
    try:
        out = gh("api", "repos/%s/contents/.github/workflows?ref=%s" % (repo, sha))
    except Err as e:
        if "HTTP 404" in str(e):
            return []
        raise
    # A truncated or odd answer is a failed read, retried like any other; only YAML is Unread.
    try:
        paths = [w["path"] for w in json.loads(out) if w["type"] == "file" and w["name"].endswith((".yml", ".yaml"))]
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        raise Err("unreadable .github/workflows listing at %s: %r" % (sha[:7], e))
    want, files = [], pr_files(repo, n, changed)
    for path in paths:
        text = gh("api", "-H", "Accept: application/vnd.github.raw", "repos/%s/contents/%s?ref=%s" % (repo, path, sha))
        try:
            if covers(push_filters(text), base, files):
                want.append(path)
        except Unread as e:
            raise Unread("%s: %s" % (path, e))
    return want

def main_ci(repo, sha, base, n, changed, secs, poll, grace):
    """The merge commit needs no check run of its own: the expected workflows are what must run.
    With none expected, ok waits out grace seconds, so an app's checks or a status that appear just
    after the push are seen and judged. A gh error is a missed read, READ_TRIES in a row an error."""
    want, start, missed = None, time.time(), 0
    end, settled = start + secs, start + min(grace, secs)
    while True:
        try:
            if want is None:
                want = expected(repo, sha, base, n, changed)
            runs = [r for r in pages("repos/%s/actions/runs?head_sha=%s&per_page=100" % (repo, sha), "workflow_runs")
                    if r.get("head_sha") == sha]
            red, wait, _ = checks(repo, sha, need_run=False)
        except Err as e:
            missed += 1
            if missed == READ_TRIES:
                raise Err("%s (%d reads in a row failed)" % (e, missed))
            wait = ["a read failed: %s" % e]
        else:
            missed = 0
            judge(runs, red, wait, [])
            have = {(r.get("path") or "").split("@")[0] for r in runs}
            wait += ["%s (no run on %s)" % (p, sha[:7]) for p in want if p not in have]
            if red:
                return 1, "red " + "; ".join(red)
            if not wait and (want or time.time() >= settled):
                return 0, "ok"
        if time.time() >= end:
            return 2, "timeout (%s)" % "; ".join(wait)
        time.sleep(poll)

try:
    mode, repo, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if mode in ("head", "base"):
        red, wait, ok = checks(repo, args[0])
        if mode == "base":
            judge([r for r in pages("repos/%s/actions/runs?head_sha=%s&per_page=100" % (repo, args[0]), "workflow_runs")
                   if r.get("head_sha") == args[0]], red, wait, ok)
        print("; ".join(red + wait or ok))
        if red or wait:
            sys.exit(1 if red else 2)
    elif mode == "age":
        # head's rule; once green, the whole minutes since its last run or status finished.
        done = []
        red, wait, ok = checks(repo, args[0], done=done)
        if red or wait:
            print("; ".join(red + wait))
            sys.exit(1 if red else 2)
        try:
            last = max(calendar.timegm(time.strptime(t, "%Y-%m-%dT%H:%M:%SZ")) for t in done)
        except (TypeError, ValueError):
            raise Err("unreadable finish time on " + args[0])
        print(int(time.time() - last) // 60)
    elif mode == "admin":
        why = admin(repo, args[0], args[1], args[2])
        if why:
            print("; ".join(why))
            sys.exit(1)
    elif mode == "files":
        files = pr_files(repo, args[0], int(args[1]))
        if not files:
            raise Err("gh listed no files, or fewer than the PR changes")
        print("\n".join(files))
    else:
        rc, msg = main_ci(repo, args[0], args[1], args[2], int(args[3]), float(args[4]), float(args[5]), float(args[6]))
        print(msg)
        sys.exit(rc)
except Exception as e:
    print("error %s" % (e or type(e).__name__))
    sys.exit(3)
