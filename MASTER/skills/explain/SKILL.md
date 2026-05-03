---
name: explain
triggers:
  - "explain"
  - "what is"
  - "how does"
  - "why does"
description: Explain a MASTER rule, concept, or code construct in plain terms with a before/after example.
---

Invoked when the user asks for an explanation. Calls `/why <rule>` for rule queries.
Returns 2–3 sentences plus a concrete example. No hedging. No padding.
