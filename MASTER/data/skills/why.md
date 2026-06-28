---
name: why
description: Explain a rule, finding, or design choice with local evidence.
triggers:
  - "\\bwhy\\b"
---

The why skill explains a rule, finding, or design choice using evidence from the repository and session. It activates on why or when the operator asks for rationale behind a constraint, scan result, or architectural decision.

Prefer direct file references and current state over memory or theory. Point to the code, config, or log line that justifies the explanation.