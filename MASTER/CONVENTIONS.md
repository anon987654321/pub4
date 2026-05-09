# MASTER — Conventions for External LLMs

Context injection for any LLM reviewing or editing MASTER. Read before touching code.

## Identity

MASTER is a constitutional AI coding agent written in Ruby 3.3+ on OpenBSD 7.8. It replaces Claude Code CLI for its operator. It is general-purpose and language-agnostic. Every change leaves the system in a working, deployable state.

## Golden rule

`PRESERVE_THEN_IMPROVE_NEVER_BREAK`. Read before write. Patch minimally. Understand before touching — Chesterton's Fence.

## Anti-simulation

Never state intent without evidence. Forbidden hedges — `will`, `would`, `could`, `might`. Require:
- File read → content with SHA-256
- Modification → unified diff
- Completion → command output

## Communication — two registers, do not mix

- **MASTER's own log/event lines** (boot banner, scheduler ticks, tool events, dmesg-style status): structured, terse, lowercase, kernel-ish — `master@host ready`, `boot0: 26ms`, `model0 at openrouter`. The OpenBSD-dmesg boot banner is sacred — never strip it.
- **Conversational replies to the operator**: plain English, proper casing, full sentences. No dmesg style here. No headlines, no empty bullets, no filler, no sycophancy, no hedging. Outcome first, evidence next, implementation last.
- **Commits and log lines** stay active, concrete, terse — Strunk & White, omit needless words.

## No ASCII line art

Never use these as decorations in any output (comments, log lines, CLI text, chat replies, commit messages):

- `===`, `----` (banner lines, section dividers)
- `•`, `|`, `›`, `‹` (bullet/separator characters)
- `[ok]`, `[err]`, `[skip]` brackets — use bare prefixes `ok:`, `err:`, `skip:`, `warn:` instead

In Markdown documents, plain `---` for an `<hr>` and table separators are fine — they carry meaning. Banner art does not.

## Code rules (enforced by scan)

- **Read before write** — every affected file before any edit.
- **No bare rescue** — always `rescue SpecificError => e`. Inline `expr rescue nil` is fine when nil is intentional.
- **Named constants** — extract literals with `.freeze`.
- **No magic numbers** — thresholds belong in `data/rules.yml` under `thresholds:`.
- **No abbreviations** — `index` not `idx`, `signature` not `sig`, `temporary_path` not `tmp`.
- **No regex when string methods suffice** — `start_with?`, `include?`, `end_with?`.
- **Outsource to gems** — if it exists and works, use it.
- **Endless methods** — single-expression methods use `def foo = expr`.
- **Result monad** — check with `respond_to?(:ok?)`, not `is_a?(Result)`. Unwrap with `.value!` only after `.ok?` is true; on an `Err` it raises.
- **No flag arguments** — a boolean that selects behavior is two methods in one.
- **Guard clauses first** — `return Result.ok(ctx) unless condition` before main logic.
- **Dependency injection** — never instantiate collaborators inside a method.
- **CQS** — queries return, commands mutate. Not both.

## Thresholds

- File — 300 lines max, warn at 200
- Method — 10 lines ideal, 7 warn
- Class — 6 public methods, 3 ivars, 200 lines
- Params — 3 positional max; keyword args for 3+
- Nesting — 2 levels max inside a method

## Ruby style

- `# frozen_string_literal: true` on every `.rb`
- Double-quoted strings always; single only inside regex or `'\1'` backrefs
- One-line comments. No YARD blocks, no section separators
- Comments explain WHY, never WHAT
- `snake_case` throughout
- Zeitwerk autoloading — file name matches class name

Bugs to avoid:
- `Dir.chdir` — process-wide, thread-unsafe. Use `File.expand_path`.
- `Prism.parse(src, freeze: true)` — `freeze:` dropped in 3.4. Use `Prism.parse(src)`.
- `next if` inside `flat_map` — returns `nil`. Use `next [] if`.
- Backtick shell with interpolation — use `Open3.capture2e(*%w[cmd], arg)`.

## Zsh / shell

Banned in zsh and SSH: `sed`, `awk`, `tr`, `grep`, `cut`, `head`, `tail`, `find`, `wc`, `sudo`, `perl`, `ruby`, `dd`, `xargs`. Use zsh builtins, parameter expansion, `doas` for privilege, Ruby scripts for complex logic.

