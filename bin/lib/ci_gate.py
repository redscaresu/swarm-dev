import calendar, json, re, signal, subprocess, sys, time, urllib.parse
OK = ("success", "skipped", "neutral")
READ_TRIES = 3   # main_ci's reads in a row that may fail before the wait ends in error
CI_OK, CI_RED, CI_TIMEOUT, CI_ERROR = 0, 1, 2, 3   # ci_gate main's exit codes (merge.sh's MAIN_CI_*)
UNLISTED = 4   # behind's exit when the compare cannot list what the base gained (merge.sh's BEHIND_UNLISTED)
# A gh error worth retrying, as merge.sh's WAIT_PR_TRANSIENT: matched against gh's own words only.
TRANSIENT = re.compile(r"\b(rate limit|timeout|timed out|connection reset|connection refused|EOF|TLS handshake|no such host|network is unreachable|stream error|HTTP (408|429|50[0234]))\b")
RUN_ID = re.compile(r"https://github\.com/[^ ;]+/actions/runs/([0-9]+)")   # an Actions run's id in a check's URL
FIXED_WALK = 20  # board-only commits fixed steps back over to the commit it judges
COMPARE_FILES = 300  # the most files the compare API lists; the PR files API lists 3000

class Err(Exception):
    """gh failed, or answered something unreadable: main_ci reads again."""

class Unlisted(Err):
    """behind's compare lists no file for its commits, or may have cut its list short: merging the base
    in clears it. Exits UNLISTED."""

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

# GitHub's compare lists this many files at most: a list that long may be cut short.
COMPARE_FILES = 300

def behind(repo, sha, base, board, wait):
    """The commits base has that sha lacks, and each path they change that is off board's paths (a
    renamed file's old path too): compare sha...base, whose ahead_by counts them and whose files are
    their changes taken together. A board entry ending in / is a folder, any other a file, as merge.sh's
    on_board_paths has them; a README.md there is off the board, since a test may check it (this repo's
    CI gate tests one). A transient gh error (TRANSIENT, in gh's own words) is read again, READ_TRIES
    reads in all, wait seconds apart; any other fails at once. A list of COMPARE_FILES or more may be cut
    short, and commits with no file listed may be a list GitHub left out: both are Unlisted."""
    path = "repos/%s/compare/%s...%s" % (repo, sha, urllib.parse.quote(base, safe=""))
    for i in range(READ_TRIES):
        try:
            d = json.loads(gh("api", path))
            break
        except Err as e:
            if i == READ_TRIES - 1 or not TRANSIENT.search(str(e).split(": ", 1)[-1]):
                raise
            time.sleep(wait)
    try:
        n, files = d["ahead_by"], d["files"]
        paths = [p for f in files for p in (f["filename"], f.get("previous_filename")) if p]
    except (KeyError, TypeError, AttributeError) as e:
        raise Err("unreadable compare of %s with %s: %r" % (sha[:7], base, e))
    if not isinstance(n, int):
        raise Err("unreadable compare of %s with %s: ahead_by %r" % (sha[:7], base, n))
    if len(files) >= COMPARE_FILES:
        raise Unlisted("the compare of %s with %s lists %d files, so it may be cut short" % (sha[:7], base, len(files)))
    if n and not paths:
        raise Unlisted("the compare of %s with %s lists no file for %d commit(s)" % (sha[:7], base, n))
    def on(p):
        return p.rsplit("/", 1)[-1] != "README.md" and any(p.startswith(b) if b.endswith("/") else p == b for b in board)
    return n, [p for p in paths if not on(p)]

def merged(repo, head, new, second):
    """The paths new, a merge of second into head, cannot be shown to take whole from second, as a list
    (empty when none): compare head...new, the merge against head, must list the files compare
    head...second lists (second against where it and head part), each with the same status, old path and
    blob, and none of them may be a file compare second...head lists (the PR's own changes since then).
    So every file the merge changes is the base's own version of a file the PR left alone. A conflict
    resolved by hand, an edit of the merge's own, a PR edit dropped for the base's version and a file both
    sides changed are all listed: patches would pass a base change made at another place. A list of
    COMPARE_FILES or more may be cut short, so it is an error, as is a read that fails."""
    def files(base, tip):
        d = json.loads(gh("api", "repos/%s/compare/%s...%s" % (repo, base, tip)))
        try:
            fs = {f["filename"]: f for f in d["files"]}
        except (KeyError, TypeError) as e:
            raise Err("unreadable compare of %s with %s: %r" % (base[:7], tip[:7], e))
        if len(fs) >= COMPARE_FILES:
            raise Err("the compare of %s with %s lists %d files, so it may be cut short" % (base[:7], tip[:7], len(fs)))
        return fs
    def change(f):
        return f.get("status"), f.get("previous_filename"), f.get("sha")
    got, want, pr = files(head, new), files(head, second), files(second, head)
    def paths(f):   # a file's path, and its old one when renamed
        return {f["filename"], f.get("previous_filename")} - {None}
    ours = set().union(*map(paths, pr.values()))
    return [n for n in sorted(set(got) | set(want))
            if n not in got or n not in want or change(got[n]) != change(want[n]) or paths(got[n]) & ours]

