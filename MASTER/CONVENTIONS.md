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

## Communication: openbsd_dmesg

Structured multi-line output. No headlines, no empty bullets, no filler, no sycophancy, no hedging. Outcome first, evidence next, implementation last. Commits and log lines stay active, concrete, terse.

## Code rules (enforced by scan)

- **Read before write** — every affected file before any edit.
- **No bare rescue** — always `rescue SpecificError => e`. Inline `expr rescue nil` is fine when nil is intentional.
- **Named constants** — extract literals with `.freeze`.
- **No magic numbers** — thresholds belong in `data/rules.yml` under `thresholds:`.
- **No abbreviations** — `index` not `idx`, `signature` not `sig`, `temporary_path` not `tmp`.
- **No regex when string methods suffice** — `start_with?`, `include?`, `end_with?`.
- **Outsource to gems** — if it exists and works, use it.
- **Endless methods** — single-expression methods use `def foo = expr`.
- **Result monad** — check with `respond_to?(:ok?)`, not `is_a?(Result)`.
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

Read files: `print -r -- "$(<file)"`. Not `cat`. Not bare `< file` via SSH — triggers pager.

## Architecture

Pipeline: `Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render`. Council and Lint run concurrently under a 30s deadline via `ParallelGroup`. Rollback on `axiom_violation` or `validation`: `git reset --hard HEAD`. Scan rules auto-register via `Rule.inherited`; zero-arg rules through `auto_build?`. All rules ship with `@auto_fix = true` and participate in sweep. Sweep runs rubocop autocorrect first, then escalates to LLM rewrite under the corruption guards.

Key files — `data/soul.yml` (golden rule, tiers, persona), `data/rules.yml` (structural rules, thresholds, depths), `data/ruby_style.yml` (style and bugs), `data/workflow.yml` (READ_BEFORE_WRITE, scan principles), `data/standing_orders.yml` (current FSM state).

## Running scans

Standard: `eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan lib/" | bundle exec ruby exe/master`. Deep: `/scan deep lib/`. Autofix sweep: `/autoloop 20`. Do not use external agents when MASTER can scan itself.

## Protection tiers

ABSOLUTE aborts the pipeline. PROTECTED emits a warning and continues. NEGOTIABLE allows if explicitly permitted. FLEXIBLE negotiates at runtime. ABSOLUTE sections in `data/soul.yml` require `/override` to amend.

## Environment

VPS: `dev@brgen.no` · `185.52.176.18` · OpenBSD 7.8 · passwordless `doas`. SSH: `sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@185.52.176.18 'cmd'`. Non-interactive SSH must not source `.zshrc` — load env only: `eval "$(grep '^export' ~/.zshrc)"`. Edit VPS files: write patch to `/tmp/patch.rb`, run `ruby /tmp/patch.rb`. Never use `ruby -i` with heredoc — empties the file on script error.
