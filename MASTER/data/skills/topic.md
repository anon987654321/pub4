---
name: topic
description: Track the current conversation or workstream topic.
triggers:
  - "\\btopic\\b"
---

The topic skill tracks the current conversation or workstream topic so later turns can resume without re-deriving intent. It responds on topic or when MASTER should label what is being worked on for session continuity.

Keep topic labels short and meaningful enough to recover later. One line should be enough for the operator to recognize the thread days afterward.