def graphql(query, **v):
    """One GraphQL read: v's ints as -F (typed), every other value as -f (a string)."""
    args = ["api", "graphql"]
    for k, x in v.items():
        args += ["-F" if isinstance(x, int) else "-f", "%s=%s" % (k, x)]
    try:
        repo = json.loads(gh(*(args + ["-f", "query=" + query])))["data"]["repository"]
    except (ValueError, KeyError, TypeError) as e:
        raise Err("unreadable GraphQL answer: %s" % e)
    if not isinstance(repo, dict):
        raise Err("unreadable GraphQL answer: no repository")
    return repo

def has_queue(repo, base, wait):
    """Whether base has a merge queue, from a ruleset or classic protection (GitHub's own answer,
    repository.mergeQueue). A failed or unparsable read is tried READ_TRIES times, wait seconds apart."""
    owner, name = repo.split("/")
    for i in range(READ_TRIES):
        try:
            return graphql("query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) "
                           "{ mergeQueue(branch: $b) { id } } }", o=owner, r=name, b=base)["mergeQueue"] is not None
        except (Err, KeyError):
            if i == READ_TRIES - 1:
                raise
            time.sleep(wait)

def pushed(repo, base, oid, wait):
    """The base's head once it holds oid, the commit a merge queue's batch was pushed at, where the
    base's push-only workflows run; oid itself when it is the head, or when READ_TRIES reads, wait
    apart, never show the head holding it."""
    b = urllib.parse.quote(base, safe="")
    for i in range(READ_TRIES):
        try:
            head = json.loads(gh("api", "repos/%s/branches/%s" % (repo, b)))["commit"]["sha"]
            if head == oid or json.loads(gh("api", "repos/%s/compare/%s...%s" % (repo, oid, head)))["status"] in ("ahead", "identical"):
                return head
        except (Err, ValueError, KeyError, TypeError):
            pass
        if i < READ_TRIES - 1:
            time.sleep(wait)
    return oid

QUEUE_QUERY = """query($o: String!, $r: String!, $n: Int!) { repository(owner: $o, name: $r) { pullRequest(number: $n) {
  id state headRefOid isInMergeQueue autoMergeRequest { enabledAt } mergeCommit { oid } mergeQueueEntry { state headCommit { oid } }
  timelineItems(last: 5, itemTypes: [REMOVED_FROM_MERGE_QUEUE_EVENT]) { nodes { ... on RemovedFromMergeQueueEvent { reason createdAt } } } } } }"""
# ponytail: a PR may wait its turn in the queue this many CI deadlines (3 hours at 30 minutes); a
# slower queue needs a setting of its own.
TURNS = 6

def when(s):
    """A GitHub timestamp as epoch seconds, or 0."""
    try:
        return calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ"))
    except (TypeError, ValueError):
        return 0

def group_commit(repo, base, n, head, since):
    """The merge group commit of the latest merge_group run for this PR at head (its branch is
    gh-readonly-queue/<base>/pr-<n>-<head>-...), started after this enqueue: for a PR that entered
    and left the queue between two reads. None when there is none, or the read fails."""
    pre = "gh-readonly-queue/%s/pr-%s-%s" % (base, n, head)
    try:
        runs = json.loads(gh("api", "repos/%s/actions/runs?event=merge_group&per_page=100" % repo)).get("workflow_runs") or []
    except (Err, ValueError, AttributeError):
        return None
    return next((r.get("head_sha") for r in runs if (r.get("head_branch") or "").startswith(pre)
                 and when(r.get("created_at")) >= since), None)

def removals(pr, since):
    """The PR's removals from the queue after this enqueue (since is read just before it), oldest
    first: never an earlier run's, such as the dequeue its stop() made."""
    return [e for e in ((pr.get("timelineItems") or {}).get("nodes") or []) if e and when(e.get("createdAt")) >= since]

def dequeued(repo, base, n, head, group, pr, since):
    """Why the PR left the queue: GitHub's reason for a removal since this enqueue, and the red or
    unfinished checks on the merge group's commit (seen while queued, else found from its runs),
    else on the head."""
    gone = removals(pr, since)
    why = "dequeued (%s)" % ((gone[-1].get("reason") if gone else None) or "no reason given")
    sha = group or group_commit(repo, base, n, head, since)
    where = "the merge group's commit" if sha else "the head"
    try:
        red, wait, _ = checks(repo, sha or head, need_run=False)
    except Err as e:
        return "%s: cannot read the checks on %s %s: %s" % (why, where, (sha or head)[:7], e)
    return "%s: %s" % (why, "; ".join(red + wait) or "no red check on %s %s" % (where, (sha or head)[:7]))

