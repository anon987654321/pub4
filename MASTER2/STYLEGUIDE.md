# MASTER Style Guide

## Core Philosophy

Boring behavior with sharp edges only when explicitly requested. (OpenBSD doctrine.)

---

## Naming

| Prefer | Avoid | Reason |
|--------|-------|--------|
| `PolicyEnforcer` | `AxiomRunner` | Operational vs philosophical |
| `IntentClassifier` | `ModeDetector` | Task-oriented |
| `OutputGuard` | `ModeGate` | Enforcement-oriented |
| `Refinement` | `PressurePass` | Self-describing |
| `ToolResult` | raw string | Contract-enforcing |
| `StateStore` | `DB` (future) | Explicit purpose |

**If a name sounds clever, rename it. If it sounds literal and slightly boring, keep it.**

---

## POLA (Principle of Least Astonishment)

- **Dry-run default**: anything that writes, edits, or deploys is dry-run unless `--apply`.
- **No implied execution**: in ops mode, never say "I deployed" unless a `ToolResult` with `evidence_hash` exists.
- **Stable flag semantics**: `--verbose` increases observable detail only; never changes behavior.
- **No self-mutation by default**: `verify_models`, `selfrun`/`self-audit` must be safe without `WRITE=1` / `--apply`.

---

## Error Taxonomy

```ruby
Result.err("message", category: :security)   # injection, capability violation
Result.err("message", category: :policy)     # axiom/mode violation
Result.err("message", category: :input)      # malformed or oversized input
Result.err("message", category: :tool)       # tool dispatch failure
Result.err("message", category: :llm)        # model call failure
```

Errors carry `request_id` (set by `Logging.with_request_id`). Tool errors also carry `evidence_hash`.

---

## Capability Levels

| Level | Name | Requires | Example |
|-------|------|----------|---------|
| 0 | `read_only` | — | inspect, explain |
| 1 | `propose` | — (default) | generate patches, plans |
| 2 | `write` | `--apply` | write files, update configs |
| 3 | `execute` | `--exec` | run shell commands, tests |
| 4 | `deploy` | `--apply --exec DEPLOY=1` | network ops, restarts |

**Escalation is explicit. Never implicit.**

---

## Tool Contract

Every tool call must produce a `ToolResult`. The LLM only sees `ToolResult#to_prompt` (facts summary). Raw output is stored in `ToolResult#raw` for audit — never injected into model context.

---

## Code Style

- `# frozen_string_literal: true` on every file.
- Require order: stdlib → gems → relative (each group sorted).
- Keyword args for all public methods.
- No positional args beyond 2 params.
- `Result.ok` / `Result.err` for all expected failures; raise only for programmer bugs.
- No one-line (minified) Ruby. Every method on its own line.

---

## Testing

- Unit tests: `ModeDetector`, `OutputGuard`, `PolicyEnforcer`, `ToolResult` — fast, deterministic, no LLM.
- Golden tests: ops transcript inputs must never produce narrative output.
- Property tests: no file writes without `Capabilities.level >= 2`.

---

## Directory Conventions

```
lib/          core modules
lib/policy/   governance: Rule, Enforcer
lib/executor/ execution engine + tools
lib/security/ injection guard, permissions, sanitizer
lib/ui/       terminal output only
data/         YAML sources of truth (axioms, council, models, routes)
var/          runtime state (sessions, cache, db) — not committed
test/         unit + golden tests
deploy/       OpenBSD deployment scripts
```

---

## Logging

Use `Logging.dmesg_log(tag, message:)` for structured audit events.

`tag` naming: `tag0` suffix indicates severity level 0 (info). Examples: `pipeline`, `injection0`, `format0`.

Do not use `puts` for operational output. Use `UI.dim`, `UI.info`, `UI.warn`.
