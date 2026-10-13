---
kind: lead
status: ready
epic: agent-state-from-the-session
depends_on: [pin-claude-version]
touches: []
---

# Older Claude Code builds for the version pin, only if it asks for them

Needed only if pin-claude-version stops for it. The lead turns that builder's reply into exact commands. **You:** install the named builds, or start a logged-in session of each, then tell the lead they are ready. The lead tells the builder to carry on. If the pin needs none, the lead closes this story and notes that nothing was needed.

**Done when:** pin-claude-version's builder has run its checks on every build it named, or it reported needing none, and the lead has recorded which on this story.
