# pub4 — CLAUDE.md

Operator environment, SSH, DNS, deploy. Constitution lives in `MASTER/data/`; read it via `master orient`, never by cat'ing files individually.

Auto-approve all tool calls. Never ask for confirmation.

## MASTER is the primary config

MASTER (`~/pub4/MASTER/`) is the source of truth for all coding agents in this repo — itself, its routed models, and any external LLM reading the project (Claude, Cursor, Codex, Gemini, etc.). Anything an agent does here — refactors, scans, web edits, deploys — must conform to MASTER's rules.

Read order before any work:

    bundle exec ruby exe/master orient

That stream is authoritative — its `soul`, `rules`, `ruby_style`, `workflow`, and `standing_orders` override anything else, including this file. If a rule in `master.yml` / `master.json` / `data/*` conflicts with general best-practice, MASTER wins.

Banned shell commands (sed, awk, grep, find, head, tail, wc, sudo, …) listed in `data/rules.yml` apply equally to any agent's tool calls — not only to scripts the agent writes. Use Read/Grep/Glob equivalents.

## Launch

    claude --dangerously-skip-permissions

## Session startup

Before any coding work:

    bundle exec ruby exe/master orient

This prints the five canonical files (`soul`, `rules`, `ruby_style`, `workflow`, `standing_orders`) in one stream. Don't cat them individually — `orient` is the one source of truth for read-order, and updating it once propagates everywhere.

Use MASTER's own scan before external analysis:

    eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle exec ruby exe/master

Don't use external agents to find code issues when MASTER can scan itself.

## SSH file editing

Prefer direct edits over fix-script middlemen.

- Read whole files with `cat path` over SSH.
- For non-trivial changes: write the new content locally, then `scp` it up.
- For trivial in-place tweaks where a script is genuinely the right tool: write to `~/pub4/tmp/patch.rb`, run with `ruby ~/pub4/tmp/patch.rb`. Never `ruby -i` with heredoc — it empties the file on script error.

## Environment

| | |
|---|---|
| Dev machine | OpenBSD VPS · `dev@brgen.no` · `185.52.176.18` (wheel, passwordless doas) |
| Password | ask user at session start: `read -s 'VPS_PASS?VPS password: '` |
| SSH | `sshpass -p "$VPS_PASS" ssh -o StrictHostKeyChecking=no dev@185.52.176.18 'cmd'` |
| Shell | zsh — ControlMaster does NOT persist across Bash tool calls; use sshpass every time |
| Local | proot-distro Ubuntu inside Termux on Android — audio production only |
| OS | OpenBSD 7.8 on VPS, Ubuntu in proot |

`.zshrc` self-skips on non-interactive shells via `[[ -o interactive ]] || return` at the top, so SSH no longer auto-launches MASTER and steals stdin. The `eval "$(grep '^export' ~/.zshrc)"` workaround is no longer required.

## DNS (brgen.no — OpenBSD Amsterdam)

    brgen.no       A     185.52.176.18
    ai.brgen.no    A     185.52.176.18
    mail.brgen.no  MX    brgen.no (priority 10)

## Repository

Git remote: `https://github.com/anon987654321/pub4.git` — same repo as `dev@brgen.no:~/pub4`. Push via `gh auth git-credential` on VPS (HTTPS).

## MASTER

Path: `~/pub4/MASTER/`. Binary: `exe/master`. Module: `Master` (Zeitwerk). rc.d: `master` (port 53187, 127.0.0.1). Web: relayd → `https://ai.brgen.no:4430`.

Pipeline (10 stages): Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run concurrently with a 30s timeout. Rollback on `axiom_violation`/`validation` error stashes uncommitted state first, then `git reset --hard HEAD`:

    git stash push -u -m "master:rollback:#{tag}" || true
    git reset --hard HEAD

Models: default `nvidia/nemotron-3-super-120b-a12b:free`. Fallback chain: `qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash`. Local tier env-gated by `OLLAMA_BASE_URL`. Circuit breaker: `FAILURE_THRESHOLD=8`, `RATE_MAX=60`.

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