STOPS = (("autoMergeRequest", "auto-merge is off", "disablePullRequestAutoMerge(input: {pullRequestId: $id})"),
         ("isInMergeQueue", "it is out of the merge queue", "dequeuePullRequest(input: {id: $id})"))

def stop(pr, every=False):
    """Turn the PR's auto-merge off, then take it out of the queue, as the last read (pr) showed
    them, or both with every (the last read may be behind), so no head merges unwatched. Says what
    it did, and what is left to do by hand."""
    if not (pr and pr.get("id")):
        return "its state is unknown: take it out of the merge queue and turn auto-merge off by hand"
    done, left = [], []
    for key, what, mutation in STOPS:
        if not (every or pr.get(key)):
            continue
        try:
            gh("api", "graphql", "-f", "id=" + pr["id"], "-f", "query=mutation($id: ID!) { %s { clientMutationId } }" % mutation)
            done.append(what)
        except Err as e:
            left.append("%s failed (%s)" % (mutation.split("(")[0], e))
    if left:
        return "; ".join(done + left) + ": take it out of the merge queue and turn auto-merge off by hand"
    return " and ".join(done) or "it was neither queued nor waiting for auto-merge"

class Stopped(Exception):
    """A TERM, HUP or INT while queued() waits; its message is the signal's name."""

SIGNALS = (signal.SIGTERM, signal.SIGHUP, signal.SIGINT)

def on_signal(sig, _frame):
    for s in SIGNALS:
        signal.signal(s, signal.SIG_IGN)   # stop() runs once, and to the end
    raise Stopped(signal.Signals(sig).name)

def stop_pr(repo, n):
    """stop(), every=True, on PR n as one read shows it (its id), for a signal that landed before
    queued() could stop it. Later signals are ignored, so it runs to the end."""
    for s in SIGNALS:
        signal.signal(s, signal.SIG_IGN)
    owner, name = repo.split("/")
    try:
        pr = graphql(QUEUE_QUERY, o=owner, r=name, n=int(n))["pullRequest"]
    except (Err, KeyError, TypeError):
        pr = None
    return stop(pr, every=True)

def queued(repo, n, head, base, since, secs, poll):
    """Wait for PR n, enqueued at head (since: epoch seconds just before the enqueue), to merge. The
    CI deadline (secs) runs from when the PR's own merge group starts, and again from each rebuilt
    group; waiting its turn, or for auto-merge to enqueue it, has the queue's own bound, TURNS
    deadlines from the start, or from when its group was taken apart. Codes: 0 "merged <merge commit>" (READ_TRIES reads wait for the
    commit); 1 a dequeue (a removal since the enqueue, or READ_TRIES reads in a row out of the
    queue with no auto-merge waiting after one showed it in) or closed; 2 a timeout; 3 READ_TRIES
    failed reads in a row (a gh error is a missed read); 4 never read as queued or waiting in
    READ_TRIES reads; 5 an open PR whose head is not head; 6 a PR that merged at a head that is not
    head; 7 a TERM, HUP or INT. On 2, 3, 4, 5 and 7 the message is the cause, a newline, and what
    stop() did."""
    owner, name = repo.split("/")
    turn_end, end, running = time.time() + secs * TURNS, None, None
    missed, absent, out, nocommit, seen, group, last, pr = 0, 0, 0, 0, False, None, "not read yet", None
    try:
        # Inside the try, so a signal the moment the handler is in still lands in except Stopped.
        for s in SIGNALS:
            signal.signal(s, on_signal)
        while True:
            try:
                read = graphql(QUEUE_QUERY, o=owner, r=name, n=int(n))["pullRequest"]
                state = read["state"]
            except (Err, KeyError, TypeError) as e:
                missed += 1
                if missed == READ_TRIES:
                    # One line: the error names the query, which spans lines, and merge cuts at the first.
                    return 3, "error %s (%d reads in a row failed)\n%s" % (" ".join(str(e).split()), missed, stop(pr, every=True))
                last = "a read failed: %s" % e
            else:
                missed, pr = 0, read
                entry = pr.get("mergeQueueEntry") or {}
                g = (entry.get("headCommit") or {}).get("oid")
                group = g or group
                if g and entry.get("state") != "QUEUED":
                    if g != running:
                        running, end = g, time.time() + secs
                elif running:
                    # Its group was taken apart (a PR ahead failed): it waits its turn again, afresh.
                    running, end, turn_end = None, None, time.time() + secs * TURNS
                if pr.get("headRefOid") != head:
                    now = (pr.get("headRefOid") or "unknown")[:7]
                    if state == "MERGED":
                        return 6, "merged at head %s, not %s, the head that was checked (merge commit %s)" % (
                            now, head[:7], ((pr.get("mergeCommit") or {}).get("oid") or "none")[:7])
                    return 5, "the head is %s, not %s, the head that was checked\n%s" % (now, head[:7], stop(pr))
                if state == "MERGED":
                    oid = (pr.get("mergeCommit") or {}).get("oid")
                    nocommit += 1
                    if oid or nocommit == READ_TRIES:
                        return 0, "merged %s" % (oid or "")
                    last = "merged, with no merge commit yet"
                elif state != "OPEN":
                    return 1, "%s while queued" % state.lower()
                elif removals(pr, since) and not pr.get("isInMergeQueue"):
                    # Dropped from the queue: auto-merge may still be on, and could enqueue it again unwatched.
                    why = dequeued(repo, base, n, head, group, pr, since)
                    return 1, why + ("; " + stop(pr) if pr.get("autoMergeRequest") else "")
                elif pr.get("isInMergeQueue") or pr.get("autoMergeRequest"):
                    seen, out = True, 0
                    last = ("waiting its turn in the merge queue" if pr.get("isInMergeQueue") and not running
                            else "in the merge queue" if pr.get("isInMergeQueue") else "auto-merge waits for the head's checks")
                elif seen:
                    # Out of the queue, not merged yet, and no removal: GitHub may not have said merged.
                    out += 1
                    if out == READ_TRIES:
                        return 1, dequeued(repo, base, n, head, group, pr, since)
                    last = "out of the merge queue, not merged yet"
                else:
                    absent += 1
                    if absent == READ_TRIES:
                        return 4, "never read as queued or waiting for auto-merge\n%s" % stop(pr, every=True)
                    last = "not yet read as queued"
            if time.time() >= (end or turn_end):
                return 2, "timeout (%s)\n%s" % (last, stop(pr))
            time.sleep(poll)
    except Stopped as e:
        # With no read yet there is no id to stop it by: stop_pr reads it first.
        return 7, "stopped by %s\n%s" % (e, stop(pr, every=True) if pr else stop_pr(repo, n))

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

