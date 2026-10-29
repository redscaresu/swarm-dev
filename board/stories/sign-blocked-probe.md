---
kind: code
status: ready
epic: delivery-liveness
depends_on: []
touches: [bin/lib/panes.py:sign_blocked (new), bin/lib/agents.sh:sign_blocked (new, beside bg_running), tests/agent_liveness_test.sh:sign probe cases, tests/test_helpers.sh:signer isolation]
estimate_lines: 260
easy: false
risk: high
---

# sign_blocked: a probe for a builder that cannot sign its work

Needs from sign-probe-pick: the confirmed method for openpgp and for ssh. Goal 3, HLD Open question 3 (decided in the epic). Add panes.py:sign_blocked(worktree) and an agents.sh wrapper `sign_blocked <worktree>` next to bg_running, with the same python3 -I shape. It is true only when all three hold: (1) the worktree's effective git config has commit.gpgsign true; (2) `git status --porcelain` is non-empty; (3) the signer git is set to use cannot sign. gpg.format picks the signer: openpgp (the default) has no cached passphrase for the signing key, read by the picked method (the key is user.signingkey, else the committer's email, which git passes to -u); ssh fails the picked check; x509 is never blocked. With gpgsign unset or false, or a clean tree, it returns before any gpg, gpg-connect-agent or ssh-keygen call. It reads git, gpg-agent and the ssh signer only: no pane, no transcript. It never opens a key file itself and never prints key material. Use gpg.program, gpg.openpgp.program or gpg.ssh.program as git would. Every external call has a subprocess timeout, and a timeout reads as not blocked. Nothing calls it yet: sign-blocked-incident wires it into agent_stalled, and lead-woken's sign-blocked: line reads it. Tests isolate git config (GIT_CONFIG_GLOBAL, or GIT_CONFIG_COUNT as tests/stacked_test.sh:160-166 does for gpg.format=ssh) and use stubs on PATH that log each call. No real key. The method (decided by the lead in planning, replacing the sign-probe-pick lead story; skeptic review, 2026-10-29): read only, never sign, never prompt. openpgp: ask the agent whether the signing key's keygrip has a cached passphrase (gpg-connect-agent KEYINFO, bounded), using the signing subkey's keygrip, not the primary key's, and the gpg-connect-agent beside the gpg that gpg.program names (its directory), never a PATH lookup that could reach another install. ssh: blocked only when user.signingkey is a public key (a path to a .pub or a key:: literal) and `ssh-add -L`, bounded and on SSH_AUTH_SOCK, does not list it; an unencrypted private-key file reads as not blocked; gpg.ssh.program and `ssh-keygen -Y sign` are never run. x509: report unknown, which neither blocks nor clears a stall. Every probe test sets HOME, GIT_CONFIG_GLOBAL and GIT_CONFIG_NOSYSTEM=1 to a temp dir and puts stub gpg, gpg-connect-agent, ssh-add and ssh-keygen first on PATH, so no test reaches the user's real signer.

**Done when:**
- tests/agent_liveness_test.sh sign probe cases: gpgsign true, one uncommitted edit, and a stub that reports the key uncached make sign_blocked exit 0.
- False cases, each exit 1: gpgsign unset; gpgsign false; a clean tree; the key cached; for the keyinfo method, a key with no passphrase.
- With gpgsign unset or false, the stub gpg, gpg-connect-agent and ssh-keygen log no call (their log files stay empty).
- gpg.format=ssh with a healthy key (the stub signer succeeds) exits 1 and calls no gpg; with the stub signer failing as a locked or absent key does, it exits 0; gpg.format=x509 exits 1.
- A stub that hangs past the timeout: sign_blocked returns 1 within the timeout plus 5 s.
- python3 -m py_compile, shellcheck, tests/loose_match_test.sh and tests/timeouts_test.sh pass.
- No ssh case calls ssh-keygen -Y sign or gpg.ssh.program (the stubs log every call, and the log has none).
- The openpgp case with a signing subkey reads the subkey's keygrip; a probe that reads the primary key's goes red.
- With gpg.format=ssh and a key ssh-add lists, the probe reports clear; with gpg.format=x509 it reports unknown.
- Every probe test runs with HOME, GIT_CONFIG_GLOBAL and GIT_CONFIG_NOSYSTEM=1 set to a temp dir (a test asserts the probe read the temp config, not ~/.gitconfig).
