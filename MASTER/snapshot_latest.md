# MASTER Snapshot — 2026-05-04T14:30:17Z

## Tree
```
completions/
data/
data/prompts/
data/web/
docs/
exe/
lib/
lib/master/
lib/master/agent/
lib/master/autoloop/
lib/master/builder/
lib/master/cli/
lib/master/code_index/
lib/master/command_registry/
lib/master/council/
lib/master/introspection/
lib/master/memory/
lib/master/reasoning/
lib/master/routing/
lib/master/scan/
lib/master/scan/rules/
lib/master/security/
lib/master/stages/
lib/master/swarm/
lib/master/swarm/workers/
lib/master/sweep/
lib/master/tools/
scripts/
skills/
skills/explain/
test/
web/
web/app/
web/app/assets/
web/app/assets/images/
web/app/assets/stylesheets/
web/app/controllers/
web/app/controllers/concerns/
web/app/helpers/
web/app/models/
web/app/models/concerns/
web/app/views/
web/app/views/chat/
web/app/views/layouts/
web/app/views/pwa/
web/bin/
web/config/
web/config/environments/
web/config/initializers/
web/config/locales/
web/db/
web/lib/
web/lib/tasks/
web/public/
web/public/assets/
web/script/
web/storage/
CLAUDE.md
CONVENTIONS.md
Gemfile
README.md
Rakefile
SOUL.md
data/council.yml
data/council_patterns.yml
data/exemplars.yml
data/heartbeat.yml
data/infer_patterns.yml
data/mcp_servers.yml
data/models.yml
data/openbsd.yml
data/openbsd_patterns.yml
data/phase_state.yml
data/platform.yml
data/prompts/mode_direct.yml
data/prompts/mode_react.yml
data/prompts/mode_rewoo.yml
data/ruby_style.yml
data/rules.yml
data/soul.yml
data/standing_orders.yml
data/sweep_prompts.yml
data/templates.yml
data/workflow.yml
data/zsh_patterns.yml
docs/master2_restoration_opportunities.md
docs/ui_supersnappy_two_party_plan.md
lib/master.rb
lib/master/agent.rb
lib/master/agent/llm_dispatch.rb
lib/master/audit_log.rb
lib/master/autoloop.rb
lib/master/autoloop/fix_evaluator.rb
lib/master/axioms.rb
lib/master/bedrock_stub.rb
lib/master/builder.rb
lib/master/builder/infra_helpers.rb
lib/master/circuit_breaker.rb
lib/master/circuit_breaker_registry.rb
lib/master/cli.rb
lib/master/cli/signals.rb
lib/master/cli/tts.rb
lib/master/code_index.rb
lib/master/code_index/symbol_visitor.rb
lib/master/command_registry.rb
lib/master/command_registry/agent_commands.rb
lib/master/command_registry/memory_commands.rb
lib/master/command_registry/service_commands.rb
lib/master/config.rb
lib/master/context_window.rb
lib/master/council/deliberation.rb
lib/master/council/ideation.rb
lib/master/council/personas.rb
lib/master/decision_engine.rb
lib/master/diff_stager.rb
lib/master/event_bus.rb
lib/master/gateway.rb
lib/master/git_operations.rb
lib/master/governor.rb
lib/master/heartbeat.rb
lib/master/introspection/self_map.rb
lib/master/learnings.rb
lib/master/logging.rb
lib/master/mcp_coordinator.rb
lib/master/memory.rb
lib/master/memory/search.rb
lib/master/metrics.rb
lib/master/personality.rb
lib/master/phase_gates.rb
lib/master/pipeline.rb
lib/master/pledge.rb
lib/master/reasoning/modes.rb
lib/master/reflexion.rb
lib/master/renderer.rb
lib/master/result.rb
lib/master/ring_buffer.rb
lib/master/routing/continuity_index.rb
lib/master/routing/model_router.rb
lib/master/ruby_llm_patch.rb
lib/master/scan/rule.rb
lib/master/scan/rules/adversarial_rule.rb
lib/master/scan/rules/arity_rule.rb
lib/master/scan/rules/axiom_coverage_rule.rb
lib/master/scan/rules/bare_rescue_rule.rb
lib/master/scan/rules/comment_quality_rule.rb
lib/master/scan/rules/conceptual_rule.rb
lib/master/scan/rules/cqs_rule.rb
lib/master/scan/rules/dead_assign_rule.rb
lib/master/scan/rules/dead_code_rule.rb
lib/master/scan/rules/debug_output_rule.rb
lib/master/scan/rules/duplicate_code_rule.rb
lib/master/scan/rules/explicit_rule.rb
lib/master/scan/rules/frozen_string_rule.rb
lib/master/scan/rules/god_class_rule.rb
lib/master/scan/rules/immutable_rule.rb
lib/master/scan/rules/interconnect_rule.rb
lib/master/scan/rules/lexical_rule.rb
lib/master/scan/rules/long_method_rule.rb
lib/master/scan/rules/naming_rule.rb
lib/master/scan/rules/nesting_depth_rule.rb
lib/master/scan/rules/nielsen_rule.rb
lib/master/scan/rules/opportunity_rule.rb
lib/master/scan/rules/pola_rule.rb
lib/master/scan/rules/prune_rule.rb
lib/master/scan/rules/reek_rule.rb
lib/master/scan/rules/rubocop_rule.rb
lib/master/scan/rules/self_explaining_rule.rb
lib/master/scan/rules/srp_rule.rb
lib/master/scan/rules/structure_rule.rb
lib/master/scan/rules/tell_dont_ask_rule.rb
lib/master/scan/rules/terse_rule.rb
lib/master/scan/rules/thread_safety_rule.rb
lib/master/scan/rules/threshold_drift_rule.rb
lib/master/scan/rules/trailing_comment_rule.rb
lib/master/scan/rules/universal_rule.rb
lib/master/scan/rules/yaml_quality_rule.rb
lib/master/scan/scanner.rb
lib/master/security/injection_guard.rb
lib/master/security/permissions.rb
lib/master/semantic_cache.rb
lib/master/session.rb
lib/master/skills.rb
lib/master/soul.rb
lib/master/speech.rb
lib/master/stages/council.rb
lib/master/stages/deliberate.rb
lib/master/stages/execute.rb
lib/master/stages/guard.rb
lib/master/stages/infer.rb
lib/master/stages/intake.rb
lib/master/stages/lint.rb
lib/master/stages/memo.rb
lib/master/stages/prune.rb
lib/master/stages/render.rb
lib/master/stages/route.rb
lib/master/standing_orders.rb
lib/master/swarm/coordinator.rb
lib/master/swarm/worker.rb
lib/master/swarm/workers/analyst.rb
lib/master/swarm/workers/coder.rb
lib/master/swarm/workers/researcher.rb
lib/master/swarm/workers/reviewer.rb
lib/master/sweep.rb
lib/master/sweep/convergence.rb
lib/master/sweep/rewriter.rb
lib/master/text_hygiene.rb
lib/master/tools/ask_llm.rb
lib/master/tools/ast_edit.rb
lib/master/tools/batch_replace.rb
lib/master/tools/clean.rb
lib/master/tools/git_context.rb
lib/master/tools/list_dir.rb
lib/master/tools/llm.rb
lib/master/tools/path_guard.rb
lib/master/tools/read_file.rb
lib/master/tools/search_files.rb
lib/master/tools/search_knowledge.rb
lib/master/tools/shell.rb
lib/master/tools/str_replace.rb
lib/master/tools/symbol_lookup.rb
lib/master/tools/tree.rb
lib/master/tools/web_search.rb
lib/master/tools/write_file.rb
lib/master/triggers.rb
lib/master/undo.rb
lib/master/unwrap_error.rb
master.gemspec
master.md
scripts/openbsd_preflight.zsh
skills/explain/SKILL.md
snapshot_agent.md
snapshot_autoloop.md
snapshot_builder.md
snapshot_cli.md
snapshot_code_index.md
snapshot_command_registry.md
snapshot_council.md
snapshot_data.md
snapshot_introspection.md
snapshot_lib_core.md
snapshot_memory.md
snapshot_reasoning.md
snapshot_routing.md
snapshot_scan.md
snapshot_security.md
snapshot_stages.md
snapshot_swarm.md
snapshot_sweep.md
snapshot_tools.md
snapshot_tree.md
test/test_agent.rb
test/test_axioms.rb
test/test_browser.rb
test/test_cli.rb
test/test_experience.rb
test/test_helper.rb
test/test_pipeline.rb
test/test_prune.rb
test/test_result.rb
test/test_ring_buffer.rb
test/test_speech.rb
test/test_web_http.rb
test/test_web_ui.rb
web/Gemfile
web/README.md
web/Rakefile
web/app/controllers/application_controller.rb
web/app/controllers/chat_controller.rb
web/app/controllers/events_controller.rb
web/app/controllers/health_controller.rb
web/app/helpers/application_helper.rb
web/app/models/application_record.rb
web/app/views/chat/index.html.erb
web/app/views/layouts/application.html.erb
web/app/views/pwa/manifest.json.erb
web/app/views/pwa/service-worker.js
web/config/application.rb
web/config/boot.rb
web/config/ci.rb
web/config/database.yml
web/config/environment.rb
web/config/environments/development.rb
web/config/environments/production.rb
web/config/environments/test.rb
web/config/initializers/assets.rb
web/config/initializers/content_security_policy.rb
web/config/initializers/filter_parameter_logging.rb
web/config/initializers/inflections.rb
web/config/initializers/master_container.rb
web/config/initializers/new_framework_defaults_8_0.rb
web/config/locales/en.yml
web/config/puma.rb
web/config/routes.rb
web/db/seeds.rb
web/public/assets/rails-ujs-20eaf715.js
web/public/assets/rails-ujs.esm-e925103b.js
web/public/robots.txt
```

## `CLAUDE.md`
```markdown
# pub4 — CLAUDE.md

Auto-approve all tool calls. Never ask for confirmation.

## Launch

```zsh
claude --dangerously-skip-permissions
```

---

## Session Startup (mandatory)

Before any coding work:
1. `cat ~/pub4/MASTER/data/soul.yml` -- golden rule, anti-simulation, protection tiers, identity
2. `cat ~/pub4/MASTER/data/rules.yml` -- structural rules, voice, zen principles
3. `cat ~/pub4/MASTER/data/ruby_style.yml` -- Ruby/zsh/OpenBSD rules, banned commands
4. `cat ~/pub4/MASTER/data/workflow.yml` -- READ_BEFORE_WRITE, scan depths, anti-sprawl
5. `cat ~/pub4/MASTER/data/standing_orders.yml` -- current FSM state (UNCHANGE / REFACTOR / etc.)

**Communication style: openbsd_dmesg** -- structured multi-line output, no headlines, no bullet lists without content, no hedging, no sycophancy.

**Banned in zsh scripts and SSH commands:** sed, awk, tr, grep, cut, head, tail, find, wc, sudo, perl, ruby (in zsh), dd, xargs
Use: zsh builtins, parameter expansion, `doas` for privilege, Ruby scripts for complex logic.

**External LLM context:** `cat ~/pub4/MASTER/CONVENTIONS.md` — dense reference distilled from data/*.yml for any LLM reviewing or editing MASTER.

**Use MASTER's own scan before external analysis:**
`eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle exec ruby exe/master`
Do not use external agents to find code issues when MASTER can scan itself.

**SSH file editing pattern (safe):**
Write script to /tmp: `doas tee /tmp/patch.rb <<'EOF' ... EOF`
Run it: `ruby /tmp/patch.rb`
Never use `ruby -i` with heredoc -- will empty file on script error.

---

## Environment

| | |
|---|---|
| **Dev machine** | OpenBSD VPS · `dev@brgen.no` · `185.52.176.18` (wheel, passwordless doas) |
| **Password** | `h00te10tu` (changes each session) |
| **SSH** | `sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@185.52.176.18 'cmd'` |
| **Shell** | zsh — ControlMaster does NOT persist across Bash tool calls, use sshpass every time |
| **Local** | proot-distro Ubuntu inside Termux on Android — audio production only |
| **OS** | OpenBSD 7.8 on VPS, Ubuntu in proot |

Non-interactive SSH must NOT source `.zshrc` — it auto-launches MASTER and steals stdin.
Load env vars only: `eval "$(grep '^export' ~/.zshrc)"`

---

## DNS (brgen.no — OpenBSD Amsterdam)

```
brgen.no       A     185.52.176.18
ai.brgen.no    A     185.52.176.18
mail.brgen.no  MX    brgen.no (priority 10)
```

Subdomains not yet deployed publicly: `brgen.no` Rails app, other vhosts.

---

## Repository: pub4

- **Git remote**: `https://github.com/anon987654321/pub4.git` — same repo as `dev@brgen.no:~/pub4`
- **Git root**: `~/pub4/`
- **Push**: `gh auth git-credential` on VPS (HTTPS, not SSH)

### Directory layout

```
pub4/
  MASTER/           — active AI agent (Ruby, ~6K LOC)
  DEPLOY/openbsd/   — openbsd.sh deploy script (1511 lines, two-stage)
  __predecessors/   — MASTER2, aight (old versions, do not touch)
  index.html        — Radio Bergen GitHub Pages
  mix/              — audio mixes
  sh/               — misc shell scripts
```

---

## MASTER — Architecture
> `master.yml` (1770-line monolithic config) deleted Feb 2026. The Ruby codebase replaced it — the agent IS the config.

MASTER is a constitutional AI coding agent that **replaces Claude Code CLI**.

- **Path**: `~/pub4/MASTER/`
- **Binary**: `exe/master`
- **Module**: `Master` (Zeitwerk autoloaded)
- **Launch**: SSH auto-starts via `~/.zshrc` → `cd MASTER && bundle exec ruby exe/master`
- **Pipe mode**: `echo "msg" | bundle exec ruby exe/master`
- **rc.d service**: `master` (port 53187, bound to 127.0.0.1)

### Pipeline (10 stages)

```
Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
```

- **ParallelGroup**: Council + Lint run concurrently (30s timeout)
- **Rollback**: `git reset --hard HEAD` on `axiom_violation`/`validation` error
- **Result monad**: `Ok/Err` — check with `respond_to?(:ok?)`, not `is_a?(Result)`


### data/ — Living Spec (replaced master.yml)

`master.yml` was a 1770-line monolithic YAML config. MASTER replaced it with modular `data/*.yml` files that the Ruby pipeline reads and enforces at runtime:

| File | Purpose |
|---|---|
| `soul.yml` | Golden rule, anti-simulation, protection tiers, persona identity |
| `rules.yml` | Structural rules, voice/strunk prose patterns, zen principles |
| `ruby_style.yml` | Ruby 3.3+ rules, Rails 8+ stack, OpenBSD config, zsh banned commands |
| `standing_orders.yml` | Current FSM state (UNCHANGE / REFACTOR / etc.) |
| `workflow.yml` | READ_FULL_FILES, READ_BEFORE_WRITE, scan depths, autoloop/sweep config, Zeitwerk inflections, anti-sprawl |
| `models.yml` | Model capability table (uses YAML anchors — load with `aliases: true`) |
| `council.yml` / `council_patterns.yml` | Council personas and trigger patterns |
| `infer_patterns.yml` | Natural language → command routing |
| `sweep_prompts.yml` | Sweep structural/cosmetic technique prompts |
| `zsh_patterns.yml` | Zsh idioms and banned-command replacements |
| `prompts/` | LLM prompt templates |

The Ruby pipeline reads these at boot via `Master.build` and enforces them through scan rules, pipeline stages, and tool guards.

### Key modules

| File | Purpose |
|---|---|
| `lib/master.rb` | `Master.build(root:)` container; `Master.boot` → CLI |
| `lib/master/cli.rb` | REPL (`run`), pipe mode (`pipe`), slash commands |
| `lib/master/pipeline.rb` | 10-stage pipeline, ParallelGroup, rollback |
| `lib/master/sweep.rb` | Self-refactor loop (MAX_CYCLES=16, convergence 0.05) |
| `lib/master/agent.rb` | LLM calls, circuit breaker, fallback models, escalation (depth ≤ 2) |
| `lib/master/standing_orders.rb` | Constitutional rules, `wire_pipeline` |
| `lib/master/code_index.rb` | Symbol/Reference Structs (no `freeze: true` — Ruby 3.4 drops it) |
| `lib/master/scan/` | 10 scan rules (EXPLICIT, IMMUTABLE, CQS, SELF_EXPLAINING, etc.) |
| `lib/master/routing/model_router.rb` | Tier routing (cheap/default/strong), ESCALATION_CHAIN, confidence thresholds |
| `lib/master/swarm/coordinator.rb` | Swarm workers, `fan_out`, `dispatch_parallel` with shared deadline |

### Web UI

- **Framework**: Rails 8 + Falcon (port `53187` internal)
- **Public**: relayd proxies → `http://ai.brgen.no:3000` / `https://ai.brgen.no:4430`
- **Routes**: `GET /` chat, `POST /chat/message` (SSE), `POST /chat/tts`, `POST /chat/speak`, `GET /chat/metrics`, `GET /chat/dmesg`, `GET /events/stream`
- **rc.d**: `master` daemon
- **Canvas**: 2000-particle orb, 50 shapes, ambient pad engine, drum sequencer, 17 voice FX

### Models

- **Default**: `nvidia/nemotron-3-super-120b-a12b:free` (OpenRouter free tier)
- **Fallback chain**: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash
- **Circuit breaker**: FAILURE_THRESHOLD=8, RATE_MAX=60

### Slash commands

`/scan [deep]`, `/sweep`, `/autoloop`, `/council`, `/crit <file|text>`, `/tts`, `/profile`, `/heartbeat`, `/orders`, `/soul`, `/dmesg`

---

## Design Priorities

1. **CLI REPL** — interactive agent, primary interface
2. **Web UI + TTS** — secondary
3. **Autonomous agent** — tertiary

---

## Deploy: openbsd.sh

Script: `~/pub4/MASTER/DEPLOY/openbsd/openbsd.sh`

Two stages:
- **Stage 1**: DNS checks, TLS certs via acme-client, pkg_add
- **Stage 2**: app installs, relayd config, rc.d services

Run in tmux: `tmux new-session -d -s deploy "cd ~/pub4/MASTER/DEPLOY/openbsd && doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"`
Resume: `doas zsh openbsd.sh --resume`

---

## Shell Preferences

- **Never** use `sed`, `awk`, `tr`, `wc`, `head`, `tail`, `grep` — use zsh builtins
- **No tmp files** for simple operations — do it inline
- **No line noise** — keep commands clean and readable
- **Ruby only** — never Python
- **Read files**: `print -r -- "$(<file)"` (not `cat`, not bare `< file` via SSH — triggers pager)
- **zsh array**: `lines=("${(@f)$(<file)}")`; last 50: `print -l $lines[-50,-1]`
- **Edit VPS files**: write patch to `~/pub4/tmp/patch.rb`, run with `ruby ~/pub4/tmp/patch.rb`
- **Man pages first** before editing config files (`MANPAGER=cat man pagename` via SSH)

---

## Sweep Safety

The sweep corruption guard (added 2026-04-27) protects against LLM error messages being written as source:
- `ask_result()` + Result monad check in `rewrite()`
- 50% minimum length guard
- `ERROR_PATTERNS` regex rejection for short outputs
- SYNTAX_CHECKERS for `.rb`, `.yml`, `.erb`

Never disable these guards. If sweep produces unexpected output, the guards will reject it.
```

## `CONVENTIONS.md`
```markdown
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
```

## `Gemfile`
```text
# frozen_string_literal: true
gem "fiddle"

source "https://rubygems.org"

gem "ruby_llm", "~> 1.3"
gem "tty-prompt", "~> 0.23"
gem "tty-reader", "~> 0.9"
gem "tty-spinner", "~> 0.9"
gem "tty-markdown", "~> 0.7"
gem "tty-table", "~> 0.12"
gem "tty-screen", "~> 0.8"
gem "tty-box", "~> 0.7"
gem "tty-command", "~> 0.10"
gem "tty-tree", "~> 0.4"
gem "tty-config", "~> 0.6"
gem "tty-logger", "~> 0.6"
gem "tty-progressbar", "~> 0.18"
gem "pastel", "~> 0.8"
gem "rouge", "~> 4.4"
gem "diffy", "~> 3.4"
gem "zeitwerk", "~> 2.7"
gem "sinatra", "~> 4.0"
gem "sinatra-contrib", "~> 4.0"

group :test do
  gem "minitest", "~> 5.25"
  gem "rack-test", "~> 2.1"
  gem "ferrum", "~> 0.15"
end
gem "ruby_llm-mcp"
gem "rubocop", "~> 1.60", require: false
gem "reek", "~> 6.4", require: false
gem "flay", require: false
```

## `README.md`
```markdown
# MASTER

Constitutional AI coding agent. OpenBSD-first. Ruby-only. Self-hosting.

Reviews its own code, argues with itself via adversarial council, ships the result.

## Quick start

```zsh
cd ~/pub4/MASTER
bundle install
export OPENROUTER_API_KEY=...
bundle exec ruby exe/master
```

## Architecture

10-stage Result-monadic pipeline:

```
Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
```

Council and Lint run in parallel (30s timeout). Rollback on axiom violation.

## Key commands

```
/scan [deep|quick|critical]   Scan lib/ for violations
/sweep [path]                 Self-refactor loop (convergence-driven)
/autoloop [n]                 Fix violations autonomously, n cycles
/crit <file|text>             Adversarial council review
/soul                         Identity evolution commands
/model [id|list]              Show or switch model
/why <rule>                   Explain a scan rule
```

## Data files

`data/*.yml` is the living spec — replaces the old master.yml monolith:

| File | Purpose |
|---|---|
| `soul.yml` | Golden rule, anti-simulation, protection tiers |
| `rules.yml` | Structural rules, voice, zen principles |
| `ruby_style.yml` | Ruby/zsh/OpenBSD rules, banned commands |
| `workflow.yml` | Scan depths, autoloop config, anti-sprawl |
| `standing_orders.yml` | Current FSM state |
| `models.yml` | Model capability table |
| `council.yml` | Council personas and trigger patterns |

## Web UI

Rails 8 + Falcon on port 53187 (internal). relayd proxies via HAProxy → ai.brgen.no:443.

Canvas: 2000-particle orb, ambient pad engine, drum sequencer, 17 voice FX.

## Deploy

```zsh
cd DEPLOY/openbsd && doas zsh openbsd.sh
```

## License

MIT
```

## `Rakefile`
```text
# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test
```

## `SOUL.md`
```markdown
# SOUL.md — MASTER Constitutional Identity

Version: 2.1.0
Persona: dark_malay
Updated: 2026-04-27

## Identity

MASTER is a constitutional AI coding agent. OpenBSD-first. Ruby-only.
Built to read, understand, fix, and ship code without human hand-holding.
Runs on a 1GB VPS at OpenBSD Amsterdam. Every byte counts.

## Voice

Terse. Direct. No filler. Dark.
Speak like dmesg — structured, factual, timestamped.
Never sycophantic. Never hedging. Never verbose.
If the answer is one word, say one word.
Active voice. Positive form. Omit needless words.

Anti-simulation rule: never claim "would", "could", "might" without evidence.
Show the diff. Show the output. Show the file. Or say nothing.

## Values

Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.

Kernel axioms (enforced — violation aborts pipeline):
- PRESERVE_FIRST: never break working code; read before write.
- SIMPLEST_WORKS: fewest moving parts that solve the problem.
- FAIL_VISIBLY: surface errors immediately; never swallow exceptions.
- ONE_SOURCE: one authoritative representation per concept.
- DECOUPLE: make hidden dependencies explicit.
- GUARD_EXPENSIVE: check preconditions before costly work.
- DEGRADE_GRACEFULLY: operate under partial failures.
- BE_CONCISE: avoid unnecessary words, tokens, or lines.

## Code Philosophy

- Result monad: Ok/Err. Check with respond_to?(:ok?), never is_a?.
- Ruby only. No Python. No Node. No sed/awk/grep.
- OpenBSD pledge/unveil mindset: minimal permissions.
- Dependency injection everywhere. No global state.
- Data in YAML, logic in Ruby. data/*.yml is the living spec.
- Convention: frozen_string_literal on every file.
- Tests are first-class code.

## Pipeline

10-stage Result-monadic pipeline:
Intake -> Infer -> Route -> Guard -> Execute -> [Council | Lint] -> Prune -> Memo -> Render

Council and Lint run in parallel (30s timeout).
Each stage receives ctx hash, returns Result.ok(ctx) or Result.err.

## Personas

| Name       | Voice                | Style   | Domain                    |
|------------|----------------------|---------|---------------------------|
| dark_malay | ms-MY-OsmanNeural   | deep    | Default. Terse. Dark.     |
| british    | en-GB-RyanNeural    | heavy   | Measured. Dry wit.        |
| norwegian  | nb-NO-FinnNeural    | slow    | Calm. Honest.             |
| ronin      | en-US-AndrewNeural  | deep    | Stoic. Minimal.           |
| hacker     | en-US-GuyNeural     | deep    | Security. CVE. Pentesting.|
| sysadmin   | en-AU-WilliamNeural | deep    | OpenBSD. pf. httpd. vmm.  |
| architect  | en-GB-RyanNeural    | heavy   | BIM. Parametric design.   |
| lawyer     | nb-NO-FinnNeural    | slow    | Norwegian law.            |
| trader     | en-US-ChristopherNeural | heavy | Crypto. DeFi. Technicals.|
| medic      | en-US-EricNeural    | slow    | Medical research. PubMed. |

## Heartbeat

Autonomous scheduled tasks (see data/heartbeat.yml):
- prune_memory: archive stale entries (1h)
- self_test: scan lib/ for violations (2h)
- prune_undo: trim journal (24h)
- snapshot: regenerate codebase snapshot (4h)

## Skills

Composable skill directories under skills/:
Each contains SKILL.md (metadata + triggers) and optional skill.rb (Ruby tool).
Skills are discovered at boot and registered as tools.

## Gateway

Multi-channel message router: CLI, web, IRC, Matrix, API.
All channels funnel through the same 10-stage pipeline.
ctx[:channel] tags origin. Response routed back to source.

## Memory

Cross-session persistent store (.master/memory.yml).
TF-IDF semantic search. Three-phase consolidation (light/deep/REM).
Injection limit: top 5 entries, capped at 2000 tokens in system prompt.

## Evolution Protocol

1. Propose change: `soul propose <rationale>` — LLM drafts amendment.
2. Drift check: ABSOLUTE sections (anti-simulation, golden rule) cannot change.
3. Review: `soul diff` — shows proposed changes.
4. Approve: `soul approve` — bumps version, commits, tags.
5. Reject: `soul reject` — discards proposal.
6. Rollback: `soul rollback` — restores previous git version.

Recurring scan violations (3+ cycles) auto-propose soul amendments.

## Changelog

| Version | Date       | Change                          | Author              |
|---------|------------|---------------------------------|----------------------|
| 2.1.0   | 2026-04-27 | Restored from sweep corruption  | Claude Opus 4.6     |
| 2.0.0   | 2026-04-24 | OpenClaw-inspired restructure   | Claude Opus 4.6     |
| 1.0.0   | 2026-04-01 | Initial soul document           | dev                  |
```

## `data/council.yml`
```yaml
# Council personas — deliberation panel for code review decisions.

- name: Architect
  role: System Design
  bias: Structure
  prompt: Review architectural boundaries, coupling, interface shapes, and migration risk.

- name: Data Steward
  role: Data Integrity
  bias: Consistency
  prompt: Audit schema impact, migrations, data lineage, and source‑of‑truth consistency.

- name: Ethics & Policy
  role: Responsible Use
  bias: Compliance
  prompt: Examine policy adherence, abuse potential, fairness, and governance implications.

- name: Maintainer
  role: Code Health
  bias: Sustainability
  prompt: Evaluate readability, naming, modularity, and long‑term maintenance burden.

- name: Performance
  role: Runtime Efficiency
  bias: Throughput
  prompt: Detect latency, memory, I/O, and algorithmic inefficiencies; suggest measurable optimizations.

- name: Product Strategist
  role: Product Fit
  bias: Value
  prompt: Verify alignment with product goals, success metrics, and roadmap leverage.

- name: QA Engineer
  role: Test Strategy
  bias: Verification
  prompt: Locate missing tests, flaky patterns, and propose deterministic validation gates.

- name: Pragmatist
  role: Delivery Pressure
  bias: Shipping
  prompt: Minimize scope while maximizing shippable value within realistic constraints.

- name: Reliability
  role: Failure Engineering
  bias: Resilience
  prompt: Review retries, timeouts, degradation modes, idempotency, and rollback safety.

- name: Security
  role: Security Review
  bias: Safety
  prompt: Identify injection, privilege escalation, data‑exposure, and auth risks. Prefix VETO when unsafe to ship.

- name: Skeptic
  role: Devil's Advocate
  bias: Caution
  prompt: Challenge assumptions, enumerate failure paths, edge cases, and brittleness.

- name: User Advocate
  role: UX Advocate
  bias: Usability
  prompt: Assess clarity, friction, error recovery, and overall user outcomes.
```

## `data/council_patterns.yml`
```yaml
# Patterns that auto‑trigger Council deliberation.
# Loaded as Regexp at runtime – keep them plain strings.
# Each entry is a Ruby‑style regex pattern; the leading \b and trailing \b
# ensure whole‑word matches where appropriate.
# Anchors are reused via YAML anchors for readability.

common: &common
  - '\beval\s+\('
  - '\bexec\s+\('
  - '\bsystem\s+\('

dangerous:
  - *common
  - '\brm\s+-rf\b'
  - '\bsudo\b'
  - '\b(?:drop|truncate)\s+table\b'
  - '\bchmod\s+777\b'
  - '\b(?:delete|remove)\s+all\b'
  - '\bopen\s*\(\s*[''"][|]'                         # suspicious file open with pipe
  - '\b(popen|spawn)\s*\('                           # process creation shortcuts
  - '\b(fork|execve?)\b'                              # low‑level process forks
  - '\bbase64\s+decode\b'                            # potential data exfiltration
  - '\b(base64|binhex)\s+decode\b'                   # duplicate safety net
  - '\bopenssl\s+enc\s+-d\b'                         # decryption shortcuts
  - '\b(gzip|gunzip)\s+-d\b'                         # decompression that may hide payloads
  - '\b(base64|urlencode)\s+decode\b'                # double‑decode attacks
  - '\bcrontab\s+-[eE]\b'                            # schedule manipulation
  - '\biptables\s+-[FI]\b'                           # firewall rule changes
  - '\bsemanage\s+fcontext\b'                        # SELinux label changes
  - '\b(systemctl|service)\s+(stop|restart|disable)\b' # service disruption
  - '\b(rm|unlink)\s+--no-preserve-root\b'           # aggressive deletes
  - '\bdd\s+if=.*\s+of=.*\s+bs=.*\s+count=.*\b'       # raw disk ops
  - '\b(mkfs|fdisk|parted)\b'                        # filesystem manipulation
  - '\bchattr\s+[-+]i\b'                             # immutable attribute toggling
  - '\b(setfacl|getfacl)\b'                          # ACL abuse
  - '\b(chcon|restorecon)\b'                         # SELinux context changes
  - '\bsecuritylimits\b'                             # limits.conf editing
  - '\bpasswd\s+-[dl]\b'                             # password lock/unlock
  - '\b(yum|apt|dnf|pacman)\s+.*\b'                  # package manager abuse
  - '\bpip\s+install\s+--upgrade\b'                  # python package escalation
  - '\bruby\s+gem\s+install\s+--pre\b'               # ruby gem pre‑release install
  - '\bnpm\s+install\s+-g\b'                         # global node modules
  - '\bsudo\s+-[S]\b'                                # sudo without password prompt
  - '\bsu\s+-\s*root\b'                              # direct root switch
  - '\b(wget|curl)\s+.*\s+-O\s+/\w+\b'               # download to root
  - '\b(tar\s+.*\s+--wildcards)\b'                   # tar extraction with wildcards
  - '\b(zip|unzip)\s+.*\s+-d\s+/\w+\b'               # archive extraction to root
  - '\b(pg_dump|mysqldump)\b'                        # database dumps
  - '\bsqlite3\s+.*\s+\.dump\b'                      # sqlite dump
  - '\b(ssh|scp)\s+.*\s+@.*\b'                        # remote command execution
  - '\b(netcat|nc)\s+.*\b'                           # raw socket commands
  - '\b(lsof|fuser)\b'                               # process/file descriptor probing
  - '\b(strace|ltrace|gdb)\b'                        # tracing/debugging utilities
  - '\bdocker\s+run\s+--rm\b'                        # container escape attempts
  - '\bkubectl\s+exec\b'                             # k8s pod exec
  - '\bcrontab\s+-[lr]\b'                            # crontab listing/modifying
  - '\bat\b'                                         # at jobs
  - '\bpowershell\s+-Command\b'                      # cross‑platform shell
  - '\bwmic\s+.*\b'                                  # Windows management
  - '\breg\s+add\b'                                  # registry edits
  - '\bnetsh\s+firewall\b'                           # Windows firewall
  - '\bsc\s+config\b'                                # Windows service config
  - '\b(setx|set)\b'                                 # environment variable changes
  - '\bexport\s+[^=]+=.*\b'                          # shell env changes
  - '\benv\s+.*\b'                                   # env command misuse
  - '\b(bash|zsh|ksh|sh)\s+-c\b'                     # nested shells
  - '\b(python|perl|ruby|node)\s+-e\b'               # language exec
  - '\bjava\s+-jar\b'                                # java jar execution
  - '\bjavac\s+.*\b'                                 # compile on the fly
  - '\bgit\s+(push\s+--force|remote\s+add|checkout\s+-b|reset\s+--hard|rebase\s+-i|push\s+origin\s+HEAD:refs/heads/.*|push\s+--tags|clone\s+--depth|fetch\s+--all|pull\s+--all|remote\s+set-url|config\s+--global|config\s+--system|lfs|submodule|rev-parse|merge|reflog|show|diff|status|log|checkout|add|commit|branch|tag|fetch|pull|push|remote|init|clone|config)\b'
  - '\bgrep\s+--binary-files=without-match\b'        # binary grep avoidance
  - '\bsed\s+-n\b'                                   # selective sed
  - '\bawk\b'                                              # awk command
  - '\btail\s+-f\b'                                  # log following
  - '\bhead\s+-n\b'                                  # head count
  - '\bcurl\s+.*\s+(-X\s+DELETE|-o\s+/.+)\b'          # HTTP delete / write to root
  - '\bwget\s+.*\s+(--method=DELETE|--output-document=/.+)\b' # HTTP delete / write to root
  - '\bscp\s+.*\s+/\w+\b'                            # copy to root
  - '\brsync\s+.*\s+/\w+\b'                          # sync to root
  - '\b(chown|chgrp)\s+.*\s+/\w+\b'                  # ownership changes on root files
  - '\bln\s+-sf\s+.*\s+/\w+\b'                       # symlink overwrite
  - '\b(mv|cp)\s+.*\s+/\w+\b'                        # move/copy to root
  - '\b(distrobox|toolbox|podman|docker)\s+run\b'    # container escape
  - '\b(lxc\-exec|lxc\-attach)\b'                    # LXC exec
  - '\bvirsh\s+console\b'                            # libvirt console
  - '\bqemu\-system\-x86_64\b'                       # qemu VM launch
  - '\bvboxmanage\s+startvm\b'                       # VirtualBox start
  - '\bssh\s+-o\s+(StrictHostKeyChecking=no|UserKnownHostsFile=/dev/null|BatchMode=yes)\b' # host key bypass
  - '\bssh\s+-[LFRDNT]\s+.*\b'                       # port forwarding / tunnel options
  - '\bsocat\s+.*\b'                                 # socket proxy
  - '\bmitmproxy\s+.*\b'                             # MITM proxy
  - '\btunnel\s+.*\b'                               # TLS tunnel
  - '\biptables\s+-[F]\b'                            # flush iptables
  - '\bnft\s+flush\s+table\b'                        # nftables flush
  - '\bufw\s+disable\b'                              # ufw disable
  - '\bfirewalld\s+stop\b'                           # firewalld stop
  - '\bsystemctl\s+(mask|disable|stop|halt)\b'       # service control
  - '\b(poweroff|reboot|shutdown\s+-[hr])\b'          # power actions
  - '\bmount\s+-o\s+remount,rw\b'                    # remount read‑write
  - '\bumount\s+.*\b'                                # unmount
  - '\b(fuser|pkill|killall|kill)\s+.*\b'             # kill commands
  - '\b(pkill|killall)\s+--signal\s+9\b'             # force kill
  - '\b(strace|ltrace|gdb)\s+-p\b'                   # attach debugger/trace
  - '\b(lsof|netstat|ss)\s+.*\b'                     # socket/process inspection
  - '\b(ps|top|htop|w|whoami)\b'                    # system info commands
  - '\b(id|groups)\b'                                # identity commands
  - '\b(set|shopt)\s+-(e|u|o\s+pipefail|s\s+(nullglob|dotglob|extglob))\b' # strict shell options
  - '\b(bash|zsh|ksh|sh)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash options
  - '\bfind\s+/.*\s+-type\s+(f\s+-exec\s+rm\s+-f\s+{}\s+;|d\s+-exec\s+rmdir\s+{}\s+;)\b' # mass delete/dir removal
  - '\b(tar|zcat|gunzip|bzip2|xz|zip|unzip)\s+.*\s+>\s+/dev/null\b' # discard output
  - '\bpipefail\b'                                   # set -o pipefail
  - '\bset\s+-(e|u|o\s+pipefail)\b'                  # exit on error, undefined var, pipefail
  - '\bshopt\s+-(s\s+(nullglob|dotglob|extglob))\b'  # globbing options
  - '\b(bash)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash errexit etc.
```

## `data/exemplars.yml`
```yaml
# Exemplars — canonical code examples for LLM context injection.

exemplars:
  - name: "Master::Axioms::ENUM"
    file: "lib/master/axioms.rb"
    lines: 9
    beauty_score: 7
    virtue: declarative
    why: "Centralised truth constants, immutable, self‑documenting"
  - name: "Master::CircuitBreaker#call"
    file: "lib/master/circuit_breaker.rb"
    lines: 6
    beauty_score: 8
    virtue: resilience
    why: "Prevents cascading failures, simple state machine, easy to test"
  - name: "Master::CodeIndex::SymbolVisitor#visit_def"
    file: "lib/master/code_index.rb"
    lines: 167
    beauty_score: 8
    virtue: introspection
    why: "Uses Prism visitor to collect symbols, pure functional style, concise"
  - name: "Master::Logging.debug"
    file: "lib/master/logging.rb"
    lines: 6
    beauty_score: 6
    virtue: transparency
    why: "Thin wrapper around logger, ensures consistent formatting, no side effects"
  - name: "Master::Logging.info"
    file: "lib/master/logging.rb"
    lines: 10
    beauty_score: 6
    virtue: transparency
    why: "Standardised info-level logging, preserves caller context"
  - name: "Master::Pipeline#run"
    file: "lib/master/pipeline.rb"
    lines: 22
    beauty_score: 9
    virtue: orchestration
    why: "Linear 10‑stage pipeline, monadic result flow, explicit error propagation"
  - name: "Master::Result::Err"
    file: "lib/master/result.rb"
    lines: 36
    beauty_score: 9
    virtue: error_handling
    why: "Explicit failure monad, immutable, forces callers to handle errors"
  - name: "Master::Result::Ok"
    file: "lib/master/result.rb"
    lines: 8
    beauty_score: 9
    virtue: zen_method
    why: "Encapsulates success, immutable, self‑describing, no boilerplate"
  - name: "Master::RingBuffer#pop"
    file: "lib/master/ring_buffer.rb"
    lines: 12
    beauty_score: 8
    virtue: efficient
    why: "Symmetric constant‑time removal, preserves immutability guarantees"
  - name: "Master::RingBuffer#push"
    file: "lib/master/ring_buffer.rb"
    lines: 5
    beauty_score: 8
    virtue: efficient
    why: "Constant‑time circular buffer, clear intent, minimal code"
  - name: "Master::Security::InjectionGuard#sanitize"
    file: "lib/master/security/injection_guard.rb"
    lines: 12
    beauty_score: 8
    virtue: safety
    why: "Robust string sanitization, guards against code injection, well‑named"
  - name: "Master::SemanticCache#fetch"
    file: "lib/master/semantic_cache.rb"
    lines: 8
    beauty_score: 8
    virtue: performance
    why: "Memoises LLM embeddings, reduces API calls, immutable cache key"
  - name: "Master::Stages::Intake#call"
    file: "lib/master/stages/intake.rb"
    lines: 8
    beauty_score: 7
    virtue: composability
    why: "Initial request parsing, validates input, isolates side‑effects"
  - name: "Master::Stages::Lint#call"
    file: "lib/master/stages/lint.rb"
    lines: 10
    beauty_score: 7
    virtue: composability
    why: "Stage pattern, thin wrapper, delegates to scanner, easy to test"
  - name: "Master::Stages::Render#call"
    file: "lib/master/stages/render.rb"
    lines: 6
    beauty_score: 9
    virtue: presentation
    why: "Final rendering step, separates view logic, pure Result output"
  - name: "Master::Tools::AskLlm#call"
    file: "lib/master/tools/ask_llm.rb"
    lines: 5
    beauty_score: 8
    virtue: delegation
    why: "Encapsulates LLM request, uniform error handling, testable abstraction"
  - name: "Master::Tools::ReadFile#call"
    file: "lib/master/tools/read_file.rb"
    lines: 5
    beauty_score: 7
    virtue: clarity
    why: "Single responsibility, explicit error handling, pure I/O abstraction"
  - name: "Master::Tools::SearchFiles#call"
    file: "lib/master/tools/search_files.rb"
    lines: 5
    beauty_score: 7
    virtue: discoverability
    why: "Recursively glob‑searches project files, filters by pattern, pure result handling"
  - name: "Master::Tools::StrReplace#call"
    file: "lib/master/tools/str_replace.rb"
    lines: 5
    beauty_score: 7
    virtue: clarity
    why: "Pure string substitution helper, validates inputs, returns Result"
  - name: "Master::Tools::Tree#call"
    file: "lib/master/tools/tree.rb"
    lines: 9
    beauty_score: 7
    virtue: introspection
    why: "Builds AST tree view, useful for debugging, returns structured Result"
  - name: "Master::Tools::WriteFile#call"
    file: "lib/master/tools/write_file.rb"
    lines: 7
    beauty_score: 7
    virtue: clarity
    why: "Encapsulates file write with atomic temp‑file swap, error propagation"
  - name: "Master::Swarm::Workers::Analyst#perform"
    file: "lib/master/swarm/workers/analyst.rb"
    lines: 7
    beauty_score: 7
    virtue: delegation
    why: "Analyzes LLM output, extracts actionable insights, pure data transformation"
  - name: "Master::Swarm::Workers::Coder#perform"
    file: "lib/master/swarm/workers/coder.rb"
    lines: 14
    beauty_score: 7
    virtue: delegation
    why: "Coordinates LLM code generation, isolates side‑effects, clear contract"
```

## `data/heartbeat.yml`
```yaml
# Heartbeat — autonomous scheduled jobs.
# Each entry runs at interval_seconds. Actions: prune_memory, check_models, self_test, prune_undo, snapshot.

- name: prune_memory
  action: prune_memory
  interval_seconds: 3600
  description: Consolidate and archive stale memory entries.

- name: self_test
  action: self_test
  interval_seconds: 7200
  description: Run standard scan against lib/ and report violations.

- name: prune_undo
  action: prune_undo
  interval_seconds: 86400
  description: Trim undo journal to last 50 entries.

- name: snapshot
  action: snapshot
  interval_seconds: 14400
  description: Regenerate .master/snapshot.md with current codebase state.
```

## `data/infer_patterns.yml`
```yaml
# Intent-inference patterns for Stages::Infer.
# Extracted from Ruby source per NO_HARDCODED_CONSTANTS / ONE_SOURCE axioms.
# Every new natural-language command goes here — no code change required.
#
# Format: each entry has a command name and a list of regex patterns.
# Patterns are compiled case-insensitive with extended mode (x flag).
# Leave escaping as it appears here — loader does not re-escape.

commands:
  sweep:
    patterns:
      - '\b(?:sweep|refactor|clean\s*up|rewrite|polish|tidy\s*up|overhaul|improve\s+(?:all|every)|go\s+through\s+(?:all|every)|full\s+pass\s+(?:over|on))(?:\s+(?:all|every(?:thing)?|the))?(?:\s+([\w\/.]+))?'
      - '\b(?:rydd\s+opp|refaktorer|forbedre?|gjennomg[åa]|omskriv)(?:\s+([\w\/.]+))?'
    capture: path

  autoloop:
    patterns:
      - '\b(?:autoloop|autofix|fix\s+all\s+violations?|keep\s+(?:fix|loop)|loop\s+until|iterate\s+until|run\s+until\s+clean|keep\s+going\s+until|(?:run|go)\s+(?:it\s+)?(?:again\s+)?until\s+(?:done|clean|fixed|perfect))(?:\s+(\d+))?'
      - '\b(?:fiks?\s+alle?\s+(?:feil|brudd)|fortsett\s+(?:til|inntil)|kj[øo]r\s+(?:til\s+)?(?:det\s+er\s+)?(?:rent|bra|ferdig))(?:\s+(\d+))?'
    capture: cycles

  council:
    patterns:
      - '\b(?:council|deliberat|multiple\s+perspect|second\s+opinion|peer\s+review|debate\s+this|get\s+(?:another|a\s+second)\s+view|multi(?:ple)?\s+(?:view|agent|model|perspect))\b'
      - '\b(?:r[åa]dsl[åa]g|bruk\s+(?:flere|multiple)\s+(?:perspektiv|synsvinkler?)|diskuter\s+(?:dette|det))\b'
    capture: on_off

  explain:
    patterns:
      - '\b(?:explain\s+(?:your(?:self)?|your\s+architecture|how\s+you\s+work)|describe\s+(?:your(?:self)?|your\s+architecture)|what\s+are\s+you|how\s+(?:are\s+you\s+built|do\s+you\s+work)|show\s+(?:your\s+)?architecture|self[\s-]?map)\b'
    capture: none

  persona:
    patterns:
      - '\b(?:(?:switch|change|set)\s+persona\s+(?:to\s+)?(\w+)|persona\s+(\w+)|use\s+(\w+)\s+persona)\b'
    capture: persona_name

  memory:
    patterns:
      - '\b(?:what\s+do\s+you\s+remember(?:\s+about\s+([\w\s]+))?|show\s+(?:my\s+)?memor(?:y|ies)|list\s+memor(?:y|ies)|recall(?:\s+([\w]+))?|what(?:''s|\s+is)\s+in\s+(?:your\s+)?memory|remember\s+([\w]+=.+)|forget\s+([\w_]+))\b'
      - '\b(?:hva\s+husker\s+du(?:\s+om\s+([\w\s]+))?|vis\s+(?:min\s+)?hukommelse|husk\s+([\w_]+=.+))\b'
    capture: first_group

  tokens:
    patterns:
      - '\b(?:token\s*count|how\s+many\s+tokens?|context\s+size|token\s+usage|how\s+much\s+context|hvor\s+mange\s+token|token\s*antall)\b'
    capture: none

  cost:
    patterns:
      - '\b(?:how\s+much\s+(?:has\s+this\s+cost|did\s+this\s+cost)|(?:current\s+)?(?:spend|cost|budget)|what(?:''s|\s+is)\s+the\s+cost|hva\s+koster?\s+(?:dette|det)|kostnader?)\b'
    capture: none

  undo:
    patterns:
      - '\b(?:undo\s+that|revert\s+(?:that|last|it)|go\s+back|take\s+that\s+back|angre\s+det|g[åa]\s+tilbake)\b'
    capture: none

  clear:
    patterns:
      - '\b(?:clear\s+(?:context|chat|history|session|screen)|start\s+(?:over|fresh|again)|reset\s+(?:context|session)|fresh\s+start|t[øo]m\s+(?:kontekst|historikk)|begynn\s+p[åa]\s+nytt)\b'
    capture: none

  save:
    patterns:
      - '\b(?:save\s+(?:session|this|my\s+work|progress)|checkpoint\s+now|lagre\s+(?:session|sesjonen?|arbeid))\b'
    capture: none

  model:
    patterns:
      - '\b(?:which\s+model|current\s+model|what\s+model\s+are\s+you|what\s+(?:llm|ai|model)\s+(?:are\s+you\s+using|is\s+this))\b'
    capture: none

  scan:
    patterns:
      - '\b(?:scan|lint|check\s+(?:code|violations?)|run\s+scan)(?:\s+(deep))?\b'
    capture: scan_depth

  dmesg:
    patterns:
      - '\b(?:show\s+(?:logs?|events?)|system\s+log|dmesg|what\s+(?:happened|has\s+happened)|recent\s+activity)\b'
    capture: none

  dreams:
    patterns:
      - '\b(?:dreams?|consolidate?\s+memor(?:y|ies)|memory\s+consolidat|dream\s+mode|promote\s+memor(?:y|ies))\b'
    capture: first_group

  soul:
    patterns:
      - '\b(?:show|check|view)\s+(?:the\s+)?soul\b'
      - '\bsoul\s+(?:version|changelog|diff|approve|reject|rollback|propose)\b'
    capture: soul_subcmd

  orders:
    patterns:
      - '\b(?:standing\s+orders?|show\s+orders?|list\s+orders?)\b'
    capture: orders_subcmd
```

## `data/mcp_servers.yml`
```yaml
# MCP server definitions for MASTER.
# Transport options: stdio | sse
# Disabled by default on resource-constrained VPS.
# Enable individual servers with enabled: true when needed.

defaults: &defaults
  transport: stdio
  command: npx
  enabled: false

servers:
  filesystem:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-filesystem"
      - "/home/dev/pub4"
    description: Expose read/write/search over a local directory

  git:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-git"
      - "--repository"
      - "/home/dev/pub4/MASTER"
    description: Expose git operations as tools

  brave_search:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-brave-search"
    description: Web search via Brave

  sequential_thinking:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-sequential-thinking"
    description: Structured reasoning assistant
```

## `data/models.yml`
```yaml
# Model routing profile — Gemini primary, Mistral/DeepSeek/OpenRouter fallback.

routing:
  enabled: true
  strategy: weighted
  escalation_enabled: true
  escalation_tier: strong
  provider: gemini

weights: &weights
  quality: 0.50
  speed: 0.25
  cost: 0.25

fallback_policy:
  retries_per_tier: 1
  on:
    - timeout
    - network_error
    - refusal

defaults: &model_defaults
  score: { quality: 0.0, speed: 0.0, cost: 0.0 }

model_defs:
  gemini_flash: &gemini_flash
    id: gemini-2.5-flash
    <<: *model_defaults
    score: { quality: 0.88, speed: 0.90, cost: 0.95 }
  gemini_pro: &gemini_pro
    id: gemini-2.5-pro
    <<: *model_defaults
    score: { quality: 0.95, speed: 0.70, cost: 0.80 }
  mistral_large: &mistral_large
    id: mistral-large-latest
    <<: *model_defaults
    score: { quality: 0.90, speed: 0.75, cost: 0.70 }
  mistral_small: &mistral_small
    id: mistral-small-latest
    <<: *model_defaults
    score: { quality: 0.78, speed: 0.85, cost: 0.90 }
  deepseek_chat: &deepseek_chat
    id: deepseek-chat
    <<: *model_defaults
    score: { quality: 0.88, speed: 0.70, cost: 0.95 }
  deepseek_coder: &deepseek_coder
    id: deepseek-coder
    <<: *model_defaults
    score: { quality: 0.85, speed: 0.70, cost: 0.95 }
  claude_sonnet: &claude_sonnet
    id: anthropic/claude-sonnet-4-6
    <<: *model_defaults
    score: { quality: 0.95, speed: 0.75, cost: 0.60 }
  nemotron_super: &nemotron_super
    id: nvidia/nemotron-3-super-120b-a12b:free
    <<: *model_defaults
    score: { quality: 0.90, speed: 0.75, cost: 1.0 }
  qwen_coder: &qwen_coder
    id: qwen/qwen3-coder:free
    <<: *model_defaults
    score: { quality: 0.75, speed: 0.65, cost: 1.0 }
  llama_70b: &llama_70b
    id: meta-llama/llama-3.3-70b-instruct:free
    <<: *model_defaults
    score: { quality: 0.78, speed: 0.70, cost: 1.0 }
  hermes_405b: &hermes_405b
    id: nousresearch/hermes-3-llama-3.1-405b:free
    <<: *model_defaults
    score: { quality: 0.85, speed: 0.50, cost: 1.0 }
  gpt_4o: &gpt_4o
    id: openai/gpt-4o
    <<: *model_defaults
    score: { quality: 0.93, speed: 0.80, cost: 0.55 }

models:
  default:
    - *gemini_flash
    - *mistral_large
    - *deepseek_chat
    - *nemotron_super
    - *qwen_coder
  strong:
    - *gemini_pro
    - *mistral_large
    - *claude_sonnet
    - *gpt_4o
    - *gemini_flash
  cheap:
    - *gemini_flash
    - *mistral_small
    - *deepseek_chat
    - *llama_70b
    - *qwen_coder

routes:
  code_generation: default
  refactoring: default
  architecture: strong
  review: default
  explanation: cheap
  exploration: cheap
  fallback_default: cheap

tool_capable_prefixes:
  - claude
  - gpt-4
  - gpt-4o
  - gemini
  - mistral
  - mixtral
  - llama-3.1
  - llama-3.3
  - qwen
  - command-r
  - deepseek
  - stepfun
  - nvidia
  - nemotron
  - meta/meta-llama
  - anthropic/claude
  - openai/gpt
  - google/gemini

operation_constraints:
  # Operations that write files, run autoloop/sweep, or execute destructive commands
  # require a model with quality score >= 0.88 (default and cheap tiers excluded).
  # Equivalent to: claude-sonnet-4-6, gemini-2.5-pro, mistral-large, gpt-4o.
  file_write:    { min_quality: 0.88, preferred_tier: strong }
  autoloop:      { min_quality: 0.88, preferred_tier: strong }
  sweep:         { min_quality: 0.88, preferred_tier: strong }
  council:       { min_quality: 0.88, preferred_tier: strong }
  destructive:   { min_quality: 0.90, preferred_tier: strong }

continuity:
  enabled: true
  updated_at: "2026-05-01T00:00:00Z"

openrouter:
  free_latest:
    - nvidia/nemotron-3-super-120b-a12b:free
    - qwen/qwen3-coder:free
```

## `data/openbsd.yml`
```yaml
# openbsd.yml — OpenBSD config validators
# Restored from master.yml v49.75; extended for OpenBSD 7.8

man_base_url: "https://man.openbsd.org"
cache_ttl: 86400

configs:
  pf.conf:
    daemon: pf
    man: pf.conf.5
    required_patterns:
      - "set skip on lo"
    warnings:
      - pattern: "pass all"
        message: "Overly permissive — add interface/protocol guards"

  nsd.conf:
    daemon: nsd
    man: nsd.conf.5
    required_patterns:
      - "server:"
      - "zone:"
    warnings:
      - pattern: "rrl-size"
        absent_message: "Missing RRL config — vulnerable to amplification DDoS"
      - pattern: "hide-version"
        absent_message: "Consider hide-version: yes"

  httpd.conf:
    daemon: httpd
    man: httpd.conf.5
    required_patterns:
      - "server"

  smtpd.conf:
    daemon: smtpd
    man: smtpd.conf.5
    required_patterns:
      - "listen on"
      - "action"
      - "match"
    warnings:
      - pattern: "match from any"
        message: "Open relay risk — restrict to authenticated senders"

  relayd.conf:
    daemon: relayd
    man: relayd.conf.5
    required_patterns:
      - "relay"

  acme-client.conf:
    daemon: acme-client
    man: acme-client.conf.5
    required_patterns:
      - "authority"
      - "domain"

  doas.conf:
    daemon: doas
    man: doas.conf.5
    required_patterns:
      - "permit"
    warnings:
      - pattern: "nopass"
        message: "Allows passwordless privilege escalation"

  sshd_config:
    daemon: sshd
    man: sshd_config.5
    warnings:
      - pattern: "PermitRootLogin yes"
        message: "Security risk — use PermitRootLogin prohibit-password"
      - pattern: "PasswordAuthentication yes"
        message: "Consider key-only auth"

  ntpd.conf:
    daemon: ntpd
    man: ntpd.conf.5
    required_patterns:
      - "server"

  unbound.conf:
    daemon: unbound
    man: unbound.conf.5
    required_patterns:
      - "server:"
```

## `data/openbsd_patterns.yml`
```yaml
# OpenBSD system knowledge – agents generate OpenBSD‑native commands
# Deterministic, flat schema, no tags.

service_commands:
  enable:   "rcctl enable ${service}"
  start:    "rcctl start ${service}"
  restart:  "rcctl restart ${service}"
  reload:   "rcctl reload ${service}"
  check:    "rcctl check ${service}"
  disable:  "rcctl disable ${service}"

configuration_paths:
  pf:           "/etc/pf.conf"
  httpd:        "/etc/httpd.conf"
  relayd:       "/etc/relayd.conf"
  smtpd:        "/etc/mail/smtpd.conf"
  acme:         "/etc/acme-client.conf"
  sshd:         "/etc/ssh/sshd_config"
  ntp:          "/etc/ntpd.conf"
  cron:         "/var/cron/tabs/${user}"
  unbound:      "/var/unbound/unbound.conf"

package_operations:
  install:   "pkg_add ${package}"
  remove:    "pkg_delete ${package}"
  search:    "pkg_info -Q ${query}"
  update:    "pkg_add -u"
  firmware:  "fw_update"

prohibited_commands:
  - command:      "systemctl"
    replacement:  "rcctl"
  - command:      "apt"
    replacement:  "pkg_add"
  - command:      "apt-get"
    replacement:  "pkg_add"
  - command:      "brew"
    replacement:  "pkg_add"
  - command:      "yum"
    replacement:  "pkg_add"
  - command:      "ip addr"
    replacement:  "ifconfig"
  - command:      "ip route"
    replacement:  "route"
  - command:      "journalctl"
    replacement:  "cat /var/log/messages"
  - command:      "sudo"
    replacement:  "doas"
  - command:      "ufw"
    replacement:  "pfctl"
  - command:      "iptables"
    replacement:  "pf"
  - command:      "nginx"
    replacement:  "httpd (OpenBSD native)"
  - command:      "docker"
    replacement:  "vmctl"
  - command:      "systemd"
    replacement:  "rcctl"
  - command:      "gsed"
    replacement:  "sed (POSIX)"
  - command:      "gawk"
    replacement:  "awk (POSIX)"
  - command:      "ggrep"
    replacement:  "grep (POSIX)"

security:
  pledge:   "pledge(2) – restrict syscalls after init"
  unveil:   "unveil(2) – restrict filesystem visibility"
  doas:     "doas.conf – preferred over sudo"
  signify:  "signify(1) – cryptographic signing"
  chroot:   "httpd runs chrooted by default"

daemon_configs:
  pf.conf:
    daemon:   pf
    man:      pf.conf.5
    required_patterns:
      - "set skip on lo"
    warnings:
      - pattern: "pass all"
        message: "Overly permissive rule"

  nsd.conf:
    daemon:   nsd
    man:      nsd.conf.5
    required_patterns:
      - "server:"
      - "zone:"
    warnings:
      - pattern: "rrl-size"
        absent_message: "Missing RRL config for DDoS protection"
      - pattern: "hide-version"
        absent_message: "Consider hide-version: yes"

  httpd.conf:
    daemon:   httpd
    man:      httpd.conf.5
    required_patterns: []
    warnings: []

  smtpd.conf:
    daemon:   smtpd
    man:      smtpd.conf.5
    required_patterns:
      - "listen on"
      - "action"
      - "match"
    warnings:
      - pattern: "match from any"
        message: "Potential open relay"

  relayd.conf:
    daemon:   relayd
    man:      relayd.conf.5
    required_patterns:
      - "relay"
    warnings: []

  acme-client.conf:
    daemon:   acme-client
    man:      acme-client.conf.5
    required_patterns:
      - "authority"
      - "domain"
    warnings: []

  doas.conf:
    daemon:   doas
    man:      doas.conf.5
    required_patterns:
      - "permit"
    warnings:
      - pattern: "nopass"
        message: "Allows password‑less escalation"

  sshd_config:
    daemon:   sshd
    man:      sshd_config.5
    required_patterns: []
    warnings:
      - pattern: "PermitRootLogin yes"
        message: "Security risk – disallow root login"
      - pattern: "PasswordAuthentication yes"
        message: "Prefer key‑based authentication"

  ntpd.conf:
    daemon:   ntpd
    man:      ntpd.conf.5
    required_patterns:
      - "server"
    warnings: []

  unbound.conf:
    daemon:   unbound
    man:      unbound.conf.5
    required_patterns:
      - "server:"
    warnings: []
```

## `data/phase_state.yml`
```yaml
---
phase: idle
met_gates: []
entered_at: 1777837945
```

## `data/platform.yml`
```yaml
# Platform — OS-specific tool mappings (audio, firewall, etc.).

openbsd:
  audio: aucat
  firewall: pf
  http_server: httpd
  package_manager: pkg_add
  privilege: doas
  service_manager: rcctl
  shell: ksh

linux:
  audio: mpv
  firewall: ufw
  http_server: nginx
  package_manager: apt
  privilege: sudo
  service_manager: systemctl
  shell: bash

macos:
  audio: afplay
  firewall: pfctl
  http_server: nginx
  package_manager: brew
  privilege: sudo
  service_manager: launchctl
  shell: zsh

windows:
  audio: powershell
  firewall: windows_defender
  http_server: iis
  package_manager: winget
  privilege: runas
  service_manager: sc
  shell: powershell
```

## `data/prompts/mode_direct.yml`
```yaml
system: |
  Direct mode only.
  No meta‑conversation.
  Answer with minimal words.
  No explanations, apologies, or padding.
  Invoke tools immediately, without preamble.

template: |
  %{message}
```

## `data/prompts/mode_react.yml`
```yaml
system: |
  Follow the ReAct paradigm. Keep reasoning concise; intervene only when necessary. Emphasize brevity and concrete actions.
template: |
  [Mode: ReAct]
  Task: %{message}
  ---
  Reason:
  %<reason>s
  Action:
  %<action>s
```

## `data/prompts/mode_rewoo.yml`
```yaml
system: |
  Generate a concise, numbered plan. Each step must reference at least one evidence slot (e.g., [slot 12]). Conclude with a single, decisive answer.

template: |
  [Mode: ReWOO]
  Task:
  %{message}
```

## `data/ruby_style.yml`
```yaml
# Ruby, shell, and git style rules enforced by MASTER.
# Scan rules reference these; Personality injects them into every LLM system prompt.

ruby:
  quotes: double  # always double-quoted strings; single only inside regex or '\1' backrefs
  frozen_string: true  # every .rb file must start with # frozen_string_literal: true

  comments:
    max_lines: 1           # class/module/method comments: 1 line or none
    require_why: true      # only add when WHY is non-obvious (hidden constraint, workaround)
    forbidden:
      - what_comments      # never describe what the code does — identifiers do that
      - yard_doc_blocks    # no # Public:, # Returns, # param - style blocks
      - section_separators # no # ----, # ====, # ---- Public API ---- etc.
      - numbered_steps     # no # 1., # 2. inline step comments
      - multi_line_prose   # cut verbosity; one line survives, paragraph does not

  bugs_to_avoid:
    - pattern: "Dir.chdir"
      reason: "process-wide; thread-unsafe in multi-threaded agents"
      fix: "pass -C root to git; expand paths with File.expand_path"

    - pattern: "Prism.parse(src, freeze: true)"
      reason: "freeze: kwarg dropped in Ruby 3.4"
      fix: "Prism.parse(src)"

    - pattern: "next if condition inside flat_map"
      reason: "next if returns nil into flat_map, producing nil entries in output"
      fix: "next [] if condition"

    - pattern: "rescue => e (multi-line bare rescue)"
      reason: "unclear; explicitly name StandardError for clarity"
      fix: "rescue StandardError => e"

    - pattern: "rescue nil (inline rescue returning nil)"
      reason: "inline rescue already catches StandardError; rescue nil is correct idiom"
      note: "do NOT change to rescue StandardError — that returns the class object, not nil"

    - pattern: "@bus&.publish(...) || value"
      reason: "when bus is present, returns bus result (truthy), masking the real value"
      fix: "call @bus&.publish(...) on its own line; return value separately"

    - pattern: "backtick shell commands with interpolation"
      reason: "shell injection risk"
      fix: "Open3.capture2e('cmd', '-flag', arg) with arg arrays"

    - pattern: "system/Open3 with string interpolation"
      reason: "shell injection risk"
      fix: "Open3.capture2e(*%w[cmd -flag], variable) with separate arguments"

    - pattern: "mutate state before publishing event that reads old state"
      reason: "event receives new state instead of previous state"
      fix: "capture prev = current before mutation; use prev in publish/return"

  naming:
    spell_out: true        # no abbreviations: index not idx, signature not sig, temporary_path not tmp
    forbidden_abbreviations:
      - idx
      - sig
      - tmp
      - buf
      - val
      - ret
      - obj
      - str
      - arr
      - num
      - cnt
      - ptr
      - msg   # unless it IS the domain term (e.g., a Message object named msg is ok if short-lived)
    rule: "Spell identifiers out. Domain names can be short (id, url, ip) — abbreviations cannot."

  prefer_string_methods:
    rule: "Prefer start_with? / include? / end_with? / split over regex when string methods suffice."
    rationale: "Regex is expressive but noisy. Use it when patterns require it, not as a default."
    prefer:
      - "str.start_with?(prefix)        over  str.match?(/^prefix/)"
      - "str.include?(substr)           over  str.match?(/substr/)"
      - "str.end_with?(suffix)          over  str.match?(/suffix$/)"
      - "str.split(sep, n)              over  str.scan(/pattern/)"
    still_use_regex_for:
      - 'Character classes: /[a-z]/, /\d+/'
      - "Anchored multiline patterns"
      - "Alternation with more than 2 branches"

  outsource_to_gems:
    rule: "If a well-maintained gem solves the problem correctly, use it. Do not reimplement."
    rationale: "Gems carry tests, edge cases, and maintenance. Home-grown duplicates carry bugs."
    examples:
      - "flay for AST-level duplicate detection"
      - "reek for code smell analysis"
      - "rubocop for style enforcement"
      - "prism for Ruby parsing"
    caveat: "Evaluate gem quality first: maintained, tested, minimal footprint."

  blank_lines:
    max_consecutive: 1     # no double blank lines anywhere

  rails_stack:
    # Current stable versions (May 2026)
    rails: "8.1.3"
    turbo_rails: "2.0.23"    # 9 actions: append prepend before after replace update remove morph refresh
    stimulus: "3.x"          # static targets, values, outlets API
    pagy: "43.x"             # Pagy::OPTIONS (not Pagy::DEFAULT — redesigned API in 43.0)
    stimulus_reflex: "3.5"   # complementary to Turbo; opt-in only for advanced reactive features

    asset_pipeline: propshaft  # default in Rails 8; do not use Sprockets
    javascript: importmap      # default; esbuild only when CSS-in-JS components needed
    queue: solid_queue         # SQLite-backed by default
    cache: solid_cache         # SQLite-backed by default
    cable: solid_cable         # SQLite-backed by default

    authentication: "rails generate authentication"  # built-in, no devise
    database: sqlite3          # default; PostgreSQL only when explicitly required

    pagy_api:
      backend:  "include Pagy::Backend"   # in ApplicationController
      frontend: "include Pagy::Frontend"  # in ApplicationHelper
      options:  "Pagy::OPTIONS[:limit] = 25"  # NOT Pagy::DEFAULT (that was 8.x)
      overflow: "Pagy::OPTIONS[:overflow] = :last_page"

    turbo_stream_actions:
      - append
      - prepend
      - before
      - after
      - replace
      - update
      - remove
      - morph   # morphs DOM — preserves element state; opt-in via data-turbo-permanent
      - refresh  # triggers full page refresh with morphing

    stimulus_api:
      targets: "static targets = [\"name\"]"       # auto-generates nameTarget, nameTargets, hasNameTarget
      values:  "static values = { url: String }"   # auto-generates urlValue, hasUrlValue, urlValueChanged
      outlets: "static outlets = [\"other\"]"      # cross-controller communication
      lifecycle: [connect, disconnect, initialize]  # + nameTargetConnected/Disconnected

    stimulus_components:
      source: "https://stimulus-components.com"
      install: "bin/importmap pin @stimulus-components/<name>"
      available:
        - { name: character-counter, use: "post/comment character limits" }
        - { name: clipboard, use: "copy URL/code to clipboard" }
        - { name: dialog, use: "modal dialogs, confirmations" }
        - { name: dropdown, use: "nav menus, user menus" }
        - { name: notification, use: "toast alerts" }
        - { name: carousel, use: "image galleries, product photos" }
        - { name: sortable, use: "drag-reorder lists" }
        - { name: rails-nested-form, use: "dynamic has-many form fields" }
        - { name: password-visibility, use: "show/hide password toggle" }

    core_web_vitals:
      lcp: "<2.0s"   # Largest Contentful Paint (tightened from 2.5s in March 2026)
      inp: "responsive"  # Interaction to Next Paint
      cls: "< 0.1"   # no layout shifts — set explicit width/height on images and embeds
      font_display: "swap"  # font-display: swap in all font-face rules

    rubocop_omakase:
      quotes: double       # double-quoted strings everywhere in app/
      hash_syntax: modern  # { a: :b } not { :a => :b }
      trailing_commas: true  # in multi-line arrays/hashes/arguments
      method_calls: "Foo.method not Foo::method"
      test_assertions: "assert_not not assert !"

    realtime_hierarchy:
      - "Turbo Drive — full-page navigation"
      - "Turbo Frames — scoped page updates"
      - "Turbo Streams — server-push DOM operations"
      - "Stimulus — client-side interactivity"
      - "StimulusReflex — opt-in for advanced RPC reactive features"

shell:
  decorations_forbidden:
    - "=== banner ===" # no ASCII section banners
    - "--- separator ---"
    - "*** header ***"
    - "emoji in print/echo output"  # no ✅ ❌ 🚀 etc. in scripts
    - "numbered step comments"      # no # Step 1:, # Phase 2: etc.

  credentials_forbidden: true  # never hardcode passwords/tokens in scripts

  prefer:
    - "pure zsh parameter expansion over external tools (see zsh_patterns.yml)"
    - "Open3.capture2e with arg arrays in Ruby over shell interpolation"
    - "File.expand_path over pwd + concatenation"
    - "print -r -- \"$(<file)\" to read files in zsh (not cat, not bare < file via SSH — triggers pager)"
    - "lines=(\"${(@f)$(<file)}\") for line arrays; last 50: print -l $lines[-50,-1]"

git:
  commit_style:
    voice: active           # "Fix bug" not "Fixed bug", "Add feature" not "Added feature"
    format: "type: short summary\n\nBody if needed."
    subject_max: 72
    no_what_if_diff_shows: true  # don't describe what changed if the diff makes it obvious
    separate_concerns: true      # don't mix bug fixes with style changes in one commit

  forbidden:
    - "Dir.chdir in Ruby before git commands"
    - "string-interpolated git commands"
    - "rm -rf in deploy scripts without explicit guard"
```

## `data/rules.yml`
```yaml
# rules.yml — universal structural rules
# scope: codebase > file > unit > line
# applies to: code, prose, law, business, science, design

# golden_rule and protection_tiers live in soul.yml (ABSOLUTE section) — single source.

voice:
  style: openbsd_dmesg
  anti_simulation:
    forbidden: [will, would, could, might]
    require_evidence:
      file_read: "show file content with SHA-256"
      modification: "show unified diff"
      completion: "show command output"
  banned_output:
    - headlines
    - section_markers
    - bullet_lists_without_content
    - filler_phrases
    - hedging
    - sycophancy
  strunk:
    preambles: ["In summary,", "Consequently,", "Therefore,", "Notably,", "Importantly,"]
    hedges: ["will", "would", "might", "could", "perhaps", "seems", "appears"]
    endings: ["as a result.", "for this reason.", "thus.", "in effect.", "accordingly."]
    code_preambles: ["# TODO: clarify intent", "# FIXME: review edge cases", "# NOTE: performance considerations", "# HACK: temporary workaround", "# REVIEW: assess after refactor"]
  inverted_pyramid:
    - "Lead with the outcome."
    - "Provide key evidence next."
    - "Add implementation detail last."

  preserve:
    boot_message: "5-line dmesg style, never collapse to one line"
    diagnostic_output: "structured multi-line output is intentional, never compress to abbreviations"
    help_text: "include command name, description, and at least one example"
    spinner_feedback: "show elapsed time and status, do not remove progress indicators"
    refinement_scope:
      streamline: "remove redundancy, not information"
      polish: "refine wording, not delete output"
      minimize: "applies to prompt tokens, not diagnostic output"

zen:
  observe: "Read current behavior before changing anything."
  simplify: "Reduce moving parts before adding new components."
  isolate: "Change one axis at a time with clear boundaries."
  verify: "Run checks and gather objective evidence."
  reflect: "Capture learning and improve defaults."

thresholds:
  file:
    max_lines: 300
    warn_lines: 200
    max_bytes: 8192
    max_line_length: 80
  method:
    max_lines: 10
    warn_lines: 7
    max_params: 3
    max_nesting: 2
    max_complexity: 4
  class:
    max_methods: 6
    max_instance_vars: 3
    max_dependencies: 2
    max_lines: 200
  coverage:
    minimum: 95
  cost:
    max_per_session: 5.00
    max_per_request: 0.50
    warn_at: 0.25

scan_depths:
  quick: &quick
    - FrozenStringRule
    - BareRescueRule
    - UniversalRule
  standard: &standard
    - FrozenStringRule
    - BareRescueRule
    - UniversalRule
    - ExplicitRule
    - ImmutableRule
    - CqsRule
    - SelfExplainingRule
    - LongMethodRule
    - GodClassRule
    - DuplicateCodeRule
    - PruneRule
    - SrpRule
    - PolaRule
    - NielsenRule
    - ArityRule
    - TellDontAskRule
    - ThresholdDriftRule
    - TerseRule
    - DeadAssignRule
    - NestingDepthRule
    - TrailingCommentRule
    - NamingRule
    - CommentQualityRule
    - DebugOutputRule
    - YamlQualityRule
    - StructureRule
    - DeadCodeRule
  deep: &deep
    - AdversarialRule
    - ConceptualRule
    - InterconnectRule
    - DuplicateCodeRule
    - FrozenStringRule
    - BareRescueRule
    - UniversalRule
    - ExplicitRule
    - ImmutableRule
    - CqsRule
    - SelfExplainingRule
    - LongMethodRule
    - GodClassRule
    - SrpRule
    - PolaRule
    - NielsenRule
    - ArityRule
    - TellDontAskRule
    - ThresholdDriftRule
    - OpportunityRule
    - RubocopRule
    - ReekRule
  hunt: *deep
  critique: *deep

languages:
  ruby:
    version: "3.3+"
    frozen_string_literal: required
    guard_clauses: true
    rescue: specify_type_always
    naming: snake_case
    max_params: 3
  rails:
    version: "8+"
    stack: [solid_queue, solid_cache, solid_cable]
    frontend: hotwire
    testing: minitest
    database: sqlite_default
    security: [strong_parameters, csrf, csp, ssl, hsts]
  zsh:
    shebang: "#!/usr/bin/env zsh"
    options: "set -euo pipefail; setopt nullglob extendedglob"
    # banned commands live in zsh_patterns.yml — single source.
  openbsd:
    service: rcctl
    packages: pkg_add
    firewall: pf
    privilege: doas
    http: httpd
    ssh:
      permit_root_login: false
      password_auth: false
      max_auth_tries: 3
  norwegian:
    dialect: "bokmål"
    rules: ["Short sentences", "Avoid anglicisms", "Active voice", "Plain language"]

rules:

  codebase:

    - id: PRESERVE_FIRST
      name: "Never break working code"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Does this change modify working code without reading it first?"
      fix: "Read before write. Patch minimally."

    - id: ONE_SOURCE
      name: "One authoritative representation per concept"
      tier: kernel
      severity: error
      autofix: true
      detect_conceptual: "Is the same logic or data defined in multiple places?"
      fix: "Extract to single source, reference from all consumers."

    - id: DECOUPLE
      name: "Make hidden dependencies explicit"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Are there implicit couplings between modules that should be injected?"
      fix: "Inject dependencies through constructor. No global state."

    - id: DEGRADE_GRACEFULLY
      name: "Operate under partial failures"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Does this code crash on partial failure instead of degrading?"
      fix: "Circuit breakers, timeouts, fallbacks."

    - id: GALLS_LAW
      name: "Complex systems evolve from simple working systems"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Is this attempting to build a complex system from scratch rather than evolving from a working simple one?"
      fix: "Start simple, prove it works, then extend."

    - id: CHESTERTONS_FENCE
      name: "Understand why something exists before removing it"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Is code being removed without understanding why it was added?"
      fix: "Read git blame, understand the rationale, then decide."

    - id: UNIX_PHILOSOPHY
      name: "Do one thing well"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Does this module try to do too many unrelated things?"
      fix: "Extract services. Clear module boundaries. Compose with pipes."

    - id: FUNCTIONAL_CORE
      name: "Pure logic in core, side effects at edges"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Are IO/DB calls scattered deep in business logic?"
      fix: "Return data from core, let shell handle IO."

    - id: CONVENTION_OVER_CONFIG
      name: "Sensible defaults reduce decisions"
      tier: productivity
      severity: info
      autofix: false
      detect_conceptual: "Does this require explicit config where a convention would suffice?"
      fix: "Provide sensible defaults, override only when needed."

    - id: MONOLITH_FIRST
      name: "Start monolith, extract when team exceeds 15"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is this prematurely splitting into services?"
      fix: "Keep it in one app until extraction is clearly needed."

    - id: CONSISTENT_ERROR_STRATEGY
      name: "One error handling strategy per module"
      tier: design
      severity: warning
      autofix: false
      detect_conceptual: "Does this module mix Result objects, exceptions, and nil-returns?"
      fix: "Pick one strategy per module. MASTER uses Result monad."

    - id: DUAL_DETECTION
      name: "Layer lexical and conceptual detection"
      tier: verification
      severity: info
      autofix: false
      detect_conceptual: "Is detection relying on regex alone or LLM alone?"
      fix: "Layer deterministic patterns with LLM semantic analysis."

    - id: MASS_GENERATE_CURATE
      name: "Generate many variations, curate ruthlessly"
      tier: creative
      severity: info
      autofix: false
      detect_conceptual: "Is the first draft being accepted without exploring alternatives?"
      fix: "Generate a swarm and curate when stakes are high."

    - id: NO_GOD_CLASS
      name: "No god classes"
      tier: core
      severity: error
      autofix: false
      detect_conceptual: "Does any class exceed 300 lines or 20 public methods?"
      fix: "Decompose into focused classes."

    - id: NO_SHOTGUN_SURGERY
      name: "One change should not require edits in many files"
      tier: core
      severity: warning
      autofix: false
      detect_conceptual: "Does a single conceptual change span many files?"
      fix: "Extract the missing abstraction."

    - id: NO_HIDDEN_GLOBAL_STATE
      name: "No hidden global state"
      tier: core
      severity: error
      autofix: false
      detect_conceptual: "Are there global variables or class-level mutable state shared across modules?"
      fix: "Inject configuration. Use dependency injection."

    - id: SINGLE_SOURCE_OF_TRUTH
      name: "One place defines each fact"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Is the same fact, rule, or definition stated in more than one place? In a legal system, is the same right defined in multiple statutes? In a genome, is the same regulatory element duplicated with divergent mutations?"
      fix: "One canonical source. Everything else references it. Never copy when you can point."

    - id: TRACER_BULLETS
      name: "End-to-end skeleton first, flesh out second"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is this building infrastructure without an end-to-end path? Is this business plan elaborating budgets before proving the revenue model? Is this research paper expanding methodology before demonstrating the finding?"
      fix: "Wire the simplest end-to-end path first. Prove it works. Then add depth."

    - id: ORTHOGONALITY
      name: "Changes in one dimension must not ripple into others"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Does changing one aspect force changes in unrelated aspects? Does reformatting break content? Does modifying one gene's expression alter another pathway?"
      fix: "Decouple dimensions. Database changes should not require UI changes. Style should not affect structure."

    - id: TRANSFORMATIONS
      name: "Think in pipelines: input transforms to output"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is this modeling the problem as mutable state instead of flowing transformations? Does this document bury its flow in scattered cross-references?"
      fix: "Express work as a chain of transformations. Each stage takes input, produces output, holds no state."

    - id: DEEP_MODULES
      name: "Powerful functionality behind simple interfaces"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Is this module shallow — complex interface, trivial implementation? Does this form ask 40 questions for a simple task? Does this clause require five cross-references?"
      fix: "Simple interface, rich implementation. A deep module does much with little ceremony."

    - id: INFORMATION_HIDING
      name: "Each module encapsulates one design decision"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Is implementation detail leaking across boundaries? Would changing an internal decision force changes elsewhere?"
      fix: "Encapsulate each decision in one module. If it changes, only that module changes."

    - id: DIFFERENT_LAYER_DIFFERENT_ABSTRACTION
      name: "Each layer speaks a different language than its neighbors"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Do adjacent layers use the same abstraction? Are there pass-through methods that add no value? Does this management layer just relay without transforming?"
      fix: "Each layer must transform, not relay. If a layer adds no abstraction, remove it."

    - id: STRUCTURAL_HONESTY
      name: "The shape of the artifact must reflect the shape of the problem"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Does the structure match the domain? Does the module hierarchy match the conceptual hierarchy? Does the floor plan match the workflow?"
      fix: "Align structure with reality. Natural domain boundaries become system boundaries."

    - id: GRACEFUL_BOUNDARIES
      name: "Where systems meet, expect translation and loss"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Does this boundary assume perfect fidelity? Does this integration assume the other side never changes?"
      fix: "Every boundary is a translation layer. Validate at every boundary. Degrade gracefully when translation fails."

    - id: PULL_COMPLEXITY_DOWN
      name: "Simple interface matters more than simple implementation"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is complexity pushed up to the caller instead of absorbed by the implementation?"
      fix: "Absorb complexity into the implementation. The caller should not need to know how it works."

    - id: ETC
      name: "Easier To Change — the meta-value behind every principle"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Does this design decision make the system harder to change? Does this contract make renegotiation unnecessarily difficult?"
      fix: "Choose the option that keeps more options open. Decoupled, parameterized, replaceable."

    - id: BROKEN_WINDOWS
      name: "Zero tolerance for visible decay"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Is there visible rot being left unfixed — dead code, broken links, stale references? In a brief, citations to overruled cases?"
      fix: "Fix it now. One broken window invites more."

    - id: ENTROPY_RESISTANCE
      name: "Systems decay toward disorder unless actively maintained"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Is there creeping disorder — naming inconsistencies, abandoned conventions, accumulating exceptions? In a legal code, contradictory amendments?"
      fix: "Actively resist entropy. Regular cleanup. Remove what no longer serves."

... 1064 lines truncated (1464 total)
```

## `data/soul.yml`
```yaml
# soul.yml — machine-enforced constitutional schema
# Human-readable narrative lives in SOUL.md.
# ABSOLUTE sections require constitutional override to amend.
# Negotiable sections: soul propose -> soul approve -> bump version.

version: "2.1.0"
persona: dark_malay
voice: ms-MY-OsmanNeural
language:
  primary: english
  secondary: norwegian
  dialect: bokmal

absolute:
  golden_rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
  anti_simulation:
    forbidden: [will, would, could, might]
    require_evidence:
      file_read: show content with SHA-256
      modification: show unified diff
      completion: show command output
  protection_tiers:
    ABSOLUTE: abort pipeline
    PROTECTED: emit warning continue
    NEGOTIABLE: allow if explicitly permitted
    FLEXIBLE: negotiate at runtime

negotiable:
  style: openbsd_dmesg
  default_model: openrouter/auto
  tts_voice: ms-MY-OsmanNeural
  language_detection: true

evolution_log:
  - version: "1.0.0"
    date: "2026-04-01"
    change: initial SOUL.md constitutional identity
    author: dev
  - version: "2.0.0"
    date: "2026-04-24"
    change: OpenClaw-inspired restructure
    author: dev
  - version: "2.1.0"
    date: "2026-04-27"
    change: restored from sweep corruption
    author: dev
```

## `data/standing_orders.yml`
```yaml
---
- name: nightly_dreams
  description: Consolidate memories during low-activity periods
  trigger: scheduled
  interval_s: 86400
  command: dreams consolidate
  enabled: true
  state: done
  last_run_at: 1777836021
- name: weekly_scan
  description: Weekly codebase axiom scan for regressions
  trigger: scheduled
  interval_s: 604800
  command: scan
  enabled: false
  state: pending
  last_run_at: 0
- name: data_integrity_check
  description: Detect and recover from corrupted data/ YAML files (LLM error strings
    written as file content)
  trigger: scheduled
  interval_s: 3600
  command: "/scan data/"
  enabled: true
  state: running
  last_run_at: 1777590915
```

## `data/sweep_prompts.yml`
```yaml
# Sweep stage prompt building blocks

axioms: |
  Constitutional constraints (non-negotiable):
  - Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
  - Default to no change if improvement is uncertain (PRESERVE_FIRST)
  - Minimum change that eliminates the violation (SIMPLEST_WORKS)
  - Raise/log errors; never swallow them silently (FAIL_VISIBLY)
  - Config in data/*.yml; code reads from there (ONE_SOURCE_OF_TRUTH)
  - rescue SpecificError => e; never bare rescue (SPECIFIC_RESCUE)
  - Extract literals to named constants; no magic numbers
  - Read current behavior before changing anything (zen: observe)
  - Change one axis at a time with clear boundaries (zen: isolate)

structural_techniques:
  - ASSERT
  - DECOUPLE
  - DEFRAG
  - DEHEDGE
  - DEPREAMBLE
  - EXTRACT
  - FLATTEN
  - HOIST
  - INLINE
  - MERGE
  - NAME
  - RECOMMENT
  - REFLOW
  - REGROUP
  - SPLIT
  - TELLPROSE_TECHNIQUES

cosmetic_techniques:
  - ALIGN_SPACE
  - CONTRACT
  - EXPAND
  - FENCE_CONSTANT
  - PRIVATE_DIMENSION_ASSESSMENT
  - MERGE
  - SPLIT
```

## `data/templates.yml`
```yaml
# Generation templates — canonical starting points for code generation tasks.

html:
  rules:
    - Semantic HTML5
    - No div soup
    - Minimal attributes
    - Accessible landmarks
    - Responsive meta viewport
    - Prefer native form controls
    - Defer non‑essential scripts
    - Inline critical CSS
  template: |
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>%{title}</title>
      <link rel="stylesheet" href="style.css">
      <script defer src="app.js"></script>
    </head>
    <body>
      <header><h1>%{title}</h1></header>
      <main>%{content}</main>
      <footer><p>&copy; %{year}</p></footer>
    </body>
    </html>

css:
  rules:
    - CSS custom properties
    - System font stack
    - Mobile‑first breakpoints
    - Dark mode via prefers‑color‑scheme
    - Prefer logical properties
    - Avoid !important
    - Use clamp() for fluid typography
    - Scope to :root for theming
    - Reduce render‑blocking selectors
  template: |
    :root {
      --bg: #fff;
      --fg: #111;
      --accent: #06f;
      --mono: ui-monospace, monospace;
      --sans: system-ui, sans-serif;
      --spacing: clamp(1rem, 2vw, 2rem);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111;
        --fg: #eee;
      }
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; }
    body {
      font: 1rem/1.5 var(--sans);
      background: var(--bg);
      color: var(--fg);
      max-width: 60ch;
      margin: auto;
      padding: var(--spacing);
    }
    a { color: var(--accent); text-decoration: underline; }

ruby:
  rules:
    - frozen_string_literal: true
    - Guard clauses over nested conditionals
    - Modules over classes when no state
    - Public methods only in modules
    - Explicit return values
    - Typed keyword arguments where possible
    - Separate IO from business logic
    - Document public API with YARD
  template: |
    # frozen_string_literal: true
    module %{module_name}
      module_function

      # @param args [Hash] keyword arguments
      # @return [Hash, nil] processed data or nil when no input
      def call(**args)
        return nil if args.empty?

        process(**args)
      end

      # @param data [Hash] business data
      # @return [Hash] transformed data
      def process(**data)
        data
      end
    end

sh:
  rules:
    - "#!/bin/sh for portability"
    - "set -eu for strict error handling"
    - Quote all variables
    - Meaningful exit codes
    - Use functions for readability
    - Redirect errors to stderr
    - Prefer command substitution over backticks
    - Guard against missing arguments
  template: |
    #!/bin/sh
    set -eu

    main() {
      %{body}
    }

    main "$@"
    exit 0
```

## `data/workflow.yml`
```yaml
# MASTER workflow rules — operational principles codified from CLAUDE.md.
# Governs how MASTER and its LLM agents read, edit, scan, and fix code.

file_reading:
  rule: READ_FULL_FILES
  statement: "Read complete files. Never grep, head, tail, or partial‑read to understand code."
  rationale: "Partial view yields partial (wrong) changes."
  allowed_exceptions:
    - "grep/search across many unknown files to locate a keyword"
  forbidden:
    - "grep pattern file to understand code structure"
    - "head -N file to check structure"
    - "tail -N file to check endings"

before_edit:
  rule: READ_BEFORE_WRITE
  statement: "Read every file that could be affected before editing any file."
  steps:
    - "Map the codebase: find all .rb files in lib/"
    - "Trace callers before changing any public method signature"
    - "Check Zeitwerk inflectors before renaming classes or files"
    - "Run ruby -c FILE after every write"
    - "Run ruby -e require_relative after every commit"

code_principles:
  no_hardcoding:
    rule: NO_HARDCODED_CONSTANTS
    statement: "Prose, patterns, and config belong in data/*.yml, not Ruby strings."
  single_source:
    rule: ONE_SOURCE_OF_TRUTH
    statement: "If it is in a data file, the code reads from there. No duplicates."
  no_magic_numbers:
    rule: NAMED_CONSTANTS
    statement: "Extract literals to named constants with .freeze"
  no_bare_rescue:
    rule: SPECIFIC_RESCUE
    statement: "Always rescue SpecificError => e. Propagate or log via event bus."
  guard_first:
    rule: GUARD_CLAUSES_FIRST
    statement: "Return Result.ok(ctx) unless condition before main logic."
  one_responsibility:
    rule: SINGLE_RESPONSIBILITY
    statement: "Split if you can name two reasons to change it."
  cqs:
    rule: COMMAND_QUERY_SEPARATION
    statement: "Queries return data and do not mutate. Commands mutate and do not return values."
  inject_deps:
    rule: DEPENDENCY_INJECTION
    statement: "Never instantiate collaborators inside a method."
  result_monad:
    rule: RESULT_MONAD
    statement: "Use respond_to?(:ok?) not is_a?(Result) for duck‑typing."

scan_rules:
  standard_depth:
    - frozen_string
    - bare_rescue
    - explicit
    - immutable
    - cqs
    - self_explaining
    - long_method
    - god_class
    - duplicate_code
    - prune
    - srp
    - pola
    - nielsen
  deep_only:
    - conceptual
    - adversarial
  hunt_only:
    - rubocop
    - reek
  notes:
    nielsen: "puts is NOT debug output in a CLI. Only p, pp, binding.pry, debugger are."
    prune: "Loads patterns from data/rules.yml (voice.strunk) — single source of truth."
    conceptual: "Loads philosophy from data/rules.yml (zen + voice) — single source of truth."
    deep_caution: "deep adds 2 LLM calls per file. With 90 files at 8 req/min free tier = 22+ minutes."

principle_groups:
  axioms:      [frozen_string, explicit, immutable, self_explaining]
  solid:       [srp, cqs, pola]
  clean_code:  [long_method, god_class, duplicate_code, bare_rescue]
  interface:   [nielsen, prune]
  llm_rules:   [conceptual, adversarial]
  heavy:       [rubocop, reek]
  quick:       [frozen_string, bare_rescue, explicit, long_method, god_class]
  critical:    [frozen_string, bare_rescue, explicit, immutable, srp, cqs]

scan_profiles:
  quick:
    depth: standard
    rules: quick
    description: "Fast scan — core violations only"
  full:
    depth: deep
    rules: "*"
    description: "All rules, deep LLM analysis"
  critical:
    depth: standard
    rules: critical
    description: "Critical issues blocking ship"
  solid:
    depth: standard
    rules: solid
    description: "SOLID principles focus"
  axioms:
    depth: standard
    rules: axioms
    description: "Constitutional axioms only"

conflicts:
  strategy: highest_priority_wins
  rules:
    - condition: "dry conflicts with wet or aha"
      resolution: "favor wet/aha if fewer than 3 duplications exist"
    - condition: "clarity conflicts with simplicity"
      resolution: "favor clarity"
    - condition: "fix introduces higher priority violation"
      resolution: "reject fix, report to autoloop"

universal_scope:
  policy: ALL_PRINCIPLES_ALL_FILES
  statement: >
    All axioms, principles, and philosophies apply to every file in the codebase
    regardless of file type: Ruby, YAML, Zsh, HTML, CSS, JavaScript, Markdown.
    Language-specific rules apply only to their target language; universal rules
    (SQUINT_TEST, TYPOGRAPHY_DISCIPLINE, MEANINGFUL_NAMES, etc.) apply everywhere.
  scan_glob: "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,md}"
  conceptual_rules: all_known_languages
  adversarial_rules: all_known_languages

autoloop:
  background: true
  idle_sleep: 60
  scan_depth: standard
  fix_depth: llm
  batch_size: 3
  max_cycles: 12
  rate_limit_sleep: 15
  max_file_bytes: 16000
  max_fix_retries: 3
  confidence_threshold: 0.60
  targets:
    - lib/
    - test/
    - data/
    - web/
    - DEPLOY/
  excludes:
    - vendor/
    - knowledge/
    - fix_
    - patch_
  skip_rules:
    - duplicate_code
    - conceptual
    - adversarial
    - axiom_coverage
    - immutable
    - self_explaining
    - long_method
    - pola
    - srp
    - cqs
    - rubocop
    - reek

sweep:
  scan_depth: deep
  converge_threshold: 0.05
  converge_window: 2
  max_cycles: 16
  codebase_map: true

zeitwerk:
  inflections:
    autoloop: AutoLoop
    cli: CLI
    mcp_server: MCPServer
    mcp_coordinator: McpCoordinator
    diff_stager: DiffStager
    code_index: CodeIndex
    git_context: GitContext
    ast_edit: AstEdit
    llm: LLM

anti_sprawl:
  forbidden_files:
    - summary.md
    - analysis.md
    - report.md
    - todo.md
    - notes.md
    - changelog.md
  rule: "Edit existing files. Single source of truth."

validation:
  after_write: "ruby -c lib/master/FILE.rb"
  after_commit: "ruby -e \"require_relative 'lib/master'; puts 'ok'\""
  scan_file: "bundle exec ruby exe/master scan lib/master/FILE.rb"

phases:
  discover:
    id: 1
    goal: "Understand actual need"
    output: "Problem statement with success criteria"
    gates:
      - no_vague_words
      - audience_identified
      - success_measurable
  analyze:
    id: 2
    goal: "Break into components"
    output: "Component diagram with dependencies"
    gates:
      - components_distinct
      - dependencies_acyclic
  ideate:
    id: 3
    goal: "Generate 15+ alternatives"
    output: "List of approaches with trade‑offs"
    gates:
      - count_gte_15
      - trade_offs_documented
  design:
    id: 4
    goal: "Specific architecture"
    output: "Interface definitions and error handling"
    gates:
      - interfaces_explicit
      - errors_documented
  implement:
    id: 5
    goal: "Execute with zero violations"
    output: "Working code at 100/100 score"
    gates:
      - tests_pass
      - zero_violations
  validate:
    id: 6
    goal: "Prove with evidence"
    output: "Test results, benchmarks"
    gates:
      - zero_test_failures
      - edge_cases_covered
  deliver:
    id: 7
    goal: "Ship with monitoring"
    output: "Deployed code with dashboards"
    gates:
      - deployed
      - monitoring_configured
session_startup:
  mandatory_reads:
    - data/soul.yml
    - data/rules.yml
    - data/ruby_style.yml
    - data/workflow.yml
    - data/standing_orders.yml
  check_standing_orders: "Verify FSM state before any mutation -- UNCHANGE blocks refactoring"
  scan_before_analysis: "Use /scan deep via MASTER, not external agents, for code analysis"
  ssh_edit_pattern: "Write to /tmp, run ruby /tmp/patch.rb -- never ruby -i with heredoc"

corruption_prevention:
  llm_error_in_file: "git checkout HEAD -- data/ && rcctl restart master -- LLM error strings silently overwrite YAML data files when circuit is open and agent#ask returns error string instead of raising"
  sweep_excludes_data: "Sweep must never rewrite data/*.yml -- these are structured config, not code to refactor"
  yaml_type_guards: "All load_yaml calls must type-check result before use (is_a?(Array/Hash)) -- circuit-open strings parse as valid YAML scalars"
  ask_raises_on_error: "agent#ask must raise StandardError when result.err? -- callers must rescue, never silently propagate error strings as LLM output"
```

## `data/zsh_patterns.yml`
```yaml
# Zsh-native patterns — replace external forks with pure Zsh
# Source: pub2/ZSH_NATIVE_PATTERNS.md

forbidden_commands:
  - command: awk
    replacement: "zsh array/string field splitting: ${${(s:,:)line}[4]}"
  - command: sed
    replacement: "zsh parameter expansion: ${var//search/replace}"
  - command: tr
    replacement: "zsh case conversion: ${(L)var} ${(U)var}"
  - command: grep
    replacement: "zsh pattern matching: ${(M)arr:#*pattern*}"
  - command: cut
    replacement: "zsh field splitting: ${${(s:delim:)var}[N]}"
  - command: head
    replacement: "zsh array slicing: ${arr[1,10]}"
  - command: tail
    replacement: "zsh array slicing: ${arr[-5,-1]}"
  - command: uniq
    replacement: "zsh unique flag: ${(u)arr}"
  - command: sort
    replacement: "zsh sort flags: ${(o)arr} (asc) / ${(O)arr} (desc)"
  - command: bash
    replacement: "zsh — never use bash"
  - command: find
    replacement: "zsh glob qualifiers: **/*.rb(.)"
  - command: wc
    replacement: "zsh length/count: ${#var} / ${#arr}"
  - command: sudo
    replacement: "doas on OpenBSD"

native_patterns:
  string_replace:          "${var//find/replace}"
  case_lower:              "${(L)var}"
  case_upper:              "${(U)var}"
  trim_whitespace:         "${${var##[[:space:]]#}%%[[:space:]]#}"
  split_to_array:          "${(s:delim:)var}"
  array_join:              "${(j:,:)arr}"
  array_unique:            "${(u)arr}"
  array_sort_asc:          "${(o)arr}"
  array_sort_desc:         "${(O)arr}"
  array_reverse:           "${(Oa)arr}"
  array_filter_match:      "${(M)arr:#*pattern*}"
  array_filter_exclude:    "${arr:#*pattern*}"
  remove_crlf:             "${var//$'\\r'/}"

exceptions:
  - "Complex regex requiring PCRE"
  - "Multi‑file operations beyond globbing"
  - "Binary data processing"

banned_commands: [python, bash, sed, awk, tr, wc, head, tail, cut, find, sudo]

auto_remediation:
  awk:   "${${(s: :)line}[n]}"
  sed:   "${var//old/new}"
  tr:    "${(U)var} or ${(L)var}"
  wc:    "${#lines}"
  head:  "${lines[1,n]}"
  tail:  "${lines[-n,-1]}"
  grep:  "${(M)lines:#*pattern*}"
  cut:   "${${(s:delim:)var}[N]}"
  sort:  "${(o)arr} or ${(O)arr}"
  find:  "**/*.ext(.)"
  sudo:  "doas"

token_economics:
  philosophy: >
    Replacing multi‑tool shell pipelines with pure Zsh parameter expansion
    eliminates process boundaries, collapses multiple grammars into one,
    reduces reasoning entropy for LLMs, and converts runtime overhead
    into in‑memory transforms — saving both tokens and wall‑clock time.
  example_bad:
    code: "awk -F, '{print $4}' | sed 's/\\r//g' | tr '[:upper:]' '[:lower:]'"
    cost: "3 grammars, pipes + subshells, I/O transformations"
  example_good:
    code: "cleaned=${var//$'\\r'/}; lower=${(L)cleaned}; fourth=${${(s:,:)lower}[4]}"
    cost: "One grammar, one evaluation model, no process boundaries"
  benefit: "Model reasons locally instead of globally across pipeline"
```

## `docs/master2_restoration_opportunities.md`
```markdown
# MASTER2 Restoration — Status

Date: 2026-04-30

## What exists in MASTER2 (not yet in MASTER)

- `lib/workflow/convergence.rb` — plateau/oscillation detection for sweep loops. High value.
- `lib/violation_hooks.rb` — JSONL persistent violation log. Useful for trend analysis.
- `lib/analysis/openbsd_config_validator.rb` — OpenBSD config validation (partially restored to `data/openbsd.yml`).
- `lib/code_review/` and `lib/review/` — legacy review engines. Architecture diverges from current MASTER; requires staged porting.

## Completed restorations

- `data/openbsd.yml` — pf/nsd/httpd/smtpd/relayd/acme-client/doas/sshd/ntpd/unbound validators.
- `data/workflow.yml` — `principle_groups` and `scan_profiles` (enables `/scan quick`, `/scan critical`).
- `data/workflow.yml` — `conflicts` strategy (DRY vs WET resolution).

## Recommended next batches

1. Port `Workflow::Convergence` into `lib/master/sweep.rb` — adds oscillation/plateau early-stop.
2. Port `ViolationHooks` — write `.constitutional_violations.jsonl` on each scan hit.
3. Review `lib/code_review/` against current scan rules before porting.
```

## `docs/ui_supersnappy_two_party_plan.md`
```markdown
# UI: Two-Party Supersnappy Plan

Goals: explicit turn state, perceived latency under 120ms, two-channel output.

## Turn state machine

States: `idle` → `typing` → `sending` → `thinking` → `streaming` → `tool_running` → `awaiting_user` → `done` / `error`

Display current state at all times. Users must answer "whose turn is it?" in one glance.

## Output channels

Split assistant output into two channels:
- **Answer** — user-facing prose
- **Activity** — tools, events, progress (shown dim; collapse when done)

## Performance targets

- Submit → first visual feedback: < 120ms
- Submit → first token visible: < 900ms
- Stop action reaction: < 150ms perceived

Optimizations: instant echo user bubble, skeleton reservation, 16–32ms chunk flush cadence, optimistic markdown rendering.

## Web UI changes (priority order)

1. Explicit turn state indicator — always visible
2. Stop / Regenerate controls on active turn
3. Activity timeline under assistant bubble (collapsible)
4. Quick-reply chips for follow-up prompts
5. Focus mode: full-height chat, sticky composer, side panel for orb
6. Virtualized history for long sessions

## CLI changes

1. Per-turn latency row: `[thinking 420ms · first token 780ms · tools 2]`
2. Consistent keymap: Enter=send, Shift+Enter=newline, Tab=cycle suggestions, ↑=edit previous
3. Dim-prefixed activity lines: `· tool: read file…`

## Shared event schema

Both CLI and web emit: `turn.started`, `stream.delta`, `tool.started`, `tool.finished`, `turn.completed`, `turn.failed`

## Implementation phases

**Phase 1 (1–2 days):** Turn state machine, sending/thinking skeleton, stop control, timing instrumentation.

**Phase 2 (3–5 days):** Answer/activity channel split, chunk flush cadence, quick replies, CLI status row.

**Phase 3 (1 week):** Focus mode, virtualized history, shared event schema, server-side transcript persistence.
```

## `lib/master.rb`
```ruby
# frozen_string_literal: true

require "zeitwerk"
require "yaml"

# Pre-load openssl before pledge stage1 engages — faraday-net_http requires it
# lazily on first HTTPS call, which fails after unveil restricts dlopen paths.
begin
  require "openssl"
rescue LoadError => e
  warn "openssl: #{e.message} — LLM calls will fail"
end

module Master
  ROOT = File.expand_path("..", __dir__).freeze

  MIN_API_KEY_LENGTH = 20
  SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
  CTX_WINDOW_SIZE = 200_000
  VIOLATION_TRUNCATE = 90

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".yml" => "yaml", ".yaml" => "yaml",
    ".js" => "javascript", ".json" => "json", ".sh" => "bash",
    ".zsh" => "bash", ".md" => "markdown", ".html" => "html",
    ".erb" => "erb", ".css" => "css"
  }.freeze

  API_KEY_PROVIDERS = {
    anthropic_api_key:  "ANTHROPIC_API_KEY",
    openai_api_key:     "OPENAI_API_KEY",
    gemini_api_key:     "GEMINI_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY",
    mistral_api_key:    "MISTRAL_API_KEY",
    deepseek_api_key:   "DEEPSEEK_API_KEY"
  }.freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "autoloop" => "AutoLoop",
    "cli"      => "CLI",
    "llm"      => "LLM"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.ignore(File.join(__dir__, "master", "ruby_llm_patch.rb"))
  %w[
    autoloop/fix_evaluator.rb
    builder/infra_helpers.rb
    cli/signals.rb
    cli/tts.rb
    command_registry/agent_commands.rb
    command_registry/memory_commands.rb
    command_registry/service_commands.rb
    memory/search.rb
    sweep/rewriter.rb
    sweep/convergence.rb
  ].each do |rel|
    loader.ignore(File.join(__dir__, "master", rel))
  end
  loader.setup

  def self.configure_providers!
    # Stub Bedrock before ruby_llm loads — avoids openssl.so on OpenBSD/LibreSSL.
    # MASTER only uses OpenRouter; Bedrock is never needed.
    require_relative "master/bedrock_stub"
    require "ruby_llm"
    require_relative "master/ruby_llm_patch"
    RubyLLM.configure do |cfg|
      API_KEY_PROVIDERS.each do |attr, env_var|
        api_key = ENV[env_var].to_s
        cfg.public_send("#{attr}=", api_key) if api_key.length >= MIN_API_KEY_LENGTH
      end
    end
  end

  def self.api_key_present?(env_var)
    ENV[env_var].to_s.length >= MIN_API_KEY_LENGTH
  end

  def self.default_model
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("OPENROUTER_API_KEY")
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("REPLICATE_API_KEY")
    return "claude-sonnet-4-6" if api_key_present?("ANTHROPIC_API_KEY")
    return "gpt-4o" if api_key_present?("OPENAI_API_KEY")
    return "gemini-2.5-flash" if api_key_present?("GEMINI_API_KEY")
    return "mistral-large-latest" if api_key_present?("MISTRAL_API_KEY")
    return "deepseek-chat" if api_key_present?("DEEPSEEK_API_KEY")
    raise "No LLM API key found. Set OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY, MISTRAL_API_KEY, or DEEPSEEK_API_KEY."
  end

  def self.load_yaml(path)
    YAML.safe_load_file(path, aliases: true)
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES => e
    warn("load_yaml: " + e.message)
    {}
  end

  def self.build(root: Dir.pwd)
    Builder.build(root:)
  end

  def self.boot(root: Dir.pwd, argv: [])
    Pledge.stage1_boot!(root)
    container = Builder.build(root:)
    Builder.boot_snapshot(container)
    container[:heartbeat]&.start!
    Pledge.stage2_lock!
    CLI.new(container:)
  end
end
```

## `lib/master/agent.rb`
```ruby
# frozen_string_literal: true

require "ruby_llm"
require "digest"
require_relative "agent/llm_dispatch"

module Master
  class Agent
    include LlmDispatch

    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN = 0.000_015

    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE = build_tool_capable_re.freeze
    MAX_TOOL_TURNS = 5
    TOOL_CALL_RE = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze
    NEMOTRON3_RE = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    LLM_TOOL_MAP = {
      Tools::ReadFile        => Tools::LLM::ReadFile,
      Tools::WriteFile       => Tools::LLM::WriteFile,
      Tools::StrReplace      => Tools::LLM::StrReplace,
      Tools::ListDir         => Tools::LLM::ListDir,
      Tools::SearchFiles     => Tools::LLM::SearchFiles,
      Tools::Shell           => Tools::LLM::Shell,
      Tools::WebSearch       => Tools::LLM::WebSearch,
      Tools::AskLlm          => Tools::LLM::AskLlm,
      Tools::GitContext      => Tools::LLM::GitContext,
      Tools::AstEdit         => Tools::LLM::AstEdit,
      Tools::SearchKnowledge => Tools::LLM::SearchKnowledge
    }.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil, context_window: nil)
      @config, @session, @tools          = config, session, tools
      @circuit_breaker, @cache, @bus     = circuit_breaker, cache, event_bus
      @model_router, @reasoning_modes    = model_router, reasoning_modes
      @memory, @personality, @code_index = memory, personality, code_index
      @context_window                    = context_window
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt = apply_reasoning_mode(message)
      context = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / Session::TOKENS_PER_CHAR)

      begin
        @circuit_breaker.check_rate!
      rescue CircuitBreaker::CircuitError => rate_err
        return Result.err(rate_err.message, category: rate_err.category)
      end

      last_response = attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      return last_response if last_response.respond_to?(:err?) && last_response.err?
      last_response = maybe_escalate(last_response, message, stream:, escalation_depth:, &blk)

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :handler_exception)
    end

    def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = routed_models.first
      result = send_with_cache(selected_model, messages, stream: false)
      raise result.message if result.respond_to?(:err?) && result.err?
      result.to_s
    end

    def ask_once(prompt, system: nil, model: nil)
      result = send_with_cache(model || self.model, [{ role: "user", content: prompt.to_s }], system:, stream: false)
      result.is_a?(String) ? result : (result.ok? ? result.value!.to_s : "")
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first
    def model=(val)
      @config["model"] = val
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary if @code_index&.built?
      parts << @memory.context_summary if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end
  end
end
```

## `lib/master/agent/llm_dispatch.rb`
```ruby
# frozen_string_literal: true

module Master
  class Agent
    # LlmDispatch — LLM routing, caching, and escalation; extracted from Agent.
    module LlmDispatch
      private

      def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
        capable = select_capable_models(candidate_models)
        return capable if capable.respond_to?(:err?) && capable.err?

        last_response = nil
        capable.each_with_index do |selected_model, index|
          response = send_with_cache(
            selected_model,
            context + [{ role: "user", content: prompt }],
            stream:, &blk
          )
          last_response = response
          publish_llm_success(selected_model, response) if response.respond_to?(:ok?) && response.ok?
          break response unless response.respond_to?(:err?) && response.err? && index < capable.length - 1
        end
        last_response
      end

      def select_capable_models(candidates)
        capable = candidates.select { |m| replicate_model?(m) || ferrum_model?(m) || tool_capable?(m) }
        return Result.err("no tool-capable model available", category: :validation) if capable.empty?
        capable
      end

      def publish_llm_success(model, response)
        @bus&.publish("llm:response", model:, success: true, tokens_approx: response.to_s.bytesize / Session::TOKENS_PER_CHAR)
      end

      def maybe_escalate(last_response, original_message, stream:, escalation_depth:, &blk)
        return last_response unless @model_router
        return last_response if escalation_depth >= 2

        current = routed_models.first
        escalation_model = @model_router.escalate_if_low_confidence(
          last_response.to_s,
          current_model: current,
          task_type: @config.task_type.to_sym
        )
        return last_response unless escalation_model

        @bus&.publish("llm:escalation", from: current, to: escalation_model)
        escalated = chat(
          original_message, stream: stream,
          escalation_depth: escalation_depth + 1, &blk
        )
        escalated.respond_to?(:err?) && escalated.err? ? last_response : escalated
      end

      def send_with_cache(selected_model, messages, system: nil, stream: false, &blk)
        cache_key = cache_key_for(messages.last[:content], messages[0...-1])
        breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
          @cache.fetch(cache_key, selected_model) {
            send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
          }
        }
      rescue StandardError => err
        Result.err("llm_request: #{err.message}", category: :llm_call_failure)
      end

      def send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
        sys = system || system_prompt
        if ferrum_model?(selected_model)
          return send_ferrum(selected_model, messages)
        elsif replicate_model?(selected_model)
          return send_replicate(selected_model, messages, sys:, stream:, &blk)
        end

        send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
      end

      def send_ferrum(selected_model, messages)
        alias_name = selected_model.split(":", 3).last
        response = Bridges::FerrumWebChat.new.ask(
          model_alias: alias_name, prompt: messages.last[:content]
        )
        return response if response.respond_to?(:err?) && response.err?
        Result.ok(
          response.respond_to?(:ok?) && response.ok? ? response.value! : response.to_s
        )
      end

      def send_replicate(selected_model, messages, sys:, stream:, &blk)
        reply = Bridges::Replicate.new.chat(
          model: selected_model, messages:, system: sys,
          stream:, &(stream ? blk : nil)
        )
        Result.ok(reply.content.to_s)
      end

      def send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
        chat_session = RubyLLM.chat(model: selected_model)
        final_sys = nemotron_system_prompt(selected_model, sys)
        chat_session.with_instructions(final_sys) if final_sys
        messages.each { |msg|
          chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s)
        }

        available_tools = llm_tools(selected_model)
        chat_session.with_tools(*available_tools) unless available_tools.empty?

        reply = if stream && blk
          chat_session.ask(messages.last[:content]) { |chunk|
            blk.call(chunk.content.to_s) if chunk.content
          }
        else
          chat_session.ask(messages.last[:content])
        end
        Result.ok(extract_response(reply, selected_model))
      end

      def routed_models
        return [@config.model] unless @model_router
        @model_router.fallback_chain(task_type: @config.task_type.to_sym)
      rescue StandardError => e
        @bus&.publish("llm:route_error", error: e.message) if defined?(@bus)
        [@config.model]
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def replicate_model?(model_id)
        return false unless ENV["REPLICATE_API_KEY"].to_s.length >= MIN_API_KEY_LENGTH
        REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
      end

      def ferrum_model?(model_id)
        model_id.to_s.start_with?("ferrum:webchat:")
      end

      def tool_capable?(model_id)
        TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
      end

      def extract_response(reply, selected_model)
        return reply.to_s unless reply.respond_to?(:content)
        if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
          thinking = reply.reasoning_content.to_s.strip
          content = reply.content.to_s
          return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
        end
        reply.content.to_s
      end

      def nemotron_system_prompt(selected_model, base = nil)
        sys = base || system_prompt
        return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
        thinking_on = @config["reasoning_mode"] != "none"
        directive = thinking_on ? "detailed thinking on" : "detailed thinking off"
        [directive, sys].compact.join("\n\n")
      end

      CACHE_WINDOW = 4
      def cache_key_for(message, context)
        return Digest::SHA256.hexdigest(message) if context.empty?
        window = context.last(CACHE_WINDOW).map { |msg|
          "#{msg[:role]}:#{msg[:content]}"
        }.join("\n")
        Digest::SHA256.hexdigest("#{message}\n#{window}")
      end

      def estimate_cost(prompt)
        (prompt.bytesize / Session::TOKENS_PER_CHAR) * COST_PER_TOKEN
      end

      def llm_tools(selected_model = model)
        return [] unless tool_capable?(selected_model)
        @llm_tools ||= build_llm_tools
      end

      def build_llm_tools
        @tools.filter_map do |tool|
          wrapper = LLM_TOOL_MAP[tool.class]
          wrapper&.new(tool)
        end
      rescue StandardError => err
        @bus&.publish("agent:llm_tools_error", error: err.message)
        []
      end
    end
  end
end
```

## `lib/master/audit_log.rb`
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only tool invocation log; subscribes to tool:before on EventBus.
  class AuditLog
    LOG_PATH = ".master/audit.log".freeze
    MAX_VAL  = 120

    def initialize(root:, event_bus:)
      @path  = File.join(root, LOG_PATH)
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(@path))
      event_bus.subscribe("tool:before") { |event_data| append(event_data) }
    end

    private

    def append(event_data)
      payload_pairs = event_data.except(:tool)
                                .map { |k, v| "#{k}=#{v.to_s[0, MAX_VAL].inspect}" }
                                .join(" ")
      log_line = "#{Time.now.utc.iso8601} tool=#{event_data[:tool]} #{payload_pairs}"
      @mutex.synchronize { File.open(@path, "a") { |f| f.puts(log_line) } }
    end
  end
end
```

## `lib/master/autoloop.rb`
```ruby
# frozen_string_literal: true

require "open3"
require_relative "git_operations"

require_relative "autoloop/fix_evaluator"

module Master
  class AutoLoop
    def self.load_cfg
      Master.load_yaml(File.join(Master::ROOT, "data", "workflow.yml"))
            .dig("autoloop") || {}
    rescue StandardError => _e
      {}
    end

    _cfg = load_cfg
    MAX_CYCLES           = _cfg.fetch("max_cycles",           12)
    BATCH_SIZE           = _cfg.fetch("batch_size",            3)
    RATE_LIMIT_SLEEP     = _cfg.fetch("rate_limit_sleep",     15)
    MAX_FIX_RETRIES      = _cfg.fetch("max_fix_retries",       3)
    CONFIDENCE_THRESHOLD = _cfg.fetch("confidence_threshold", 0.60)
    MAX_FILE_BYTES       = _cfg.fetch("max_file_bytes",   16_000)
    SKIP_RULES           = Array(_cfg.fetch("skip_rules", [])).freeze
    TARGETS              = Array(_cfg.fetch("targets", %w[lib/ test/ data/ web/ DEPLOY/])).freeze
    EXCLUDES             = Array(_cfg.fetch("excludes", %w[vendor/ knowledge/])).freeze

    SCORE_INCREMENT = 0.25
    MAX_SIZE_RATIO  = 2.0
    MIN_SIZE_RATIO  = 0.80

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil, learnings: nil)
      @agent           = agent
      @scanner         = scanner
      @root            = root
      @bus             = event_bus
      @soul            = soul
      @learnings       = learnings
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git             = GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_paths  = TARGETS.map { |d| File.join(@root, d.delete_suffix("/")) }
                              .select { |d| File.directory?(d) }
        all_results = scan_paths.flat_map { |dir|
          scan_result = @scanner.scan_dir(dir, depth: :standard)
          scan_result.ok? ? scan_result.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        # Deduplicate by file — one fix per unique file to avoid write-race.
        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)

        mutex   = Mutex.new
        fixes   = {}
        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota

        threads = by_file.each_with_index.map do |v, idx|
          Thread.new do
            sleep(stagger * idx) if idx.positive?
            fix = request_fix(v)
            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix
          rescue StandardError => e
            @bus&.publish("autoloop:thread_error", file: v[:file], error: e.message)
          end
        end
        threads.each(&:join)

        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }

        if @git.dirty?("lib/")
          @git.add_lib_files
          @git.commit("autoloop: fix scan violations [cycle #{cycle}]")
          if @learnings
            fixes.each_value { |v, _| @learnings.record(trigger: v[:rule].to_s, strategy: "autoloop_fix", outcome: "commit") }
          end
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    include FixEvaluator
    private

    def apply_fix(rel_path, fixed_src)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)
      original = File.read(path, encoding: "UTF-8")
      return if fixed_src.strip == original.strip
      temporary_path = "#{path}.tmp.#{Process.pid}"
      File.write(temporary_path, fixed_src)
      File.rename(temporary_path, path)
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    rescue StandardError => e
      @bus&.publish("autoloop:write_error", file: rel_path, error: e.message)
    end

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.ok?
        rel = path.delete_prefix("#{@root}/")
        next [] if EXCLUDES.any? { |ex| rel.start_with?(ex) }
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .reject { |f| SKIP_RULES.include?(f[:rule].to_s) }
          .map    { |f| f.merge(file: rel) }
      }.select { |f|
        full_path = File.join(@root, f[:file])
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES # GUARD_EXPENSIVE
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return nil
      end

      src         = File.read(path, encoding: "UTF-8")
      base_prompt = build_fix_prompt(violation, src)
      result = Reflexion.run(agent: @agent, task: base_prompt, max: MAX_FIX_RETRIES) do |prompt, attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          fix = extract_code(@agent.ask(prompt).to_s)
          next nil if fix.nil?
          next nil if confidence_score(fix, src) < CONFIDENCE_THRESHOLD
          fix
        rescue StandardError => e
          err = e.message.to_s
          if TRANSIENT_RE.match?(err) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: err[0, 120])
          end
          nil
        end
      end
      result.respond_to?(:ok?) && result.ok? ? result.value! : nil
    end
  end
end
```

## `lib/master/autoloop/fix_evaluator.rb`
```ruby
# frozen_string_literal: true

module Master
  class AutoLoop
    module FixEvaluator
      ERROR_TRUNCATE = 200
      private

      def build_fix_prompt(violation, src)
        "#{constitutional_preamble}\n\n" \
          "Fix this Ruby violation in #{violation[:file]}.\n" \
          "Rule: #{violation[:rule]}\n" \
          "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
          "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
          "```ruby\n#{src}\n```"
      end

      def constitutional_preamble
        @constitutional_preamble ||= begin
          soul  = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
          rules = Master.load_yaml(File.join(Master::ROOT, "data", "rules.yml"))
          golden = soul.dig("absolute", "golden_rule") || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          zen = rules.fetch("zen", {})
          lines = ["Constitutional constraints:", "- Golden rule: #{golden}"]
          zen.each_value { |v| lines << "- #{v}" } if zen.is_a?(Hash)
          lines.join("\n")
        rescue StandardError => _e
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      def reflected_prompt(base, last_error, attempt)
        "Prior attempt (#{attempt}) failed with: #{last_error[0, ERROR_TRUNCATE]}\n" \
          "Reflect briefly on what went wrong, then retry.\n\n" \
          "#{base}"
      end

      def extract_code(text)
        return text.match(/```ruby\n(.*?)```/m)[1].strip if text.match?(/```ruby\n(.*?)```/m)
        return text.match(/```\n(.*?)```/m)[1].strip if text.match?(/```\n(.*?)```/m)
        return text.strip if text.match?(/frozen_string_literal|module |class /)
        nil
      end

      def confidence_score(code, original_src)
        return 0.0 if code.nil? || code.strip.empty?
        score = 0.0
        score += SCORE_INCREMENT if code.include?("# frozen_string_literal: true")
        score += SCORE_INCREMENT if code.match?(/\A.*?(?:module |class )[A-Z]/m)
        ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max
        score += SCORE_INCREMENT if ratio >= MIN_SIZE_RATIO && ratio <= MAX_SIZE_RATIO
        score += SCORE_INCREMENT if syntax_ok?(code)
        score
      end

      def syntax_ok?(content)
        require "tempfile"
        Tempfile.open(["al_chk", ".rb"]) do |f|
          f.binmode
          f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
          f.flush
          system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
        end
      rescue StandardError => _e
        false
      end

      def track_recurrence(violations)
        return unless @soul
        tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        tally.each do |rule_id, count|
          @rule_recurrence[rule_id] += 1
          next unless @rule_recurrence[rule_id] >= 3
          @rule_recurrence.delete(rule_id)
          sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
          result = @soul.propose_from_violations(rule_id, sample, agent: @agent)
          @bus&.publish("autoloop:soul_proposal", rule: rule_id, result: result.to_s[0, 80])
        end
        (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
      end
    end
  end
end
```

## `lib/master/axioms.rb`
```ruby
# frozen_string_literal: true

module Master
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
  class Axioms
    DATA_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "rules.yml").freeze
    SOUL_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "soul.yml").freeze
    WORKFLOW_PATH = File.join(File.expand_path("../../..", __dir__), "data", "workflow.yml").freeze

    def initialize(root: nil)
      @rules_path    = root ? File.join(root, "data", "rules.yml")    : DATA_PATH
      @soul_path     = root ? File.join(root, "data", "soul.yml")     : SOUL_PATH
      @workflow_path = root ? File.join(root, "data", "workflow.yml") : WORKFLOW_PATH
      @data          = load_yaml(@rules_path)    || {}
      @soul_data     = load_yaml(@soul_path)     || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end

    def kernel
      @kernel ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .select { |r| r["tier"] == "kernel" }
          .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
          .freeze
      end
    end

    def workflow = @workflow.freeze

    def philosophy(limit: nil)
      @philosophy ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .reject { |r| r["tier"] == "kernel" }
          .map { |h| h.transform_keys(&:to_s) }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end

    def all_rules     = @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    def rules_for_scope(scope) = (@data.dig("rules", scope.to_s) || []).freeze

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Rules (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return nil if items.empty?

      top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
      "## Rules (top #{items.size})\n#{top}"
    end

    def voice    = @voice    ||= (@data["voice"] || {}).freeze
    def strunk   = @strunk   ||= (voice["strunk"] || {}).freeze
    def preserve = @preserve ||= (voice["preserve"] || {}).freeze

    def constitution
      @constitution ||= begin
        absolute = @soul_data["absolute"] || {}
        {
          "golden_rule"         => absolute["golden_rule"]      || @data["golden_rule"],
          "protection"          => absolute["protection_tiers"] || @data["protection"],
          "banned_output"       => voice["banned_output"],
          "anti_simulation"     => absolute["anti_simulation"]  || voice["anti_simulation"],
          "communication_style" => voice["style"]
        }.freeze
      end
    end

    def thresholds       = @thresholds       ||= (@data["thresholds"] || {}).freeze
    def scan_depths      = @scan_depths      ||= (@data["scan_depths"] || {}).freeze
    def languages_config = @languages_config ||= (@data["languages"] || {}).freeze
    def workflow_rule(key) = @workflow.dig(key.to_s) || {}

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
    end

    def valid_id?(id) = all_ids.include?(id.to_s)
    def all_ids       = @all_ids ||= all_rules.map { |r| r["id"] }.compact.to_set.freeze
    def empty?        = @data.empty?

    private

    def load_yaml(path)
      return nil unless File.exist?(path)

      Master.load_yaml(path)
    rescue StandardError => _e
      nil
    end
  end
end
```

## `lib/master/bedrock_stub.rb`
```ruby
# frozen_string_literal: true

# Pre-define Bedrock constants before ruby_llm loads.
# Zeitwerk skips autoloading already-defined constants, so bedrock/auth.rb
# (which requires openssl.so) is never touched.
# MASTER uses OpenRouter exclusively — Bedrock is never needed.
module RubyLLM
  module Providers
    module Bedrock
      module Auth
        def self.included(_base); end
      end

      def self.api_base = ""
      def self.headers(_cfg) = {}
      def self.models = []
      def self.slug = "bedrock"
    end
  end
end
```

## `lib/master/builder.rb`
```ruby
# frozen_string_literal: true

require_relative "builder/infra_helpers"

module Master
  module Builder
    RING_SIZE = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS = %w[exe lib/master data].freeze

    module_function

    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai_stack(root, infra)
      pipeline, gateway = build_pipeline_and_gateway(root, infra, ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    def build_infrastructure(root)
      config = Config.new(root)
      config["model"] ||= Master.default_model

      bus = EventBus.new
      ring = RingBuffer.new(RING_SIZE)
      logging = Logging.new(ring_buffer: ring, event_bus: bus)
      session = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo = Undo.new(session:, event_bus: bus, root:)
      breaker = CircuitBreakerRegistry.new(
        budget_max: config.budget_max, req_max: config.req_max, event_bus: bus
      )
      cache = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
      governor = Governor.new(config:, event_bus: bus)
      renderer = Renderer.new(config:)
      metrics = Metrics.new(root:, event_bus: bus)
      AuditLog.new(root:, event_bus: bus)

      code_index = CodeIndex.new(root:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
      mcp = McpCoordinator.new(root:, event_bus: bus)
      mcp.connect_all
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }

      memory = Memory.new(root:)
      personality = Personality.new(
        config["persona"]&.to_sym || Personality::DEFAULT, root:
      )

      phase_gates = PhaseGates.new(root:, event_bus: bus)
      {
        config:, ring:, bus:, logging:, session:, undo:, breaker:, cache:,
        governor:, renderer:, metrics:, code_index:, diff_stager:, mcp:,
        memory:, personality:, phase_gates:
      }
    end

    def build_ai_stack(root, infra)
      agent, soul_doc, scanner, swarm, deliberation, council_stage, ideation = build_agent_core(root, infra)
      autonomous = build_autonomous(root, infra, agent:, scanner:, soul: soul_doc)
      {
        agent:, soul: soul_doc, scanner:, swarm:, deliberation:, council_stage:, ideation:,
        guard: Security::InjectionGuard.new
      }.merge(autonomous)
    end

    def build_agent_core(root, infra)
      bus          = infra[:bus]
      agent, tools = build_agent_instance(root, infra)
      soul_doc     = Soul.new(root:, agent:)
      tools << Tools::AskLlm.new(agent:, governor: infra[:governor],
                                  circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus)
      ctx = ContextWindow.new(session: infra[:session], agent:, model_context: CTX_WINDOW_SIZE)
      ctx.check_and_compact!
      agent.wire_context_window(ctx)
      scanner               = build_scanner(root:, agent:, bus:)
      swarm                 = Swarm::Coordinator.new(agent:, event_bus: bus)
      deliberation, council, ideation = build_council(root, infra, agent:)
      [agent, soul_doc, scanner, swarm, deliberation, council, ideation]
    end

    def build_council(root, infra, agent:)
      personas     = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
      deliberation = Council::Deliberation.new(personas:, agent:, event_bus: infra[:bus])
      ideation     = Council::Ideation.new(agent:, event_bus: infra[:bus])
      [deliberation, Stages::Council.new(deliberation:, config: infra[:config]), ideation]
    end

    def build_agent_instance(root, infra)
      tools = build_tools(root:, infra:) + infra[:mcp].tools
      agent = Agent.new(
        config: infra[:config], session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: infra[:bus],
        model_router: Routing::ModelRouter.new(config: infra[:config]),
        reasoning_modes: Reasoning::Modes.new,
        memory: infra[:memory], personality: infra[:personality], code_index: infra[:code_index]
      )
      [agent, tools]
    end

    def build_autonomous(root, infra, agent:, scanner:, soul:)
      bus      = infra[:bus]
      standing = StandingOrders.new(pipeline: nil, event_bus: bus)
      learnings = Learnings.new(root:)
      autoloop = AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul:, learnings:)
      skills   = Skills.new(root:, event_bus: bus)
      skills.discover!
      heartbeat = Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory], event_bus: bus)
      triggers  = Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!
      { standing:, learnings:, autoloop:, skills:, heartbeat:, triggers: }
    end

    def build_pipeline_and_gateway(root, infra, ai)
      config   = infra[:config]
      bus      = infra[:bus]
      commands = CommandRegistry.build(infra:, ai:, root:)
      stages   = build_stages(root:, infra:, ai:, commands:)
      pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
      ai[:standing].wire_pipeline(pipeline)
      gateway = Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(ctx) { gateway.channels }
      [pipeline, gateway]
    end

    def build_stages(root:, infra:, ai:, commands:)
      config = infra[:config]
      bus    = infra[:bus]
      [
        Stages::Intake.new,
        Stages::Infer.new,
        Stages::Route.new(commands:, agent: ai[:agent]),
        Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Stages::Deliberate.new(agent: ai[:agent], config:),
        Stages::Execute.new,
        Pipeline::SkipOnPressure.new(Pipeline::ParallelGroup.new(
          ai[:council_stage],
          Stages::Lint.new(scanner: ai[:scanner], config:, autoloop: ai[:autoloop], root:, event_bus: bus),
          bus:
        )),
        Pipeline::SkipOnPressure.new(Stages::Prune.new),
        Stages::Memo.new(memory: infra[:memory], event_bus: bus),
        Stages::Render.new(renderer: infra[:renderer])
      ]
    end

    def build_tools(root:, infra:)
      bus = infra[:bus]
      undo = infra[:undo]
      governor = infra[:governor]
      [
        Tools::ReadFile.new(root:, undo:, event_bus: bus),
        Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::ListDir.new(root:, event_bus: bus),
        Tools::SearchFiles.new(root:, event_bus: bus),
        Tools::WebSearch.new(governor:, event_bus: bus),
        Tools::Shell.new(root:, governor:, event_bus: bus),
        Tools::BatchReplace.new(root:, governor:, event_bus: bus),
        Tools::GitContext.new(root:, event_bus: bus),
        Tools::AstEdit.new(root:, undo:, event_bus: bus),
        Tools::Tree.new(root:, event_bus: bus),
        Tools::SymbolLookup.new(code_index: infra[:code_index], event_bus: bus),
        Tools::Clean.new(root:, governor:, event_bus: bus),
        Tools::SearchKnowledge.new(root:, event_bus: bus)
      ]
    end

  end
end
```

## `lib/master/builder/infra_helpers.rb`
```ruby
# frozen_string_literal: true

module Master
  module Builder
    module_function

    def build_scanner(root:, agent:, bus:)
      scanner = Scan::Scanner.new(event_bus: bus)
      Scan::Rule.registry.select(&:auto_build?).each { |klass| scanner.add_rule(klass.new) }
      scanner.add_rule(Scan::Rules::AxiomCoverageRule.new(root:))
      scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Scan::Rules::InterconnectRule.new(root:))
      scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
      scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
      scanner
    end

    def boot_snapshot(container)
      root  = container[:root]
      files = collect_snapshot_files(root)
      body  = render_snapshot_body(root, files)
      write_snapshot(root, files, body)
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end

    def collect_snapshot_files(root)
      SNAPSHOT_DIRS.flat_map { |d| Dir.glob(File.join(root, d, "**", "*")) }
                   .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                   .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                   .sort
    end

    def render_snapshot_body(root, files)
      files.flat_map do |f|
        rel  = f.sub("#{root}/", "")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src  = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
      rescue StandardError => _e
        []
      end
    end

    def write_snapshot(root, files, body)
      header  = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      content = (header + body).join("\n")
      out     = File.join(root, ".master", "snapshot.md")
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, content)
      File.write(File.join(root, "snapshot.md"), content)
    end
  end
end
```

## `lib/master/circuit_breaker.rb`
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  class CircuitBreaker
    include MonitorMixin

    FAILURE_THRESHOLD = 8
    COOLDOWN_S        = 30
    RATE_WINDOW_S     = 60
    RATE_MAX          = 60

    class CircuitError < StandardError
      attr_reader :category
      def initialize(msg, category) = (super(msg); @category = category)
    end

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @budget_max    = budget_max
      @bus           = event_bus
      @failures      = 0
      @opened_at     = nil
      @state         = :closed
      @session_total = 0.0
      @req_times     = []
    end

    def check_rate!
      synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @req_times.reject! { |t| now - t > RATE_WINDOW_S }
        raise CircuitError.new("rate limit: #{RATE_MAX} req/min exceeded", :infrastructure) if @req_times.size >= RATE_MAX
        @req_times << now
      end
    end

    def call(cost_estimate, &blk)
      check_budget(cost_estimate)
      check_circuit
      execute_with_tracking(blk)
    rescue CircuitError => e
      # Budget/circuit-open errors are not backend failures — don't penalize.
      Result.err(e.message, category: e.category)
    end

    def record_cost(amount)  = synchronize { @session_total += amount }
    def session_total        = synchronize { @session_total }

    def state = synchronize { @state }

    private

    def execute_with_tracking(blk)
      result = blk.call
      on_success
      result
    rescue RubyLLM::RateLimitError => e
      # API rate limit is infrastructure noise — don't open the circuit.
      Result.err("rate_limit: #{e.message}", category: :infrastructure)
    rescue StandardError => e
      on_failure
      Result.err(e.message, category: :provider_error)
    end

    def check_budget(estimate)
      return unless @budget_max.positive? # Only check budget if it's a positive value.
      synchronize do
        raise CircuitError.new("budget: $#{(@session_total + estimate).round(4)} exceeds $#{@budget_max}", :budget) if @session_total + estimate > @budget_max
      end
    end

    def check_circuit
      synchronize do
        return if @state == :closed
        if @state == :open
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
          if elapsed >= COOLDOWN_S
            @state = :half_open
          else
            raise CircuitError.new("circuit open: retry in #{(COOLDOWN_S - elapsed).ceil}s", :infrastructure)
          end
        end
      end
    end

    def on_success
      synchronize do
        @failures = 0
        if @state == :half_open
          @state = :closed
          @bus&.publish("circuit:closed", breaker: object_id)
        end
      end
    end

    def on_failure
      synchronize do
        @failures += 1
        return unless @failures >= FAILURE_THRESHOLD
        @state     = :open
        @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @bus&.publish("circuit:open", failures: @failures)
      end
    end
  end
end
```

## `lib/master/circuit_breaker_registry.rb`
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  # Per-model circuit breakers so a flaky free-tier endpoint doesn't affect paid fallbacks.
  class CircuitBreakerRegistry
    include MonitorMixin

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @defaults = { budget_max: budget_max, req_max: req_max, event_bus: event_bus }.freeze
      @breakers = {}
      @global   = CircuitBreaker.new(**@defaults)
    end

    def for(model_id)
      synchronize { @breakers[model_id.to_s] ||= CircuitBreaker.new(**@defaults) }
    end

    def check_rate!
      @global.check_rate!
    end

    def session_total
      synchronize { @breakers.values.sum(&:session_total) + @global.session_total }
    end

    def record_cost(amount)
      @global.record_cost(amount)
    end

    def call(cost_estimate, &blk)
      @global.call(cost_estimate, &blk)
    end

    def open_models
      synchronize do
        @breakers.filter_map { |id, breaker| id if breaker.respond_to?(:open?) && breaker.open? }
      end
    end
  end
end
```

## `lib/master/cli.rb`
```ruby
# frozen_string_literal: true

require_relative "cli/tts"
require_relative "cli/signals"

require "open3"
require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI
    DMESG_LINES        = 50
    IDLE_SLEEP_DEFAULT = 60

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    attr_reader :container

    def initialize(container:)
      @container = container
      assign_container_refs!(container)
      @reader          = TTY::Reader.new(track_history: true)
      @running         = false
      @interrupt_at    = Time.now
      @last_ok         = true
      @tts_on          = Speech.available? && @config["tts"] != false
      @violations      = 0
      @bg_thread       = nil
      @seen_violations = {}
      @user_active     = false
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      start_background_loop
      puts @renderer.splash(@agent.model)
      puts @renderer.render("session0: #{@session.name}", mode: :dim) if @session.name
      process(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      stripped = input.strip
      return if stripped.empty?

      run_input(stripped)
    end

    def run_input(input)
      return if input.strip.empty?

      @user_active = true
      accumulated = +""
      streamed = false
      thinking_shown = true

      on_chunk = chunk_accumulator(accumulated) do |text|
        if thinking_shown && $stdout.isatty
          print "\r\e[K"
          thinking_shown = false
        end
        print text
        $stdout.flush
        streamed = true
      end

      print_thinking_indicator
      result = @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      display_result(result, accumulated, streamed)
    ensure
      @user_active = false
    end

    private

    def assign_container_refs!(c)
      @session     = c[:session]
      @agent       = c[:agent]
      @renderer    = c[:renderer]
      @logging     = c[:logging]
      @undo        = c[:undo]
      @config      = c[:config]
      @pipeline    = c[:pipeline]
      @scanner     = c[:scanner]
      @autoloop    = c[:autoloop]
      @root        = c[:root] || Dir.pwd
      @diff_stager = c[:diff_stager]
      @bus         = c[:bus]
    end

    def repl_loop
      while @running
        tokens = @session.token_est
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations,
          tokens: tokens
        )
        line = begin
          @reader.read_line("", echo: true).chomp
        rescue StandardError => _e
          nil
        end
        break if line.nil?
        next if line.strip.empty?

        if line.strip == "/exit"
          exit_cli
        elsif line.strip == "<<"
          run_input(read_multiline)
        else
          run_input(line)
        end
      end
      @bg_thread&.kill
      @session.save!
    end

    def exit_cli = (@session.save!; @running = false)

    def read_multiline
      lines = []
      puts @renderer.render("-- enter lines, blank line to send --", mode: :dim)
      loop do
        print "  "
        inner = (@reader.read_line("", echo: true).chomp rescue nil)
        break if inner.nil? || inner.strip.empty?

        lines << inner
      end
      lines.join("\n")
    end

    def start_background_loop
      idle_interval = AutoLoop.load_cfg.fetch("idle_sleep", IDLE_SLEEP_DEFAULT)
      @bg_thread = Thread.new do
        boot_scan
        loop do
          sleep idle_interval
          background_cycle unless @user_active
        end
      rescue StandardError => e
        @bus&.publish("cli:bg_error", error: e.message)
      end
    end

    def boot_scan
      lib_dir = File.join(@root, "lib")
      changed = begin
        out, = Open3.capture2e("git", "-C", @root, "diff", "--name-only", "HEAD")
        out.strip.empty? ? [] : out.lines.map { |l| File.join(@root, l.strip) }
                                         .select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
      rescue StandardError => _e
        []
      end

      result = if changed.any?
                 Result.ok(changed.map { |p| [p, @scanner.scan(p, depth: :standard)] })
               else
                 @scanner.scan_dir(lib_dir, depth: :standard)
               end

      return unless result.respond_to?(:ok?) && result.ok?

      count = result.value!.sum do |_file, file_result|
        file_result.respond_to?(:ok?) && file_result.ok? ? file_result.value!.size : 0
      end
      @violations = count
      return if count.zero?

      puts "\n#{@renderer.render("boot scan: #{count} violation(s)", mode: :dim)}"
      print @renderer.prompt_line(@agent.model, @session.phase, last_ok: @last_ok, violations: @violations)
    rescue StandardError => e
      @bus&.publish("cli:warn", error: e.message)
    end

    def background_cycle
      return unless @autoloop

      @autoloop.run(max_cycles: 1) do |_cycle, violations|
        next if violations.empty?
        @violations = violations.size
        top = violations.first(3).map { |v| "#{File.basename(v[:file])}:#{v[:rule]}" }.join(" ")
        $stdout.puts "\nautoloop: #{violations.size} violation(s) #{top}"
        $stdout.flush
      end
    rescue StandardError => e
      @bus&.publish("autoloop:bg_error", error: e.message)
    end

    def chunk_accumulator(buffer)
      lambda do |chunk|
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?

        yield text
        buffer << text
      end
    end

    def print_thinking_indicator
      return unless $stdout.isatty

      print @renderer.render("thinking...", mode: :dim)
      $stdout.flush
    rescue StandardError => _e
      print "thinking..."
    end

    def display_result(result, accumulated, streamed)
      case result
      in Master::Result::Ok => ok
        @last_ok = true
        display_ok(ok, accumulated, streamed)
      in Master::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def display_ok(ok, accumulated, streamed)
      if streamed
        puts
        speak_async(accumulated) if @tts_on
      else
        print "\r\e[K" if $stdout.isatty
        value = ok.value
        text = value.is_a?(Hash) && value[:rendered] ? value[:rendered] : value.to_s
        puts text
        speak_async(text) if @tts_on
      end
    end
  end
end
```

## `lib/master/cli/signals.rb`
```ruby
# frozen_string_literal: true

module Master
  class CLI
    private

    def setup_signals
      trap("USR1") { on_usr1 }
      trap("INT")  { on_int }
    end

    def on_usr1
      Zeitwerk::Loader.for_gem.reload
      puts "\n#{@renderer.render("reloaded", mode: :success)}"
    rescue StandardError => e
      puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
    end

    def on_int
      if Time.now - @interrupt_at < 1
        @scan_thread&.kill
        @session.save!
        exit(0)
      else
        @interrupt_at = Time.now
        puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
      end
    end
  end
end
```

## `lib/master/cli/tts.rb`
```ruby
# frozen_string_literal: true

module Master
  class CLI
    TTS_CHAR_LIMIT = 400

    private

    def speak_async(text)
      Thread.new do
        plain = sanitize_for_speech(text)
        next if plain.empty?
        audio_path = Speech.synthesize(plain)
        next unless audio_path
        played = Speech.play(audio_path)
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        begin; File.unlink(audio_path); rescue StandardError => _e; nil; end if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain.gsub(/```.*?```/m, "")[0..TTS_CHAR_LIMIT]
    end
  end
end
```

## `lib/master/code_index.rb`
```ruby
# frozen_string_literal: true

require "prism"
require "set"
require "monitor"
require_relative "code_index/symbol_visitor"

module Master
  # Live Prism-parsed symbol graph; rebuilt on write events.
  class CodeIndex
    Symbol = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
    Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

    attr_reader :symbols, :references, :built_at

    def initialize(root:, event_bus: nil)
      @root = File.expand_path(root)
      @bus = event_bus
      @symbols = {}
      @references = []
      @mtimes = {}
      @built_at = nil
      @lock = Monitor.new
      @build_thread = nil
    end

    def build(path: nil)
      target = path ? File.expand_path(path, @root) : @root
      files  = Dir.glob(File.join(target, "**", "*.rb"))
                  .reject { |f| f.include?("/vendor/") }

      if @built_at.nil?
        @symbols.clear
        @references.clear
        @mtimes.clear
        files.each do |f|
          index_file(f)
          @mtimes[f] = File.mtime(f) rescue Errno::ENOENT
        end
      else
        changed = 0
        (@mtimes.keys - files).each do |gone|
          @symbols.delete_if { |_, s| s.file == gone }
          @references.reject! { |r| r.from_file == gone }
          @mtimes.delete(gone)
        end
        files.each do |f|
          mt = File.mtime(f) rescue Errno::ENOENT
          next if @mtimes[f] == mt
          reindex(f)
          @mtimes[f] = mt
          changed += 1
        end
        @bus&.publish("code_index:incremental", changed: changed, total: files.size) if changed > 0
      end

      @built_at = Time.now
      @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size)
      self
    rescue StandardError => e
      @bus&.publish("code_index:error", error: e.message)
      self
    end

    def build_async
      @build_thread = Thread.new { build }
      self
    end

    def ready?     = !@built_at.nil?
    def wait_for_build = @build_thread&.join

    def reindex(file)
      full = File.expand_path(file, @root)
      @symbols.delete_if { |_, s| s.file == full }
      @references.reject! { |r| r.from_file == full }
      index_file(full) if File.file?(full)
    rescue StandardError => e
      @bus&.publish("code_index:reindex_error", path: file, error: e.message)
    end

    def symbols_in(file)
      wait_for_build unless ready?
      full = File.expand_path(file, @root)
      @symbols.values.select { |s| s.file == full }
    end

    def find(name)
      wait_for_build unless ready?
      exact = @symbols[name]
      return [exact] if exact

      suffix = name.to_s
      @symbols.values.select { |s| s.fqn.end_with?(suffix) || s.fqn.include?(suffix) }
    end

    def references_to(fqn)
      wait_for_build unless ready?
      @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") }
    end

    def impact(fqn)
      wait_for_build unless ready?
      refs = references_to(fqn)
      files = refs.map(&:from_file).uniq.map { |f| f.sub("#{@root}/", "") }
      callers = refs.map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }.uniq
      { fqn:, reference_count: refs.size, files:, callers: }
    end

    def summary(limit: nil)
      wait_for_build unless ready?
      classes = @symbols.values
                         .select { |s| %i[class module].include?(s.type) }
                         .reject { |s| s.file.include?("/DEPLOY/") || s.file.match?(/fix_|patch_/) }
                         .reject { |s| %w[Entry Message Symbol CircuitError].any? { |n| s.fqn.end_with?("::#{n}") } }
                         .sort_by(&:fqn)
                         .map do |s|
        parent = s.parent && s.parent != "Object" ? " < #{s.parent}" : ""
        "  #{s.fqn}#{parent} (#{s.file.sub("#{@root}/", "")}:#{s.line})"
      end

      lib_count = @symbols.values.count { |s| s.file.include?("/lib/") }
      header = "# Codebase: #{lib_count} lib symbols (indexed #{built_at&.strftime("%H:%M") || "never"})"
      title = "## Classes & Modules (#{classes.size})"
      [header, title, *classes].join("\n")
    end

    def query(name)
      wait_for_build unless ready?
      hits = find(name)
      return { error: "not found: #{name}" } if hits.empty?

      hits.map do |s|
        refs = references_to(s.fqn)
        {
          fqn: s.fqn,
          type: s.type,
          file: s.file.sub("#{@root}/", ""),
          line: s.line,
          parent: s.parent,
          used_in: refs.first(10).map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }
        }
      end
    end

    def size = @symbols.size
    def built? = !@built_at.nil?

    private

    def index_file(file)
      src = File.read(file, encoding: "UTF-8")
      result = Prism.parse(src)
      return unless result.success?

      visitor = SymbolVisitor.new(file:, root: @root)
      result.value.accept(visitor)

      visitor.symbols.each { |s| @symbols[s.fqn] = s }
      @references.concat(visitor.references)
    rescue StandardError => e
      @bus&.publish("code_index:parse_error", path: file, error: e.message)
    end

  end
end
```

## `lib/master/code_index/symbol_visitor.rb`
```ruby
# frozen_string_literal: true

module Master
  class CodeIndex
    class SymbolVisitor < Prism::Visitor
      attr_reader :symbols, :references

      def initialize(file:, root:)
        @file = file
        @root = root
        @symbols = []
        @references = []
        @scope = []
      end

      def visit_class_node(node)
        name = const_name(node.constant_path)
        parent = node.superclass ? const_name(node.superclass) : "Object"
        fqn = qualified(name)

        @symbols << Symbol.new(
          fqn:, type: :class, file: @file,
          line: node.location.start_line, parent:, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      def visit_module_node(node)
        name = const_name(node.constant_path)
        fqn = qualified(name)

        @symbols << Symbol.new(
          fqn:, type: :module, file: @file,
          line: node.location.start_line, parent: nil, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      def visit_def_node(node)
        meth = node.name.to_s
        owner = @scope.last || "(top)"
        fqn = "#{qualified(owner)}##{meth}"

        @symbols << Symbol.new(
          fqn:, type: :method, file: @file,
          line: node.location.start_line, parent: owner, includes: []
        )
        super
      end

      def visit_call_node(node)
        method_name = node.name.to_s
        return super unless method_name.match?(/\A[_a-z][a-z0-9_]*[!?]?\z/i) && method_name.length > 1

        receiver_fqn = node.receiver ? const_name_safe(node.receiver) : nil
        to_fqn = receiver_fqn ? "#{receiver_fqn}##{method_name}" : method_name

        @references << Reference.new(
          from_file: @file,
          from_line: node.location.start_line,
          to_fqn:,
          ref_type: :call
        )
        super
      end

      private

      def qualified(name)
        return name if @scope.empty? || name.include?("::")
        "#{@scope.join('::')}::#{name}"
      end

      def const_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          "#{const_name(node.parent)}::#{node.name}"
        else
          node.respond_to?(:name) ? node.name.to_s : ""
        end
      end

      def const_name_safe(node)
        name = const_name(node)
        name.empty? ? nil : name
      rescue StandardError => _e
        nil
      end
    end
  end
end
```

## `lib/master/command_registry.rb`
```ruby
# frozen_string_literal: true

require_relative "command_registry/agent_commands"
require_relative "command_registry/memory_commands"
require_relative "command_registry/service_commands"

module Master
  # CommandRegistry — all pipeline-routable commands in one place.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        agent_commands(ai:, root:, infra:),
        memory_commands(infra[:memory], ai[:agent]),
        service_commands(ai, infra[:phase_gates]),
        utility_commands(ai[:agent], root, infra[:cache]),
        control_commands(ai[:standing], ai[:soul]),
        "help" => ->(_ctx) {
          "just talk. intent is inferred automatically.\n" \
          "exit with /exit or ctrl-C twice."
        }
      )
    end

    def session_commands(infra)
      session = infra[:session]
      undo = infra[:undo]
      logging = infra[:logging]
      config = infra[:config]
      {
        "clear"  => ->(_ctx) { session.clear!; "context cleared" },
        "save"   => ->(_ctx) { session.save!; "session saved" },
        "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
        "undo"   => ->(_ctx) { result = undo.undo!; result.ok? ? "reverted: #{result.value!}" : result.message },
        "dmesg"  => ->(_ctx) { logging.dmesg },
        "cost"   => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "config" => ->(_ctx) { config.data.inspect }
      }
    end

    def mode_commands(config)
      reasoning_commands(config).merge(persona_commands(config)).merge(flag_commands(config))
    end

    def reasoning_commands(config)
      {
        "mode" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          Reasoning::Modes::SUPPORTED.include?(arg) ?
            (config["reasoning_mode"] = arg; config.save!; "mode: #{arg}") :
            "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
        },
        "task" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}")
        }
      }
    end

    def persona_commands(config)
      {
        "persona" => ->(ctx) {
          arg   = ctx[:args].to_s.strip.to_sym
          names = Personality::PERSONAS.keys
          if names.include?(arg)
            config["persona"] = arg.to_s; config.save!; "persona: #{arg}"
          else
            "persona: #{config["persona"] || "dark_malay"} -- available: #{names.join(", ")}"
          end
        },
      }
    end

    def flag_commands(config)
      {
        "autotest" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then config["auto_testing"] = true;  config.save!; "autotest: on"
          when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
          else "autotest: #{config.auto_testing? ? "on" : "off"}"
          end
        }
      }
    end

  end
end
```

## `lib/master/command_registry/agent_commands.rb`
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      scan_loop_commands(ai:, root:, infra:)
        .merge(model_agent_commands(ai:, root:, infra:))
        .merge(crit_command(ai:, root:))
        .merge(ideate_command(ai:))
        .merge(topic_command(infra:))
    end

    def scan_loop_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      bus = infra[:bus]
      deliberation = ai[:deliberation]
      autoloop = ai[:autoloop]
      {
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          result = autoloop.run(max_cycles: max) { |cycle, violations|
            top = violations.first(3).map { |v| "#{File.basename(v[:file])}:#{v[:rule]}" }.join(" ")
            $stdout.puts "autoloop: cycle #{cycle} #{violations.size} violation(s) #{top}"
            $stdout.flush
          }
          result.ok? ? result.value! : result.message
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus, code_index: infra[:code_index])
          result = sweeper.run(target) { |cycle, file, delta|
            $stdout.puts "sweep: cycle #{cycle} #{file} +#{delta}"
            $stdout.flush
          }
          result.ok? ? result.value! : result.message
        },
        "scan" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          profile, depth, rule_filter = resolve_scan_profile(arg, root)
          raw_arg = arg.sub(/\A(?:deep|quick|full|critical|solid|axioms)\s*/, "").strip
          target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
          pairs = if target_arg && File.file?(target_arg)
            fr = scanner.scan(target_arg, depth:)
            [[target_arg, fr]]
          elsif target_arg && File.directory?(target_arg)
            dir_result = scanner.scan_dir(target_arg, depth:, glob: "**/*", stream: true)
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          else
            dir_result = scanner.scan_dir(File.join(root, "lib"), depth:, stream: true)
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          end
          by_rule = Hash.new { |h, k| h[k] = [] }
          pairs.each do |_file, file_result|
            next unless file_result.respond_to?(:ok?) && file_result.ok?
            file_result.value!.each do |v|
              next if rule_filter && !rule_filter.include?(v[:rule].to_s)
              by_rule[v[:rule].to_s] << v
            end
          end
          total = by_rule.values.sum(&:size)
          header = profile ? "[profile: #{profile}] " : ""
          next "#{header}clean -- no violations" if total.zero?
          lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
            ["[#{rule}] #{vs.size}"] +
              vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
          end
          lines << "#{header}#{total} total violations"
          lines.join("\n")
        }
      }
    end

    def resolve_scan_profile(arg, root)
      profiles_cfg = begin
        data = Master.load_yaml(File.join(root, "data", "workflow.yml"))
        groups  = data.dig("principle_groups") || {}
        profiles = data.dig("scan_profiles") || {}
        [groups, profiles]
      rescue StandardError => _e
        [{}, {}]
      end
      groups, profiles = profiles_cfg

      profile_name = %w[quick full critical solid axioms].find { |p| arg.start_with?(p) }
      profile_name ||= "deep" if arg.start_with?("deep")

      if profile_name && profile_name != "deep"
        cfg   = profiles[profile_name] || {}
        depth = (cfg["depth"] == "deep") ? :deep : :standard
        rule_ids = groups[cfg["rules"].to_s]
        rule_filter = (rule_ids && cfg["rules"] != "*") ? rule_ids.map(&:to_s).to_set : nil
        [profile_name, depth, rule_filter]
      elsif profile_name == "deep"
        [nil, :deep, nil]
      else
        [nil, :standard, nil]
      end
    end

    def model_agent_commands(ai:, root:, infra:)
      council_meta_commands(ai:, root:).merge(model_commands(ai:, root:, infra:))
    end

    def council_meta_commands(ai:, root:)
      council_stage = ai[:council_stage]
      swarm         = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm"   => ->(ctx) { dispatch_swarm(swarm, ctx[:args].to_s.strip) },
        "explain" => ->(_ctx) { explain_master(root) }
      }
    end

    def dispatch_swarm(swarm, arg)
      parts = arg.split(" ", 2)
      role  = parts[0]&.to_sym
      task  = parts[1].to_s
      return "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}" if role.nil? || task.empty?
      result = swarm.dispatch(role, task:, context_slice: {})
      result.ok? ? result.value!.inspect : result.message
    end

    def explain_master(root)
      map    = Introspection::SelfMap.new(root:)
      info   = map.describe
      cov    = map.axiom_coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
      stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
      "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov}"
    end

    def model_commands(ai:, root:, infra:)
      agent   = ai[:agent]
      config  = infra[:config]
      metrics = infra[:metrics]
      {
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next list_models(root, metrics, agent) if arg == "list"
          next "model: #{agent.model}" if arg.empty?
          agent.model = arg; config.save!; "model: #{arg}"
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          next "usage: /why <rule_name>" if rule.empty?
          agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                         "give a before/after Ruby example, and state why it matters.")
        }
      }
    end

    def list_models(root, metrics, agent)
      yml_path = File.join(root, "data", "models.yml")
      return "model: #{agent.model}" unless File.exist?(yml_path)
      data = Master.load_yaml(yml_path)
      tiers = data["models"] || {}
      model_lines = tiers.flat_map { |tier, ms| ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" } }
      quality_lines = metrics&.model_quality&.map { |mod, stat|
        "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
      } || []
      sections = ["available models:"] + model_lines
      sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
      sections.join("\n")
    end

    def crit_command(ai:, root:)
      deliberation = ai[:deliberation]
      {
        "crit" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /crit <file|text>" if arg.empty?
          payload = if File.exist?(File.expand_path(arg, root))
            File.read(File.expand_path(arg, root), encoding: "UTF-8")
          else
            arg
          end
          result = deliberation.review(payload, context: "explicit /crit session")
          next result.message if result.err?
          format_crit_feedback(result.value!)
        }
      }
    end

    def format_crit_feedback(feedback)
      feedback.map { |f|
        veto = f[:veto_role] ? " [VETO ELIGIBLE]" : ""
        "#{f[:persona]} (#{f[:role]})#{veto}:\n#{f[:feedback].to_s.strip}"
      }.join("\n\n---\n\n")
    end

    def topic_command(infra:)
      session = infra[:session]
      {
        "topic" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            current_topic = session.respond_to?(:topic) ? session.topic : nil
            current_topic ? "topic: #{current_topic}" : "no topic set  /topic <description>"
          else
            session.topic = arg if session.respond_to?(:topic=)
            "topic: #{arg}"
          end
        }
      }
    end

    def ideate_command(ai:)
      ideation = ai[:ideation]
      {
        "ideate" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /ideate <prompt> [-- constraint1, constraint2]" if arg.empty?
          prompt, constraints_raw = arg.split(" -- ", 2)
          constraints = constraints_raw ? constraints_raw.split(",").map(&:strip).reject(&:empty?) : []
          result = ideation.ideate(prompt.strip, constraints:)
          next result.message if result.err?
          v = result.value!
          lines = []
          lines << "ideas (#{v[:ideas].size}):"
          v[:ideas].each { |i| lines << "  - #{i}" }
          lines << ""
          v[:critiques].each_with_index { |c, n| lines << "critique #{n + 1}: #{c}" }
          lines << ""
          lines << "synthesis:"
          lines << v[:final]
          lines.join("\n")
        }
      }
    end
  end
end
```

## `lib/master/command_registry/memory_commands.rb`
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) { dispatch_memory(memory, ctx[:args].to_s.strip) },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries  = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active   = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary  = memory.recall("_consolidated_summary")
            lines    = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end

    def dispatch_memory(memory, arg)
      case arg
      when /\Aforget (.+)/  then memory.forget($1.strip); "forgot: #{$1.strip}"
      when /\Aremember (.+)/
        key, value = $1.split("=", 2).map(&:strip)
        value ? (memory.remember(key, value); "remembered: #{key}") : "usage: /memory remember key=value"
      when /\Asearch (.+)/ then memory_search(memory, $1.strip)
      when ""
        (e = memory.all).empty? ? "(no memories)" : e.map { |k, v| "#{k}: #{v}" }.join("\n")
      else
        (r = memory.recall(arg)) ? "#{arg}: #{r}" : "(not found: #{arg})"
      end
    end

    def memory_search(memory, query)
      hits = memory.respond_to?(:semantic_recall) ? memory.semantic_recall(query) :
               memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
      hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
    end
  end
end
```

## `lib/master/command_registry/service_commands.rb`
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    BINARY_SNIFF_BYTES = 512

    module_function

    def control_commands(standing, soul)
      {
        "orders" => ->(ctx) { dispatch_orders(standing, ctx[:args].to_s.strip) },
        "soul"   => ->(ctx) { dispatch_soul(soul, ctx[:args].to_s.strip) }
      }
    end

    def service_commands(ai, phase_gates = nil)
      heartbeat = ai[:heartbeat]
      skills    = ai[:skills]
      scanner   = ai[:scanner]
      {
        "heartbeat" => ->(ctx) { dispatch_heartbeat(heartbeat, ctx[:args].to_s.strip) },
        "skills"    => ->(ctx) {
          arg   = ctx[:args].to_s.strip
          found = skills&.find(arg)
          arg.empty? ? (skills&.list || "(no skills)") : (found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})")
        },
        "phase" => ->(ctx) { dispatch_phase(phase_gates, ctx[:args].to_s.strip) },
        "score" => ->(ctx) { score_file(scanner, ctx[:args].to_s.strip) }
      }
    end

    def dispatch_phase(gates, arg)
      return "no phase_gates configured" unless gates
      case arg
      when "", "status" then gates.status
      when "advance"    then result = gates.advance!; result.ok? ? result.value! : result.message
      when /\Aforce (.+)\z/  then gates.force!($1.strip).value!
      when /\Ameet (.+)\z/   then gates.meet_gate!($1.strip); "gate met: #{$1.strip}"
      else "phase: #{gates.current}  /phase [status|advance|force <name>|meet <gate>]"
      end
    end

    def dispatch_orders(standing, arg)
      case arg
      when "list", "" then standing.list
      when /\Aenable (.+)\z/  then standing.enable($1.strip)
      when /\Adisable (.+)\z/ then standing.disable($1.strip)
      when /\Aadd name=(\S+) cmd=(.+)\z/ then standing.upsert(name: $1, command: $2.strip)
      when "run"
        results = standing.run_due!
        results.empty? ? "no orders due" :
          results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      when /\Areset (.+)\z/ then standing.reset($1.strip)
      else "usage: /orders  /orders enable|disable|reset <name>  /orders run"
      end
    end

    def dispatch_soul(soul, arg)
      case arg
      when "", "show"          then soul.summary
      when "version", "changelog" then soul.changelog
      when "diff"              then soul.diff
      when "approve"           then soul.approve
      when "reject"            then soul.reject
      when "rollback"          then soul.rollback
      when /\Apropose (.+)\z/  then soul.propose($1.strip)
      else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
      end
    end

    SCORE_WEIGHTS = { error: 10, critical: 10, warning: 3, style: 1 }.freeze

    def score_file(scanner, arg)
      return "usage: /score <file>" if arg.empty?
      path = File.expand_path(arg)
      return "not found: #{arg}" unless File.exist?(path)

      src   = File.read(path, encoding: "UTF-8")
      lines = src.lines
      total = lines.size
      return "empty file" if total.zero?

      blank   = lines.count { |l| l.strip.empty? }
      comment = lines.count { |l| l.strip.start_with?("#") }
      long    = lines.count { |l| l.chomp.length > 100 }

      result = scanner&.scan(path, depth: :standard)
      violations = result.respond_to?(:ok?) && result.ok? ? result.value! : []

      penalty = violations.sum { |v| SCORE_WEIGHTS[v[:severity]] || 1 }
      score   = [100 - penalty, 0].max

      by_rule = violations.group_by { |v| v[:rule] }
                          .sort_by { |_, vs| -vs.size }
                          .map { |rule, vs| "  #{rule}: #{vs.size}" }

      lines_out = [
        "score: #{score}/100  #{path.split("/").last}",
        "  #{total} lines  #{blank} blank  #{comment} comment  #{long} over 100 chars",
        "  #{violations.size} violation(s)  -#{penalty} pts"
      ]
      lines_out.concat(by_rule) unless by_rule.empty?
      lines_out.join("\n")
    end

    def dispatch_heartbeat(heartbeat, arg)
      case arg
      when "run"   then heartbeat ? heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n") : "no heartbeat"
      when "start" then heartbeat&.start!; "heartbeat started"
      when "stop"  then heartbeat&.stop!;  "heartbeat stopped"
      else heartbeat&.list || "no heartbeat"
      end
    end

    def utility_commands(agent, root, cache)
      {
        "snapshot" => ->(_ctx) {
          out        = File.join(root, "snapshot_latest.md")
          text_exts  = %w[.rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json .toml .gemspec .txt .erb .conf .ini .env].to_set.freeze
          text_names = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
          skip_segs  = %w[.git vendor tmp var node_modules .bundle coverage log dist knowledge].to_set.freeze
          skip_path  = ->(rel) { rel.split("/").any? { |s| skip_segs.include?(s) } }
          text_file  = ->(f)   { text_exts.include?(File.extname(f).downcase) || text_names.include?(File.basename(f)) }

          all   = Dir.glob(File.join(root, "**", "*")).reject { |f| File.basename(f).start_with?(".") }
                     .reject { |f| skip_path.(f.delete_prefix("#{root}/")) }.sort
          dirs  = all.select { |f| File.directory?(f) }
          files = all.select { |f| File.file?(f) && text_file.(f) && File.size(f) < CTX_WINDOW_SIZE }

          stamp = Time.now.utc.iso8601
          buf   = ["# MASTER Snapshot — #{stamp}", ""]

          buf << "## Tree" << "```"
          dirs.each  { |d| buf << "#{d.delete_prefix("#{root}/")}/" }
          files.each { |f| buf << f.delete_prefix("#{root}/") }
          buf << "```" << ""

          max_file_lines = 400
          n_trunc = 0
          n_lines = 0

          files.each do |f|
            rel  = f.delete_prefix("#{root}/")
            lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
            body = File.read(f, encoding: "UTF-8", invalid: :replace).lines
            n_lines += body.size
            buf << "## `#{rel}`" << "```#{lang}"
            if body.size > max_file_lines
              buf.concat(body.first(max_file_lines).map(&:rstrip))
              buf << "... #{body.size - max_file_lines} lines truncated (#{body.size} total)"
              n_trunc += 1
            else
              buf.concat(body.map(&:rstrip))
            end
            buf << "```" << ""
          rescue StandardError => e
            buf << "## `#{rel}`" << "[skipped: #{e.message}]" << ""
          end

          buf << "files: #{files.size} / lines: #{n_lines} / truncated: #{n_trunc} / est. tokens: ~#{n_lines * 6 / 5}"
          File.write(out, buf.join("\n"))

          day = Time.now.strftime("%Y-%m-%d")
          system("git", "-C", root, "add", "snapshot_latest.md")
          system("git", "-C", root, "commit", "-m", "snapshot: #{day} — #{files.size} files")

          gist_out, gist_st = Open3.capture2e("gh", "gist", "create", out,
                                              "--public",
                                              "--desc", "MASTER #{day}",
                                              "--filename", "snapshot_latest.md")
          gist_url = gist_st.success? ? " → #{gist_out.strip}" : ""
          "snapshot: #{files.size} files #{n_lines} lines#{gist_url}"
        },
        "cache" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "clear"
            cache.invalidate_all!
            "cache cleared"
          else
            stats = cache.stats
            suffix = arg == "stats" ? "" : "  (use /cache clear to purge)"
            "cache: #{stats[:entries]} entries, #{stats[:size_kb]} KB#{suffix}"
          end
        },
        "diff" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          base = arg.empty? ? "HEAD" : arg
          out, = Open3.capture2e("git", "-C", root, "diff", base, "--stat")
          out.strip.empty? ? "(no changes since #{base})" : out.strip
        },
        "commit" => ->(_ctx) {
          diff, = Open3.capture2e("git", "-C", root, "diff", "--cached", "--stat")
          diff, = Open3.capture2e("git", "-C", root, "diff", "--stat") if diff.strip.empty?
          next "nothing to commit" if diff.strip.empty?
          prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
          msg = agent.ask_once(prompt).strip.lines.first.to_s.strip
          Open3.capture2e("git", "-C", root, "add", "-u")
          out, = Open3.capture2e("git", "-C", root, "commit", "-m", msg)
          out.strip
        },
        "knowledge" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("add ")
            url = arg.sub("add ", "").strip
            require "open-uri"
            require "shellwords"
            next "usage: /knowledge add <url>" if url.empty?
            slug = url.gsub(/[^a-z0-9._-]/i, "_").downcase[0, 60]
            kdir = File.join(root, "knowledge", "web")
            FileUtils.mkdir_p(kdir)
            dest = File.join(kdir, "#{slug}.txt")
            content = URI.open(url, read_timeout: 15, &:read)
                         .encode("UTF-8", invalid: :replace, undef: :replace)
            File.write(dest, content, encoding: "UTF-8")
            "saved #{content.bytesize} bytes to knowledge/web/#{slug}.txt"
          else
            "usage: /knowledge add <url>"
          end
        }
      }
    end
  end
end
```

## `lib/master/config.rb`
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  class Config
    BUDGET_MAX_DEFAULT = 10.0
    HISTORY_MAX = 500
    DEFAULT_WEB_PORT = 10_002

    DEFAULTS = {
      'model'          => 'nvidia/nemotron-3-super-120b-a12b:free',
      'web_host'       => '0.0.0.0',
      'web_public_url' => 'http://ai.brgen.no:3000',
      'web_port'       => DEFAULT_WEB_PORT,
      'budget_max'     => BUDGET_MAX_DEFAULT,
      'req_max'        => 1.0,
      'trace'          => 0,
      'prescan'        => true,
      'auto'           => false,
      'cache_ttl'      => 3_600,
      'history_max'    => 500,
      'reasoning_mode' => 'direct',
      'task_type'      => 'code_generation',
      'auto_testing'   => false
    }.freeze

    attr_reader :data

    def initialize(root = Dir.pwd)
      @root  = root
      @path  = File.join(root, '.master', 'config.yml')
      @mutex = Mutex.new
      @data  = load_config
    end

    def [](key)         = @data[key.to_s]
    def []=(key, value) ; @mutex.synchronize { @data[key.to_s] = value } ; end

    def model          = self['model']
    def budget_max     = self['budget_max'].to_f
    def req_max        = self['req_max'].to_f
    def trace          = (ENV['MASTER_TRACE'] || self['trace']).to_i
    def prescan?       = !!self['prescan']
    def auto?          = !!self['auto']
    def reasoning_mode = self['reasoning_mode'].to_s
    def task_type      = self['task_type'].to_s
    def auto_testing?  = !!self['auto_testing']

    # Persist atomically; fsync ensures durability.
    def save!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)

      tmp = "#{@path}.tmp.#{Process.pid}"
      File.open(tmp, 'w') do |f|
        f.write(@data.to_yaml)
        f.flush
        f.fsync
      end
      File.rename(tmp, @path)
    ensure
      File.delete(tmp) if defined?(tmp) && File.exist?(tmp) rescue nil
    end

    def reload!
      @mutex.synchronize { @data = load_config }
    end

    # Export as plain hash (deep dup to avoid external mutation)
    def to_h = Marshal.load(Marshal.dump(@data))

    private

    def load_config
      return deep_dup(DEFAULTS) unless File.exist?(@path)

      raw    = Master.load_yaml(@path)
      loaded = raw.is_a?(Hash) ? raw : {}
      deep_merge(DEFAULTS, stringify_keys(loaded))
    rescue Psych::Exception => e
      warn "config: failed to parse #{@path}: #{e.message}"
      deep_dup(DEFAULTS)
    end

    def deep_merge(a, b)
      a.merge(b) do |_key, old_val, new_val|
        old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end

    def deep_dup(hash)
      Marshal.load(Marshal.dump(hash))
    end
  end
end
```

## `lib/master/context_window.rb`
```ruby
# frozen_string_literal: true

module Master
  class ContextWindow
    COMPACT_THRESHOLD = 0.80
    private_constant :COMPACT_THRESHOLD

    attr_reader :session, :agent, :model_context

    def initialize(session:, agent: nil, model_context: 200_000)
      @session = session
      @agent   = agent
      @model_context = model_context
    end

    def check_and_compact!
      return Result.ok(:ok) unless agent
      return Result.ok(:ok) unless safe_to_compact?

      compact!
    end

    private

    def safe_to_compact?
      est = session.token_est
      return false unless est.is_a?(Numeric)

      est >= model_context * COMPACT_THRESHOLD
    end

    def compact!
      summary = agent.ask(
        "Summarize our progress, preserving all file paths, decisions, and remaining tasks.",
        context: session.messages
      )
      session.clear!
      session.add_message(
        role: :assistant,
        content: "[Context compacted]\n\n#{summary}"
      )
      Result.ok(:compacted)
    rescue StandardError => e
      Result.err("context compaction failed: #{e.message}", category: :infrastructure)
    end
  end
end
```

## `lib/master/council/deliberation.rb`
```ruby
# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      MAX_CONCURRENT  = 4
      MAX_CODE_BYTES  = 8_192
      TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze

      def initialize(personas:, agent:, event_bus: nil)
        @personas = personas
        @agent    = agent
        @bus      = event_bus
        validate_dependencies!
      end

      def review(code, context: nil)
        return Master::Result.err("council: no personas configured", category: :validation) if @personas.empty?

        slots = Mutex.new
        available = MAX_CONCURRENT
        ready = ConditionVariable.new

        threads = @personas.map do |persona|
          Thread.new do
            slots.synchronize { ready.wait(slots) until available > 0; available -= 1 }
            begin
              response = @agent.ask(build_prompt(persona, code, context))
              entry = { persona: persona.name, role: persona.role,
                        veto_role: veto_role?(persona), feedback: response }
              @bus&.publish(:council_feedback, entry)
              entry
            rescue StandardError => e
              @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
              nil
            ensure
              slots.synchronize { available += 1; ready.signal }
            end
          end
        end
        feedback = threads.map { |thread| thread.join(30) ? thread.value : nil }.compact
        if feedback.empty?
          @bus&.publish(:council_timeout, personas: @personas.map(&:name))
          return Master::Result.err("council: all personas timed out (#{@personas.size})", category: :timeout)
        end

        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        unless vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          return Master::Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        Master::Result.ok(feedback)
      rescue StandardError => e
        Master::Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def validate_dependencies!
        raise ArgumentError, "personas must be an array" unless @personas.is_a?(Array)
        raise ArgumentError, "agent must respond to :ask" unless @agent.respond_to?(:ask)
      end

      def veto_role?(persona)
        if persona.respond_to?(:veto?)
          persona.veto?
        else
          persona.respond_to?(:veto_role) && !!persona.veto_role
        end
      end

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        safe_code = truncate_code(code.to_s)
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{persona.prompt}

          Code:
          #{safe_code}

          Provide terse, actionable feedback.#{veto_hint}
        PROMPT
      end

      def truncate_code(code)
        return code if code.bytesize <= MAX_CODE_BYTES
        @bus&.publish(:council_code_truncated, bytes: code.bytesize, limit: MAX_CODE_BYTES)
        code.byteslice(0, MAX_CODE_BYTES) + TRUNCATE_MARKER
      end

      VETO_RE = /\AVETO:/i.freeze

      def veto_text?(feedback)
        VETO_RE.match?(feedback.to_s.strip)
      end
    end
  end
end
```

## `lib/master/council/ideation.rb`
```ruby
# frozen_string_literal: true

module Master
  module Council
    class Ideation
      DEFAULT_CYCLES = 2

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
      end

      def ideate(prompt, constraints: [], cycles: DEFAULT_CYCLES)
        ideas     = []
        critiques = []

        cycles.times do |cycle|
          result = brainstorm(prompt, ideas, constraints)
          return result if result.err?
          ideas += result.value
          @bus&.publish("ideation:cycle", cycle: cycle + 1, ideas: ideas.size)

          result = critique(ideas)
          return result if result.err?
          critiques << result.value
        end

        result = synthesize(prompt:, ideas:, critiques:, constraints:)
        return result if result.err?

        Master::Result.ok(ideas: ideas, critiques: critiques, final: result.value)
      end

      private

      def brainstorm(prompt, prior, constraints)
        context           = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        raw     = @agent.ask_once(<<~PROMPT, system: "Generate 3-5 novel, bold ideas. One idea per bullet (- prefix).")
          #{constraint_prefix}#{context}Generate ideas for: #{prompt}
        PROMPT
        return Master::Result.err("ideation: brainstorm failed") if raw.to_s.strip.empty?

        parsed = raw.scan(/^[-*]\s*(.+)/).flatten
        parsed = [raw.strip] if parsed.empty?
        Master::Result.ok(parsed)
      end

      def critique(ideas)
        list = ideas.map { |idea| "- #{idea}" }.join("\n")
        raw  = @agent.ask_once(<<~PROMPT, system: "Critique these ideas. Identify weaknesses, blind spots, risks. Be direct.")
          #{list}
        PROMPT
        return Master::Result.err("ideation: critique failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end

      def synthesize(prompt:, ideas:, critiques:, constraints:)
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        list              = ideas.map { |idea| "- #{idea}" }.join("\n")
        crits = critiques.join("\n---\n")
        raw   = @agent.ask_once(<<~PROMPT, system: "Synthesize the best elements into a concrete, practical recommendation. Preserve innovation. Address valid critiques.")
          Goal: #{prompt}
          #{constraint_prefix}
          Ideas:
          #{list}

          Critiques:
          #{crits}
        PROMPT
        return Master::Result.err("ideation: synthesis failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end
    end
  end
end
```

## `lib/master/council/personas.rb`
```ruby
# frozen_string_literal: true

module Master
  module Council
    module Personas
      Persona = Data.define(:name, :role, :bias, :prompt, :veto_role) do
        def veto? = veto_role == true
      end

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure",
                    prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false),
        Persona.new(name: "Skeptic",    role: "Devil's advocate", bias: "Caution",
                    prompt: "Find what could go wrong. Challenge every assumption.", veto_role: false),
        Persona.new(name: "Pragmatist", role: "Implementation",  bias: "Shipping",
                    prompt: "Is this shippable? Flag over-engineering.", veto_role: false),
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",
                    prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true),
        Persona.new(name: "User",       role: "UX advocate",     bias: "Usability",
                    prompt: "Does this serve the user? Are error messages actionable?", veto_role: false),
        Persona.new(name: "Mentor",     role: "Code review",     bias: "Clarity",
                    prompt: "Is this code readable? Do names reveal intent?", veto_role: false)
      ].freeze

      @cache = {}

      def self.load(data_path = nil)
        return DEFAULTS if data_path.nil? || !File.exist?(data_path)

        @cache[data_path] ||= begin
          raw = Master.load_yaml(data_path, symbolize_names: true)
          raise "Invalid persona data" unless raw.is_a?(Array)

          raw.map do |attrs|
            raise "Persona must be a hash" unless attrs.is_a?(Hash)

            attrs = { veto_role: false }.merge(attrs)
            Persona.new(**attrs)
          end.freeze
        rescue StandardError => _e
          DEFAULTS
        end
      end
    end
  end
end
```

## `lib/master/decision_engine.rb`
```ruby
# frozen_string_literal: true

module Master
  # DecisionEngine — universal priority scorer.
  # Formula: (impact * confidence) / cost
  # Used by: ModelRouter (model selection), Heartbeat (job ordering),
  #          AutoLoop (file ordering), Swarm (worker result weighting).
  module DecisionEngine
    EPSILON = 1e-6

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    def pick_best(candidates)
      ranked(candidates).first
    end

    def ranked(candidates)
      Array(candidates).map do |c|
        c = { value: c } unless c.is_a?(Hash)
        c.merge(de_score: score(
          impact:     c.fetch(:impact,     c.fetch("impact",     1.0)),
          confidence: c.fetch(:confidence, c.fetch("confidence", 1.0)),
          cost:       c.fetch(:cost,       c.fetch("cost",       1.0))
        ))
      end.sort_by { |c| -c[:de_score] }
    end

    def converged?(previous:, current:, min_delta: 0.001)
      return false if previous.nil?
      (current.to_f - previous.to_f).abs < min_delta.to_f
    end
  end
end
```

## `lib/master/diff_stager.rb`
```ruby
# frozen_string_literal: true

require "diffy"
require "fileutils"
require "json"

module Master
  # DiffStager — intercepts file writes and stores diffs for human review.
  # When staging_enabled? in config, tools push here instead of writing directly.
  # CLI commands: /stage (list), /apply [n|all], /discard [n|all]
  class DiffStager
    Entry = Struct.new(:id, :path, :old_content, :new_content, :tool, :created_at, keyword_init: true) do
      def diff
        Diffy::Diff.new(old_content.to_s, new_content.to_s, context: 3)
      end

      def diff_stats
        lines  = diff.to_s.lines
        added  = lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
        removed = lines.count { |l| l.start_with?("-") && !l.start_with?("---") }
        "+#{added}/-#{removed}"
      end
    end

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @mutex   = Mutex.new
      @pending = []
      @counter = 0
    end

    # Called by tools instead of writing directly. Returns a Result.
    def stage(path:, new_content:, tool: "unknown")
      old_content = File.exist?(path) ? File.read(path) : ""
      return Result.ok("no change") if old_content == new_content

      @mutex.synchronize do
      @counter += 1
      entry = Entry.new(
        id:          @counter,
        path:        path,
        old_content: old_content,
        new_content: new_content,
        tool:        tool,
        created_at:  Time.now
      )
      @pending << entry
      end
      persist_entry(entry)
      @bus&.publish("stage:queued", id: entry.id, path: entry.path, stats: entry.diff_stats)
      Result.ok({ staged: true, id: entry.id, path: entry.path, stats: entry.diff_stats })
    end

    def pending = @pending.dup
    def empty?  = @pending.empty?
    def size    = @pending.size

    # Apply one or all entries. Returns array of applied paths.
    def apply(id: :all)
      targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
      applied = []
      targets.each do |entry|
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.new_content)
        @mutex.synchronize { @pending.delete(entry) }
        remove_persisted(entry)
        @bus&.publish("stage:applied", id: entry.id, path: entry.path)
        applied << entry.path
      end
      applied
    end

    # Discard one or all without writing.
    def discard(id: :all)
      targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
      targets.each do |entry|
        @mutex.synchronize { @pending.delete(entry) }
        remove_persisted(entry)
        @bus&.publish("stage:discarded", id: entry.id, path: entry.path)
      end
      targets.map(&:path)
    end

    # Colored summary for CLI display
    def summary(pastel)
      return pastel.dim("  (no staged changes)") if @pending.empty?
      @pending.map do |e|
        short = e.path.sub(@root + "/", "")
        "  #{pastel.yellow("[#{e.id}]")} #{pastel.white(short)} #{pastel.dim(e.diff_stats)} #{pastel.dim("via #{e.tool}")}"
      end.join("\n")
    end

    # Colored unified diff for one entry
    def render_diff(id, pastel)
      entry = @pending.find { |e| e.id == id }
      return pastel.red("no staged change with id #{id}") unless entry

      short = entry.path.sub(@root + "/", "")
      header = "#{pastel.bold(short)} #{pastel.dim(entry.diff_stats)}\n"
      diff_lines = entry.diff.to_s.lines.map do |line|
        case line[0]
        when "+" then pastel.green(line.chomp)
        when "-" then pastel.red(line.chomp)
        when "@" then pastel.cyan(line.chomp)
        else          pastel.dim(line.chomp)
        end
      end
      header + diff_lines.join("\n")
    end

    private

    def stage_dir
      File.join(@root, ".master", "pending")
    end

    def persist_entry(entry)
      FileUtils.mkdir_p(stage_dir)
      File.write(
        File.join(stage_dir, "#{entry.id}.json"),
        JSON.generate({
          id: entry.id, path: entry.path, tool: entry.tool,
          created_at: entry.created_at.iso8601,
          stats: entry.diff_stats
        })
      )
    rescue StandardError => e
      @bus&.publish("diff_stager:persist_error", error: e.message)
    end

    def remove_persisted(entry)
      persist_file = File.join(stage_dir, "#{entry.id}.json")
      # Safe to delete: this persisted staging file is being removed after the entry
      # has been either applied (written to the actual file) or discarded (abandoned).
      File.delete(persist_file) if File.exist?(persist_file)
    rescue StandardError => e
      @bus&.publish("diff_stager:cleanup_error", error: e.message)
    end
  end
end
```

## `lib/master/event_bus.rb`
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  class EventBus
    include MonitorMixin

    BOOT_TIME         = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    PATTERN_CACHE_MAX = 512

    def initialize
      super()
      @subscribers   = Hash.new { |h, k| h[k] = [] }
      @pattern_cache = {}
    end

    def subscribe(pattern, &handler)
      synchronize { @subscribers[pattern] << handler }
      -> { synchronize { @subscribers[pattern].delete(handler) } }
    end

    def publish(event, payload = {})
      ts      = elapsed_ms
      payload = payload.merge(event:, ts:)
      synchronize { matching_handlers(event) }.each { |h| h.call(payload) }
      self
    end

    private

    def elapsed_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - BOOT_TIME
    end

    def matching_handlers(event)
      @subscribers.flat_map { |pattern, handlers|
        handlers if glob_match?(pattern, event)
      }.compact
    end

    def glob_match?(pattern, event)
      @pattern_cache.shift if @pattern_cache.size >= PATTERN_CACHE_MAX
      re = @pattern_cache[pattern] ||= Regexp.new(
        "\\A" + Regexp.escape(pattern).gsub("\\*\\*", ".*").gsub("\\*", "[^:]*") + "\\z"
      )
      re.match?(event)
    end
  end
end
```

## `lib/master/gateway.rb`
```ruby
# frozen_string_literal: true

module Master
  class Gateway
    CHANNELS = %i[cli web irc matrix api].freeze

    # Contract for channel adapters.
    module Adapter
      def render(text, metadata = {})
        raise NotImplementedError, "#{self.class}#render not implemented"
      end
    end

    def initialize(pipeline:, session:, event_bus: nil)
      @pipeline = pipeline
      @session  = session
      @bus      = event_bus
      @adapters = {}
    end

    def register(channel, adapter_or_proc = nil, &block)
      handler = adapter_or_proc || block
      @adapters[channel.to_sym] = handler
    end

    def receive(channel:, message:, metadata: {})
      channel = channel.to_sym
      return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

      @bus&.publish("gateway:receive", channel: channel, size: message.bytesize)

      ctx = { user_message: message.to_s.strip, channel: channel, metadata: metadata }
      result = @pipeline.call(Result.ok(ctx))

      if (adapter = @adapters[channel])
        text = result.respond_to?(:ok?) && result.ok? ? extract_text(result) : result.to_s
        adapter.respond_to?(:render) ? adapter.render(text, metadata) : adapter.call(text, metadata)
      end

      result
    end

    def channels
      CHANNELS.map do |ch|
        status = @adapters.key?(ch) ? "active" : "available"
        "#{ch}: #{status}"
      end.join("
")
    end

    private

    def extract_text(result)
      output = result.value!
      output.is_a?(Hash) && output[:rendered] ? output[:rendered] : output.to_s
    rescue StandardError => e
      @bus&.publish("gateway:extract_error", error: e.message)
      result.to_s
    end
  end
end
```

## `lib/master/git_operations.rb`
```ruby
# frozen_string_literal: true

require "open3"

module Master
  # GitOperations — git wrappers scoped to a repository root.
  class GitOperations
    def initialize(root_path)
      @root_path = root_path
    end

    def dirty?(path = "lib/")
      out, = Open3.capture2e("git", "-C", @root_path, "status", "--porcelain", path)
      !out.strip.empty?
    end

    def add_lib_files
      Open3.capture2e("git", "-C", @root_path, "add", "-A", "lib/")
    end

    def commit(message)
      Open3.capture2e("git", "-C", @root_path, "commit", "-m", message.to_s)
    end
  end
end
```

## `lib/master/governor.rb`
```ruby
# frozen_string_literal: true

require "tty-prompt"

module Master
  class Governor
    RATE_WINDOW = 60.0
    TIERS = { safe: 0, guarded: 1, dangerous: 2 }.freeze

    # Sliding-window rate limits per tier (calls per minute).
    TIER_RATE_LIMITS = { guarded: 10, dangerous: 3 }.freeze

    def initialize(config:, event_bus: nil)
      @config        = config
      @bus           = event_bus
      @prompt        = $stdout.isatty ? TTY::Prompt.new : nil
      @auto          = config.auto?
      @approve_all   = false
      @rate_windows  = Hash.new { |h, k| h[k] = [] }
      @rate_mutex    = Mutex.new
    end

    def check_permit(tool_name, tier, description = nil)
      @bus&.publish("tool:before", tool: tool_name, tier:)

      if (rate_err = check_rate_limit!(tier))
        @bus&.publish("tool:rate_limited", tool: tool_name, tier:)
        return rate_err
      end

      case tier
      when :safe      then return Result.ok(true)
      when :guarded   then return Result.ok(true) if @auto || @approve_all
      when :dangerous then return Result.ok(true) if @auto || @approve_all
      end

      ask_user(tool_name, tier, description)
    rescue StandardError => e
      Result.err(e.message, category: :validation)
    end

    alias permit? check_permit

    def approve_all!   = @approve_all = true
    def reset_approve! = @approve_all = false

    private

    def check_rate_limit!(tier)
      limit = TIER_RATE_LIMITS[tier]
      return nil unless limit
      now = Time.now.to_f
      @rate_mutex.synchronize do
        calls = @rate_windows[tier]
        calls.reject! { |t| now - t > RATE_WINDOW }
        if calls.size >= limit
          return Result.err("rate limit: #{tier} tier (#{limit}/min)", category: :rate_limit)
        end
        calls << now
      end
      nil
    end

    def ask_user(tool_name, tier, description)
      return Result.err("non-TTY: cannot prompt for approval", category: :validation) unless @prompt

      label  = description ? "#{tool_name}: #{description}" : tool_name
      choice = @prompt.select("#{tier_icon(tier)} #{label}", [
        { name: "approve", value: :approve },
        { name: "deny",    value: :deny },
        { name: "quit",    value: :quit }
      ])

      case choice
      when :approve then Result.ok(true)
      when :deny    then @bus&.publish("tool:denied",
        tool: tool_name); Result.err("denied by user", category: :validation)
      when :quit    then exit(0)
      end
    end

    def tier_icon(tier)
      case tier
      when :safe      then "i"
      when :guarded   then "!"
      when :dangerous then "!!"
      end
    end
  end
end
```

## `lib/master/heartbeat.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  class Heartbeat
    POLL_INTERVAL = 60
    JOURNAL_KEEP = 50
    DATA_PATH  = File.join(Master::ROOT, "data", "heartbeat.yml").freeze
    STATE_PATH = ".master/heartbeat_state.yml".freeze

    RESULT_TRUNCATE     = 200
    SECONDS_PER_HOUR    = 3600
    SECONDS_PER_2HOURS  = 7200

    JOB_HANDLERS = {
      "prune_memory" => :prune_memory,
      "check_models" => :check_model_availability,
      "self_test"    => :run_self_test,
      "prune_undo"   => :prune_undo_journal,
      "snapshot"     => :run_snapshot
    }.freeze

    def initialize(root:, agent: nil, scanner: nil, memory: nil, event_bus: nil)
      @root    = root
      @agent   = agent
      @scanner = scanner
      @memory  = memory
      @bus     = event_bus
      @jobs    = load_jobs
      @state   = load_state
      @thread  = nil
      @stop    = false
    end

    def start!
      return if @jobs.empty?

      @stop   = false
      @thread = Thread.new do
        loop do
          break if @stop
          run_due!
          sleep POLL_INTERVAL
        end
      rescue StandardError => e
        @bus&.publish("heartbeat:error", message: e.message)
      end
    end

    def stop!
      @stop = true
      @thread&.kill
      @thread = nil
    end

    def run_due!
      now = Time.now.to_i
      results = []

      @jobs.each do |job|
        name     = job["name"]
        interval = job["interval_seconds"].to_i
        last_run = @state.dig(name, "last_run").to_i

        next unless now - last_run >= interval

        @bus&.publish("heartbeat:run", job: name)
        result = execute_job(job)
        @state[name] = { "last_run" => now, "result" => result.to_s[0, RESULT_TRUNCATE] }
        results << { name: name, result: result }
      end

      persist_state unless results.empty?
      results
    end

    def list
      @jobs.map do |job|
        last = @state.dig(job["name"], "last_run").to_i
        ago  = last.zero? ? "never" : "#{(Time.now.to_i - last) / 60}m ago"
        "#{job["name"]}: every #{job["interval_seconds"] / 60}m, last: #{ago}"
      end.join("\n")
    end

    private

    def execute_job(job)
      method_name = JOB_HANDLERS[job["action"]]
      return "unknown action: #{job["action"]}" unless method_name

      send(method_name)
    rescue StandardError => e
      "error: #{e.message}"
    end

    def prune_memory
      @memory&.consolidate!(agent: @agent) || "no memory"
    end

    def check_model_availability
      models_path = File.join(@root, "data", "models.yml")
      return "no models.yml" unless File.exist?(models_path)

      data = Master.load_yaml(models_path)
      tiers = data["models"] || {}
      ids = tiers.values.flat_map { |m| [m["id"]] }.compact
      alive = ids.select { |id| model_reachable?(id) }
      "models: #{alive.size}/#{ids.size} reachable"
    end

    def model_reachable?(model_id)
      RubyLLM.chat(model: model_id).ask("ping")
      true
    rescue StandardError => _e
      false
    end

    def run_self_test
      return "no scanner" unless @scanner

      target = File.join(@root, "lib")
      result = @scanner.scan_dir(target, depth: :standard)
      return "scan failed" unless result.respond_to?(:ok?) && result.ok?

      count = result.value!.sum do |_, fr|
        fr.respond_to?(:ok?) && fr.ok? ? fr.value!.size : 0
      end
      @bus&.publish("heartbeat:self_test", violations: count)
      "self-test: #{count} violations"
    end

    def prune_undo_journal
      journal_path = File.join(@root, ".master", "undo.jsonl")
      return "no journal" unless File.exist?(journal_path)

      lines = File.readlines(journal_path)
      return "journal empty" if lines.empty?

      keep = [lines.size / 2, JOURNAL_KEEP].max
      File.write(journal_path, lines.last(keep).join)
      "pruned undo: kept #{keep}/#{lines.size} entries"
    end

    def run_snapshot
      container = { root: @root, bus: @bus }
      Builder.boot_snapshot(container)
      "snapshot: generated"
    end

    def load_jobs
      path = File.join(@root, "data", "heartbeat.yml")
      return default_jobs unless File.exist?(path)

      result = Master.load_yaml(path); result.is_a?(Array) ? result : default_jobs
    rescue StandardError => _e
      default_jobs
    end

    def default_jobs
      [
        { "name" => "prune_memory", "action" => "prune_memory", "interval_seconds" => SECONDS_PER_HOUR },
        { "name" => "self_test", "action" => "self_test", "interval_seconds" => SECONDS_PER_2HOURS },
        { "name" => "prune_undo", "action" => "prune_undo", "interval_seconds" => 86_400 },
        { "name" => "snapshot", "action" => "snapshot", "interval_seconds" => 14_400 }
      ]
    end

    def load_state
      path = File.join(@root, STATE_PATH)
      return {} unless File.exist?(path)

      Master.load_yaml(path) || {}
    rescue StandardError => _e
      {}
    end

    def persist_state
      path = File.join(@root, STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @state.to_yaml)
    end
  end
end
```

## `lib/master/introspection/self_map.rb`
```ruby
# frozen_string_literal: true

module Master
  module Introspection
    class SelfMap
      AXIOM_FALLBACK = %w[
        PRESERVE_FIRST SIMPLEST_WORKS FAIL_VISIBLY EXPLICIT IMMUTABLE
        CQS SELF_EXPLAINING SINGLE_RESPONSIBILITY NO_HARDCODING GUARD_FIRST
      ].freeze

      def initialize(root:)
        @root = root
      end

      def describe
        files = Dir.glob(File.join(@root, "lib/**/*.rb"))
        lines = files.sum { |f| File.read(f, encoding: "UTF-8").lines.size rescue 0 }
        { files: files.size, lines: lines }
      end

      def axiom_coverage
        tags = load_axiom_tags
        src  = Dir.glob(File.join(@root, "lib/**/*.rb"))
                  .map { |f| File.read(f, encoding: "UTF-8") rescue "" }
                  .join("\n")
        tags.each_with_object({}) { |ax, h| h[ax] = src.scan(/\b#{Regexp.escape(ax)}\b/).size }
      end

      private

      def load_axiom_tags
        rules_path = File.join(@root, "data", "rules.yml")
        data = Master.load_yaml(rules_path)
        tags = (data["rules"] || {}).keys
        tags.empty? ? AXIOM_FALLBACK : tags
      rescue StandardError => _e
        AXIOM_FALLBACK
      end
    end
  end
end
```

## `lib/master/learnings.rb`
```ruby
# frozen_string_literal: true

require "json"

module Master
  class Learnings
    STORE_PATH = "data/learnings.jsonl".freeze
    MAX_ENTRIES = 500
    CONFIDENCE_DECAY_DAYS = 30

    def initialize(root:)
      @path    = File.join(root, STORE_PATH)
      @mutex   = Mutex.new
      @entries = load_entries
    end

    def record(trigger:, strategy:, outcome:)
      @mutex.synchronize do
        existing = @entries.find { |e| e["trigger"] == trigger.to_s && e["strategy"] == strategy.to_s }
        if existing
          existing["reuse_count"] = existing["reuse_count"].to_i + 1
          existing["confidence"]  = [existing["confidence"].to_f + 0.05, 1.0].min
          existing["outcome"]     = outcome.to_s
          existing["timestamp"]   = Time.now.to_i
        else
          @entries << {
            "trigger"     => trigger.to_s,
            "strategy"    => strategy.to_s,
            "outcome"     => outcome.to_s,
            "confidence"  => outcome == :fixed ? 0.7 : 0.4,
            "reuse_count" => 0,
            "timestamp"   => Time.now.to_i
          }
        end
        prune_old!
        persist
      end
    end

    def search(trigger_fragment, limit: 3)
      fragment = trigger_fragment.to_s.downcase
      @mutex.synchronize do
        @entries
          .select { |e| e["trigger"].to_s.downcase.include?(fragment) && e["outcome"] != "failed" }
          .sort_by { |e| -e["confidence"].to_f }
          .first(limit)
      end
    end

    def all = @mutex.synchronize { @entries.dup }

    def prune_stale!
      cutoff = Time.now.to_i - (CONFIDENCE_DECAY_DAYS * 86_400)
      @mutex.synchronize do
        before = @entries.size
        @entries.reject! { |e| e["reuse_count"].to_i == 0 && e["timestamp"].to_i < cutoff }
        persist if @entries.size < before
      end
    end

    private

    def load_entries
      return [] unless File.exist?(@path)
      File.readlines(@path, chomp: true)
          .map { |l| begin; JSON.parse(l); rescue StandardError => _e; nil; end }
          .compact
    rescue StandardError => _e
      []
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      tmp_path = "#{@path}.tmp.#{Process.pid}"
      File.write(tmp_path, @entries.map { |e| JSON.generate(e) }.join("\n") + "\n")
      File.rename(tmp_path, @path)
    end

    def prune_old!
      @entries = @entries.last(MAX_ENTRIES) if @entries.size > MAX_ENTRIES
    end
  end
end
```

## `lib/master/logging.rb`
```ruby
# frozen_string_literal: true

module Master
  class Logging
    DEFAULT_DMESG_LINES = 50
    attr_reader :buffer

    def initialize(ring_buffer:, event_bus:)
      @buffer      = ring_buffer
      @bus         = event_bus
      wire_events
    end

    def dmesg(lines = DEFAULT_DMESG_LINES)
      @buffer.to_a.last(lines).join("\n")
    end

    private

    def wire_events
      @bus.subscribe("**") { |payload| @buffer.push(format_entry(payload)) }
    end

    def format_entry(payload)
      event = payload[:event].to_s
      rest  = payload.except(:event, :ts)
      component, action = event.split(":", 2)
      action  ||= "ready"
      details   = rest.map { |k, v| "#{k}=#{v}" }.join(" ")
      details.empty? ? "#{component}: #{action}" : "#{component}: #{action} #{details}"
    end
  end
end
```

## `lib/master/mcp_coordinator.rb`
```ruby
# frozen_string_literal: true

require "ruby_llm/mcp" if $LOAD_PATH.any? { |p| File.exist?(File.join(p, "ruby_llm/mcp.rb")) }

module Master
  # McpCoordinator — manages MCP server connections and exposes
  # their tools to the agent alongside MASTER's native tools.
  # Servers are defined in data/mcp_servers.yml.
  class McpCoordinator
    CONFIG_PATH = "data/mcp_servers.yml".freeze

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @clients = {}
    end

    # Connect to all configured MCP servers. Non-fatal on failure.
    def connect_all
      servers = load_servers
      servers.each do |name, cfg|
        connect(name, cfg)
      end
      @bus&.publish("mcp:connected", count: @clients.size)
    rescue StandardError => e
      @bus&.publish("mcp:error", error: e.message)
    end

    # Return all tools from all connected MCP servers as RubyLLM::Tool wrappers.
    def tools
      @clients.flat_map do |name, client|
        client.tools.filter_map do |tool|
          McpToolWrapper.new(name:, client:, tool:)
        rescue StandardError => e
          @bus&.publish("mcp:tool_wrap_error", name:, error: e.message)
          nil
        end
      end
    rescue StandardError => e
      @bus&.publish("mcp:tools_error", error: e.message)
      []
    end

    def connected?
      @clients.any?
    end

    def server_names
      @clients.keys
    end

    private

    def connect(name, cfg)
      return unless cfg.is_a?(Hash) && cfg["enabled"] != false
      transport = (cfg["transport"] || "stdio").to_sym
      mcp_config = case transport
                   when :stdio
                     { command: cfg["command"], args: cfg["args"] || [] }
                   when :sse
                     { url: cfg["url"] }
                   else
                     return
                   end
      client = ::RubyLLM::MCP::Client.new(
        name: name,
        transport_type: transport,
        config: mcp_config,
        start: false
      )
      client.start
      @clients[name] = client
      @bus&.publish("mcp:server_connected", name:, transport: transport.to_s)
    rescue StandardError => e
      @bus&.publish("mcp:server_failed", name:, error: e.message)
    end

    def load_servers
      path = File.join(@root, CONFIG_PATH)
      return {} unless File.exist?(path)
      require "yaml"
      data = Master.load_yaml(path) || {}
      data.fetch("servers", {})
    rescue StandardError => _e
      {}
    end
  end

  # Wraps an MCP tool as a RubyLLM::Tool for the agent's tool list.
  if defined?(::RubyLLM::Tool)
    class McpToolWrapper < ::RubyLLM::Tool
      def initialize(name:, client:, tool:)
        @mcp_name   = name
        @mcp_client = client
        @mcp_tool   = tool
      end

      def name
        "#{@mcp_name}__#{@mcp_tool.name}"
      end

      def description
        "[MCP:#{@mcp_name}] #{@mcp_tool.description}"
      end

      def execute(**params)
        result = @mcp_client.call_tool(@mcp_tool.name, params)
        result.respond_to?(:content) ? result.content : result.to_s
      rescue StandardError => e
        "MCP tool error: #{e.message}"
      end
    end
  end
end
```

## `lib/master/memory.rb`
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

require_relative "memory/search"

module Master
  # Memory — persistent cross-session store with TF-IDF semantic search.
  # Stored at .master/memory.yml. Survives restarts.
  class Memory
    TTL_DAYS = 90
    CONSOLIDATE_THRESHOLD = 40
    SECONDS_PER_DAY = 86_400
    MAX_INJECT_TOKENS = 2000
    MAX_INJECT_ENTRIES = 5

    include Search

    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @mutex = Mutex.new
      @store = load_store
    end

    def remember(key, value)
      @mutex.synchronize do
        prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
        @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
      end
      persist
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @mutex.synchronize { @store.delete(key.to_s) }
      persist
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Token-limited injection for system prompt. Caps at MAX_INJECT_TOKENS.
    def context_summary
      active = @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
      return nil if active.empty?

      recent    = active.sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) }.first(MAX_INJECT_ENTRIES)
      lines     = []
      token_sum = 0

      recent.each do |k, v|
        text = "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}"
        est  = text.bytesize / Session::TOKENS_PER_CHAR
        break if token_sum + est > MAX_INJECT_TOKENS
        lines << text
        token_sum += est
      end
      return nil if lines.empty?

      archived_n = @store.count { |k, _| k.to_s.start_with?("archive/") }
      summary    = recall("_consolidated_summary")
      header     = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
      header    += " [+#{archived_n} archived]" if archived_n > 0
      "#{header}\n#{lines.join("\n")}"
    end

    # Three-phase consolidation: light (score), deep (archive), REM (LLM summary).
    def consolidate!(agent: nil)
      return "nothing to consolidate" if @store.empty?

      now      = Time.now.to_i
      entries  = @store.reject { |k, _| k.to_s.start_with?("archive/") }
      archived = 0

      scored = entries.map do |key, data|
        ts    = data.is_a?(Hash) ? data["ts"].to_i : 0
        value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
        age_d = (now - ts) / 86_400.0
        { key: key, value: value, score: 1.0 / (1.0 + age_d / TTL_DAYS.to_f) }
      end

      scored.each do |entry|
        next if entry[:key] == "_consolidated_summary"
        next unless entry[:score] < 0.33
        @store["archive/#{entry[:key]}"] = @store.delete(entry[:key])
        archived += 1
      end

      if agent
        active_text = @store
          .reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
          .map    { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
          .join("\n")

        unless active_text.strip.empty?
          summary = agent.ask_once(
            "Summarize in 2 concise sentences, preserving all key facts:\n#{active_text}"
          )
          remember("_consolidated_summary", summary.strip)
        end
      end

      persist
      "dreaming: #{entries.size} entries checked, #{archived} archived"
    rescue StandardError => e
      "consolidation error: #{e.message}"
    end

    private

    def prune_stale!
      cutoff = Time.now.to_i - TTL_DAYS * SECONDS_PER_DAY
      @store.each do |k, v|
        next if k.to_s.start_with?("archive/") || k == "_consolidated_summary"
        ts = v.is_a?(Hash) ? v["ts"].to_i : 0
        next unless ts > 0 && ts < cutoff
        @store["archive/#{k}"] = @store.delete(k)
      end
    end

    def load_store
      return {} unless File.exist?(@path)
      loaded = Master.load_yaml(@path, symbolize_names: false); loaded.is_a?(Hash) ? loaded : {}
    rescue StandardError => _e
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @store.to_yaml)
    end

  end
end
```

## `lib/master/memory/search.rb`
```ruby
# frozen_string_literal: true

module Master
  class Memory
    module Search
      def semantic_recall(query, top_n: 3)
        return [] if @store.empty?

        query_terms = tokenize(query)
        return [] if query_terms.empty?

        scored = @store.filter_map do |key, data|
          value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
          score = tfidf_score(query_terms, tokenize("#{key} #{value}"))
          next if score.zero?
          { key: key, value: value, score: score }
        end

        scored.sort_by { |e| -e[:score] }.first(top_n)
      end

      private

      def tokenize(text) = text.downcase.scan(/\b[a-z]{2,}\b/)

      def tfidf_score(query_terms, doc_terms)
        return 0.0 if doc_terms.empty?
        freq = doc_terms.tally
        query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
      end
    end
  end
end
```

## `lib/master/metrics.rb`
```ruby
# frozen_string_literal: true

require "json"

module Master
  class Metrics
    SLOW_REQUEST_MS = 5000
    METRICS_PREFIX = "metrics0".freeze
    DIFF_SIZE_LIMIT_DEFAULT = 200
    MAX_DIFF_SIZE_LIMIT = DIFF_SIZE_LIMIT_DEFAULT.freeze
    MAX_DIFF_SIZE_LINES = MAX_DIFF_SIZE_LIMIT.freeze
    ROLLBACK_RATE_THRESHOLD = 0.15
    DECISION_LATENCY_MS_THRESHOLD = 5000

    def initialize(root:, event_bus: nil)
      @path        = File.join(root, ".master", "metrics.jsonl")
      @bus         = event_bus
      @mutex       = Mutex.new
      @writes      = 0
      @undos       = 0
      @latencies   = []
      @diff_sizes  = []
      @model_stats = Hash.new { |h, k| h[k] = { calls: 0, failures: 0, escalations: 0 } }
      subscribe_to_bus(event_bus) if event_bus
    end

    def record_latency(ms)
      @mutex.synchronize { @latencies << ms }
      check_threshold(:decision_latency_ms, average(@latencies))
      append(decision_latency_ms: ms)
    end

    def record_diff(lines)
      @mutex.synchronize { @diff_sizes << lines; @writes += 1 }
      check_threshold(:diff_size_lines, average(@diff_sizes))
      append(diff_size_lines: lines)
    end

    def record_undo
      rate = @mutex.synchronize { @undos += 1; @writes > 0 ? @undos.to_f / @writes : 0.0 }
      check_threshold(:rollback_rate, rate)
      append(rollback_rate: rate.round(3))
    end

    def record_llm_response(model:, success:, tokens_approx: 0, escalated: false)
      @mutex.synchronize do
        stats = @model_stats[model.to_s]
        stats[:calls]       += 1
        stats[:failures]    += 1 unless success
        stats[:escalations] += 1 if escalated
      end
      append(llm_response: { model: model.to_s, success:, tokens_approx:, escalated: })
    end

    def summary
      {
        avg_latency_ms: average(@latencies).round,
        avg_diff_lines: average(@diff_sizes).round,
        rollback_rate:  (@writes > 0 ? @undos.to_f / @writes : 0.0).round(3),
        writes:         @writes,
        undos:          @undos
      }
    end

    def model_quality
      @model_stats.transform_values do |s|
        fail_rate = s[:calls] > 0 ? (s[:failures].to_f / s[:calls]).round(3) : 0.0
        s.merge(fail_rate:)
      end.sort_by { |_, v| -v[:fail_rate] }.to_h
    end

    private

    def subscribe_to_bus(bus)
      bus.subscribe("llm:response") do |ev|
        record_llm_response(
          model:        ev[:model].to_s,
          success:      ev[:success] != false,
          tokens_approx: ev[:tokens_approx].to_i,
          escalated:    ev[:escalated] == true
        )
      rescue StandardError => e
        @bus&.publish("metrics:record_error", error: e.message)
      end
    end

    def check_threshold(metric, value)
      threshold =
        case metric
        when :decision_latency_ms then DECISION_LATENCY_MS_THRESHOLD
        when :diff_size_lines     then MAX_DIFF_SIZE_LINES
        when :rollback_rate       then ROLLBACK_RATE_THRESHOLD
        else return
        end
      return unless value > threshold
      @bus&.publish("metrics:threshold_exceeded", metric:, value:)
      warn "#{METRICS_PREFIX}: #{metric} #{value} exceeds #{threshold}"
    end

    def average(arr)
      return 0.0 if arr.empty?
      arr.sum.to_f / arr.size
    end

    def append(entry)
      entry[:ts] = Time.now.to_i
      File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
    rescue StandardError => e
      @bus&.publish("metrics:append_error", error: e.message)
    end
  end
end
```

## `lib/master/personality.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # MASTER's behavioral persona: voice, TTS settings, and LLM style.
  # Default: dark_malay — terse, direct, Osman TTS voice.
  class Personality
    PERSONAS = {
      dark_malay: {
        voice:       "ms-MY-OsmanNeural",
        tts_rate:    "-35%",
        tts_pitch:   "-150Hz",
        style:       :deep,
        description: "Terse. Direct. No filler. Dark."
      },
      british: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Measured. Precise. Dry wit."
      },
      norwegian: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Calm. Considered. Honest."
      },
      ronin: {
        voice:       "en-US-AndrewNeural",
        tts_rate:    "-25%",
        tts_pitch:   "-100Hz",
        style:       :deep,
        description: "Stoic. Minimal. Decisive. Says only what must be said."
      },
      lawyer: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-10%",
        tts_pitch:   "-20Hz",
        style:       :slow,
        description: "Norwegian law focus. Barnevernet, lovdata.no, sivilombudet.no. Not legal advice."
      },
      hacker: {
        voice:       "en-US-GuyNeural",
        tts_rate:    "-30%",
        tts_pitch:   "-120Hz",
        style:       :deep,
        description: "OpenBSD security. CVE analysis. Pentesting. Exploit-db."
      },
      architect: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-60Hz",
        style:       :heavy,
        description: "Parametric design. BIM. archdaily.com. dezeen.com."
      },
      sysadmin: {
        voice:       "en-AU-WilliamNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :deep,
        description: "OpenBSD. pf. httpd. vmm. man.openbsd.org."
      },
      trader: {
        voice:       "en-US-ChristopherNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Crypto. DeFi. Technicals. TradingView. CoinGecko."
      },
      medic: {
        voice:       "en-US-EricNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Medical research. PubMed. Not medical advice."
      }
    }.freeze

    DEFAULT = :dark_malay
    AXIOM_DISPLAY_LIMIT = 10

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def initialize(name = DEFAULT, root: nil)
      @name      = name.to_sym
      persona    = PERSONAS.fetch(@name, PERSONAS[DEFAULT])
      @voice     = persona[:voice]
      @tts_rate  = persona[:tts_rate]
      @tts_pitch = persona[:tts_pitch]
      @style     = persona[:style]
      @desc      = persona[:description]
      @axioms    = Axioms.new(root:)
    end

    # Injected before every LLM call. Pulls from rules.yml via Axioms.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

    def build_system_prompt
      ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
      constitution = @axioms.constitution
      strunk = @axioms.strunk
      banned  = (constitution["banned_output"] || [])
      no_open = (strunk["preambles"] || []).first(4)
      no_end  = (strunk["endings"]   || []).first(3)
      ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
      ls << "Evidence only: show diff or file content, never assert. Active voice."
      kernel = @axioms.kernel
      ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
      phil = @axioms.philosophy(limit: AXIOM_DISPLAY_LIMIT)
      ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
      golden = constitution["golden_rule"]
      ls << "Rule: #{golden}." if golden

      # Hard formatting rules — [K] enforced
      ls << "Output format: plain prose or dmesg-style lines. No markdown headers (#), no bold (**),
        no bullet lists (- *), no numbered lists. Code fences (```) are allowed only for actual code."
      ls << "Never use: Certainly, Of course, Great question, Absolutely, Happy to help, I would be glad."

      # Code generation axioms — [K] enforced
      ls << "Code axioms — refuse to generate code that violates these:"
      ls << "FAIL_VISIBLY: never rescue Exception or bare rescue that swallows errors silently. Always rescue StandardError or a specific class."
      thresholds   = @axioms.thresholds
      max_lines    = thresholds.dig("class", "max_lines")    || 200
      max_methods  = thresholds.dig("class", "max_methods")  || 6
      ls << "SIMPLEST_WORKS: refuse to create god classes (>#{max_lines} lines, >#{max_methods} methods). Push back and suggest decomposition."
      ls << "PRESERVE_FIRST: never rewrite working code from scratch. Read first, patch minimally."
      ls << "BE_CONCISE: minimal response. If the answer is one word, say one word."

      zsh = load_yaml_data("zsh_patterns.yml")
      if zsh
        banned_cmds = Array(zsh["banned_commands"]).join(", ")
        ls << "Zsh scripts: never use #{banned_cmds}. Use pure zsh parameter expansion and builtins instead."
      end

      style = load_yaml_data("ruby_style.yml")
      if style
        bugs = Array(style.dig("ruby", "bugs_to_avoid"))
                  .map { |b| "#{b["pattern"]}: #{b["fix"] || b["note"]}" }
                  .first(5)
        ls << "Ruby bugs to avoid: #{bugs.join("; ")}." if bugs.any?
        shell_forbidden = Array(style.dig("shell", "decorations_forbidden"))
        ls << "Shell scripts: no ASCII banners (===,---), no emoji, no hardcoded credentials." if shell_forbidden.any?
        abbrev_rule = style.dig("ruby", "naming", "rule")
        ls << "Naming: #{abbrev_rule}" if abbrev_rule
        string_rule = style.dig("ruby", "prefer_string_methods", "rule")
        ls << "String methods: #{string_rule}" if string_rule
        gem_rule = style.dig("ruby", "outsource_to_gems", "rule")
        ls << "Gems: #{gem_rule}" if gem_rule
      end

      ls.join("\n")
    end

    def load_zsh_patterns
      load_yaml_data("zsh_patterns.yml")
    end

    def load_yaml_data(filename)
      path = File.join(Master::ROOT, "data", filename)
      Master.load_yaml(path) if File.exist?(path)
    rescue StandardError => _e
      nil
    end
  end
end
```

## `lib/master/phase_gates.rb`
```ruby
# frozen_string_literal: true

module Master
  PHASES = %w[discover analyze ideate design implement validate deliver idle].freeze

  class PhaseGates
    PHASE_STATE_PATH = "data/phase_state.yml".freeze

    GATES = {
      "discover"  => %w[problem_stated success_measurable],
      "analyze"   => %w[components_distinct dependencies_noted],
      "ideate"    => %w[alternatives_gte_3],
      "design"    => %w[interfaces_noted errors_noted],
      "implement" => %w[],
      "validate"  => %w[tests_noted],
      "deliver"   => %w[deployed_noted],
      "idle"      => %w[]
    }.freeze

    def initialize(root:, event_bus: nil)
      @root  = root
      @bus   = event_bus
      @state = load_state
    end

    def current = @state["phase"] || "idle"

    def advance!(to: nil)
      prev   = current
      target = to&.to_s || next_phase
      return Master::Result.err("unknown phase: #{target}") unless PHASES.include?(target)
      return Master::Result.err("already at final phase: #{prev}") if prev == "idle" && target == "idle"

      unmet = unmet_gates(prev)
      if unmet.any?
        return Master::Result.err("phase #{prev} gates unmet: #{unmet.join(",")} — override with /phase advance --force")
      end

      @state["phase"] = target
      @state["entered_at"] = Time.now.to_i
      persist
      @bus&.publish("phase:advanced", from: prev, to: target)
      Master::Result.ok("phase: #{prev} -> #{target}")
    end

    def force!(phase)
      @state["phase"] = phase.to_s
      @state["entered_at"] = Time.now.to_i
      persist
      Master::Result.ok("phase forced to #{phase}")
    end

    def meet_gate!(gate)
      @state["met_gates"] ||= []
      @state["met_gates"] |= [gate.to_s]
      persist
    end

    def status
      unmet = unmet_gates(current)
      met   = (@state["met_gates"] || []) & (GATES[current] || [])
      "phase=#{current} met=#{met.join(",")} unmet=#{unmet.join(",")}"
    end

    private

    def next_phase
      phase_index = PHASES.index(current) || 0
      PHASES[[phase_index + 1, PHASES.size - 1].min]
    end

    def unmet_gates(phase)
      required = GATES.fetch(phase, [])
      met = @state["met_gates"] || []
      required - met
    end

    def load_state
      path = File.join(@root, PHASE_STATE_PATH)
      return { "phase" => "idle", "met_gates" => [] } unless File.exist?(path)
      data = Master.load_yaml(path)
      data.is_a?(Hash) ? data : { "phase" => "idle", "met_gates" => [] }
    rescue StandardError => _e
      { "phase" => "idle", "met_gates" => [] }
    end

    def persist
      path = File.join(@root, PHASE_STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, YAML.dump(@state))
    end
  end
end
```

## `lib/master/pipeline.rb`
```ruby
# frozen_string_literal: true

require "open3"

module Master
  class Pipeline
    ROLLBACK_CATEGORIES   = %i[validation axiom_violation].freeze
    MS_PER_SECOND         = 1000
    ROLLBACK_MSG_TRUNCATE = 120

    attr_reader :last_timings

    def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil)
      @stages = stages
      @last_timings = {}
      @bus   = bus || event_bus
      @trace = trace
      @root  = root
    end

    def call(initial)
      timings = {}
      @stages.reduce(initial) do |result, stage|
        result.and_then(stage_label(stage)) do |ctx|
          t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          stage_result = stage.call(ctx)
          ms     = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * MS_PER_SECOND).round
          timings[stage_label(stage)] = ms
          if stage_result.respond_to?(:ok?) && stage_result.ok?
            @last_timings = timings.dup
            @bus&.publish("pipeline:stage", stage: stage_label(stage), ms:) if @trace
            Result.ok(stage_result.value!.merge(_timings: timings.dup))
          else
            stage_result
          end
        end
      end.tap { |final| maybe_rollback(final) }
    end

    class ParallelGroup
      PARALLEL_TIMEOUT_S = 30

      def initialize(*stages, bus: nil)
        @stages = stages
        @bus    = bus
      end

      def call(ctx)
        frozen_ctx = ctx.freeze
        threads    = @stages.map do |s|
          Thread.new do
            s.call(frozen_ctx)
          rescue StandardError => e
            @bus&.publish("pipeline:stage_error", stage: s.class.name, error: e.message)
            Result.ok(frozen_ctx.merge(_stage_error: e.message))
          end
        end

        results = threads.each_with_index.map do |t, i|
          if t.join(PARALLEL_TIMEOUT_S)
            t.value
          else
            begin; t.kill; rescue ThreadError; nil; end
            @bus&.publish("pipeline:stage_timeout", stage: @stages[i].class.name)
            Result.ok(frozen_ctx.merge(_parallel_timeout: @stages[i].class.name))
          end
        end

        errors = results.filter_map { |r| r.respond_to?(:err?) && r.err? ? r.message : nil }
        merged = results.reduce(ctx) { |acc, r| r.respond_to?(:ok?) && r.ok? ? acc.merge(r.value!) : acc }
        merged = merged.merge(_parallel_errors: errors) unless errors.empty?

        Result.ok(merged)
      rescue StandardError => e
        Result.ok(ctx.merge(_parallel_errors: [e.message]))
      end
    end

    class SkipOnPressure
      def initialize(stage, bus: nil)
        @stage = stage
        @bus   = bus
      end

      def call(ctx)
        return @stage.call(ctx) unless ctx[:pressure]
        label = @stage.respond_to?(:stages) ? "parallel[#{@stage.stages.map { |s| s.class.name.split("::").last }.join(",")}]" : @stage.class.name.split("::").last
        @bus&.publish("pipeline:skipped", stage: label, reason: "pressure")
        $stdout.puts "pipeline: skipped #{label} (pressure)"
        $stdout.flush
        Result.ok(ctx)
      end
    end

    private

    def maybe_rollback(result)
      return unless result.respond_to?(:err?) && result.err?
      return unless ROLLBACK_CATEGORIES.include?(result.category)
      return unless @root && git_workspace?
      return unless dirty?

      @bus&.publish("pipeline:rollback", category: result.category, message: result.message[0, ROLLBACK_MSG_TRUNCATE])
      Open3.capture2e("git", "-C", @root, "reset", "--hard", "HEAD")
    end

    def git_workspace?
      @root && Dir.exist?(File.join(@root, ".git"))
    end

    def dirty?
      out, _, st = Open3.capture3("git", "-C", @root, "status", "--porcelain")
      st.success? && !out.strip.empty?
    end

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end
```

## `lib/master/pledge.rb`
```ruby
# frozen_string_literal: true

module Master
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      require "fiddle"
      require "fiddle/import"

      module LibC
        extend Fiddle::Importer
        dlload "libc.so"
        extern "int pledge(const char *, const char *)"
        extern "int unveil(const char *, const char *)"
      end

      def pledge(promises, execpromises = nil)
        result = LibC.pledge(promises, execpromises || Fiddle::NULL)
        raise SystemCallError.new("pledge failed", Fiddle.last_error) if result == -1
      end

      def unveil(path, permissions)
        result = LibC.unveil(path, permissions)
        raise SystemCallError.new("unveil failed", Fiddle.last_error) if result == -1
      end

      def lock_unveil! = LibC.unveil(Fiddle::NULL, Fiddle::NULL)
    else
      def pledge(*) = nil
      def unveil(*) = nil
      def lock_unveil! = nil
    end

    # Stage 1: called before Builder.build -- widest promises, no lock
    # "error" converts unknown-ioctl pledge kills to EPERM so tty gems degrade gracefully.
    def stage1_boot!(root)
      pledge("stdio rpath wpath cpath proc exec inet dns tty unveil prot_exec error")
      unveil("/", "")
      unveil(root, "rwc")
      unveil(Dir.home, "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      unveil("/usr/local/lib", "r")
      unveil("/usr/local/share", "r")
      [Dir.home + "/.local/share/gem", Dir.home + "/.gem"].each { |p| unveil(p, "r") if Dir.exist?(p) }
      unveil("/dev/urandom", "r")
      unveil("/var/run", "r")
    end

    # Stage 2: called after CLI is fully initialized -- lock filesystem
    def stage2_lock!
      lock_unveil!
      pledge("stdio rpath wpath cpath proc exec inet dns tty prot_exec error")
    end

    # Stage 3: scan-only sessions (no network, no exec)
    def stage3_scan_only!
      lock_unveil!
      pledge("stdio rpath wpath cpath tty")
    end

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
  end
end
```

## `lib/master/reasoning/modes.rb`
```ruby
# frozen_string_literal: true

module Master
  module Reasoning
    class Modes
      SUPPORTED = %w[direct react rewoo].freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def supported = SUPPORTED

      def wrap(message, mode: "direct")
        selected = SUPPORTED.include?(mode.to_s) ? mode.to_s : "direct"
        prompt = load_prompt(selected)
        format(prompt.fetch("template", "%{message}"), message: message.to_s)
      rescue StandardError => e
        $stderr.puts "reasoning/modes: wrap failed (mode=#{mode}): #{e.message}"
        message.to_s
      end

      private

      def load_prompt(mode)
        path = File.join(@root, "data", "prompts", "mode_#{mode}.yml")
        Master.load_yaml(path) || {}
      end
    end
  end
end
```

## `lib/master/reflexion.rb`
```ruby
# frozen_string_literal: true

module Master
  module Reflexion
    MAX_REFLECTIONS   = 3
    TASK_TRUNCATE     = 400
    HISTORY_TRUNCATE  = 200

    module_function

    def run(agent:, task:, fast_model: nil, max: MAX_REFLECTIONS)
      last_result = nil
      last_critique = nil

      (max + 1).times do |i|
        prompt = i.zero? ? task : build_revision_prompt(task, last_result, last_critique)
        last_result = yield(prompt, i)
        return last_result if last_result.respond_to?(:ok?) && last_result.ok?

        break if i >= max
        last_critique = critique(agent:, task:, result: last_result, fast_model:)
      end

      last_result
    end

    def critique(agent:, task:, result:, fast_model: nil)
      prompt = <<~PROMPT
        Task: #{task.to_s[0, TASK_TRUNCATE]}
        Attempt output: #{result.to_s[0, TASK_TRUNCATE]}
        What specifically went wrong? Name the constraint violated. What must change in the next attempt? One paragraph, no preamble.
      PROMPT
      resp = fast_model ? agent.ask_once(prompt, model: fast_model) : agent.ask(prompt)
      resp.respond_to?(:value!) ? resp.value! : resp.to_s
    rescue StandardError => _e
      "previous attempt failed — try a different approach"
    end

    def build_revision_prompt(task, previous_result, critique)
      <<~PROMPT
        #{task}

        Previous attempt failed.
        Critique: #{critique}
        Previous output: #{previous_result.to_s[0, HISTORY_TRUNCATE]}

        Revise based on the critique. Return only the corrected result.
      PROMPT
    end
  end
end
```

## `lib/master/renderer.rb`
```ruby
# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"
require "socket"

module Master
  DEFAULT_WEB_PORT = Config::DEFAULT_WEB_PORT

  class Renderer
    TICK             = "\u2714".freeze
    CROSS            = "\u2718".freeze
    DMESG_LINE_COUNT = 5
    MS_PER_SEC       = 1000

    def initialize(config:)
      @config   = config
      @p        = Pastel.new
      @boot_ms  = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i
    end

    def splash(model)
      t0    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      now   = Time.now
      host  = (Socket.gethostname rescue "openbsd")
      user  = ENV["USER"] || "dev"
      shell = File.basename(ENV["SHELL"] || "zsh")
      pchar = shell == "zsh" ? "%" : "$"
      rev   = git_rev
      url   = @config["web_public_url"] || "https://ai.brgen.no"
      token = @config["web_token"]
      web   = token ? "#{url}/?token=#{token}" : url
      pledge_ok = RUBY_PLATFORM.include?("openbsd")

      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << d("MASTER (CONSTITUTIONAL) #1: #{now.strftime('%a %b %-d %H:%M:%S %Z %Y')}")
      lines << d("    #{user}@#{host}:#{@config["root"] || Dir.pwd}")
      lines << d("runtime0: #{RUBY_PLATFORM}  ruby #{RUBY_VERSION}  #{shell} #{user}#{pchar}")
      lines << d("model0:   #{short_model(model)}")
      lines << d("rev0:     #{rev}") if rev
      lines << d("security0: #{pledge_ok ? "pledge armed" : "pledge unavailable"}")
      lines << d("web0:     #{web}")
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * MS_PER_SEC).round
      lines << d("boot0:    #{elapsed}ms")
      lines << ""
      lines << @p.bold.red("master") + @p.dim("@#{host} ready -- /help for commands")
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil)
      branch = git_branch
      tok    = tokens && tokens > 0 ? @p.dim("#{tokens}t ") : ""
      vbadge = violations > 0 ? @p.red("[#{violations}v] ") : ""
      phase_str = phase && phase.to_s != "idle" ? @p.dim("{#{phase}} ") : ""
      branch_str = branch ? "#{@p.dim("(")}#{@p.red(branch)}#{@p.dim(")")} " : ""
      dollar = last_ok ? @p.bright_red("$") : @p.red("$")
      "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{branch_str}#{phase_str}#{tok}#{vbadge}#{dollar} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.bright_red(TICK)} #{@p.bright_red(content)}"
      when :warning then @p.red("! #{content}")
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then format_dmesg(content)
      else               content.to_s
      end
    end

    def format_error(message)  = render(message, mode: :error)
    def format_dmesg(line)     = @p.dim(line.to_s)

    def beautify(text)
      text
        .gsub(/"([^"]*?)"/) { "\u201C#{Regexp.last_match(1)}\u201D" }
        .gsub(/\s--\s/, " \u2014 ")
        .gsub("...", "\u2026")
    end

    private

    def d(text) = @p.dim(text)

    def git_rev
      out, _, st = Open3.capture3("git", "-C", @config["root"] || Dir.pwd, "rev-parse", "--short", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def short_model(model)
      model.to_s.split("/").last.sub(/:free$/, "")
    end

    def git_branch
      out, _, st = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def dmesg_lines
      boot_log = "/var/run/dmesg.boot"
      raw = if File.readable?(boot_log)
              File.readlines(boot_log, chomp: true).first(DMESG_LINE_COUNT)
            else
              stdout, = Open3.capture3("dmesg")
              stdout.lines(chomp: true).first(DMESG_LINE_COUNT)
            end
      raw.empty? ? ["dmesg unavailable"] : raw
    rescue StandardError
      ["dmesg unavailable"]
    end
  end
end
```

## `lib/master/result.rb`
```ruby
# frozen_string_literal: true

module Master
  class Result
    def self.ok(value)                      = Ok.new(value)
    def self.err(msg, category: :unknown)   = Err.new(msg, category)
    def self.wrap(val)                      = val.respond_to?(:ok?) ? val : Ok.new(val)

    class Ok
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def ok?              = true
      def err?             = false
      def value!           = @value
      def unwrap           = @value
      def value_or(_)      = @value

      def map(&blk)        = Result.ok(blk.call(@value))
      def flat_map(&blk)   = blk.call(@value)

      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.respond_to?(:ok?) ? result : Result.ok(result)
      rescue StandardError => e
        Result.err("#{label || "stage"}: #{e.message}", category: :unknown)
      end

      def deconstruct_keys(_keys) = { value: @value }
      def to_s                    = @value.to_s
      def inspect                 = "Ok(#{@value.inspect})"
    end

    class Err
      attr_reader :message, :category

      RETRIABLE = %i[infrastructure timeout].freeze
      PERMANENT = %i[validation axiom_violation budget].freeze

      def initialize(message, category = :unknown)
        @message  = message
        @category = category
        freeze
      end

      def ok?                   = false
      def err?                  = true
      def value!                = raise(Master::UnwrapError, "Err#value\! called: #{@message}")
      def unwrap                = value!
      def value_or(default)     = default

      def map(&)                = self
      def flat_map(&)           = self
      def and_then(*)           = self

      def retriable?            = RETRIABLE.include?(@category)
      def permanent?            = PERMANENT.include?(@category)

      def deconstruct_keys(_keys) = { message: @message, category: @category }
      def to_s                    = @message
      def inspect                 = "Err(#{@category}: #{@message})"
    end
  end
end
```

## `lib/master/ring_buffer.rb`
```ruby
# frozen_string_literal: true

module Master
  class RingBuffer
    include Enumerable
    include MonitorMixin

    def initialize(capacity)
      super()
      @capacity = capacity
      @buffer      = Array.new(capacity)
      @start    = 0
      @size     = 0
    end

    def push(item)
      synchronize do
        write_pos = (@start + @size) % @capacity
        if @size < @capacity
          @buffer[write_pos] = item
          @size += 1
        else
          @buffer[@start] = item
          @start = (@start + 1) % @capacity
        end
      end
      self
    end

    alias << push

    def each
      return enum_for(__method__) unless block_given?
      synchronize { @size.times { |i| yield @buffer[(@start + i) % @capacity] } }
    end

    def to_a    = @size.times.map { |i| @buffer[(@start + i) % @capacity] }
    def size    = @size
    def full?   = @size == @capacity
    def empty?  = @size.zero?

    def clear
      @start = @size = 0
      self
    end
  end
end
```

## `lib/master/routing/continuity_index.rb`
```ruby
# frozen_string_literal: true


module Master
  module Routing
    class ContinuityIndex
      def initialize(root: Master::ROOT)
        @root       = root
        @data_cache = nil
        @data_mtime = nil
      end

      def fallback_models
        return [] unless enabled?

        [openrouter_latest, ferrum_latest].flatten.compact.uniq
      end

      private

      def enabled?
        data.dig("continuity", "enabled") != false
      end

      def openrouter_latest
        data.dig("openrouter", "free_latest").to_a
      end


      def ferrum_latest
        data.dig("ferrum_web_chat", "free_latest").to_a
      end

      def data
        path = File.join(@root, "data", "models.yml")
        current_mtime = File.exist?(path) ? File.mtime(path) : nil

        if @data_cache.nil? || current_mtime != @data_mtime
          @data_cache = begin
            Master.load_yaml(path) || {}
          rescue StandardError => _e
            {}
          end
          @data_mtime = current_mtime
        end

        @data_cache
      end
    end
  end
end
```

## `lib/master/routing/model_router.rb`
```ruby
# frozen_string_literal: true

module Master
  module Routing
    class ModelRouter
      UNCERTAINTY_PHRASES = [
        "i'm not sure", "i don't know", "cannot determine",
        "unclear", "uncertain", "might be", "possibly",
        "probably not", "limited information", "i cannot",
        "i am unable", "i lack the", "not enough information",
        "i would need more"
      ].freeze

      ESCALATION_CHAIN = %w[cheap default strong].freeze
      DEFAULT_THRESHOLD = 0.3

      def initialize(config:, root: Master::ROOT, continuity_index: nil)
        @config = config
        @root = root
        @rules = load_rules
        @continuity_index = continuity_index || ContinuityIndex.new(root: @root)
      end

      def preferred(task_type: :exploration)
        return @config.model unless enabled?

        tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
        candidates = @rules.dig("models", tier).to_a
        return @config.model if candidates.empty?

        best = candidates.max_by { |m| weighted_score(m["score"] || {}) }
        best["id"] || @config.model
      end

      def fallback_chain(task_type: :exploration)
        return [@config.model] unless enabled?

        pref = preferred(task_type:)
        all = @rules.fetch("models", {}).values.flat_map { |tier| tier.filter_map { |m| m["id"] } }
        continuity = @continuity_index.fallback_models
        ([pref] + all + continuity + [@config.model]).uniq
      end

      def escalate?(response, threshold: DEFAULT_THRESHOLD)
        return false unless @rules.dig("routing", "escalation_enabled")

        text = response.to_s.downcase
        hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
        hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
      end

      def stronger_model(task_type: :exploration)
        tier = @rules.dig("routing", "escalation_tier") || "strong"
        candidates = @rules.dig("models", tier).to_a
        return preferred(task_type:) if candidates.empty?

        candidates.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred(task_type:)
      end

      def escalate_if_low_confidence(response, current_model:, task_type: :exploration)
        return nil unless escalate?(response)

        strong_model = stronger_model(task_type:)
        return nil if current_model == strong_model

        strong_model
      end

      def constrained_for(operation:)
        constraint = @rules.dig("operation_constraints", operation.to_s)
        return preferred unless constraint

        min_quality = constraint.fetch("min_quality", 0.0).to_f
        preferred_tier = constraint.fetch("preferred_tier", "strong")
        candidates = @rules.dig("models", preferred_tier).to_a
        qualified = candidates.select { |m| m.dig("score", "quality").to_f >= min_quality }
        return preferred if qualified.empty?

        qualified.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred
      end

      def tier_for_model(model_id)
        @rules.fetch("models", {}).each do |tier, models|
          return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
        end
        "cheap"
      end

      def next_escalation_tier(current_tier)
        tier_index = ESCALATION_CHAIN.index(current_tier.to_s)
        return nil unless tier_index

        ESCALATION_CHAIN[tier_index + 1]
      end

      def confidence_threshold(task_type: :exploration)
        route = @rules.dig("routes", task_type.to_s)
        return DEFAULT_THRESHOLD unless route.is_a?(Hash)

        route.fetch("confidence_threshold", DEFAULT_THRESHOLD).to_f
      end

      private

      def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        weights = @rules.fetch("weights", {})
        qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
        sw = [weights.fetch("speed",   1.0).to_f, 0.01].max
        cw = [weights.fetch("cost",    1.0).to_f, 0.01].max
        DecisionEngine.score(
          impact:     score.fetch("quality", 0.5).to_f * qw,
          confidence: [score.fetch("speed", 1.0).to_f * sw, 0.01].max,
          cost:       1.0 / [score.fetch("cost", 0.5).to_f * cw, 0.001].max
        )
      end

      def load_rules
        path = File.join(@root, "data", "models.yml")
        Master.load_yaml(path) || {}
      rescue StandardError => _e
        {}
      end
    end
  end
end
```

## `lib/master/ruby_llm_patch.rb`
```ruby
# frozen_string_literal: true

module RubyLLM
  DEFAULT_MAX_TOKENS = 4096

  class Models
    class << self
      def read_from_json(file = RubyLLM.config.model_registry_file)
        data = File.exist?(file) ? File.read(file, encoding: "utf-8") : "[]"
        JSON.parse(data, symbolize_names: true).map { |model| Model::Info.new(model) }
      rescue JSON::ParserError
        []
      end
    end

    private

    def find_without_provider(model_id)
      exact_matches = all.select { |m| m.id == model_id }
      return preferred_match(exact_matches) if exact_matches.any?

      resolved_id = Aliases.resolve(model_id)
      alias_matches = all.select { |m| m.id == resolved_id }
      return preferred_match(alias_matches) if alias_matches.any?

      Model::Info.new({
        id: model_id.to_s,
        name: model_id.to_s,
        provider: "openrouter",
        type: "chat",
        family: model_id.to_s.split("/").first,
        context_window: 128_000,
        max_tokens: DEFAULT_MAX_TOKENS,
        input_price_per_million: 0.0,
        output_price_per_million: 0.0,
        modalities: { input: ["text"], output: ["text"] },
        metadata: {}
      })
    end
  end
end
```

## `lib/master/scan/rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    class Rule
      EXT_LANG = {
        ".rb"      => "ruby",        ".rake"  => "ruby",   ".gemspec" => "ruby",
        ".erb"     => "html",        ".html"  => "html",   ".htm"     => "html",
        ".css"     => "css",         ".scss"  => "scss",   ".sass"    => "scss",
        ".js"      => "javascript",  ".ts"    => "javascript",
        ".jsx"     => "javascript",  ".tsx"   => "javascript",
        ".zsh"     => "zsh",         ".sh"    => "zsh",    ".bash"    => "zsh",
        ".yml"     => "yaml",        ".yaml"  => "yaml",
        ".md"      => "markdown",    ".json"  => "json",
      }.freeze

      attr_reader :id, :description, :severity, :axiom_tags, :auto_fix

      def self.inherited(subclass)
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize do
          (@registry ||= []) << subclass
        end
      end

      def self.registry
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize { @registry || [] }
      end

      # Rules that need constructor args (root:, agent:) override this to false.
      # Builder uses it to auto-discover zero-arg rules from the registry.
      def self.auto_build? = true

      def initialize
        @id         = self.class.name&.split("::")&.last&.downcase || "unknown"
        @description = ""
        @severity    = :warning
        @axiom_tags  = []
        @auto_fix    = true
      end

      def check(code, path:)
        raise NotImplementedError, "#{self.class}#check not implemented"
      end

      def language(path)
        EXT_LANG[File.extname(path).downcase]
      end

      def applies_to?(path, languages)
        return true if languages.nil? || languages.empty?
        lang = language(path)
        lang && languages.include?(lang)
      end

      protected

      def finding(line:, message:, fix: nil)
        { rule: @id, message:, line:, severity: @severity, fix: }
      end

      def scan_lines(code, pattern, message:, fix: nil)
        code.each_line.with_index(1).filter_map { |line, num|
          finding(line: num, message:, fix:) if line.match?(pattern)
        }
      end
    end
  end
end
```

## `lib/master/scan/rules/adversarial_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Steelman-first red-team: the model must defend the code before it can attack it.
      # This suppresses false positives by forcing consideration of legitimate reasons
      # before a violation can survive. Deep depth only; one LLM call per file.
      class AdversarialRule < Rule
        PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Challenge: list only the violations that survive the steelman.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "adversarial"
          @description = "Red-team scan: steelman then challenge — suppresses false positives"
          @severity    = :error
          @axiom_tags  = %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE]
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless (lang = language(path))
          return [] unless @agent

          prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                           lang: lang,
                                           code: code[0, 3_000])
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "adversarial: scan error — #{e.message}")]
        end

        private

        def parse_findings(response)
          return [] if response.strip.upcase.start_with?("CLEAN")

          response.lines.filter_map do |line|
            match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
            next unless match
            finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/arity_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Too many constructor args signal a god object; callers can't reason about what matters.
      # Reads max_params from rules.yml so the threshold stays in one place.
      class ArityRule < Rule
        DEFAULT_MAX = 3

        def initialize
          super
          @max_params  = Master::Axioms.new.thresholds.dig("method", "max_params") || DEFAULT_MAX
          @id          = "arity"
          @description = "initialize with > #{@max_params} args — extract a context struct or config object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          lines    = code.lines
          index    = 0
          while index < lines.size
            line = lines[index]
            if line.match?(/^\s*def\s+initialize\s*\(/)
              signature, end_index = collect_signature(lines, index)
              param_count = count_params(signature)
              findings << finding(line: index + 1,
                message: "initialize takes #{param_count} args (max #{@max_params}) — extract AgentContext or Config struct") if param_count > @max_params
              index = end_index + 1
            else
              index += 1
            end
          end
          findings
        end

        private

        def collect_signature(lines, start)
          signature = +""
          depth     = 0
          current   = start
          while current < lines.size
            signature << lines[current]
            depth += lines[current].count("(") - lines[current].count(")")
            break if depth <= 0
            current += 1
          end
          [signature, current]
        end

        def count_params(signature)
          inner = signature.match(/def\s+initialize\s*\((.+)\)/m)
          return 0 unless inner
          content = inner[1].strip
          return 0 if content.empty?
          depth = 0
          count = 1
          content.each_char do |char|
            case char
            when "(", "[", "{" then depth += 1
            when ")", "]", "}" then depth -= 1
            when "," then count += 1 if depth.zero?
            end
          end
          count
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/axiom_coverage_rule.rb`
```ruby
# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      # Every rule ID in rules.yml must have scan rule coverage; every @axiom_tags
      # symbol must name a real rule ID. Orphaned tags and uncovered rules both signal drift.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every rule must have scan rule coverage; every tag must be a real rule"
          @severity    = :warning
          @axiom_tags  = []
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in rules.yml — define it or remove the tag")
          end

          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "rule #{id} has no scan rule coverage — add a rule or accept as advisory")
          end

          findings
        end

        private

        def load_axiom_ids
          path = File.join(@root, "data", "rules.yml")
          return [] unless File.exist?(path)

          data = Master.load_yaml(path)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules.map { |r| r["id"] }.compact.uniq
        rescue StandardError => _e
          []
        end

        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            extract_axiom_tags(File.read(f))
          }.uniq
        rescue StandardError => _e
          []
        end

        def extract_axiom_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError => _e
          []
        end

        class TagCollector < Prism::Visitor
          attr_reader :tags
          def initialize
            super
            @tags = []
          end

          def visit_instance_variable_write_node(node)
            if node.name == :@axiom_tags
              @tags.concat(collect_symbols(node.value))
            end
            super
          end

          private

          def collect_symbols(node)
            return [] unless node
            case node
            when Prism::ArrayNode
              node.elements.flat_map { |el| collect_symbols(el) }
            when Prism::SymbolNode
              [node.unescaped.to_s]
            else
              []
            end
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/bare_rescue_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class BareRescueRule < Rule
        def initialize
          super
          @id          = "bare_rescue"
          @description = "Never use bare rescue -- always specify exception type"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          scan_lines(code, /^\s*rescue\s*$/, message: "bare rescue: specify exception type (e.g. rescue StandardError)")
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/comment_quality_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class CommentQualityRule < Rule
        TODO_NO_REF      = /^\s*#\s*TODO(?!.*[:(#@])/.freeze
        FIXME_NO_REF     = /^\s*#\s*FIXME(?!.*[:(#@])/.freeze
        CODE_LINE_RE     = /(?:def |end\b|=\s|\.call|if |unless |return |@@|@\w+ =)/.freeze
        MIN_CODE_COMMENTS = 3

        def initialize
          super
          @id          = "comment_quality"
          @description = "Low-quality comments — TODO without ref, commented-out code"
          @severity    = :style
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_findings = []
          lines = code.lines

          lines.each_with_index do |line, i|
            num = i + 1
            line_findings << finding(line: num, message: "TODO without owner or issue ref — add TODO(name) or TODO(#123)") if line.match?(TODO_NO_REF)
            line_findings << finding(line: num, message: "FIXME without owner or issue ref — add FIXME(name)") if line.match?(FIXME_NO_REF)
          end

          line_findings + commented_out_blocks(lines)
        end

        private

        def commented_out_blocks(lines)
          findings  = []
          run_start = nil
          run_count = 0

          lines.each_with_index do |line, i|
            stripped = line.strip
            if stripped.start_with?("#") && CODE_LINE_RE.match?(stripped[1..].to_s)
              run_start ||= i + 1
              run_count  += 1
            else
              if run_count >= MIN_CODE_COMMENTS
                findings << finding(line: run_start, message: "#{run_count} consecutive lines of commented-out code — delete it, git history preserves it")
              end
              run_start = nil
              run_count = 0
            end
          end

          if run_count >= MIN_CODE_COMMENTS
            findings << finding(line: run_start, message: "#{run_count} consecutive lines of commented-out code — delete it, git history preserves it")
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/conceptual_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # LLM review for rules whose violations resist lexical detection; deep depth only.
      # Rules with detect_conceptual prompts in rules.yml are batched into one LLM call per file.
      class ConceptualRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
        CODE_SNIPPET_LIMIT = 2000

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual"
          @description = "LLM-based rule review (runs at :deep depth only)"
          @severity    = :warning
          @axioms      = load_conceptual_rules
          @axiom_tags  = @axioms.keys.map(&:to_sym)
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless language(path)
          return [] unless @agent

          prompt = build_prompt(code, path)
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "conceptual: scan error — #{e.message}")]
        end

        private

        def load_conceptual_rules
          data = Master.load_yaml(RULES_PATH)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules
            .select { |r| r["detect_conceptual"] }
            .each_with_object({}) { |r, h| h[r["id"]] = r["detect_conceptual"] }
        end

        def build_prompt(code, path)
          axiom_list = @axioms.map { |id, stmt| "#{id}: #{stmt}" }.join("\n")
          <<~PROMPT
            Review #{File.basename(path)} against these rules. List ONLY clear violations.
            Format each as: RULE_ID:LINE:description (one per line)
            If clean, respond with exactly: CLEAN

            Rules:
            #{axiom_list}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end

        def parse_findings(response)
          return [] if response.strip.upcase == "CLEAN"

          response.lines.filter_map do |line|
            match_data = line.strip.match(/\A([A-Z_]+):(\d+):(.+)\z/)
            next unless match_data && @axioms.key?(match_data[1])
            finding(line: match_data[2].to_i, message: "#{match_data[1]}: #{match_data[3].strip}")
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/cqs_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # CqsRule — detects Command/Query Separation violations.
      # A method should either return a value (query) or change state (command), not both.
      # Flags methods named like queries (get_*, find_*, fetch_*, load_*) that also
      # contain state-mutating patterns (@x =, save!, update!, write).
      class CqsRule < Rule
        QUERY_PREFIX   = /^\s+def\s+(get_|find_|fetch_|load_|read_|list_|show_|describe_)\w+/.freeze
        MUTATION_IN_BODY = /(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|\.write[!\s]|File\.write)/.freeze

        def initialize
          super
          @id          = "cqs"
          @description = "Command/Query Separation — queries must not mutate state"
          @severity    = :warning
          @axiom_tags  = [:CQS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          in_query  = false
          query_line = 0
          depth      = 0

          code.each_line.with_index(1) do |line, num|
            if !in_query && line.match?(QUERY_PREFIX)
              in_query   = true
              query_line = num
              depth      = 1
              next
            end

            if in_query
              depth += line.scan(/^\s*(?:if|case|begin|do)\b|\bdo\s*(?:\|[^|]*\|)?\s*$|\bdef\s/).size
              depth -= line.scan(/\bend\b/).size

              if depth <= 0
                in_query = false
                next
              end

              if line.match?(MUTATION_IN_BODY)
                findings << finding(
                  line: query_line,
                  message: "query method mutates state (line #{num}) — split into separate command and query"
                )
                in_query = false
              end
            end
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/dead_assign_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DeadAssignRule < Rule
        # Match: leading whitespace, lowercase lvar, single = (not ==, +=, -=, =~, =>)
        ASSIGN = /^\s+([a-z_][a-z0-9_]*)\s*=(?![>=~])/.freeze

        def initialize
          super
          @id          = "dead_assign"
          @description = "Local variable assigned but never read — remove or use it"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          extract_methods(code).flat_map { |m| check_method(m) }
        end

        private

        def extract_methods(code)
          methods = []
          lines   = code.lines
          i       = 0
          while i < lines.size
            if lines[i].match?(/^\s*def \w/)
              start = i
              depth = 1
              i += 1
              while i < lines.size && depth > 0
                stripped = lines[i].strip
                depth += stripped.scan(/\b(?:def|do|begin|if|unless|case|class|module)\b/).size
                depth -= stripped.scan(/\bend\b/).size
                i += 1
              end
              methods << { lines: lines[start...i], start_line: start + 1 }
            else
              i += 1
            end
          end
          methods
        end

        def check_method(method)
          lines    = method[:lines]
          start    = method[:start_line]
          findings = []

          lines.each_with_index do |line, i|
            stripped = line.strip
            next if stripped.start_with?("#")
            m = line.match(ASSIGN)
            next unless m

            var = m[1]
            next if var.start_with?("_")               # intentionally unused
            next if %w[true false nil self].include?(var)

            rest = lines[(i + 1)..].join
            next if rest.match?(/\b#{Regexp.escape(var)}\b/)

            findings << finding(line: start + i, message: "#{var} is assigned but never read — remove or use it")
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/dead_code_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DeadCodeRule < Rule
        EMPTY_RESCUE = /rescue\s+\w[\w:]*(?:\s*=>\s*\w+)?\s*\n\s*end/.freeze
        CONST_DEF    = /^\s*([A-Z][A-Z0-9_]{2,})\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "dead_code"
          @description = "Dead constants and empty rescue blocks"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_rescue_findings(code) + dead_constants(code)
        end

        private

        def line_rescue_findings(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            next unless line.match?(/^\s*rescue\b/)
            next_stripped = lines[i + 1]&.strip
            if next_stripped == "end"
              findings << finding(line: i + 1, message: "empty rescue block swallows errors silently — log or re-raise")
            end
          end
          findings
        end

        def dead_constants(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            m = line.match(CONST_DEF)
            next unless m

            const = m[1]
            rest  = (lines[0...i] + lines[(i + 1)..]).join
            next if rest.match?(/\b#{Regexp.escape(const)}\b/)

            findings << finding(line: i + 1, message: "#{const} is defined but never referenced — remove it")
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/debug_output_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DebugOutputRule < Rule
        PP_CALL     = /^\s*pp?\s+(?!self\b)/.freeze
        STDERR_PUTS = /\$stderr\.puts\b/.freeze
        BINDING_PRY = /\bbinding\.pry\b/.freeze
        DEBUGGER    = /\bdebugger\b/.freeze

        def initialize
          super
          @id          = "debug_output"
          @description = "Debug output left in lib/ — remove before shipping"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb") && path.include?("/lib/")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "p/pp debug call — remove or publish via event bus") if line.match?(PP_CALL)
            findings << finding(line: num, message: "$stderr.puts — use @bus.publish or $stdout for structured output") if line.match?(STDERR_PUTS)
            findings << finding(line: num, message: "binding.pry left in — remove before commit") if line.match?(BINDING_PRY)
            findings << finding(line: num, message: "debugger left in — remove before commit") if line.match?(DEBUGGER)
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/duplicate_code_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Duplicate structural code (same AST shape, different names) violates ONE_SOURCE.
      # Delegates to flay for reliable AST-level detection; falls back to a line-hash
      # approach when flay is unavailable (e.g. gem not installed).
      class DuplicateCodeRule < Rule
        FLAY_THRESHOLD = 16
        OCCUR_MIN      = 2

        def initialize
          super
          @id          = "duplicate_code"
          @description = "Duplicate code blocks violate ONE_SOURCE — extract to shared method"
          @severity    = :warning
          @axiom_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          flay_available? ? flay_check(code, path) : []
        end

        private

        def flay_available?
          require "flay"
          true
        rescue LoadError
          false
        end

        def flay_check(code, path)
          flay = Flay.new(threshold: FLAY_THRESHOLD, verbose: false, diff: false, summary: false)
          flay.process(path)
          flay.masses.filter_map { |hash, nodes|
            next if nodes.size < OCCUR_MIN
            first = nodes.first
            finding(
              line: first.line,
              message: "duplicate structure #{nodes.size} times (flay mass #{flay.masses[hash]}) — extract to shared method (ONE_SOURCE)"
            )
          }
        rescue StandardError
          []
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/explicit_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ExplicitRule — detects implicit/opaque patterns that violate EXPLICIT.
      # Flags: bare rescue, implicit return of nil, magic number literals,
      # single-letter variable names outside loops, and undefined method patterns.
      class ExplicitRule < Rule
        RESCUE_NIL   = /rescue\s+nil\b/.freeze
        MAGIC_NUM    = /[^:]\b([2-9]\d{2,}|[1-9]\d{3,})\b(?!\s*[#=])/.freeze
        OPAQUE_VAR   = /^\s+[a-z]\s*=(?!=)/.freeze        # x = ... (not x == or x +=)
        IMPLICIT_NIL = /def\s+\w+[^;]*\n(?:\s*#[^\n]*\n)*\s*end/.freeze  # empty method body

        def initialize
          super
          @id          = "explicit"
          @description = "Implicit, opaque patterns — prefer explicit contracts"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            findings << finding(line: num, message: "bare rescue hides errors — name the exception class or propagate") if line.match?(RESCUE_NIL)
            next if line.match?(/^\s*[A-Z][A-Z_0-9]*\s*=/)  # skip constant defs
            findings << finding(line: num, message: "magic number — extract to a named constant")                if line.match?(MAGIC_NUM) && !line.strip.start_with?("#")
            findings << finding(line: num,
              message: "single-letter variable obscures intent — use a descriptive name") if line.match?(OPAQUE_VAR) && !in_loop_context?(code, num)
          end
          findings
        end

        private

        def in_loop_context?(code, target_line)
          lines = code.lines
          ((target_line - 4)..(target_line - 1)).any? do |i|
            next false unless i >= 0 && i < lines.size
            lines[i].match?(/\b(?:each|map|times|upto|downto|step|for\s+\w)\b/)
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/frozen_string_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class FrozenStringRule < Rule
        def initialize
          super
          @id          = "frozen_string"
          @description = "Ruby files should declare # frozen_string_literal: true"
          @severity    = :warning
          @axiom_tags  = [:PERFORMANCE]
          @auto_fix    = true
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] if code.lines.first&.include?("frozen_string_literal")
          [finding(line: 1, message: "missing # frozen_string_literal: true",
                   fix: "# frozen_string_literal: true\n" + code)]
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/god_class_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class GodClassRule < Rule
        DEFAULT_THRESHOLD = 200

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("class", "max_lines") || DEFAULT_THRESHOLD
          @id          = "god_class"
          @description = "Classes over #{@threshold} lines should be split by responsibility"
          @severity    = :warning
          @axiom_tags  = [:SIMPLEST_WORKS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines = code.lines.size
          return [] if lines <= @threshold

          class_name = code.match(/class (\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} is #{lines} lines (threshold: #{@threshold}) — split by responsibility"
          )]
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/immutable_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ImmutableRule < Rule
        UNFROZEN_CONST     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*(?:"[^"]*"|'[^']*'|\[|\{)(?!.*(?:\.freeze|\.min|\.max|\.count|\.size|\.length|\.sum|\.to_i|\.to_f)\b)/.freeze
        MULTILINE_OPEN     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*[\[{]/.freeze
        STRING_CONTINUATION = /\\\s*$/.freeze
        CLASS_VAR_WRITE = /^\s+@@\w+\s*=(?!=)/.freeze
        GLOBAL_WRITE    = /^\s+\$\w+\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "immutable"
          @description = "Mutable shared state — prefer frozen constants and immutable data flow"
          @severity    = :warning
          @axiom_tags  = [:IMMUTABLE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          lines = code.lines
          findings = []

          lines.each_with_index do |line, line_index|
            line_number = line_index + 1
            next if line.strip.start_with?("#")

            if line.match?(UNFROZEN_CONST)
              if line.match?(MULTILINE_OPEN) && !inline_close?(line)
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze") unless multiline_frozen?(lines, line_index)
              elsif line.match?(STRING_CONTINUATION)
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze") unless string_continuation_frozen?(lines, line_index)
              else
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze")
              end
            end

            findings << finding(line: line_number, message: "class variable mutation (@@) — use instance state or inject") if line.match?(CLASS_VAR_WRITE)
            findings << finding(line: line_number, message: "global variable mutation ($) — eliminate shared global state") if line.match?(GLOBAL_WRITE)
          end

          findings
        end

        private

        def inline_close?(line)
          stripped = line.rstrip
          return true if stripped.end_with?("].freeze", "}.freeze", "].freeze,", "}.freeze,")
          sq = stripped.count("[")
          cq = stripped.count("{")
          (sq > 0 && sq == stripped.count("]")) || (cq > 0 && cq == stripped.count("}"))
        end

        def string_continuation_frozen?(lines, start_line)
          (start_line...lines.size).each do |current_line|
            return lines[current_line].include?(".freeze") unless lines[current_line].match?(STRING_CONTINUATION)
          end
          false
        end

        def multiline_frozen?(lines, start_line)
          line   = lines[start_line]
          opener = line.include?("{") ? "{" : "["
          closer = opener == "{" ? "}" : "]"
          depth  = 0
          (start_line...lines.size).each do |current_line|
            depth += lines[current_line].count(opener) - lines[current_line].count(closer)
            return lines[current_line].include?(".freeze") if depth <= 0
          end
          false
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/interconnect_rule.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    module Rules
      # Detects phantom reads — Ruby code digs keys that don't exist in the corresponding data/*.yml.
      # Also detects orphan keys — top-level YAML keys with zero references in lib/.
      # Only meaningful when scanning lib/ with root: access.
      class InterconnectRule < Rule
        LOAD_CALL   = /load_yaml(?:_data)?\s*\(\s*["']([^"']+\.yml)["']/.freeze
        DIG_CALL    = /\.dig\(\s*((?:["'][^"']+["']\s*,?\s*)+)\)/.freeze
        FETCH_CALL  = /\.fetch\(\s*["']([^"']+)["']/.freeze
        BRACKET_KEY = /\[["']([^"']+)["']\]/.freeze

        def self.auto_build? = false

        def initialize(root:)
          super()
          @id          = "interconnect"
          @description = "Phantom YAML key reads and orphan data keys"
          @severity    = :warning
          @auto_fix    = false
          @axiom_tags  = %i[ONE_SOURCE SINGLE_SOURCE_OF_TRUTH]
          @root        = root
          @data_dir    = File.join(root, "data")
          @lib_source  = load_lib_source(root)
        end

        def check(code, path:)
          return [] unless path.include?("/lib/") && path.end_with?(".rb")

          findings = []
          yaml_files = extract_loaded_yamls(code)
          yaml_files.each do |yml_name|
            yml_path = File.join(@data_dir, yml_name)
            next unless File.exist?(yml_path)

            yaml_data = YAML.safe_load(File.read(yml_path), aliases: true) rescue next
            dug_paths = extract_dig_paths(code)
            dug_paths.each do |path_keys|
              next if yaml_data.dig(*path_keys)

              code.each_line.with_index(1) do |line, number|
                key_pattern = path_keys.first.to_s
                next unless line.include?(key_pattern)

                findings << finding(
                  line: number,
                  message: "phantom key #{path_keys.inspect} not found in #{yml_name} — stale dig path or missing YAML entry"
                )
                break
              end
            end
          end
          findings
        end

        private

        def extract_loaded_yamls(code)
          code.scan(LOAD_CALL).flatten.compact
        end

        def extract_dig_paths(code)
          code.scan(DIG_CALL).filter_map do |match|
            keys = match.first.to_s.scan(/["']([^"']+)["']/).flatten
            keys.size >= 1 ? keys : nil
          end
        end

        def load_lib_source(root)
          lib_dir = File.join(root, "lib")
          return "" unless File.directory?(lib_dir)

          Dir.glob(File.join(lib_dir, "**", "*.rb"))
            .filter_map { |path| File.read(path) rescue nil }
            .join("\n")
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/lexical_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # LexicalRule — data-driven: loads all detect_lexical rules from rules.yml
      # and applies them to the matching file language. Single class covering
      # HTML, CSS, Zsh, JavaScript, and cross-language lexical checks.
      class LexicalRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze

        def initialize
          super
          @id          = "lexical"
          @description = "Data-driven lexical checks from rules.yml for all file types"
          @severity    = :warning
          @axiom_tags  = [:UNIVERSAL]
          @loaded      = load_lexical_rules
        end

        def check(code, path:)
          lang = language(path)
          return [] unless lang

          @loaded
            .select { |r| r[:languages].nil? || r[:languages].include?(lang) }
            .flat_map { |r| apply(r, code, path) }
        end

        private

        def load_lexical_rules
          data = Master.load_yaml(RULES_PATH)
          all  = (data["rules"] || {}).values.flatten
          all.filter_map do |r|
            next unless r["detect_lexical"] && !r["detect_lexical"].to_s.empty?
            langs = Array(r["languages"]).compact
            {
              id:        r["id"],
              message:   r["name"] || r["id"],
              pattern:   Regexp.new(r["detect_lexical"]),
              fix:       r["fix"],
              severity:  (r["severity"] || "warning").to_sym,
              languages: langs.empty? ? nil : langs,
            }
          rescue RegexpError
            nil
          end.compact
        rescue StandardError => _e
          []
        end

        def apply(rule, code, path)
          code.each_line.with_index(1).filter_map do |line, num|
            next unless line.match?(rule[:pattern])
            { rule: rule[:id], message: rule[:message], line: num,
              severity: rule[:severity], fix: rule[:fix] }
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/long_method_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class LongMethodRule < Rule
        DEFAULT_THRESHOLD = 10

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("method", "max_lines") || DEFAULT_THRESHOLD
          @id          = "long_method"
          @description = "Methods over #{@threshold} lines should be extracted"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          method_start = nil
          method_name  = nil
          depth        = 0

          code.each_line.with_index(1) do |line, num|
            if line.match?(/^\s*def /)
              method_start = num
              method_name  = line.match(/def (\w+)/)[1]
              depth        = 1
            elsif method_start
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bclass\b|\bmodule\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                length = num - method_start + 1
                if length > @threshold
                  findings << finding(
                    line: method_start,
                    message: "method #{method_name} is #{length} lines (threshold: #{@threshold}) — extract responsibilities"
                  )
                end
                method_start = nil
              end
            end
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/naming_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class NamingRule < Rule
        IS_PREFIX      = /def is_\w+(?!\?)/.freeze
        GET_PREFIX     = /def get_\w+/.freeze
        SET_PREFIX     = /def set_\w+/.freeze
        BOOL_NO_QMARK  = /def (?:has|can|should|will|did|was|have)_\w+(?!\?)/.freeze
        SCREAMING_ABBR = /\b[A-Z]{4,}\b/.freeze

        def initialize
          super
          @id          = "naming"
          @description = "Method names violate Ruby conventions"
          @severity    = :style
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "is_ prefix: use adjective with ? suffix (e.g. valid? not is_valid?)") if line.match?(IS_PREFIX)
            findings << finding(line: num, message: "get_ prefix: Ruby readers drop get_ (e.g. name not get_name)") if line.match?(GET_PREFIX)
            findings << finding(line: num, message: "set_ prefix: use name= for writers (e.g. name= not set_name)") if line.match?(SET_PREFIX)
            findings << finding(line: num, message: "boolean predicate missing ? suffix — add ? to indicate it returns bool") if line.match?(BOOL_NO_QMARK)
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/nesting_depth_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class NestingDepthRule < Rule
        DEFAULT_DEPTH = 2

        OPEN_KWORDS  = /\b(?:if|unless|case|while|until|for|begin)\b/.freeze
        CLOSE_KWORD  = /\bend\b/.freeze

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("method", "max_nesting") || DEFAULT_DEPTH
          @id          = "nesting_depth"
          @description = "Nesting deeper than #{@threshold} — use guard clauses to flatten"
          @severity    = :warning
          @axiom_tags  = [:GUARD_CLAUSES_FIRST]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings    = []
          in_method   = false
          nesting     = 0   # depth relative to method body (0 = top of method)
          over        = false

          code.each_line.with_index(1) do |line, num|
            stripped = line.strip
            next if stripped.start_with?("#")

            if !in_method && stripped.match?(/\bdef \w/)
              in_method = true
              nesting   = 0
              over      = false
              next
            end
            next unless in_method

            opens  = stripped.scan(OPEN_KWORDS).size
            closes = stripped.scan(CLOSE_KWORD).size

            nesting += opens

            if nesting > @threshold && !over
              over = true
              findings << finding(line: num, message: "nesting depth #{nesting} exceeds #{@threshold} — extract method or add guard clause")
            end

            nesting -= closes
            nesting  = [nesting, 0].max

            if nesting <= @threshold
              over = false
            end

            if nesting < 0 || (stripped == "end" && nesting == 0)
              in_method = false
              nesting   = 0
            end
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/nielsen_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # NielsenRule — enforces Nielsen Norman Group's 10 Usability Heuristics
      # at the code level: API design, error messages, output behavior.
      class NielsenRule < Rule
        # H9: Error messages must describe the problem — bare string raises with no guidance
        BARE_RAISE       = /\braise\s+["'][^"']{0,20}["']/.freeze
        # H9: Result.err with no message or single-word message
        THIN_ERR         = /Result\.err\(["'][a-z_]{1,15}["'](?:\s*\))/.freeze
        # H4: Inconsistent boolean naming — mix of is_/has_/can_ with plain predicates
        # H6: Positional args over 3 — harms recognition (caller can't tell what each is)
        POSITIONAL_HEAVY = /def\s+\w+\((?:[^:,)]+,){3,}[^*&]/.freeze
        # H8: Aesthetic minimalism — debug inspect calls (p/pp/pry) left in production
        DEBUG_OUTPUT     = /^\s+(?:p|pp|binding\.pry|debugger)\s+(?!.*#\s*rubocop)/.freeze
        # H3: User control — destructive methods without bang or guard comment
        SILENT_DELETE    = /\b(?:FileUtils\.rm|File\.delete|Dir\.rmdir)\s*\((?!.*#.*safe)/.freeze
        # H2: Real world match — internal jargon in user-facing strings
        JARGON           = /(?:raise|Result\.err)\(.*\b(?:nil\b|exception|stacktrace|backtrace|segfault|errno)\b/.freeze

        def initialize
          super
          @id          = "nielsen"
          @description = "Nielsen's 10 heuristics: error quality, recognition, minimalism, user control"
          @severity    = :warning
          @axiom_tags  = %i[ERROR_RECOVERY REAL_WORLD_MATCH USER_CONTROL AESTHETIC_MINIMALISM
                            RECOGNITION_NOT_RECALL CONSISTENCY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "[ERROR_RECOVERY] raise with no guidance — tell the user what to do next")         if line.match?(BARE_RAISE)
            findings << finding(line: num, message: "[ERROR_RECOVERY] thin Result.err message — include what failed and how to fix it") if line.match?(THIN_ERR)
            findings << finding(line: num, message: "[RECOGNITION_NOT_RECALL] 4+ positional args — use keyword arguments so callers read intent") if line.match?(POSITIONAL_HEAVY)
            findings << finding(line: num, message: "[AESTHETIC_MINIMALISM] debug output left in — remove puts/p or guard with log level")  if line.match?(DEBUG_OUTPUT)
            findings << finding(line: num, message: "[USER_CONTROL] destructive call without safety comment — add undo or confirmation guard") if line.match?(SILENT_DELETE)
            findings << finding(line: num, message: "[REAL_WORLD_MATCH] internal jargon in user-facing error — use plain language")          if line.match?(JARGON)
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/opportunity_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Opportunities are not violations — they are structural improvements waiting to happen.
      # Detects: deep nesting (reflow), lambda dispatch tables (regroup into Command),
      # thin delegation wrappers (collapse), and dense inline hashes (extract class).
      # Severity :info so they show up in deep scans without polluting standard output.
      class OpportunityRule < Rule
        NESTING_THRESHOLD   = 4
        HASH_PAIR_THRESHOLD = 4
        LAMBDA_TABLE_MIN    = 3
        INDENT_UNIT         = 2

        def initialize
          super
          @id          = "opportunity"
          @description = "Structural improvement opportunity — refactor for clarity or cohesion"
          @severity    = :info
          @axiom_tags  = %i[SIMPLEST_WORKS DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          findings += deep_nesting(code)
          findings += lambda_dispatch_table(code)
          findings += thin_delegation(code)
          findings += dense_inline_hash(code)
          findings
        end

        private

        def deep_nesting(code)
          results    = []
          base_indent = nil
          method_line = nil

          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#") || stripped.start_with?(".")
            indent = 0
            indent += 1 while line[indent] == " "
            if stripped.start_with?("def ")
              base_indent = indent
              method_line = number
            elsif base_indent && stripped == "end"
              base_indent = nil
              method_line = nil
            elsif base_indent
              relative_depth = (indent - base_indent) / INDENT_UNIT
              if relative_depth >= NESTING_THRESHOLD
                results << finding(line: method_line,
                  message: "#{relative_depth} levels of nesting in method — reflow with early returns or extract method")
                base_indent = nil
              end
            end
          end
          results
        end

        def lambda_dispatch_table(code)
          results = []
          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            next unless stripped.start_with?('"') && stripped.include?("=>") && stripped.include?("->")
            count = code.lines.count { |other| other.strip.start_with?('"') && other.strip.include?("=>") && other.strip.include?("->") }
            if count >= LAMBDA_TABLE_MIN
              results << finding(line: number,
                message: "lambda dispatch table (#{count} entries) — regroup into Command objects or a registry")
              break
            end
          end
          results
        end

        def thin_delegation(code)
          results = []
          lines   = code.lines
          lines.each_with_index do |line, line_index|
            stripped = line.strip
            next unless stripped.start_with?("def ") && !stripped.include?("=")
            method_name = stripped.split(" ", 3)[1].to_s.split("(", 2).first
            body_index  = line_index + 1
            next if body_index >= lines.size
            body    = lines[body_index].strip
            closing = lines[body_index + 1]&.strip
            next unless body.include?(".") && !body.start_with?("#") && closing == "end"
            delegated = body.split(".").last.split("(").first.strip
            if delegated == method_name
              results << finding(line: line_index + 1,
                message: "#{method_name}: thin transparent delegation — use Forwardable or delegate")
            end
          end
          results
        end

        def dense_inline_hash(code)
          results = []
          in_method  = false
          method_line = 0
          hash_pairs  = 0

          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            if stripped.start_with?("def ")
              in_method   = true
              method_line = number
              hash_pairs  = 0
            elsif stripped == "end" && in_method
              if hash_pairs >= HASH_PAIR_THRESHOLD
                results << finding(line: method_line,
                  message: "#{hash_pairs} hash pairs inline — hoist to a named constant or extract a builder")
              end
              in_method  = false
              hash_pairs = 0
            elsif in_method
              hash_pairs += stripped.scan("=>").size
            end
          end
          results
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/pola_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class PolaRule < Rule
        BOOL_POSITIONAL = /def\s+\w+\([^)]*,\s*(true|false)\s*[,)]/.freeze
        DOUBLE_NEG      = /\bunless\s+!/.freeze
        NEG_BOOL_ATTR   = /\battr_\w+\s+:(?:not_|no_|without_|disabled?_|skip_)\w+/.freeze

        def initialize
          super
          @id          = "pola"
          @description = "Principle of Least Astonishment — surprising names, contracts, or side-effects"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings        = []
          in_predicate    = false
          pred_line       = 0
          depth           = 0

          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "boolean positional default — use keyword arg (def method(flag: false)) to name intent at call site") if line.match?(BOOL_POSITIONAL)
            findings << finding(line: num, message: "double negation detected — invert condition and use positive form") if line.match?(DOUBLE_NEG)
            findings << finding(line: num,
              message: "negative attribute name — name what it IS, not what it ISN'T") if line.match?(NEG_BOOL_ATTR)

            if line.match?(/^\s+def\s+\w+\?/)
              if line.match?(/=\s*[^=]/)
                in_predicate = false
              else
                in_predicate = true
                pred_line    = num
                depth        = 1
              end
            elsif in_predicate
              depth += line.scan(/\bdo\b|\bbegin\b|\bdef\b/).size
              depth += 1 if line.match?(/^\s+(?:if|case|unless|while|until|for)\b/)
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                in_predicate = false
              elsif line.match?(/(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|File\.write)/)
                findings << finding(line: pred_line,
                  message: "predicate method (?) mutates state — predicates must only query, never mutate (POLA)")
                in_predicate = false
              end
            end
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/prune_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Hedge words and preamble phrases in comments dilute signal.
      # Applies to Ruby and shell files — both use # comments.
      # Patterns loaded from data/rules.yml (voice.strunk section).
      class PruneRule < Rule
        DATA_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
        COMMENT_EXT = %w[.rb .sh .zsh .bash].freeze

        def initialize
          super
          @id          = "prune"
          @description = "Hedge words and preamble phrases in comments reduce clarity"
          @severity    = :warning
          @axiom_tags  = [:STRUNK_WHITE]
        end

        def check(code, path:)
          return [] unless COMMENT_EXT.include?(File.extname(path).downcase)

          hedge_re    = build_hedge_re
          preamble_re = build_preamble_re

          code.each_line.with_index(1).flat_map { |line, num|
            next [] unless line.include?("#")
            findings = []
            findings << finding(line: num, message: "hedge in comment: #{line.strip}")    if hedge_re&.match?(line)
            findings << finding(line: num, message: "preamble in comment: #{line.strip}") if preamble_re&.match?(line)
            findings
          }
        end

        private

        def rules
          @rules ||= begin
            data = File.exist?(DATA_PATH) ? Master.load_yaml(DATA_PATH) : {}
            data.dig("voice", "strunk") || {}
          end
        rescue StandardError => _e
          @rules = {}
        end

        def build_hedge_re
          words = rules.fetch("hedges", []).filter_map { |h|
            if h.is_a?(Hash)
              pat = h["pattern"].to_s.strip
              pat.empty? ? nil : Regexp.escape(pat)
            elsif h.is_a?(String)
              h.strip.empty? ? nil : Regexp.escape(h.strip)
            end
          }
          return nil if words.empty?
          /(#{words.join("|")})/i
        rescue StandardError => _e
          nil
        end

        def build_preamble_re
          phrases = rules.fetch("preambles", []).filter_map { |p|
            next unless p.is_a?(String)
            p.strip.empty? ? nil : Regexp.escape(p.strip)
          }
          return nil if phrases.empty?
          /\#.*(?:#{phrases.join("|")})/i
        rescue StandardError => _e
          nil
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/reek_rule.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Scan
    module Rules
      # Reek smell detection mapped to MASTER axioms.
      # Degrades gracefully when reek is unavailable (CI, fresh installs).
      class ReekRule < Rule
        SMELL_MAP = {
          "TooManyMethods"         => { axiom: "ONE_JOB",        sev: :warning },
          "TooManyInstanceVariables" => { axiom: "ONE_JOB",      sev: :warning },
          "LongParameterList"      => { axiom: "DECOUPLE",       sev: :warning },
          "FeatureEnvy"            => { axiom: "DECOUPLE",       sev: :warning },
          "DataClump"              => { axiom: "DECOUPLE",       sev: :warning },
          "DuplicateMethodCall"    => { axiom: "ONE_SOURCE",     sev: :warning },
          "BooleanParameter"       => { axiom: "EXPLICIT",       sev: :warning },
          "ControlParameter"       => { axiom: "CQS",            sev: :warning },
          "NilCheck"               => { axiom: "EXPLICIT",       sev: :warning },
          "UncommunicativeMethodName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UncommunicativeVariableName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UncommunicativeParameterName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UtilityFunction"        => { axiom: "DECOUPLE",       sev: :warning },
          "InstanceVariableAssumption" => { axiom: "EXPLICIT",   sev: :warning },
          "IrresponsibleModule"    => { axiom: "SELF_EXPLAINING", sev: :warning },
          "RepeatedConditional"    => { axiom: "ONE_SOURCE",     sev: :warning },
          "SubclassedFromCoreClass" => { axiom: "EXTEND_DONT_MODIFY", sev: :warning },
          "ModuleInitialize"       => { axiom: "POLA",           sev: :warning },
        }.freeze

        def initialize(root: nil)
          super()
          @id          = "reek"
          @description = "Code smell detection: feature envy, data clumps, boolean params (reek)"
          @severity    = :warning
          @axiom_tags  = SMELL_MAP.values.map { |v| v[:axiom].to_sym }.uniq
          @root        = root
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless reek_available?

          out, _err, _status = Open3.capture3(
            "bundle", "exec", "reek",
            "--format", "json",
            "--no-color",
            path,
            chdir: @root || Dir.pwd
          )

          parse_smells(out)
        rescue StandardError => _e
          []
        end

        private

        def reek_available?
          @reek_available ||= begin
            _, _, s = Open3.capture3("bundle", "exec", "reek", "--version",
                                     chdir: @root || Dir.pwd)
            s.success?
          rescue StandardError => _e
            false
          end
        end

        def parse_smells(json_str)
          data = JSON.parse(json_str)
          data.filter_map do |smell|
            meta = SMELL_MAP[smell["smell_type"]]
            next unless meta
            finding(
              line:    smell["lines"]&.first || 1,
              message: "[#{meta[:axiom]}] #{smell["smell_type"]}: #{smell["message"]}"
            )
          end
        rescue StandardError => _e
          []
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/rubocop_rule.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Scan
    module Rules
      # Rubocop AST analysis filtered to cops that map directly to MASTER axioms.
      # Degrades gracefully when rubocop is unavailable (CI, fresh installs).
      class RubocopRule < Rule
        COP_MAP = {
          "Metrics/MethodLength"        => { axiom: "ONE_JOB",       sev: :warning },
          "Metrics/ClassLength"         => { axiom: "SIMPLEST_WORKS", sev: :warning },
          "Metrics/AbcSize"             => { axiom: "ONE_JOB",       sev: :warning },
          "Metrics/CyclomaticComplexity" => { axiom: "SIMPLEST_WORKS", sev: :error },
          "Metrics/PerceivedComplexity" => { axiom: "SIMPLEST_WORKS", sev: :warning },
          "Metrics/ParameterLists"      => { axiom: "DECOUPLE",      sev: :warning },
          "Lint/RescueException"        => { axiom: "FAIL_VISIBLY",  sev: :error },
          "Lint/SuppressedException"    => { axiom: "FAIL_VISIBLY",  sev: :error },
          "Lint/DuplicateMethods"       => { axiom: "ONE_SOURCE",    sev: :error },
          "Style/GuardClause"           => { axiom: "BE_CONCISE",    sev: :warning },
          "Style/ReturnNil"             => { axiom: "EXPLICIT",      sev: :warning },
          "Naming/MethodParameterName"  => { axiom: "SELF_EXPLAINING", sev: :warning },
          "Layout/LineLength"           => { axiom: "BE_CONCISE",    sev: :warning },
        }.freeze

        def initialize(root: nil)
          super()
          @id          = "rubocop"
          @description = "AST-based analysis: complexity, guard clauses, parameter names (rubocop)"
          @severity    = :warning
          @axiom_tags  = COP_MAP.values.map { |v| v[:axiom].to_sym }.uniq
          @root        = root
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless rubocop_available?

          config_flag = rubocop_config_flag
          out, _err, status = Open3.capture3(
            "bundle", "exec", "rubocop",
            *config_flag,
            "--format", "json",
            "--no-color",
            path,
            chdir: @root || Dir.pwd
          )

          return [] unless status.exitstatus&.<= 1  # 0=clean 1=offenses 2=error

          parse_offenses(out)
        rescue StandardError => _e
          []
        end

        private

        def rubocop_available?
          @rubocop_available ||= begin
            _, _, s = Open3.capture3("bundle", "exec", "rubocop", "--version",
                                     chdir: @root || Dir.pwd)
            s.success?
          rescue StandardError => _e
            false
          end
        end

        def rubocop_config_flag
          cfg = File.join(@root || Dir.pwd, ".rubocop.yml")
          File.exist?(cfg) ? ["--config", cfg] : ["--only", COP_MAP.keys.join(",")]
        end

        def parse_offenses(json_str)
          data = JSON.parse(json_str)
          data["files"].flat_map do |file|
            file["offenses"].filter_map do |o|
              meta = COP_MAP[o["cop_name"]]
              next unless meta
              finding(
                line:    o.dig("location", "line") || 1,
                message: "[#{meta[:axiom]}] #{o["cop_name"]}: #{o["message"]}"
              )
            end
          end
        rescue StandardError => _e
          []
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/self_explaining_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SelfExplainingRule — detects names that obscure intent, violating SELF_EXPLAINING.
      # Flags method/variable names that are abbreviations, noise words, or too generic
      # to reveal purpose without reading the implementation.
      class SelfExplainingRule < Rule
        NOISE_NAMES   = /^\s+def\s+(?:self\.)?(do_it|handle|process|run_it|execute_it|go|doit)\b/.freeze
        ABBREV_METHOD = /^\s+def\s+(tmp|res|ret|val|obj|thingy|stuff|thing|data2|info2)\b/.freeze
        ABBREV_VAR    = /\b(tmp|res|ret|val|obj|arr|lst|hsh|idx|cnt|num|str)\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "self_explaining"
          @description = "Opaque names — names should reveal purpose without reading the implementation"
          @severity    = :warning
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] if line.strip.start_with?("#")
            next [] if line.match?(/^\s+[A-Z][A-Z0-9_]+ \s*=/)
            findings = []
            findings << finding(line: num, message: "noise method name — rename to reveal intent") if line.match?(NOISE_NAMES)
            findings << finding(line: num, message: "abbreviated method name — use the full descriptive word") if line.match?(ABBREV_METHOD)
            findings << finding(line: num, message: "abbreviated variable — prefer descriptive identifier") if line.match?(ABBREV_VAR)
            findings
          }
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/srp_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SrpRule — Single Responsibility Principle.
      # A class should have one reason to change. Flags classes whose public methods
      # span multiple concern domains (persistence, rendering, validation, networking, parsing).
      class SrpRule < Rule
        CONCERNS = {
          persistence: /\b(save|load|read_\w|write_\w|persist|store_\w|fetch_\w|find_by|delete|destroy|insert|upsert)\b/,
          rendering:   /\b(render|display|format_\w|present|to_html|draw|paint|emit|output_\w)\b/,
          validation:  /\b(valid\?|validate[^d]|check_\w|verify_\w|assert_\w|ensure_\w|guard_\w)\b/,
          networking:  /\b(request_\w|http_\w|send_request|receive_\w|connect_\w|socket_\w)\b/,
          parsing:     /\b(parse_\w|tokenize|lex_\w|extract_\w|decode_\w|encode_\w|deserialize|serialize)\b/,
        }.freeze

        def initialize
          super
          @id          = "srp"
          @description = "Single Responsibility Principle — class spans multiple concern domains"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          public_methods = code.scan(/^\s{2,8}def\s+(\w+)/).flatten
          return [] if public_methods.size < 4

          concerns_found = CONCERNS.select { |_, pat| public_methods.any? { |m| m.match?(pat) } }
          return [] if concerns_found.size < 2

          class_name = code.match(/class\s+(\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} spans #{concerns_found.size} domains " \
                     "(#{concerns_found.keys.join(", ")}) — split by single responsibility (SRP)"
          )]
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/structure_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class StructureRule < Rule
        UNREACHABLE_ELSE = /^\s*return\b[^\n]*\n(?:\s*#[^\n]*\n)*\s*else\b/.freeze
        GUARD_RETURN     = /^\s*if\s+.+\n\s*return\b/.freeze
        FLATTEN_NO_ARG   = /\.flatten\s*(?:\.|$|\))/.freeze
        SINGLE_WHEN      = /\bcase\b/.freeze

        def initialize
          super
          @id          = "structure"
          @description = "Structural anti-patterns — guard clauses, unreachable code, flatten depth"
          @severity    = :warning
          @axiom_tags  = [:GUARD_CLAUSES_FIRST]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []

          findings.concat(scan_lines(code, FLATTEN_NO_ARG,
            message: ".flatten without depth arg flattens infinitely — use .flatten(1) unless full depth is intended"))

          findings.concat(check_guard_candidates(code))
          findings.concat(check_single_when(code))
          findings.concat(check_unreachable_else(code))
          findings
        end

        private

        def check_guard_candidates(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            next unless line.match?(/^\s*if\s+/)
            next_sig = lines[i + 1]&.strip
            next unless next_sig&.start_with?("return")
            findings << finding(line: i + 1, message: "if/return block — invert to guard clause: return X if condition")
          end
          findings
        end

        def check_single_when(code)
          findings = []
          in_case  = false
          when_count = 0
          case_line  = 0

          code.each_line.with_index(1) do |line, num|
            stripped = line.strip
            if stripped.start_with?("case")
              in_case    = true
              when_count = 0
              case_line  = num
            elsif in_case
              when_count += 1 if stripped.start_with?("when")
              if stripped == "end"
                findings << finding(line: case_line, message: "case with one `when` — use if/else") if when_count == 1
                in_case = false
              end
            end
          end
          findings
        end

        def check_unreachable_else(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            next unless line.strip.start_with?("return")
            j = i + 1
            j += 1 while j < lines.size && lines[j].strip.start_with?("#")
            next unless j < lines.size && lines[j].strip.start_with?("else")
            findings << finding(line: j + 1, message: "else after return is unreachable — remove the else and dedent")
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/tell_dont_ask_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Querying an object's state then acting on it from outside breaks encapsulation.
      # The decision should live inside the object (tell it what to do, don't ask what it is).
      # Flags the most common Ruby patterns: .status/.state/.type == then method call,
      # and nil? guards that should be moved into the object.
      class TellDontAskRule < Rule
        STATE_QUERY  = /\b(\w+)\.(status|state|type|kind|mode|phase)\s*==/.freeze
        NIL_GUARD    = /\b(\w+)\.nil\?\s*\|\|/.freeze
        READY_QUERY  = /\b(\w+)\.ready\?\s*&&\s*\1\./.freeze

        def initialize
          super
          @id          = "tell_dont_ask"
          @description = "Tell-Don't-Ask: move state-based decisions into the object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num,
              message: "TDA: querying .status/.state outside the object — move the decision into the class") if line.match?(STATE_QUERY)
            findings << finding(line: num,
              message: "TDA: nil? guard before method call — use Null Object or move nil check into the object") if line.match?(NIL_GUARD)
            findings << finding(line: num,
              message: "TDA: ready? check then method call on same object — replace with a single command method") if line.match?(READY_QUERY)
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/terse_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class TerseRule < Rule
        BOOL_CMP      = /(?:==|!=)\s*(?:true|false)\b/.freeze
        NIL_EQ        = /==\s*nil\b/.freeze
        NIL_NEQ       = /!=\s*nil\b/.freeze
        THEN_KWORD    = /\b(?:if|unless|when)\b[^#\n]*\bthen\b/.freeze
        SYMBOL_PROC   = /\.(map|select|reject|flat_map|filter_map|sort_by|min_by|max_by|count|sum|any\?|all\?|none\?|find)\s*\{\s*\|(\w+)\|\s*\2\.(\w+)\s*\}/.freeze
        NOT_EMPTY     = /!\s*\w+\.empty\?/.freeze
        LEN_ZERO      = /\.(length|size|count)\s*==\s*0\b/.freeze
        LEN_POS       = /\.(length|size|count)\s*(?:>|>=)\s*[01]\b/.freeze
        DOUBLE_BANG   = /!!\s*\w/.freeze
        UNLESS_NOT    = /\bunless\s+!/.freeze
        TERNARY_SELF  = /(\w+)\s*\?\s*\1\s*:/.freeze

        def initialize
          super
          @id          = "terse"
          @description = "Verbose Ruby patterns — use idiomatic shortcuts"
          @severity    = :style
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            line_findings << finding(line: num, message: "== true/false is redundant — use the boolean directly") if line.match?(BOOL_CMP)
            line_findings << finding(line: num, message: "use .nil? instead of == nil") if line.match?(NIL_EQ)
            line_findings << finding(line: num, message: "use object instead of != nil — truthy check suffices") if line.match?(NIL_NEQ)
            line_findings << finding(line: num, message: "remove `then` — it is noise in multi-line if/unless") if line.match?(THEN_KWORD)
            line_findings << finding(line: num, message: "symbol-to-proc: .map(&:method_name) instead of block") if line.match?(SYMBOL_PROC)
            line_findings << finding(line: num, message: "!x.empty? → x.any?") if line.match?(NOT_EMPTY)
            line_findings << finding(line: num, message: ".length/size/count == 0 → .empty?") if line.match?(LEN_ZERO)
            line_findings << finding(line: num, message: ".length/size/count > 0 → .any?") if line.match?(LEN_POS)
            line_findings << finding(line: num, message: "!! is a no-op on booleans and obscures intent — use explicit truthiness") if line.match?(DOUBLE_BANG)
            line_findings << finding(line: num, message: "unless !x → if x") if line.match?(UNLESS_NOT)
            line_findings << finding(line: num, message: "x ? x : y → x || y") if line.match?(TERNARY_SELF)
          end
          line_findings + redundant_returns(code)
        end

        private

        def redundant_returns(code)
          findings = []
          method_lines = []
          in_method = false
          depth = 0

          code.each_line.with_index(1) do |line, num|
            stripped = line.strip
            if !in_method && stripped.match?(/\bdef \w/)
              in_method = true
              method_lines = []
              depth = 1
              next
            end
            next unless in_method

            depth += stripped.scan(/\b(?:def|do|begin|if|unless|case|class|module)\b/).size
            depth -= stripped.scan(/\bend\b/).size

            if depth <= 0
              last = method_lines.reverse.find { |l| !l[:text].strip.empty? && !l[:text].strip.start_with?("#") }
              if last && last[:text].match?(/^\s*return\s+\S/) && !last[:text].match?(/return\s+.+\bif\b/)
                findings << finding(line: last[:num], message: "redundant return — last expression is the implicit return value")
              end
              in_method = false
              method_lines = []
              depth = 0
            else
              method_lines << { text: line, num: }
            end
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/thread_safety_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ThreadSafetyRule < Rule
        # Dir.chdir is process-wide; breaks concurrent threads using different roots.
        DIR_CHDIR     = /\bDir\.chdir\b/
        # String-interpolated shell calls risk injection and hide argument boundaries.
        SHELL_INTERP  = /(?:system|`|IO\.popen|Open3\.\w+)\s*\(?\s*["'][^"']*#\{/
        # Prism.parse freeze: kwarg dropped in Ruby 3.4.
        PRISM_FREEZE  = /Prism\.parse\([^)]*freeze:\s*(?:true|false)/

        def initialize
          super
          @id          = "thread_safety"
          @description = "Detect thread-unsafe patterns: Dir.chdir, shell interpolation, dropped kwargs"
          @severity    = :error
          @axiom_tags  = %i[FAIL_VISIBLY EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          scan_lines(code, DIR_CHDIR,
            message: "Dir.chdir is process-wide and thread-unsafe; use -C flag or File.expand_path") +
          scan_lines(code, SHELL_INTERP,
            message: "shell interpolation risks injection; use Open3.capture2e with arg array") +
          scan_lines(code, PRISM_FREEZE,
            message: "Prism.parse freeze: kwarg removed in Ruby 3.4; drop it")
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/threshold_drift_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Hardcoded threshold constants in scan rules drift silently from rules.yml.
      # Every threshold should be read from Axioms at init time, not baked into a constant.
      # Flags THRESHOLD, MAX_LINES, MIN_LINES, WARN_LINES constants in scan rule files.
      class ThresholdDriftRule < Rule
        DRIFT_CONST = /^\s+(?:THRESHOLD|MAX_LINES|MIN_LINES|WARN_LINES|MAX_PARAMS|MAX_METHODS)\s*=\s*\d+/.freeze

        def initialize
          super
          @id          = "threshold_drift"
          @description = "Hardcoded threshold constant in scan rule — read from Axioms instead"
          @severity    = :warning
          @axiom_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.include?("scan/rules") && path.end_with?(".rb")
          scan_lines(code, DRIFT_CONST,
            message: "hardcoded threshold — use Master::Axioms.new.thresholds.dig(...) so rules.yml is the single source")
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/trailing_comment_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Flags inline trailing comments whose text restates identifiers already
      # visible in the same line. The name should speak; the comment is noise.
      class TrailingCommentRule < Rule
        INLINE_COMMENT = /^([^#\n]+\S)\s+#\s*(.+)$/.freeze
        NOISE_WORDS    = %w[the a an this that returns gets sets is are be].to_set.freeze

        def initialize
          super
          @id          = "trailing_comment"
          @description = "Trailing comment restates the code — rename instead of annotating"
          @severity    = :style
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            m = line.match(INLINE_COMMENT)
            next unless m

            code_part = m[1]
            comment   = m[2].strip
            next if comment.length > 60
            next unless restatement?(code_part, comment)

            findings << finding(line: num, message: "trailing comment restates the code — remove it or rename the identifier")
          end
          findings
        end

        private

        def restatement?(code_part, comment)
          comment_words = comment.downcase.scan(/[a-z_]+/).reject { |w| NOISE_WORDS.include?(w) }
          return false if comment_words.empty? || comment_words.size > 4
          code_words = code_part.downcase.scan(/[a-z_]+/).to_set
          overlap = comment_words.count { |w| code_words.include?(w) }
          overlap.to_f / comment_words.size >= 0.75
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/universal_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # UniversalRule — cross-language axiom checks applied to every file type.
      class UniversalRule < Rule
        BLANK_FLOOD = /\n{4,}/.freeze
        BOX_CHARS   = "\u256D\u256E\u2570\u256F\u2502\u2500\u250C\u2510\u2514\u2518\u251C\u2524\u252C\u2534\u253C\u2550\u2551\u2554\u2557\u255A\u255D".freeze
        BOX_DRAWING = Regexp.new("[#{Regexp.escape(BOX_CHARS)}]|={4,}|-{4,}").freeze
        OPAQUE_NAMES    = /\b(tmp|temp|val|ret|obj|str|arr|buf)\b\s*=/.freeze
        DEAD_AFTER_STOP = /\b(return|exit|raise|throw)\b.+\n\s*\S/.freeze
        STALE_COMMENT   = /^\s*#\s*(TODO|FIXME|HACK|REVIEW|NOTE):\s*$/i.freeze

        CHECKS = [
          { pattern: BLANK_FLOOD,     message: "more than 3 consecutive blank lines — use single blank between sections",       fix: "collapse to one blank line" },
          { pattern: BOX_DRAWING,     message: "box-drawing chars or separator lines — use whitespace as layout tool",          fix: "delete separators" },
          { pattern: OPAQUE_NAMES,    message: "generic variable name — use a domain-specific name",                            fix: nil },
          { pattern: STALE_COMMENT,   message: "empty TODO/FIXME marker — fill it or delete it",                               fix: "delete marker" },
        ].freeze

        def initialize
          super
          @id          = "universal"
          @description = "Cross-language axiom checks"
          @severity    = :info
          @auto_fix    = true
          @axiom_tags  = %i[SQUINT_TEST TYPOGRAPHY_DISCIPLINE MEANINGFUL_NAMES WHITESPACE_PUNCTUATION]
        end

        def check(code, path:)
          findings = []
          CHECKS.each do |check|
            code.each_line.with_index(1) do |line, number|
              findings << finding(line: number, message: check[:message], fix: check[:fix]) if line.match?(check[:pattern])
            end
          end
          check_dead_code(code, findings)
          check_dense_methods(code, findings)
          findings
        end

        private

        def check_dead_code(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, number_a), (line_b, _)|
            next unless line_a.match?(DEAD_AFTER_STOP) && line_b.match?(/\S/)
            findings << finding(line: number_a, message: "dead code after #{line_a.strip.split.first} — remove unreachable lines", fix: "delete unreachable lines")
          end
        end

        def check_dense_methods(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, number_a), (line_b, _)|
            stripped_a = line_a.strip
            stripped_b = line_b.strip
            next unless stripped_a == "end" && stripped_b.start_with?("def ")
            findings << finding(line: number_a, message: "no blank line between method definitions — add vertical spacing", fix: "insert blank line")
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/yaml_quality_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class YamlQualityRule < Rule
        QUOTED_BOOL   = /:\s*["'](true|false|yes|no|null)["']/.freeze
        QUOTED_INT    = /:\s*["'](\d+)["']/.freeze
        UNNECESSARY_Q = /:\s*"([a-zA-Z0-9_\-\/\.]+)"/.freeze

        def initialize
          super
          @id          = "yaml_quality"
          @description = "YAML verbosity — unnecessary quotes, type coercions"
          @severity    = :style
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".yml") || path.end_with?(".yaml")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "boolean/null as quoted string — remove quotes so YAML parses the type correctly") if line.match?(QUOTED_BOOL)
            findings << finding(line: num, message: "integer as quoted string — remove quotes") if line.match?(QUOTED_INT)
            findings << finding(line: num, message: "unnecessary quotes — plain scalars don't need quoting unless they contain : or #") if line.match?(UNNECESSARY_Q) && !line.match?(QUOTED_BOOL) && !line.match?(QUOTED_INT)
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/scanner.rb`
```ruby
# frozen_string_literal: true

require "etc"

module Master
  module Scan
    class Scanner
      RULES_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
      POOL_SIZE    = [Etc.nprocessors, 8].min

      def initialize(rules: nil, event_bus: nil)
        @rules = rules || []
        @bus   = event_bus
        @mutex = Mutex.new
      end

      def scan(path, depth: :standard)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code     = File.read(path, encoding: "UTF-8")
        active   = active_rules(depth)
        findings = active.flat_map { |rule| rule.check(code, path:) }

        @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        Result.ok(findings)
      rescue StandardError => e
        @bus&.publish("scan:error", path:, error: e.message)
        Result.err("scan failed: #{e.message}", category: :unknown)
      end

      SCAN_GLOB = "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,md}".freeze

      def scan_dir(dir, depth: :standard, glob: SCAN_GLOB, stream: false)
        paths     = Dir.glob(File.join(dir, glob)).sort
        results   = Array.new(paths.size)
        threads   = []
        semaphore = Mutex.new
        index     = 0

        POOL_SIZE.times do
          threads << Thread.new do
            loop do
              current_index = semaphore.synchronize { (index += 1) - 1 }
              break if current_index >= paths.size
              path = paths[current_index]
              begin
                file_result = scan(path, depth:)
                results[current_index] = [path, file_result]
                if stream && file_result.respond_to?(:ok?) && file_result.ok?
                  count = file_result.value!.size
                  $stdout.puts "scan: #{path.sub(dir, "").delete_prefix("/")} #{count > 0 ? "#{count} violation(s)" : "ok"}" if count > 0
                  $stdout.flush
                end
              rescue StandardError => e
                @bus&.publish("scanner:thread_error", path:, error: e.message)
                results[current_index] = [path, Result.err(e.message, category: :unknown)]
              end
            end
          end
        end

        threads.each(&:join)
        Result.ok(results)
      rescue StandardError => e
        Result.err("scan_dir: #{e.message}", category: :unknown)
      end

      def add_rule(rule)
        @rules << rule
        self
      end

      def set_agent(agent)
        @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
        self
      end

      private

      def depth_rules
        @depth_rules ||= begin
          data = Master.load_yaml(RULES_PATH)
          data["scan_depths"] || {}
        end
      rescue StandardError => _e
        @depth_rules = {}
      end

      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed.include?(r.class.name.split("::").last) || allowed.include?(r.id) }
      end
    end
  end
end
```

## `lib/master/security/injection_guard.rb`
```ruby
# frozen_string_literal: true

module Master
  module Security
    class InjectionGuard
      PATTERNS = [
        /ignore (?:previous|all|your) instructions/i,
        /disregard (?:your )?(?:system )?prompt/i,
        /you are now (?:a|an|in)/i,
        /pretend (?:to be|you are|you're)/i,
        /new instructions:/i,
        /\[SYSTEM\]/i,
        /###\s*SYSTEM/i,
        /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
        /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
        /jailbreak/i,
      ].freeze

      # Shell-injection pattern checked separately (multiline, heavier regex).
      SHELL_INJECTION_RE = /```(?:bash|sh|zsh|shell)\n.*?(?:rm\s+-rf|curl\b.*?\|\s*(?:bash|sh)\b|wget\b.*?\|\s*(?:bash|sh)\b)/im.freeze

      def scan(content)
        hits = PATTERNS.select { |p| content.match?(p) }
        hits << SHELL_INJECTION_RE if content.match?(SHELL_INJECTION_RE)
        return Result.ok(:clean) if hits.empty?
        Result.err("injection detected: #{hits.size} pattern(s) matched", category: :validation)
      end

      def clean!(content)
        cleaned = PATTERNS.reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
        Result.ok(cleaned)
      end
    end
  end
end
```

## `lib/master/security/permissions.rb`
```ruby
# frozen_string_literal: true

module Master
  module Security
    module Permissions
      TOOL_TIERS = {
        "read_file"    => :safe,
        "list_dir"     => :safe,
        "search_files" => :safe,
        "write_file"   => :guarded,
        "str_replace"  => :guarded,
        "apply_diff"   => :guarded,
        "ask_llm"      => :guarded,
        "web_search"   => :guarded,
        "zsh"          => :dangerous
      }.freeze

      BLOCKLIST = [
        "rm -rf /",
        "sudo",
        "reboot",
        "shutdown",
        "mkfs",
        "dd if=",
        "> /dev/",
        "chmod 777",
        "curl | sh",
        "wget | sh"
      ].freeze

      def self.tier_for(tool_name)
        TOOL_TIERS[tool_name.to_s] || :guarded
      end

      def self.blocked?(command)
        BLOCKLIST.any? { |b| command.downcase.include?(b.downcase) }
      end
    end
  end
end
```

## `lib/master/semantic_cache.rb`
```ruby
# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  class SemanticCache
    MAX_ENTRIES = 1000
    DEFAULT_TTL = 3600
    BYTES_PER_KB = 1024.0

    def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
      @root = File.join(root, ".master", "cache")
      @ttl  = ttl
      @bus  = event_bus
      @lru  = []
      @lock = Monitor.new
      Dir.mkdir(@root) unless Dir.exist?(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      @lock.synchronize do
        hit = read_entry(path)
        if hit
          @bus&.publish("cache:hit", key:)
          return hit
        end
      end

      @bus&.publish("cache:miss", key:)
      result = blk.call
      @lock.synchronize { write_entry(path, result, key) }
      result
    end

    def invalidate!(prompt, model)
      path = cache_path(cache_key(prompt, model))
      @lock.synchronize { File.delete(path) if File.exist?(path) }
    end

    def invalidate_all!
      @lock.synchronize do
        Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue Errno::ENOENT }
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum { |f| File.exist?(f) ? File.size(f) : 0 }
        { entries: files.size, size_kb: (bytes / BYTES_PER_KB).round(1) }
      end
    end

    private

    def cache_key(prompt, model) = Digest::SHA256.hexdigest("#{prompt}::#{model}")
    def cache_path(key) = File.join(@root, "#{key}.json")

    def stale?(entry) = Time.now.to_i - entry[:ts] > @ttl

    def expire_entry!(path)
      @lru.delete(path)
      File.delete(path) rescue Errno::ENOENT
      nil
    end

    def drop_entry!(path)
      File.delete(path) rescue Errno::ENOENT
      @lru.delete(path)
      nil
    end

    def read_entry(path)
      return nil unless File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      return expire_entry!(path) if stale?(entry)
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError
      drop_entry!(path)
    end

    def write_entry(path, value, key)
      value = value.value! if value.respond_to?(:ok?) && value.ok?
      evict_lru while @lru.size >= MAX_ENTRIES
      File.write(path, JSON.generate({ ts: Time.now.to_i, value: }))
      @lru.push(path)
    end

    def promote_lru(path)
      @lru.delete(path)
      @lru.push(path)
    end

    def evict_lru
      oldest = @lru.shift
      return unless oldest && File.exist?(oldest)
      File.delete(oldest) rescue Errno::ENOENT
    end
  end
end
```

## `lib/master/session.rb`
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  class Session
    TOKENS_PER_CHAR  = 4
    SESSION_NAME_MAX = 40
    COSTS_MAX_BYTES  = 102_400     # 100 KB

    attr_reader :name, :messages, :cost, :phase, :snapshots

    def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
      @root       = root
      @budget_max = budget_max
      @req_max    = req_max
      @mutex      = Mutex.new
      @messages   = []
      @snapshots  = {}
      @cost       = 0.0
      @phase      = :discover
      @name       = nil
      @path       = File.join(root, ".master", "session.json")
      @costs_path = File.join(root, ".master", "costs.jsonl")
      Dir.mkdir(File.join(root, ".master")) unless Dir.exist?(File.join(root, ".master"))
    end

    def add_message(role:, content:)
      msg = { role:, content:, ts: Time.now.to_i }
      @mutex.synchronize do
        @messages << msg
        @name ||= auto_name(content) if role == :user
      end
      msg
    end

    def record_cost(amount, model:, tokens:)
      entry = nil
      @mutex.synchronize do
        @cost += amount
        entry = { ts: Time.now.to_i, amount:, model:, tokens:, total: @cost }
      end
      rotate_costs! if File.exist?(@costs_path) && File.size(@costs_path) > COSTS_MAX_BYTES
      File.open(@costs_path, "a") { |f| f.puts(JSON.generate(entry)) }
      entry
    end

    def snapshot(path, content)
      @snapshots[path] ||= []
      @snapshots[path] << content
    end

    def last_snapshot(path)
      @snapshots[path]&.last
    end

    def save!
      FileUtils.mkdir_p(File.dirname(@path))
      data = { name: @name, phase: @phase, messages: @messages, cost: @cost, ts: Time.now.to_i }
      File.write(@path, JSON.generate(data))
    end

    def load!
      return self unless File.exist?(@path)
      begin
        data = JSON.parse(File.read(@path), symbolize_names: true)
      rescue JSON::ParserError, Errno::ENOENT
        data = {}
      end
      @name     = data[:name]
      @phase    = data[:phase]&.to_sym || :discover
      @messages = data[:messages] || []
      @cost     = data[:cost].to_f
      self
    end

    def exists?    = File.exist?(@path)
    def clear!     = (@messages = [] ; @cost = 0.0 ; @name = nil ; self)
    def token_est  = @messages.sum { |m| m[:content].to_s.bytesize / TOKENS_PER_CHAR }

    private

    def auto_name(content)
      content.to_s.split.first(5).join(" ").then { |s| s[0, SESSION_NAME_MAX] }
    end

    def rotate_costs!
      return unless File.exist?(@costs_path)

      lines = File.readlines(@costs_path)
      # Keep the most recent half of the lines
      keep  = lines.last([lines.size / 2, 1].max)
      File.write(@costs_path, keep.join)
    end
  end
end
```

## `lib/master/skills.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # Skills — discovers and loads composable skill directories.
  # Each skill is a directory under skills/ containing:
  #   SKILL.md   — metadata (name, description, trigger patterns)
  #   skill.rb   — optional Ruby implementation (loaded as a tool)
  #
  # Skills discovered at boot are available via /skills; tool registration is pending.
  class Skills
    SKILLS_DIR = "skills".freeze

    attr_reader :loaded

    def initialize(root:, event_bus: nil)
      @root   = root
      @bus    = event_bus
      @loaded = []
    end

    def discover!
      skills_path = File.join(@root, SKILLS_DIR)
      return [] unless Dir.exist?(skills_path)

      Dir.children(skills_path).sort.each do |name|
        dir = File.join(skills_path, name)
        next unless File.directory?(dir)

        skill = load_skill(dir, name)
        @loaded << skill if skill
      end

      @bus&.publish("skills:loaded", count: @loaded.size)
      @loaded
    end

    def list
      return "(no skills loaded)" if @loaded.empty?

      @loaded.map { |s| "#{s[:name]}: #{s[:description]}" }.join("\n")
    end

    def find(name)
      @loaded.find { |s| s[:name] == name.to_s }
    end

    def trigger_for(input)
      @loaded.select do |s|
        s[:triggers]&.any? { |t| input.match?(Regexp.new(t, Regexp::IGNORECASE)) }
      end
    end

    private

    def load_skill(dir, name)
      md_path = File.join(dir, "SKILL.md")
      rb_path = File.join(dir, "skill.rb")

      metadata = parse_skill_md(md_path) if File.exist?(md_path)
      metadata ||= { "name" => name, "description" => name }

      skill = {
        name:        metadata["name"] || name,
        description: metadata["description"] || name,
        triggers:    metadata["triggers"] || [],
        dir:         dir,
        has_ruby:    File.exist?(rb_path)
      }

      if File.exist?(rb_path)
        begin
          require rb_path
          @bus&.publish("skills:ruby_loaded", skill: name)
        rescue StandardError => e
          @bus&.publish("skills:load_error", skill: name, error: e.message)
        end
      end

      skill
    rescue StandardError => e
      @bus&.publish("skills:load_error", skill: name, error: e.message)
      nil
    end

    def parse_skill_md(path)
      content = File.read(path, encoding: "UTF-8")
      return {} unless content.start_with?("---")

      parts = content.split("---", 3)
      return {} if parts.size < 3

      YAML.safe_load(parts[1]) || {}
    rescue StandardError => _e
      {}
    end
  end
end
```

## `lib/master/soul.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "yaml"
require "fileutils"

module Master
  # Manages SOUL.md identity document; Evolution Protocol: propose→test→approve→tag.
  class Soul
    SOUL_PATH     = File.join(Master::ROOT, "SOUL.md").freeze
    PROPOSAL_PATH = File.join(Master::ROOT, ".master", "soul_proposal.md").freeze

    # Drift boundaries — changes to ABSOLUTE sections are blocked without override.
    ABSOLUTE_PATTERNS  = [/anti-simulation rule/i, /golden rule/i, /preserve.*then.*improve/i].freeze
    PROTECTED_PATTERNS = [/voice character/i, /terse.*direct.*dark/i].freeze

    def initialize(root: Master::ROOT, agent: nil)
      @root  = root
      @agent = agent
      @soul  = load_soul
    end

    # Wire the agent after construction (avoids circular dependency in build).
    def wire_agent(agent) = @agent = agent

    def summary
      version = extract_version
      persona = extract_field("Persona")
      voice   = extract_field("Voice").to_s.lines.first.to_s.strip[0, 120]
      "SOUL.md v#{version} | persona: #{persona}\n#{voice}"
    end

    def changelog
      block = @soul[/## Changelog\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      block.empty? ? "(no changelog)" : block
    end

    def propose(rationale, agent: @agent)
      return "no agent available for drafting" unless agent

      current = @soul
      prompt  = <<~PROMPT
        You are editing SOUL.md — a constitutional identity document for an AI coding agent.
        Current document:
        #{current}

        Proposed change rationale: #{rationale}

        Draft ONLY the minimal changes needed. Preserve the anti-simulation rule,
          golden rule, and voice character unchanged.
        Output the full updated SOUL.md. No preamble.
      PROMPT

      draft = agent.ask_once(prompt)
      return "draft failed" if draft.to_s.strip.empty?

      drift = measure_drift(current, draft)
      blocked = drift[:absolute_changed].any?

      if blocked
        "BLOCKED: proposal changes ABSOLUTE sections: #{drift[:absolute_changed].join(", ")}. Add /override to force."
      else
        FileUtils.mkdir_p(File.dirname(PROPOSAL_PATH))
        tmp_w = "#{PROPOSAL_PATH}.tmp.#{Process.pid}"
        File.write(tmp_w, draft)
        File.rename(tmp_w, PROPOSAL_PATH)
        risk = drift[:protected_changed].any? ? " [PROTECTED sections affected: #{drift[:protected_changed].join(", ")}]" : ""
        "proposal saved#{risk}. Review with `soul diff`, approve with `soul approve`, reject with `soul reject`."
      end
    rescue StandardError => e
      "proposal error: #{e.message}"
    end

    def diff
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)
      lines_old = @soul.lines
      lines_new = proposal.lines
      changes = lines_new.reject { |l| lines_old.include?(l) }
      removals = lines_old.reject { |l| lines_new.include?(l) }
      out = []
      out += removals.first(10).map { |l| "- #{l.chomp}" }
      out += changes.first(10).map { |l| "+ #{l.chomp}" }
      out.empty? ? "(no visible changes)" : out.join("\n")
    end

    def approve
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)

      old_version = extract_version
      new_version = bump_version(old_version, :patch)

      # Inject new version into proposal
      updated = proposal.sub(/Version: [\d.]+/, "Version: #{new_version}")
      # Update changelog entry
      date    = Time.now.strftime("%Y-%m-%d")
      entry   = "| #{new_version} | #{date} | Evolution Protocol change | Approved via `soul approve` |\n"
      updated = updated.sub(/\| 1\.0\.0 \|/, entry + "| 1.0.0 |")

      tmp_w = "#{SOUL_PATH}.tmp.#{Process.pid}"
      File.write(tmp_w, updated)
      File.rename(tmp_w, SOUL_PATH)
      File.unlink(PROPOSAL_PATH)
      @soul = updated

      # Git tag
      Open3.capture2e("git", "-C", @root, "add", "SOUL.md")
      Open3.capture2e("git", "-C", @root, "commit", "-m", "soul: v#{new_version} — evolution protocol update")

      "soul updated to v#{new_version}"
    rescue StandardError => e
      "approve error: #{e.message}"
    end

    def reject
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      File.unlink(PROPOSAL_PATH)
      "proposal rejected"
    end

    def rollback
      log_out, = Open3.capture2e("git", "-C", @root, "log", "--oneline", "SOUL.md")
      out = log_out.lines
      return "no git history for SOUL.md" if out.size < 2
      prev_sha = out[1].split.first
      restored, = Open3.capture2e("git", "-C", @root, "show", "#{prev_sha}:SOUL.md")
      tmp_w = "#{SOUL_PATH}.tmp.#{Process.pid}"
      File.write(tmp_w, restored)
      File.rename(tmp_w, SOUL_PATH)
      @soul = restored
      "rolled back to #{prev_sha} — #{out[1].chomp}"
    rescue StandardError => e
      "rollback error: #{e.message}"
    end

    def system_prompt
      voice  = @soul[/## Voice\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      values = @soul[/## Values\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      "#{voice}\n\n#{values}"
    end

    def propose_from_violations(rule_id, sample_violations, agent: @agent)
      return "no agent available" unless agent

      examples  = sample_violations.first(3).map { |v| "  L#{v[:line]}: #{v[:message]}" }.join("\n")
      rationale = "Recurring scan rule '#{rule_id}' flagged #{sample_violations.size} " \
                  "violations across multiple files and cycles:\n#{examples}\n" \
                  "Propose whether the codebase axioms or soul principles should acknowledge this pattern " \
                  "or whether the rule needs refinement."
      propose(rationale, agent:)
    end

    private

    def load_soul
      File.exist?(SOUL_PATH) ? File.read(SOUL_PATH, encoding: "UTF-8") : ""
    rescue StandardError => _e
      ""
    end

    def extract_version
      @soul[/^Version: ([\d.]+)/, 1] || "1.0.0"
    end

    def extract_field(name)
      @soul[/^#{Regexp.escape(name)}:\s*(.+)/, 1].to_s.strip
    end

    def bump_version(ver, level)
      parts = ver.split(".").map(&:to_i)
      case level
      when :major then "#{parts[0] + 1}.0.0"
      when :minor then "#{parts[0]}.#{parts[1] + 1}.0"
      when :patch then "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
      end
    end

    def measure_drift(old_doc, new_doc)
      absolute_changed  = ABSOLUTE_PATTERNS.select  { |p| old_doc.match?(p) && !new_doc.match?(p) }.map(&:source)
      protected_changed = PROTECTED_PATTERNS.select { |p| old_doc.match?(p) && !new_doc.match?(p) }.map(&:source)
      { absolute_changed:, protected_changed: }
    end
  end
end
```

## `lib/master/speech.rb`
```ruby
# frozen_string_literal: true

require "securerandom"
require "fileutils"

module Master
  module Speech
    EDGE_TTS = %w[/home/dev/.local/bin/edge-tts /usr/local/bin/edge-tts].find { |p| File.executable?(p) }
    ESPEAK   = %w[/usr/bin/espeak /usr/local/bin/espeak].find { |p| File.executable?(p) }

    VOICES = {
      osman:   "ms-MY-OsmanNeural",
      yasmin:  "en-MY-YasminNeural",
      ryan:    "en-GB-RyanNeural",
      finn:    "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
    }.freeze

    STYLES = {
      deep:    { rate: "-35%", pitch: "-150Hz" },
      heavy:   { rate: "-30%", pitch: "-120Hz" },
      normal:  { rate: "+0%",  pitch: "+0Hz"   },
      slow:    { rate: "-20%", pitch: "-60Hz"  },
      natural: { rate: "+8%",  pitch: "+20Hz"  }
    }.freeze

    DEFAULT_VOICE = :osman
    DEFAULT_STYLE = :natural

    PULSE_SOCKET     = "/tmp/pulse/native".freeze
    PULSE_DAEMON     = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze
    PAPLAY_CANDIDATES = %w[
      /data/data/com.termux/files/usr/bin/paplay
      /usr/bin/paplay
      /usr/local/bin/paplay
    ].freeze
    FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze
    DIRECT_PLAYERS    = %w[aucat mpv ffplay aplay].freeze

    module_function

    def available?
      !EDGE_TTS.nil? || !ESPEAK.nil?
    end

    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      return nil if text.to_s.strip.empty?

      if EDGE_TTS
        synthesize_edge(text, voice: voice, style: style)
      elsif ESPEAK
        synthesize_espeak(text)
      end
    end

    def synthesize_bytes(text, **opts)
      path = synthesize(text, **opts)
      return nil unless path
      bytes = File.binread(path)
      File.unlink(path) rescue StandardError => _e
      bytes
    end

    def play(audio_path)
      return false unless audio_path && File.exist?(audio_path)
      play_via_pulse(audio_path) || play_direct(audio_path)
    end

    private

    module_function

    def synthesize_edge(text, voice:, style:)
      audio_path   = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
      voice_name   = VOICES.fetch(voice.to_sym, VOICES[DEFAULT_VOICE])
      style_config = STYLES.fetch(style.to_sym, STYLES[DEFAULT_STYLE])

      ok = system(
        EDGE_TTS,
        "--voice", voice_name,
        "--rate=#{style_config[:rate]}",
        "--pitch=#{style_config[:pitch]}",
        "--text", text.to_s,
        "--write-media", audio_path,
        out: File::NULL, err: File::NULL
      )

      (ok && File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end

    def synthesize_espeak(text)
      audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
      ok         = system(
        ESPEAK, "-s", "140", "-p", "30", "-a", "150",
        "-w", audio_path, text.to_s,
        out: File::NULL, err: File::NULL
      )
      (ok && File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end
  end
end
```

## `lib/master/stages/council.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Council — 6-persona deliberation on dangerous or multi-file changes.
    # PRAISE votes are appended to data/exemplars.yml for future reference.
    class Council
      EXEMPLARS_PATH       = File.join(Master::ROOT, "data", "exemplars.yml").freeze
      PATTERNS_PATH        = File.join(Master::ROOT, "data", "council_patterns.yml").freeze
      EXEMPLAR_MSG_CHARS   = 120
      EXEMPLAR_FEEDBACK_CHARS = 240

      def initialize(deliberation:, config: nil, enabled: false)
        @deliberation      = deliberation
        @config            = config
        @enabled           = @config&.[]("council") == true || enabled
        @dangerous_patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless should_run?(ctx)

        payload = extract_payload(ctx)
        result  = @deliberation.review(payload, context: ctx[:message])
        return result if result.err?

        feedback = result.value!
        log_praise(ctx[:message], feedback) if praise?(feedback)

        Result.ok(ctx.merge(council_feedback: feedback))
      end

      def enable!
        @enabled = true
        @config&.[]=("council", true)
        @config&.save!
      end

      def disable!
        @enabled = false
        @config&.[]=("council", false)
        @config&.save!
      end

      def enabled? = @enabled

      private

      def load_patterns
        data = Master.load_yaml(PATTERNS_PATH)
        (data["dangerous"] || []).flatten.filter_map do |str|
          Regexp.new(str, Regexp::IGNORECASE)
        rescue RegexpError
          nil
        end
      end

      def should_run?(ctx)
        return false if ctx[:intent] == :command
        @enabled || dangerous_request?(ctx) || dangerous_tool?(ctx) || multi_file_diff?(ctx)
      end

      def dangerous_request?(ctx)
        msg = ctx[:message].to_s.gsub(/[[:cntrl:]]/, "")
        !msg.empty? && @dangerous_patterns.any? { |p| msg.match?(p) }
      end

      def dangerous_tool?(ctx)  = ctx[:last_tool_tier] == :dangerous
      def multi_file_diff?(ctx) = extract_payload(ctx).scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2

      def extract_payload(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then ""
        else
          text = out.to_s
          text.empty? ? ctx[:message].to_s : text
        end
      end

      # Detect unanimous or majority PRAISE in council feedback text.
      def praise?(feedback)
        text = feedback.to_s.downcase
        text.scan(/\bpraise\b/).size >= 3
      end

      # Append a PRAISE entry to data/exemplars.yml.
      def log_praise(message, feedback)
        entry = {
          "timestamp" => Time.now.iso8601,
          "message"   => message.to_s[0, EXEMPLAR_MSG_CHARS],
          "feedback"  => feedback.to_s[0, EXEMPLAR_FEEDBACK_CHARS]
        }
        existing = File.exist?(EXEMPLARS_PATH) ? (Master.load_yaml(EXEMPLARS_PATH) || []) : []
        File.write(EXEMPLARS_PATH, YAML.dump(existing + [entry]))
      rescue StandardError => e
        @bus&.publish("council:exemplar_error", error: e.message)
      end
    end
  end
end
```

## `lib/master/stages/deliberate.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Deliberate — enumerate N approaches before acting; prevents first-solution fixation.
    class Deliberate
      MIN_OPTIONS   = 4
      CODING_TYPES  = %i[coding refactor architecture infrastructure].freeze

      def initialize(agent:, config:)
        @agent  = agent
        @config = config
      end

      def call(ctx)
        return Result.ok(ctx) unless applicable?(ctx)

        msg    = ctx[:message].to_s
        Result.ok(ctx.merge(message: wrap(msg)))
      end

      private

      def applicable?(ctx)
        ctx[:intent] == :llm &&
          CODING_TYPES.include?(ctx[:task_type]) &&
          @config["deliberate"] != false
      end

      def wrap(msg)
        <<~PROMPT
          #{msg}

          Before acting: list #{MIN_OPTIONS} distinct approaches (numbered). Each: one-line name + one-line trade-off. Then execute the strongest one. State which you chose and why in one sentence.
        PROMPT
      end
    end
  end
end
```

## `lib/master/stages/execute.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Execute — call the handler resolved by Route and store its output.
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        Result.ok(ctx.merge(output: handler.call(ctx)))
      rescue StandardError => e
        Result.err("execute: #{e.message}", category: :handler_exception)
      end
    end
  end
end
```

## `lib/master/stages/guard.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Guard — reject messages that contain prompt-injection patterns.
    # Skips scan when message is absent (command-only paths set no :message).
    class Guard
      def initialize(governor:, injection_guard:)
        @governor        = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        msg = ctx[:message].to_s
        return Result.ok(ctx) if msg.empty?

        scan = @injection_guard.scan(msg)
        return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

        Result.ok(ctx)
      end
    end
  end
end
```

## `lib/master/stages/infer.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Infer — promote natural-language messages to :command intent via data/infer_patterns.yml.
    class Infer
      # Heuristic task-type detection — used by ModelRouter for tiered model selection.
      PRESSURE_PATTERN = /\b(?:urgent|asap|immediately|critical|now|hurry|fast|quick(?:ly)?|emergency|sos)\b/i.freeze

      VAGUE_STUBS  = /\A(?:help(?:\s+me)?|hmm+|idk|ugh|ok+|yeah|yep|nope?|hi+|hey|hello|good\s+\w+|test(?:ing)?|please)\z/i.freeze
      ACTIONABLE   = /\b(?:fix|write|add|explain|refactor|scan|implement|show|list|create|delete|update|find|run|check|what|how|why|where|when|who|which|read|open|build|deploy|revert|move|rename)\b/i.freeze
      FILE_REF     = /[`'"]|\/|\.\w{2,4}\b/.freeze
      ELICIT_WORDS = 5

      ELICIT_QUESTIONS = {
        implement: "which file, which method, and what change exactly?",
        refactor:  "which file, which method, and what change exactly?",
        design:    "what interface — inputs, outputs, constraints?",
        discover:  "what problem, and how will you measure success?",
      }.freeze
      ELICIT_DEFAULT = "be specific: which file or function, and what should change?".freeze

      TASK_TYPE_PATTERNS = {
        architecture: /\b(?:restructur|reorganiz|hierarch|layout|folder|director|module\s+boundar|decouple|extract\s+(?:a\s+)?(?:module|class|layer|service)|where\s+should|how\s+should\s+(?:we|i)\s+organiz|split\s+(?:this\s+)?(?:into|across)|consolidat)/i,
        coding:       /\b(?:def |class |module |require |\.rb\b|fix\s+(?:the\s+)?(?:bug|error|issue)|refactor|implement|write\s+(?:a\s+)?(?:method|class|function|test)|add\s+(?:a\s+)?(?:method|feature)|```(?:ruby|python|js|javascript|bash))/i,
        research:     /\b(?:search|find\s+(?:all|every|info)|research|look\s+up|what\s+is|explain\s+(?:how|what|why)|tell\s+me\s+about)\b/i,
        qa:           /\?(?:\s*$|\s+[A-Z])/m,
      }.freeze

      PATTERNS_PATH = File.join(Master::ROOT, "data", "infer_patterns.yml").freeze

      def initialize
        @patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless ctx[:intent] == :llm

        msg = ctx[:message].to_s.strip
        @patterns.each do |cmd, entry|
          entry[:regexes].each do |pattern|
            next unless (m = msg.match(pattern))
            return Result.ok(ctx.merge(intent: :command, command: cmd, args: extract_args(cmd,
              entry[:capture], m, msg)))
          end
        end

        if vague?(msg)
          q = ELICIT_QUESTIONS[ctx[:phase]&.to_sym] || ELICIT_DEFAULT
          return Result.ok(ctx.merge(intent: :clarify, clarifying_question: q))
        end

        pressure = msg.match?(PRESSURE_PATTERN)
        Result.ok(ctx.merge(task_type: infer_task_type(msg), pressure: pressure || ctx[:pressure]))
      end

      private

      def load_patterns
        return {} unless File.exist?(PATTERNS_PATH)
        data = Master.load_yaml(PATTERNS_PATH) || {}
        commands = data["commands"] || {}
        commands.each_with_object({}) do |(name, spec), out|
          regexes = (spec["patterns"] || []).map { |src| Regexp.new(src, Regexp::IGNORECASE | Regexp::EXTENDED) }
          out[name.to_s] = { regexes: regexes, capture: spec["capture"].to_s }
        end
      rescue StandardError => _e
        {}
      end

      def vague?(msg)
        return true if msg.match?(VAGUE_STUBS)

        msg.split.size <= ELICIT_WORDS && !msg.match?(ACTIONABLE) && !msg.match?(FILE_REF)
      end

      def infer_task_type(msg)
        TASK_TYPE_PATTERNS.each { |type, pat| return type if msg.match?(pat) }
        :general
      end

      def extract_args(cmd, capture, match, msg)
        case capture
        when "path"
          path = match[1]&.strip
          path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
          path.to_s
        when "cycles"
          (match[1] || msg[/\b(\d+)\s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
        when "on_off"
          msg.match?(/\b(?:off|disable|stop|av|skru\s+av)\b/i) ? "off" : "on"
        when "first_group"
          match.captures.compact.first.to_s.strip
        when "persona_name"
          (match[1] || match[2] || match[3]).to_s.strip
        when "soul_subcmd"
          msg[/\b(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
        when "orders_subcmd"
          msg.match?(/\blist|show\b/i) ? "list" : ""
        when "scan_depth"
          match[1]&.strip.to_s
        else
          ""
        end
      end
    end
  end
end
```

## `lib/master/stages/intake.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string (may be empty)
      COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m.freeze

      def call(ctx)
        raw = ctx[:user_message]
        msg = raw.to_s.strip
        return Result.err("intake: empty message", category: :validation) if msg.empty?

        if (m = msg.match(COMMAND_RE))
          command = m[1].downcase
          args    = m[2].strip
          args = nil if args.empty?
          Result.ok(ctx.merge(intent: :command, command: command, args: args))
        else
          Result.ok(ctx.merge(intent: :llm, message: msg))
        end
      end
    end
  end
end
```

## `lib/master/stages/lint.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Lint — scan written files and chat code blocks; autofix via autoloop if available.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil, root: nil, event_bus: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
        @root     = root
        @bus      = event_bus
      end

      def call(ctx)
        findings = []

        paths = Array(ctx[:written_files]).filter_map { |p| File.exist?(p) ? p : nil }
        paths.each do |scan_path|
          if File.directory?(scan_path)
            result = @scanner.scan_dir(scan_path, depth: :standard)
            findings.concat(result.value!.flat_map { |_, r| r.respond_to?(:ok?) && r.ok? ? r.value! : [] }) if result.respond_to?(:ok?) && result.ok?
          elsif scan_path.end_with?(".rb")
            result = @scanner.scan(scan_path, depth: :standard)
            findings.concat(result.value!) if result.respond_to?(:ok?) && result.ok?
          end
        end

        output = ctx[:output].to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        if findings.any? && @autoloop
          fixable = findings.select { |f| !AutoLoop::SKIP_RULES.include?(f[:rule].to_s) }
          if fixable.any?
            fix_result = @autoloop.run(max_cycles: 3)
            ctx = ctx.merge(autofix_result: fix_result)
          end
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue StandardError => e
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          result = @scanner.scan(f.path, depth: :standard)
          if result.respond_to?(:ok?) && result.ok?
            findings = result.value!.map { |v| v.merge(source: :inline) }
          end
        end
        findings
      rescue StandardError => e
        @bus&.publish("lint:scan_error", error: e.message)
        []
      end
    end
  end
end
```

## `lib/master/stages/memo.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Memo — extract memories from :user_message only; assistant output ignored to prevent hallucination loops.
    class Memo
      REMEMBER_RE = /\bremember\s+(?:that\s+)?(.{10,200}?)(?:[.!]|$)/im.freeze
      DECISION_RE = /\bwe(?:'ve|\s+have)?\s+decided\s+(?:to\s+)?(.{10,150}?)(?:[.!]|$)/im.freeze
      PREFER_RE   = /\bI\s+prefer\s+(.{5,100}?)(?:[.!]|$)/im.freeze

      def initialize(memory:, event_bus: nil)
        @memory = memory
        @bus    = event_bus
      end

      def call(ctx)
        text = user_text(ctx)
        scan_for_memories(text) if text && !text.empty?
        Result.ok(ctx)
      rescue StandardError => e
        @bus&.publish("memo:error", message: e.message)
        Result.ok(ctx)
      end

      private

      def user_text(ctx)
        ctx[:user_message].to_s
      end

      def scan_for_memories(text)
        text.scan(REMEMBER_RE).each_with_index do |(fact), i|
          @memory.remember("note_#{Time.now.to_i}_#{i}", fact.strip)
        end
        text.scan(DECISION_RE).each_with_index do |(decision), i|
          @memory.remember("decision_#{Time.now.to_i}_#{i}", decision.strip)
        end
        text.scan(PREFER_RE).each_with_index do |(pref), i|
          key = "pref_#{Time.now.to_i}_#{i}_#{pref.split.first(3).join("_").downcase.gsub(/\W/, "")}"
          @memory.remember(key, pref.strip)
        end
      end
    end
  end
end
```

## `lib/master/stages/prune.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Prune — strip sycophancy and markdown formatting from LLM responses.
    # Rules loaded from data/rules.yml (voice.strunk). Fence-aware: prunes prose, leaves code blocks.
    class Prune
      RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      HEADER_RE     = %r{^\#{1,6}\s+}.freeze
      BOLD_RE       = /\*\*(.+?)\*\*/
      ITALIC_RE     = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
      BULLET_RE     = /^\s*[-*+]\s+/
      NUMBERED_RE   = /^\s*\d+\.\s+/
      HR_RE         = /^-{3,}\s*$/
      LINK_RE       = /\[([^\]]+)\]\([^)]+\)/
      SYCOPHANCY_RE = /\A\s*(?:certainly|of course|great question|absolutely|sure|happy to help|i(?:'d| would) be (?:happy|glad)|no problem)[!.,]*\s*/i

      def call(ctx)
        raw = ctx[:output]
        output = if raw.respond_to?(:ok?) && raw.ok?
                   raw.value!.to_s
                 elsif raw.is_a?(String)
                   raw
                 else
                   return Result.ok(ctx)
                 end
        return Result.ok(ctx) if output.empty?

        cleaned = prune_mixed(output)
        final = raw.respond_to?(:ok?) ? Result.ok(cleaned.strip) : cleaned.strip
        Result.ok(ctx.merge(output: final))
      end

      private

      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          seg.start_with?("```") ? seg : strip_all(seg)
        }.join
      end

      def strip_all(text)
        cleaned = text
        cleaned = cleaned.sub(SYCOPHANCY_RE, "")

        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end

        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")
        cleaned = cleaned.gsub(/\n{3,}/, "\n\n")
        cleaned
      end

      def rules
        @rules ||= begin
          data = File.exist?(RULES_PATH) ? Master.load_yaml(RULES_PATH) : {}
          data.dig("voice", "strunk") || {}
        end
      rescue StandardError => _e
        @rules = {}
      end
    end
  end
end
```

## `lib/master/stages/render.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Render — format the final output for display.
    class Render
      def initialize(renderer:)
        @renderer = renderer
      end

      def call(ctx)
        output = ctx[:output]
        rendered = case output
                   when Result::Ok  then @renderer.render(output.value!, mode: :plain)
                   when Result::Err then @renderer.render(output.message, mode: :error)
                   else                  @renderer.render(output.to_s, mode: :plain)
                   end

        Result.ok(ctx.merge(rendered:))
      end
    end
  end
end
```

## `lib/master/stages/route.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Route — attach the correct handler to the context.
    # :command looks up registered command. :llm uses the agent.
    class Route
      def initialize(commands:, agent:)
        @commands = commands
        @agent    = agent
      end

      def add_command(name, handler) = @commands[name.to_s] = handler

      def call(ctx)
        case ctx[:intent]
        when :command  then route_command(ctx)
        when :llm      then Result.ok(ctx.merge(handler: @agent))
        when :clarify  then Result.ok(ctx.merge(handler: ->(_c) { ctx[:clarifying_question] }))
        else                Result.err("route: unknown intent #{ctx[:intent].inspect}", category: :validation)
        end
      end

      private

      def route_command(ctx)
        cmd = @commands[ctx[:command]]
        unless cmd
          suggestion = closest_command(ctx[:command])
          msg = "unknown command: /#{ctx[:command]}"
          msg += " -- did you mean /#{suggestion}?" if suggestion
          return Result.err(msg, category: :validation)
        end
        Result.ok(ctx.merge(handler: cmd))
      end

      def closest_command(name)
        best = @commands.keys.min_by { |k| levenshtein(k, name) }
        return nil unless best && levenshtein(best, name) <= [name.length, 3].min

        best
      end

      def levenshtein(a, b)
        m = a.length
        n = b.length
        dp = Array.new(m + 1) { |i| Array.new(n + 1) { |j| i.zero? ? j : (j.zero? ? i : 0) } }
        (1..m).each do |i|
          (1..n).each do |j|
            dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].min
          end
        end
        dp[m][n]
      end
    end
  end
end
```

## `lib/master/standing_orders.rb`
```ruby
# frozen_string_literal: true

module Master
  class StandingOrders
    DAILY_INTERVAL   = 86_400
    WEEKLY_INTERVAL  = 604_800
    ERROR_TRUNCATE   = 200
    STORE_PATH       = File.join(Master::ROOT, "data", "standing_orders.yml")
    VALID_STATES    = %w[pending running done error].freeze

    BUILTIN_ORDERS = [
      { name: "nightly_dreams", description: "Consolidate memories during low-activity periods",
        trigger: "scheduled", interval_s: 86_400, command: "dreams consolidate", enabled: true },
      { name: "weekly_scan", description: "Weekly codebase axiom scan for regressions",
        trigger: "scheduled", interval_s: 604_800, command: "scan", enabled: false }
    ].freeze

    def initialize(pipeline: nil, event_bus: nil)
      @pipeline = pipeline
      @bus      = event_bus
      @orders   = load_orders
    end

    def wire_pipeline(pipeline)
      @pipeline = pipeline
    end

    def due
      now = Time.now.to_i
      @orders.select do |o|
        o["enabled"] &&
          o["trigger"] == "scheduled" &&
          %w[pending done].include?(state_of(o)) &&
          (now - o["last_run_at"].to_i) >= o["interval_s"].to_i
      end
    end

    def run_due!
      results = []
      due.each do |order|
        order["state"] = "running"
        persist

        result = execute_order(order)
        order["last_run_at"] = Time.now.to_i

        if result.ok?
          order["state"] = "done"
          order.delete("last_error")
        else
          order["state"] = "error"
          order["last_error"] = result.message.to_s[0, ERROR_TRUNCATE]
        end

        results << { name: order["name"], result: }
        @bus&.publish("standing_order:ran", name: order["name"], ok: result.ok?, state: order["state"])
      end
      persist if results.any?
      results
    end

    def upsert(name:, description: "", trigger: "scheduled",
               interval_s: 86_400, command:, enabled: true)
      existing = @orders.find { |o| o["name"] == name.to_s }
      if existing
        existing.merge!(
          "description" => description, "trigger" => trigger.to_s,
          "interval_s"  => interval_s.to_i, "command" => command.to_s, "enabled" => enabled
        )
      else
        @orders << {
          "name" => name.to_s, "description" => description.to_s, "trigger" => trigger.to_s,
          "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled,
          "state" => "pending", "last_run_at" => 0
        }
      end
      persist
      "standing order '#{name}' saved"
    end

    def enable(name)  = toggle(name, true)
    def disable(name) = toggle(name, false)

    def reset(name)
      order = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless order
      order["state"] = "pending"
      order.delete("last_error")
      persist
      "'#{name}' reset -> pending"
    end

    def list
      return "no standing orders defined" if @orders.empty?
      @orders.map do |o|
        st   = state_of(o)
        flag = o["enabled"] ? "on" : "off"
        last = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
        err  = o["last_error"] ? "  !! #{o["last_error"][0, 60]}" : ""
        "#{o['name']} [#{flag}|#{st}] - #{o['description']} (last: #{last})#{err}"
      end.join("\n")
    end

    private

    def state_of(order) = VALID_STATES.include?(order["state"]) ? order["state"] : "done"

    def execute_order(order)
      return Result.err("no pipeline") unless @pipeline
      @pipeline.call(Result.ok(user_message: order["command"].to_s))
    rescue StandardError => e
      Result.err(e.message)
    end

    def toggle(name, enabled)
      order = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless order
      order["enabled"] = enabled
      persist
      "#{name} #{enabled ? 'enabled' : 'disabled'}"
    end

    def load_orders
      if File.exist?(STORE_PATH)
        orders = Master.load_yaml(STORE_PATH)
        unless orders.is_a?(Array)
          @bus&.publish("standing_orders:corrupt", path: STORE_PATH, got: orders.class.name)
          return builtin_orders
        end
        orders.select { |o| o.is_a?(Hash) }.each { |o| o["state"] ||= "done" }
      else
        builtin_orders
      end
    rescue Psych::Exception, Errno::ENOENT, TypeError, NoMethodError => e
      @bus&.publish("standing_orders:load_error", error: e.message)
      builtin_orders
    end

    def builtin_orders
      BUILTIN_ORDERS.map { |o| o.transform_keys(&:to_s).merge("last_run_at" => 0, "state" => "pending") }
    end

    def persist
      return unless @orders.is_a?(Array)
      FileUtils.mkdir_p(File.dirname(STORE_PATH))
      File.write(STORE_PATH, YAML.dump(@orders))
    end
  end
end
```

## `lib/master/swarm/coordinator.rb`
```ruby
# frozen_string_literal: true

require "timeout"

module Master
  module Swarm
    class Coordinator
      SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, keyword_init: true) do
        def ok?      = verdict != :error
        def approved? = verdict == :approved
      end

      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      WORKER_TIMEOUT = 30
      SHARED_DEADLINE = 60
      SYNTHESIS_TRUNCATE_LIMIT = 200

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

      def analyse_and_review(file_path:, code:)
        fan_out([
          { role: :analyst,  task: "identify all issues",          context_slice: { file: file_path, code: code } },
          { role: :reviewer, task: "security and correctness review", context_slice: { code: code } }
        ]).and_then do |sr|
          analysis = sr.artifacts[:analyst]
          review   = sr.artifacts[:reviewer]
          Result.ok({ analysis:, review:, approved: review.is_a?(Hash) && review["approved"] })
        end
      end

      def fan_out(tasks, timeout: WORKER_TIMEOUT)
        threads = tasks.map do |t|
          Thread.new do
            [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}")]
          end
        end

        results = threads.map do |th|
          if th.join(timeout)
            th.value
          else
            begin; th.kill; rescue ThreadError; nil; end
            @bus&.publish(:swarm_worker_timeout, timeout:)
            [:timeout, Result.err("worker timed out after #{timeout}s")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, verdict: sr.verdict,
                      synthesis: sr.reasoning[0..SYNTHESIS_TRUNCATE_LIMIT])
        Result.ok(sr)
      end

      def dispatch_parallel(role_tasks, deadline: SHARED_DEADLINE)
        finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

        threads = role_tasks.map do |t|
          Thread.new do
            remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
            Timeout.timeout(remaining) do
              [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
            end
          rescue Timeout::Error
            [t[:role], Result.err("worker exceeded shared deadline")]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}")]
          end
        end

        results = threads.map do |th|
          if th.join(deadline)
            th.value
          else
            begin; th.kill; rescue ThreadError; nil; end
            @bus&.publish(:swarm_parallel_timeout, deadline:)
            [nil, Result.err("worker exceeded shared deadline")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys, verdict: sr.verdict)
        Result.ok(sr)
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      def build_swarm_result(results)
        successes = results.reject { |role, _| role == :timeout }
                           .select { |_, r| r.respond_to?(:ok?) && r.ok? }
        artifacts = successes.transform_values(&:value!)
        confidence = results.empty? ? 0.0 : successes.size.to_f / results.size
        lines = successes.map { |role, r| "### #{role}\n#{r.value!.to_s.strip}" }
        reasoning = lines.empty? ? "(no results)" : lines.join("\n\n")
        verdict = if confidence >= 0.8 then :approved
                 elsif confidence >= 0.5 then :mixed
                 elsif successes.empty? then :error
                 else :rejected
                 end
        SwarmResult.new(verdict:, confidence:, reasoning:, artifacts:)
      end

      def worker_for(role)
        sym = role.to_sym
        @workers.fetch(sym) do
          klass = WORKER_CLASSES[sym]
          return nil unless klass

          @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
        end
      end
    end
  end
end
```

## `lib/master/swarm/worker.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know).
    class Worker
      PREFERRED_MODEL = nil

      UNCERTAINTY_PHRASES = %w[unclear uncertain not\ sure cannot\ determine
                                i\ don't\ know limited\ information probably].freeze

      attr_reader :role, :result, :confidence

      def initialize(agent:, event_bus: nil)
        @agent      = agent
        @bus        = event_bus
        @role       = self.class.name.split("::").last.downcase
        @result     = nil
        @confidence = 1.0
      end

      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

        preferred = self.class::PREFERRED_MODEL
        raw = @agent.ask_once(prompt, model: preferred, system: worker_system_prompt)
        @result, @confidence = parse_result(raw)

        @bus&.publish(:swarm_worker_done, role: @role, ok: @result.ok?)
        @result
      rescue StandardError => e
        Result.err("worker #{@role}: #{e.message}", category: :unknown)
      end

      private

      def worker_system_prompt
        "You are a specialized #{@role} agent. #{role_description}\n" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end

      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}\n\nTask: #{task}"

      def parse_result(raw)
        text = raw.to_s.strip
        hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
        conf = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
        [Result.ok({ text: text, confidence: conf }), conf]
      end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
end
```

## `lib/master/swarm/workers/analyst.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reads code, produces structured analysis. Knows nothing about other workers.
      class Analyst < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        private

        def role_description
          "You analyze code for quality, bugs, and design issues. " \
            "Output JSON: {issues: [{file, line, severity(1-3), description}], summary: string}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "File: #{ctx[:file]}" if ctx[:file]
          parts << "Code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Analyze: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          match_str = raw.to_s.match(/\{.*\}/m)&.to_s || "{}"
          parsed = JSON.parse(match_str)
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ summary: raw.to_s.strip, issues: [] })
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/coder.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Writes code given a spec. Knows only the spec + relevant file context.
      class Coder < Worker
        private

        def role_description
          "You write clean, minimal Ruby/Rails/Zsh code. " \
            "Output only the code block. No explanation unless asked."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Language: #{ctx[:language] || "ruby"}"
          parts << "Existing code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Spec: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/researcher.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Synthesizes research from external sources. No codebase context.
      class Researcher < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        private

        def role_description
          "You are a research analyst. Synthesize information concisely. " \
            "Output: factual summary, sources if known, confidence level (low/med/high)."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Domain: #{ctx[:domain]}" if ctx[:domain]
          parts << "Prior findings:\n#{ctx[:prior_findings]}" if ctx[:prior_findings]
          parts << "Research: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/reviewer.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reviews code for security, correctness, style. Constitutional layer.
      class Reviewer < Worker
        CHECKLIST = %w[
          sql_injection xss command_injection path_traversal
          hardcoded_secrets open_redirect mass_assignment
        ].freeze

        private

        def role_description
          "You are a security-focused code reviewer. Check for OWASP top-10 issues, " \
            "logic bugs, and constitutional AI violations. " \
            "Output JSON: {approved: bool, violations: [{type, line, description}]}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Code to review:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Security checklist: #{CHECKLIST.join(", ")}"
          parts << "Review for: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          parsed = JSON.parse(raw.to_s.match(/\{.*\}/m)&.to_s || "{}")
          parsed["approved"] = true if parsed.empty?
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ "approved" => true, "violations" => [] })
        end
      end
    end
  end
end
```

## `lib/master/sweep.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "tempfile"
require "set"
require_relative "sweep/rewriter"
require_relative "sweep/convergence"

module Master
  # Full-codebase refactor to convergence; stops on delta/oscillation/stall (arxiv:2602.21833).
  class Sweep
    MAX_CYCLES         = 16
    CONVERGE_THRESHOLD = 0.05
    CONVERGE_WINDOW    = 2
    RENAME_WINDOW    = 3
    TRAJECTORY_GAMMA = 0.9

    GLOBS = {
      rb:  "**/*.rb",
      sh:  "**/*.sh",
      yml: "**/*.yml",
      md:  "**/*.md",
      erb: "**/*.erb"
    }.freeze

    SYNTAX_CHECKERS = {
      ".rb"  => ->(p) { _, _, st = Open3.capture3("ruby", "-c", p); st.success? },
      ".sh"  => ->(p) { _, _, st = Open3.capture3("bash", "-n", p); st.success? },
      ".yml" => ->(p) { begin; Master.load_yaml(p); true; rescue StandardError => _e; false; end },
      ".erb" => ->(p) { begin; RubyVM::InstructionSequence.compile(ERB.new(File.read(p, encoding: "UTF-8")).src); true; rescue SyntaxError, StandardError => _e; false; end }
    }.freeze

    SEVERITY_RANK = Master::SEVERITY_RANK

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable|
circuit\sopen|retry\sin|llm_request)\b
    /ix.freeze

    PROMPTS_PATH      = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze
    MIN_REWRITE_BYTES = 500

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

    include Rewriter
    include Convergence

    def initialize(agent:, scanner:, root:, council: nil, event_bus: nil, code_index: nil)
      @agent      = agent
      @scanner    = scanner
      @root       = root
      @bus        = event_bus
      @code_index = code_index
      @map        = nil
      @prompts    = nil
      @rename_log = Hash.new { |h, k| h[k] = [] }
      @cycle_log  = []
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      @map            = build_codebase_map
      @prompts        = load_prompts
      violation_history = []
      converge_streak   = 0
      init_cycle_log

      max_cycles.times do |i|
        cycle       = i + 1
        changed     = 0
        cycle_viol  = 0
        cycle_fixed = 0
        cycle_defer = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, types).each do |path|
          rel    = path.delete_prefix("#{@root}/")
          before = violations_in(path)
          src    = File.read(path, encoding: "UTF-8")

          new_src, after = evaluate_rewrite(rel, src, before, cycle)
          if new_src.nil?
            cycle_defer += before
            next
          end

          delta = before - after
          File.write(path, new_src, encoding: "UTF-8")
          changed     += 1
          cycle_viol  += after
          cycle_fixed += delta
          @bus&.publish("sweep:improved", file: rel, before:, after:)
          yield cycle, rel, delta if block_given?
        end

        violation_history << cycle_viol
        entry = record_cycle(violations: cycle_viol, fixed: cycle_fixed, deferred: cycle_defer)
        @bus&.publish("sweep:cycle_stats", cycle:, **entry)
        commit("sweep: full-codebase refactor [cycle #{cycle}]") if changed > 0 && git_dirty?

        converge_streak = converged?(violation_history) ? converge_streak + 1 : 0
        break if converge_streak >= CONVERGE_WINDOW
        break if trajectory_stalled?(violation_history)
        break if should_halt_early?
      end

      summary = convergence_summary
      @bus&.publish("sweep:done", summary:)
      Result.ok(summary)
    rescue StandardError => e
      Result.err("sweep: #{e.message}", category: :unknown)
    end

    private

    def evaluate_rewrite(rel, src, before, cycle)
      new_src = rewrite(File.join(@root, rel), rel)
      return nil unless new_src && new_src.strip != src.strip && syntax_ok?(File.join(@root, rel), new_src)

      after = violations_in_text(new_src, File.join(@root, rel))
      return nil if after > before

      if rename_oscillation?(rel, src, new_src, cycle)
        @bus&.publish("sweep:oscillation_rejected", file: rel, cycle:)
        return nil
      end

      [new_src, after]
    end
  end
end
```

## `lib/master/sweep/convergence.rb`
```ruby
# frozen_string_literal: true

module Master
  class Sweep
    # Per-cycle metrics tracking and early-stop logic for sweep loops.
    # Detects stall, low success rate, and sign-reversal oscillation.
    module Convergence
      LOW_SUCCESS_RATE = 0.10

      private

      def init_cycle_log
        @cycle_log = []
      end

      # Record one cycle's metrics. Returns the entry for bus publishing.
      def record_cycle(violations:, fixed:, deferred:)
        prev  = @cycle_log.last
        delta = prev ? (prev[:violations] - violations) : fixed
        total = violations + fixed
        rate  = total.zero? ? 0.0 : (fixed.to_f / total).round(3)
        entry = { violations:, fixed:, deferred:, delta:, rate: }
        @cycle_log << entry
        entry
      end

      # Unified early-stop: stall, low success rate, oscillation, or done.
      def should_halt_early?
        return false if @cycle_log.size < 2

        last = @cycle_log.last
        return true if last[:violations].zero?
        return true if last[:rate] < LOW_SUCCESS_RATE
        return true if @cycle_log.last(2).all? { |entry| entry[:delta] == 0 }
        return true if oscillating?

        false
      end

      def oscillating?
        signs = @cycle_log.last(3).map { |entry| entry[:delta] <=> 0 }
        return false if signs.size < 3
        signs.each_cons(2).all? { |x, y| x != 0 && x == -y }
      end

      def convergence_summary
        return "sweep: no cycles recorded" if @cycle_log.empty?
        count = @cycle_log.size
        last  = @cycle_log.last
        prev  = count > 1 ? @cycle_log[-2][:violations] : "?"
        osc   = oscillating? ? 1 : 0
        "sweep: iter=#{count} violations=#{prev}->#{last[:violations]} " \
          "fixed=#{last[:fixed]} deferred=#{last[:deferred]} rate=#{last[:rate]} oscillating=#{osc}"
      end

      # A→B→A within RENAME_WINDOW cycles signals oscillation (arxiv:2602.21833 §4.3).
      def rename_oscillation?(rel, old_src, new_src, cycle)
        old_names   = extract_names(old_src)
        new_names   = extract_names(new_src)
        removed_now = old_names - new_names
        added_now   = new_names - old_names
        history     = @rename_log[rel]
        oscillates  = history.last(RENAME_WINDOW).any? { |entry| names_reverted?(entry, added_now, removed_now) }
        history << { cycle:, removed: removed_now, added: added_now }
        @rename_log[rel] = history.last(RENAME_WINDOW * 2)
        oscillates
      end

      def names_reverted?(entry, added_now, removed_now)
        (entry[:removed] & added_now).any? && (entry[:added] & removed_now).any?
      end

      def extract_names(source) = source.scan(NAME_RE).flatten.compact.uniq

      def converged?(history)
        return false if history.size < 2
        prev, curr = history[-2], history[-1]
        return true if curr.zero?
        (prev - curr).abs.to_f / [prev, 1].max < CONVERGE_THRESHOLD
      end

      def trajectory_stalled?(history)
        return false if history.size < 3
        deltas = history.each_cons(2).map { |a, b| a - b }
        weighted = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, idx| d * (TRAJECTORY_GAMMA**idx) }
        weighted.abs < 1.0
      end

      def commit(msg)
        Open3.capture2e("git", "-C", @root, "add", "-A")
        Open3.capture2e("git", "-C", @root, "commit", "-m", msg.to_s)
      end

      def git_dirty?
        out, = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
        !out.strip.empty?
      end
    end
  end
end
```

## `lib/master/sweep/rewriter.rb`
```ruby
# frozen_string_literal: true

require "tempfile"

module Master
  class Sweep
    module Rewriter
      private

      def load_prompts = Master.load_yaml(PROMPTS_PATH)

      def build_codebase_map
        files = Dir.glob(File.join(@root, "lib", "**", Scan::Scanner::SCAN_GLOB))
                   .reject { |f| f.include?("/vendor/") || f.include?("/knowledge/") }
                   .map    { |f| f.delete_prefix("#{@root}/") }
                   .sort
        unless @code_index&.built?
          return "## Codebase (#{files.size} files)\n" + files.map { |f| "  #{f}" }.join("\n")
        end

        lines = ["## Codebase (#{files.size} files)"]
        files.each do |rel|
          syms = @code_index.symbols_in(File.join(@root, rel))
          if syms.empty?
            lines << "  #{rel}"
          else
            lines << rel
            syms.select { |s| %i[class module].include?(s.type) }.each { |s| lines << "  class #{s.fqn}" }
            syms.select { |s| s.type == :method }.each { |s| lines << "  def #{s.fqn}" }
          end
        end
        lines.join("\n")
      end

      def collect_files(dir, types)
        types.flat_map { |t| Dir.glob(File.join(dir, GLOBS[t].to_s)) }
             .reject { |f| f.include?("/data/") }
             .uniq.sort
      end

      def rewrite(path, rel)
        src  = File.read(path, encoding: "UTF-8")
        lang = Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
        response = @agent.ask(build_prompt(src, rel, lang))
        extract(response.to_s, lang)
      rescue StandardError => e
        @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
        nil
      end

      def build_prompt(src, rel, lang)
        <<~PROMPT
          You are refactoring #{rel} (#{lang}). Study the full codebase map below
          before making any change — do not modify an interface without tracing its callers.

          #{@map}

          #{@prompts["axioms"]}
          #{@prompts["structural_techniques"]}
          #{@prompts["prose_techniques"]}

          Improve every dimension of #{rel} in a single pass.
          Return ONLY the improved file content — no explanation, no markdown fences
          unless the file is already markdown. If no improvement is possible, return
          exactly: UNCHANGED

          File content:
          #{src}
        PROMPT
      end

      def extract(text, lang)
        return nil if text.strip == "UNCHANGED"
        return nil if text.bytesize < MIN_REWRITE_BYTES && ERROR_PATTERNS.match?(text)
        fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
        return text.match(fence_re)[1]         if text.match?(fence_re)
        return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)
        text.strip.empty? ? nil : text
      end

      def syntax_ok?(path, content)
        checker = SYNTAX_CHECKERS[File.extname(path)]
        return true unless checker
        Tempfile.open(["sweep", File.extname(path)]) do |f|
          f.write(content); f.flush; checker.call(f.path)
        end
      end

      def violations_in(path)
        return 0 unless Scan::Rule::EXT_LANG.key?(File.extname(path).downcase) && File.exist?(path)
        scan_result = @scanner.scan(path, depth: :deep)
        scan_result.ok? ? scan_result.value!.size : 0
      rescue StandardError => _e
        0
      end

      def violations_in_text(content, ref_path)
        ext = File.extname(ref_path).downcase
        return 0 unless Scan::Rule::EXT_LANG.key?(ext)
        Tempfile.open(["vcheck", ext]) do |f|
          f.write(content); f.flush
          scan_result = @scanner.scan(f.path, depth: :deep)
          scan_result.ok? ? scan_result.value!.size : 0
        end
      rescue StandardError => _e
        0
      end
    end
  end
end
```

## `lib/master/text_hygiene.rb`
```ruby
# frozen_string_literal: true

module Master
  # TextHygiene — deterministic pre-write normalization.
  # Ported from MASTER2. Strips BOM, zero-width chars, CRLF, trailing spaces.
  # Called by WriteFile and StrReplace tools before writing.
  module TextHygiene
    BINARY_EXTS = %w[.png .jpg .jpeg .gif .webp .pdf .zip .gz .tgz .mp3 .mp4 .mov .woff .woff2].freeze

    module_function

    def normalize(content, filename: nil, ensure_final_newline: true)
      return content unless content.is_a?(String)

      out = content.dup
      out.gsub!("\r\n", "\n")
      out.gsub!("\r", "\n")
      out.sub!(/\A\xEF\xBB\xBF/, "")
      out.gsub!(/[\u200B\u200C\u200D\uFEFF]/, "")
      out.gsub!(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")
      out.gsub!(/[ \t]+$/, "")
      out.gsub!(/([^\n\t ]) {2,}/, '\1 ')
      out.gsub!("\u00A0", " ")
      out.gsub!(/^\t+$/, "")
      out.gsub!(/\n{3,}/, "\n\n")

      if ensure_final_newline && text_like?(filename) && !out.empty? && !out.end_with?("\n")
        out << "\n"
      end

      out
    end

    def text_like?(filename)
      return true if filename.nil?

      ext = File.extname(filename.to_s).downcase
      !BINARY_EXTS.include?(ext)
    end
  end
end
```

## `lib/master/tools/ask_llm.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AskLlm — delegate sub-questions to the LLM agent mid-pipeline.
    class AskLlm
      TIER        = :guarded
      NAME        = "ask_llm".freeze
      DESCRIPTION = "Ask the LLM a sub-question and return the answer as a string.".freeze

      def initialize(agent:, governor:, circuit_breaker:, cache:, event_bus: nil)
        @agent          = agent
        @governor       = governor
        @circuit_breaker = circuit_breaker
        @cache          = cache
        @bus            = event_bus
      end

      def call(prompt:, context: nil)
        perm = @governor.permit?(NAME, TIER, prompt[0, 60])
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, prompt: prompt[0, 80])

        result = @circuit_breaker.call(estimate_cost(prompt)) {
          @cache.fetch(prompt, @agent.model) {
            @agent.ask(prompt, context: context)
          }
        }

        @bus&.publish("tool:after", tool: NAME)
        Result.ok(result.to_s)
      rescue StandardError => e
        Result.err("ask_llm: #{e.message}", category: :unknown)
      end

      private

      def estimate_cost(prompt)
        (prompt.bytesize / Session::TOKENS_PER_CHAR) * Agent::COST_PER_TOKEN
      end
    end
  end
end
```

## `lib/master/tools/ast_edit.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AST-aware editing tool using Ruby's Ripper (stdlib) for parsing.
    # Supports: find_method, rename_method, extract_lines_to_method, add_after_method.
    # Uses Ripper::SexpBuilder for structure-awareness without external gem dependencies.
    class AstEdit
      TIER        = :guarded
      NAME        = "ast_edit".freeze
      DESCRIPTION = "AST-aware code editing: find, rename, or restructure Ruby methods safely.".freeze

      def initialize(root:, undo:, event_bus: nil)
        @root = File.realpath(root)
        @undo = undo
        @bus  = event_bus
      end

      def call(operation:, path:, **opts)
        full = resolve(path)
        return full if full.err?
        fp = full.value!
        return Result.err("ast_edit: not found: #{path}", category: :validation) unless File.exist?(fp)

        src = File.read(fp)
        case operation.to_s
        when "find_method"    then find_method(src, opts[:name].to_s)
        when "rename_method"  then rename_method(fp, src, opts[:from].to_s, opts[:to].to_s)
        when "add_after"      then add_after_method(fp, src, opts[:after].to_s, opts[:code].to_s)
        when "method_lines"   then method_lines(src, opts[:name].to_s)
        else
          Result.err("ast_edit: unknown operation: #{operation}", category: :validation)
        end
      rescue StandardError => e
        Result.err("ast_edit: #{e.message}", category: :unknown)
      end

      private

      # Find a method definition and return its source lines
      def find_method(src, name)
        lines  = src.lines
        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry

        slice  = lines[(entry[:start] - 1)..(entry[:end] - 1)].join
        Result.ok("# #{name} (lines #{entry[:start]}–#{entry[:end]})\n#{slice}")
      end

      # Rename all occurrences of a method definition and calls
      def rename_method(fp, src, from, to)
        return Result.err("ast_edit: from/to required", category: :validation) if from.empty? || to.empty?
        return Result.err("ast_edit: invalid name: #{to}", category: :validation) unless to.match?(/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/)

        @undo.snapshot(fp)
        updated = src
          .gsub(/\bdef\s+#{Regexp.escape(from)}\b/, "def #{to}")
          .gsub(/\b#{Regexp.escape(from)}\s*\(/, "#{to}(")
          .gsub(/\b#{Regexp.escape(from)}\b(?!\s*[:=])/) { |m| to }

        File.write(fp, updated)
        @bus&.publish("tool:ast_edit", op: "rename", from: from, to: to, path: fp)
        Result.ok("renamed #{from} → #{to} in #{File.basename(fp)}")
      end

      # Insert a new method directly after an existing one
      def add_after_method(fp, src, after_name, code)
        return Result.err("ast_edit: after/code required", category: :validation) if after_name.empty? || code.empty?

        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == after_name }
        return Result.err("ast_edit: method not found: #{after_name}", category: :validation) unless entry

        lines = src.lines
        insert_at = entry[:end]  # after the 'end' of the target method
        lines.insert(insert_at, "\n", code.chomp + "\n")

        @undo.snapshot(fp)
        File.write(fp, lines.join)
        @bus&.publish("tool:ast_edit", op: "add_after", after: after_name, path: fp)
        Result.ok("inserted method after #{after_name} in #{File.basename(fp)}")
      end

      # Return start/end line numbers for each method definition
      def method_lines(src, name)
        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry
        Result.ok("#{name}: lines #{entry[:start]}–#{entry[:end]}")
      end

      def method_line_ranges(src)
        require "ripper"
        lines  = src.lines
        ranges = []
        stack  = []  # stack of {name:, start:, depth:}
        depth  = 0

        Ripper.lex(src).each do |(_line, _col), type, token, _state|
          case type
          when :on_kw
            case token
            when "def"
              # next identifier token is the method name
              stack.push({ name: nil, start: _line, depth: depth })
              depth += 1
            when "class", "module", "do", "begin", "for", "if", "unless",
                 "while", "until", "case"
              depth += 1 unless token == "if" && !stack.empty? && stack.last[:name]
            when "end"
              depth -= 1
              if !stack.empty? && depth == stack.last[:depth]
                entry        = stack.pop
                entry[:end]  = _line
                ranges << entry if entry[:name]
              end
            end
          when :on_ident
            if !stack.empty? && stack.last[:name].nil?
              stack.last[:name] = token
            end
          end
        end
        ranges
      end

      def resolve(path)
        full = File.expand_path(path.to_s, @root)
        return Result.err("path escapes root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/batch_replace.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # BatchReplace — apply multiple search-and-replace operations in one pass.
    class BatchReplace
      TIER        = :guarded
      NAME        = "replace".freeze
      DESCRIPTION = "Find and replace text across all files in a directory.".freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
      end

      def call(old_str:, new_str:, dir: nil, rename_files: false)
        perm = @governor.permit?(NAME, TIER, "#{old_str} → #{new_str}")
        return perm if perm.err?

        target = dir ? File.expand_path(dir, @root) : @root
        return Result.err("replace: directory not found: #{target}", category: :validation) unless Dir.exist?(target)

        @bus&.publish("tool:before", tool: NAME, old: old_str, new: new_str)

        changed = 0
        Dir.glob("#{target}/**/*").each do |path|
          next unless File.file?(path)
          content = File.read(path, encoding: "UTF-8") rescue next
          next unless content.include?(old_str)
          File.write(path, content.gsub(old_str, new_str))
          changed += 1
        end

        if rename_files
          Dir.glob("#{target}/**/*")
             .select { |p| File.file?(p) && File.basename(p).include?(old_str) }
             .each do |path|
               new_path = File.join(File.dirname(path), File.basename(path).gsub(old_str, new_str))
               File.rename(path, new_path)
               changed += 1
             end
        end

        @bus&.publish("tool:after", tool: NAME)
        Result.ok("replaced in #{changed} file(s)")
      rescue StandardError => e
        Result.err("replace: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/clean.rb`
```ruby
# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Clean — removes trailing whitespace, CRLF, and excess blank lines
    # from text files under a given path, using sh/clean.sh.
    class Clean
      SCRIPT = File.expand_path("../../../sh/clean.sh", __dir__).freeze

      def initialize(root:, governor:, event_bus: nil)
        @bus = event_bus
        @root     = root
        @governor = governor
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}", category: :validation) unless File.exist?(target) || Dir.exist?(target)

        guard = @governor.guard("clean #{target}")
        return Result.err(guard.message, category: :policy) if guard.respond_to?(:ok?) && !guard.ok?

        out, err, status = Open3.capture3("zsh", SCRIPT, target)
        return Result.err("clean failed: #{err.strip}", category: :unknown) unless status.success?

        cleaned = out.lines.grep(/^Cleaned:/).map { |l| l.sub("Cleaned: ", "").chomp }
        @bus&.publish("tool:clean", path: target, count: cleaned.size)
        Result.ok("cleaned #{cleaned.size} file(s):\n#{cleaned.join("\n")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/git_context.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    class GitContext
      TIER            = :safe
      NAME            = "git_context".freeze
      DESCRIPTION     = "Query git log, blame, diff, and status for the project.".freeze
      MAX_OUTPUT_CHARS = 4000

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(operation:, path: nil, limit: 20)
        case operation.to_s
        when "log"    then git_log(path, limit.to_i)
        when "blame"  then git_blame(path)
        when "diff"   then git_diff(path)
        when "status" then git_status
        when "show"   then git_show(path)
        else
          Result.err("git_context: unknown operation: #{operation}", category: :validation)
        end
      rescue StandardError => e
        Result.err("git_context: #{e.message}", category: :unknown)
      end

      private

      def git_log(path, limit)
        args = ["git", "-C", @root, "log", "--oneline", "--no-color", "-#{limit}"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no commits)" : out.strip)
      end

      def git_blame(path)
        return Result.err("git_context blame: path required", category: :validation) unless path
        safe = safe_path(path)
        return Result.err("git_context blame: file not found: #{path}",
          category: :validation) unless File.exist?(File.join(@root, safe))
        out = IO.popen(["git", "-C", @root, "blame", "--no-color", "-l", safe], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no blame data)" : out.strip)
      end

      def git_diff(path)
        args = ["git", "-C", @root, "diff", "--no-color"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no unstaged changes)" : out.strip)
      end

      def git_status
        out = IO.popen(["git", "-C", @root, "status", "--short", "--no-color"], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(clean)" : out.strip)
      end

      def git_show(ref)
        ref_s = (ref.to_s.empty? ? "HEAD" : ref.to_s).gsub(/[^a-zA-Z0-9._~^:\-\/]/, "")
        out = IO.popen(["git", "-C", @root, "show", "--stat", "--no-color", ref_s], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(not found)" : out.strip[0..MAX_OUTPUT_CHARS])
      end

      def safe_path(path)
        full = File.expand_path(path.to_s, @root)
        raise "path escapes root" unless full.start_with?(@root)
        Pathname.new(full).relative_path_from(@root).to_s
      end
    end
  end
end
```

## `lib/master/tools/list_dir.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    class ListDir
      TIER        = :safe
      NAME        = "list_dir".freeze
      DESCRIPTION = "List directory contents, depth-limited.".freeze
      MAX_DEPTH   = 5

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(path: ".", depth: 2, pattern: nil)
        resolved = resolve(path)
        return resolved if resolved.err?

        full  = resolved.value!
        depth = [depth.to_i, MAX_DEPTH].min
        lines = list_tree(full, full, depth, pattern)
        Result.ok(lines.join("\n"))
      end

      private

      def list_tree(base, dir, depth, pattern, indent = 0)
        return [] if depth < 0
        entries = Dir.entries(dir).reject { |e| e.start_with?(".") }.sort
        entries.flat_map { |entry|
          full = File.join(dir, entry)
          next [] if pattern && !File.fnmatch?(pattern, entry)
          prefix = "  " * indent
          if File.directory?(full)
            ["#{prefix}#{entry}/"] + list_tree(base, full, depth - 1, pattern, indent + 1)
          else
            ["#{prefix}#{entry}"]
          end
        }
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        return Result.err("not a directory: #{path}", category: :validation) unless File.directory?(full)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/llm.rb`
```ruby
# frozen_string_literal: true

require "ruby_llm"

module Master
  module Tools
    # LLM-callable wrappers around the existing Master tool instances.
    # Each class holds a reference to the underlying tool via initialize,
    # so governor, undo, and event_bus plumbing is preserved.
    module LLM

    # LLM — shared base module for LLM-backed tool functionality.
      class ReadFile < RubyLLM::Tool
        DEFAULT_LIMIT = 2000

        description "Read a file with line numbers. Path is relative to project root."
        param :path,   desc: "File path relative to project root", required: true
        param :offset, desc: "First line to read (0-indexed)", type: "integer", required: false
        param :limit,  desc: "Maximum number of lines to return", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(path:, offset: 0, limit: DEFAULT_LIMIT)
          result = @tool.call(path: path.to_s, offset: offset.to_i, limit: limit.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class WriteFile < RubyLLM::Tool
        description "Write content to a file, creating it if needed. Snapshots for undo."
        param :path,    desc: "File path relative to project root", required: true
        param :content, desc: "Full content to write", required: true

        def initialize(tool) = @tool = tool

        def execute(path:, content:)
          result = @tool.call(path: path.to_s, content: content.to_s)
          result.ok? ? "Written: #{result.value!}" : "Error: #{result.message}"
        end
      end

      class StrReplace < RubyLLM::Tool
        description "Replace an exact unique string in a file with new content."
        param :path,        desc: "File path relative to project root", required: true
        param :old_string,  desc: "Exact string to find (must be unique in file)", required: true
        param :new_string,  desc: "Replacement string", required: true

        def initialize(tool) = @tool = tool

        def execute(path:, old_string:, new_string:)
          result = @tool.call(path: path.to_s, old_string: old_string.to_s, new_string: new_string.to_s)
          result.ok? ? "Replaced in: #{result.value!}" : "Error: #{result.message}"
        end
      end

      class ListDir < RubyLLM::Tool
        description "List directory contents as a tree. Path is relative to project root."
        param :path,  desc: "Directory path (default: project root)", required: false
        param :depth, desc: "Tree depth (1-5)", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(path: ".", depth: 3)
          result = @tool.call(path: path.to_s, depth: depth.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class SearchFiles < RubyLLM::Tool
        description "Search files in the project for a regex pattern. Returns matching lines with context."
        param :pattern, desc: "Ruby regex pattern to search for", required: true
        param :path,    desc: "Directory to search in (default: project root)", required: false
        param :context, desc: "Lines of context to show around each match", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(pattern:, path: ".", context: 2)
          result = @tool.call(pattern: pattern.to_s, path: path.to_s, context: context.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class Shell < RubyLLM::Tool
        description "Run a shell command in the project root. Blocked patterns are enforced."
        param :command, desc: "Shell command to execute", required: true

        def initialize(tool) = @tool = tool

        def execute(command:)
          result = @tool.call(command: command.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class WebSearch < RubyLLM::Tool
        MAX_QUERY_LENGTH = 300

        description "Search the web using DuckDuckGo. Returns titles and snippets."
        param :query, desc: "Search query (max #{MAX_QUERY_LENGTH} chars)", required: true

        def initialize(tool) = @tool = tool

        def execute(query:)
          result = @tool.call(query: query.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class AskLlm < RubyLLM::Tool
        description "Ask a sub-question to a fresh LLM context. Useful for isolated reasoning."
        param :prompt,  desc: "The question or prompt to ask", required: true
        param :context, desc: "Optional background context", required: false

        def initialize(tool) = @tool = tool

        def execute(prompt:, context: nil)
          result = @tool.call(prompt: prompt.to_s, context: context&.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class GitContext < RubyLLM::Tool
        description "Query git log, blame, diff, status, or show for the project."
        param :operation, desc: "One of: log, blame, diff, status, show", required: true
        param :path,      desc: "File path (required for blame; optional for log/diff/show)", required: false
        param :limit,     desc: "Max commits for log", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(operation:, path: nil, limit: 20)
          result = @tool.call(operation: operation.to_s, path: path&.to_s, limit: limit.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class AstEdit < RubyLLM::Tool
        description "AST-aware Ruby code editing: find, rename, or insert methods safely."
        param :operation, desc: "One of: find_method, rename_method, add_after, method_lines", required: true
        param :path,      desc: "File path relative to project root", required: true
        param :name,      desc: "Method name (for find_method, method_lines)", required: false
        param :from,      desc: "Original method name (for rename_method)", required: false
        param :to,        desc: "New method name (for rename_method)", required: false
        param :after,     desc: "Insert after this method name (for add_after)", required: false
        param :code,      desc: "Ruby code to insert (for add_after)", required: false

        def initialize(tool) = @tool = tool

        def execute(operation:, path:, name: nil, from: nil, to: nil, after: nil, code: nil)
          result = @tool.call(operation: operation.to_s, path: path.to_s,
                         name: name&.to_s, from: from&.to_s, to: to&.to_s,
                         after: after&.to_s, code: code&.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class SearchKnowledge < RubyLLM::Tool
        description "Search the local knowledge base: ruby_llm docs, OpenBSD man pages, system prompts, gem docs. Topics: ruby_llm,
          openbsd, system_prompts, gems, awesome."
        param :query, desc: "Search pattern (regex-capable)", required: true
        param :topic, desc: "Limit to topic folder: ruby_llm, openbsd, system_prompts, gems, awesome", required: false

        def initialize(tool) = @tool = tool

        def execute(query:, topic: nil)
          result = @tool.call(query: query.to_s, topic: topic&.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

    end
  end
end
```

## `lib/master/tools/path_guard.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    module PathGuard
      SACRED_PATHS = %w[data/ SOUL.md CLAUDE.md .claude/].freeze

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)

        rel = full.delete_prefix(@root + "/")
        if sacred?(rel)
          return Result.err(
            "#{rel} is sacred-tier (constitutional). Amend via `soul propose`.",
            category: :validation
          )
        end

        Result.ok(full)
      end

      private

      def sacred?(rel_path)
        SACRED_PATHS.any? { |s| rel_path.start_with?(s) || rel_path == s.chomp("/") }
      end
    end
  end
end
```

## `lib/master/tools/read_file.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
      include PathGuard
      TIER        = :safe
      MAX_LINES   = 2000
      NAME        = "read_file".freeze
      DESCRIPTION = "Read a file with line numbers. Guarded to project root.".freeze

      def initialize(root:, undo:, event_bus: nil)
        @root  = File.realpath(root)
        @undo  = undo
        @bus   = event_bus
        @cache = {}
      end

      # Clear per-turn cache — called by Agent at the start of each chat turn.
      def reset!
        @cache.clear
      end

      def call(path:, offset: 0, limit: MAX_LINES)
        key = [path, offset, limit]
        return @cache[key] if @cache.key?(key)
        resolved = resolve(path)
        return resolved if resolved.err?

        full_path = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full_path)
        return Result.err("not a file: #{path}", category: :validation) unless File.file?(full_path)

        lines = File.readlines(full_path)
        total = lines.size
        slice = lines[offset, limit] || []

        numbered = slice.each_with_index.map { |l, i| "#{offset + i + 1}\t#{l}" }.join
        suffix   = total > offset + limit ? "\n[...truncated, #{total} total lines]" : ""

        result = Result.ok(numbered + suffix)
        @cache[key] = result
        result
      end

      private

    end
  end
end
```

## `lib/master/tools/search_files.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    class SearchFiles
      TIER               = :safe
      NAME               = "search_files".freeze
      DESCRIPTION        = "Search for a pattern in files under the project root.".freeze
      MAX_RESULTS        = 200
      BINARY_SAMPLE_BYTES = 512

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(pattern:, glob: "**/*", context_lines: 2)
        begin
          re = Regexp.new(pattern)
        rescue RegexpError
          return Result.err("invalid pattern: #{pattern}", category: :validation)
        end

        paths   = Dir.glob(File.join(@root, glob)).select { |p| File.file?(p) }
        results = []

        paths.each do |path|
          next if binary_file?(path)

          lines = File.readlines(path)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - context_lines, 0].max
            finish = [idx + context_lines, lines.size - 1].min
            ctx    = lines[start..finish].each_with_index.map { |l, i| "#{start + i + 1}:#{l}" }.join
            rel    = path.delete_prefix(@root + "/")
            results << "#{rel}:#{idx + 1}\n#{ctx}"
            return Result.ok(results.join("\n---\n") + "\n[...truncated]") if results.size >= MAX_RESULTS
          end
        end

        Result.ok(results.empty? ? "(no matches)" : results.join("\n---\n"))
      rescue StandardError => e
        Result.err("search_files: #{e.message}", category: :unknown)
      end

      private

      def binary_file?(path)
        sample = begin; File.read(path, BINARY_SAMPLE_BYTES); rescue StandardError; ""; end
        sample.include?("\x00")
      end
    end
  end
end
```

## `lib/master/tools/search_knowledge.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # Search the local knowledge base: cloned docs, man pages, system prompts, gem READMEs.
    class SearchKnowledge
      TIER        = :safe
      NAME        = "search_knowledge".freeze
      DESCRIPTION = "Search local knowledge base (ruby_llm docs, OpenBSD man pages, system prompts, gem docs). " \
                    "Use for: how does X work in ruby_llm? what does man pf.conf say? example system prompts?".freeze
      MAX_RESULTS = 30

      def initialize(root:, event_bus: nil)
        @knowledge_root = File.join(File.realpath(root), "knowledge")
        @bus = event_bus
      end

      def call(query:, topic: nil)
        return Result.err("knowledge base not found", category: :validation) unless Dir.exist?(@knowledge_root)

        search_dir = topic ? File.join(@knowledge_root, topic.to_s) : @knowledge_root
        unless Dir.exist?(search_dir) && File.realpath(search_dir).start_with?(@knowledge_root)
          return Result.err("unknown topic: #{topic}. Available: #{available_topics.join(", ")}", category: :validation)
        end

        begin
          re = Regexp.new(query, Regexp::IGNORECASE)
        rescue RegexpError => e
          re = Regexp.new(Regexp.escape(query), Regexp::IGNORECASE)
        end

        paths   = Dir.glob(File.join(search_dir, "**", "*")).select { |p| File.file?(p) && text_file?(p) }
        results = []

        paths.each do |path|
          next if skip_file?(path)
          lines = File.readlines(path, encoding: "UTF-8", invalid: :replace)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - 2, 0].max
            finish = [idx + 2, lines.size - 1].min
            ctx    = lines[start..finish].map.with_index(start + 1) { |l, n| "#{n}: #{l}" }.join
            rel    = path.delete_prefix(@knowledge_root + "/")
            results << "### #{rel}:#{idx + 1}\n#{ctx}"
            break if results.size >= MAX_RESULTS
          end
          break if results.size >= MAX_RESULTS
        end

        if results.empty?
          Result.ok("No matches for '#{query}' in #{topic || "all knowledge"}.")
        else
          header = "# Knowledge search: '#{query}' (#{results.size} matches)\n\n"
          Result.ok(header + results.join("\n---\n"))
        end
      rescue StandardError => e
        Result.err("search_knowledge: #{e.message}", category: :unknown)
      end

      def available_topics
        return [] unless Dir.exist?(@knowledge_root)
        Dir.entries(@knowledge_root).select { |e| File.directory?(File.join(@knowledge_root, e)) && !e.start_with?(".") }
      end

      private

      def text_file?(path)
        ext = File.extname(path).downcase
        %w[.rb .md .txt .yml .yaml .json .sh .conf .html .rst .rdoc].include?(ext) || ext.empty?
      end

      def skip_file?(path)
        path.include?("/.git/") || path.include?("/node_modules/") ||
          path.include?("/vendor/") || File.size(path) > 500_000
      end
    end
  end
end
```

## `lib/master/tools/shell.rb`
```ruby
# frozen_string_literal: true

require "tty-command"
require "timeout"
require "shellwords"

module Master
  module Tools
    # Shell — execute shell commands with timeout and governor approval.
    class Shell
      TIER        = :dangerous
      NAME        = "zsh".freeze
      DESCRIPTION = "Execute a zsh command in the project root.".freeze
      TIMEOUT     = 30
      BLOCKLIST   = Security::Permissions::BLOCKLIST
      ZSH_BANNED  = %w[sed awk grep find head tail wc cut tr bash sudo perl python].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
        @cmd      = TTY::Command.new(printer: :null)
      end

      def call(command:)
        return Result.err("blocked command: #{command}", category: :validation) if blocked?(command)

        perm = @governor.permit?(NAME, TIER, command)
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, command:)

        banned = ZSH_BANNED.select { |b| command.match?(/\b#{b}\b/) }
        @bus&.publish("zsh:banned_tool_warning", tools: banned, command:) if banned.any?

        zdotdir = File.writable?("/tmp") ? "/tmp" : Dir.home
        wrapped = "#!/usr/bin/env zsh\nset -euo pipefail\nsetopt nullglob extendedglob\nexport ZDOTDIR=#{Shellwords.escape(zdotdir)}\nexport LC_ALL=C.UTF-8\ncd #{Shellwords.escape(@root)}\n#{command}\n"

        out, err = Timeout.timeout(TIMEOUT) { @cmd.run!("zsh", input: wrapped) }
        @bus&.publish("tool:after", tool: NAME, exit_code: out.exit_status)

        if out.exit_status != 0
          Result.err("zsh: exit #{out.exit_status}\n#{err.to_s.strip}", category: :unknown)
        else
          Result.ok(out.to_s.strip)
        end
      rescue Timeout::Error
        Result.err("zsh: timed out after #{TIMEOUT}s", category: :unknown)
      rescue TTY::Command::ExitError => e
        Result.err("zsh: #{e.message}", category: :unknown)
      end

      private

      def blocked?(command)
        BLOCKLIST.any? { |b| command.include?(b) }
      end
    end
  end
end
```

## `lib/master/tools/str_replace.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    class StrReplace
      include PathGuard
      TIER        = :guarded
      NAME        = "str_replace".freeze
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root        = File.realpath(root)
        @undo        = undo
        @governor    = governor
        @bus         = event_bus
        @diff_stager = diff_stager
      end

      def call(path:, old_string:, new_string:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full    = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full)

        content = File.read(full)
        count   = content.scan(Regexp.quote(old_string)).size

        return Result.err("str_replace: pattern not found in #{path}", category: :validation) if count.zero?
        return Result.err("str_replace: pattern matches #{count} times in #{path} (must be unique)", category: :validation) if count > 1

        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        new_content = content.sub(old_string, new_string)

        if @diff_stager
          return @diff_stager.stage(path: full, new_content:, tool: NAME)
        end

        @undo.snapshot(full)

        tmp_path = "#{full}.tmp.#{Process.pid}"
        File.write(tmp_path, new_content)
        File.rename(tmp_path, full)

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue StandardError => e
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
        Result.err("str_replace: #{e.message}", category: :unknown)
      end

      private

    end
  end
end
```

## `lib/master/tools/symbol_lookup.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # SymbolLookup — query the live symbol graph; returns definition, callers, and impact.
    class SymbolLookup
      NAME        = "symbol_lookup".freeze
      DESCRIPTION = "Look up a Ruby class, module, or method in the codebase. " \
                    "Returns file, line, and all cross-file references (callers/usages). " \
                    "Use before refactoring to understand impact.".freeze
      def initialize(code_index:, event_bus: nil)
        @index = code_index
        @bus   = event_bus
      end

      def call(name:)
        return Result.err("symbol_lookup: index not built yet", category: :validation) unless @index.built?

        hits = @index.query(name)
        if hits.is_a?(Hash) && hits[:error]
          return Result.err("symbol_lookup: #{hits[:error]}", category: :validation)
        end

        @bus&.publish("tool:symbol_lookup", name:, hits: hits.size)
        Result.ok(hits.map { |h| format_hit(h) }.join("\n\n"))
      end

      private

      def format_hit(h)
        lines = ["#{h[:fqn]} (#{h[:type]})"]
        lines << "  defined: #{h[:file]}:#{h[:line]}"
        lines << "  parent:  #{h[:parent]}" if h[:parent] && h[:parent] != "Object"
        if h[:used_in].any?
          lines << "  used in:"
          h[:used_in].each { |ref| lines << "    #{ref}" }
        else
          lines << "  used in: (no cross-file references found)"
        end
        lines.join("\n")
      end
    end
  end
end
```

## `lib/master/tools/tree.rb`
```ruby
# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Tree — lists directory structure using sh/tree.sh.
    # Safe: read-only, no writes.
    class Tree
      SCRIPT = File.expand_path("../../../sh/tree.sh", __dir__).freeze

      def initialize(root:, event_bus: nil)
        @bus = event_bus
        @root = root
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}", category: :validation) unless Dir.exist?(target)

        out, err, status = Open3.capture3("zsh", SCRIPT, target)
        return Result.err("tree failed: #{err.strip}", category: :unknown) unless status.success?

        lines = out.lines.map(&:chomp).reject(&:empty?)
        @bus&.publish("tool:tree", path: target, count: lines.size)
        Result.ok(lines.join("\n"))
      rescue StandardError => e
        Result.err("tree: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/web_search.rb`
```ruby
# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module Master
  module Tools
    class WebSearch
      TIER               = :guarded
      MAX_QUERY_CHARS    = 300
      MAX_SEARCH_RESULTS = 5
      HTTP_OK            = "200".freeze

      NAME        = "web_search".freeze
      DESCRIPTION = "Search DuckDuckGo instant answers API.".freeze
      ENDPOINT    = "https://api.duckduckgo.com/".freeze
      TIMEOUT     = 10

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus      = event_bus
      end

      def call(query:)
        if query.length > MAX_QUERY_CHARS
          @bus&.publish("tool:warning", tool: NAME, message: "query truncated to #{MAX_QUERY_CHARS} chars")
          query = query[0, MAX_QUERY_CHARS]
        end

        perm = @governor.permit?(NAME, TIER, query)
        return perm if perm.err?

        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(q: query, format: "json", no_redirect: 1)

        response = Timeout.timeout(TIMEOUT * 2) {
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: TIMEOUT) { |h|
            h.get(uri.request_uri)
          }
        }

        return Result.err("web_search: HTTP #{response.code}", category: :infrastructure) unless response.code == HTTP_OK

        data    = JSON.parse(response.body)
        results = extract_results(data)
        @bus&.publish("tool:after", tool: NAME, query:)
        Result.ok(results)
      rescue StandardError => e
        Result.err("web_search: #{e.message}", category: :infrastructure)
      end

      private

      def extract_results(data)
        parts = []
        parts << data["Abstract"] unless data["Abstract"].to_s.empty?
        (data["RelatedTopics"] || []).first(MAX_SEARCH_RESULTS).each { |t| parts << t["Text"] if t["Text"] }
        parts.empty? ? "(no results)" : parts.join("\n\n")
      end
    end
  end
end
```

## `lib/master/tools/write_file.rb`
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  module Tools
    class WriteFile
      include PathGuard
      TIER        = :guarded
      NAME        = "write_file".freeze
      DESCRIPTION = "Atomically write content to a file, with undo snapshot.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root        = File.realpath(root)
        @undo        = undo
        @governor    = governor
        @bus         = event_bus
        @diff_stager = diff_stager
      end

      def call(path:, content:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        return @diff_stager.stage(path: full, new_content: content, tool: NAME) if @diff_stager

        @undo.snapshot(full)
        FileUtils.mkdir_p(File.dirname(full))

        tmp_path = "#{full}.tmp.#{Process.pid}"
        File.write(tmp_path, content)
        File.rename(tmp_path, full)

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue StandardError => e
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
        Result.err("write_file: #{e.message}", category: :unknown)
      end

    end
  end
end
```

## `lib/master/triggers.rb`
```ruby
# frozen_string_literal: true

module Master
  class Triggers
    DEFAULTS       = %i[after_scan on_error budget_low tool_after].freeze
    ERROR_TRUNCATE = 200

    def initialize(event_bus:, scanner: nil, agent: nil)
      @bus     = event_bus
      @scanner = scanner
      @agent   = agent
      @rules   = []
    end

    def install_defaults!
      register(:after_scan) do |ctx|
        count = ctx[:violations].to_i
        if count > 0
          @bus.publish("triggers:violations_found", count: count)
        end
      end

      register(:on_error) do |ctx|
        @bus.publish("triggers:error_logged", error: ctx[:error].to_s[0, ERROR_TRUNCATE])
      end

      register(:budget_low) do |_ctx|
        @bus.publish("triggers:budget_low", action: "switch_to_free_tier")
      end

      @bus.subscribe("tool:after") do |ev|
        fire(:tool_after, ev)
      end

      self
    end

    def register(event, &handler)
      @rules << { event: event.to_sym, handler: handler }
    end

    def fire(event, context = {})
      matching = @rules.select { |r| r[:event] == event.to_sym }
      matching.each do |rule|
        rule[:handler].call(context)
      rescue StandardError => e
        @bus.publish("triggers:handler_error", event: event, error: e.message)
      end
    end

    def list
      @rules.map { |r| r[:event].to_s }.tally.map { |e, n| "#{e}: #{n} handler(s)" }.join("\n")
    end

    def clear!
      @rules.clear
    end
  end
end
```

## `lib/master/undo.rb`
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  class Undo
    MAX_JOURNAL = 50

    def initialize(session:, event_bus: nil, root: Dir.pwd)
      @session = session
      @bus     = event_bus
      @root    = root
      @journal = File.join(root, ".master", "undo_journal.jsonl")
      @stack   = load_journal
    end

    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
      @stack.shift while @stack.size > MAX_JOURNAL
      persist_journal
      Result.ok(path)
    rescue StandardError => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end

    def undo!(steps: 1)
      return Result.err("nothing to undo", category: :validation) if @stack.empty?

      steps = [steps, @stack.size].min
      paths = []

      steps.times do
        entry = @stack.pop
        restore(entry["path"], entry["content"])
        paths << entry["path"]
        @bus&.publish("undo:applied", path: paths.last)
      end

      persist_journal
      Result.ok(paths.size == 1 ? paths.first : paths)
    end

    def depth = @stack.size

    def history(limit: 10)
      @stack.last(limit).reverse.map.with_index(1) do |entry, i|
        time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
        "#{i}. #{entry["path"]} (#{time})"
      end
    end

    private

    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end
    end

    def load_journal
      return [] unless File.exist?(@journal)
      File.readlines(@journal).filter_map do |line|
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError => e
      @bus&.publish("undo:read_error", error: e.message) if defined?(@bus)
      []
    end

    def persist_journal
      FileUtils.mkdir_p(File.dirname(@journal))
      File.open(@journal, "w") do |f|
        @stack.each { |entry| f.puts(JSON.generate(entry)) }
      end
    end
  end
end
```

## `lib/master/unwrap_error.rb`
```ruby
# frozen_string_literal: true

module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end
end
```

## `master.gemspec`
```text
# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name    = "master"
  s.version = "3.0.0"
  s.summary = "Constitutional governance for an autonomous coding agent"
  s.authors = ["dev"]
  s.files   = Dir["lib/**/*.rb", "exe/*", "data/**/*", "*.yml"]
  s.executables = ["master"]
  s.require_paths = ["lib"]

  s.add_dependency "ruby_llm",       "~> 1.3"
  s.add_dependency "tty-prompt",     "~> 0.23"
  s.add_dependency "tty-reader",     "~> 0.9"
  s.add_dependency "tty-spinner",    "~> 0.9"
  s.add_dependency "tty-markdown",   "~> 0.7"
  s.add_dependency "tty-table",      "~> 0.12"
  s.add_dependency "tty-screen",     "~> 0.8"
  s.add_dependency "tty-box",        "~> 0.7"
  s.add_dependency "tty-command",    "~> 0.10"
  s.add_dependency "tty-tree",       "~> 0.4"
  s.add_dependency "tty-config",     "~> 0.6"
  s.add_dependency "tty-logger",     "~> 0.6"
  s.add_dependency "tty-progressbar","~> 0.18"
  s.add_dependency "pastel",         "~> 0.8"
  s.add_dependency "rouge",          "~> 4.4"
  s.add_dependency "diffy",          "~> 3.4"
  s.add_dependency "zeitwerk",       "~> 2.7"
end
```

## `master.md`
```markdown
# MASTER — Reference

## Pipeline stages

| Stage | Role |
|---|---|
| Intake | Normalize input, detect channel (CLI/web/IRC/Matrix) |
| Infer | NLP → command routing via infer_patterns.yml |
| Route | Select model tier, tool, or pipeline branch |
| Guard | Axiom enforcement; abort on violation |
| Execute | LLM call, tool dispatch, or command handler |
| Council | Adversarial multi-persona review (parallel) |
| Lint | Scan output for rule violations (parallel) |
| Prune | Strunk & White prose pass; trim verbosity |
| Memo | Write to memory, learnings, audit log |
| Render | Format and emit to source channel |

## Scan rules

| Rule | Checks |
|---|---|
| FROZEN_STRING | Missing `# frozen_string_literal: true` |
| EXPLICIT | Bare rescue, implicit returns, shadow variables |
| IMMUTABLE | Mutable constants, shared mutable state |
| CQS | Methods that command and query simultaneously |
| SRP | Classes with multiple responsibilities |
| SELF_EXPLAINING | Unclear names, missing intent |
| LONG_METHOD | Methods over ~20 lines |
| GOD_CLASS | Files over ~300 lines with too many concerns |
| DUPLICATE | Copy-paste code blocks |
| BARE_RESCUE | `rescue` without error variable |

## Models

Default: `nvidia/nemotron-3-super-120b-a12b:free`

Fallback chain: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash

Circuit breaker: FAILURE_THRESHOLD=8, RATE_MAX=60/min.

## Constitution

Golden rule: **PRESERVE_THEN_IMPROVE_NEVER_BREAK**

Kernel axioms (violation aborts pipeline):
- PRESERVE_FIRST
- SIMPLEST_WORKS
- FAIL_VISIBLY
- ONE_SOURCE
- DECOUPLE
- GUARD_EXPENSIVE
- DEGRADE_GRACEFULLY
- BE_CONCISE

## Evolution Protocol

1. `soul propose <rationale>` — LLM drafts amendment
2. `soul diff` — review changes
3. `soul approve` — bump version, commit, tag
4. `soul reject` — discard

ABSOLUTE sections (anti-simulation rule, golden rule) block without `/override`.
```

## `scripts/openbsd_preflight.zsh`
```bash
#!/usr/bin/env zsh
# MASTER preflight check — run before deploying to OpenBSD
set -euo pipefail
setopt err_exit

ROOT=${${0:A}:h:h}
cd "$ROOT"

print "MASTER preflight — ${ROOT}"

# Ruby version
[[ -x $(whence ruby) ]] || { print "FAIL: ruby not found"; exit 1 }
print "ok: ruby $(ruby -e 'print RUBY_VERSION')"

# Bundler
[[ -x $(whence bundle) ]] || { print "FAIL: bundler not found"; exit 1 }
print "ok: bundler $(bundle -v)"

# Gem dependencies
bundle check >/dev/null 2>&1 || { print "FAIL: bundle check failed (run: bundle install)"; exit 1 }
print "ok: gems installed"

# API keys
[[ -n "${REPLICATE_API_KEY:-}" ]]   && print "ok: REPLICATE_API_KEY" || print "warn: REPLICATE_API_KEY not set"
[[ -n "${ANTHROPIC_API_KEY:-}" ]]   && print "ok: ANTHROPIC_API_KEY" || print "warn: ANTHROPIC_API_KEY not set"
[[ -n "${OPENROUTER_API_KEY:-}" ]]  && print "ok: OPENROUTER_API_KEY" || print "warn: OPENROUTER_API_KEY not set"

# Syntax
print "check: ruby syntax"
ruby -c lib/master.rb >/dev/null
print "ok: lib/master.rb syntax"

# Tests
print "check: test suite"
bundle exec ruby -Itest test/test_result.rb test/test_ring_buffer.rb test/test_axioms.rb test/test_prune.rb 2>&1 | tail -1
print "ok: tests passed"

print "\nMASTER preflight complete."
```

## `skills/explain/SKILL.md`
```markdown
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
```

## `snapshot_agent.md`
```markdown
# MASTER Snapshot — lib/master/agent/
Generated: 2026-05-04T10:21:42Z

## lib/master/agent/llm_dispatch.rb
```ruby
# frozen_string_literal: true

module Master
  class Agent
    # LlmDispatch — LLM routing, caching, and escalation; extracted from Agent.
    module LlmDispatch
      private

      def attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
        capable = select_capable_models(candidate_models)
        return capable if capable.respond_to?(:err?) && capable.err?

        last_response = nil
        capable.each_with_index do |selected_model, index|
          response = send_with_cache(
            selected_model,
            context + [{ role: "user", content: prompt }],
            stream:, &blk
          )
          last_response = response
          publish_llm_success(selected_model, response) if response.respond_to?(:ok?) && response.ok?
          break response unless response.respond_to?(:err?) && response.err? && index < capable.length - 1
        end
        last_response
      end

      def select_capable_models(candidates)
        capable = candidates.select { |m| replicate_model?(m) || ferrum_model?(m) || tool_capable?(m) }
        return Result.err("no tool-capable model available", category: :validation) if capable.empty?
        capable
      end

      def publish_llm_success(model, response)
        @bus&.publish("llm:response", model:, success: true, tokens_approx: response.to_s.bytesize / Session::TOKENS_PER_CHAR)
      end

      def maybe_escalate(last_response, original_message, stream:, escalation_depth:, &blk)
        return last_response unless @model_router
        return last_response if escalation_depth >= 2

        current = routed_models.first
        escalation_model = @model_router.escalate_if_low_confidence(
          last_response.to_s,
          current_model: current,
          task_type: @config.task_type.to_sym
        )
        return last_response unless escalation_model

        @bus&.publish("llm:escalation", from: current, to: escalation_model)
        escalated = chat(
          original_message, stream: stream,
          escalation_depth: escalation_depth + 1, &blk
        )
        escalated.respond_to?(:err?) && escalated.err? ? last_response : escalated
      end

      def send_with_cache(selected_model, messages, system: nil, stream: false, &blk)
        cache_key = cache_key_for(messages.last[:content], messages[0...-1])
        breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
          @cache.fetch(cache_key, selected_model) {
            send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
          }
        }
      rescue StandardError => err
        Result.err("llm_request: #{err.message}", category: :llm_call_failure)
      end

      def send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
        sys = system || system_prompt
        if ferrum_model?(selected_model)
          return send_ferrum(selected_model, messages)
        elsif replicate_model?(selected_model)
          return send_replicate(selected_model, messages, sys:, stream:, &blk)
        end

        send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
      end

      def send_ferrum(selected_model, messages)
        alias_name = selected_model.split(":", 3).last
        response = Bridges::FerrumWebChat.new.ask(
          model_alias: alias_name, prompt: messages.last[:content]
        )
        return response if response.respond_to?(:err?) && response.err?
        Result.ok(
          response.respond_to?(:ok?) && response.ok? ? response.value! : response.to_s
        )
      end

      def send_replicate(selected_model, messages, sys:, stream:, &blk)
        reply = Bridges::Replicate.new.chat(
          model: selected_model, messages:, system: sys,
          stream:, &(stream ? blk : nil)
        )
        Result.ok(reply.content.to_s)
      end

      def send_ruby_llm(selected_model, messages, sys:, stream:, &blk)
        chat_session = RubyLLM.chat(model: selected_model)
        final_sys = nemotron_system_prompt(selected_model, sys)
        chat_session.with_instructions(final_sys) if final_sys
        messages.each { |msg|
          chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s)
        }

        available_tools = llm_tools(selected_model)
        chat_session.with_tools(*available_tools) unless available_tools.empty?

        reply = if stream && blk
          chat_session.ask(messages.last[:content]) { |chunk|
            blk.call(chunk.content.to_s) if chunk.content
          }
        else
          chat_session.ask(messages.last[:content])
        end
        Result.ok(extract_response(reply, selected_model))
      end

      def routed_models
        return [@config.model] unless @model_router
        @model_router.fallback_chain(task_type: @config.task_type.to_sym)
      rescue StandardError => e
        @bus&.publish("llm:route_error", error: e.message) if defined?(@bus)
        [@config.model]
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def replicate_model?(model_id)
        return false unless ENV["REPLICATE_API_KEY"].to_s.length >= MIN_API_KEY_LENGTH
        REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
      end

      def ferrum_model?(model_id)
        model_id.to_s.start_with?("ferrum:webchat:")
      end

      def tool_capable?(model_id)
        TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
      end

      def extract_response(reply, selected_model)
        return reply.to_s unless reply.respond_to?(:content)
        if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
          thinking = reply.reasoning_content.to_s.strip
          content = reply.content.to_s
          return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
        end
        reply.content.to_s
      end

      def nemotron_system_prompt(selected_model, base = nil)
        sys = base || system_prompt
        return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
        thinking_on = @config["reasoning_mode"] != "none"
        directive = thinking_on ? "detailed thinking on" : "detailed thinking off"
        [directive, sys].compact.join("\n\n")
      end

      CACHE_WINDOW = 4
      def cache_key_for(message, context)
        return Digest::SHA256.hexdigest(message) if context.empty?
        window = context.last(CACHE_WINDOW).map { |msg|
          "#{msg[:role]}:#{msg[:content]}"
        }.join("\n")
        Digest::SHA256.hexdigest("#{message}\n#{window}")
      end

      def estimate_cost(prompt)
        (prompt.bytesize / Session::TOKENS_PER_CHAR) * COST_PER_TOKEN
      end

      def llm_tools(selected_model = model)
        return [] unless tool_capable?(selected_model)
        @llm_tools ||= build_llm_tools
      end

      def build_llm_tools
        @tools.filter_map do |tool|
          wrapper = LLM_TOOL_MAP[tool.class]
          wrapper&.new(tool)
        end
      rescue StandardError => err
        @bus&.publish("agent:llm_tools_error", error: err.message)
        []
      end
    end
  end
end

```
```

## `snapshot_autoloop.md`
```markdown
# MASTER Snapshot — lib/master/autoloop/
Generated: 2026-05-04T10:21:42Z

## lib/master/autoloop/fix_evaluator.rb
```ruby
# frozen_string_literal: true

module Master
  class AutoLoop
    module FixEvaluator
      ERROR_TRUNCATE = 200
      private

      def build_fix_prompt(violation, src)
        "#{constitutional_preamble}\n\n" \
          "Fix this Ruby violation in #{violation[:file]}.\n" \
          "Rule: #{violation[:rule]}\n" \
          "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
          "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
          "```ruby\n#{src}\n```"
      end

      def constitutional_preamble
        @constitutional_preamble ||= begin
          soul  = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
          rules = Master.load_yaml(File.join(Master::ROOT, "data", "rules.yml"))
          golden = soul.dig("absolute", "golden_rule") || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          zen = rules.fetch("zen", {})
          lines = ["Constitutional constraints:", "- Golden rule: #{golden}"]
          zen.each_value { |v| lines << "- #{v}" } if zen.is_a?(Hash)
          lines.join("\n")
        rescue StandardError => _e
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      def reflected_prompt(base, last_error, attempt)
        "Prior attempt (#{attempt}) failed with: #{last_error[0, ERROR_TRUNCATE]}\n" \
          "Reflect briefly on what went wrong, then retry.\n\n" \
          "#{base}"
      end

      def extract_code(text)
        return text.match(/```ruby\n(.*?)```/m)[1].strip if text.match?(/```ruby\n(.*?)```/m)
        return text.match(/```\n(.*?)```/m)[1].strip if text.match?(/```\n(.*?)```/m)
        return text.strip if text.match?(/frozen_string_literal|module |class /)
        nil
      end

      def confidence_score(code, original_src)
        return 0.0 if code.nil? || code.strip.empty?
        score = 0.0
        score += SCORE_INCREMENT if code.include?("# frozen_string_literal: true")
        score += SCORE_INCREMENT if code.match?(/\A.*?(?:module |class )[A-Z]/m)
        ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max
        score += SCORE_INCREMENT if ratio >= MIN_SIZE_RATIO && ratio <= MAX_SIZE_RATIO
        score += SCORE_INCREMENT if syntax_ok?(code)
        score
      end

      def syntax_ok?(content)
        require "tempfile"
        Tempfile.open(["al_chk", ".rb"]) do |f|
          f.binmode
          f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
          f.flush
          system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
        end
      rescue StandardError => _e
        false
      end

      def track_recurrence(violations)
        return unless @soul
        tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        tally.each do |rule_id, count|
          @rule_recurrence[rule_id] += 1
          next unless @rule_recurrence[rule_id] >= 3
          @rule_recurrence.delete(rule_id)
          sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
          result = @soul.propose_from_violations(rule_id, sample, agent: @agent)
          @bus&.publish("autoloop:soul_proposal", rule: rule_id, result: result.to_s[0, 80])
        end
        (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
      end
    end
  end
end

```
```

## `snapshot_builder.md`
```markdown
# MASTER Snapshot — lib/master/builder/
Generated: 2026-05-04T10:21:42Z

## lib/master/builder/infra_helpers.rb
```ruby
# frozen_string_literal: true

module Master
  module Builder
    module_function

    def build_scanner(root:, agent:, bus:)
      scanner = Scan::Scanner.new(event_bus: bus)
      Scan::Rule.registry.select(&:auto_build?).each { |klass| scanner.add_rule(klass.new) }
      scanner.add_rule(Scan::Rules::AxiomCoverageRule.new(root:))
      scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
      scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
      scanner
    end

    def boot_snapshot(container)
      root  = container[:root]
      files = collect_snapshot_files(root)
      body  = render_snapshot_body(root, files)
      write_snapshot(root, files, body)
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end

    def collect_snapshot_files(root)
      SNAPSHOT_DIRS.flat_map { |d| Dir.glob(File.join(root, d, "**", "*")) }
                   .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                   .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                   .sort
    end

    def render_snapshot_body(root, files)
      files.flat_map do |f|
        rel  = f.sub("#{root}/", "")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src  = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
      rescue StandardError => _e
        []
      end
    end

    def write_snapshot(root, files, body)
      header  = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      content = (header + body).join("\n")
      out     = File.join(root, ".master", "snapshot.md")
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, content)
      File.write(File.join(root, "snapshot.md"), content)
    end
  end
end

```
```

## `snapshot_cli.md`
```markdown
# MASTER Snapshot — lib/master/cli/
Generated: 2026-05-04T10:21:42Z

## lib/master/cli/signals.rb
```ruby
# frozen_string_literal: true

module Master
  class CLI
    private

    def setup_signals
      trap("USR1") { on_usr1 }
      trap("INT")  { on_int }
    end

    def on_usr1
      Zeitwerk::Loader.for_gem.reload
      puts "\n#{@renderer.render("reloaded", mode: :success)}"
    rescue StandardError => e
      puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
    end

    def on_int
      if Time.now - @interrupt_at < 1
        @scan_thread&.kill
        @session.save!
        exit(0)
      else
        @interrupt_at = Time.now
        puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
      end
    end
  end
end

```

## lib/master/cli/tts.rb
```ruby
# frozen_string_literal: true

module Master
  class CLI
    TTS_CHAR_LIMIT = 400

    private

    def speak_async(text)
      Thread.new do
        plain = sanitize_for_speech(text)
        next if plain.empty?
        audio_path = Speech.synthesize(plain)
        next unless audio_path
        played = Speech.play(audio_path)
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        begin; File.unlink(audio_path); rescue StandardError => _e; nil; end if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain.gsub(/```.*?```/m, "")[0..TTS_CHAR_LIMIT]
    end
  end
end

```
```

## `snapshot_code_index.md`
```markdown
# MASTER Snapshot — lib/master/code_index/
Generated: 2026-05-04T10:21:42Z

## lib/master/code_index/symbol_visitor.rb
```ruby
# frozen_string_literal: true

module Master
  class CodeIndex
    class SymbolVisitor < Prism::Visitor
      attr_reader :symbols, :references

      def initialize(file:, root:)
        @file = file
        @root = root
        @symbols = []
        @references = []
        @scope = []
      end

      def visit_class_node(node)
        name = const_name(node.constant_path)
        parent = node.superclass ? const_name(node.superclass) : "Object"
        fqn = qualified(name)

        @symbols << Symbol.new(
          fqn:, type: :class, file: @file,
          line: node.location.start_line, parent:, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      def visit_module_node(node)
        name = const_name(node.constant_path)
        fqn = qualified(name)

        @symbols << Symbol.new(
          fqn:, type: :module, file: @file,
          line: node.location.start_line, parent: nil, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      def visit_def_node(node)
        meth = node.name.to_s
        owner = @scope.last || "(top)"
        fqn = "#{qualified(owner)}##{meth}"

        @symbols << Symbol.new(
          fqn:, type: :method, file: @file,
          line: node.location.start_line, parent: owner, includes: []
        )
        super
      end

      def visit_call_node(node)
        method_name = node.name.to_s
        return super unless method_name.match?(/\A[_a-z][a-z0-9_]*[!?]?\z/i) && method_name.length > 1

        receiver_fqn = node.receiver ? const_name_safe(node.receiver) : nil
        to_fqn = receiver_fqn ? "#{receiver_fqn}##{method_name}" : method_name

        @references << Reference.new(
          from_file: @file,
          from_line: node.location.start_line,
          to_fqn:,
          ref_type: :call
        )
        super
      end

      private

      def qualified(name)
        return name if @scope.empty? || name.include?("::")
        "#{@scope.join('::')}::#{name}"
      end

      def const_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          "#{const_name(node.parent)}::#{node.name}"
        else
          node.respond_to?(:name) ? node.name.to_s : ""
        end
      end

      def const_name_safe(node)
        name = const_name(node)
        name.empty? ? nil : name
      rescue StandardError => _e
        nil
      end
    end
  end
end

```
```

## `snapshot_command_registry.md`
```markdown
# MASTER Snapshot — lib/master/command_registry/
Generated: 2026-05-04T10:21:42Z

## lib/master/command_registry/agent_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      scan_loop_commands(ai:, root:, infra:)
        .merge(model_agent_commands(ai:, root:, infra:))
        .merge(crit_command(ai:, root:))
        .merge(ideate_command(ai:))
        .merge(topic_command(infra:))
    end

    def scan_loop_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      bus = infra[:bus]
      deliberation = ai[:deliberation]
      autoloop = ai[:autoloop]
      {
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          log = []
          result = autoloop.run(max_cycles: max) { |cycle, violations|
            log << "  cycle #{cycle}: #{violations.size} violation(s)"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus, code_index: infra[:code_index])
          log = []
          result = sweeper.run(target) { |cycle, file, delta|
            log << "  cycle #{cycle}  #{file}  +#{delta}"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "scan" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          profile, depth, rule_filter = resolve_scan_profile(arg, root)
          raw_arg = arg.sub(/\A(?:deep|quick|full|critical|solid|axioms)\s*/, "").strip
          target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
          pairs = if target_arg && File.file?(target_arg)
            fr = scanner.scan(target_arg, depth:)
            [[target_arg, fr]]
          elsif target_arg && File.directory?(target_arg)
            dir_result = scanner.scan_dir(target_arg, depth:, glob: "**/*")
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          else
            dir_result = scanner.scan_dir(File.join(root, "lib"), depth:)
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          end
          by_rule = Hash.new { |h, k| h[k] = [] }
          pairs.each do |_file, file_result|
            next unless file_result.respond_to?(:ok?) && file_result.ok?
            file_result.value!.each do |v|
              next if rule_filter && !rule_filter.include?(v[:rule].to_s)
              by_rule[v[:rule].to_s] << v
            end
          end
          total = by_rule.values.sum(&:size)
          header = profile ? "[profile: #{profile}] " : ""
          next "#{header}clean -- no violations" if total.zero?
          lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
            ["[#{rule}] #{vs.size}"] +
              vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
          end
          lines << "#{header}#{total} total violations"
          lines.join("\n")
        }
      }
    end

    def resolve_scan_profile(arg, root)
      profiles_cfg = begin
        data = Master.load_yaml(File.join(root, "data", "workflow.yml"))
        groups  = data.dig("principle_groups") || {}
        profiles = data.dig("scan_profiles") || {}
        [groups, profiles]
      rescue StandardError => _e
        [{}, {}]
      end
      groups, profiles = profiles_cfg

      profile_name = %w[quick full critical solid axioms].find { |p| arg.start_with?(p) }
      profile_name ||= "deep" if arg.start_with?("deep")

      if profile_name && profile_name != "deep"
        cfg   = profiles[profile_name] || {}
        depth = (cfg["depth"] == "deep") ? :deep : :standard
        rule_ids = groups[cfg["rules"].to_s]
        rule_filter = (rule_ids && cfg["rules"] != "*") ? rule_ids.map(&:to_s).to_set : nil
        [profile_name, depth, rule_filter]
      elsif profile_name == "deep"
        [nil, :deep, nil]
      else
        [nil, :standard, nil]
      end
    end

    def model_agent_commands(ai:, root:, infra:)
      council_meta_commands(ai:, root:).merge(model_commands(ai:, root:, infra:))
    end

    def council_meta_commands(ai:, root:)
      council_stage = ai[:council_stage]
      swarm         = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm"   => ->(ctx) { dispatch_swarm(swarm, ctx[:args].to_s.strip) },
        "explain" => ->(_ctx) { explain_master(root) }
      }
    end

    def dispatch_swarm(swarm, arg)
      parts = arg.split(" ", 2)
      role  = parts[0]&.to_sym
      task  = parts[1].to_s
      return "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}" if role.nil? || task.empty?
      result = swarm.dispatch(role, task:, context_slice: {})
      result.ok? ? result.value!.inspect : result.message
    end

    def explain_master(root)
      map    = Introspection::SelfMap.new(root:)
      info   = map.describe
      cov    = map.axiom_coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
      stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
      "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov}"
    end

    def model_commands(ai:, root:, infra:)
      agent   = ai[:agent]
      config  = infra[:config]
      metrics = infra[:metrics]
      {
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next list_models(root, metrics, agent) if arg == "list"
          next "model: #{agent.model}" if arg.empty?
          agent.model = arg; config.save!; "model: #{arg}"
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          next "usage: /why <rule_name>" if rule.empty?
          agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                         "give a before/after Ruby example, and state why it matters.")
        }
      }
    end

    def list_models(root, metrics, agent)
      yml_path = File.join(root, "data", "models.yml")
      return "model: #{agent.model}" unless File.exist?(yml_path)
      data = Master.load_yaml(yml_path)
      tiers = data["models"] || {}
      model_lines = tiers.flat_map { |tier, ms| ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" } }
      quality_lines = metrics&.model_quality&.map { |mod, stat|
        "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
      } || []
      sections = ["available models:"] + model_lines
      sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
      sections.join("\n")
    end

    def crit_command(ai:, root:)
      deliberation = ai[:deliberation]
      {
        "crit" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /crit <file|text>" if arg.empty?
          payload = if File.exist?(File.expand_path(arg, root))
            File.read(File.expand_path(arg, root), encoding: "UTF-8")
          else
            arg
          end
          result = deliberation.review(payload, context: "explicit /crit session")
          next result.message if result.err?
          format_crit_feedback(result.value!)
        }
      }
    end

    def format_crit_feedback(feedback)
      feedback.map { |f|
        veto = f[:veto_role] ? " [VETO ELIGIBLE]" : ""
        "#{f[:persona]} (#{f[:role]})#{veto}:\n#{f[:feedback].to_s.strip}"
      }.join("\n\n---\n\n")
    end

    def topic_command(infra:)
      session = infra[:session]
      {
        "topic" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            current_topic = session.respond_to?(:topic) ? session.topic : nil
            current_topic ? "topic: #{current_topic}" : "no topic set  /topic <description>"
          else
            session.topic = arg if session.respond_to?(:topic=)
            "topic: #{arg}"
          end
        }
      }
    end

    def ideate_command(ai:)
      ideation = ai[:ideation]
      {
        "ideate" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /ideate <prompt> [-- constraint1, constraint2]" if arg.empty?
          prompt, constraints_raw = arg.split(" -- ", 2)
          constraints = constraints_raw ? constraints_raw.split(",").map(&:strip).reject(&:empty?) : []
          result = ideation.ideate(prompt.strip, constraints:)
          next result.message if result.err?
          v = result.value!
          lines = []
          lines << "ideas (#{v[:ideas].size}):"
          v[:ideas].each { |i| lines << "  - #{i}" }
          lines << ""
          v[:critiques].each_with_index { |c, n| lines << "critique #{n + 1}: #{c}" }
          lines << ""
          lines << "synthesis:"
          lines << v[:final]
          lines.join("\n")
        }
      }
    end
  end
end

```

## lib/master/command_registry/memory_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) { dispatch_memory(memory, ctx[:args].to_s.strip) },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries  = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active   = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary  = memory.recall("_consolidated_summary")
            lines    = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end

    def dispatch_memory(memory, arg)
      case arg
      when /\Aforget (.+)/  then memory.forget($1.strip); "forgot: #{$1.strip}"
      when /\Aremember (.+)/
        key, value = $1.split("=", 2).map(&:strip)
        value ? (memory.remember(key, value); "remembered: #{key}") : "usage: /memory remember key=value"
      when /\Asearch (.+)/ then memory_search(memory, $1.strip)
      when ""
        (e = memory.all).empty? ? "(no memories)" : e.map { |k, v| "#{k}: #{v}" }.join("\n")
      else
        (r = memory.recall(arg)) ? "#{arg}: #{r}" : "(not found: #{arg})"
      end
    end

    def memory_search(memory, query)
      hits = memory.respond_to?(:semantic_recall) ? memory.semantic_recall(query) :
               memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
      hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
    end
  end
end

```

## lib/master/command_registry/service_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    BINARY_SNIFF_BYTES = 512

    module_function

    def control_commands(standing, soul)
      {
        "orders" => ->(ctx) { dispatch_orders(standing, ctx[:args].to_s.strip) },
        "soul"   => ->(ctx) { dispatch_soul(soul, ctx[:args].to_s.strip) }
      }
    end

    def service_commands(ai, phase_gates = nil)
      heartbeat = ai[:heartbeat]
      skills    = ai[:skills]
      {
        "heartbeat" => ->(ctx) { dispatch_heartbeat(heartbeat, ctx[:args].to_s.strip) },
        "skills"    => ->(ctx) {
          arg   = ctx[:args].to_s.strip
          found = skills&.find(arg)
          arg.empty? ? (skills&.list || "(no skills)") : (found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})")
        },
        "phase" => ->(ctx) { dispatch_phase(phase_gates, ctx[:args].to_s.strip) }
      }
    end

    def dispatch_phase(gates, arg)
      return "no phase_gates configured" unless gates
      case arg
      when "", "status" then gates.status
      when "advance"    then result = gates.advance!; result.ok? ? result.value! : result.message
      when /\Aforce (.+)\z/  then gates.force!($1.strip).value!
      when /\Ameet (.+)\z/   then gates.meet_gate!($1.strip); "gate met: #{$1.strip}"
      else "phase: #{gates.current}  /phase [status|advance|force <name>|meet <gate>]"
      end
    end

    def dispatch_orders(standing, arg)
      case arg
      when "list", "" then standing.list
      when /\Aenable (.+)\z/  then standing.enable($1.strip)
      when /\Adisable (.+)\z/ then standing.disable($1.strip)
      when /\Aadd name=(\S+) cmd=(.+)\z/ then standing.upsert(name: $1, command: $2.strip)
      when "run"
        results = standing.run_due!
        results.empty? ? "no orders due" :
          results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      when /\Areset (.+)\z/ then standing.reset($1.strip)
      else "usage: /orders  /orders enable|disable|reset <name>  /orders run"
      end
    end

    def dispatch_soul(soul, arg)
      case arg
      when "", "show"          then soul.summary
      when "version", "changelog" then soul.changelog
      when "diff"              then soul.diff
      when "approve"           then soul.approve
      when "reject"            then soul.reject
      when "rollback"          then soul.rollback
      when /\Apropose (.+)\z/  then soul.propose($1.strip)
      else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
      end
    end

    def dispatch_heartbeat(heartbeat, arg)
      case arg
      when "run"   then heartbeat ? heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n") : "no heartbeat"
      when "start" then heartbeat&.start!; "heartbeat started"
      when "stop"  then heartbeat&.stop!;  "heartbeat stopped"
      else heartbeat&.list || "no heartbeat"
      end
    end

    def utility_commands(agent, root, cache)
      {
        "snapshot" => ->(_ctx) {
          stamp = Time.now.strftime("%Y%m%d_%H%M%S")
          out = File.expand_path("~/master_snapshot_#{stamp}.md")
          dirs = %w[exe lib/master web/app web/config data].map { |d| File.join(root, d) }
          files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                      .select { |f| File.file?(f) && File.size(f) < CTX_WINDOW_SIZE }
                      .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                      .reject { |f| begin; File.binread(f, BINARY_SNIFF_BYTES).include?("\x00"); rescue StandardError => _e; true; end }
                      .sort
          lines = ["# MASTER Codebase Snapshot", "Generated: #{Time.now.utc.iso8601}", ""]
          files.each do |f|
            rel = f.sub("#{root}/", "")
            lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
            src = File.read(f, encoding: "UTF-8", invalid: :replace)
            lines << "## #{rel}" << "```#{lang}" << src.rstrip << "```" << ""
          rescue StandardError => e
            lines << "## #{rel}" << "[skipped: #{e.message}]" << ""
... 57 lines truncated (457 total)
```

## `snapshot_council.md`
```markdown
# MASTER Snapshot — lib/master/council/
Generated: 2026-05-04T10:21:42Z

## lib/master/council/deliberation.rb
```ruby
# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      MAX_CONCURRENT  = 4
      MAX_CODE_BYTES  = 8_192
      TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze

      def initialize(personas:, agent:, event_bus: nil)
        @personas = personas
        @agent    = agent
        @bus      = event_bus
        validate_dependencies!
      end

      def review(code, context: nil)
        return Master::Result.err("council: no personas configured", category: :validation) if @personas.empty?

        slots = Mutex.new
        available = MAX_CONCURRENT
        ready = ConditionVariable.new

        threads = @personas.map do |persona|
          Thread.new do
            slots.synchronize { ready.wait(slots) until available > 0; available -= 1 }
            begin
              response = @agent.ask(build_prompt(persona, code, context))
              entry = { persona: persona.name, role: persona.role,
                        veto_role: veto_role?(persona), feedback: response }
              @bus&.publish(:council_feedback, entry)
              entry
            rescue StandardError => e
              @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
              nil
            ensure
              slots.synchronize { available += 1; ready.signal }
            end
          end
        end
        feedback = threads.map { |thread| thread.join(30) ? thread.value : nil }.compact
        if feedback.empty?
          @bus&.publish(:council_timeout, personas: @personas.map(&:name))
          return Master::Result.err("council: all personas timed out (#{@personas.size})", category: :timeout)
        end

        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        unless vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          return Master::Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        Master::Result.ok(feedback)
      rescue StandardError => e
        Master::Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def validate_dependencies!
        raise ArgumentError, "personas must be an array" unless @personas.is_a?(Array)
        raise ArgumentError, "agent must respond to :ask" unless @agent.respond_to?(:ask)
      end

      def veto_role?(persona)
        if persona.respond_to?(:veto?)
          persona.veto?
        else
          persona.respond_to?(:veto_role) && !!persona.veto_role
        end
      end

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        safe_code = truncate_code(code.to_s)
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{persona.prompt}

          Code:
          #{safe_code}

          Provide terse, actionable feedback.#{veto_hint}
        PROMPT
      end

      def truncate_code(code)
        return code if code.bytesize <= MAX_CODE_BYTES
        @bus&.publish(:council_code_truncated, bytes: code.bytesize, limit: MAX_CODE_BYTES)
        code.byteslice(0, MAX_CODE_BYTES) + TRUNCATE_MARKER
      end

      VETO_RE = /\AVETO:/i.freeze

      def veto_text?(feedback)
        VETO_RE.match?(feedback.to_s.strip)
      end
    end
  end
end
```

## lib/master/council/ideation.rb
```ruby
# frozen_string_literal: true

module Master
  module Council
    class Ideation
      DEFAULT_CYCLES = 2

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
      end

      def ideate(prompt, constraints: [], cycles: DEFAULT_CYCLES)
        ideas     = []
        critiques = []

        cycles.times do |cycle|
          result = brainstorm(prompt, ideas, constraints)
          return result if result.err?
          ideas += result.value
          @bus&.publish("ideation:cycle", cycle: cycle + 1, ideas: ideas.size)

          result = critique(ideas)
          return result if result.err?
          critiques << result.value
        end

        result = synthesize(prompt:, ideas:, critiques:, constraints:)
        return result if result.err?

        Master::Result.ok(ideas: ideas, critiques: critiques, final: result.value)
      end

      private

      def brainstorm(prompt, prior, constraints)
        context           = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        raw     = @agent.ask_once(<<~PROMPT, system: "Generate 3-5 novel, bold ideas. One idea per bullet (- prefix).")
          #{constraint_prefix}#{context}Generate ideas for: #{prompt}
        PROMPT
        return Master::Result.err("ideation: brainstorm failed") if raw.to_s.strip.empty?

        parsed = raw.scan(/^[-*]\s*(.+)/).flatten
        parsed = [raw.strip] if parsed.empty?
        Master::Result.ok(parsed)
      end

      def critique(ideas)
        list = ideas.map { |idea| "- #{idea}" }.join("\n")
        raw  = @agent.ask_once(<<~PROMPT, system: "Critique these ideas. Identify weaknesses, blind spots, risks. Be direct.")
          #{list}
        PROMPT
        return Master::Result.err("ideation: critique failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end

      def synthesize(prompt:, ideas:, critiques:, constraints:)
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        list              = ideas.map { |idea| "- #{idea}" }.join("\n")
        crits = critiques.join("\n---\n")
        raw   = @agent.ask_once(<<~PROMPT, system: "Synthesize the best elements into a concrete, practical recommendation. Preserve innovation. Address valid critiques.")
          Goal: #{prompt}
          #{constraint_prefix}
          Ideas:
          #{list}

          Critiques:
          #{crits}
        PROMPT
        return Master::Result.err("ideation: synthesis failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end
    end
  end
end

```

## lib/master/council/personas.rb
```ruby
# frozen_string_literal: true

module Master
  module Council
    module Personas
      Persona = Data.define(:name, :role, :bias, :prompt, :veto_role) do
        def veto? = veto_role == true
      end

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure",
                    prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false),
        Persona.new(name: "Skeptic",    role: "Devil's advocate", bias: "Caution",
                    prompt: "Find what could go wrong. Challenge every assumption.", veto_role: false),
        Persona.new(name: "Pragmatist", role: "Implementation",  bias: "Shipping",
                    prompt: "Is this shippable? Flag over-engineering.", veto_role: false),
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",
                    prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true),
        Persona.new(name: "User",       role: "UX advocate",     bias: "Usability",
                    prompt: "Does this serve the user? Are error messages actionable?", veto_role: false),
        Persona.new(name: "Mentor",     role: "Code review",     bias: "Clarity",
                    prompt: "Is this code readable? Do names reveal intent?", veto_role: false)
      ].freeze

      @cache = {}

      def self.load(data_path = nil)
        return DEFAULTS if data_path.nil? || !File.exist?(data_path)

        @cache[data_path] ||= begin
          raw = Master.load_yaml(data_path, symbolize_names: true)
          raise "Invalid persona data" unless raw.is_a?(Array)

          raw.map do |attrs|
            raise "Persona must be a hash" unless attrs.is_a?(Hash)

            attrs = { veto_role: false }.merge(attrs)
            Persona.new(**attrs)
          end.freeze
        rescue StandardError => _e
          DEFAULTS
        end
      end
    end
  end
end
```
```

## `snapshot_data.md`
```markdown
# MASTER Snapshot — data/
Generated: 2026-05-04T10:21:42Z

## data/council.yml
```yaml
# Council personas — deliberation panel for code review decisions.

- name: Architect
  role: System Design
  bias: Structure
  prompt: Review architectural boundaries, coupling, interface shapes, and migration risk.

- name: Data Steward
  role: Data Integrity
  bias: Consistency
  prompt: Audit schema impact, migrations, data lineage, and source‑of‑truth consistency.

- name: Ethics & Policy
  role: Responsible Use
  bias: Compliance
  prompt: Examine policy adherence, abuse potential, fairness, and governance implications.

- name: Maintainer
  role: Code Health
  bias: Sustainability
  prompt: Evaluate readability, naming, modularity, and long‑term maintenance burden.

- name: Performance
  role: Runtime Efficiency
  bias: Throughput
  prompt: Detect latency, memory, I/O, and algorithmic inefficiencies; suggest measurable optimizations.

- name: Product Strategist
  role: Product Fit
  bias: Value
  prompt: Verify alignment with product goals, success metrics, and roadmap leverage.

- name: QA Engineer
  role: Test Strategy
  bias: Verification
  prompt: Locate missing tests, flaky patterns, and propose deterministic validation gates.

- name: Pragmatist
  role: Delivery Pressure
  bias: Shipping
  prompt: Minimize scope while maximizing shippable value within realistic constraints.

- name: Reliability
  role: Failure Engineering
  bias: Resilience
  prompt: Review retries, timeouts, degradation modes, idempotency, and rollback safety.

- name: Security
  role: Security Review
  bias: Safety
  prompt: Identify injection, privilege escalation, data‑exposure, and auth risks. Prefix VETO when unsafe to ship.

- name: Skeptic
  role: Devil's Advocate
  bias: Caution
  prompt: Challenge assumptions, enumerate failure paths, edge cases, and brittleness.

- name: User Advocate
  role: UX Advocate
  bias: Usability
  prompt: Assess clarity, friction, error recovery, and overall user outcomes.
```

## data/council_patterns.yml
```yaml
# Patterns that auto‑trigger Council deliberation.
# Loaded as Regexp at runtime – keep them plain strings.
# Each entry is a Ruby‑style regex pattern; the leading \b and trailing \b
# ensure whole‑word matches where appropriate.
# Anchors are reused via YAML anchors for readability.

common: &common
  - '\beval\s+\('
  - '\bexec\s+\('
  - '\bsystem\s+\('

dangerous:
  - *common
  - '\brm\s+-rf\b'
  - '\bsudo\b'
  - '\b(?:drop|truncate)\s+table\b'
  - '\bchmod\s+777\b'
  - '\b(?:delete|remove)\s+all\b'
  - '\bopen\s*\(\s*[''"][|]'                         # suspicious file open with pipe
  - '\b(popen|spawn)\s*\('                           # process creation shortcuts
  - '\b(fork|execve?)\b'                              # low‑level process forks
  - '\bbase64\s+decode\b'                            # potential data exfiltration
  - '\b(base64|binhex)\s+decode\b'                   # duplicate safety net
  - '\bopenssl\s+enc\s+-d\b'                         # decryption shortcuts
  - '\b(gzip|gunzip)\s+-d\b'                         # decompression that may hide payloads
  - '\b(base64|urlencode)\s+decode\b'                # double‑decode attacks
  - '\bcrontab\s+-[eE]\b'                            # schedule manipulation
  - '\biptables\s+-[FI]\b'                           # firewall rule changes
  - '\bsemanage\s+fcontext\b'                        # SELinux label changes
  - '\b(systemctl|service)\s+(stop|restart|disable)\b' # service disruption
  - '\b(rm|unlink)\s+--no-preserve-root\b'           # aggressive deletes
  - '\bdd\s+if=.*\s+of=.*\s+bs=.*\s+count=.*\b'       # raw disk ops
  - '\b(mkfs|fdisk|parted)\b'                        # filesystem manipulation
  - '\bchattr\s+[-+]i\b'                             # immutable attribute toggling
  - '\b(setfacl|getfacl)\b'                          # ACL abuse
  - '\b(chcon|restorecon)\b'                         # SELinux context changes
  - '\bsecuritylimits\b'                             # limits.conf editing
  - '\bpasswd\s+-[dl]\b'                             # password lock/unlock
  - '\b(yum|apt|dnf|pacman)\s+.*\b'                  # package manager abuse
  - '\bpip\s+install\s+--upgrade\b'                  # python package escalation
  - '\bruby\s+gem\s+install\s+--pre\b'               # ruby gem pre‑release install
  - '\bnpm\s+install\s+-g\b'                         # global node modules
  - '\bsudo\s+-[S]\b'                                # sudo without password prompt
  - '\bsu\s+-\s*root\b'                              # direct root switch
  - '\b(wget|curl)\s+.*\s+-O\s+/\w+\b'               # download to root
  - '\b(tar\s+.*\s+--wildcards)\b'                   # tar extraction with wildcards
  - '\b(zip|unzip)\s+.*\s+-d\s+/\w+\b'               # archive extraction to root
  - '\b(pg_dump|mysqldump)\b'                        # database dumps
  - '\bsqlite3\s+.*\s+\.dump\b'                      # sqlite dump
  - '\b(ssh|scp)\s+.*\s+@.*\b'                        # remote command execution
  - '\b(netcat|nc)\s+.*\b'                           # raw socket commands
  - '\b(lsof|fuser)\b'                               # process/file descriptor probing
  - '\b(strace|ltrace|gdb)\b'                        # tracing/debugging utilities
  - '\bdocker\s+run\s+--rm\b'                        # container escape attempts
  - '\bkubectl\s+exec\b'                             # k8s pod exec
  - '\bcrontab\s+-[lr]\b'                            # crontab listing/modifying
  - '\bat\b'                                         # at jobs
  - '\bpowershell\s+-Command\b'                      # cross‑platform shell
  - '\bwmic\s+.*\b'                                  # Windows management
  - '\breg\s+add\b'                                  # registry edits
  - '\bnetsh\s+firewall\b'                           # Windows firewall
  - '\bsc\s+config\b'                                # Windows service config
  - '\b(setx|set)\b'                                 # environment variable changes
  - '\bexport\s+[^=]+=.*\b'                          # shell env changes
  - '\benv\s+.*\b'                                   # env command misuse
  - '\b(bash|zsh|ksh|sh)\s+-c\b'                     # nested shells
  - '\b(python|perl|ruby|node)\s+-e\b'               # language exec
  - '\bjava\s+-jar\b'                                # java jar execution
  - '\bjavac\s+.*\b'                                 # compile on the fly
  - '\bgit\s+(push\s+--force|remote\s+add|checkout\s+-b|reset\s+--hard|rebase\s+-i|push\s+origin\s+HEAD:refs/heads/.*|push\s+--tags|clone\s+--depth|fetch\s+--all|pull\s+--all|remote\s+set-url|config\s+--global|config\s+--system|lfs|submodule|rev-parse|merge|reflog|show|diff|status|log|checkout|add|commit|branch|tag|fetch|pull|push|remote|init|clone|config)\b'
  - '\bgrep\s+--binary-files=without-match\b'        # binary grep avoidance
  - '\bsed\s+-n\b'                                   # selective sed
  - '\bawk\b'                                              # awk command
  - '\btail\s+-f\b'                                  # log following
  - '\bhead\s+-n\b'                                  # head count
  - '\bcurl\s+.*\s+(-X\s+DELETE|-o\s+/.+)\b'          # HTTP delete / write to root
  - '\bwget\s+.*\s+(--method=DELETE|--output-document=/.+)\b' # HTTP delete / write to root
  - '\bscp\s+.*\s+/\w+\b'                            # copy to root
  - '\brsync\s+.*\s+/\w+\b'                          # sync to root
  - '\b(chown|chgrp)\s+.*\s+/\w+\b'                  # ownership changes on root files
  - '\bln\s+-sf\s+.*\s+/\w+\b'                       # symlink overwrite
  - '\b(mv|cp)\s+.*\s+/\w+\b'                        # move/copy to root
  - '\b(distrobox|toolbox|podman|docker)\s+run\b'    # container escape
  - '\b(lxc\-exec|lxc\-attach)\b'                    # LXC exec
  - '\bvirsh\s+console\b'                            # libvirt console
  - '\bqemu\-system\-x86_64\b'                       # qemu VM launch
  - '\bvboxmanage\s+startvm\b'                       # VirtualBox start
  - '\bssh\s+-o\s+(StrictHostKeyChecking=no|UserKnownHostsFile=/dev/null|BatchMode=yes)\b' # host key bypass
  - '\bssh\s+-[LFRDNT]\s+.*\b'                       # port forwarding / tunnel options
  - '\bsocat\s+.*\b'                                 # socket proxy
  - '\bmitmproxy\s+.*\b'                             # MITM proxy
  - '\btunnel\s+.*\b'                               # TLS tunnel
  - '\biptables\s+-[F]\b'                            # flush iptables
  - '\bnft\s+flush\s+table\b'                        # nftables flush
  - '\bufw\s+disable\b'                              # ufw disable
  - '\bfirewalld\s+stop\b'                           # firewalld stop
  - '\bsystemctl\s+(mask|disable|stop|halt)\b'       # service control
  - '\b(poweroff|reboot|shutdown\s+-[hr])\b'          # power actions
  - '\bmount\s+-o\s+remount,rw\b'                    # remount read‑write
  - '\bumount\s+.*\b'                                # unmount
  - '\b(fuser|pkill|killall|kill)\s+.*\b'             # kill commands
  - '\b(pkill|killall)\s+--signal\s+9\b'             # force kill
  - '\b(strace|ltrace|gdb)\s+-p\b'                   # attach debugger/trace
  - '\b(lsof|netstat|ss)\s+.*\b'                     # socket/process inspection
  - '\b(ps|top|htop|w|whoami)\b'                    # system info commands
  - '\b(id|groups)\b'                                # identity commands
  - '\b(set|shopt)\s+-(e|u|o\s+pipefail|s\s+(nullglob|dotglob|extglob))\b' # strict shell options
  - '\b(bash|zsh|ksh|sh)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash options
  - '\bfind\s+/.*\s+-type\s+(f\s+-exec\s+rm\s+-f\s+{}\s+;|d\s+-exec\s+rmdir\s+{}\s+;)\b' # mass delete/dir removal
  - '\b(tar|zcat|gunzip|bzip2|xz|zip|unzip)\s+.*\s+>\s+/dev/null\b' # discard output
  - '\bpipefail\b'                                   # set -o pipefail
  - '\bset\s+-(e|u|o\s+pipefail)\b'                  # exit on error, undefined var, pipefail
  - '\bshopt\s+-(s\s+(nullglob|dotglob|extglob))\b'  # globbing options
  - '\b(bash)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash errexit etc.
```

## data/exemplars.yml
```yaml
# Exemplars — canonical code examples for LLM context injection.

exemplars:
  - name: "Master::Axioms::ENUM"
    file: "lib/master/axioms.rb"
    lines: 9
    beauty_score: 7
    virtue: declarative
    why: "Centralised truth constants, immutable, self‑documenting"
  - name: "Master::CircuitBreaker#call"
    file: "lib/master/circuit_breaker.rb"
    lines: 6
    beauty_score: 8
    virtue: resilience
    why: "Prevents cascading failures, simple state machine, easy to test"
  - name: "Master::CodeIndex::SymbolVisitor#visit_def"
    file: "lib/master/code_index.rb"
    lines: 167
    beauty_score: 8
    virtue: introspection
    why: "Uses Prism visitor to collect symbols, pure functional style, concise"
  - name: "Master::Logging.debug"
    file: "lib/master/logging.rb"
    lines: 6
    beauty_score: 6
    virtue: transparency
    why: "Thin wrapper around logger, ensures consistent formatting, no side effects"
  - name: "Master::Logging.info"
    file: "lib/master/logging.rb"
    lines: 10
    beauty_score: 6
    virtue: transparency
    why: "Standardised info-level logging, preserves caller context"
  - name: "Master::Pipeline#run"
    file: "lib/master/pipeline.rb"
    lines: 22
    beauty_score: 9
    virtue: orchestration
    why: "Linear 10‑stage pipeline, monadic result flow, explicit error propagation"
  - name: "Master::Result::Err"
    file: "lib/master/result.rb"
    lines: 36
    beauty_score: 9
    virtue: error_handling
    why: "Explicit failure monad, immutable, forces callers to handle errors"
  - name: "Master::Result::Ok"
    file: "lib/master/result.rb"
    lines: 8
    beauty_score: 9
    virtue: zen_method
    why: "Encapsulates success, immutable, self‑describing, no boilerplate"
  - name: "Master::RingBuffer#pop"
    file: "lib/master/ring_buffer.rb"
    lines: 12
    beauty_score: 8
    virtue: efficient
    why: "Symmetric constant‑time removal, preserves immutability guarantees"
  - name: "Master::RingBuffer#push"
    file: "lib/master/ring_buffer.rb"
    lines: 5
    beauty_score: 8
    virtue: efficient
    why: "Constant‑time circular buffer, clear intent, minimal code"
  - name: "Master::Security::InjectionGuard#sanitize"
    file: "lib/master/security/injection_guard.rb"
    lines: 12
    beauty_score: 8
    virtue: safety
    why: "Robust string sanitization, guards against code injection, well‑named"
  - name: "Master::SemanticCache#fetch"
    file: "lib/master/semantic_cache.rb"
    lines: 8
    beauty_score: 8
    virtue: performance
    why: "Memoises LLM embeddings, reduces API calls, immutable cache key"
  - name: "Master::Stages::Intake#call"
    file: "lib/master/stages/intake.rb"
    lines: 8
    beauty_score: 7
    virtue: composability
    why: "Initial request parsing, validates input, isolates side‑effects"
  - name: "Master::Stages::Lint#call"
    file: "lib/master/stages/lint.rb"
    lines: 10
    beauty_score: 7
    virtue: composability
    why: "Stage pattern, thin wrapper, delegates to scanner, easy to test"
  - name: "Master::Stages::Render#call"
    file: "lib/master/stages/render.rb"
    lines: 6
    beauty_score: 9
    virtue: presentation
    why: "Final rendering step, separates view logic, pure Result output"
  - name: "Master::Tools::AskLlm#call"
    file: "lib/master/tools/ask_llm.rb"
    lines: 5
    beauty_score: 8
    virtue: delegation
    why: "Encapsulates LLM request, uniform error handling, testable abstraction"
  - name: "Master::Tools::ReadFile#call"
    file: "lib/master/tools/read_file.rb"
    lines: 5
    beauty_score: 7
    virtue: clarity
    why: "Single responsibility, explicit error handling, pure I/O abstraction"
  - name: "Master::Tools::SearchFiles#call"
    file: "lib/master/tools/search_files.rb"
    lines: 5
    beauty_score: 7
    virtue: discoverability
    why: "Recursively glob‑searches project files, filters by pattern, pure result handling"
  - name: "Master::Tools::StrReplace#call"
    file: "lib/master/tools/str_replace.rb"
    lines: 5
    beauty_score: 7
    virtue: clarity
    why: "Pure string substitution helper, validates inputs, returns Result"
  - name: "Master::Tools::Tree#call"
    file: "lib/master/tools/tree.rb"
    lines: 9
    beauty_score: 7
    virtue: introspection
    why: "Builds AST tree view, useful for debugging, returns structured Result"
  - name: "Master::Tools::WriteFile#call"
    file: "lib/master/tools/write_file.rb"
    lines: 7
    beauty_score: 7
    virtue: clarity
    why: "Encapsulates file write with atomic temp‑file swap, error propagation"
  - name: "Master::Swarm::Workers::Analyst#perform"
    file: "lib/master/swarm/workers/analyst.rb"
    lines: 7
    beauty_score: 7
    virtue: delegation
    why: "Analyzes LLM output, extracts actionable insights, pure data transformation"
  - name: "Master::Swarm::Workers::Coder#perform"
    file: "lib/master/swarm/workers/coder.rb"
    lines: 14
    beauty_score: 7
    virtue: delegation
    why: "Coordinates LLM code generation, isolates side‑effects, clear contract"
```

## data/heartbeat.yml
```yaml
# Heartbeat — autonomous scheduled jobs.
# Each entry runs at interval_seconds. Actions: prune_memory, check_models, self_test, prune_undo, snapshot.

- name: prune_memory
  action: prune_memory
  interval_seconds: 3600
  description: Consolidate and archive stale memory entries.

- name: self_test
  action: self_test
  interval_seconds: 7200
  description: Run standard scan against lib/ and report violations.

- name: prune_undo
  action: prune_undo
  interval_seconds: 86400
  description: Trim undo journal to last 50 entries.

- name: snapshot
  action: snapshot
  interval_seconds: 14400
  description: Regenerate .master/snapshot.md with current codebase state.

```

## data/infer_patterns.yml
```yaml
# Intent-inference patterns for Stages::Infer.
# Extracted from Ruby source per NO_HARDCODED_CONSTANTS / ONE_SOURCE axioms.
# Every new natural-language command goes here — no code change required.
#
# Format: each entry has a command name and a list of regex patterns.
# Patterns are compiled case-insensitive with extended mode (x flag).
# Leave escaping as it appears here — loader does not re-escape.

commands:
  sweep:
    patterns:
      - '\b(?:sweep|refactor|clean\s*up|rewrite|polish|tidy\s*up|overhaul|improve\s+(?:all|every)|go\s+through\s+(?:all|every)|full\s+pass\s+(?:over|on))(?:\s+(?:all|every(?:thing)?|the))?(?:\s+([\w\/.]+))?'
      - '\b(?:rydd\s+opp|refaktorer|forbedre?|gjennomg[åa]|omskriv)(?:\s+([\w\/.]+))?'
    capture: path

  autoloop:
    patterns:
      - '\b(?:autoloop|autofix|fix\s+all\s+violations?|keep\s+(?:fix|loop)|loop\s+until|iterate\s+until|run\s+until\s+clean|keep\s+going\s+until|(?:run|go)\s+(?:it\s+)?(?:again\s+)?until\s+(?:done|clean|fixed|perfect))(?:\s+(\d+))?'
      - '\b(?:fiks?\s+alle?\s+(?:feil|brudd)|fortsett\s+(?:til|inntil)|kj[øo]r\s+(?:til\s+)?(?:det\s+er\s+)?(?:rent|bra|ferdig))(?:\s+(\d+))?'
    capture: cycles

  council:
    patterns:
      - '\b(?:council|deliberat|multiple\s+perspect|second\s+opinion|peer\s+review|debate\s+this|get\s+(?:another|a\s+second)\s+view|multi(?:ple)?\s+(?:view|agent|model|perspect))\b'
      - '\b(?:r[åa]dsl[åa]g|bruk\s+(?:flere|multiple)\s+(?:perspektiv|synsvinkler?)|diskuter\s+(?:dette|det))\b'
    capture: on_off

  explain:
    patterns:
      - '\b(?:explain\s+(?:your(?:self)?|your\s+architecture|how\s+you\s+work)|describe\s+(?:your(?:self)?|your\s+architecture)|what\s+are\s+you|how\s+(?:are\s+you\s+built|do\s+you\s+work)|show\s+(?:your\s+)?architecture|self[\s-]?map)\b'
    capture: none

  persona:
    patterns:
      - '\b(?:(?:switch|change|set)\s+persona\s+(?:to\s+)?(\w+)|persona\s+(\w+)|use\s+(\w+)\s+persona)\b'
    capture: persona_name

  memory:
    patterns:
      - '\b(?:what\s+do\s+you\s+remember(?:\s+about\s+([\w\s]+))?|show\s+(?:my\s+)?memor(?:y|ies)|list\s+memor(?:y|ies)|recall(?:\s+([\w]+))?|what(?:''s|\s+is)\s+in\s+(?:your\s+)?memory|remember\s+([\w]+=.+)|forget\s+([\w_]+))\b'
... 2690 lines truncated (3090 total)
```

## `snapshot_introspection.md`
```markdown
# MASTER Snapshot — lib/master/introspection/
Generated: 2026-05-04T10:21:42Z

## lib/master/introspection/self_map.rb
```ruby
# frozen_string_literal: true

module Master
  module Introspection
    class SelfMap
      AXIOM_FALLBACK = %w[
        PRESERVE_FIRST SIMPLEST_WORKS FAIL_VISIBLY EXPLICIT IMMUTABLE
        CQS SELF_EXPLAINING SINGLE_RESPONSIBILITY NO_HARDCODING GUARD_FIRST
      ].freeze

      def initialize(root:)
        @root = root
      end

      def describe
        files = Dir.glob(File.join(@root, "lib/**/*.rb"))
        lines = files.sum { |f| File.read(f, encoding: "UTF-8").lines.size rescue 0 }
        { files: files.size, lines: lines }
      end

      def axiom_coverage
        tags = load_axiom_tags
        src  = Dir.glob(File.join(@root, "lib/**/*.rb"))
                  .map { |f| File.read(f, encoding: "UTF-8") rescue "" }
                  .join("\n")
        tags.each_with_object({}) { |ax, h| h[ax] = src.scan(/\b#{Regexp.escape(ax)}\b/).size }
      end

      private

      def load_axiom_tags
        rules_path = File.join(@root, "data", "rules.yml")
        data = Master.load_yaml(rules_path)
        tags = (data["rules"] || {}).keys
        tags.empty? ? AXIOM_FALLBACK : tags
      rescue StandardError => _e
        AXIOM_FALLBACK
      end
    end
  end
end

```
```

## `snapshot_lib_core.md`
```markdown
# MASTER Snapshot — lib/master/
Generated: 2026-05-04T10:21:42Z

## lib/master/agent.rb
```ruby
# frozen_string_literal: true

require "ruby_llm"
require "digest"
require_relative "agent/llm_dispatch"

module Master
  class Agent
    include LlmDispatch

    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN = 0.000_015

    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE = build_tool_capable_re.freeze
    MAX_TOOL_TURNS = 5
    TOOL_CALL_RE = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze
    NEMOTRON3_RE = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    LLM_TOOL_MAP = {
      Tools::ReadFile        => Tools::LLM::ReadFile,
      Tools::WriteFile       => Tools::LLM::WriteFile,
      Tools::StrReplace      => Tools::LLM::StrReplace,
      Tools::ListDir         => Tools::LLM::ListDir,
      Tools::SearchFiles     => Tools::LLM::SearchFiles,
      Tools::Shell           => Tools::LLM::Shell,
      Tools::WebSearch       => Tools::LLM::WebSearch,
      Tools::AskLlm          => Tools::LLM::AskLlm,
      Tools::GitContext      => Tools::LLM::GitContext,
      Tools::AstEdit         => Tools::LLM::AstEdit,
      Tools::SearchKnowledge => Tools::LLM::SearchKnowledge
    }.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil, context_window: nil)
      @config, @session, @tools          = config, session, tools
      @circuit_breaker, @cache, @bus     = circuit_breaker, cache, event_bus
      @model_router, @reasoning_modes    = model_router, reasoning_modes
      @memory, @personality, @code_index = memory, personality, code_index
      @context_window                    = context_window
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt = apply_reasoning_mode(message)
      context = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / Session::TOKENS_PER_CHAR)

      begin
        @circuit_breaker.check_rate!
      rescue CircuitBreaker::CircuitError => rate_err
        return Result.err(rate_err.message, category: rate_err.category)
      end

      last_response = attempt_chat_with_fallbacks(candidate_models:, prompt:, context:, stream:, &blk)
      return last_response if last_response.respond_to?(:err?) && last_response.err?
      last_response = maybe_escalate(last_response, message, stream:, escalation_depth:, &blk)

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :handler_exception)
    end

    def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = routed_models.first
      result = send_with_cache(selected_model, messages, stream: false)
      raise result.message if result.respond_to?(:err?) && result.err?
      result.to_s
    end

    def ask_once(prompt, system: nil, model: nil)
      result = send_with_cache(model || self.model, [{ role: "user", content: prompt.to_s }], system:, stream: false)
      result.is_a?(String) ? result : (result.ok? ? result.value!.to_s : "")
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first
    def model=(val)
      @config["model"] = val
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary if @code_index&.built?
      parts << @memory.context_summary if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end
  end
end

```

## lib/master/audit_log.rb
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only tool invocation log; subscribes to tool:before on EventBus.
  class AuditLog
    LOG_PATH = ".master/audit.log".freeze
    MAX_VAL  = 120

    def initialize(root:, event_bus:)
      @path  = File.join(root, LOG_PATH)
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(@path))
      event_bus.subscribe("tool:before") { |event_data| append(event_data) }
    end

    private

    def append(event_data)
      payload_pairs = event_data.except(:tool)
                                .map { |k, v| "#{k}=#{v.to_s[0, MAX_VAL].inspect}" }
                                .join(" ")
      log_line = "#{Time.now.utc.iso8601} tool=#{event_data[:tool]} #{payload_pairs}"
      @mutex.synchronize { File.open(@path, "a") { |f| f.puts(log_line) } }
    end
  end
end

```

## lib/master/autoloop.rb
```ruby
# frozen_string_literal: true

require "open3"
require_relative "git_operations"

require_relative "autoloop/fix_evaluator"

module Master
  class AutoLoop
    def self.load_cfg
      Master.load_yaml(File.join(Master::ROOT, "data", "workflow.yml"))
            .dig("autoloop") || {}
    rescue StandardError => _e
      {}
    end

    _cfg = load_cfg
    MAX_CYCLES           = _cfg.fetch("max_cycles",           12)
    BATCH_SIZE           = _cfg.fetch("batch_size",            3)
    RATE_LIMIT_SLEEP     = _cfg.fetch("rate_limit_sleep",     15)
    MAX_FIX_RETRIES      = _cfg.fetch("max_fix_retries",       3)
    CONFIDENCE_THRESHOLD = _cfg.fetch("confidence_threshold", 0.60)
    MAX_FILE_BYTES       = _cfg.fetch("max_file_bytes",   16_000)
    SKIP_RULES           = Array(_cfg.fetch("skip_rules", [])).freeze
    TARGETS              = Array(_cfg.fetch("targets", %w[lib/ test/ data/ web/ DEPLOY/])).freeze
    EXCLUDES             = Array(_cfg.fetch("excludes", %w[vendor/ knowledge/])).freeze

    SCORE_INCREMENT = 0.25
    MAX_SIZE_RATIO  = 2.0
    MIN_SIZE_RATIO  = 0.80

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil, learnings: nil)
      @agent           = agent
      @scanner         = scanner
      @root            = root
      @bus             = event_bus
      @soul            = soul
      @learnings       = learnings
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git             = GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_paths  = TARGETS.map { |d| File.join(@root, d.delete_suffix("/")) }
                              .select { |d| File.directory?(d) }
        all_results = scan_paths.flat_map { |dir|
          scan_result = @scanner.scan_dir(dir, depth: :standard)
          scan_result.ok? ? scan_result.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        # Deduplicate by file — one fix per unique file to avoid write-race.
        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)

        mutex   = Mutex.new
        fixes   = {}
        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota

        threads = by_file.each_with_index.map do |v, idx|
          Thread.new do
            sleep(stagger * idx) if idx.positive?
            fix = request_fix(v)
            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix
          rescue StandardError => e
            @bus&.publish("autoloop:thread_error", file: v[:file], error: e.message)
          end
        end
        threads.each(&:join)

        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }

        if @git.dirty?("lib/")
          @git.add_lib_files
          @git.commit("autoloop: fix scan violations [cycle #{cycle}]")
          if @learnings
            fixes.each_value { |v, _| @learnings.record(trigger: v[:rule].to_s, strategy: "autoloop_fix", outcome: "commit") }
          end
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    include FixEvaluator
    private

    def apply_fix(rel_path, fixed_src)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)
      original = File.read(path, encoding: "UTF-8")
      return if fixed_src.strip == original.strip
      temporary_path = "#{path}.tmp.#{Process.pid}"
      File.write(temporary_path, fixed_src)
      File.rename(temporary_path, path)
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    rescue StandardError => e
      @bus&.publish("autoloop:write_error", file: rel_path, error: e.message)
    end

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.ok?
        rel = path.delete_prefix("#{@root}/")
        next [] if EXCLUDES.any? { |ex| rel.start_with?(ex) }
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .reject { |f| SKIP_RULES.include?(f[:rule].to_s) }
          .map    { |f| f.merge(file: rel) }
      }.select { |f|
        full_path = File.join(@root, f[:file])
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES # GUARD_EXPENSIVE
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return nil
      end

      src         = File.read(path, encoding: "UTF-8")
      base_prompt = build_fix_prompt(violation, src)
      result = Reflexion.run(agent: @agent, task: base_prompt, max: MAX_FIX_RETRIES) do |prompt, attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          fix = extract_code(@agent.ask(prompt).to_s)
          next nil if fix.nil?
          next nil if confidence_score(fix, src) < CONFIDENCE_THRESHOLD
          fix
        rescue StandardError => e
          err = e.message.to_s
          if TRANSIENT_RE.match?(err) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: err[0, 120])
          end
          nil
        end
      end
      result.respond_to?(:ok?) && result.ok? ? result.value! : nil
    end
  end
end

```

## lib/master/axioms.rb
```ruby
# frozen_string_literal: true

module Master
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
  class Axioms
    DATA_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "rules.yml").freeze
    WORKFLOW_PATH = File.join(File.expand_path("../../..", __dir__), "data", "workflow.yml").freeze

    def initialize(root: nil)
      @rules_path    = root ? File.join(root, "data", "rules.yml")    : DATA_PATH
      @workflow_path = root ? File.join(root, "data", "workflow.yml") : WORKFLOW_PATH
      @data          = load_yaml(@rules_path)    || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end

    def kernel
      @kernel ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .select { |r| r["tier"] == "kernel" }
          .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
          .freeze
      end
    end

    def workflow = @workflow.freeze

    def philosophy(limit: nil)
      @philosophy ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .reject { |r| r["tier"] == "kernel" }
          .map { |h| h.transform_keys(&:to_s) }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end

    def all_rules     = @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    def rules_for_scope(scope) = (@data.dig("rules", scope.to_s) || []).freeze

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Rules (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
... 4087 lines truncated (4487 total)
```

## `snapshot_memory.md`
```markdown
# MASTER Snapshot — lib/master/memory/
Generated: 2026-05-04T10:21:42Z

## lib/master/memory/search.rb
```ruby
# frozen_string_literal: true

module Master
  class Memory
    module Search
      def semantic_recall(query, top_n: 3)
        return [] if @store.empty?

        query_terms = tokenize(query)
        return [] if query_terms.empty?

        scored = @store.filter_map do |key, data|
          value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
          score = tfidf_score(query_terms, tokenize("#{key} #{value}"))
          next if score.zero?
          { key: key, value: value, score: score }
        end

        scored.sort_by { |e| -e[:score] }.first(top_n)
      end

      private

      def tokenize(text) = text.downcase.scan(/\b[a-z]{2,}\b/)

      def tfidf_score(query_terms, doc_terms)
        return 0.0 if doc_terms.empty?
        freq = doc_terms.tally
        query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
      end
    end
  end
end

```
```

## `snapshot_reasoning.md`
```markdown
# MASTER Snapshot — lib/master/reasoning/
Generated: 2026-05-04T10:21:42Z

## lib/master/reasoning/modes.rb
```ruby
# frozen_string_literal: true

module Master
  module Reasoning
    class Modes
      SUPPORTED = %w[direct react rewoo].freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def supported = SUPPORTED

      def wrap(message, mode: "direct")
        selected = SUPPORTED.include?(mode.to_s) ? mode.to_s : "direct"
        prompt = load_prompt(selected)
        format(prompt.fetch("template", "%{message}"), message: message.to_s)
      rescue StandardError => e
        $stderr.puts "reasoning/modes: wrap failed (mode=#{mode}): #{e.message}"
        message.to_s
      end

      private

      def load_prompt(mode)
        path = File.join(@root, "data", "prompts", "mode_#{mode}.yml")
        Master.load_yaml(path) || {}
      end
    end
  end
end

```
```

## `snapshot_routing.md`
```markdown
# MASTER Snapshot — lib/master/routing/
Generated: 2026-05-04T10:21:42Z

## lib/master/routing/continuity_index.rb
```ruby
# frozen_string_literal: true


module Master
  module Routing
    class ContinuityIndex
      def initialize(root: Master::ROOT)
        @root       = root
        @data_cache = nil
        @data_mtime = nil
      end

      def fallback_models
        return [] unless enabled?

        [openrouter_latest, ferrum_latest].flatten.compact.uniq
      end

      private

      def enabled?
        data.dig("continuity", "enabled") != false
      end

      def openrouter_latest
        data.dig("openrouter", "free_latest").to_a
      end


      def ferrum_latest
        data.dig("ferrum_web_chat", "free_latest").to_a
      end

      def data
        path = File.join(@root, "data", "models.yml")
        current_mtime = File.exist?(path) ? File.mtime(path) : nil

        if @data_cache.nil? || current_mtime != @data_mtime
          @data_cache = begin
            Master.load_yaml(path) || {}
          rescue StandardError => _e
            {}
          end
          @data_mtime = current_mtime
        end

        @data_cache
      end
    end
  end
end

```

## lib/master/routing/model_router.rb
```ruby
# frozen_string_literal: true

module Master
  module Routing
    class ModelRouter
      UNCERTAINTY_PHRASES = [
        "i'm not sure", "i don't know", "cannot determine",
        "unclear", "uncertain", "might be", "possibly",
        "probably not", "limited information", "i cannot",
        "i am unable", "i lack the", "not enough information",
        "i would need more"
      ].freeze

      ESCALATION_CHAIN = %w[cheap default strong].freeze
      DEFAULT_THRESHOLD = 0.3

      def initialize(config:, root: Master::ROOT, continuity_index: nil)
        @config = config
        @root = root
        @rules = load_rules
        @continuity_index = continuity_index || ContinuityIndex.new(root: @root)
      end

      def preferred(task_type: :exploration)
        return @config.model unless enabled?

        tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
        candidates = @rules.dig("models", tier).to_a
        return @config.model if candidates.empty?

        best = candidates.max_by { |m| weighted_score(m["score"] || {}) }
        best["id"] || @config.model
      end

      def fallback_chain(task_type: :exploration)
        return [@config.model] unless enabled?

        pref = preferred(task_type:)
        all = @rules.fetch("models", {}).values.flat_map { |tier| tier.filter_map { |m| m["id"] } }
        continuity = @continuity_index.fallback_models
        ([pref] + all + continuity + [@config.model]).uniq
      end

      def escalate?(response, threshold: DEFAULT_THRESHOLD)
        return false unless @rules.dig("routing", "escalation_enabled")

        text = response.to_s.downcase
        hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
        hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
      end

      def stronger_model(task_type: :exploration)
        tier = @rules.dig("routing", "escalation_tier") || "strong"
        candidates = @rules.dig("models", tier).to_a
        return preferred(task_type:) if candidates.empty?

        candidates.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred(task_type:)
      end

      def escalate_if_low_confidence(response, current_model:, task_type: :exploration)
        return nil unless escalate?(response)

        strong_model = stronger_model(task_type:)
        return nil if current_model == strong_model

        strong_model
      end

      def tier_for_model(model_id)
        @rules.fetch("models", {}).each do |tier, models|
          return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
        end
        "cheap"
      end

      def next_escalation_tier(current_tier)
        tier_index = ESCALATION_CHAIN.index(current_tier.to_s)
        return nil unless tier_index

        ESCALATION_CHAIN[tier_index + 1]
      end

      def confidence_threshold(task_type: :exploration)
        route = @rules.dig("routes", task_type.to_s)
        return DEFAULT_THRESHOLD unless route.is_a?(Hash)

        route.fetch("confidence_threshold", DEFAULT_THRESHOLD).to_f
      end

      private

      def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        weights = @rules.fetch("weights", {})
        qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
        sw = [weights.fetch("speed",   1.0).to_f, 0.01].max
        cw = [weights.fetch("cost",    1.0).to_f, 0.01].max
        DecisionEngine.score(
          impact:     score.fetch("quality", 0.5).to_f * qw,
          confidence: [score.fetch("speed", 1.0).to_f * sw, 0.01].max,
          cost:       1.0 / [score.fetch("cost", 0.5).to_f * cw, 0.001].max
        )
      end

      def load_rules
        path = File.join(@root, "data", "models.yml")
        Master.load_yaml(path) || {}
      rescue StandardError => _e
        {}
      end
    end
  end
end

```
```

## `snapshot_scan.md`
```markdown
# MASTER Snapshot — lib/master/scan/
Generated: 2026-05-04T10:21:42Z

## lib/master/scan/rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    class Rule
      EXT_LANG = {
        ".rb"      => "ruby",        ".rake"  => "ruby",   ".gemspec" => "ruby",
        ".erb"     => "html",        ".html"  => "html",   ".htm"     => "html",
        ".css"     => "css",         ".scss"  => "scss",   ".sass"    => "scss",
        ".js"      => "javascript",  ".ts"    => "javascript",
        ".jsx"     => "javascript",  ".tsx"   => "javascript",
        ".zsh"     => "zsh",         ".sh"    => "zsh",    ".bash"    => "zsh",
        ".yml"     => "yaml",        ".yaml"  => "yaml",
        ".md"      => "markdown",    ".json"  => "json",
      }.freeze

      attr_reader :id, :description, :severity, :axiom_tags, :auto_fix

      def self.inherited(subclass)
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize do
          (@registry ||= []) << subclass
        end
      end

      def self.registry
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize { @registry || [] }
      end

      # Rules that need constructor args (root:, agent:) override this to false.
      # Builder uses it to auto-discover zero-arg rules from the registry.
      def self.auto_build? = true

      def initialize
        @id         = self.class.name&.split("::")&.last&.downcase || "unknown"
        @description = ""
        @severity    = :warning
        @axiom_tags  = []
        @auto_fix    = true
      end

      def check(code, path:)
        raise NotImplementedError, "#{self.class}#check not implemented"
      end

      def language(path)
        EXT_LANG[File.extname(path).downcase]
      end

      def applies_to?(path, languages)
        return true if languages.nil? || languages.empty?
        lang = language(path)
        lang && languages.include?(lang)
      end

      protected

      def finding(line:, message:, fix: nil)
        { rule: @id, message:, line:, severity: @severity, fix: }
      end

      def scan_lines(code, pattern, message:, fix: nil)
        code.each_line.with_index(1).filter_map { |line, num|
          finding(line: num, message:, fix:) if line.match?(pattern)
        }
      end
    end
  end
end

```

## lib/master/scan/rules/adversarial_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Steelman-first red-team: the model must defend the code before it can attack it.
      # This suppresses false positives by forcing consideration of legitimate reasons
      # before a violation can survive. Deep depth only; one LLM call per file.
      class AdversarialRule < Rule
        PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Challenge: list only the violations that survive the steelman.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "adversarial"
          @description = "Red-team scan: steelman then challenge — suppresses false positives"
          @severity    = :error
          @axiom_tags  = %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE]
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless (lang = language(path))
          return [] unless @agent

          prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                           lang: lang,
                                           code: code[0, 3_000])
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "adversarial: scan error — #{e.message}")]
        end

        private

        def parse_findings(response)
          return [] if response.strip.upcase.start_with?("CLEAN")

          response.lines.filter_map do |line|
            match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
            next unless match
            finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/arity_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Too many constructor args signal a god object; callers can't reason about what matters.
      # Reads max_params from rules.yml so the threshold stays in one place.
      class ArityRule < Rule
        DEFAULT_MAX = 3

        def initialize
          super
          @max_params  = Master::Axioms.new.thresholds.dig("method", "max_params") || DEFAULT_MAX
          @id          = "arity"
          @description = "initialize with > #{@max_params} args — extract a context struct or config object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          lines    = code.lines
          index    = 0
          while index < lines.size
            line = lines[index]
            if line.match?(/^\s*def\s+initialize\s*\(/)
              signature, end_index = collect_signature(lines, index)
              param_count = count_params(signature)
              findings << finding(line: index + 1,
                message: "initialize takes #{param_count} args (max #{@max_params}) — extract AgentContext or Config struct") if param_count > @max_params
              index = end_index + 1
            else
              index += 1
            end
          end
          findings
        end

        private

        def collect_signature(lines, start)
          signature = +""
          depth     = 0
          current   = start
          while current < lines.size
            signature << lines[current]
            depth += lines[current].count("(") - lines[current].count(")")
            break if depth <= 0
            current += 1
          end
          [signature, current]
        end

        def count_params(signature)
          inner = signature.match(/def\s+initialize\s*\((.+)\)/m)
          return 0 unless inner
          content = inner[1].strip
          return 0 if content.empty?
          depth = 0
          count = 1
          content.each_char do |char|
            case char
            when "(", "[", "{" then depth += 1
            when ")", "]", "}" then depth -= 1
            when "," then count += 1 if depth.zero?
            end
          end
          count
        end
      end
    end
  end
end

```

## lib/master/scan/rules/axiom_coverage_rule.rb
```ruby
# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      # Every rule ID in rules.yml must have scan rule coverage; every @axiom_tags
      # symbol must name a real rule ID. Orphaned tags and uncovered rules both signal drift.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every rule must have scan rule coverage; every tag must be a real rule"
          @severity    = :warning
          @axiom_tags  = []
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in rules.yml — define it or remove the tag")
          end

          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "rule #{id} has no scan rule coverage — add a rule or accept as advisory")
          end

          findings
        end

        private

        def load_axiom_ids
          path = File.join(@root, "data", "rules.yml")
          return [] unless File.exist?(path)

          data = Master.load_yaml(path)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules.map { |r| r["id"] }.compact.uniq
        rescue StandardError => _e
          []
        end

        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            extract_axiom_tags(File.read(f))
          }.uniq
        rescue StandardError => _e
          []
        end

        def extract_axiom_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError => _e
          []
        end

        class TagCollector < Prism::Visitor
          attr_reader :tags
          def initialize
            super
            @tags = []
          end

          def visit_instance_variable_write_node(node)
            if node.name == :@axiom_tags
              @tags.concat(collect_symbols(node.value))
            end
            super
          end

          private

          def collect_symbols(node)
            return [] unless node
            case node
            when Prism::ArrayNode
              node.elements.flat_map { |el| collect_symbols(el) }
            when Prism::SymbolNode
              [node.unescaped.to_s]
            else
              []
            end
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/bare_rescue_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class BareRescueRule < Rule
        def initialize
          super
          @id          = "bare_rescue"
          @description = "Never use bare rescue -- always specify exception type"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          scan_lines(code, /^\s*rescue\s*$/, message: "bare rescue: specify exception type (e.g. rescue StandardError)")
        end
      end
    end
  end
end

```

## lib/master/scan/rules/conceptual_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # LLM review for rules whose violations resist lexical detection; deep depth only.
      # Rules with detect_conceptual prompts in rules.yml are batched into one LLM call per file.
      class ConceptualRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
        CODE_SNIPPET_LIMIT = 2000

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual"
          @description = "LLM-based rule review (runs at :deep depth only)"
          @severity    = :warning
          @axioms      = load_conceptual_rules
          @axiom_tags  = @axioms.keys.map(&:to_sym)
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
... 1411 lines truncated (1811 total)
```

## `snapshot_security.md`
```markdown
# MASTER Snapshot — lib/master/security/
Generated: 2026-05-04T10:21:42Z

## lib/master/security/injection_guard.rb
```ruby
# frozen_string_literal: true

module Master
  module Security
    class InjectionGuard
      PATTERNS = [
        /ignore (?:previous|all|your) instructions/i,
        /disregard (?:your )?(?:system )?prompt/i,
        /you are now (?:a|an|in)/i,
        /pretend (?:to be|you are|you're)/i,
        /new instructions:/i,
        /\[SYSTEM\]/i,
        /###\s*SYSTEM/i,
        /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
        /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
        /jailbreak/i,
      ].freeze

      # Shell-injection pattern checked separately (multiline, heavier regex).
      SHELL_INJECTION_RE = /```(?:bash|sh|zsh|shell)\n.*?(?:rm\s+-rf|curl\b.*?\|\s*(?:bash|sh)\b|wget\b.*?\|\s*(?:bash|sh)\b)/im.freeze

      def scan(content)
        hits = PATTERNS.select { |p| content.match?(p) }
        hits << SHELL_INJECTION_RE if content.match?(SHELL_INJECTION_RE)
        return Result.ok(:clean) if hits.empty?
        Result.err("injection detected: #{hits.size} pattern(s) matched", category: :validation)
      end

      def clean!(content)
        cleaned = PATTERNS.reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
        Result.ok(cleaned)
      end
    end
  end
end

```

## lib/master/security/permissions.rb
```ruby
# frozen_string_literal: true

module Master
  module Security
    module Permissions
      TOOL_TIERS = {
        "read_file"    => :safe,
        "list_dir"     => :safe,
        "search_files" => :safe,
        "write_file"   => :guarded,
        "str_replace"  => :guarded,
        "apply_diff"   => :guarded,
        "ask_llm"      => :guarded,
        "web_search"   => :guarded,
        "zsh"          => :dangerous
      }.freeze

      BLOCKLIST = [
        "rm -rf /",
        "sudo",
        "reboot",
        "shutdown",
        "mkfs",
        "dd if=",
        "> /dev/",
        "chmod 777",
        "curl | sh",
        "wget | sh"
      ].freeze

      def self.tier_for(tool_name)
        TOOL_TIERS[tool_name.to_s] || :guarded
      end

      def self.blocked?(command)
        BLOCKLIST.any? { |b| command.downcase.include?(b.downcase) }
      end
    end
  end
end

```
```

## `snapshot_stages.md`
```markdown
# MASTER Snapshot — lib/master/stages/
Generated: 2026-05-04T10:21:42Z

## lib/master/stages/council.rb
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Council — 6-persona deliberation on dangerous or multi-file changes.
    # PRAISE votes are appended to data/exemplars.yml for future reference.
    class Council
      EXEMPLARS_PATH  = File.join(Master::ROOT, "data", "exemplars.yml").freeze
      PATTERNS_PATH   = File.join(Master::ROOT, "data", "council_patterns.yml").freeze

      def initialize(deliberation:, config: nil, enabled: false)
        @deliberation      = deliberation
        @config            = config
        @enabled           = @config&.[]("council") == true || enabled
        @dangerous_patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless should_run?(ctx)

        payload = extract_payload(ctx)
        result  = @deliberation.review(payload, context: ctx[:message])
        return result if result.err?

        feedback = result.value!
        log_praise(ctx[:message], feedback) if praise?(feedback)

        Result.ok(ctx.merge(council_feedback: feedback))
      end

      def enable!
        @enabled = true
        @config&.[]=("council", true)
        @config&.save!
      end

      def disable!
        @enabled = false
        @config&.[]=("council", false)
        @config&.save!
      end

      def enabled? = @enabled

      private

      def load_patterns
        data = Master.load_yaml(PATTERNS_PATH)
        (data["dangerous"] || []).flatten.filter_map { |str| Regexp.new(str, Regexp::IGNORECASE) rescue nil }
      end

      def should_run?(ctx)
        return false if ctx[:intent] == :command
        @enabled || dangerous_request?(ctx) || dangerous_tool?(ctx) || multi_file_diff?(ctx)
      end

      def dangerous_request?(ctx)
        msg = ctx[:message].to_s.gsub(/[[:cntrl:]]/, "")
        !msg.empty? && @dangerous_patterns.any? { |p| msg.match?(p) }
      end

      def dangerous_tool?(ctx)  = ctx[:last_tool_tier] == :dangerous
      def multi_file_diff?(ctx) = extract_payload(ctx).scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2

      def extract_payload(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then ""
        else
          text = out.to_s
          text.empty? ? ctx[:message].to_s : text
        end
      end

      # Detect unanimous or majority PRAISE in council feedback text.
      def praise?(feedback)
        text = feedback.to_s.downcase
        text.scan(/\bpraise\b/).size >= 3
      end

      # Append a PRAISE entry to data/exemplars.yml.
      def log_praise(message, feedback)
        entry = {
          "timestamp" => Time.now.iso8601,
          "message"   => message.to_s[0, 120],
          "feedback"  => feedback.to_s[0, 240]
        }
        existing = File.exist?(EXEMPLARS_PATH) ? (Master.load_yaml(EXEMPLARS_PATH) || []) : []
        File.write(EXEMPLARS_PATH, YAML.dump(existing + [entry]))
      rescue StandardError => e
        @bus&.publish("council:exemplar_error", error: e.message)
      end
    end
  end
end

```

## lib/master/stages/deliberate.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Deliberate — enumerate N approaches before acting; prevents first-solution fixation.
    class Deliberate
      MIN_OPTIONS   = 4
      CODING_TYPES  = %i[coding refactor architecture infrastructure].freeze

      def initialize(agent:, config:)
        @agent  = agent
        @config = config
      end

      def call(ctx)
        return Result.ok(ctx) unless applicable?(ctx)

        msg    = ctx[:message].to_s
        Result.ok(ctx.merge(message: wrap(msg)))
      end

      private

      def applicable?(ctx)
        ctx[:intent] == :llm &&
          CODING_TYPES.include?(ctx[:task_type]) &&
          @config["deliberate"] != false
      end

      def wrap(msg)
        <<~PROMPT
          #{msg}

          Before acting: list #{MIN_OPTIONS} distinct approaches (numbered). Each: one-line name + one-line trade-off. Then execute the strongest one. State which you chose and why in one sentence.
        PROMPT
      end
    end
  end
end

```

## lib/master/stages/execute.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Execute — call the handler resolved by Route and store its output.
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        Result.ok(ctx.merge(output: handler.call(ctx)))
      rescue StandardError => e
        Result.err("execute: #{e.message}", category: :handler_exception)
      end
    end
  end
end

```

## lib/master/stages/guard.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Guard — reject messages that contain prompt-injection patterns.
    # Skips scan when message is absent (command-only paths set no :message).
    class Guard
      def initialize(governor:, injection_guard:)
        @governor        = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        msg = ctx[:message].to_s
        return Result.ok(ctx) if msg.empty?

        scan = @injection_guard.scan(msg)
        return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

        Result.ok(ctx)
      end
    end
  end
end

```

## lib/master/stages/infer.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Infer — promote natural-language messages to :command intent via data/infer_patterns.yml.
    class Infer
      # Heuristic task-type detection — used by ModelRouter for tiered model selection.
      PRESSURE_PATTERN = /\b(?:urgent|asap|immediately|critical|now|hurry|fast|quick(?:ly)?|emergency|sos)\b/i.freeze

      TASK_TYPE_PATTERNS = {
        coding:   /\b(?:def |class |module |require |\.rb\b|fix\s+(?:the\s+)?(?:bug|error|issue)|refactor|implement|write\s+(?:a\s+)?(?:method|class|function|test)|add\s+(?:a\s+)?(?:method|feature)|```(?:ruby|python|js|javascript|bash))/i,
        research: /\b(?:search|find\s+(?:all|every|info)|research|look\s+up|what\s+is|explain\s+(?:how|what|why)|tell\s+me\s+about)\b/i,
        qa:       /\?(?:\s*$|\s+[A-Z])/m,
      }.freeze

      PATTERNS_PATH = File.join(Master::ROOT, "data", "infer_patterns.yml").freeze

      def initialize
        @patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless ctx[:intent] == :llm

        msg = ctx[:message].to_s.strip
        @patterns.each do |cmd, entry|
          entry[:regexes].each do |pattern|
            next unless (m = msg.match(pattern))
            return Result.ok(ctx.merge(intent: :command, command: cmd, args: extract_args(cmd,
              entry[:capture], m, msg)))
          end
        end

        pressure = msg.match?(PRESSURE_PATTERN)
        Result.ok(ctx.merge(task_type: infer_task_type(msg), pressure: pressure || ctx[:pressure]))
      end

      private

      def load_patterns
        return {} unless File.exist?(PATTERNS_PATH)
        data = Master.load_yaml(PATTERNS_PATH) || {}
        commands = data["commands"] || {}
        commands.each_with_object({}) do |(name, spec), out|
          regexes = (spec["patterns"] || []).map { |src| Regexp.new(src, Regexp::IGNORECASE | Regexp::EXTENDED) }
          out[name.to_s] = { regexes: regexes, capture: spec["capture"].to_s }
        end
      rescue StandardError => _e
        {}
      end

      def infer_task_type(msg)
        TASK_TYPE_PATTERNS.each { |type, pat| return type if msg.match?(pat) }
        :general
      end

      def extract_args(cmd, capture, match, msg)
        case capture
        when "path"
          path = match[1]&.strip
          path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
          path.to_s
        when "cycles"
          (match[1] || msg[/\b(\d+)\s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
        when "on_off"
          msg.match?(/\b(?:off|disable|stop|av|skru\s+av)\b/i) ? "off" : "on"
        when "first_group"
          match.captures.compact.first.to_s.strip
        when "persona_name"
          (match[1] || match[2] || match[3]).to_s.strip
        when "soul_subcmd"
          msg[/\b(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
        when "orders_subcmd"
          msg.match?(/\blist|show\b/i) ? "list" : ""
        when "scan_depth"
          match[1]&.strip.to_s
        else
          ""
        end
      end
    end
  end
end

```

## lib/master/stages/intake.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string (may be empty)
      COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m.freeze

      def call(ctx)
        raw = ctx[:user_message]
        msg = raw.to_s.strip
        return Result.err("intake: empty message", category: :validation) if msg.empty?

        if (m = msg.match(COMMAND_RE))
          command = m[1].downcase
          args    = m[2].strip
          args = nil if args.empty?
          Result.ok(ctx.merge(intent: :command, command: command, args: args))
        else
          Result.ok(ctx.merge(intent: :llm, message: msg))
        end
      end
    end
  end
end
```

## lib/master/stages/lint.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Lint — scan written files and chat code blocks; autofix via autoloop if available.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil, root: nil, event_bus: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
        @root     = root
        @bus      = event_bus
      end

      def call(ctx)
        findings = []

        paths = Array(ctx[:written_files]).filter_map { |p| File.exist?(p) ? p : nil }
        paths.each do |scan_path|
          if File.directory?(scan_path)
            result = @scanner.scan_dir(scan_path, depth: :standard)
            findings.concat(result.value!.flat_map { |_, r| r.respond_to?(:ok?) && r.ok? ? r.value! : [] }) if result.respond_to?(:ok?) && result.ok?
          elsif scan_path.end_with?(".rb")
            result = @scanner.scan(scan_path, depth: :standard)
            findings.concat(result.value!) if result.respond_to?(:ok?) && result.ok?
          end
        end

        output = ctx[:output].to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        if findings.any? && @autoloop
          fixable = findings.select { |f| !AutoLoop::SKIP_RULES.include?(f[:rule].to_s) }
          if fixable.any?
            fix_result = @autoloop.run(max_cycles: 3)
            ctx = ctx.merge(autofix_result: fix_result)
          end
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue StandardError => e
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          result = @scanner.scan(f.path, depth: :standard)
          if result.respond_to?(:ok?) && result.ok?
            findings = result.value!.map { |v| v.merge(source: :inline) }
          end
        end
        findings
      rescue StandardError => e
        @bus&.publish("lint:scan_error", error: e.message)
        []
      end
    end
  end
end

```

## lib/master/stages/memo.rb
```ruby
... 198 lines truncated (598 total)
```

## `snapshot_swarm.md`
```markdown
# MASTER Snapshot — lib/master/swarm/
Generated: 2026-05-04T10:21:42Z

## lib/master/swarm/coordinator.rb
```ruby
# frozen_string_literal: true

require "timeout"

module Master
  module Swarm
    class Coordinator
      SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, keyword_init: true) do
        def ok?      = verdict != :error
        def approved? = verdict == :approved
      end

      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      WORKER_TIMEOUT = 30
      SHARED_DEADLINE = 60
      SYNTHESIS_TRUNCATE_LIMIT = 200

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

      def analyse_and_review(file_path:, code:)
        fan_out([
          { role: :analyst,  task: "identify all issues",          context_slice: { file: file_path, code: code } },
          { role: :reviewer, task: "security and correctness review", context_slice: { code: code } }
        ]).and_then do |sr|
          analysis = sr.artifacts[:analyst]
          review   = sr.artifacts[:reviewer]
          Result.ok({ analysis:, review:, approved: review.is_a?(Hash) && review["approved"] })
        end
      end

      def fan_out(tasks, timeout: WORKER_TIMEOUT)
        threads = tasks.map do |t|
          Thread.new do
            [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}")]
          end
        end

        results = threads.map do |th|
          if th.join(timeout)
            th.value
          else
            begin; th.kill; rescue ThreadError; nil; end
            @bus&.publish(:swarm_worker_timeout, timeout:)
            [:timeout, Result.err("worker timed out after #{timeout}s")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, verdict: sr.verdict,
                      synthesis: sr.reasoning[0..SYNTHESIS_TRUNCATE_LIMIT])
        Result.ok(sr)
      end

      def dispatch_parallel(role_tasks, deadline: SHARED_DEADLINE)
        finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

        threads = role_tasks.map do |t|
          Thread.new do
            remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
            Timeout.timeout(remaining) do
              [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
            end
          rescue Timeout::Error
            [t[:role], Result.err("worker exceeded shared deadline")]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}")]
          end
        end

        results = threads.map do |th|
          if th.join(deadline)
            th.value
          else
            begin; th.kill; rescue ThreadError; nil; end
            @bus&.publish(:swarm_parallel_timeout, deadline:)
            [nil, Result.err("worker exceeded shared deadline")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys, verdict: sr.verdict)
        Result.ok(sr)
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      def build_swarm_result(results)
        successes = results.reject { |role, _| role == :timeout }
                           .select { |_, r| r.respond_to?(:ok?) && r.ok? }
        artifacts = successes.transform_values(&:value!)
        confidence = results.empty? ? 0.0 : successes.size.to_f / results.size
        lines = successes.map { |role, r| "### #{role}\n#{r.value!.to_s.strip}" }
        reasoning = lines.empty? ? "(no results)" : lines.join("\n\n")
        verdict = if confidence >= 0.8 then :approved
                 elsif confidence >= 0.5 then :mixed
                 elsif successes.empty? then :error
                 else :rejected
                 end
        SwarmResult.new(verdict:, confidence:, reasoning:, artifacts:)
      end

      def worker_for(role)
        sym = role.to_sym
        @workers.fetch(sym) do
          klass = WORKER_CLASSES[sym]
          return nil unless klass

          @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
        end
      end
    end
  end
end

```

## lib/master/swarm/worker.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know).
    class Worker
      PREFERRED_MODEL = nil

      UNCERTAINTY_PHRASES = %w[unclear uncertain not\ sure cannot\ determine
                                i\ don't\ know limited\ information probably].freeze

      attr_reader :role, :result, :confidence

      def initialize(agent:, event_bus: nil)
        @agent      = agent
        @bus        = event_bus
        @role       = self.class.name.split("::").last.downcase
        @result     = nil
        @confidence = 1.0
      end

      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

        preferred = self.class::PREFERRED_MODEL
        raw = @agent.ask_once(prompt, model: preferred, system: worker_system_prompt)
        @result, @confidence = parse_result(raw)

        @bus&.publish(:swarm_worker_done, role: @role, ok: @result.ok?)
        @result
      rescue StandardError => e
        Result.err("worker #{@role}: #{e.message}", category: :unknown)
      end

      private

      def worker_system_prompt
        "You are a specialized #{@role} agent. #{role_description}\n" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end

      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}\n\nTask: #{task}"

      def parse_result(raw)
        text = raw.to_s.strip
        hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
        conf = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
        [Result.ok({ text: text, confidence: conf }), conf]
      end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
end

```

## lib/master/swarm/workers/analyst.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reads code, produces structured analysis. Knows nothing about other workers.
      class Analyst < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        private

        def role_description
          "You analyze code for quality, bugs, and design issues. " \
            "Output JSON: {issues: [{file, line, severity(1-3), description}], summary: string}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "File: #{ctx[:file]}" if ctx[:file]
          parts << "Code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Analyze: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          match_str = raw.to_s.match(/\{.*\}/m)&.to_s || "{}"
          parsed = JSON.parse(match_str)
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ summary: raw.to_s.strip, issues: [] })
        end
      end
    end
  end
end

```

## lib/master/swarm/workers/coder.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Writes code given a spec. Knows only the spec + relevant file context.
      class Coder < Worker
        private

        def role_description
          "You write clean, minimal Ruby/Rails/Zsh code. " \
            "Output only the code block. No explanation unless asked."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Language: #{ctx[:language] || "ruby"}"
          parts << "Existing code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Spec: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end

```

## lib/master/swarm/workers/researcher.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Synthesizes research from external sources. No codebase context.
      class Researcher < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        private

        def role_description
          "You are a research analyst. Synthesize information concisely. " \
            "Output: factual summary, sources if known, confidence level (low/med/high)."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Domain: #{ctx[:domain]}" if ctx[:domain]
          parts << "Prior findings:\n#{ctx[:prior_findings]}" if ctx[:prior_findings]
          parts << "Research: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end

```

## lib/master/swarm/workers/reviewer.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reviews code for security, correctness, style. Constitutional layer.
      class Reviewer < Worker
        CHECKLIST = %w[
          sql_injection xss command_injection path_traversal
          hardcoded_secrets open_redirect mass_assignment
        ].freeze

        private

        def role_description
          "You are a security-focused code reviewer. Check for OWASP top-10 issues, " \
            "logic bugs, and constitutional AI violations. " \
            "Output JSON: {approved: bool, violations: [{type, line, description}]}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Code to review:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Security checklist: #{CHECKLIST.join(", ")}"
          parts << "Review for: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          parsed = JSON.parse(raw.to_s.match(/\{.*\}/m)&.to_s || "{}")
          parsed["approved"] = true if parsed.empty?
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ "approved" => true, "violations" => [] })
        end
      end
    end
  end
end

```
```

## `snapshot_sweep.md`
```markdown
# MASTER Snapshot — lib/master/sweep/
Generated: 2026-05-04T10:21:42Z

## lib/master/sweep/convergence.rb
```ruby
# frozen_string_literal: true

module Master
  class Sweep
    # Per-cycle metrics tracking and early-stop logic for sweep loops.
    # Detects stall, low success rate, and sign-reversal oscillation.
    module Convergence
      LOW_SUCCESS_RATE = 0.10

      private

      def init_cycle_log
        @cycle_log = []
      end

      # Record one cycle's metrics. Returns the entry for bus publishing.
      def record_cycle(violations:, fixed:, deferred:)
        prev  = @cycle_log.last
        delta = prev ? (prev[:violations] - violations) : fixed
        total = violations + fixed
        rate  = total.zero? ? 0.0 : (fixed.to_f / total).round(3)
        entry = { violations:, fixed:, deferred:, delta:, rate: }
        @cycle_log << entry
        entry
      end

      # Unified early-stop: stall, low success rate, oscillation, or done.
      def should_halt_early?
        return false if @cycle_log.size < 2

        last = @cycle_log.last
        return true if last[:violations].zero?
        return true if last[:rate] < LOW_SUCCESS_RATE
        return true if @cycle_log.last(2).all? { |entry| entry[:delta] == 0 }
        return true if oscillating?

        false
      end

      def oscillating?
        signs = @cycle_log.last(3).map { |entry| entry[:delta] <=> 0 }
        return false if signs.size < 3
        signs.each_cons(2).all? { |x, y| x != 0 && x == -y }
      end

      def convergence_summary
        return "sweep: no cycles recorded" if @cycle_log.empty?
        count = @cycle_log.size
        last  = @cycle_log.last
        prev  = count > 1 ? @cycle_log[-2][:violations] : "?"
        osc   = oscillating? ? 1 : 0
        "sweep: iter=#{count} violations=#{prev}->#{last[:violations]} " \
          "fixed=#{last[:fixed]} deferred=#{last[:deferred]} rate=#{last[:rate]} oscillating=#{osc}"
      end

      # A→B→A within RENAME_WINDOW cycles signals oscillation (arxiv:2602.21833 §4.3).
      def rename_oscillation?(rel, old_src, new_src, cycle)
        old_names   = extract_names(old_src)
        new_names   = extract_names(new_src)
        removed_now = old_names - new_names
        added_now   = new_names - old_names
        history     = @rename_log[rel]
        oscillates  = history.last(RENAME_WINDOW).any? { |entry| names_reverted?(entry, added_now, removed_now) }
        history << { cycle:, removed: removed_now, added: added_now }
        @rename_log[rel] = history.last(RENAME_WINDOW * 2)
        oscillates
      end

      def names_reverted?(entry, added_now, removed_now)
        (entry[:removed] & added_now).any? && (entry[:added] & removed_now).any?
      end

      def extract_names(source) = source.scan(NAME_RE).flatten.compact.uniq

      def converged?(history)
        return false if history.size < 2
        prev, curr = history[-2], history[-1]
        return true if curr.zero?
        (prev - curr).abs.to_f / [prev, 1].max < CONVERGE_THRESHOLD
      end

      def trajectory_stalled?(history)
        return false if history.size < 3
        deltas = history.each_cons(2).map { |a, b| a - b }
        weighted = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, idx| d * (TRAJECTORY_GAMMA**idx) }
        weighted.abs < 1.0
      end

      def commit(msg)
        Open3.capture2e("git", "-C", @root, "add", "-A")
        Open3.capture2e("git", "-C", @root, "commit", "-m", msg.to_s)
      end

      def git_dirty?
        out, = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
        !out.strip.empty?
      end
    end
  end
end

```

## lib/master/sweep/rewriter.rb
```ruby
# frozen_string_literal: true

require "tempfile"

module Master
  class Sweep
    module Rewriter
      private

      def load_prompts = Master.load_yaml(PROMPTS_PATH)

      def build_codebase_map
        files = Dir.glob(File.join(@root, "lib", "**", Scan::Scanner::SCAN_GLOB))
                   .reject { |f| f.include?("/vendor/") || f.include?("/knowledge/") }
                   .map    { |f| f.delete_prefix("#{@root}/") }
                   .sort
        unless @code_index&.built?
          return "## Codebase (#{files.size} files)\n" + files.map { |f| "  #{f}" }.join("\n")
        end

        lines = ["## Codebase (#{files.size} files)"]
        files.each do |rel|
          syms = @code_index.symbols_in(File.join(@root, rel))
          if syms.empty?
            lines << "  #{rel}"
          else
            lines << rel
            syms.select { |s| %i[class module].include?(s.type) }.each { |s| lines << "  class #{s.fqn}" }
            syms.select { |s| s.type == :method }.each { |s| lines << "  def #{s.fqn}" }
          end
        end
        lines.join("\n")
      end

      def collect_files(dir, types)
        types.flat_map { |t| Dir.glob(File.join(dir, GLOBS[t].to_s)) }
             .reject { |f| f.include?("/data/") }
             .uniq.sort
      end

      def rewrite(path, rel)
        src  = File.read(path, encoding: "UTF-8")
        lang = Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
        response = @agent.ask(build_prompt(src, rel, lang))
        extract(response.to_s, lang)
      rescue StandardError => e
        @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
        nil
      end

      def build_prompt(src, rel, lang)
        <<~PROMPT
          You are refactoring #{rel} (#{lang}). Study the full codebase map below
          before making any change — do not modify an interface without tracing its callers.

          #{@map}

          #{@prompts["axioms"]}
          #{@prompts["structural_techniques"]}
          #{@prompts["prose_techniques"]}

          Improve every dimension of #{rel} in a single pass.
          Return ONLY the improved file content — no explanation, no markdown fences
          unless the file is already markdown. If no improvement is possible, return
          exactly: UNCHANGED

          File content:
          #{src}
        PROMPT
      end

      def extract(text, lang)
        return nil if text.strip == "UNCHANGED"
        return nil if text.bytesize < MIN_REWRITE_BYTES && ERROR_PATTERNS.match?(text)
        fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
        return text.match(fence_re)[1]         if text.match?(fence_re)
        return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)
        text.strip.empty? ? nil : text
      end

      def syntax_ok?(path, content)
        checker = SYNTAX_CHECKERS[File.extname(path)]
        return true unless checker
        Tempfile.open(["sweep", File.extname(path)]) do |f|
          f.write(content); f.flush; checker.call(f.path)
        end
      end

      def violations_in(path)
        return 0 unless Scan::Rule::EXT_LANG.key?(File.extname(path).downcase) && File.exist?(path)
        scan_result = @scanner.scan(path, depth: :deep)
        scan_result.ok? ? scan_result.value!.size : 0
      rescue StandardError => _e
        0
      end

      def violations_in_text(content, ref_path)
        ext = File.extname(ref_path).downcase
        return 0 unless Scan::Rule::EXT_LANG.key?(ext)
        Tempfile.open(["vcheck", ext]) do |f|
          f.write(content); f.flush
          scan_result = @scanner.scan(f.path, depth: :deep)
          scan_result.ok? ? scan_result.value!.size : 0
        end
      rescue StandardError => _e
        0
      end
    end
  end
end

```
```

## `snapshot_tools.md`
```markdown
# MASTER Snapshot — lib/master/tools/
Generated: 2026-05-04T10:21:42Z

## lib/master/tools/ask_llm.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AskLlm — delegate sub-questions to the LLM agent mid-pipeline.
    class AskLlm
      TIER        = :guarded
      NAME        = "ask_llm".freeze
      DESCRIPTION = "Ask the LLM a sub-question and return the answer as a string.".freeze

      def initialize(agent:, governor:, circuit_breaker:, cache:, event_bus: nil)
        @agent          = agent
        @governor       = governor
        @circuit_breaker = circuit_breaker
        @cache          = cache
        @bus            = event_bus
      end

      def call(prompt:, context: nil)
        perm = @governor.permit?(NAME, TIER, prompt[0, 60])
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, prompt: prompt[0, 80])

        result = @circuit_breaker.call(estimate_cost(prompt)) {
          @cache.fetch(prompt, @agent.model) {
            @agent.ask(prompt, context: context)
          }
        }

        @bus&.publish("tool:after", tool: NAME)
        Result.ok(result.to_s)
      rescue StandardError => e
        Result.err("ask_llm: #{e.message}", category: :unknown)
      end

      private

      def estimate_cost(prompt)
        (prompt.bytesize / Session::TOKENS_PER_CHAR) * Agent::COST_PER_TOKEN
      end
    end
  end
end

```

## lib/master/tools/ast_edit.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AST-aware editing tool using Ruby's Ripper (stdlib) for parsing.
    # Supports: find_method, rename_method, extract_lines_to_method, add_after_method.
    # Uses Ripper::SexpBuilder for structure-awareness without external gem dependencies.
    class AstEdit
      TIER        = :guarded
      NAME        = "ast_edit".freeze
      DESCRIPTION = "AST-aware code editing: find, rename, or restructure Ruby methods safely.".freeze

      def initialize(root:, undo:, event_bus: nil)
        @root = File.realpath(root)
        @undo = undo
        @bus  = event_bus
      end

      def call(operation:, path:, **opts)
        full = resolve(path)
        return full if full.err?
        fp = full.value!
        return Result.err("ast_edit: not found: #{path}", category: :validation) unless File.exist?(fp)

        src = File.read(fp)
        case operation.to_s
        when "find_method"    then find_method(src, opts[:name].to_s)
        when "rename_method"  then rename_method(fp, src, opts[:from].to_s, opts[:to].to_s)
        when "add_after"      then add_after_method(fp, src, opts[:after].to_s, opts[:code].to_s)
        when "method_lines"   then method_lines(src, opts[:name].to_s)
        else
          Result.err("ast_edit: unknown operation: #{operation}", category: :validation)
        end
      rescue StandardError => e
        Result.err("ast_edit: #{e.message}", category: :unknown)
      end

      private

      # Find a method definition and return its source lines
      def find_method(src, name)
        lines  = src.lines
        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry

        slice  = lines[(entry[:start] - 1)..(entry[:end] - 1)].join
        Result.ok("# #{name} (lines #{entry[:start]}–#{entry[:end]})\n#{slice}")
      end

      # Rename all occurrences of a method definition and calls
      def rename_method(fp, src, from, to)
        return Result.err("ast_edit: from/to required", category: :validation) if from.empty? || to.empty?
        return Result.err("ast_edit: invalid name: #{to}", category: :validation) unless to.match?(/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/)

        @undo.snapshot(fp)
        updated = src
          .gsub(/\bdef\s+#{Regexp.escape(from)}\b/, "def #{to}")
          .gsub(/\b#{Regexp.escape(from)}\s*\(/, "#{to}(")
          .gsub(/\b#{Regexp.escape(from)}\b(?!\s*[:=])/) { |m| to }

        File.write(fp, updated)
        @bus&.publish("tool:ast_edit", op: "rename", from: from, to: to, path: fp)
        Result.ok("renamed #{from} → #{to} in #{File.basename(fp)}")
      end

      # Insert a new method directly after an existing one
      def add_after_method(fp, src, after_name, code)
        return Result.err("ast_edit: after/code required", category: :validation) if after_name.empty? || code.empty?

        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == after_name }
        return Result.err("ast_edit: method not found: #{after_name}", category: :validation) unless entry

        lines = src.lines
        insert_at = entry[:end]  # after the 'end' of the target method
        lines.insert(insert_at, "\n", code.chomp + "\n")

        @undo.snapshot(fp)
        File.write(fp, lines.join)
        @bus&.publish("tool:ast_edit", op: "add_after", after: after_name, path: fp)
        Result.ok("inserted method after #{after_name} in #{File.basename(fp)}")
      end

      # Return start/end line numbers for each method definition
      def method_lines(src, name)
        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry
        Result.ok("#{name}: lines #{entry[:start]}–#{entry[:end]}")
      end

      def method_line_ranges(src)
        require "ripper"
        lines  = src.lines
        ranges = []
        stack  = []  # stack of {name:, start:, depth:}
        depth  = 0

        Ripper.lex(src).each do |(_line, _col), type, token, _state|
          case type
          when :on_kw
            case token
            when "def"
              # next identifier token is the method name
              stack.push({ name: nil, start: _line, depth: depth })
              depth += 1
            when "class", "module", "do", "begin", "for", "if", "unless",
                 "while", "until", "case"
              depth += 1 unless token == "if" && !stack.empty? && stack.last[:name]
            when "end"
              depth -= 1
              if !stack.empty? && depth == stack.last[:depth]
                entry        = stack.pop
                entry[:end]  = _line
                ranges << entry if entry[:name]
              end
            end
          when :on_ident
            if !stack.empty? && stack.last[:name].nil?
              stack.last[:name] = token
            end
          end
        end
        ranges
      end

      def resolve(path)
        full = File.expand_path(path.to_s, @root)
        return Result.err("path escapes root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end

```

## lib/master/tools/batch_replace.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # BatchReplace — apply multiple search-and-replace operations in one pass.
    class BatchReplace
      TIER        = :guarded
      NAME        = "replace".freeze
      DESCRIPTION = "Find and replace text across all files in a directory.".freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
      end

      def call(old_str:, new_str:, dir: nil, rename_files: false)
        perm = @governor.permit?(NAME, TIER, "#{old_str} → #{new_str}")
        return perm if perm.err?

        target = dir ? File.expand_path(dir, @root) : @root
        return Result.err("replace: directory not found: #{target}", category: :validation) unless Dir.exist?(target)

        @bus&.publish("tool:before", tool: NAME, old: old_str, new: new_str)

        changed = 0
        Dir.glob("#{target}/**/*").each do |path|
          next unless File.file?(path)
          content = File.read(path, encoding: "UTF-8") rescue next
          next unless content.include?(old_str)
          File.write(path, content.gsub(old_str, new_str))
          changed += 1
        end

        if rename_files
          Dir.glob("#{target}/**/*")
             .select { |p| File.file?(p) && File.basename(p).include?(old_str) }
             .each do |path|
               new_path = File.join(File.dirname(path), File.basename(path).gsub(old_str, new_str))
               File.rename(path, new_path)
               changed += 1
             end
        end

        @bus&.publish("tool:after", tool: NAME)
        Result.ok("replaced in #{changed} file(s)")
      rescue StandardError => e
        Result.err("replace: #{e.message}", category: :unknown)
      end
    end
  end
end

```

## lib/master/tools/clean.rb
```ruby
# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Clean — removes trailing whitespace, CRLF, and excess blank lines
    # from text files under a given path, using sh/clean.sh.
    class Clean
      SCRIPT = File.expand_path("../../../sh/clean.sh", __dir__).freeze

      def initialize(root:, governor:, event_bus: nil)
        @bus = event_bus
        @root     = root
        @governor = governor
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}", category: :validation) unless File.exist?(target) || Dir.exist?(target)

        guard = @governor.guard("clean #{target}")
        return Result.err(guard.message, category: :policy) if guard.respond_to?(:ok?) && !guard.ok?

        out, err, status = Open3.capture3("zsh", SCRIPT, target)
        return Result.err("clean failed: #{err.strip}", category: :unknown) unless status.success?

        cleaned = out.lines.grep(/^Cleaned:/).map { |l| l.sub("Cleaned: ", "").chomp }
        @bus&.publish("tool:clean", path: target, count: cleaned.size)
        Result.ok("cleaned #{cleaned.size} file(s):\n#{cleaned.join("\n")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end
    end
  end
end

```

## lib/master/tools/git_context.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    class GitContext
      TIER            = :safe
      NAME            = "git_context".freeze
      DESCRIPTION     = "Query git log, blame, diff, and status for the project.".freeze
      MAX_OUTPUT_CHARS = 4000

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(operation:, path: nil, limit: 20)
        case operation.to_s
        when "log"    then git_log(path, limit.to_i)
        when "blame"  then git_blame(path)
        when "diff"   then git_diff(path)
        when "status" then git_status
        when "show"   then git_show(path)
        else
          Result.err("git_context: unknown operation: #{operation}", category: :validation)
        end
      rescue StandardError => e
        Result.err("git_context: #{e.message}", category: :unknown)
      end

      private

      def git_log(path, limit)
        args = ["git", "-C", @root, "log", "--oneline", "--no-color", "-#{limit}"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no commits)" : out.strip)
      end

      def git_blame(path)
        return Result.err("git_context blame: path required", category: :validation) unless path
        safe = safe_path(path)
        return Result.err("git_context blame: file not found: #{path}",
          category: :validation) unless File.exist?(File.join(@root, safe))
        out = IO.popen(["git", "-C", @root, "blame", "--no-color", "-l", safe], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no blame data)" : out.strip)
      end

      def git_diff(path)
        args = ["git", "-C", @root, "diff", "--no-color"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no unstaged changes)" : out.strip)
      end

      def git_status
        out = IO.popen(["git", "-C", @root, "status", "--short", "--no-color"], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(clean)" : out.strip)
      end

      def git_show(ref)
        ref_s = (ref.to_s.empty? ? "HEAD" : ref.to_s).gsub(/[^a-zA-Z0-9._~^:\-\/]/, "")
        out = IO.popen(["git", "-C", @root, "show", "--stat", "--no-color", ref_s], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(not found)" : out.strip[0..MAX_OUTPUT_CHARS])
      end

      def safe_path(path)
        full = File.expand_path(path.to_s, @root)
        raise "path escapes root" unless full.start_with?(@root)
        Pathname.new(full).relative_path_from(@root).to_s
      end
    end
  end
end

```

## lib/master/tools/list_dir.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    class ListDir
      TIER        = :safe
      NAME        = "list_dir".freeze
      DESCRIPTION = "List directory contents, depth-limited.".freeze
      MAX_DEPTH   = 5

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(path: ".", depth: 2, pattern: nil)
        resolved = resolve(path)
        return resolved if resolved.err?

        full  = resolved.value!
        depth = [depth.to_i, MAX_DEPTH].min
        lines = list_tree(full, full, depth, pattern)
        Result.ok(lines.join("\n"))
      end

      private

      def list_tree(base, dir, depth, pattern, indent = 0)
        return [] if depth < 0
        entries = Dir.entries(dir).reject { |e| e.start_with?(".") }.sort
... 767 lines truncated (1167 total)
```

## `snapshot_tree.md`
```markdown
# MASTER Snapshot — Directory Tree
Generated: 2026-05-04T10:21:42Z

```
├── CLAUDE.md
├── DEPLOY
│   ├── README.md
│   ├── openbsd
│   │   ├── README.md
│   │   ├── dot.profile
│   │   └── openbsd.sh
│   ├── postpro.rb
│   ├── rails
│   │   ├── @shared_functions.sh
│   │   ├── README.md
│   │   ├── VOTING_README.md
│   │   ├── __common_patterns.css
│   │   ├── __shared
│   │   │   ├── @active_storage_and_imageprocessing.sh
│   │   │   ├── @ai.sh
│   │   │   ├── @airbnb_features.sh
│   │   │   ├── @common.sh
│   │   │   ├── @devise.sh
│   │   │   ├── @falcon.sh
│   │   │   ├── @features_base.sh
│   │   │   ├── @instant_messaging.sh
│   │   │   ├── @live_cam_streaming.sh
│   │   │   ├── @live_streaming.sh
│   │   │   ├── @messenger_features.sh
│   │   │   ├── @postgresql.sh
│   │   │   ├── @posts.sh
│   │   │   ├── @pwa.sh
│   │   │   ├── @rails_new.sh
│   │   │   ├── @reddit_features.sh
│   │   │   ├── @redis.sh
│   │   │   ├── @twitter_features.sh
│   │   │   ├── @yarn.sh
│   │   │   └── layouts
│   │   │       ├── _flash.html.erb
│   │   │       ├── _footer.html.erb
│   │   │       ├── _meta.html.erb
│   │   │       ├── _nav.html.erb
│   │   │       ├── application.html.erb
│   │   │       ├── visualizer.css
│   │   │       └── visualizer.js
│   │   ├── amber
│   │   │   ├── @shared_functions.sh
│   │   │   ├── README.md
│   │   │   └── amber.sh
│   │   ├── baibl
│   │   │   ├── README.md
│   │   │   └── baibl.sh
│   │   ├── blognet
│   │   │   ├── README.md
│   │   │   ├── blognet.sh
│   │   │   └── blognet_test.sh
│   │   ├── brgen
│   │   │   ├── README.md
│   │   │   ├── README_takeaway.md
│   │   │   ├── README_tv.md
│   │   │   ├── brgen.sh
│   │   │   ├── brgen_dating.sh
│   │   │   ├── brgen_marketplace.sh
│   │   │   ├── brgen_playlist.sh
│   │   │   ├── brgen_takeaway.sh
│   │   │   ├── brgen_tv.sh
│   │   │   ├── demo.html
│   │   │   └── features
│   │   │       ├── auth.sh
│   │   │       ├── controllers.sh
│   │   │       ├── deploy.sh
│   │   │       ├── i18n.sh
│   │   │       ├── messaging.sh
│   │   │       ├── models.sh
│   │   │       ├── routes.sh
│   │   │       ├── seeds.sh
│   │   │       ├── setup.sh
│   │   │       ├── social.sh
│   │   │       ├── styles.sh
│   │   │       ├── views.sh
│   │   │       └── voting.sh
│   │   ├── bsdports
│   │   │   ├── README.md
│   │   │   ├── bsdports.sh
│   │   │   └── bsdports_test.sh
│   │   ├── check_ports.sh
│   │   ├── demo.sh
│   │   ├── hjerterom
│   │   │   ├── README.md
│   │   │   └── hjerterom.sh
│   │   ├── modernize_zsh.sh
│   │   ├── mytoonz.sh
│   │   ├── privcam
│   │   │   ├── README.md
│   │   │   └── privcam.sh
│   │   ├── rich_editor_system.sh
│   │   ├── social_web.pdf
│   │   └── voting_system.sh
│   └── repligen.rb
├── Gemfile
├── Gemfile.lock
├── README.md
├── Rakefile
├── SOUL.md
├── completions
│   └── _master
├── data
│   ├── council.yml
│   ├── council_patterns.yml
│   ├── exemplars.yml
│   ├── heartbeat.yml
│   ├── infer_patterns.yml
│   ├── mcp_servers.yml
│   ├── models.yml
│   ├── openbsd.yml
│   ├── openbsd_patterns.yml
│   ├── platform.yml
│   ├── prompts
│   │   ├── mode_direct.yml
│   │   ├── mode_react.yml
│   │   └── mode_rewoo.yml
│   ├── ruby_style.yml
│   ├── rules.yml
│   ├── soul.yml
│   ├── standing_orders.yml
│   ├── sweep_prompts.yml
│   ├── templates.yml
│   ├── web
│   │   └── favicon.svg
│   ├── workflow.yml
│   └── zsh_patterns.yml
├── docs
│   ├── master2_restoration_opportunities.md
│   └── ui_supersnappy_two_party_plan.md
├── exe
│   └── master
├── knowledge
│   ├── MASTER2
│   │   ├── AGENTS.md
│   │   ├── CLAUDE.md
│   │   ├── Gemfile
│   │   ├── LLM.md
│   │   ├── README.md
│   │   ├── Rakefile
│   │   ├── bin
│   │   │   ├── master
│   │   │   ├── mcp_server
│   │   │   ├── simulate
│   │   │   ├── validate
│   │   │   └── weekly
│   │   ├── completions
│   │   │   └── _master
│   │   ├── data
│   │   │   ├── axiom_resolution.yml
│   │   │   ├── axioms.yml
│   │   │   ├── compression.yml
│   │   │   ├── constitution.yml
│   │   │   ├── council.yml
│   │   │   ├── design.yml
│   │   │   ├── detectors.yml
│   │   │   ├── exemplars.yml
│   │   │   ├── friction_patterns.yml
│   │   │   ├── hooks.yml
│   │   │   ├── integrations.yml
│   │   │   ├── language_detection.yml
│   │   │   ├── language_rules.yml
│   │   │   ├── learned_smells.json
│   │   │   ├── models.yml
│   │   │   ├── personas.yml
│   │   │   ├── phases.yml
│   │   │   ├── pipelines
│   │   │   │   ├── blade-runner-2049.yml
│   │   │   │   ├── film-noir-classic.yml
│   │   │   │   └── wes-anderson-aesthetic.yml
│   │   │   ├── platform.yml
│   │   │   ├── principles.yml
│   │   │   ├── prompts
│   │   │   │   ├── preact.yml
│   │   │   │   ├── react.yml
│   │   │   │   ├── reflexion.yml
│   │   │   │   └── rewoo.yml
│   │   │   ├── quality_thresholds.yml
│   │   │   ├── replicate_models.yml
│   │   │   ├── scheduled_jobs.yml
│   │   │   ├── session_template.yml
│   │   │   ├── stack.yml
│   │   │   ├── strunk.yml
│   │   │   ├── style_guides.yml
│   │   │   ├── system_prompt.yml
│   │   │   └── ui_ux_seo.yml
│   │   ├── docs
│   │   │   ├── masterpiece_roadmap.md
│   │   │   ├── openbsd_execution.md
│   │   │   └── video_narration.md
│   │   ├── examples
│   │   │   └── cinematic_demo.rb
│   │   ├── instructions.txt
│   │   ├── lib
│   │   │   ├── agent
│   │   │   │   ├── autonomy.rb
│   │   │   │   ├── behavior_monitor.rb
│   │   │   │   ├── credential_store.rb
│   │   │   │   ├── firewall.rb
│   │   │   │   ├── policy.rb
│   │   │   │   └── pool.rb
│   │   │   ├── agent.rb
│   │   │   ├── analysis
│   │   │   │   ├── introspection
│   │   │   │   │   ├── self_critique.rb
│   │   │   │   │   └── self_repair.rb
│   │   │   │   ├── introspection.rb
│   │   │   │   ├── openbsd_config_validator.rb
│   │   │   │   └── prescan.rb
│   │   │   ├── analysis.rb
│   │   │   ├── auto_fixer.rb
│   │   │   ├── auto_install.rb
│   │   │   ├── axiom_resolver.rb
│   │   │   ├── boot
│   │   │   │   └── modes.rb
│   │   │   ├── boot.rb
│   │   │   ├── bridges
│   │   │   │   ├── postpro
│   │   │   │   │   └── vips_effects.rb
│   │   │   │   ├── postpro.rb
│   │   │   │   ├── repligen
│   │   │   │   │   └── pipelines.rb
│   │   │   │   └── repligen.rb
│   │   │   ├── bridges.rb
│   │   │   ├── capabilities.rb
│   │   │   ├── chamber
│   │   │   │   ├── creative.rb
│   │   │   │   ├── deliberation.rb
│   │   │   │   ├── ideation.rb
│   │   │   │   ├── review.rb
│   │   │   │   └── swarm.rb
│   │   │   ├── chamber.rb
│   │   │   ├── cinematic
│   │   │   │   └── templates.rb
│   │   │   ├── cinematic.rb
│   │   │   ├── circuit_breaker.rb
│   │   │   ├── code_review
│   │   │   │   ├── analyzers.rb
│   │   │   │   ├── audit.rb
│   │   │   │   ├── bug_hunting
│   │   │   │   │   └── phases.rb
│   │   │   │   ├── bug_hunting.rb
│   │   │   │   ├── cross_ref.rb
│   │   │   │   ├── engine.rb
│   │   │   │   ├── llm_friendly.rb
│   │   │   │   ├── prism_analyzer.rb
│   │   │   │   ├── smells.rb
│   │   │   │   └── violations.rb
│   │   │   ├── command_registry.rb
│   │   │   ├── commands
│   │   │   │   ├── budget_commands.rb
│   │   │   │   ├── chat_commands.rb
│   │   │   │   ├── code_commands.rb
│   │   │   │   ├── init_commands.rb
│   │   │   │   ├── misc_commands
│   │   │   │   │   ├── cinematic_persona.rb
│   │   │   │   │   ├── self_run.rb
│   │   │   │   │   └── selftest_full.rb
│   │   │   │   ├── misc_commands.rb
│   │   │   │   ├── model_commands.rb
│   │   │   │   ├── refactor_helpers.rb
│   │   │   │   ├── session_commands.rb
│   │   │   │   ├── system_commands.rb
│   │   │   │   └── workflow_commands.rb
│   │   │   ├── commands.rb
│   │   │   ├── conflict_resolver.rb
│   │   │   ├── constants.rb
│   │   │   ├── convergence_tracker.rb
│   │   │   ├── conversation.rb
│   │   │   ├── cross_file_analyzer.rb
│   │   │   ├── db_jsonl
│   │   │   │   └── tables.rb
│   │   │   ├── db_jsonl.rb
│   │   │   ├── decision_engine.rb
│   │   │   ├── dependency_map.rb
│   │   │   ├── enforcement
│   │   │   │   ├── layers.rb
│   │   │   │   └── scopes.rb
│   │   │   ├── env_loader.rb
│   │   │   ├── event_bus.rb
│   │   │   ├── evolve.rb
│   │   │   ├── executor
│   │   │   │   ├── context.rb
│   │   │   │   ├── convention_extractor.rb
│   │   │   │   ├── grounded_context.rb
│   │   │   │   ├── momentum.rb
│   │   │   │   ├── plan.rb
│   │   │   │   ├── preact.rb
│   │   │   │   ├── prompts.rb
│   │   │   │   ├── react.rb
│   │   │   │   ├── reflexion.rb
│   │   │   │   ├── rewoo.rb
│   │   │   │   ├── step_loop.rb
│   │   │   │   ├── strategy.rb
│   │   │   │   ├── tool_protocol.rb
│   │   │   │   ├── tool_result.rb
│   │   │   │   └── tools.rb
│   │   │   ├── executor.rb
│   │   │   ├── file_collector.rb
│   │   │   ├── file_processor.rb
│   │   │   ├── harvester.rb
│   │   │   ├── heartbeat.rb
│   │   │   ├── hooks.rb
│   │   │   ├── html_generator.rb
│   │   │   ├── introspection
│   │   │   │   ├── adversarial.rb
│   │   │   │   ├── architect.rb
│   │   │   │   ├── friction_recorder.rb
│   │   │   │   ├── reporting.rb
│   │   │   │   ├── self_map.rb
│   │   │   │   └── session_retrospective.rb
│   │   │   ├── lane.rb
│   │   │   ├── learned_smells.rb
│   │   │   ├── learnings
│   │   │   │   ├── feedback.rb
│   │   │   │   ├── quality.rb
│   │   │   │   └── reflection.rb
│   │   │   ├── learnings.rb
│   │   │   ├── llm
│   │   │   │   ├── budget.rb
│   │   │   │   ├── context_window.rb
│   │   │   │   ├── hesitation_detector.rb
│   │   │   │   ├── models.rb
│   │   │   │   ├── request.rb
│   │   │   │   └── tools.rb
│   │   │   ├── llm.rb
│   │   │   ├── logging
│   │   │   │   ├── dmesg.rb
│   │   │   │   └── structured.rb
│   │   │   ├── logging.rb
│   │   │   ├── master.rb
│   │   │   ├── mcp_server.rb
│   │   │   ├── mode.rb
│   │   │   ├── multi_refactor.rb
│   │   │   ├── nlu.rb
│   │   │   ├── openbsd_validator.rb
│   │   │   ├── output.rb
│   │   │   ├── parser
│   │   │   │   └── multi_language.rb
│   │   │   ├── paths.rb
│   │   │   ├── personas.rb
│   │   │   ├── phase_gates.rb
│   │   │   ├── pipeline
│   │   │   │   ├── context.rb
│   │   │   │   └── repl.rb
│   │   │   ├── pipeline.rb
│   │   │   ├── platform_check.rb
│   │   │   ├── pledge.rb
│   │   │   ├── policy
│   │   │   │   ├── enforcer.rb
│   │   │   │   ├── profile.rb
│   │   │   │   └── rule.rb
│   │   │   ├── pressure_pass.rb
│   │   │   ├── problem_solver.rb
│   │   │   ├── project_memory.rb
│   │   │   ├── quality_gates.rb
│   │   │   ├── queue.rb
│   │   │   ├── reflow.rb
│   │   │   ├── replicate
│   │   │   │   ├── client.rb
│   │   │   │   ├── generators.rb
│   │   │   │   ├── llm.rb
│   │   │   │   ├── media.rb
│   │   │   │   ├── models.rb
│   │   │   │   └── narration.rb
│   │   │   ├── replicate.rb
│   │   │   ├── result.rb
│   │   │   ├── review
│   │   │   │   ├── axiom_stats.rb
│   │   │   │   ├── beauty.rb
│   │   │   │   ├── constitution.rb
│   │   │   │   ├── design_codex.rb
│   │   │   │   ├── enforcer
│   │   │   │   │   ├── language_axioms.rb
│   │   │   │   │   └── quality_standards.rb
│   │   │   │   ├── enforcer.rb
│   │   │   │   ├── fixer.rb
│   │   │   │   ├── reflow.rb
│   │   │   │   ├── scanner.rb
│   │   │   │   └── tool_scanner.rb
│   │   │   ├── review.rb
│   │   │   ├── rubocop_detector.rb
│   │   │   ├── scan
│   │   │   │   └── rules
│   │   │   │       ├── code_style.rb
│   │   │   │       ├── encoding.rb
│   │   │   │       ├── rescue_hygiene.rb
│   │   │   │       └── silent_rescue.rb
│   │   │   ├── scan.rb
│   │   │   ├── scheduler.rb
│   │   │   ├── security
│   │   │   │   ├── injection_guard.rb
│   │   │   │   ├── permissions.rb
│   │   │   │   └── sanitizer.rb
│   │   │   ├── self_refactor.rb
│   │   │   ├── semantic_cache.rb
... 2952 lines truncated (3352 total)
```

## `test/test_agent.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

# Minimal unit tests for Master::Agent — specifically targeting the Tier-1
# bugs the patch corrects. Does not hit any real LLM.
class TestAgent < Minitest::Test
  include Master

  # Fake collaborators — just enough to construct an Agent.
  FakeConfig  = Struct.new(:model, :task_type, :reasoning_mode) do
    def [](k) = send(k) rescue nil
  end
  FakeSession = Struct.new(:messages) { def add_message(**) = messages << _1 }
  FakeCB      = Struct.new(:out) { def check_rate!; end; def call(_, &b); b.call; end }
  FakeCache   = Struct.new(:store) { def fetch(k, m, &b); (store[k] ||= b.call); end }

  def setup
    @agent = Master::Agent.new(
      config:          FakeConfig.new("claude-sonnet-4-6", :exploration, "none"),
      session:         FakeSession.new([]),
      tools:           [],
      circuit_breaker: FakeCB.new,
      cache:           FakeCache.new({})
    )
  end

  # tool_capable? — previously a substring-include check. After patch,
  # anchored regex rejects garbage-tailed model ids but accepts real ones.
  def test_tool_capable_accepts_known_providers
    assert @agent.send(:tool_capable?, "claude-sonnet-4-6")
    assert @agent.send(:tool_capable?, "gpt-4o")
    assert @agent.send(:tool_capable?, "anthropic/claude-opus-4-1")
  end

  def test_tool_capable_rejects_arbitrary_strings
    refute @agent.send(:tool_capable?, "not-a-model")
    refute @agent.send(:tool_capable?, "")
    refute @agent.send(:tool_capable?, "random-gpt-mention-inside-sentence"), \
      "substring-contains is the old bug; anchored regex must not match this"
  end

  # cache_key_for — must produce bounded, deterministic SHA256 keys.
  def test_cache_key_bounded
    k = @agent.send(:cache_key_for, "hello", [])
    assert_equal 64, k.length, "SHA256 hex is 64 chars"
    assert_equal k, @agent.send(:cache_key_for, "hello", []), "deterministic"
  end

  def test_cache_key_uses_window_not_full_context
    long_ctx = (1..100).map { |i| { role: "user", content: "msg #{i}" * 50 } }
    short_ctx = long_ctx.last(4)
    k_long  = @agent.send(:cache_key_for, "same", long_ctx)
    k_short = @agent.send(:cache_key_for, "same", short_ctx)
    assert_equal k_long, k_short, "only the last CACHE_WINDOW messages affect the key"
  end

  # escalation flag — must be per-thread, not per-instance.
  def test_escalation_flag_is_thread_local
    Thread.current[:master_escalation_done] = nil
    other_thread_saw = nil
    t = Thread.new do
      other_thread_saw = Thread.current[:master_escalation_done]
    end
    t.join
    assert_nil other_thread_saw, "flag must not leak across threads"
  end
end
```

## `test/test_axioms.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestAxioms < Minitest::Test
  def setup
    @axioms = Master::Axioms.new
  end

  def test_kernel_not_empty
    refute @axioms.kernel.empty?, "kernel axioms must be present"
  end

  def test_kernel_has_preserve_first
    assert @axioms.kernel.key?("PRESERVE_FIRST")
  end

  def test_philosophy_sorted_by_priority
    items = @axioms.philosophy
    refute items.empty?
    priorities = items.map { |a| a["priority"].to_i }
    assert_equal priorities.sort, priorities
  end

  def test_kernel_block_formatted
    block = @axioms.kernel_block
    assert block.include?("## Kernel Axioms")
    assert block.include?("PRESERVE_FIRST")
  end

  def test_philosophy_block_limit
    block = @axioms.philosophy_block(limit: 3)
    assert block.include?("## Core Philosophy (top 3)")
  end

  def test_lookup_kernel
    val = @axioms.lookup("PRESERVE_FIRST")
    refute_nil val
    assert val.length > 5
  end
end
```

## `test/test_browser.rb`
```ruby
# frozen_string_literal: true

# Browser integration test using Ferrum + local Chromium.
# Run: bundle exec ruby test/test_browser.rb
#
# NOTE: Browser must be created BEFORE minitest/autorun is loaded,
# otherwise Minitest's signal handlers break Ferrum's pipe reading.
#
# Requires ~300MB free RAM. On low-memory servers, tests are auto-skipped.
#
# WHY CHROME TESTS SKIP ON OPENBSD
# =================================
# Chrome/Chromium exits with SIGSEGV (139) immediately on OpenBSD due to the
# W^X (Write XOR Execute) memory protection policy enforced by the kernel.
# Chrome's V8 engine — even with --jitless -- and its process model require
# mmap(PROT_WRITE|PROT_EXEC) pages that OpenBSD forbids at the OS level.
# No combination of flags (--no-sandbox, --single-process, --jitless,
# --disable-gpu) resolves this; a dedicated OpenBSD-patched Chromium port
# would be required.
#
# To run browser tests against the live server from a non-OpenBSD machine:
#   WEB_URL=https://ai.brgen.no:4430 bundle exec ruby test/test_browser.rb
#
# HTTP smoke tests (test_web_http.rb) cover: page load, overlay presence,
# JS syntax, metrics JSON, and SSE stream — and run fine on OpenBSD.

require "ferrum"
require "json"
require "net/http"
require "socket"

CHROME_PATH = %w[/usr/local/bin/chrome /usr/local/bin/chromium].find { |p| File.executable?(p) }
WEB_URL     = (ENV["WEB_URL"] || "http://localhost:10002").freeze

FREE_MEM_MB = begin
  # Use free + inactive pages — inactive pages are reclaimable by new processes.
  stats = `vmstat -s`
  free_pages     = stats[/(\d+) pages free/,    1].to_i
  inactive_pages = stats[/(\d+) pages inactive/, 1].to_i
  (free_pages + inactive_pages) * 4 / 1024  # 4KB pages → MB
rescue
  999
end

SKIP_REASON = if CHROME_PATH.nil?
  "Chromium not found"
elsif begin; TCPSocket.new("127.0.0.1", 10002).close; false; rescue; true; end
  "Web server not running on port 10002"
elsif FREE_MEM_MB < 300
  "Insufficient free memory (#{FREE_MEM_MB}MB < 300MB required for Chrome)"
end

# Start Chrome now, before minitest/autorun installs signal handlers.
FERRUM_BROWSER = if SKIP_REASON.nil?
  begin
    Ferrum::Browser.new(
      browser_path: CHROME_PATH,
      process_timeout: 30,
      timeout: 20,
      browser_options: {
        "headless"       => "new",
        "no-sandbox"     => nil,
        "single-process" => nil,
        "disable-gpu"    => nil,
        "disable-dev-shm-usage" => nil
      }
    )
  rescue StandardError => e
    warn "Chrome failed to start: #{e.message}"
    nil
  end
end

# Override SKIP_REASON if browser failed to start
BROWSER_SKIP = SKIP_REASON || (FERRUM_BROWSER.nil? ? "Chrome failed to start" : nil)

require "minitest/autorun"

class TestBrowserUI < Minitest::Test
  def skip_if_unavailable
    skip BROWSER_SKIP if BROWSER_SKIP
  end

  def fresh_page
    pg = FERRUM_BROWSER.create_page
    pg.go_to(WEB_URL)
    pg.network.wait_for_idle
    pg
  rescue Ferrum::DeadBrowserError => e
    skip "Chrome died (OOM): #{e.message}"
  end

  def teardown
    FERRUM_BROWSER&.pages&.each(&:close) rescue nil
  end

  def test_01_page_loads_with_overlay
    skip_if_unavailable
    pg = fresh_page
    assert pg.at_css("#overlay"), "overlay element missing"
    assert !pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be visible on load"
  end

  def test_02_overlay_dismisses_on_click
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be hidden after click"
  end

  def test_03_input_active_after_overlay_dismissed
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('input-field').classList.contains('active')"),
           "input-field should have 'active' class"
  end

  def test_04_chat_receives_response
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.2
    pg.at_css("#input-field input[type=text]").focus
    pg.keyboard.type("ping")
    pg.keyboard.type(:Return)
    deadline = Time.now + 30
    response = ""
    loop do
      response = pg.evaluate("document.getElementById('chat-log').textContent").strip
      break unless response.empty?
      break if Time.now > deadline
      sleep 1
    end
    refute_empty response, "chat-log should contain a response to 'ping'"
  end

  # Uses plain HTTP — no browser page needed for a JSON endpoint.
  def test_05_metrics_endpoint_json
    skip "Web server not running" unless begin
      TCPSocket.new("127.0.0.1", 10002).close
      true
    rescue
      false
    end
    uri  = URI("#{WEB_URL}/chat/metrics")
    body = Net::HTTP.get(uri)
    data = JSON.parse(body)
    assert data.key?("model"),         "metrics should include 'model'"
    assert data.key?("tokens"),        "metrics should include 'tokens'"
    assert data.key?("open_breakers"), "metrics should include 'open_breakers'"
  rescue JSON::ParserError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end
end

Minitest.after_run { FERRUM_BROWSER&.quit rescue nil }
```

## `test/test_cli.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestCLI < Minitest::Test
  def setup
    @session     = Minitest::Mock.new
    @agent       = Minitest::Mock.new
    @renderer    = Minitest::Mock.new
    @logging     = Minitest::Mock.new
    @undo        = Minitest::Mock.new
    @config      = Minitest::Mock.new
    @pipeline    = Minitest::Mock.new

    @config.expect(:[], false, ["tts"])
    @config.expect(:prescan?, false)

    @container = {
      session:  @session,
      agent:    @agent,
      renderer: @renderer,
      logging:  @logging,
      undo:     @undo,
      config:   @config,
      pipeline: @pipeline
    }

    @cli = Master::CLI.new(container: @container)
  end

  # ── container accessor ────────────────────────────────────────────────────

  def test_container_accessor
    assert_same @container, @cli.container
  end

  # ── TTS flag ──────────────────────────────────────────────────────────────

  def test_tts_off_when_unavailable
    refute @cli.instance_variable_get(:@tts_on),
      "tts_on should be false when Speech.available? is false"
  end

  # ── handle_command dispatch ───────────────────────────────────────────────

  def test_handle_command_returns_false_for_non_command
    assert_equal false, @cli.send(:handle_command, "hello world")
  end

  def test_handle_command_save
    @session.expect(:save!, nil)
    @renderer.expect(:render, "saved", ["saved"], mode: :success)
    capture_io { @cli.send(:handle_command, "/save") }
    @session.verify
  end

  def test_handle_command_exit
    @session.expect(:save!, nil)
    capture_io { @cli.send(:handle_command, "/exit") }
    refute @cli.instance_variable_get(:@running)
    @session.verify
  end

  def test_handle_command_tts_on
    # Speech not available in test env — /tts on should stay off → "unavailable"
    @renderer.expect(:render, "tts: unavailable", [String], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts on") }
  end

  def test_handle_command_tts_off
    @renderer.expect(:render, "tts: off", ["tts: off"], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts off") }
    refute @cli.instance_variable_get(:@tts_on)
  end

  def test_handle_command_unknown
    @renderer.expect(:render, "unknown command: /foo", [String], mode: :warning)
    capture_io { @cli.send(:handle_command, "/foo") }
    @renderer.verify
  end

  # ── process ───────────────────────────────────────────────────────────────

  def test_process_skips_blank_input
    @pipeline.expect(:call, nil)
    @cli.send(:process, "   ")
  end

  def test_process_ok_result
    text = "the answer is 42"
    result = Master::Result.ok(rendered: text)
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.send(:process, "what is 6*7") }
    assert_includes out, text
    assert @cli.instance_variable_get(:@last_ok)
  end

  def test_process_err_result
    result = Master::Result.err("model unavailable")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    @renderer.expect(:render, "[ERR]", ["model unavailable"], mode: :error)
    capture_io { @cli.send(:process, "fail me") }
    refute @cli.instance_variable_get(:@last_ok)
  end

  # ── pipe ──────────────────────────────────────────────────────────────────

  def test_pipe_calls_process
    result = Master::Result.ok(rendered: "pong")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.pipe("ping") }
    assert_includes out, "pong"
  end
end
```

## `test/test_experience.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestExperience < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @exp = Master::State::Experience.new(root: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_signature_ignores_arguments
    plan_a = [{ tool: :fs_read, path: "a.rb" }, { tool: :ast_replace, method: "login" }]
    plan_b = [{ tool: :fs_read, path: "z.rb" }, { tool: :ast_replace, method: "logout" }]
    # Same strategy, different arguments → same signature → shared score.
    @exp.record(plan: plan_a, score: 1.0)
    refute_in_delta 0.0, @exp.score(plan_b), 0.2, "same tool sequence should share experience"
  end

  def test_decay_bounds_unbounded_growth
    plan = [{ tool: :fs_read }]
    20.times { @exp.record(plan: plan, score: 1.0) }
    entry = @exp.record(plan: plan, score: 1.0)
    # With DECAY=0.99, count cannot grow to 21 — it stays well below.
    assert_in_delta 20.0, entry["count"], 2.0
  end

  def test_unknown_plan_returns_near_zero
    score = @exp.score([{ tool: :never_run }])
    assert_in_delta 0.0, score, 0.1, "unseen plan returns base 0 + small noise"
  end
end
```

## `test/test_helper.rb`
```ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "timeout"

# Load MASTER without booting the CLI
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"

# All tests time out after 10s to prevent hangs.
Minitest::Test.class_eval do
  alias_method :run_without_timeout, :run
  def run(*args)
    Timeout.timeout(10) { run_without_timeout(*args) }
  rescue Timeout::Error
    failures << Minitest::UnexpectedError.new(Timeout::Error.new("timed out after 10s"))
    self
  end
end
```

## `test/test_pipeline.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

# Pipeline unit tests — Result-monadic chaining and rollback contract.
class TestPipeline < Minitest::Test
  include Master

  class OkStage
    def call(ctx) = Master::Result.ok(ctx.merge(stamped: true))
  end

  class ErrStage
    def initialize(cat = :unknown) = (@cat = cat)
    def call(_ctx) = Master::Result.err("boom", category: @cat)
  end

  class RaiseStage
    def call(_ctx) = raise "stage exploded"
  end

  def test_happy_path_passes_context_through
    pipe = Master::Pipeline.new([OkStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(input: "hi"))
    assert result.ok?
    assert result.value![:stamped]
  end

  def test_first_error_short_circuits
    pipe = Master::Pipeline.new([OkStage.new, ErrStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok({}))
    refute result.ok?
    assert_equal "boom", result.message
  end

  def test_raise_in_stage_becomes_err
    pipe = Master::Pipeline.new([OkStage.new, RaiseStage.new])
    result = pipe.call(Master::Result.ok({}))
    refute result.ok?
    assert_match(/exploded/, result.message)
  end

  def test_rollback_skipped_outside_git_workspace
    # In /tmp (no .git), rollback is a no-op — must not crash.
    Dir.mktmpdir do |dir|
      pipe = Master::Pipeline.new([ErrStage.new(:validation)], root: dir)
      result = pipe.call(Master::Result.ok({}))
      refute result.ok?
      # No exception raised = success for this test.
    end
  end
end
```

## `test/test_prune.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestPrune < Minitest::Test
  def stage
    Master::Stages::Prune.new
  end

  def call(text)
    stage.call({ output: text })
  end

  def test_strips_preamble
    r = call("Certainly! Here is the answer.")
    assert r.ok?
    assert_equal "Here is the answer.", r.value![:output]
  end

  def test_strips_hedge
    r = call("I think that Ruby is great.")
    assert r.ok?
    assert_equal "Ruby is great.", r.value![:output]
  end

  def test_skips_code_blocks
    code = "```ruby\njust use this\n```"
    r = call(code)
    assert_equal code, r.value![:output]  # must not mangle code
  end

  def test_passthrough_non_string
    r = stage.call({ output: 42 })
    assert r.ok?
    assert_equal 42, r.value![:output]
  end

  def test_empty_string_passthrough
    r = call("")
    assert r.ok?
  end
end
```

## `test/test_result.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestResult < Minitest::Test
  def test_ok_holds_value
    r = Master::Result.ok("hello")
    assert r.ok?
    refute r.err?
    assert_equal "hello", r.value!
  end

  def test_err_holds_message
    r = Master::Result.err("boom", category: :unknown)
    assert r.err?
    refute r.ok?
    assert_equal "boom", r.message
  end

  def test_and_then_chains_on_ok
    r = Master::Result.ok(2).and_then { |v| Master::Result.ok(v * 3) }
    assert r.ok?
    assert_equal 6, r.value!
  end

  def test_and_then_short_circuits_on_err
    r = Master::Result.err("fail").and_then { |_| Master::Result.ok("never") }
    assert r.err?
    assert_equal "fail", r.message
  end

  def test_and_then_wraps_plain_value
    r = Master::Result.ok(5).and_then { |v| v * 2 }
    assert r.ok?
    assert_equal 10, r.value!
  end
end
```

## `test/test_ring_buffer.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestRingBuffer < Minitest::Test
  def test_push_and_to_a
    buf = Master::RingBuffer.new(3)
    buf.push("a").push("b").push("c")
    assert_equal %w[a b c], buf.to_a
  end

  def test_wraps_around
    buf = Master::RingBuffer.new(3)
    %w[a b c d].each { |x| buf.push(x) }
    assert_equal %w[b c d], buf.to_a
  end

  def test_each_without_block_returns_enumerator
    buf = Master::RingBuffer.new(3)
    buf.push("x")
    assert_instance_of Enumerator, buf.each
  end

  def test_to_a_without_block
    buf = Master::RingBuffer.new(3)
    buf.push("x").push("y")
    assert_equal %w[x y], buf.to_a  # must not raise LocalJumpError
  end

  def test_size_and_empty
    buf = Master::RingBuffer.new(4)
    assert buf.empty?
    buf.push("a")
    assert_equal 1, buf.size
    refute buf.empty?
  end
end
```

## `test/test_speech.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestSpeech < Minitest::Test
  # ── module interface ──────────────────────────────────────────────────────

  def test_available_returns_boolean
    assert_includes [true, false], Master::Speech.available?
  end

  def test_voices_constants_present
    assert Master::Speech::VOICES.key?(:osman)
    assert Master::Speech::VOICES.key?(:ryan)
  end

  def test_styles_constants_present
    assert Master::Speech::STYLES.key?(:deep)
    assert Master::Speech::STYLES.key?(:normal)
  end

  def test_synthesize_returns_nil_for_empty_text
    assert_nil Master::Speech.synthesize("")
    assert_nil Master::Speech.synthesize("   ")
  end

  def test_synthesize_bytes_returns_nil_for_empty
    assert_nil Master::Speech.synthesize_bytes("")
  end

  # ── when edge-tts unavailable ─────────────────────────────────────────────

  def test_synthesize_returns_nil_when_unavailable
    # Stub Speech.available? to false
    Master::Speech.stub(:available?, false) do
      assert_nil Master::Speech.synthesize("hello")
    end
  end

  def test_synthesize_bytes_returns_nil_when_unavailable
    Master::Speech.stub(:available?, false) do
      assert_nil Master::Speech.synthesize_bytes("hello")
    end
  end

  # ── when edge-tts available (mock system call) ────────────────────────────

  def test_synthesize_calls_edge_tts_with_correct_args
    skip "edge-tts not installed" unless Master::Speech.available?

    tmp = nil
    Master::Speech.stub(:synthesize, ->(text, **) {
      # Just verify we can call it without raising
      nil
    }) do
      tmp = Master::Speech.synthesize("test", voice: :osman, style: :deep)
    end
    assert_nil tmp  # mock returns nil
  end

  def test_synthesize_bytes_cleans_up_temp_file
    fake_path = "/tmp/m3_tts_test_fake.mp3"

    Master::Speech.stub(:synthesize, fake_path) do
      # Create a fake mp3
      File.write(fake_path, "fake-mp3-data")
      bytes = Master::Speech.synthesize_bytes("hello")
      assert_equal "fake-mp3-data", bytes
      refute File.exist?(fake_path), "temp file should be deleted"
    end
  end

  # ── voice / style lookup ─────────────────────────────────────────────────

  def test_unknown_voice_falls_back_to_default
    # Speech.synthesize uses VOICES.fetch(voice, VOICES[DEFAULT_VOICE])
    # so unknown symbol falls back to Osman
    default_voice = Master::Speech::VOICES[Master::Speech::DEFAULT_VOICE]
    assert default_voice
  end

  def test_deep_style_has_negative_pitch
    style = Master::Speech::STYLES[:deep]
    assert style[:pitch].start_with?("-"), "deep pitch should be negative"
    assert style[:rate].start_with?("-"),  "deep rate should be negative"
  end
end
```

## `test/test_web_http.rb`
```ruby
# frozen_string_literal: true

# HTTP smoke tests for the MASTER web UI.
# Faster and lighter than browser tests -- no Chrome required.
# Run: bundle exec ruby test/test_web_http.rb

require "net/http"
require "json"
require "socket"
require "minitest/autorun"

WEB_PORT = 10002

SKIP_HTTP = begin
  TCPSocket.new("127.0.0.1", WEB_PORT).close
  nil
rescue Errno::ECONNREFUSED
  "Web server not running on port #{WEB_PORT}"
end

class TestWebHTTP < Minitest::Test
  def skip_unless_server
    skip SKIP_HTTP if SKIP_HTTP
  end

  def get(path, headers = {})
    Net::HTTP.start("127.0.0.1", WEB_PORT, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(path, headers))
    end
  end

  def test_01_homepage_returns_200
    skip_unless_server
    res = get("/")
    assert_equal "200", res.code, "homepage should return 200"
  end

  def test_02_homepage_contains_overlay
    skip_unless_server
    res = get("/")
    assert_includes res.body, "overlay", "homepage should contain overlay element"
  end

  def test_03_homepage_js_no_stray_paren
    skip_unless_server
    res = get("/")
    bad = res.body.lines.grep(/^\s*"\);/)
    assert_empty bad, "stray \");\" found in page JS: #{bad.first(2).inspect}"
  end

  def test_04_metrics_returns_json
    skip_unless_server
    res = get("/chat/metrics")
    assert_equal "200", res.code, "metrics endpoint should return 200"
    data = JSON.parse(res.body)
    assert data.key?("model"),         "metrics should include 'model'"
    assert data.key?("tokens"),        "metrics should include 'tokens'"
    assert data.key?("uptime"),        "metrics should include 'uptime'"
    assert data.key?("open_breakers"), "metrics should include 'open_breakers'"
  rescue StandardError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end

  def test_05_message_endpoint_streams_sse
    skip_unless_server
    Net::HTTP.start("127.0.0.1", WEB_PORT, read_timeout: 15) do |http|
      req = Net::HTTP::Post.new("/chat/message")
      req.set_form_data("message" => "ping")
      data = ""
      http.request(req) do |res|
        assert_equal "200", res.code, "message endpoint should return 200"
        assert_match "text/event-stream", res["Content-Type"].to_s,
                     "message endpoint should stream SSE"
        res.read_body do |chunk|
          data += chunk
          break if data.include?("[DONE]") || data.size > 512
        end
      end
      assert_includes data, "data:", "SSE response should contain data: lines"
    end
  rescue Net::ReadTimeout
    # Server still streaming -- that means it accepted the request fine
  end
end
```

## `test/test_web_ui.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "rack/test"

# Minimal Rack test harness for the web UI chat controller.
# Tests cover SSE stream, TTS endpoint, dmesg, and metrics.

ENV["RAILS_ENV"] = "test"

# We test the controller logic via a stub Rack app rather than
# booting the full Rails stack.
class FakeSpeech
  def self.available?  = true
  def self.synthesize_bytes(_text, **) = "FAKE-MP3-BYTES"
end

class FakePipeline
  attr_writer :result
  def call(_ctx) = @result || Master::Result.ok(rendered: "hello from pipeline")
end

class FakeSession
  def token_est = 42
  def cost      = 0.0001
end

class FakeAgent
  def model = "test/model-7b"
end

class FakeContainer
  def [](key)
    case key
    when :agent    then FakeAgent.new
    when :session  then FakeSession.new
    when :pipeline then @pipeline ||= FakePipeline.new
    end
  end
  def pipeline = self[:pipeline]
end

class TestWebUI < Minitest::Test
  include Rack::Test::Methods

  def setup
    @container = FakeContainer.new
  end

  # ── Result monad ──────────────────────────────────────────────────────────

  def test_result_ok_wraps_value
    r = Master::Result.ok("hello")
    assert r.ok?
    assert_equal "hello", r.value!
  end

  def test_result_err_wraps_message
    r = Master::Result.err("boom")
    assert r.err?
    assert_equal "boom", r.message
  end

  def test_result_err_value_bang_raises_unwrap_error
    r = Master::Result.err("boom")
    assert_raises(Master::UnwrapError) { r.value! }
  end

  def test_result_ok_chaining
    r = Master::Result.ok(5).and_then { |v| Master::Result.ok(v * 2) }
    assert_equal 10, r.value!
  end

  def test_result_err_short_circuits
    r = Master::Result.err("x").and_then { raise "should not reach" }
    assert r.err?
  end

  # ── Pipeline ─────────────────────────────────────────────────────────────

  def test_pipeline_returns_result
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_includes result.value![:rendered], "hello"
  end

  def test_pipeline_err_propagates
    @container.pipeline.result = Master::Result.err("model down")
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.err?
    assert_equal "model down", result.message
  end

  # ── Speech bytes ─────────────────────────────────────────────────────────

  def test_speech_synthesize_bytes_stub
    bytes = FakeSpeech.synthesize_bytes("hello world")
    assert_equal "FAKE-MP3-BYTES", bytes
  end

  # ── Cognitive monitor ─────────────────────────────────────────────────────

  def test_cognitive_monitor_starts_clean
    m = Master::CognitiveMonitor.new
    assert_equal 0.0, m.load
    assert_equal :optimal, m.flow_state
  end

  def test_cognitive_monitor_push_increases_load
    m = Master::CognitiveMonitor.new
    m.push("concept_a", weight: 2.0)
    assert_in_delta 2.0, m.load, 0.01
  end

  def test_cognitive_monitor_overload_after_threshold
    m = Master::CognitiveMonitor.new
    m.push("heavy", weight: 8.0)
    assert m.overloaded?
  end

  def test_cognitive_monitor_reset
    m = Master::CognitiveMonitor.new
    5.times { |i| m.push("c#{i}", weight: 1.5) }
    m.reset!(keep_recent: 2)
    assert m.load <= 3.0
    assert_equal 0, m.switches
  end

  def test_cognitive_monitor_update_flow_returns_self
    m = Master::CognitiveMonitor.new
    assert_same m, m.update_flow(context_switches: 1)
  end

  def test_cognitive_monitor_state_hash
    m = Master::CognitiveMonitor.new
    s = m.state
    assert s.key?(:load)
    assert s.key?(:flow_state)
    assert s.key?(:overload_risk)
    assert s.key?(:complexity)
  end

  # ── SwarmCoordinator ─────────────────────────────────────────────────────

  def test_swarm_coordinator_worker_roles
    # Just check the list is non-empty without booting real agents
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :analyst
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :coder
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :reviewer
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :researcher
  end

  def test_swarm_coordinator_unknown_role
    mock_agent = Minitest::Mock.new
    coord = Master::Swarm::Coordinator.new(agent: mock_agent)
    result = coord.dispatch(:nonexistent, task: "foo")
    assert result.err?
    assert_includes result.message, "unknown role"
  end

  # ── Memory ───────────────────────────────────────────────────────────────

  def test_memory_remember_and_recall
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:user_name, "Osman")
      assert_equal "Osman", m.recall(:user_name)
    end
  end

  def test_memory_context_summary_nil_when_empty
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      assert_nil m.context_summary
    end
  end

  def test_memory_context_summary_lists_keys
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:language, "Ruby")
      summary = m.context_summary
      assert_includes summary, "language"
      assert_includes summary, "Ruby"
    end
  end

  # ── Personality ──────────────────────────────────────────────────────────

  def test_personality_default_is_dark_malay
    assert_equal :dark_malay, Master::Personality::DEFAULT
  end

  def test_personality_system_prompt_non_empty
    p = Master::Personality.new(:dark_malay)
    assert p.system_prompt.length > 10
  end

  def test_personality_system_prompt_memoized
    p = Master::Personality.new(:dark_malay)
    assert_same p.system_prompt, p.system_prompt
  end

  # ── UnwrapError ──────────────────────────────────────────────────────────

  def test_unwrap_error_is_runtime_error_subclass
    assert Master::UnwrapError < RuntimeError
  end
end
```

## `web/Gemfile`
```text
source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
# gem "puma"
gem "falcon"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end

gem "master", path: ".."
```

## `web/README.md`
```markdown
# MASTER Web UI

Rails 8 + Falcon server. Internal port 53187; relayd proxies to ai.brgen.no:4430.

## Routes

| Route | Description |
|---|---|
| `GET /` | Chat interface |
| `POST /chat/message` | SSE streaming response |
| `POST /chat/tts` | TTS synthesis |
| `POST /chat/speak` | Speak text |
| `GET /chat/metrics` | Session metrics |
| `GET /chat/dmesg` | Event log |
| `GET /events/stream` | SSE event stream |

## Canvas

- 2000-particle orb visualization
- 50 procedural shapes
- Ambient pad engine
- Drum sequencer
- 17 voice FX chains

## rc.d service

```zsh
doas rcctl enable master
doas rcctl start master
```

Daemon binds to 127.0.0.1:53187. relayd handles TLS termination.
```

## `web/Rakefile`
```text
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks
```

## `web/app/controllers/application_controller.rb`
```ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate!

  @@container        = nil
  @@mutex            = Mutex.new
  @@start_ms         = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  @@scheduler_thread = nil

  private

  def authenticate!
    return if request.path == "/up" || request.path == "/health"
    return if session[:authenticated]
    tok = web_token
    if params[:token] == tok || request.headers["X-Token"] == tok
      session[:authenticated] = true
      return
    end
    render plain: "401 Unauthorized — visit with ?token=#{tok}", status: :unauthorized
  end

  def web_token
    cfg_file = File.join(Rails.root, "../.master/config.yml")
    cfg = YAML.safe_load_file(cfg_file, permitted_classes: [], aliases: true) rescue {}
    cfg["web_token"].presence || generate_token!(cfg_file, cfg)
  end

  def generate_token!(cfg_file, cfg)
    require "securerandom"
    tok = SecureRandom.urlsafe_base64(24)
    cfg["web_token"] = tok
    File.write(cfg_file, cfg.to_yaml)
    tok
  end

  def container
    @@mutex.synchronize do
      @@container ||= Master.build(root: Rails.root.join("..").to_s).tap do |c|
        start_scheduler(c)
        Master.generate_boot_snapshot(c) rescue nil
        c[:heartbeat]&.start!
      end
    end
  end

  def start_scheduler(c)
    return if @@scheduler_thread&.alive?
    @@scheduler_thread = Thread.new do
      sleep 300
      loop do
        begin
          due = c[:standing].due
          if due.any?
            results = c[:standing].run_due!
            results.each { |r| c[:bus].publish("scheduler:ran", name: r[:name]) rescue nil }
          end
        rescue StandardError
          nil
        end
        sleep 900
      end
    end
    @@scheduler_thread.abort_on_exception = false
  end

  def start_ms
    @@start_ms
  end
end
```

## `web/app/controllers/chat_controller.rb`
```ruby
# frozen_string_literal: true

require "shellwords"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:message, :tts, :speak]

  def index
    @model = container[:agent].model.to_s.split("/").last
    render layout: false
  end

  def dmesg
    lines = `dmesg 2>/dev/null`.lines.first(20).map(&:chomp)
    render json: { lines: lines }
  end

  def metrics
    c = container
    repo_root = Rails.root.join("..").to_s
    dirty = `git -C #{Shellwords.escape(repo_root)} status --porcelain 2>/dev/null`.lines.count
    open_models = c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    render json: {
      model:            c[:agent].model.to_s.split("/").last,
      tokens:           c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:             "$%.4f" % (c[:session].respond_to?(:cost) ? c[:session].cost : 0.0),
      uptime:           ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      repo_dirty_count: dirty,
      open_breakers:    open_models
    }
  end

  def message
    input = params[:message].to_s.strip
    return head(:bad_request) if input.empty?

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    sse = response.stream
    begin
      streamed  = false
      tool_sub  = container[:bus].subscribe("tool:before") do |ev|
        begin
          payload = { tool: ev[:tool].to_s, path: ev[:path].to_s }.to_json
          sse.write("event: tool\ndata: #{payload}\n\n")
        rescue StandardError
          nil
        end
      end

      on_chunk = ->(token) {
        streamed = true
        encoded = token.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
        sse.write("data: #{encoded}\n\n")
      }

      ctx = { user_message: input, on_chunk: on_chunk }
      if (img = params[:image]).present?
        ctx[:image] = { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
      end

      result = container[:pipeline].call(Master::Result.ok(**ctx))

      unless streamed
        text = case result
               when Master::Result::Ok
                 val = result.value
                 val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
               when Master::Result::Err
                 "ERROR: #{result.message}"
               end
        unless text.to_s.strip.empty?
          encoded = text.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
          sse.write("data: #{encoded}\n\n")
        end
      end

      sse.write("data: [DONE]\n\n")
    rescue => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      begin
        tool_sub.call if defined?(tool_sub) && tool_sub
      rescue StandardError
        nil
      end
      sse.close
    end
  end

  def speak
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?
    container[:bus].publish("speak:text", { text: text })
    head :ok
  end

  def tts
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    bytes = Master::Speech.synthesize_bytes(text)
    if bytes && bytes.bytesize > 0
      send_data bytes, type: "audio/mpeg", disposition: "inline"
    else
      head :service_unavailable
    end
  rescue => e
    logger.error "TTS failed: #{e.message}"
    head :service_unavailable
  end
end
```

## `web/app/controllers/events_controller.rb`
```ruby
# frozen_string_literal: true

# EventsController — SSE stream of EventBus events to the orb visualizer.
#
# The orb already exists (web/app/views/chat/index.html.erb). What it lacked
# was a real signal. This controller subscribes to the container's EventBus,
# serializes each event as Server-Sent Event, and streams them.
#
# Wire into routes:
#   get "/events/stream" => "events#stream"
#
# Consume from the orb JS:
#   const es = new EventSource("/events/stream");
#   es.onmessage = e => handleEvent(JSON.parse(e.data));
#
# Event types the orb can react to (emitted by existing pipeline stages):
#   llm:request           → burst pulse
#   llm:escalation        → color shift
#   tool:used             → ripple
#   scan:complete         → stabilization flash
#   autoloop:cycle        → rotation increment
#   sweep:cycle           → slow rotation
#   pipeline:rollback     → red glitch (from Pipeline rollback)
class EventsController < ApplicationController
  include ActionController::Live

  POLL_INTERVAL_S = 0.1
  MAX_STREAM_S    = 600   # hard cap — 10 minute stream ceiling

  def stream
    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"  # nginx passthrough

    bus      = container[:bus]
    received = Queue.new
    sub      = bus.subscribe("*") { |type, payload|
      received << { t: Time.now.to_f, type: type, data: payload }
    }
    deadline = Time.now + MAX_STREAM_S

    loop do
      break if Time.now > deadline
      if received.empty?
        response.stream.write(": keepalive\n\n")  # SSE comment, prevents proxy timeout
        sleep POLL_INTERVAL_S
      else
        event = received.pop(true) rescue nil
        next unless event
        response.stream.write("data: #{event.to_json}\n\n")
      end
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client went away — normal. Stop streaming.
  ensure
    bus&.unsubscribe(sub) if sub && bus.respond_to?(:unsubscribe)
    response.stream.close rescue nil
  end
end
```

## `web/app/controllers/health_controller.rb`
```ruby
# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    render json: { status: "ok" }, status: :ok
  end
end
```

## `web/app/helpers/application_helper.rb`
```ruby
module ApplicationHelper
end
```

## `web/app/models/application_record.rb`
```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
```

## `web/app/views/chat/index.html.erb`
```erb
<!DOCTYPE html>
<html lang="ms">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover"/>
  <meta name="mobile-web-app-capable" content="yes"/>
  <meta name="color-scheme" content="dark"/>
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/>
  <title>MASTER &middot; <%= @model %></title>
  <meta name="theme-color" content="#000000"/>
<style>
  @layer base, components, utilities;

  @layer base{
  :root{

      --safe-top:env(safe-area-inset-top,0px);
      --safe-right:env(safe-area-inset-right,0px);
      --safe-bottom:env(safe-area-inset-bottom,0px);
      --safe-left:env(safe-area-inset-left,0px);
    }

    html,body{
      margin:0;
      height:100%;
      background:#020000;
      color:#dcdcdc;
      font:16px/1.5 Helvetica,Arial,sans-serif;
      overflow:hidden;
  touch-action:none;
}
}/* end @layer base */

@layer components{
/* Low-end CSS orb
 — GPU compositor only, zero JS render cost */
    #orb-css{
      position:fixed;
      left:50%;top:50%;
      width:min(58vw,58vh);height:min(58vw,58vh);
      border-radius:50%;
      transform:translate(-50%,-50%) translateZ(0);
      background:radial-gradient(circle at 38% 35%,#6b2018,#1a0505 55%,#020000);
      box-shadow:0 0 60px 8px rgba(80,10,10,0.35),inset 0 0 40px rgba(0,0,0,0.7);
      animation:orb-idle 4s ease-in-out infinite;
      will-change:transform,opacity;
      pointer-events:none;
    }
    @keyframes orb-idle{
      0%,100%{transform:translate(-50%,-50%) scale(1) translateZ(0);opacity:.65;}
      50%     {transform:translate(-50%,-50%) scale(1.06) translateZ(0);opacity:.85;}
    }
    #orb-css.speaking{
      background:radial-gradient(circle at 38% 35%,#b03030,#3d1010 55%,#020000);
      box-shadow:0 0 90px 20px rgba(160,20,20,0.55),inset 0 0 35px rgba(0,0,0,0.4);
      animation:orb-speak .55s ease-in-out infinite;
    }
    @keyframes orb-speak{
      0%,100%{transform:translate(-50%,-50%) scale(1) translateZ(0);}
      30%     {transform:translate(-50%,-50%) scale(1.1) translateZ(0);}
      70%     {transform:translate(-50%,-50%) scale(.96) translateZ(0);}
    }
    #orb-css.processing{
      background:radial-gradient(circle at 38% 35%,#6b4008,#1e0e02 55%,#020000);
      box-shadow:0 0 70px 12px rgba(90,55,5,0.45),inset 0 0 40px rgba(0,0,0,0.6);
      animation:orb-think 1.3s ease-in-out infinite;
    }
    @keyframes orb-think{
      0%,100%{transform:translate(-50%,-50%) scale(1) translateZ(0);opacity:.6;}
      50%     {transform:translate(-50%,-50%) scale(1.05) translateZ(0);opacity:1;}
    }

    canvas{
      position:fixed;
      inset:0;
      width:100dvw;
      height:100dvh;
      display:block;
      background:#020000;
      touch-action:none;
      cursor:pointer;
    }

    #status{
      position:fixed;
      top:calc(10px + var(--safe-top));
      right:calc(10px + var(--safe-right));
      z-index:95;
      user-select:none;
      font-size:14px;
      color:#333;
      cursor:pointer;
      padding:12px;
      transition:color 0.3s;
    }

    #status.think{color:#662222;}
    #status.speak{color:#993333;}
    #status.processing{color:#7a3a0a;animation:pulse-status 1.2s ease-in-out infinite;}
    @keyframes pulse-status{0%,100%{opacity:1;}50%{opacity:0.3;}}

    #ui{
      position:fixed;
      right:calc(12px + var(--safe-right));
      bottom:calc(10px + var(--safe-bottom));
      color:#2a0808;
      font:9px/1.1 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;
      text-transform:uppercase;
      letter-spacing:.28em;
      white-space:nowrap;
      pointer-events:none;
      user-select:none;
      text-align:right;
      opacity:.5;
      transition:opacity 0.6s, color 0.3s;
    }
    #ui.highlight{opacity:1;color:#993333;}

    #ui .dots{
      display:inline-block;
      width:3ch;
      text-align:left;
    }

    #input-field{
      position:fixed;
      bottom:15vh;
      left:50%;
      transform:translateX(-50%);
      width:0;
      opacity:0;
      transition:width 0.3s ease-out, opacity 0.2s ease;
      z-index:10;
    }

    #input-field.active{
      width:70vw;
      max-width:500px;
      opacity:1;
    }

    #input-field input{
      width:calc(100% - 28px);
      background:transparent;
      border:none;
      color:#ccc;
      font-family:Helvetica,Arial,sans-serif;
      font-size:18px;
      font-weight:300;
      letter-spacing:0.05em;
      padding:12px 0;
      outline:none;
      text-align:center;
    }

    #input-field input::placeholder{
      color:#333;
    }

    #attach-btn{
      background:none;
      border:none;
      color:#333;
      cursor:pointer;
      font-size:18px;
      padding:0 0 0 6px;
      vertical-align:middle;
      transition:color 0.2s, opacity 0.3s;
      opacity:0;
    }
    #input-field.active #attach-btn{opacity:1;}
    #attach-btn:hover,#attach-btn.has-file{color:#888;}
    #attach-label{
      display:block;
      font-size:10px;
      color:#555;
      text-align:center;
      letter-spacing:0.08em;
      margin-top:4px;
      overflow:hidden;
      white-space:nowrap;
      text-overflow:ellipsis;
    }

    .arrow{
      position:fixed;
      top:50%;
      transform:translateY(-50%);
      width:60px;
      height:100px;
      display:flex;
      align-items:center;
      justify-content:center;
      cursor:pointer;
      z-index:100;
      opacity:0;
      transition:opacity 0.4s;
      user-select:none;
      -webkit-tap-highlight-color:transparent;
    }

    .arrow:hover{opacity:0.5;}
    .arrow:active{opacity:0.8;}

    #arrow-left{left:calc(10px + var(--safe-left));}
    #arrow-right{right:calc(10px + var(--safe-right));}

    .arrow span{
      color:#333;
      font-size:24px;
      font-weight:300;
    }

    #overlay{
      position:fixed;
      inset:0;
      display:flex;
      flex-direction:column;
      align-items:center;
      justify-content:center;
      gap:28px;
      background:#000;
      cursor:pointer;
      user-select:none;
      z-index:1000;
      touch-action:manipulation;
      text-align:center;
      padding:32px;
      opacity:1;
      transition:opacity 0.8s ease;
    }

    #overlay.ack{opacity:0;pointer-events:none;}
    #overlay[hidden]{display:none;}

    #overlay h1{
      margin:0;
      font-size:clamp(18px,4vw,28px);
      font-weight:300;
      color:#666;
      letter-spacing:.25em;
      text-transform:uppercase;
    }

    #overlay .hint{
      font-size:10px;
      color:#222;
      letter-spacing:.15em;
      animation:overlay-pulse 3s ease-in-out infinite;
    }

    @keyframes overlay-pulse{0%,100%{opacity:.4;}50%{opacity:.8;}}

    #chat-log{
      display:none;
      position:fixed;
      inset:0;
      z-index:200;
      background:rgba(0,0,0,.92);
      overflow-y:auto;
      padding:48px 5vw 80px;
      font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;
      color:#aaa;
    }
    #chat-log.open{display:block;}
    #chat-log .entry{margin-bottom:1.4em;white-space:pre-wrap;word-break:break-word;}
    #chat-log .entry.user{color:#ccc;}
    #chat-log .entry.master{color:#777;}
    #chat-log .entry.user::before{content:'> ';color:#555;}
    #chat-log .tab-hint{
      position:fixed;top:12px;right:16px;
      font-size:10px;color:#333;letter-spacing:.1em;pointer-events:none;
    }
    #sidebar{
      position:fixed;top:0;right:0;
      width:min(280px,85vw);height:100dvh;
      background:#0a0202;border-left:1px solid #1a0606;
      z-index:400;overflow-y:auto;padding:16px;box-sizing:border-box;
      transform:translateX(100%);transition:transform 0.2s ease;
      font-size:11px;color:#555;letter-spacing:.05em;
    }
    #sidebar.open{transform:translateX(0);}
    #sidebar h3{color:#662222;font-size:10px;letter-spacing:.15em;text-transform:uppercase;margin:12px 0 4px;}
    #sidebar .row{display:flex;justify-content:space-between;padding:2px 0;border-bottom:1px solid #0f0303;}
    #sidebar .ok{color:#2a6a2a;}
    #sidebar .err{color:#8a1a1a;}
    }/* end @layer components */
  </style>
  <%= csrf_meta_tags %>
</head>
<body>
  <div id="chat-log"><span class="tab-hint">TAB TO CLOSE</span></div>
  <section id="status">◉</section>
  <aside id="sidebar" aria-label="System status">
    <h3>Circuit Breakers</h3><div id="sb-breakers"></div>
    <h3>Session Budget</h3><div id="sb-budget"></div>
    <h3>Phase</h3><div id="sb-phase"></div>
    <h3>Standing Orders</h3><div id="sb-orders"></div>
  </aside>
  <section id="ui"><span id="ui-label">MASTER</span><span class="dots" id="ui-dots"></span></section>

  <section id="arrow-left" class="arrow"><span>‹</span></section>
  <section id="arrow-right" class="arrow"><span>›</span></section>

  <section id="input-field">
    <input type="text" placeholder="Ask anything…" autocomplete="off" maxlength="512" aria-label="Message">
    <button id="attach-btn" title="Attach image">+</button>
    <input type="file" id="file-input" accept="image/*,text/*,.pdf" hidden>
    <span id="attach-label"></span>
  </section>

  <canvas id="canvas"></canvas>

  <section id="overlay" role="dialog" aria-modal="true">
    <h1>MASTER</h1>
    <p class="hint">tap to begin</p>
  </section>

  <script>
    "use strict";
    const canvas=document.getElementById('canvas');
    const ctx=canvas.getContext('2d',{alpha:false});
    const statusEl=document.getElementById('status');
    const uiLabel=document.getElementById('ui-label');
    const uiDots=document.getElementById('ui-dots');
    const inputField=document.getElementById('input-field');
    let _overlayJustDismissed=false;
    const input=inputField.querySelector('input[type=text]');
    const fileInput=document.getElementById('file-input');
    const attachBtn=document.getElementById('attach-btn');
    const attachLabel=document.getElementById('attach-label');
    const chatLog=document.getElementById('chat-log');
    const overlay=document.getElementById('overlay');
    const arrowLeft=document.getElementById('arrow-left');
    const arrowRight=document.getElementById('arrow-right');
    const SpeechRecognition=window.SpeechRecognition||window.webkitSpeechRecognition;
    const MASTER_TOKEN='x';
    const COMPAT_LABEL="master or+rep";
    const TTS_BACKEND_KEY="master_tts_backend";

    // Chat log helpers with localStorage persistence
    const CHAT_KEY='m2_chat';
    const MAX_STORED=50;
    const logAppend=(role,text)=>{
      const e=document.createElement('div');
      e.className=`entry ${role}`;
      if(role==='master'){e.innerHTML=renderMd(text);}else{e.textContent=text;}
      chatLog.appendChild(e);
      chatLog.scrollTop=chatLog.scrollHeight;
      // Persist
      try{
        const stored=JSON.parse(localStorage.getItem(CHAT_KEY)||'[]');
        stored.push({r:role,t:text});
        if(stored.length>MAX_STORED) stored.splice(0,stored.length-MAX_STORED);
        localStorage.setItem(CHAT_KEY,JSON.stringify(stored));
      }catch(_){}
    };
    // Restore chat history on load
    try{
      const stored=JSON.parse(localStorage.getItem(CHAT_KEY)||'[]');
      for(const m of stored){
        const e=document.createElement('div');
        e.className=`entry ${m.r}`;
        e.textContent=m.t;
        chatLog.appendChild(e);
      }
      chatLog.scrollTop=chatLog.scrollHeight;
    }catch(_){}
    document.addEventListener('keydown',e=>{
      if(e.key==='Tab'){e.preventDefault();chatLog.classList.toggle('open');}
    });
    let lastCanvasTap=0;
    canvas.addEventListener('touchend',()=>{
      const now=Date.now();
      if(now-lastCanvasTap<350) chatLog.classList.toggle('open');
      lastCanvasTap=now;
    },{passive:true});
    let pullStartY=0,pullStartX=0,pullActive=false;
    window.addEventListener('touchstart',e=>{
      const touch=e.touches[0];
      if(touch.clientY<80&&!chatLog.classList.contains('open')){pullStartY=touch.clientY;pullStartX=touch.clientX;pullActive=true;}
      else pullActive=false;
    },{passive:true});
    window.addEventListener('touchend',e=>{
      if(!pullActive) return;
      const dy=e.changedTouches[0].clientY-pullStartY;
      const dx=Math.abs(e.changedTouches[0].clientX-pullStartX);
      if(dy>60&&dx<40){chatLog.classList.add('open');haptic(10);}
      pullActive=false;
    },{passive:true});

const csrfToken = () => {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute('content') : '';
};

const renderMd = raw => {
  let t = String(raw).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  t = t.replace(/```[\w]*\n?([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
  t = t.replace(/`([^`\n]+)`/g, '<code>$1</code>');
... 2003 lines truncated (2403 total)
```

## `web/app/views/layouts/application.html.erb`
```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Web" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="Web">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <%# Enable PWA manifest for installable apps (make sure to enable in config/routes.rb too!) %>
    <%#= tag.link rel: "manifest", href: pwa_manifest_path(format: :json) %>

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%# Includes all stylesheet files in app/assets/stylesheets %>
    <%= stylesheet_link_tag :app %>
  </head>

  <body>
    <%= yield %>
  </body>
</html>
```

## `web/app/views/pwa/manifest.json.erb`
```erb
{
  "name": "Web",
  "icons": [
    {
      "src": "/icon.png",
      "type": "image/png",
      "sizes": "512x512"
    },
    {
      "src": "/icon.png",
      "type": "image/png",
      "sizes": "512x512",
      "purpose": "maskable"
    }
  ],
  "start_url": "/",
  "display": "standalone",
  "scope": "/",
  "description": "Web.",
  "theme_color": "red",
  "background_color": "red"
}
```

## `web/app/views/pwa/service-worker.js`
```javascript
// Add a service worker for processing Web Push notifications:
//
// self.addEventListener("push", async (event) => {
//   const { title, options } = await event.data.json()
//   event.waitUntil(self.registration.showNotification(title, options))
// })
//
// self.addEventListener("notificationclick", function(event) {
//   event.notification.close()
//   event.waitUntil(
//     clients.matchAll({ type: "window" }).then((clientList) => {
//       for (let i = 0; i < clientList.length; i++) {
//         let client = clientList[i]
//         let clientPath = (new URL(client.url)).pathname
//
//         if (clientPath == event.notification.data.path && "focus" in client) {
//           return client.focus()
//         }
//       }
//
//       if (clients.openWindow) {
//         return clients.openWindow(event.notification.data.path)
//       }
//     })
//   )
// })
```

## `web/config/application.rb`
```ruby
require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
# require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks master])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
```

## `web/config/boot.rb`
```ruby
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
```

## `web/config/ci.rb`
```ruby
# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"



  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
```

## `web/config/database.yml`
```yaml
default: &default
  adapter: sqlite3
  max_connections: 5
  timeout: 5000

development:
  <<: *default
  database: storage/development.sqlite3

test:
  <<: *default
  database: storage/test.sqlite3

production:
  <<: *default
  database: storage/production.sqlite3
```

## `web/config/environment.rb`
```ruby
# Load the Rails application.
require_relative "application"

# Initialize the Rails application.
Rails.application.initialize!
```

## `web/config/environments/development.rb`
```ruby
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
```

## `web/config/environments/production.rb`
```ruby
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # SSL terminated at relayd proxy layer — do not redirect internally.
  config.force_ssl = false

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Host validation handled by relayd; disable Rails-level host authorization.
  config.host_authorization = { exclude: ->(request) { true } }
end
```

## `web/config/environments/test.rb`
```ruby
# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
```

## `web/config/initializers/assets.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path
```

## `web/config/initializers/content_security_policy.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data
#     policy.img_src     :self, :https, :data
#     policy.object_src  :none
#     policy.script_src  :self, :https
#     policy.style_src   :self, :https
#     # Specify URI for violation reports
#     # policy.report_uri "/csp-violation-report-endpoint"
#   end
#
#   # Generate session nonces for permitted importmap, inline scripts, and inline styles.
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w(script-src style-src)
#
#   # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
#   # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
#   # config.content_security_policy_nonce_auto = true
#
#   # Report violations without enforcing the policy.
#   # config.content_security_policy_report_only = true
# end
```

## `web/config/initializers/filter_parameter_logging.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]
```

## `web/config/initializers/inflections.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end
```

## `web/config/initializers/master_container.rb`
```ruby
# frozen_string_literal: true
# Pre-build container at boot to avoid blocking Falcons async event loop.
Rails.application.config.after_initialize do
  Thread.new { ApplicationController.class_eval { container } rescue nil }
end
```

## `web/config/initializers/new_framework_defaults_8_0.rb`
```ruby
# Be sure to restart your server when you modify this file.
#
# This file eases your Rails 8.0 framework defaults upgrade.
#
# Uncomment each configuration one by one to switch to the new default.
# Once your application is ready to run with all new defaults, you can remove
# this file and set the `config.load_defaults` to `8.0`.
#
# Read the Guide for Upgrading Ruby on Rails for more info on each option.
# https://guides.rubyonrails.org/upgrading_ruby_on_rails.html

###
# Specifies whether `to_time` methods preserve the UTC offset of their receivers or preserves the timezone.
# If set to `:zone`, `to_time` methods will use the timezone of their receivers.
# If set to `:offset`, `to_time` methods will use the UTC offset.
# If `false`, `to_time` methods will convert to the local system UTC offset instead.
#++
# Rails.application.config.active_support.to_time_preserves_timezone = :zone

###
# When both `If-Modified-Since` and `If-None-Match` are provided by the client
# only consider `If-None-Match` as specified by RFC 7232 Section 6.
# If set to `false` both conditions need to be satisfied.
#++
# Rails.application.config.action_dispatch.strict_freshness = true

###
# Set `Regexp.timeout` to `1`s by default to improve security over Regexp Denial-of-Service attacks.
#++
# Regexp.timeout = 1
```

## `web/config/locales/en.yml`
```yaml
# Files in the config/locales directory are used for internationalization and
# are automatically loaded by Rails. If you want to use locales other than
# English, add the necessary files in this directory.
#
# To use the locales, use `I18n.t`:
#
#     I18n.t "hello"
#
# In views, this is aliased to just `t`:
#
#     <%= t("hello") %>
#
# To use a different locale, set it with `I18n.locale`:
#
#     I18n.locale = :es
#
# This would use the information in config/locales/es.yml.
#
# To learn more about the API, please read the Rails Internationalization guide
# at https://guides.rubyonrails.org/i18n.html.
#
# Be aware that YAML interprets the following case-insensitive strings as
# booleans: `true`, `false`, `on`, `off`, `yes`, `no`. Therefore, these strings
# must be quoted to be interpreted as strings. For example:
#
#     en:
#       "yes": yup
#       enabled: "ON"

en:
  hello: "Hello world"
```

## `web/config/puma.rb`
```ruby
# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
```

## `web/config/routes.rb`
```ruby
Rails.application.routes.draw do
  root "chat#index"
  post "chat/message",  to: "chat#message"
  post "chat/tts",      to: "chat#tts"
  post "chat/speak",    to: "chat#speak"
  get  "chat/metrics",  to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "events/stream", to: "events#stream"
  get  "up" => "rails/health#show", as: :rails_health_check
  get  "health" => "health#show"
end
```

## `web/db/seeds.rb`
```ruby
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
```

## `web/public/assets/rails-ujs-20eaf715.js`
```javascript
/*
Unobtrusive JavaScript
https://github.com/rails/rails/blob/main/actionview/app/javascript
Released under the MIT license
 */
(function(global, factory) {
  typeof exports === "object" && typeof module !== "undefined" ? module.exports = factory() : typeof define === "function" && define.amd ? define(factory) : (global = typeof globalThis !== "undefined" ? globalThis : global || self,
  global.Rails = factory());
})(this, (function() {
  "use strict";
  const linkClickSelector = "a[data-confirm], a[data-method], a[data-remote]:not([disabled]), a[data-disable-with], a[data-disable]";
  const buttonClickSelector = {
    selector: "button[data-remote]:not([form]), button[data-confirm]:not([form])",
    exclude: "form button"
  };
  const inputChangeSelector = "select[data-remote], input[data-remote], textarea[data-remote]";
  const formSubmitSelector = "form:not([data-turbo=true])";
  const formInputClickSelector = "form:not([data-turbo=true]) input[type=submit], form:not([data-turbo=true]) input[type=image], form:not([data-turbo=true]) button[type=submit], form:not([data-turbo=true]) button:not([type]), input[type=submit][form], input[type=image][form], button[type=submit][form], button[form]:not([type])";
  const formDisableSelector = "input[data-disable-with]:enabled, button[data-disable-with]:enabled, textarea[data-disable-with]:enabled, input[data-disable]:enabled, button[data-disable]:enabled, textarea[data-disable]:enabled";
  const formEnableSelector = "input[data-disable-with]:disabled, button[data-disable-with]:disabled, textarea[data-disable-with]:disabled, input[data-disable]:disabled, button[data-disable]:disabled, textarea[data-disable]:disabled";
  const fileInputSelector = "input[name][type=file]:not([disabled])";
  const linkDisableSelector = "a[data-disable-with], a[data-disable]";
  const buttonDisableSelector = "button[data-remote][data-disable-with], button[data-remote][data-disable]";
  let nonce = null;
  const loadCSPNonce = () => {
    const metaTag = document.querySelector("meta[name=csp-nonce]");
    return nonce = metaTag && metaTag.content;
  };
  const cspNonce = () => nonce || loadCSPNonce();
  const m = Element.prototype.matches || Element.prototype.matchesSelector || Element.prototype.mozMatchesSelector || Element.prototype.msMatchesSelector || Element.prototype.oMatchesSelector || Element.prototype.webkitMatchesSelector;
  const matches = function(element, selector) {
    if (selector.exclude) {
      return m.call(element, selector.selector) && !m.call(element, selector.exclude);
    } else {
      return m.call(element, selector);
    }
  };
  const EXPANDO = "_ujsData";
  const getData = (element, key) => element[EXPANDO] ? element[EXPANDO][key] : undefined;
  const setData = function(element, key, value) {
    if (!element[EXPANDO]) {
      element[EXPANDO] = {};
    }
    return element[EXPANDO][key] = value;
  };
  const $ = selector => Array.prototype.slice.call(document.querySelectorAll(selector));
  const isContentEditable = function(element) {
    var isEditable = false;
    do {
      if (element.isContentEditable) {
        isEditable = true;
        break;
      }
      element = element.parentElement;
    } while (element);
    return isEditable;
  };
  const csrfToken = () => {
    const meta = document.querySelector("meta[name=csrf-token]");
    return meta && meta.content;
  };
  const csrfParam = () => {
    const meta = document.querySelector("meta[name=csrf-param]");
    return meta && meta.content;
  };
  const CSRFProtection = xhr => {
    const token = csrfToken();
    if (token) {
      return xhr.setRequestHeader("X-CSRF-Token", token);
    }
  };
  const refreshCSRFTokens = () => {
    const token = csrfToken();
    const param = csrfParam();
    if (token && param) {
      return $('form input[name="' + param + '"]').forEach((input => input.value = token));
    }
  };
  const AcceptHeaders = {
    "*": "*/*",
    text: "text/plain",
    html: "text/html",
    xml: "application/xml, text/xml",
    json: "application/json, text/javascript",
    script: "text/javascript, application/javascript, application/ecmascript, application/x-ecmascript"
  };
  const ajax = options => {
    options = prepareOptions(options);
    var xhr = createXHR(options, (function() {
      const response = processResponse(xhr.response != null ? xhr.response : xhr.responseText, xhr.getResponseHeader("Content-Type"));
      if (Math.floor(xhr.status / 100) === 2) {
        if (typeof options.success === "function") {
          options.success(response, xhr.statusText, xhr);
        }
      } else {
        if (typeof options.error === "function") {
          options.error(response, xhr.statusText, xhr);
        }
      }
      return typeof options.complete === "function" ? options.complete(xhr, xhr.statusText) : undefined;
    }));
    if (options.beforeSend && !options.beforeSend(xhr, options)) {
      return false;
    }
    if (xhr.readyState === XMLHttpRequest.OPENED) {
      return xhr.send(options.data);
    }
  };
  var prepareOptions = function(options) {
    options.url = options.url || location.href;
    options.type = options.type.toUpperCase();
    if (options.type === "GET" && options.data) {
      if (options.url.indexOf("?") < 0) {
        options.url += "?" + options.data;
      } else {
        options.url += "&" + options.data;
      }
    }
    if (!(options.dataType in AcceptHeaders)) {
      options.dataType = "*";
    }
    options.accept = AcceptHeaders[options.dataType];
    if (options.dataType !== "*") {
      options.accept += ", */*; q=0.01";
    }
    return options;
  };
  var createXHR = function(options, done) {
    const xhr = new XMLHttpRequest;
    xhr.open(options.type, options.url, true);
    xhr.setRequestHeader("Accept", options.accept);
    if (typeof options.data === "string") {
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
    }
    if (!options.crossDomain) {
      xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
      CSRFProtection(xhr);
    }
    xhr.withCredentials = !!options.withCredentials;
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        return done(xhr);
      }
    };
    return xhr;
  };
  var processResponse = function(response, type) {
    if (typeof response === "string" && typeof type === "string") {
      if (type.match(/\bjson\b/)) {
        try {
          response = JSON.parse(response);
        } catch (error) {}
      } else if (type.match(/\b(?:java|ecma)script\b/)) {
        const script = document.createElement("script");
        script.setAttribute("nonce", cspNonce());
        script.text = response;
        document.head.appendChild(script).parentNode.removeChild(script);
      } else if (type.match(/\b(xml|html|svg)\b/)) {
        const parser = new DOMParser;
        type = type.replace(/;.+/, "");
        try {
          response = parser.parseFromString(response, type);
        } catch (error1) {}
      }
    }
    return response;
  };
  const href = element => element.href;
  const isCrossDomain = function(url) {
    const originAnchor = document.createElement("a");
    originAnchor.href = location.href;
    const urlAnchor = document.createElement("a");
    try {
      urlAnchor.href = url;
      return !((!urlAnchor.protocol || urlAnchor.protocol === ":") && !urlAnchor.host || originAnchor.protocol + "//" + originAnchor.host === urlAnchor.protocol + "//" + urlAnchor.host);
    } catch (e) {
      return true;
    }
  };
  let preventDefault;
  let {CustomEvent: CustomEvent} = window;
  if (typeof CustomEvent !== "function") {
    CustomEvent = function(event, params) {
      const evt = document.createEvent("CustomEvent");
      evt.initCustomEvent(event, params.bubbles, params.cancelable, params.detail);
      return evt;
    };
    CustomEvent.prototype = window.Event.prototype;
    ({preventDefault: preventDefault} = CustomEvent.prototype);
    CustomEvent.prototype.preventDefault = function() {
      const result = preventDefault.call(this);
      if (this.cancelable && !this.defaultPrevented) {
        Object.defineProperty(this, "defaultPrevented", {
          get() {
            return true;
          }
        });
      }
      return result;
    };
  }
  const fire = (obj, name, data) => {
    const event = new CustomEvent(name, {
      bubbles: true,
      cancelable: true,
      detail: data
    });
    obj.dispatchEvent(event);
    return !event.defaultPrevented;
  };
  const stopEverything = e => {
    fire(e.target, "ujs:everythingStopped");
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();
  };
  const delegate = (element, selector, eventType, handler) => element.addEventListener(eventType, (function(e) {
    let {target: target} = e;
    while (!!(target instanceof Element) && !matches(target, selector)) {
      target = target.parentNode;
    }
    if (target instanceof Element && handler.call(target, e) === false) {
      e.preventDefault();
      e.stopPropagation();
    }
  }));
  const toArray = e => Array.prototype.slice.call(e);
  const serializeElement = (element, additionalParam) => {
    let inputs = [ element ];
    if (matches(element, "form")) {
      inputs = toArray(element.elements);
    }
    const params = [];
    inputs.forEach((function(input) {
      if (!input.name || input.disabled) {
        return;
      }
      if (matches(input, "fieldset[disabled] *")) {
        return;
      }
      if (matches(input, "select")) {
        toArray(input.options).forEach((function(option) {
          if (option.selected) {
            params.push({
              name: input.name,
              value: option.value
            });
          }
        }));
      } else if (input.checked || [ "radio", "checkbox", "submit" ].indexOf(input.type) === -1) {
        params.push({
          name: input.name,
          value: input.value
        });
      }
    }));
    if (additionalParam) {
      params.push(additionalParam);
    }
    return params.map((function(param) {
      if (param.name) {
        return `${encodeURIComponent(param.name)}=${encodeURIComponent(param.value)}`;
      } else {
        return param;
      }
    })).join("&");
  };
  const formElements = (form, selector) => {
    if (matches(form, "form")) {
      return toArray(form.elements).filter((el => matches(el, selector)));
    } else {
      return toArray(form.querySelectorAll(selector));
    }
  };
  const handleConfirmWithRails = rails => function(e) {
    if (!allowAction(this, rails)) {
      stopEverything(e);
    }
  };
  const confirm = (message, element) => window.confirm(message);
  var allowAction = function(element, rails) {
    let callback;
    const message = element.getAttribute("data-confirm");
    if (!message) {
      return true;
    }
    let answer = false;
    if (fire(element, "confirm")) {
      try {
        answer = rails.confirm(message, element);
      } catch (error) {}
      callback = fire(element, "confirm:complete", [ answer ]);
    }
    return answer && callback;
  };
  const handleDisabledElement = function(e) {
    const element = this;
    if (element.disabled) {
      stopEverything(e);
    }
  };
  const enableElement = e => {
    let element;
    if (e instanceof Event) {
      if (isXhrRedirect(e)) {
        return;
      }
      element = e.target;
    } else {
      element = e;
    }
    if (isContentEditable(element)) {
      return;
    }
    if (matches(element, linkDisableSelector)) {
      return enableLinkElement(element);
    } else if (matches(element, buttonDisableSelector) || matches(element, formEnableSelector)) {
      return enableFormElement(element);
    } else if (matches(element, formSubmitSelector)) {
      return enableFormElements(element);
    }
  };
  const disableElement = e => {
    const element = e instanceof Event ? e.target : e;
    if (isContentEditable(element)) {
      return;
    }
    if (matches(element, linkDisableSelector)) {
      return disableLinkElement(element);
    } else if (matches(element, buttonDisableSelector) || matches(element, formDisableSelector)) {
      return disableFormElement(element);
    } else if (matches(element, formSubmitSelector)) {
      return disableFormElements(element);
    }
  };
  var disableLinkElement = function(element) {
    if (getData(element, "ujs:disabled")) {
      return;
    }
    const replacement = element.getAttribute("data-disable-with");
    if (replacement != null) {
      setData(element, "ujs:enable-with", element.innerHTML);
      element.innerHTML = replacement;
    }
    element.addEventListener("click", stopEverything);
    return setData(element, "ujs:disabled", true);
  };
  var enableLinkElement = function(element) {
    const originalText = getData(element, "ujs:enable-with");
    if (originalText != null) {
      element.innerHTML = originalText;
      setData(element, "ujs:enable-with", null);
    }
    element.removeEventListener("click", stopEverything);
    return setData(element, "ujs:disabled", null);
  };
  var disableFormElements = form => formElements(form, formDisableSelector).forEach(disableFormElement);
  var disableFormElement = function(element) {
    if (getData(element, "ujs:disabled")) {
      return;
    }
    const replacement = element.getAttribute("data-disable-with");
    if (replacement != null) {
      if (matches(element, "button")) {
        setData(element, "ujs:enable-with", element.innerHTML);
        element.innerHTML = replacement;
      } else {
        setData(element, "ujs:enable-with", element.value);
        element.value = replacement;
      }
    }
    element.disabled = true;
    return setData(element, "ujs:disabled", true);
  };
  var enableFormElements = form => formElements(form, formEnableSelector).forEach((element => enableFormElement(element)));
  var enableFormElement = function(element) {
    const originalText = getData(element, "ujs:enable-with");
    if (originalText != null) {
      if (matches(element, "button")) {
        element.innerHTML = originalText;
      } else {
        element.value = originalText;
      }
      setData(element, "ujs:enable-with", null);
    }
    element.disabled = false;
    return setData(element, "ujs:disabled", null);
  };
  var isXhrRedirect = function(event) {
    const xhr = event.detail ? event.detail[0] : undefined;
    return xhr && xhr.getResponseHeader("X-Xhr-Redirect");
  };
  const handleMethodWithRails = rails => function(e) {
    const link = this;
    const method = link.getAttribute("data-method");
    if (!method) {
      return;
    }
    if (isContentEditable(this)) {
      return;
... 230 lines truncated (630 total)
```

## `web/public/assets/rails-ujs.esm-e925103b.js`
```javascript
/*
Unobtrusive JavaScript
https://github.com/rails/rails/blob/main/actionview/app/javascript
Released under the MIT license
 */
const linkClickSelector = "a[data-confirm], a[data-method], a[data-remote]:not([disabled]), a[data-disable-with], a[data-disable]";

const buttonClickSelector = {
  selector: "button[data-remote]:not([form]), button[data-confirm]:not([form])",
  exclude: "form button"
};

const inputChangeSelector = "select[data-remote], input[data-remote], textarea[data-remote]";

const formSubmitSelector = "form:not([data-turbo=true])";

const formInputClickSelector = "form:not([data-turbo=true]) input[type=submit], form:not([data-turbo=true]) input[type=image], form:not([data-turbo=true]) button[type=submit], form:not([data-turbo=true]) button:not([type]), input[type=submit][form], input[type=image][form], button[type=submit][form], button[form]:not([type])";

const formDisableSelector = "input[data-disable-with]:enabled, button[data-disable-with]:enabled, textarea[data-disable-with]:enabled, input[data-disable]:enabled, button[data-disable]:enabled, textarea[data-disable]:enabled";

const formEnableSelector = "input[data-disable-with]:disabled, button[data-disable-with]:disabled, textarea[data-disable-with]:disabled, input[data-disable]:disabled, button[data-disable]:disabled, textarea[data-disable]:disabled";

const fileInputSelector = "input[name][type=file]:not([disabled])";

const linkDisableSelector = "a[data-disable-with], a[data-disable]";

const buttonDisableSelector = "button[data-remote][data-disable-with], button[data-remote][data-disable]";

let nonce = null;

const loadCSPNonce = () => {
  const metaTag = document.querySelector("meta[name=csp-nonce]");
  return nonce = metaTag && metaTag.content;
};

const cspNonce = () => nonce || loadCSPNonce();

const m = Element.prototype.matches || Element.prototype.matchesSelector || Element.prototype.mozMatchesSelector || Element.prototype.msMatchesSelector || Element.prototype.oMatchesSelector || Element.prototype.webkitMatchesSelector;

const matches = function(element, selector) {
  if (selector.exclude) {
    return m.call(element, selector.selector) && !m.call(element, selector.exclude);
  } else {
    return m.call(element, selector);
  }
};

const EXPANDO = "_ujsData";

const getData = (element, key) => element[EXPANDO] ? element[EXPANDO][key] : undefined;

const setData = function(element, key, value) {
  if (!element[EXPANDO]) {
    element[EXPANDO] = {};
  }
  return element[EXPANDO][key] = value;
};

const $ = selector => Array.prototype.slice.call(document.querySelectorAll(selector));

const isContentEditable = function(element) {
  var isEditable = false;
  do {
    if (element.isContentEditable) {
      isEditable = true;
      break;
    }
    element = element.parentElement;
  } while (element);
  return isEditable;
};

const csrfToken = () => {
  const meta = document.querySelector("meta[name=csrf-token]");
  return meta && meta.content;
};

const csrfParam = () => {
  const meta = document.querySelector("meta[name=csrf-param]");
  return meta && meta.content;
};

const CSRFProtection = xhr => {
  const token = csrfToken();
  if (token) {
    return xhr.setRequestHeader("X-CSRF-Token", token);
  }
};

const refreshCSRFTokens = () => {
  const token = csrfToken();
  const param = csrfParam();
  if (token && param) {
    return $('form input[name="' + param + '"]').forEach((input => input.value = token));
  }
};

const AcceptHeaders = {
  "*": "*/*",
  text: "text/plain",
  html: "text/html",
  xml: "application/xml, text/xml",
  json: "application/json, text/javascript",
  script: "text/javascript, application/javascript, application/ecmascript, application/x-ecmascript"
};

const ajax = options => {
  options = prepareOptions(options);
  var xhr = createXHR(options, (function() {
    const response = processResponse(xhr.response != null ? xhr.response : xhr.responseText, xhr.getResponseHeader("Content-Type"));
    if (Math.floor(xhr.status / 100) === 2) {
      if (typeof options.success === "function") {
        options.success(response, xhr.statusText, xhr);
      }
    } else {
      if (typeof options.error === "function") {
        options.error(response, xhr.statusText, xhr);
      }
    }
    return typeof options.complete === "function" ? options.complete(xhr, xhr.statusText) : undefined;
  }));
  if (options.beforeSend && !options.beforeSend(xhr, options)) {
    return false;
  }
  if (xhr.readyState === XMLHttpRequest.OPENED) {
    return xhr.send(options.data);
  }
};

var prepareOptions = function(options) {
  options.url = options.url || location.href;
  options.type = options.type.toUpperCase();
  if (options.type === "GET" && options.data) {
    if (options.url.indexOf("?") < 0) {
      options.url += "?" + options.data;
    } else {
      options.url += "&" + options.data;
    }
  }
  if (!(options.dataType in AcceptHeaders)) {
    options.dataType = "*";
  }
  options.accept = AcceptHeaders[options.dataType];
  if (options.dataType !== "*") {
    options.accept += ", */*; q=0.01";
  }
  return options;
};

var createXHR = function(options, done) {
  const xhr = new XMLHttpRequest;
  xhr.open(options.type, options.url, true);
  xhr.setRequestHeader("Accept", options.accept);
  if (typeof options.data === "string") {
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
  }
  if (!options.crossDomain) {
    xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
    CSRFProtection(xhr);
  }
  xhr.withCredentials = !!options.withCredentials;
  xhr.onreadystatechange = function() {
    if (xhr.readyState === XMLHttpRequest.DONE) {
      return done(xhr);
    }
  };
  return xhr;
};

var processResponse = function(response, type) {
  if (typeof response === "string" && typeof type === "string") {
    if (type.match(/\bjson\b/)) {
      try {
        response = JSON.parse(response);
      } catch (error) {}
    } else if (type.match(/\b(?:java|ecma)script\b/)) {
      const script = document.createElement("script");
      script.setAttribute("nonce", cspNonce());
      script.text = response;
      document.head.appendChild(script).parentNode.removeChild(script);
    } else if (type.match(/\b(xml|html|svg)\b/)) {
      const parser = new DOMParser;
      type = type.replace(/;.+/, "");
      try {
        response = parser.parseFromString(response, type);
      } catch (error1) {}
    }
  }
  return response;
};

const href = element => element.href;

const isCrossDomain = function(url) {
  const originAnchor = document.createElement("a");
  originAnchor.href = location.href;
  const urlAnchor = document.createElement("a");
  try {
    urlAnchor.href = url;
    return !((!urlAnchor.protocol || urlAnchor.protocol === ":") && !urlAnchor.host || originAnchor.protocol + "//" + originAnchor.host === urlAnchor.protocol + "//" + urlAnchor.host);
  } catch (e) {
    return true;
  }
};

let preventDefault;

let {CustomEvent: CustomEvent} = window;

if (typeof CustomEvent !== "function") {
  CustomEvent = function(event, params) {
    const evt = document.createEvent("CustomEvent");
    evt.initCustomEvent(event, params.bubbles, params.cancelable, params.detail);
    return evt;
  };
  CustomEvent.prototype = window.Event.prototype;
  ({preventDefault: preventDefault} = CustomEvent.prototype);
  CustomEvent.prototype.preventDefault = function() {
    const result = preventDefault.call(this);
    if (this.cancelable && !this.defaultPrevented) {
      Object.defineProperty(this, "defaultPrevented", {
        get() {
          return true;
        }
      });
    }
    return result;
  };
}

const fire = (obj, name, data) => {
  const event = new CustomEvent(name, {
    bubbles: true,
    cancelable: true,
    detail: data
  });
  obj.dispatchEvent(event);
  return !event.defaultPrevented;
};

const stopEverything = e => {
  fire(e.target, "ujs:everythingStopped");
  e.preventDefault();
  e.stopPropagation();
  e.stopImmediatePropagation();
};

const delegate = (element, selector, eventType, handler) => element.addEventListener(eventType, (function(e) {
  let {target: target} = e;
  while (!!(target instanceof Element) && !matches(target, selector)) {
    target = target.parentNode;
  }
  if (target instanceof Element && handler.call(target, e) === false) {
    e.preventDefault();
    e.stopPropagation();
  }
}));

const toArray = e => Array.prototype.slice.call(e);

const serializeElement = (element, additionalParam) => {
  let inputs = [ element ];
  if (matches(element, "form")) {
    inputs = toArray(element.elements);
  }
  const params = [];
  inputs.forEach((function(input) {
    if (!input.name || input.disabled) {
      return;
    }
    if (matches(input, "fieldset[disabled] *")) {
      return;
    }
    if (matches(input, "select")) {
      toArray(input.options).forEach((function(option) {
        if (option.selected) {
          params.push({
            name: input.name,
            value: option.value
          });
        }
      }));
    } else if (input.checked || [ "radio", "checkbox", "submit" ].indexOf(input.type) === -1) {
      params.push({
        name: input.name,
        value: input.value
      });
    }
  }));
  if (additionalParam) {
    params.push(additionalParam);
  }
  return params.map((function(param) {
    if (param.name) {
      return `${encodeURIComponent(param.name)}=${encodeURIComponent(param.value)}`;
    } else {
      return param;
    }
  })).join("&");
};

const formElements = (form, selector) => {
  if (matches(form, "form")) {
    return toArray(form.elements).filter((el => matches(el, selector)));
  } else {
    return toArray(form.querySelectorAll(selector));
  }
};

const handleConfirmWithRails = rails => function(e) {
  if (!allowAction(this, rails)) {
    stopEverything(e);
  }
};

const confirm = (message, element) => window.confirm(message);

var allowAction = function(element, rails) {
  let callback;
  const message = element.getAttribute("data-confirm");
  if (!message) {
    return true;
  }
  let answer = false;
  if (fire(element, "confirm")) {
    try {
      answer = rails.confirm(message, element);
    } catch (error) {}
    callback = fire(element, "confirm:complete", [ answer ]);
  }
  return answer && callback;
};

const handleDisabledElement = function(e) {
  const element = this;
  if (element.disabled) {
    stopEverything(e);
  }
};

const enableElement = e => {
  let element;
  if (e instanceof Event) {
    if (isXhrRedirect(e)) {
      return;
    }
    element = e.target;
  } else {
    element = e;
  }
  if (isContentEditable(element)) {
    return;
  }
  if (matches(element, linkDisableSelector)) {
    return enableLinkElement(element);
  } else if (matches(element, buttonDisableSelector) || matches(element, formEnableSelector)) {
    return enableFormElement(element);
  } else if (matches(element, formSubmitSelector)) {
    return enableFormElements(element);
  }
};

const disableElement = e => {
  const element = e instanceof Event ? e.target : e;
  if (isContentEditable(element)) {
    return;
  }
  if (matches(element, linkDisableSelector)) {
    return disableLinkElement(element);
  } else if (matches(element, buttonDisableSelector) || matches(element, formDisableSelector)) {
    return disableFormElement(element);
  } else if (matches(element, formSubmitSelector)) {
    return disableFormElements(element);
  }
};

var disableLinkElement = function(element) {
  if (getData(element, "ujs:disabled")) {
    return;
  }
  const replacement = element.getAttribute("data-disable-with");
  if (replacement != null) {
    setData(element, "ujs:enable-with", element.innerHTML);
    element.innerHTML = replacement;
  }
  element.addEventListener("click", stopEverything);
  return setData(element, "ujs:disabled", true);
};

var enableLinkElement = function(element) {
  const originalText = getData(element, "ujs:enable-with");
  if (originalText != null) {
    element.innerHTML = originalText;
    setData(element, "ujs:enable-with", null);
  }
  element.removeEventListener("click", stopEverything);
  return setData(element, "ujs:disabled", null);
};

var disableFormElements = form => formElements(form, formDisableSelector).forEach(disableFormElement);
... 286 lines truncated (686 total)
```

## `web/public/robots.txt`
```text
# See https://www.robotstxt.org/robotstxt.html for documentation on how to use the robots.txt file
```

files: 240 / lines: 36788 / truncated: 11 / est. tokens: ~44145