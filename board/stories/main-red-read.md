---
kind: code
status: blocked
epic: lead-woken
depends_on: [lead-alerts-wired]
needs: [lead-alerts-wired (main_red_lines, wired in lead_queue)]
touches: [bin/lib/lifecycle.sh:lead_bases (new), bin/lib/lifecycle.sh:lead_wake heads pass, bin/lib/lifecycle.sh:main_red_lines, tests/wait_lead_test.sh:main-red read cases, docs/reference.md:the main-red row]
estimate_lines: 170
easy: false
risk: high
---

# wait --lead reads each base head's CI and prints main-red: for a red one, clearing it once the base goes green

Split from main-red-line (skeptic review, 2026-10-29). Needs lead-alerts-wired's empty main_red_lines. Needs from lead-alerts-wired: the empty main_red_lines that lead_queue calls after pr_lines, and main-red: being an alert. Needs from fix-main-outside-merge: fix_main's mode for a red that no swarm merge made. Two parts. (1) The base read: a new function lead_bases, called from lead_wake's heads-pass block (lifecycle.sh:3784-3788). Polls between heads passes then still make no gh call, as docs/reference.md § The lead promises. It covers the project's repo and each repo: the stories name (open_story_prs' list and its LEAD_REPOS cache). For each, read the base's head sha (gh api repos/<nwo>/commits/<base>, under within BASE_HEAD_WAIT, as green_mains does at merge.sh:1743-1752). For a head whose CI has not concluded, run ci_gate head <nwo> <sha> under within (0 green, 1 red, 2 pending or no runs, 3 unread; merge.sh:44-47). Keep '<nwo> <base> <sha> <verdict>' in a file under .swarm/lead. A head is marked read only once its CI has concluded (green or red), so a pending or unread head is read again on the next heads pass, and a later red on the same sha still counts. Do not call base_for (bin/swarm.sh:362): it fetches and can die. Resolve each repo's base once a run, bounded. On red, when key_reds <key> (merge.sh:1614-1620) does not hold the sha (merge_pr's fix_main has not recorded it), run fix_main's new mode detached and pinned to the project. Send its output to a file under .swarm/lead, never inside lead_queue's $(...) (lifecycle.sh:3790), with SWARM_FIX_MAIN_LOG_SECONDS set small. Do not start a second run for a sha whose run is still going. (2) main_red_lines prints a line for each live red (key_reds live, or main_red: events only, no gh), whoever recorded it: `main-red: <sha7> <owner/repo> <base> (<red checks, cut by ci_data>), exit: build fix-main-<sha7>, which next names first`. A base cleared by main-green prints nothing. Docs: a main-red bullet in docs/reference.md § The lead, replacing the sentence 'A red `main` is not one of these' (reference.md:161), which would be false, and a commands/swarm.md paragraph for the line. This story is the read and the line only: lead_bases resolves each repo's base once a run as base_for does (base_branches first, else the default branch), bounded, and keeps a per-head state file; a head whose CI is pending or not started is rechecked in the heads pass (which already runs gh) until it concludes. When the base's head goes green while a red is recorded, the read clears it through the existing bounded clear path (clear_red_main, merge.sh:1724-1741), so the line does not outlive the fix. It starts no fix_main: main-red-fix does. A head that concluded green is not marked read for good: it is rechecked, bounded, for as long as it is the base's head and at most 2 hours, so a rerun that fails on the same sha still prints main-red:.

**Done when:**
- A fixture base whose head goes pending, then red, prints one main-red: line once CI concludes red, and none while it is pending.
- A red base that later goes green with no injected main-green event clears the line on the next poll (the read writes the clear).
- base_branches picks the base: a fixture with base_branches = dev reads dev, not the default branch.
- A head that concludes green and then goes red on a rerun of the same sha prints main-red: on the next poll.