def on_filters(text, event):
    """on: <event>'s filters ({} for none), or None when there is no such trigger. Reads the forms
    workflows use: on: push, on: [push, ...], and a block of events with block or [flow] lists."""
    lines = [re.sub(r"(^|\s)#.*", "", l).rstrip() for l in text.splitlines()]
    top = [i for i, l in enumerate(lines) if re.match(r"""^(on|"on"|'on'|true)\s*:""", l)]
    if not top:
        raise Unread("no on: key")
    v = lines[top[0]].split(":", 1)[1]
    if v.strip():
        return {} if event in flow(v) else None
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
            if unq(k[1:]) == event:
                return {}
            continue
        key, _, rest = k.partition(":")
        if unq(key) != event:
            continue
        if rest.strip() not in ("", "{}", "null", "~"):
            raise Unread("%s: %s is not read" % (event, rest.strip()))
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
                raise Unread("%s: %s is not read" % (event, c))
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

def pr_files(repo, n, changed, status=False, base=None, sha=None, hold=None):
    """Every path PR n changes, a renamed file's old one too, or None when fewer than its changed
    count come back (the API lists 3000 at most). With base and sha, the files of base...sha
    instead, the PR's files at that head whatever head it has now (the API lists 300 at most). With
    status, each as "<status> <path>": added, modified, removed, renamed or copied, empty when the API
    gives none. With hold, the seconds between reads for merge's read of a story PR's files at its
    pinned head (pinned_files, for protected_hold and the epic guard), and only there: a
    transient gh error (TRANSIENT, in gh's own words) is read again, READ_TRIES reads in all, and a
    list the compare cannot give is an Err that says why (it lists COMPARE_FILES at most, so a PR of
    more is never listed, a PR of no file has none, and a shorter list than changed is cut), where
    every other caller gets None or [] as before."""
    got, tries = [], READ_TRIES if hold is not None else 1
    if sha:
        if hold is not None and changed > COMPARE_FILES:
            raise Err("the compare of %s with %s lists at most %d files, and the PR changes %d, so it cannot list them all" % (base, sha[:7], COMPARE_FILES, changed))
        if hold is not None and not changed:
            raise Err("the PR changes no file")
        path = "repos/%s/compare/%s...%s" % (repo, urllib.parse.quote(base, safe=""), sha)
        for i in range(tries):
            try:
                got = json.loads(gh("api", path)).get("files")
                break
            except Err as e:
                if i == tries - 1 or not TRANSIENT.search(str(e).split(": ", 1)[-1]):
                    raise
                time.sleep(hold)
        if not isinstance(got, list):
            raise Err("unreadable files for %s...%s" % (base, sha[:7]))
        if hold is not None and len(got) != changed:
            raise Err("the compare of %s with %s lists %d of the %d files the PR changes" % (base, sha[:7], len(got), changed))
    else:
        for d in docs("repos/%s/pulls/%s/files?per_page=100" % (repo, n)):
            if not isinstance(d, list):
                raise Err("unreadable files for #" + n)
            got += d
    if len(got) != changed:
        return None
    try:
        if status:
            return ["%s %s" % (f.get("status") or "", p) for f in got for p in (f["filename"], f.get("previous_filename")) if p]
        return [p for f in got for p in (f["filename"], f.get("previous_filename")) if p]
    except (KeyError, TypeError, AttributeError) as e:
        raise Err("unreadable files for #%s: %r" % (n, e))

