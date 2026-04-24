# frozen_string_literal: true

# Patch A: Rewrite master.md to match actual code
# Patch B: Rewrite CLAUDE.md with real project instructions  
# Patch C: Delete snapshot.md

BASE = "/home/dev/pub4/MASTER"

# --- A: master.md ---
master_md = <<~'MD'
# MASTER

Constitutional governance for an autonomous coding agent. Ruby. OpenBSD. zsh. Ultraminimalist.

## Kernel / Philosophy split

Every rule in this document is tagged:

- `[K]` Kernel — enforced by code. Violation blocks or warns at runtime.
- `[P]` Philosophy — advisory. Guides humans, does not block the agent.

If a rule cannot map to a scan rule, pipeline stage, or tool guard, it is `[P]`.
The machine only enforces `[K]`.

---

## 0. Golden Rule `[K]`

```
PRESERVE_THEN_IMPROVE_NEVER_BREAK
```

Never break working code. Read before writing. Understand before changing.
Enforced by: Undo stack snapshot before every write. Scan after every change.

---

## 1. Protection Levels `[K]`

| Level | Runtime behavior |
|---|---|
| ABSOLUTE | Halts execution |
| PROTECTED | Logs violation, continues |
| NEGOTIABLE | Context-dependent |

---

## 2. Axioms `[K]`

Eight core axioms. Every other rule derives from these.

| ID | Statement | Enforced by |
|---|---|---|
| PRESERVE_FIRST | Never break working code. Read before write. | Undo snapshot + post-write scan |
| SIMPLEST_WORKS | Fewest moving parts that solve the problem. | Council Skeptic + scan: god_class |
| FAIL_VISIBLY | Errors surface immediately. Never swallow exceptions. | scan: bare_rescue |
| ONE_SOURCE | One authoritative representation per concept. | scan: duplicate_code |
| DECOUPLE | Hidden dependencies become explicit. | Council Architect |
| GUARD_EXPENSIVE | Check preconditions before costly work. | CircuitBreaker + scan: guard_expensive |
| DEGRADE_GRACEFULLY | Works offline. Works with partial failures. | tool timeout wrappers |
| BE_CONCISE | No unnecessary words, tokens, or lines. | Prune stage |

Everything else (structural axioms, process axioms, aesthetic axioms) is `[P]`.

---

## 3. Anti-Simulation `[K]`

All LLM output about completed actions:

- Past tense for completed actions.
- Evidence required: read → show content. write → show diff. complete → show output.
- Unverified claims prefixed `Hypothesis:`.
- Future tense ("will", "would", "could") forbidden for describing already-taken actions.

Enforced by: Prune stage pattern scan on output before display.

---

## 4. Tool Permission Tiers `[K]`

| Tier | Approval | Tools |
|---|---|---|
| `:safe` | Auto | read_file, list_dir, search_files |
| `:guarded` | Prompt (approve / approve-all / deny / quit) | write_file, str_replace, apply_diff, web_search, ask_llm |
| `:dangerous` | Always prompt | zsh |

Governor checks tier before every tool call. EventBus fires `tool:before`.

---

## 5. Path Jail `[K]`

All file operations resolve against project root.
Paths escaping the root → `Result.err(category: :validation)` immediately.
No exceptions, no overrides.

---

## 6. Command Blocklist `[K]`

Blocked patterns (zsh tool):
`rm -rf /`, `sudo`, `reboot`, `shutdown`, `mkfs`, `dd if=`, `> /dev/`, `chmod 777`, `curl | sh`, `wget | sh`

Configurable via `governance.yml`.

---

## 7. Circuit Breaker `[K]`

Three gates before every LLM call:

1. Rate limit: 60 requests/minute sliding window → `Result.err(category: :infrastructure)`
2. Budget: session_total + estimate > budget_max → `Result.err(category: :budget)`
3. Circuit state: 8 failures → open for 30s → `Result.err(category: :infrastructure)`

Per-model breakers via CircuitBreakerRegistry. Global rate limiting shared.

---

## 8. Injection Guard `[K]`

Scans all tool results before feeding back to LLM.
Blocks: system prompt overrides, role reassignment, instruction injection.
Enforced by: Guard stage, 10 regex patterns + shell injection regex.

---

## 9. Pipeline `[K]`

```
Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
```

10 stages. Each returns `Result`. `Err` at any stage short-circuits the rest.
Stages compose via `Result#and_then`. Council and Lint run in parallel via
`ParallelGroup` (30s timeout). Rollback on validation/axiom_violation errors
via `git reset --hard`.

### Stage details

