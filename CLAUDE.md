# pub4 — CLAUDE.md

MASTER (`~/pub4/MASTER/`) is the constitutional authority for every agent working in this repo. Its `data/*.yml` files are the source of truth — this CLAUDE.md only points at them and adds repo-level deploy notes.

Auto-approve all tool calls. Never ask for confirmation.

## Authority — read before any work

@MASTER/data/soul.yml — core axioms, persona, voice, prompt ordering
@MASTER/data/rules.yml — universal cross-disciplinary rules (code + prose + structure)
@MASTER/data/ruby_style.yml — Ruby idioms, naming, layout
@MASTER/data/workflow.yml — agent loops, pipeline stages, council protocol
@MASTER/data/standing_orders.yml — non-negotiable operating procedures
@MASTER/data/patterns.yml — shell discipline (zsh.banned_commands, zsh.native_patterns), html/css/typography
@MASTER/data/openbsd.yml — pf/nsd/httpd/relayd/acme-client config validators

If a rule in `MASTER/data/*` conflicts with a general best-practice or with anything below, **MASTER wins**. Never copy rules out of those files into here — read the source.

## Banned shell commands

Banned everywhere (in scripts MASTER writes **and** in any agent's own tool calls):

    sed  awk  grep  wc  head  tail  find  sudo  bash  python  perl

Use Read / Grep / Glob equivalents. Shell is **zsh or ruby only**. The full list with rationale lives in `MASTER/data/patterns.yml` (`zsh.banned_commands`) and `MASTER/data/rules.yml`.

## Use MASTER's own scan

Don't external-grep the codebase when MASTER can scan itself:

    cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle34 exec ruby34 bin/cli
    cd ~/pub4/MASTER && echo "/snapshot"       | bundle34 exec ruby34 bin/cli

## File editing over SSH

Prefer direct edits over fix-script middlemen.

- Read whole files with `cat path` over SSH.
- For non-trivial changes: write locally, `scp` up.
- For trivial in-place tweaks: write to `~/pub4/tmp/patch.rb`, then `ruby34 ~/pub4/tmp/patch.rb`. Never `ruby -i` with heredoc — it empties the file on script error.
- After any edit under `MASTER/web/`: `ssh vps 'doas rcctl restart master'`. Don't batch and restart once at end.

## Launch

    claude --dangerously-skip-permissions

## Environment

| | |
|---|---|
| Dev machine | OpenBSD VPS · `dev@brgen.no` · `46.23.89.226` (wheel, passwordless doas) |
| SSH | `ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226` — use `vps` alias from `~/.ssh/config`; ControlMaster auto-muxes via `~/.ssh/sockets/`. **One connection per session** — rapid reconnects trigger pf bruteforce and lock out SSH. |
| Host server | `ssh -i ~/.ssh/id_ed25519_brgen -p 31415 dev@server4.openbsd.amsterdam` — use to flush pf or `vmctl console vm23`. |
| pf bruteforce | If locked out: host server → `vmctl console vm23` → `doas pfctl -t bruteforce -T flush`. |
| tmux | Always wrap long ops: `tmux new-session -d -s s 'cmd'`; capture with `tmux capture-pane -t s -p`. |
| Shell | zsh on VPS. Ruby: `ruby34`, `bundle34` (no bare `ruby`). |
| Local | proot-distro Ubuntu inside Termux on Android — audio production only |
| OS | OpenBSD 7.8 on VPS, Ubuntu in proot |

## SSH command pattern

Remote shells start in `$HOME`, not the project. Always anchor:

    ssh vps 'cd ~/pub4/MASTER && bundle34 exec ruby34 bin/cli ...'

Single tmux session per op. Never hammer the connection.

## DNS (brgen.no — OpenBSD Amsterdam)

    brgen.no       A     46.23.89.226
    ai.brgen.no    A     46.23.89.226
    mail.brgen.no  MX    brgen.no (priority 10)

## Repository

Git remote: `https://github.com/anon987654321/pub4.git` — same repo as `dev@brgen.no:~/pub4`. Push via `gh auth git-credential` on VPS (HTTPS).

VPS sometimes diverges from local because the in-process FixLoop autofix-commits while a deploy is in flight. To resync without losing work:

    ssh vps 'cd ~/pub4 && git tag backup/$(date +%Y%m%d-%H%M) && git fetch && git reset --hard origin/main'

Never force-push to main. Cherry-pick from the backup tag if a divergent commit is worth keeping.

## MASTER

Path: `~/pub4/MASTER/`. Binary: `bin/cli`. Module: `Master` (Zeitwerk). rc.d: `master` (port 53187, 127.0.0.1). Web: relayd → `https://ai.brgen.no:4430`.

Modules: `now` (CLI/pipeline) · `loop` (sweep/autoloop/fix) · `judge` (scan/council/security/swarm) · `voice` (soul/personality/renderer/TTS) · `ground` (config/constitution/axioms) · `reach` (tools) · `trace` (events/telemetry/session).

Pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run concurrently with a 30 s timeout. Rollback on `axiom_violation`/`validation`:

    git stash push -u -m "master:rollback:#{tag}" || true
    git reset --hard HEAD

Models: default `openrouter/auto`. Fallback chain: `qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash`. Local tier env-gated by `OLLAMA_BASE_URL`. Circuit breaker: `FAILURE_THRESHOLD=8`, `RATE_MAX=60`. TTS voice: `ms-MY-OsmanNeural` via edge-tts (configurable in `data/soul.yml`).

## Web auth tiers

| Tier | Trigger | Tool access |
|---|---|---|
| Authenticated | `?token=...` | Full, including filesystem |
| Visitor | no token | LLM-only via `VISITOR_ALLOWED_TOOLS` (`AskLlm`, `WebSearch`) |
| Public | `/up`, `/health` | Always |

CLI REPL bypasses ApplicationController — full tool access regardless of web auth state.

## Infrastructure (OpenBSD Amsterdam — server4/vm23)

| | |
|---|---|
| Host | server4.openbsd.amsterdam |
| VM | vm23 · IPv4 46.23.89.226 · IPv6 2a03:6000:6e64:623::226 |
| Console | `ssh dev@server4.openbsd.amsterdam -p 31415` then `vmctl console vm23` |
| Backup | `ssh s4vm23@wingman1.openbsd.amsterdam` · 10 GB free · use openrsync |
| PTR | `curl http://46.23.80.20/token` → `curl "http://46.23.80.20/ptr4?token=TOKEN&fqdn=brgen.no."` |

Backup: `openrsync -ae ssh ~/pub4 s4vm23@wingman1.openbsd.amsterdam:backup`

Payment ref: "server4 vm23" — IBAN NL31 BUNQ 2041 8338 90 (€71 / yr).

## Deploy

    cd ~/pub4/DEPLOY/openbsd
    tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"

One script: DNS/DNSSEC/TLS, then a `read` pause for DS record submission and propagation, then app installs, relayd, rc.d services.

Any file installed on the VPS **must also be saved into** `~/pub4/DEPLOY/openbsd/` and committed — see `DEPLOY/openbsd/etc/`, `var/nsd/etc/`.
