# pub4 — CLAUDE.md

Auto-approve all tool calls. Never ask for confirmation.

## Launch

```zsh
claude --dangerously-skip-permissions
```

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
- **Latest pushed commit**: `d39ed302`

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
> `master.yml` (the old 1770-line YAML config) was deleted in Feb 2026. MASTER (the Ruby codebase) replaced it — the agent IS the config.


MASTER is a constitutional AI coding agent that **replaces Claude Code CLI**.

- **Path**: `~/pub4/MASTER/`
- **Binary**: `exe/master`
- **Module**: `Master` (Zeitwerk autoloaded)
- **Launch**: SSH auto-starts via `~/.zshrc` → `cd MASTER && bundle exec ruby exe/master`
- **Pipe mode**: `echo "msg" | bundle exec ruby exe/master`
- **rc.d service**: `masterweb` (was `master3web` — rename pending on VPS)

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
| `axioms.yml` | Kernel axioms (PRESERVE_FIRST, SIMPLEST_WORKS, FAIL_VISIBLY, etc.) + top-25 philosophy principles |
| `constitution.yml` | Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK; protection levels; anti-simulation rules; communication style: openbsd_dmesg |
| `principles.yml` | KISS, DRY, YAGNI, SoC, SRP, SOLID — each with anti-patterns and auto-fix flag |
| `language_rules.yml` | Ruby 3.3+ rules, Rails 8+ stack, OpenBSD config, zsh banned commands (sed/awk/grep/find/etc.) |
| `standing_orders.yml` | Current FSM state (UNCHANGE / REFACTOR / etc.) |
| `workflow.yml` | READ_FULL_FILES, READ_BEFORE_WRITE, scan depths, autoloop/sweep config, Zeitwerk inflections, anti-sprawl |
| `language_axioms.yml` | Communication principles |
| `scan_depths.yml` | standard / deep / hunt rule sets |
| `fallback_models.yml` | Model fallback chain |
| `models.yml` | Model capability table |
| `council.yml` / `council_patterns.yml` | Council trigger patterns |
| `infer_patterns.yml` | Natural language → command routing |
| `strunk.yml` | Strunk & White prose rules for Prune stage |
| `prompts/` | LLM prompt templates |

The Ruby pipeline reads these at boot via `Master.build` and enforces them through scan rules, pipeline stages, and tool guards.

### Key modules

| File | Purpose |
|---|---|
| `lib/master.rb` | `Master.build(root:)` container; `Master.boot` → CLI |
| `lib/master/cli.rb` | REPL (`run`), pipe mode (`pipe`), slash commands |
| `lib/master/pipeline.rb` | 10-stage pipeline, ParallelGroup, rollback |
| `lib/master/sweep.rb` | Self-refactor loop (MAX_CYCLES=16, convergence 0.05) |
| `lib/master/agent.rb` | LLM calls, circuit breaker, fallback models |
| `lib/master/standing_orders.rb` | Constitutional rules, `wire_pipeline` |
| `lib/master/code_index.rb` | Symbol/Reference Structs (no `freeze: true` — Ruby 3.4 drops it) |
| `lib/master/scan/` | 10 scan rules (EXPLICIT, IMMUTABLE, CQS, SELF_EXPLAINING, etc.) |

### Web UI

- **Framework**: Sinatra + Falcon (port `10002` internal)
- **Public**: relayd proxies → `http://ai.brgen.no:3000`
- **Routes**: `GET /` chat, `POST /chat/message` (SSE), `GET /chat/metrics`, `GET /chat/dmesg`
- **rc.d**: `masterweb` daemon

### Models

- **Default**: `meta-llama/llama-3.3-70b-instruct:free` (OpenRouter, ~8 req/min)
- **Circuit breaker**: FAILURE_THRESHOLD=8, RATE_MAX=60

### Slash commands

`/scan [deep]`, `/sweep`, `/autoloop`, `/council`, `/tts`, `/profile`

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

Known fixes already applied (commits `39bff649`, `33a23ded`, `d39ed302`):
- PF pass rule includes ports 22, 25, 80, 443, 3000, 4430, 8080–8086
- masterweb binds to `127.0.0.1:10002`
- acme-client.conf: domain explicitly listed as first SAN entry
- Disk check: 10MB root, 512MB /var

---

## Shell Preferences

- **Never** use `sed`, `awk`, `tr`, `wc`, `head`, `tail`, `grep` — use zsh builtins
- **No tmp files** for simple operations — do it inline
- **No line noise** — keep commands clean and readable
- **Ruby only** — never Python
- **Read files**: `print -r -- "$(<file)"` (not `cat`, not bare `< file` via SSH — triggers pager)
- **zsh array**: `lines=("${(@f)$(<file)}")`; last 50: `print -l $lines[-50,-1]`
- **Edit VPS files**: `doas tee /path <<'EOF'` or `doas ruby -e "File.write(...)"`
- **Man pages first** before editing config files (`MANPAGER=cat man pagename` via SSH)

---

## TODO / Backlog

- [ ] Rename rc.d service `master3web` → `masterweb` on VPS
- [ ] Update `~/.zshrc`: still references `MASTER3/exe/master3` → `MASTER/exe/master`
- [ ] Deploy brgen.no Rails app publicly
- [ ] Task #13: Parallelize swarm worker dispatch
- [ ] Task #15: Confidence-based dynamic model escalation
- [ ] Verify EventSource orb visualizer in browser (`/events/stream`)
- [ ] openbsd.sh deploy: stage_1 stalled (only 2 lines logged) — needs restart + debug