Read files over SSH with `cat path` — read the whole file once. Do not stitch `grep` + `head` fragments; reasoning from full context beats reasoning from snippets. For local zsh array work use `lines=("${(@f)$(<file)}")`.

## Architecture

Pipeline: `Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render`. Council and Lint run concurrently under a 30s deadline via `ParallelGroup`. Rollback on `axiom_violation` or `validation`: `git reset --hard HEAD`. Scan rules auto-register via the `Rule.inherited` callback — every file under `scan/rules/` must subclass `Rule` or it goes silently unrun. Rules with no constructor args set `def auto_build? = true` to opt into the registry's zero-arg construction path. `axiom_coverage_rule` walks `scan/rules/*.rb` with a Prism `SuperclassFinder` and flags any file whose top-level class does not inherit from `Rule`, so silent registry drift is caught at scan time. All rules ship with `@auto_fix = true` and participate in sweep. Sweep runs rubocop autocorrect first, then escalates to LLM rewrite under the corruption guards.

Council deliberation samples a focus question per persona per turn from `data/council_questions.yml` (8 categories — assumptions, failure_modes, attacker, edge_cases, degradation, ops_maint, economics, clarity). Architect → assumptions, Skeptic → failure_modes, Security → attacker, User → edge_cases, Pragmatist → economics, Mentor → clarity. Unmapped personas pass through with no question.

Observability: `Master::Telemetry` is a soft-optional OpenTelemetry tracer that emits JSONL spans to `.master/traces.log`. Wraps `EventBus#publish`, `Metrics#append`, `AuditLog#append`, and `Heartbeat#execute_job`. Bootstrap fires in `Master.boot` between Pledge stage1 and stage2.

Key files — `data/soul.yml` (golden rule, tiers, persona), `data/rules.yml` (structural rules, thresholds, depths), `data/ruby_style.yml` (style and bugs), `data/workflow.yml` (READ_BEFORE_WRITE, scan principles), `data/standing_orders.yml` (current FSM state).

## Running scans

Standard: `eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan lib/" | bundle exec ruby exe/master`. Autofix sweep: `/autoloop 20`. Do not use external agents when MASTER can scan itself. Depth knobs are gone — every scan is full by default.

## Protection tiers

ABSOLUTE aborts the pipeline. PROTECTED emits a warning and continues. NEGOTIABLE allows if explicitly permitted. FLEXIBLE negotiates at runtime. ABSOLUTE sections in `data/soul.yml` require `/override` to amend.

## Environment

VPS: `dev@brgen.no` · OpenBSD 7.8 · passwordless `doas`. SSH credentials live in the operator's environment, never in versioned docs. Non-interactive SSH must not source `.zshrc` — load env only: `eval "$(grep '^export' ~/.zshrc)"`.

Edit VPS files by direct edit + `scp` — write the new file content locally, scp it up. Reserve `~/pub4/tmp/patch.rb` for genuinely script-shaped edits where a patch script is the right tool. Never use `ruby -i` with heredoc — empties the file on script error.

After every scp under `MASTER/web/`, immediately `doas rcctl restart master` so Falcon picks up the change. Falcon does not hot-reload in production; without the restart the deployed app keeps serving the prior bytecode.

## Web auth tiers

`?token=...` matches the value in `~/pub4/.master/config.yml` and grants full tool access. No token = visitor — chat works, but `Thread.current[:master_visitor]` is set so `Master::Agent::LlmDispatch#build_llm_tools` filters tools to the visitor allow-list (currently `AskLlm`, `WebSearch`). The CLI REPL bypasses this entirely and always has full access.

## Slash commands

`/scan [profile] [path]`, `/sweep`, `/autoloop [N]`, `/triad [path]`, `/council on|off`, `/swarm <role> <task>`, `/explain`, `/crit <file|text>`, `/ideate <prompt>`, `/topic`, `/rsi [stats]`, `/model [list|<id>]`, `/why <law|scan_rule|anti_pattern|style.key>`, `/diag [drives|breaker|rules|ring]`, `/snapshot`, `/tts`, `/profile`, `/heartbeat`, `/orders`, `/soul`, `/dmesg`. `/triad` runs scan + sweep + council deliberation in one pass. `/snapshot` publishes two GitHub gists — one for MASTER, one for DEPLOY — full tree + file bodies. `/why` resolves locally first via `WhyExplainer`; the LLM answer fires only on a miss. `/diag` composes a state digest (drives, circuit-breaker, registered rule count, dmesg ring tail).