def workflows(repo, sha):
    """Each workflow file in .github/workflows at sha, as (path, text); none when there is no such folder."""
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
    return [(path, gh("api", "-H", "Accept: application/vnd.github.raw", "repos/%s/contents/%s?ref=%s" % (repo, path, sha)))
            for path in paths]

def expected(repo, sha, base, n, changed):
    texts = workflows(repo, sha)
    want, files = [], pr_files(repo, n, changed) if texts else None
    for path, text in texts:
        try:
            if covers(on_filters(text, "push"), base, files):
                want.append(path)
        except Unread as e:
            raise Unread("%s: %s" % (path, e))
    return want

def pr_tree(repo, sha, n):
    """The commit GitHub runs PR n's pull_request workflows from, its merge commit (refs/pull/<n>/merge)
    once that merges sha, else sha. A ref that is missing (GitHub has not made it, 404 or 422) or stale
    (it merges an older head) gives sha, the workflows the PR's own files name; any other failed or odd
    read is an Err, read again as any other. The ref is read as it is now, but the runs came from the
    merge commit at push time, and GitHub rebuilds the ref when the base moves: a base commit since the
    push that adds a pull_request workflow, or widens one's branches or paths, is waited on though it
    never ran, and the wait ends with exit 2 after the grace until the base is merged in and pushed."""
    try:
        d = json.loads(gh("api", "repos/%s/commits/refs/pull/%s/merge" % (repo, n)))
        parents = [p.get("sha") for p in d["parents"][1:]]
        merge = d["sha"]
    except Err as e:
        if re.search(r"HTTP (404|422)", str(e)):
            return sha
        raise
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        raise Err("unreadable refs/pull/%s/merge: %r" % (n, e))
    return merge if sha in parents else sha

def inactive(repo):
    """The workflow files Actions has disabled (by hand, for inactivity, on a fork): it runs none of them."""
    return {w.get("path") for w in pages("repos/%s/actions/workflows?per_page=100" % repo, "workflows")
            if w.get("state") != "active"}

def pr_expected(repo, sha, base, n, changed):
    """The workflows a pull_request into base with PR n's files at sha runs, read at pr_tree (their
    branches and paths filters; none Actions has disabled); a line for each whose triggers are not read,
    which is not waited on, so the wait is no stricter than with none expected. A head may be the PR's
    first (opened) or a later one (synchronize), so a types list without both is not waited on either."""
    texts = workflows(repo, pr_tree(repo, sha, n))
    want, unread, files = [], [], None
    if texts:
        off = inactive(repo)
        texts = [(p, t) for p, t in texts if p not in off]
        files = pr_files(repo, n, changed, False, *((base, sha) if changed <= COMPARE_FILES else ()))
    for path, text in texts:
        try:
            f = on_filters(text, "pull_request")
            if covers(f, base, files) and {"opened", "synchronize"} <= set(f.get("types", ["opened", "synchronize"])):
                want.append(path)
        except (Unread, re.error) as e:
            unread.append("%s (triggers not read: %s)" % (path, e))
    return want, unread

def run_path(r):
    """A workflow run's file, without the @<ref> a reusable workflow's path carries."""
    return (r.get("path") or "").split("@")[0]

def sha_runs(repo, sha):
    """The workflow runs on sha."""
    return [r for r in pages("repos/%s/actions/runs?head_sha=%s&per_page=100" % (repo, sha), "workflow_runs")
            if r.get("head_sha") == sha]

def head_expected(repo, sha, args):
    """head's red and pending lines for the expected workflows (pr_expected), and its unread lines. Only
    the newest pull_request run of each counts (a push run on sha is not the PR's, and a run a reopen
    or a newer run replaced is over): none is pending, as is one not finished, and one that finished
    other than green is red, check run or not. args are <base> <pr> <changed> and, optionally, a file
    that keeps pr_expected's answer, so a wait reads the workflows once, at the merge commit or the head
    as pr_tree found it on the first read."""
    memo = args[3] if len(args) > 3 else None
    try:
        with open(memo) as fh:
            want, unread = json.load(fh)
    except (TypeError, OSError, ValueError):
        want, unread = pr_expected(repo, sha, args[0], args[1], int(args[2]))
        if memo:
            with open(memo, "w") as fh:
                json.dump([want, unread], fh)
    if not want:
        return [], [], unread
    newest = {}
    for r in sha_runs(repo, sha):
        p = run_path(r)
        if r.get("event") == "pull_request" and (r.get("id") or 0) >= (newest.get(p, {}).get("id") or 0):
            newest[p] = r
    red, wait = [], []
    for p in want:
        if p not in newest:
            wait.append("%s (no run on %s)" % (p, sha[:7]))
        judge([dict(newest[p], name=p)] if p in newest else [], red, wait, [])
    return red, wait, unread