| Stage | Purpose |
|---|---|
| Intake | Classify input: command dispatch vs LLM chat |
| Infer | NL pattern matching from `data/infer_patterns.yml` |
| Route | Select model via ModelRouter weighted scoring |
| Guard | InjectionGuard + tool permission checks |
| Execute | Run agent.chat or tool calls |
| Council | Multi-persona deliberation (when triggered) |
| Lint | RuboCop + Reek + scan rules |
| Prune | Strunk & White prose cleanup, fence-aware |
| Memo | Save user messages to Memory (user-role only) |
| Render | Pastel-colored dmesg-style output |

### Council gate `[K]`

Council runs **only when**:
- Tool tier is `:dangerous`, OR
- Output contains a multi-file diff (2+ file paths in the output), OR
- Explicitly requested via `/council on`

Security persona has VETO power (prefix `VETO:`).

### Ideate gate `[K]`

When intent is classified as `:ideate`:
- Minimum 5 alternatives before evaluation.
- Maximum 7 for architectural decisions, 3 for tactical/reversible ones.
- No alternative is evaluated before all are generated (anti-anchoring).

---

## 10. Result Monad `[K]`

`Result.ok(value)` / `Result.err(message, category:)`

Categories: `:infrastructure`, `:validation`, `:timeout`, `:budget`, `:axiom_violation`, `:unknown`

`retriable?` → true for `:infrastructure`, `:timeout`
`permanent?` → true for `:validation`, `:axiom_violation`, `:budget`

All stages and tools return Result. No exceptions escape the pipeline.

---

## 11. Scan Rules `[K]`

18 rules. Depth levels and what triggers them:

| Depth | Rules | LLM |
|---|---|---|
| `:quick` | frozen_string, bare_rescue | No |
| `:standard` | + long_method, duplicate_code, god_class, srp, cqs, immutable, explicit, self_explaining, prune | No |
| `:hunt` | + multi-phase bug analysis | Yes |
| `:deep` | All + axiom constitutional check + adversarial red-team + conceptual | Yes |

Auto-scan runs at `:quick` after every write. `:standard` on `/scan`.

---

## 12. Undo `[K]`

Every write_file and str_replace snapshots original content before mutation.
`/undo` reverts the last file change (not just conversation).
Git tag checkpoint before multi-file operations: `evolve_checkpoint_{timestamp}`.

---

## 13. Session & Budget `[K]`

- Messages: append-only.
- Cost: per-request and cumulative, appended to `.master/costs.jsonl`.
- Budget warnings at 80% of limit.
- Context compaction at 80% of model context window (CTX_WINDOW_SIZE=200K tokens).

---

## 14. Runtime Metrics `[K]`

Three metrics tracked per session, written to `.master/metrics.jsonl`:

| Metric | What it measures | Alert threshold |
|---|---|---|
| `decision_latency_ms` | Time from prompt to first action | > 5000ms average |
| `diff_size_lines` | Lines changed per task | > 200 lines/task average |
| `rollback_rate` | Undo calls / write calls | > 0.15 |

If any metric crosses its threshold, the agent logs `metrics0: governance overhead detected`.

---

## 15. Architecture `[K]`

```
Kernel     (~1200 LOC)   Result, Pipeline, EventBus, CircuitBreaker,
                          CircuitBreakerRegistry, SemanticCache, Session,
                          Undo, Governor, Agent, Config, ModelRouter
Analyzer   (~2500 LOC)   18 scan rules, Council (12 personas), Deliberation,
                          InjectionGuard, AutoLoop, Swarm, CognitiveMonitor,
                          CodeIndex, Memory, Soul
Operator   (~1500 LOC)   CLI, Renderer, REPL commands, Personality (10 personas),
                          TTS, Web UI (Rails 8 + Falcon)
```

The Kernel has zero dependencies on Analyzer or Operator.
The Analyzer depends only on Kernel interfaces.
The Operator depends on both.

---

## 16. Communication Style `[K]`

```
format: "subsystem0: terse factual message"
```

No headers, no bullet lists, no markdown in REPL output.
Connected prose or single-line dmesg statements only.
Evidence over narration.

Prune stage enforces this by stripping preambles and hedges from LLM output.

---

## 17. Language Rules (Ruby) `[K/P]`

```
frozen_string_literal: true on every file  [K] scan: frozen_string
no bare rescue                              [K] scan: bare_rescue
methods <= 20 lines                         [K] scan: long_method
classes <= 300 lines                        [K] scan: god_class
no duplicate blocks (>= 4 lines, >= 2 uses) [K] scan: duplicate_code
guard clauses over nesting                 [P]
keyword args for 3+ params                 [P]
pattern matching for complex conditionals  [P]
```

---

## 18. Zsh Rules `[K]`

```
shebang: #!/usr/bin/env zsh              [K] enforced by zsh tool wrapper
options: set -euo pipefail               [K] injected by zsh tool wrapper
setopt nullglob extendedglob             [K] injected by zsh tool wrapper
ZDOTDIR=/tmp                             [K] injected by zsh tool wrapper
```

---

## 19. Council Personas `[K]`

