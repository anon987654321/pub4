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

**Communication style.** Two registers, do not mix them:
- *MASTER's own log/event lines* (boot banner, scheduler ticks, tool events): structured dmesg style — lowercase, terse, kernel-ish (`master@host ready`, `boot0: 26ms`, `model0 at openrouter`). The OpenBSD-dmesg boot banner is sacred — never remove it.
- *My conversational prose to the operator*: plain English, proper casing, full sentences. No dmesg style for chat replies. No headlines, no bullet lists without content, no hedging, no sycophancy.

**Never use ASCII line art in any output** — comments, log lines, CLI text, chat replies. Banned decorations: `===`, `----`, `•`, `|`, `›`, `‹`, banner boxes. Status indicators are bare prefixes (`ok:`, `err:`, `warn:`, `skip:`) — never `[ok]`, `[err]`, `[skip]` brackets.

**Banned in zsh scripts and SSH commands:** sed, awk, tr, grep, cut, head, tail, find, wc, sudo, perl, ruby (in zsh), dd, xargs
Use: zsh builtins, parameter expansion, `doas` for privilege, Ruby scripts for complex logic.

**External LLM context:** `cat ~/pub4/MASTER/CONVENTIONS.md` — dense reference distilled from data/*.yml for any LLM reviewing or editing MASTER.

**Use MASTER's own scan before external analysis:**
`eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle exec ruby exe/master`
Do not use external agents to find code issues when MASTER can scan itself.

**SSH file editing pattern.** Prefer direct edits over fix-script middlemen:
- Read whole files with `cat path` over SSH (avoid stitching grep + head fragments — confuses context).
- For non-trivial changes: write the new file content locally, then `scp` it up. No transient `/tmp/patch.rb` "fix script" indirection.
- For trivial in-place tweaks where a script truly is the right tool: write to `~/pub4/tmp/patch.rb`, run with `ruby ~/pub4/tmp/patch.rb`. Never use `ruby -i` with heredoc — empties the file on script error.

---

## Environment

| | |
|---|---|
| **Dev machine** | OpenBSD VPS · `dev@brgen.no` · `185.52.176.18` (wheel, passwordless doas) |
| **Password** | ask user at session start: `read -s 'VPS_PASS?VPS password: '` |
| **SSH** | `sshpass -p "$VPS_PASS" ssh -o StrictHostKeyChecking=no dev@185.52.176.18 'cmd'` |
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
| `ruby_style.yml` | Ruby 3.3+ rules, Rails 8+ stack, OpenBSD config, zsh banned commands. Includes html, css, typography, nielsen_heuristics, accessibility, parametric_design, cultural_sensitivity sections (restored Wave E from master4.yml). |
| `standing_orders.yml` | Current FSM state (UNCHANGE / REFACTOR / etc.) |
| `workflow.yml` | READ_FULL_FILES, READ_BEFORE_WRITE, scan depths, autoloop/sweep config, Zeitwerk inflections, anti-sprawl |
| `models.yml` | Tiered model table (default/strong/cheap/claude_code/local). Uses YAML anchors — load with `aliases: true`. `local:` tier = ollama_phi/llama/qwen, env-gated by OLLAMA_BASE_URL. |
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
| `lib/master/agent/llm_dispatch.rb` | Tool-list builder; filters fs-touching tools when `Thread.current[:master_visitor]` is set |
| `lib/master/why_explainer.rb` | Local lookup for `/why <id>` — laws, scan rules, anti-patterns, style keys. Falls back to LLM only on miss. |
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
- **Auth tiers** (added 2026-05-06):
  - `?token=...` → `session[:tier] = "authenticated"` → full tool access including filesystem
  - no token → `session[:tier] = "visitor"` → free chat with LLM, but `Thread.current[:master_visitor]` is set so `LlmDispatch#build_llm_tools` filters out every fs-touching tool. Visitor allow-list lives in `VISITOR_ALLOWED_TOOLS` (currently `AskLlm`, `WebSearch`).
  - `/up` and `/health` are always public.
- **Chat UI**: minimalist by design — black background, central orb, hidden text input (`#input-field` is `width:0; opacity:0` until activated). The mic-circle status indicator in the top-right (`#status`) is the click target that activates the input.

### CLI access

- The CLI REPL (`exe/master`) does **not** go through ApplicationController — it always has full tool access regardless of web auth state.
- When OpenRouter / Replicate credit is available, premium models route through normally via `model_router`. Free tier and `local:` (ollama) are the always-available fallbacks.

### Models

- **Default**: `nvidia/nemotron-3-super-120b-a12b:free` (OpenRouter free tier)
- **Fallback chain**: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash
- **Local tier** (env-gated by `OLLAMA_BASE_URL`): ollama_phi → ollama_llama → ollama_qwen — trust 0.40
- **Circuit breaker**: FAILURE_THRESHOLD=8, RATE_MAX=60

### Slash commands

`/scan [deep]`, `/sweep`, `/autoloop`, `/council`, `/crit <file|text>`, `/tts`, `/profile`, `/heartbeat`, `/orders`, `/soul`, `/dmesg`, `/why <law|scan_rule|anti_pattern|style.key>` (local lookup, LLM fallback only on miss).

---

## Design Priorities

1. **CLI REPL** — interactive agent, primary interface, full tool access
2. **Web UI + TTS** — secondary, two-tier auth (visitor / authenticated)
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

- **Never** use `sed`, `awk`, `tr`, `wc`, `head`, `tail`, `grep`, `find` — use zsh builtins or the editor's Grep/Glob tools
- **No tmp files** for simple operations — do it inline
- **No line noise** — keep commands clean and readable
- **Ruby only** — never Python
- **Read files**: `cat path` over SSH for whole-file reads. Do not stitch `grep` + `head` fragments — read the whole file once and reason from full context.
- **zsh array**: `lines=("${(@f)$(<file)}")`; last 50: `print -l $lines[-50,-1]`
- **Edit VPS files**: prefer direct local edit + `scp` over write-fix-script-and-run pattern. Reserve `~/pub4/tmp/patch.rb` only for genuinely script-shaped edits.
- **Man pages first** before editing config files (`MANPAGER=cat man pagename` via SSH)

---

## Sweep Safety

The sweep corruption guard (added 2026-04-27) protects against LLM error messages being written as source:
- `ask_result()` + Result monad check in `rewrite()`
- 50% minimum length guard
- `ERROR_PATTERNS` regex rejection for short outputs
- SYNTAX_CHECKERS for `.rb`, `.yml`, `.erb`

Never disable these guards. If sweep produces unexpected output, the guards will reject it.

---

## House Rules (recurring corrections, distilled)

- **Autoproceed.** Once approved, execute the full backlog without per-step go/no-go.
- **No new files without approval.** Always edit originals in place; no `_v2`, `_new`, staging copies.
- **Frequent git commits.** Commit after every meaningful change, not in batches.
- **Mandatory lint/beautify on touch.** Every edited file gets a full lint/beautify pass, not just changed lines.
- **Always autofix violations.** Run `/sweep` immediately after any scan finds violations, no confirmation needed.
- **No heavy work on Termux/Android.** Defer Ruby runs, large clones, mass ops to the VPS.
- **Bare HTML/CSS targeting.** Style by tag (`nav a`, not `.nav__link`); use the tag helper; no class attrs on elements that are targetable by tag.
- **README auto-refresh.** Update `README.md` after any behavior/capability/surface change, no prompting.
