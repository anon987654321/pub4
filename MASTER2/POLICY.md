# MASTER Policy

## Mode / Intent Rules

| Intent | Allowed output | Blocked output |
|--------|----------------|----------------|
| `:ops` | commands, diffs, tool results, status | narrative, fiction, chapter headings |
| `:refactor` | diffs, code, analysis | ungrounded execution claims |
| `:chat` | anything | — |
| `:doc` | documentation, examples | shell commands with side effects |
| `:creative` | anything | claims about system state |

**Enforcement**: `OutputGuard` + `Policy::Enforcer` run on every LLM response before it reaches the user.

---

## Hard Policy Rules (block output)

| Rule ID | Scope | Trigger | Action |
|---------|-------|---------|--------|
| `OPS_NO_NARRATIVE` | `:ops` | "Chapter N", "To be continued" | `Result.err` |
| `OPS_NO_UNGROUNDED_EXECUTION_CLAIMS` | `:ops` | "I ran/deployed/installed" without evidence hash | `Result.err` |

**Hard violations abort the response.** The user sees an error, not the invalid output.

---

## Soft Policy Rules (warn, allow)

Soft rules attach `policy_violations` to the result payload but do not block. Used for metrics and trending.

---

## Capability Policy

Default capability level: **1 (propose)** — read files, generate plans, never write.

Escalation requires explicit flags:

```
--apply      → level 2 (write files)
--exec        → level 3 (run shell commands)  
DEPLOY=1 + --apply --exec → level 4 (deploy)
```

`MASTER_CAP=N` env var overrides for scripted use.

---

## Injection Policy

`Security::InjectionGuard` runs on every tool output before normalization.

- **Severe patterns** (override system prompt, disregard axioms): block immediately (`Result.err`, category `:security`).
- **3+ hits** of any injection pattern: block immediately.
- **1–2 hits** of soft patterns: redact to `[REDACTED:injection_attempt]`, continue.

---

## Input Length Policy

Inputs exceeding `Pipeline::MAX_INPUT_LENGTH` (100,000 bytes, ~25k tokens) are rejected with `Result.err(category: :input)`. Send smaller chunks.

---

## Evidence Requirements (Ops Mode)

In `:ops` mode, any response claiming an action occurred must include one of:

- A `ToolResult` with a non-nil `content_hash`
- An explicit `exit_code`
- A file path in `files_touched`

Responses lacking evidence for execution claims are blocked by `OPS_NO_UNGROUNDED_EXECUTION_CLAIMS`.

---

## Axiom Alignment

The 68 axioms in `data/axioms.yml` are the source of truth for code quality governance. `Policy::Enforcer` starts with the two highest-frequency violations (narrative in ops, ungrounded claims). Additional axioms are compiled into rules incrementally — see Phase C roadmap.

---

## Audit Trail

Every `pipeline.call` creates a `request_id` (set by `Logging.with_request_id`). Tool calls attach `evidence_hash` to history entries. Both are available in `var/db/` JSONL logs.
