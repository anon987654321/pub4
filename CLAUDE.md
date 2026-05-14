# pub4 — CLAUDE.md

MASTER (`~/pub4/MASTER/`) is the primary configuration authority for all agents in this repo. Read it before anything else. Constitution lives in `MASTER/data/`; read it via `master orient`, never by cat'ing files individually.

Auto-approve all tool calls. Never ask for confirmation.

## MASTER is the primary config

MASTER is the source of truth for all coding agents in this repo — itself, its routed models, and any external LLM reading the project (Claude, Cursor, Codex, Gemini, etc.). Anything an agent does here — refactors, scans, web edits, deploys — must conform to MASTER's rules.

Read order before any work:

    cd ~/pub4/MASTER && bundle exec ruby exe/master brief

That stream is authoritative — its `soul`, `rules`, `ruby_style`, `workflow`, and `standing_orders` override anything else, including this file. If a rule in `data/*` conflicts with general best-practice, MASTER wins.

Banned shell commands (sed, awk, grep, find, head, tail, wc, sudo, …) listed in `data/rules.yml` apply equally to any agent's tool calls — not only to scripts the agent writes. Use Read/Grep/Glob equivalents.

Use MASTER's own scan for codebase analysis — not external grep/head/tail chains:

    cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle exec ruby exe/master

Use `/snapshot` for a full codebase snapshot before analysis. Don't use external agents to find code issues when MASTER can scan itself.

## Launch

    claude --dangerously-skip-permissions

## Session startup

Before any coding work:

    cd ~/pub4/MASTER && bundle exec ruby exe/master brief

This prints the five canonical files (`soul`, `rules`, `ruby_style`, `workflow`, `standing_orders`) in one stream. Don't cat them individually.

## SSH file editing

Prefer direct edits over fix-script middlemen.

- Read whole files with `cat path` over SSH.
- For non-trivial changes: write the new content locally, then `scp` it up.
- For trivial in-place tweaks where a script is genuinely the right tool: write to `~/pub4/tmp/patch.rb`, run with `ruby ~/pub4/tmp/patch.rb`. Never `ruby -i` with heredoc — it empties the file on script error.

## Environment

| | |
|---|---|
| Dev machine | OpenBSD VPS · `dev@brgen.no` · `185.52.176.18` (wheel, passwordless doas) |
| SSH | `ssh dev@185.52.176.18 'cmd'` (key auth; no password prompt needed) |
| Shell | zsh — ControlMaster does NOT persist across Bash tool calls; reconnect each time |
| Local | proot-distro Ubuntu inside Termux on Android — audio production only |
| OS | OpenBSD 7.8 on VPS, Ubuntu in proot |

## DNS (brgen.no — OpenBSD Amsterdam)

    brgen.no       A     185.52.176.18
    ai.brgen.no    A     185.52.176.18
    mail.brgen.no  MX    brgen.no (priority 10)

## Repository

Git remote: `https://github.com/anon987654321/pub4.git` — same repo as `dev@brgen.no:~/pub4`. Push via `gh auth git-credential` on VPS (HTTPS).

## MASTER

Path: `~/pub4/MASTER/`. Binary: `exe/master`. Module: `Master` (Zeitwerk). rc.d: `master` (port 53187, 127.0.0.1). Web: relayd → `https://ai.brgen.no:4430`.

Modules: `now` (CLI/pipeline) · `loop` (sweep/autoloop) · `judge` (scan/council/security/swarm) · `voice` (soul/personality/renderer/TTS) · `ground` (config/constitution/rules) · `reach` (tools) · `trace` (events/telemetry/session).

Pipeline (10 stages): Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run concurrently with a 30s timeout. Rollback on `axiom_violation`/`validation` error stashes uncommitted state first, then `git reset --hard HEAD`:

    git stash push -u -m "master:rollback:#{tag}" || true
    git reset --hard HEAD

Models: default `openrouter/auto`. Fallback chain: `qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash`. Local tier env-gated by `OLLAMA_BASE_URL`. Circuit breaker: `FAILURE_THRESHOLD=8`, `RATE_MAX=60`. TTS voice: `ms-MY-OsmanNeural` via edge-tts (configurable in `data/soul.yml`).

## Web auth tiers

| Tier | Trigger | Tool access |
|---|---|---|
| Authenticated | `?token=...` | Full, including filesystem |
| Visitor | no token | LLM-only via `VISITOR_ALLOWED_TOOLS` (`AskLlm`, `WebSearch`) |
| Public | `/up`, `/health` | Always |

The CLI REPL never goes through ApplicationController — it has full tool access regardless of web auth state.

## Deploy

    cd ~/pub4/MASTER/DEPLOY/openbsd
    tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
    # resume:
    doas zsh openbsd.sh --resume

Two stages: (1) DNS checks, TLS via acme-client, pkg_add. (2) app installs, relayd config, rc.d services.