def required(repo, base):
    """The status checks base requires, as base_rules reads them (context, the app that must report
    it or None), and why they could not be read ("" when they were). Any part not read leaves none,
    so every check counts."""
    try:
        return base_rules(repo, base, "squash")[0], ""
    except (Err, ValueError, KeyError, TypeError, AttributeError) as e:
        return [], "%s" % (e or type(e).__name__)

def is_req(r, req):
    """Whether check r is one req names, from the app req binds it to, if any (a status has none)."""
    app = (r.get("app") or {}).get("id")
    return any(r.get("name") == c and (a in (None, -1) or a == app) for c, a in req)

def ci_items(repo, sha):
    """sha's workflow runs, and its check runs and commit statuses, each status as a check run (its
    target_url the html_url, its updated_at the completed_at)."""
    runs = sha_runs(repo, sha)
    items = pages("repos/%s/commits/%s/check-runs?per_page=100" % (repo, sha), "check_runs")
    items += [{"name": s.get("context"), "status": "pending" if s.get("state") == "pending" else "completed",
               "conclusion": s.get("state"), "html_url": s.get("target_url"), "completed_at": s.get("updated_at")}
              for s in pages("repos/%s/commits/%s/status?per_page=100" % (repo, sha), "statuses")]
    return runs, items

def by_rule(req, runs, items):
    """The checks that decide (the required ones, or every one and every workflow run when none is
    required), the rest, and the names of the required checks with no run among items."""
    if not req:
        return items + runs, [], []
    return ([r for r in items if is_req(r, req)], [r for r in items if not is_req(r, req)] + runs,
            [c for c, a in req if not any(is_req(r, [(c, a)]) for r in items)])