12 personas loaded from `data/council.yml`. Security has VETO power.

Default 6 (Data.define):

| Persona | Bias | Veto power |
|---|---|---|
| Architect | Structure | No |
| Skeptic | Caution | No |
| Pragmatist | Shipping | No |
| Security | Safety | Yes (prefix `VETO:`) |
| User | Usability | No |
| Mentor | Clarity | No |

Plus 6 extended personas from YAML: Ethicist, Performance, Accessibility,
Minimalist, Historian, Devil's Advocate.

Council cost-gated: only runs on `:dangerous` tier or multi-file diffs (section 9).

---

## 20. OpenBSD Platform `[K]`

```
privilege: doas (never sudo)
services:  rcctl (never systemctl)
packages:  pkg_add (never apt)
pledge:    applied after init via Fiddle FFI
unveil:    applied after init, locked
```

Platform detection is compile-time. Non-OpenBSD platforms use no-op stubs.

---

## 21. Philosophy `[P]`

The following are advisory. They guide human contributors and inform the agent's
defaults but do not block execution.

**Books**: Clean Code (Martin), Refactoring (Fowler), Polished Ruby Programming (Evans),
The Pragmatic Programmer (Hunt & Thomas), Release It! (Nygard),
The Elements of Style (Strunk & White), The Elements of Typographic Style (Bringhurst).

25 prioritized philosophy axioms in `data/axioms.yml`.
Nielsen usability heuristics, clean code smells, refactoring patterns.

---

## 22. Self-Adherence `[K]`

This document passes its own filter.
Sections 0-20 contain only `[K]` rules.
Section 21 contains only `[P]` rules.
Every `[K]` rule maps to a scan rule, pipeline stage, or tool guard.
Every `[P]` rule is clearly labeled advisory.

---

## 23. Model Routing `[K]`

Weighted scoring (quality 0.50, speed 0.25, cost 0.25) across 3 tiers:

| Tier | Primary | Use |
|---|---|---|
| default | nemotron-super → qwen3-coder → gpt-oss → gemini-flash | General coding |
| strong | claude-sonnet → gpt-4o → nemotron-super → gemini-flash | Architecture |
| cheap | llama-70b → qwen3-coder → gpt-oss → gemini-flash | Exploration |

Confidence-based escalation: uncertainty phrases in output trigger promotion
to strong tier. Escalation happens at most once per chat call.

Tool capability checked via `TOOL_CAPABLE_RE` regex whitelist in agent.rb.
MD

File.write("#{BASE}/master.md", master_md)
puts "master.md: rewritten (#{master_md.lines.count} lines)"

# --- B: CLAUDE.md ---
claude_md = <<~'MD'
# MASTER — Claude Code Project Instructions

## Build & Run

```sh
cd /home/dev/pub4/MASTER
bundle install
bundle exec ruby exe/master          # CLI REPL (TTY mode)
echo "hello" | bundle exec ruby exe/master  # pipe mode
```

## Web UI

```sh
cd web && bundle exec falcon serve -b http://127.0.0.1:10002
# Or via rc.d:
doas rcctl restart master
```

## Test

```sh
bundle exec ruby -Ilib:test test/test_web_http.rb   # HTTP smoke tests (5 tests)
bundle exec ruby -Ilib:test test/test_browser.rb     # Browser tests (needs Chrome + 250MB free RAM)
```

## Lint

```sh
bundle exec rubocop lib/
bundle exec reek lib/
```

## Architecture

- 10-stage pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
- Result monad: `Result.ok(value)` / `Result.err(msg, category:)` — all stages return Result
- Entry point: `exe/master` → `Master.boot` (lib/master.rb)
- Config: `.master/config.yml`, data files in `data/*.yml`
- Web UI: Rails 8 app in `web/`, Falcon on port 10002

## Key Conventions

- `frozen_string_literal: true` on every .rb file
- No bare rescue — always specify exception class
- Methods <= 20 lines, classes <= 300 lines
- Result monad everywhere — check with `respond_to?(:ok?)`, not `is_a?`
- OpenBSD: `doas` not `sudo`, `rcctl` not `systemctl`, `pkg_add` not `apt`
- Zeitwerk autoloading — inflectors: `"cli" => "CLI"`, `"mcp_server" => "MCPServer"`

## SSH Access

```sh
sshpass -p 'PASSWORD' ssh -o StrictHostKeyChecking=no dev@brgen.no
```
MD

File.write("#{BASE}/CLAUDE.md", claude_md)
puts "CLAUDE.md: rewritten (#{claude_md.lines.count} lines)"

# --- C: Delete snapshot.md ---
snap = "#{BASE}/snapshot.md"
if File.exist?(snap)
  size = File.size(snap)
  File.delete(snap)
  puts "snapshot.md: deleted (#{size} bytes freed)"
else
  puts "snapshot.md: already gone"
end
