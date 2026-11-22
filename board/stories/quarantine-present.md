---
kind: lead
status: ready
epic: binary-fetch
depends_on: []
touches: [board/hld/2026-11-18-swarm-dev-v0-32-go-rewrite.md:The wrapper refuses (the quarantine line, :224), board/epics/binary-fetch.md:Done when]
estimate_lines: 0
---

# You decide whether a binary already present that carries macOS's quarantine mark is refused on every call

Needs no other story.
The epic and the HLD disagree. The epic's Done when (2)-(3): a quarantine mark stops the call, and the checks run once, at download. HLD:224: the wrapper refuses to run a file that carries the mark. A mark added after the download, such as a plugin folder copied through a browser or AirDrop, is caught only by a check on every call.
The cost of a check on every call on macOS is one /usr/bin/xattr start. On the lead's Mac on 2026-11-22: 20 runs of `/usr/bin/xattr -p com.apple.quarantine /bin/ls`, median 3.4 ms, min 2.5 ms, one run 1009 ms. Linux pays nothing.
**You:** choose one.
(a) At download only, as the epic says. The lead changes HLD:224 to say the mark is checked once, at download, on a board PR you merge.
(b) Every call on macOS. The lead amends the epic's Done when (3) to name this one check, and fetch-quarantine's (b) items apply: binary_present (fetch-ensure) runs binary_quarantined on <root>/swarm on Darwin and refuses a marked file in one line.
fetch-quarantine waits on this step. Nothing else does: fetch-ensure keeps the present-binary test in binary_present, the one place (b) changes.

**Done when:**
- The user's choice, (a) or (b), and its date are in this story file.
- (a): the HLD's quarantine line says the mark is checked at download, on a board PR the user merged. (b): the epic's Done when (3) names the exception, and board/stories/fetch-quarantine.md says (b) applies.