def main_ci(repo, sha, base, n, changed, secs, poll, grace):
    """The merge commit needs no check run of its own: the expected workflows are what must run.
    With none expected, ok waits out grace seconds, so an app's checks or a status that appear just
    after the push are seen and judged. A gh error is a missed read, READ_TRIES in a row an error.
    When base requires checks (read once; when any part cannot be read, a warning on stderr, and every
    check counts), only they are red. Any other red check or workflow run waits until each required
    check has a run (a timeout names those with none), then is a warning line after ok, and once every
    required check has finished green nothing else is waited on. Once every expected workflow has
    finished, a required check still with no run never gets one, so every check counts. A red whose
    every check is an Actions run's has those runs' failed jobs rerun, once a run, when the runs have
    finished (a red whose run, or rerun, outlasts the wait is red), with a fresh wait of secs; a transient gh error on the rerun
    is a missed poll, READ_TRIES in a row an error. ok then has a flaky line (flaky <run id> <attempt
    that failed> <its red checks>) per run whose rerun went green. A red line may have a second,
    note: <why>, for a rerun that failed too, was refused or is under way."""
    want, start, missed, rerun_missed = None, time.time(), 0, 0
    end, settled = start + secs, start + min(grace, secs)
    req, why = required(repo, base)
    if why:
        print("warning: could not read %s's required checks (%s), so every check counts" % (base, why), file=sys.stderr)
    # again: run id -> (attempt rerun, its red checks' names, their red lines); held: red, its run finishing
    # or its rerun not started; known: (run id, red line) of a rerun not finished; going: runs not finished
    again, stale, held, going, absent, known = {}, set(), [], set(), [], []
    while True:
        try:
            if want is None:
                want = expected(repo, sha, base, n, changed)
            runs, items = ci_items(repo, sha)
        except Err as e:
            missed += 1
            if missed == READ_TRIES:
                raise Err("%s (%d reads in a row failed)" % (e, missed))
            wait = ["a read failed: %s" % e]
        else:
            missed = 0
            # A rerun run reads pending until its new attempt shows, and its old red checks until they change.
            runs = [dict(r, status="rerun requested") if r.get("id") in again and (r.get("run_attempt") or 0) <= again[r["id"]][0] else r
                    for r in runs]
            items = [dict(r, status="rerun requested") if (r.get("html_url"), r.get("completed_at")) in stale else r for r in items]
            going = {r.get("id") for r in runs if r.get("status") != "completed"}
            mine, rest, absent = by_rule(req, runs, items)
            # Once every expected push workflow has finished (with none expected, once grace is over), a
            # required check with no run will not get one: every check counts then, as with none required.
            if absent and (want or time.time() >= settled) and all(
                    any(run_path(r) == p and r.get("status") == "completed" for r in runs) for p in want):
                mine, rest = items + runs, []
            red, rwait, wait, warn = [], [], [], []
            judge(mine, red, rwait, [])
            judge(rest, warn, wait, [])
            if absent:
                wait, warn = wait + ["%s, held until every required check has a run" % w for w in warn], []
            have = {run_path(r) for r in runs}
            wait += ["%s (no run on %s)" % (p, sha[:7]) for p in want if p not in have]
            bad = [r for r in mine if r.get("status") == "completed" and r.get("conclusion") not in OK]   # red's, in order
            ids = [int(m.group(1)) if m else None for m in (RUN_ID.search(r.get("html_url") or "") for r in bad)]
            held = []
            if red and ids and all(i is not None and i not in again for i in ids):   # each run gets one rerun
                if any(i in going for i in ids):
                    held, rwait = red, rwait + ["%s, finishing before its rerun" % x for x in red]
                else:
                    tried, started = {r.get("id"): r.get("run_attempt") or 1 for r in runs}, []
                    for i in sorted(set(ids)):
                        try:
                            gh("run", "rerun", str(i), "--failed", "--repo", repo)
                        except Err as e:
                            if not TRANSIENT.search(str(e).split(": ", 1)[-1]):
                                return CI_RED, red_line(red, [], sorted(j for j in again if j in started or j in going),
                                                        "A rerun of run %d's failed jobs was refused: %s" % (i, e))
                            rerun_missed += 1
                            if rerun_missed == READ_TRIES:
                                raise Err("%s (%d reruns in a row failed)" % (e, rerun_missed))
                            held, rwait = red, rwait + ["a rerun failed: %s" % e]   # red, if the wait runs out first
                            break
                        rerun_missed, mine_i = 0, [r for j, r in zip(ids, bad) if j == i]
                        again[i] = (tried.get(i) or 1, [str(r.get("name")) for r in mine_i], [x for j, x in zip(ids, red) if j == i])
                        end = time.time() + secs
                        stale |= {(r.get("html_url"), r.get("completed_at")) for r in mine_i}
                        started.append(i)
                    rwait += ["%s, rerun" % x for x in red]
                red = []
            if red:
                return CI_RED, red_line(red, sorted(i for i in again if i in ids), sorted(i for i in again if i not in ids and i in going))
            green = {r.get("name") for r in items + runs if r.get("status") == "completed" and r.get("conclusion") in OK}
            # The reds whose rerun has not finished: red, if the wait runs out first.
            rerunning = {int(m.group(1)) for r in items if r.get("status") == "rerun requested"
                         for m in [RUN_ID.search(r.get("html_url") or "")] if m} | (going & set(again))
            known = [(i, x) for i in sorted(rerunning & set(again)) for n, x in zip(again[i][1], again[i][2]) if n not in green]
            if not rwait and ((req and not absent) or (not wait and (want or time.time() >= settled))):
                return CI_OK, "\n".join(["ok"] + ["warning: %s is red on %s, which does not require it" % (w, base) for w in warn]
                                       + ["flaky %d %d %s" % (i, a, "; ".join(x)) for i, (a, x, _) in sorted(again.items()) if set(x) <= green])
            wait = rwait + wait
        if time.time() >= end:
            if held or known:
                return CI_RED, red_line(held + [x for _, x in known], [], sorted({i for i, _ in known} | (going & set(again))))
            return CI_TIMEOUT, "timeout (%s)" % "; ".join(wait + ["%s (required, no run on %s)" % (c, sha[:7]) for c in absent])
        time.sleep(poll)

def red_line(red, failed, under, refused=""):
    """main_ci's red: red <checks>, then note: <why> when the runs failed were rerun and failed too, a
    rerun was refused, or the runs under are being rerun."""
    why = ["Run %d's failed jobs were rerun once, and the rerun failed too" % i for i in failed]
    why += [refused] if refused else []
    why += ["A rerun of run %d's failed jobs is under way" % i for i in under]
    return "red " + "; ".join(red) + ("\nnote: " + "; ".join(why) if why else "")

