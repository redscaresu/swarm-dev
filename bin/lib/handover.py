"""handover.py <out> <swarm dir> <memory dir or ""> <board checkout> <commit> <branch> <project checkout>
— the copy half of swarm.sh handover (handover_report in bin/lib/handover.sh), which has already
written <out>/board.patch, against <commit> on <branch> of <board checkout>.

It writes into <out>:
  swarm/       <swarm dir> (the project's .swarm/) without its session logs (no *.jsonl or *.jsonl.gz
               file and nothing under a folder named sessions) and without what belongs to this machine
               (LOCAL): state/ (herdr pane records, which on another machine would claim its panes of the
               same id), launch/ (agent launch wrappers, which hold the environment values an agent
               started with, credentials among them), locks/, the lead's herdr workspace records,
               auto-mode-done, and every lock and pid file. No agent
               session id comes with it: agents.tsv's session column (its 7th) is "-" on every line, the
               value the readers take as no session, and every UUID in every file copied is "-" too, as
               events.tsv names sessions in free text ("resumed session <id>").
  memory/      <memory dir>, only when it is named, under the same rules.
  snapshot.md  the open PRs (HANDOVER_PRS, gh pr list's JSON, else HANDOVER_PRS_ERR says why not) and
               this project's agents (HANDOVER_AGENTS, herdr agent list's JSON, kept to the panes the
               pane records in state/ name, else HANDOVER_AGENTS_ERR); each with only the fields it names.
  RESTORE.md   how to restore each part into a fresh clone, as commands run from the clone's root that
               name the handover by HANDOVER_DIR, not by <out>, so it can move; and every path it skipped.
A file or folder whose name looks like a credential (token, key, secret, password ...) is never opened,
not even to read a pane record: it is listed in RESTORE.md as skipped. In .swarm/, a name that is a slug
swarm.sh knows (known_slugs), alone or with .md, is its own record, whatever words the slug holds; a
credential file's type (.pem, .key, .env ...) is skipped whatever its name. So is anything that is not a
regular file or folder (a symlink could lead out of the folder to anything).
"""
import datetime
import json
import os
import re
import subprocess
import sys

# A credential's name: a word one holds (which a slug can hold too), or a credential file's type, which
# no slug exemption overrides.
CREDENTIAL_WORD = re.compile(r"token|secret|key|credential|passw", re.I)
CREDENTIAL_FILE = re.compile(r"\.(pem|p12|pfx|key|keystore|jks|env)$|^\.env|netrc|^id_(rsa|dsa|ecdsa|ed25519)", re.I)
SLUG_SUFFIXES = ("", ".md")   # the names swarm.sh gives a record by slug: <slug> and <slug>.md
SESSION_LOG = re.compile(r"\.jsonl(\.gz)?$")
SESSIONS_DIR = "sessions"
STATE_DIR = "state"   # STATE_DIR in bin/swarm.sh
# What in .swarm/ belongs to this machine, each with why it is left out: the paths in LOCAL,
# and at any depth a lock (a merge lock holds a pid, which on another machine may name a live process)
# or a pid file.
LOCAL = {
    STATE_DIR: "this machine's herdr pane records, which would claim panes of the same id on another",
    "launch": "agent launch wrappers, which hold the environment values an agent started with, credentials among them",
    "locks": "this machine's locks",
    "lead/workspace": "this machine's herdr workspace id for the lead",
    "lead/agents-workspace": "this machine's herdr workspace id for the lead's agents",
    "auto-mode-done": "this machine's word that auto mode's setup ran: run /auto-mode-setup on the new one, "
                      "then swarm.sh init --auto-mode-done",
}
LOCK = re.compile(r"\.lock$")
PID_FILE = re.compile(r"(^|\.)pid$")


