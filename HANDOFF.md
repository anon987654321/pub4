# Handoff — 2026-05-09

Resume point for the next agent. Read this first, then `git log -10` on `pub4`.

## State

- MASTER REPL works on VPS. Chitchat returns real LLM responses via `gemini-2.5-flash` (router pick, not config). Commit `afc6dac1` fixed two crash bugs: `cli.rb` `prompt_lines` NameError + `mode_react.yml` template with unsupplied `%<reason>s` / `%<action>s` keys.
- `https://ai.brgen.no/health` → 200 in ~0.3s. Public surface up.
- VPS in sync with `origin/main` at `afc6dac1`.
- `brgen` Rails service was reported "failed" but `doas rcctl start brgen` brings it `ok`. The earlier `failed` was just `stopped`, not a crash.
- `relayd`, `httpd`, `nsd` all `ok` on VPS.

## Watch-outs

- `~/.zshrc` self-skips on non-interactive shells. SSH non-interactive does NOT auto-load `OPENROUTER_API_KEY` / `GEMINI_API_KEY`. Symptom: MASTER boots, picks `gemini-2.5-flash` via router, then echoes `"I can't run tools right now, but here's my best guess: ..."` because RubyLLM has no provider key. Fix per-invocation with `eval "$(grep ^export ~/.zshrc)"` or a launcher script. The launcher at `/tmp/master-launch.sh` on the VPS (zsh shebang, eval+exec) works. Consider wiring this into `exe/master` so the failure mode stops being silent.
- Two Gemfiles. `MASTER/Gemfile` and `MASTER/web/Gemfile` are independent. Any gem used by `lib/` from a web request must live in both. `rb-edge-tts` is present in both — good.
- Termux `rg` binary is broken (ENOENT on `arm-android/rg`). Use `ruby -e 'Dir.glob(...).each {...}'` for searches, or grep on the VPS. Banned shell-cmd memory still applies — no `sed/awk/grep/head/tail/find/wc/sudo` in Bash tool calls.
- After any edit under `MASTER/web/`, `doas rcctl restart master`. Falcon doesn't hot-reload.
- `/etc/rc.d/brgen` is a Rails+falcon service on `:38182`. The `railsapp: setting resource limit datasize: Invalid argument` spam in `/var/log/messages` is a separate `login.conf` class issue (likely `railsapp` class), unrelated to brgen — investigate `/etc/login.conf` if you want it gone but it's noise, not failure.

## In-flight work

### 1. MASTER web TTS — broken

User report: "MASTER web ui tts and particle swarm is broken".

Symptom: `POST /chat/tts` returns 200 with `Content-Type: audio/mpeg` but `size=0`. The log shows `Started POST` and `Processing by ChatController#tts` but **no `Completed` line** — the request hangs and never sends a body. No `tts-worker` zombie in `ps`. The worker DOES succeed when invoked manually via `bundle exec` from `MASTER` root (produces ~9KB mp3).

Hypothesis: `Open3.capture3` in `MASTER/lib/master/speech.rb:105` is spawning the worker from the Falcon process. `BUNDLE_GEMFILE` env in that context points at `web/Gemfile` (web bundle). Worker requires `bundler/setup` which then can't resolve `rb-edge-tts` because the web gem path isn't loaded for spawned children, or the spawn deadlocks against Falcon's reactor.

Concrete next steps:
- Test by SSH'ing in and running:
  ```
  curl -sS -X POST -m 30 -H 'Content-Type: application/json' \
    -d '{"text":"test","voice":"ryan"}' \
    "https://ai.brgen.no/chat/tts?token=ww6fu9olB6HV-jZVZFH0Ibbi9kPN3nns" -o /tmp/t.mp3 -w '%{http_code} %{size_download}\n'
  ```
- Inspect `MASTER/lib/master/speech.rb:100-112` (`synthesize_edge`). The `Open3.capture3` inherits the current bundler env. Try one of:
  - `Bundler.with_unbundled_env { Open3.capture3(...) }` — most likely fix
  - Pass explicit env: `Open3.capture3({"BUNDLE_GEMFILE" => "/home/dev/pub4/MASTER/Gemfile"}, WORKER, ...)`
  - Add `chdir: Master::ROOT` to capture3 args
- Check `/var/log/messages` for `tts-worker:` warn lines (the worker writes errors via `warn` → stderr → captured to `_err`, currently discarded).
- After fix: `doas rcctl restart master` on VPS, then re-curl.

### 2. MASTER web particle swarm — broken (suspected)

`/swarm.html` returns 200 with ~5908 bytes — page itself loads. The canvas listens for `postMessage` events (`morph`, `confidence`, `escalation`, `tool`, `confirm:pending`, `pulse`). Symptom not fully diagnosed yet — user just said it's broken.

