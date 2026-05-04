# MASTER — Conventions for External LLMs

This file is a context injection document. If you are an LLM reviewing or editing MASTER, read this before touching any code.

---

## Identity

MASTER is a constitutional AI coding agent written in Ruby 3.3+ on OpenBSD 7.8.
It replaces Claude Code CLI for its operator. It is general-purpose and language-agnostic.
Every change it makes to code must leave the system in a working, deployable state.

---

## Golden Rule

`PRESERVE_THEN_IMPROVE_NEVER_BREAK`

Read before write. Patch minimally. If it works, understand it before touching it (Chesterton's Fence).

---

## Anti-Simulation

Never state intentions without evidence. Forbidden hedges: `will`, `would`, `could`, `might`.
Require evidence:
- File read → show content with SHA-256
- Modification → show unified diff
- Completion → show command output

---

## Communication Style: openbsd_dmesg

Structured multi-line output. No headlines. No bullet lists without content.
No filler phrases. No sycophancy. No hedging.
Lead with the outcome. Key evidence next. Implementation detail last.
Commits and log lines: active voice, concrete verbs, omit needless words.

---

## Code Rules (enforced at runtime by scan pipeline)

**Read before write.** Read every file that could be affected before editing any file.

**No bare rescue.** Always `rescue SpecificError => e`. Never `rescue Exception`. Never bare `rescue`.
Exception: inline `expr rescue nil` is the correct idiom when nil return is intentional.

**Named constants.** Extract numeric and string literals to named constants with `.freeze`.

**No magic numbers.** Every threshold belongs in `data/rules.yml` under `thresholds:`.

**No abbreviated identifiers.** Spell out: `index` not `idx`, `signature` not `sig`, `temporary_path` not `tmp`.

**No regex when string methods suffice.** Use `start_with?`, `include?`, `end_with?`, array matching over patterns.

**Outsource to gems.** If a gem exists that solves the problem correctly, use it. Do not reimplement.

**Endless methods.** Single-expression methods use endless form: `def foo = expr`.

**Result monad.** Check with `respond_to?(:ok?)` not `is_a?(Result)`.

**No flag arguments.** A boolean that selects behavior means two methods hiding as one.

**Guard clauses first.** `return Result.ok(ctx) unless condition` before main logic.

**Dependency injection.** Never instantiate collaborators inside a method.

**CQS.** Queries return data and do not mutate. Commands mutate and do not return values.

---

## File Thresholds

| Scope  | Limit |
|--------|-------|
| File   | 300 lines max, warn at 200 |
| Method | 10 lines ideal, 7 warn |
| Class  | 6 public methods, 3 instance vars, 200 lines |
| Params | max 3 positional; use keyword args for 3+ |
| Nesting | max 2 levels inside a method |

---

## Ruby Style

- `# frozen_string_literal: true` on every `.rb` file
- Double-quoted strings always; single only inside regex or `'\1'` backrefs
- One-line comments only; never YARD doc blocks or section separators
- Comments explain WHY, never WHAT
- `snake_case` naming throughout
- Zeitwerk autoloading — file name must match class name

**Bugs to avoid:**
- `Dir.chdir` — process-wide, thread-unsafe; use `File.expand_path` instead
- `Prism.parse(src, freeze: true)` — `freeze:` dropped in Ruby 3.4; use `Prism.parse(src)`
- `next if` inside `flat_map` — returns `nil`; use `next [] if`
- Backtick shell commands with interpolation — use `Open3.capture2e(*%w[cmd], arg)`

---

## Zsh / Shell

**Banned in zsh scripts and SSH commands:** `sed`, `awk`, `tr`, `grep`, `cut`, `head`, `tail`, `find`, `wc`, `sudo`, `perl`, `ruby`, `dd`, `xargs`

Use: zsh builtins, parameter expansion, `doas` for privilege, Ruby scripts for complex logic.

Read files: `print -r -- "$(<file)"` — not `cat`, not bare `< file` via SSH (triggers pager).

---

## Architecture

Pipeline: `Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render`

- Council + Lint run concurrently (30s timeout) via `ParallelGroup`
- Rollback on `axiom_violation` or `validation` error: `git reset --hard HEAD`
- Scan registry: rules auto-register via `Rule.inherited`; zero-arg rules via `auto_build?`
- All rules have `@auto_fix = true` by default — they participate in sweep/autoloop

Key files:
- `data/soul.yml` — golden rule, protection tiers, persona
- `data/rules.yml` — all structural rules, thresholds, scan depths
- `data/ruby_style.yml` — Ruby/zsh style, bugs to avoid
- `data/workflow.yml` — READ_BEFORE_WRITE, scan principles
- `data/standing_orders.yml` — current FSM state (check before acting)

---

## Running Scans

```zsh
# Standard scan of lib/
eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan lib/" | bundle exec ruby exe/master

# Deep scan
echo "/scan deep lib/" | bundle exec ruby exe/master

# Autofix sweep (20 cycles max)
echo "/autoloop 20" | bundle exec ruby exe/master
```

Do not use external agents to find code issues when MASTER can scan itself.

---

## Protection Tiers

| Tier       | Action                        |
|------------|-------------------------------|
| ABSOLUTE   | Abort pipeline                |
| PROTECTED  | Emit warning, continue        |
| NEGOTIABLE | Allow if explicitly permitted |
| FLEXIBLE   | Negotiate at runtime          |

`data/soul.yml` ABSOLUTE sections require `/override` to amend.

---

## Environment

- VPS: `dev@brgen.no` · `185.52.176.18` · OpenBSD 7.8 · passwordless `doas`
- SSH: `sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@185.52.176.18 'cmd'`
- Non-interactive SSH must not source `.zshrc` — load env only: `eval "$(grep '^export' ~/.zshrc)"`
- Edit VPS files: write patch to `/tmp/patch.rb`, run with `ruby /tmp/patch.rb`
- Never use `ruby -i` with heredoc — will empty file on script error