def local_why(rel, name):
    """Why <name>, in folder <rel> of .swarm/, belongs to this machine, or None."""
    path = os.path.normpath(os.path.join(rel, name))
    if path in LOCAL:
        return LOCAL[path]
    if LOCK.search(name):
        return "this machine's lock"
    if PID_FILE.search(name):
        return "a process id on this machine"
    return None
# A pane record's line, as own_panes (bin/lib/agents.sh) reads it: "<pane> [name]".
PANE_RECORD = re.compile(r"^([A-Za-z0-9]+:[A-Za-z0-9]+)(?:\s+\S+)?\s*$")
UUID = re.compile(rb"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
AGENTS_TSV = "agents.tsv"
SESSION_COLUMN = 6   # agents.tsv's 7th field
NO_SESSION = b"-"


def scrub(data, is_agents_log):
    """<data> with every UUID "-", and, in agents.tsv, every line's session column "-" whatever its form."""
    data = UUID.sub(NO_SESSION, data)
    if is_agents_log:
        lines = []
        for line in data.split(b"\n"):
            cols = line.split(b"\t")
            if len(cols) > SESSION_COLUMN:
                cols[SESSION_COLUMN] = NO_SESSION
            lines.append(b"\t".join(cols))
        data = b"\n".join(lines)
    return data


def known_slugs(swarm, board, checkout):
    """The slugs swarm.sh names its records by (board-state/stories/<slug>, a pane record named for its
    agent): every story and epic file the board has held, from its history in <checkout> and its folder
    now (untracked ones too), and every agent name in agents.tsv. A slug can hold any word, key among them."""
    names, rel = set(), os.path.relpath(board, checkout)
    folders = [os.path.normpath(os.path.join(rel, k)) for k in ("stories", "epics")]
    try:
        log = subprocess.run(["git", "-C", checkout, "log", "--format=", "--name-only", "--"] + folders,
                             capture_output=True, text=True, check=True).stdout
        names.update(os.path.basename(p)[:-3] for p in log.split("\n") if p.endswith(".md"))
    except (OSError, subprocess.CalledProcessError):
        pass
    for k in ("stories", "epics"):
        try:
            names.update(n[:-3] for n in os.listdir(os.path.join(board, k)) if n.endswith(".md"))
        except OSError:
            pass
    try:
        with open(os.path.join(swarm, AGENTS_TSV), encoding="utf-8", errors="replace") as f:
            names.update(c[2] for c in (l.rstrip("\n").split("\t") for l in f) if len(c) > 2 and c[2])
    except OSError:
        pass
    names.discard("README")
    return names


def credential_named(name, known):
    """<name> looks like a credential's: a credential file's type, whatever its stem, or a credential word,
    unless <name> is a slug in <known> as swarm.sh names a record by it (SLUG_SUFFIXES). No such name has a
    credential file's type today; the type is checked first so that one never would, were SLUG_SUFFIXES to grow."""
    if CREDENTIAL_FILE.search(name):
        return True
    return bool(CREDENTIAL_WORD.search(name)) and not any(name == k + x for x in SLUG_SUFFIXES for k in known if name.startswith(k))


def readable(path, name, known):
    """Why <path> (named <name>) must not be opened, or None when it may be."""
    if credential_named(name, known):
        return "its name looks like a credential, so it was not read"
    if os.path.islink(path) or not os.path.isfile(path):
        return "not a regular file"
    return None


def copy_tree(src, dest, label, skipped, machine=False, known=frozenset()):
    """Copy <src> into <dest> under the rules above; return how many session logs it left out. Each
    skipped path goes in <skipped> as (label/path, why). With <machine> (.swarm/), what local_why
    names is left out too. A name in <known> is a slug, never taken for a credential's."""
    logs = 0
    os.makedirs(dest, exist_ok=True)
    def unread(err):   # a folder os.walk cannot list: said in RESTORE.md, never dropped quietly
        shown = os.path.normpath(os.path.join(label, os.path.relpath(err.filename, src)))
        skipped.append((shown + "/", "could not be read (%s), so nothing in it was copied" % err.strerror))

    for root, dirs, files in os.walk(src, onerror=unread):
        rel = os.path.relpath(root, src)
        keep = []
        for d in sorted(dirs):
            path = os.path.join(root, d)
            shown = os.path.normpath(os.path.join(label, rel, d)) + "/"
            if d == SESSIONS_DIR:
                logs += sum(len(fs) for _, _, fs in os.walk(path))
            elif machine and local_why(rel, d):
                skipped.append((shown, local_why(rel, d)))
            elif credential_named(d, known):
                skipped.append((shown, "its name looks like a credential, so nothing in it was read"))
            elif os.path.islink(path):
                skipped.append((shown, "a symlink, not a folder of its own"))
            else:
                keep.append(d)
        dirs[:] = keep
        for name in sorted(files):
            path = os.path.join(root, name)
            why = None if not SESSION_LOG.search(name) else "session log"
            if why:
                logs += 1
                continue
            why = readable(path, name, known) or (machine and local_why(rel, name))
            if why:
                skipped.append((os.path.normpath(os.path.join(label, rel, name)), why))
                continue
            target = os.path.join(dest, rel, name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(path, "rb") as f:
                data = scrub(f.read(), label == "swarm" and rel == "." and name == AGENTS_TSV)
            with open(target, "wb") as f:
                f.write(data)
            st = os.stat(path)
            os.chmod(target, st.st_mode & 0o777)
            # Its own times, which readers compare (epic_report_stale: a conductor report against the epic's
            # last merge); RESTORE.md's cp -Rp keeps them.
            os.utime(target, ns=(st.st_atime_ns, st.st_mtime_ns))
    return logs


def own_panes(swarm, known):
    """The pane ids this project's pane records in <swarm>/state name, opening only files readable()
    allows (own_panes in bin/lib/agents.sh reads every regular file there)."""
    panes, state = set(), os.path.join(swarm, STATE_DIR)
    if os.path.islink(state) or not os.path.isdir(state):   # a symlink could name another project's
        return panes
    for name in os.listdir(state):
        path = os.path.join(state, name)
        if readable(path, name, known):
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            panes.update(m.group(1) for m in map(PANE_RECORD.match, f) if m)
    return panes


def pr_lines():
    raw = os.environ.get("HANDOVER_PRS", "")
    if not raw:
        return ["not read: " + os.environ.get("HANDOVER_PRS_ERR", "no reason given")]
    try:
        prs = json.loads(raw)
    except ValueError:
        return ["not read: gh pr list gave no JSON"]
    out = []
    for p in prs:
        kind = "draft" if p.get("isDraft") else "open"
        out.append("#%s %s (%s, %s) %s" % (p.get("number"), p.get("title"), p.get("headRefName"), kind, p.get("url")))
    return out or ["none open"]


def agent_lines(own):
    raw = os.environ.get("HANDOVER_AGENTS", "")
    if not raw:
        return ["not read: " + os.environ.get("HANDOVER_AGENTS_ERR", "no reason given")]
    try:
        agents = json.loads(raw)["result"]["agents"]
    except (ValueError, KeyError, TypeError):
        return ["not read: herdr agent list gave no agent list"]
    # Its name and pane only: an agent's state comes from its session (tests/agent_state_test.sh), and
    # on another machine it is gone anyway.
    out = ["%s, pane %s" % (a.get("name"), a.get("pane_id")) for a in agents if str(a.get("pane_id")) in own]
    return out or ["none running in this project's panes"]


def write_snapshot(out, checkout, commit, branch, when, own):
    with open(os.path.join(out, "snapshot.md"), "w") as f:
        f.write("# Snapshot\n\nTaken %s from %s, at commit %s on %s.\n" % (when, checkout, commit, branch))
        f.write("\n## Open PRs\n\n" + "".join("- %s\n" % l for l in pr_lines()))
        f.write("\n## Agents\n\n" + "".join("- %s\n" % l for l in agent_lines(own)))


def write_restore(out, commit, branch, when, memory, logs, skipped, board_repo):
    here = '"${HANDOVER_DIR:?set HANDOVER_DIR to this folder}"'
    at = "check out %s at commit %s (the board patch is against that commit)" % (branch, commit)
    lines = [
        "# Restoring this handover", "",
        "Written by swarm.sh handover at %s. It holds what another machine needs that git does not carry." % when,
        "Keep it private: never commit it or push it anywhere%s." % (", as memory/ holds the lead's own notes" if memory else ""),
        "", "## Restore", "",
        ("Clone the project. Its board is in a repo of its own (%s): clone that too and %s." % (board_repo, at)) if board_repo
        else ("Clone the project and %s." % at),
        "Set HANDOVER_DIR to this folder's path on the new machine, then run each block from the project clone's root.", "",
    ]
    if board_repo:
        lines += ["The project's board_dir in .claude/swarm/config names %s on the old machine. If the board's clone"
                  % os.environ.get("HANDOVER_BOARD", "the board's folder"),
                  "sits anywhere else, set board_dir to the same folder in it, or swarm.sh reads no board.", ""]
    lines += [
        "The project's .swarm/, which git ignores:", "", "```sh",
        "mkdir -p .swarm", "cp -Rp %s/swarm/. .swarm/" % here, "```", "",
    ]
    if os.path.getsize(os.path.join(out, "board.patch")):
        where = "the board repo's clone's root, not the project's" if board_repo else "the clone's root"
        lines += ["The main checkout's uncommitted board edits, run from %s:" % where, "", "```sh",
                  "git apply --binary %s/board.patch" % here, "```", ""]
    else:
        lines += ["The main checkout had no uncommitted board edits, so board.patch is empty.", ""]
    if memory:
        lines += ["The lead's memory folder, into the one Claude Code reads for this clone:", "", "```sh",
                  'dest="${CLAUDE_PROJECTS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}/$(pwd -P | sed \'s/[^A-Za-z0-9]/-/g\')/memory"',
                  'mkdir -p "$dest"', 'cp -Rp %s/memory/. "$dest/"' % here, "```", ""]
    lines += ["snapshot.md lists the PRs that were open and the agents that ran. The PRs are on GitHub",
              "already; the agents do not move, so start each one's work again on this machine.", "",
              "## Skipped", ""]
    lines.append("- %d session log%s: no *.jsonl or *.jsonl.gz file, and nothing under a sessions folder. "
                 "agents.tsv's session column, and every UUID in the files copied, is -." % (logs, "" if logs == 1 else "s"))
    lines += ["- %s: %s" % s for s in skipped]
    with open(os.path.join(out, "RESTORE.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    out, swarm, memory, checkout, commit, branch, project = sys.argv[1:8]
    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    skipped, logs, own = [], 0, set()
    if os.path.isdir(swarm):
        known = known_slugs(swarm, os.environ.get("HANDOVER_BOARD", checkout), checkout)
        logs = copy_tree(swarm, os.path.join(out, "swarm"), "swarm", skipped, machine=True, known=known)
        own = own_panes(swarm, known)
    else:
        os.makedirs(os.path.join(out, "swarm"))   # a project with no .swarm/ yet: RESTORE.md's copy still runs
    if memory:
        copy_tree(memory, os.path.join(out, "memory"), "memory", skipped)
    write_snapshot(out, checkout, commit, branch, when, own)
    write_restore(out, commit, branch, when, memory, logs, skipped, checkout if checkout != project else "")
    print("handover: wrote %s (swarm/, board.patch, snapshot.md, RESTORE.md%s); %d session logs left out, %d paths skipped"
          % (out, ", memory/" if memory else "", logs, len(skipped)))


if __name__ == "__main__":
    main()