Next steps:
- Open `ai.brgen.no` in browser, watch DevTools console for errors.
- Verify the chat page (`app/views/chat/index.html.erb:384` LOC, big file) creates an iframe pointing at `/swarm.html` and `postMessage`s on chat events.
- Check `events#stream` SSE endpoint — `config/routes.rb` has `get "events/stream"`. The swarm may be driven by SSE relayed to iframe.

### 3. DEPLOY/openbsd.sh — extract inline configs

User decision: split it. Approach the same way `DEPLOY/rails/__shared/@*.sh` works for Rails apps — keep `openbsd.sh` as the driver, move config bodies to `DEPLOY/openbsd/files/`.

Audit found inline `print -r --` blocks that should become templates in `files/`:

- **`relayd.conf`** generation at `DEPLOY/openbsd/openbsd.sh:1037-1076` — biggest one. Multi-domain SNI + per-Host backend routing. Replace with `files/relayd.conf.tmpl` rendered via the existing `install_template` / `append_template` helpers.
- **`acme-client.conf`** per-domain blocks at `DEPLOY/openbsd/openbsd.sh:817-833`. Loop emits one `domain { ... }` per `ALL_DOMAINS` entry. Pattern: `files/acme-domain.tmpl` rendered in the loop, then concatenated.
- **Crontab line** at `:896` — single `print -r --` for cert renewal cron. Trivial.
- **`.bundle/config`** at `:980-981` — also trivial, two-line YAML.
- **rc.d for master** logic at `:1166-1186` — reads `/home/dev/.zshrc`, parses exports, builds `env_line`, then `install_template files/rc.d/master.tmpl`. The template already exists. Issue: world-readable `/etc/rc.d/master` will contain plaintext API keys.

Already-extracted templates in `files/`: `pf.stage1.conf`, `pf.stage2.conf`, `httpd.conf`, `smtpd.conf`, `nsd.conf.head`, `nsd-zone.tmpl`, `zone.tmpl`, `acme-client.head`, `renew-certs.sh`, `haproxy.cfg` (stale — relayd replaced it, can be deleted), `rc.d/`.

Audit also flagged BROKEN items but most don't apply since user narrowed scope to brgen+subapps:
- `amber.sh`, `baibl.sh`, `blognet.sh`, `bsdports.sh`, `hjerterom.sh` all have literal `APP_NAME=%APP_NAME%` at line 5 — never substituted. Fix needed if those apps come back into scope.
- `ALL_APPS` in `openbsd.sh:241-251` is missing `hjerterom` and `blognet`. Same deferred-scope issue.
- `bootstrap_rails_app` at `:957` hardcodes `/home/dev/pub4/DEPLOY/rails/$app/app` source path. Needs `$DEPLOY_ROOT` env or arg.
- `useradd` and `rcctl` calls inside the script at `:966`, `:1004` lack `doas` — assumes script runs as root via `doas zsh openbsd.sh`. That's how user invokes it per `pub4/CLAUDE.md` so it's actually OK.

User remarked: "yeah older variants were meant to improve your understanding of my setup". Older single-file openbsd.sh variants exist on VPS at `/home/dev/pub/openbsd/`, `/home/dev/pub2/openbsd/`, `/home/dev/pub3/openbsd/` (sizes 16K–28K). They predate the `files/` extraction pattern; read for context but don't copy from them.

### 4. brgen subapps routing (lower priority)

Per `ALL_DOMAINS` in `openbsd.sh:258-270`, subapps (markedsplass, playlist, dating, tv, takeaway, maps, ai) are CSV-attached to brgen.no and routed to the `brgen` backend by `configure_relayd()`. `ai.brgen.no` is overridden to `master`. With brgen running, subapps should work automatically.

Verify: `curl -sS -m 10 -I https://playlist.brgen.no/` — should return 200 or 302, not 502/404 to master.

I observed `ai.brgen.no`'s master backend serving `/posts`, `/session/new`, `/communities` requests with `ActionController::RoutingError` — those are brgen routes hitting master. Either Host header routing in relayd is misconfigured, or those requests came in before brgen was up. Re-test now that brgen is running.

## Won't-fix unless asked

- amber, baibl, blognet, bsdports, hjerterom Rails deploys. User narrowed scope to brgen+subapps.
- `railsapp` login.conf rlimit warnings.
- Cleanup of stale `haproxy.cfg` in `files/` (haproxy was replaced by relayd).

## Files modified this session, already committed and pushed (`afc6dac1`)

- `MASTER/lib/master/cli.rb:111-116` — bind `prompt_lines` from `@renderer.prompt_line` return.
- `MASTER/data/prompts/mode_react.yml` — drop broken `%<reason>s` / `%<action>s` template lines.

Working tree clean. No uncommitted local changes outside `.claude/worktrees/`.