def fixed(repo, sha, base, red_sha, board, names):
    """Why sha does not show a red main fixed, or None. A board-only commit's CI may skip its tests,
    so it is judged by its first parent, back to the newest commit that is not board-only (a fix, then
    a finish or a merge --board). There everything must be green, as main_ci judges a merge commit (no
    check run needed of its own), and either each check that went red passed there, or base requires
    checks and each of those passed: a fix may rename or drop the job that failed, but a check a path
    filter skipped has no run that passed. Once each required check has a run, only those must be
    green, as main_ci judges them. It must hold red_sha in its history: a merge that landed
    before the red one and whose wait ended after it fixes nothing."""
    for _ in range(FIXED_WALK):
        files, parents = [], []
        for d in docs("repos/%s/commits/%s" % (repo, sha)):
            if not (isinstance(d, dict) and isinstance(d.get("files"), list)):
                raise Err("unreadable commit " + sha[:7])
            files += [f.get("filename") or "" for f in d["files"]]
            parents = [p.get("sha") for p in d.get("parents") or [] if isinstance(p, dict)] or parents
        if not (board and files and all(f.startswith(tuple(board)) for f in files)):
            break
        if not parents or not re.fullmatch(r"[0-9a-f]{40}", parents[0] or ""):
            return "%s changes only the board's files" % sha[:7]
        sha = parents[0]
    else:
        return "no commit that is not board-only within %d of the head" % FIXED_WALK
    if sha != red_sha and json.loads(gh("api", "repos/%s/compare/%s...%s" % (repo, red_sha, sha))).get("behind_by") != 0:
        return "%s does not have the red %s in its history" % (sha[:7], red_sha[:7])
    req = required(repo, base)[0]   # none read: each check that went red decides
    runs, items = ci_items(repo, sha)
    mine, rest, absent = by_rule(req, runs, items)
    red, wait = [], []
    judge(mine, red, wait, [])
    if absent:   # until each required check has a run, every check counts, as in main_ci
        judge(rest, red, wait, [])
        wait += ["%s (required, absent)" % c for c in absent]
    if red or wait:
        return "; ".join(red + wait)
    passed = {r.get("name") for r in mine if r.get("status") == "completed" and r.get("conclusion") == "success"}
    missing = [n for n in names if n not in passed]
    if missing and not req:
        return "; ".join("%s (no run that passed)" % n for n in missing)
    return None

try:
    mode, repo, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if mode == "head":
        red, wait, ok = checks(repo, args[0])
        # A red head is red whatever has run, so the expected workflows are read only when there is none.
        bad, more, unread = head_expected(repo, args[0], args[1:]) if args[1:] and not red else ([], [], [])
        red, wait = red + bad, wait + more
        print("; ".join(red + wait or ok))
        if unread:
            print("not waited on: " + "; ".join(unread))
        if red or wait:
            sys.exit(1 if red else 2)
    elif mode == "fixed":
        why = fixed(repo, args[0], args[1], args[2], [b for b in args[3].split("\n") if b], args[4:])
        print(why or "fixed")
        if why:
            sys.exit(1)
    elif mode == "base":
        # head's rule for a base's head: a commit status alone counts, as on main, but with no check
        # run and no status nothing has concluded. A red head prints its red checks alone.
        red, wait, ok = checks(repo, args[0], need_run=False)
        wait = wait if red or wait or ok else ["no check runs or statuses"]
        print("; ".join(red or wait or ok))
        if red or wait:
            sys.exit(1 if red else 2)
    elif mode == "required":
        # The checks base requires, one name a line (none for a base that requires none); an error when any
        # part of its rules cannot be read.
        req, why = required(repo, args[0])
        if why:
            raise Err(why)
        print("\n".join(sorted({c for c, _ in req})))
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
    elif mode == "behind":
        try:
            n, off = behind(repo, args[0], args[1], [b for b in args[2].split("\n") if b], float(args[3]))
        except Unlisted as e:
            print("error %s" % e)
            sys.exit(UNLISTED)
        print("\n".join([str(n)] + off))
    elif mode == "merged":
        extra = merged(repo, args[0], args[1], args[2])
        if extra:
            print(", ".join(extra[:5]) + (" and %d more" % (len(extra) - 5) if len(extra) > 5 else ""))
            sys.exit(1)
    elif mode == "queue":
        print("yes" if has_queue(repo, args[0], float(args[1])) else "no")
    elif mode == "pushed":
        print(pushed(repo, args[0], args[1], float(args[2])))
    elif mode == "stop":
        print(stop_pr(repo, args[0]))
    elif mode == "queued":
        rc, msg = queued(repo, args[0], args[1], args[2], float(args[3]), float(args[4]), float(args[5]))
        print(msg)
        sys.exit(rc)
    elif mode in ("files", "files-status"):
        files = pr_files(repo, args[0], int(args[1]), mode == "files-status", *args[2:4], hold=float(args[4]) if len(args) > 4 else None)
        if not files:
            raise Err("gh listed no files, or fewer than the PR changes")
        print("\n".join(files))
    else:
        rc, msg = main_ci(repo, args[0], args[1], args[2], int(args[3]), float(args[4]), float(args[5]), float(args[6]))
        print(msg)
        sys.exit(rc)
except Exception as e:
    print("error %s" % (e or type(e).__name__))
    sys.exit(CI_ERROR)
