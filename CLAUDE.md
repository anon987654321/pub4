# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Authority order: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > this file.

## Repository layout

```
pub4/
  MASTER/           Constitutional AI agent — the primary product
  DEPLOY/openbsd/   Two-stage OpenBSD deploy script (openbsd.sh)
  DEPLOY/rails/     Rails 8 sub-apps: brgen, amber, baibl, bsdports, blognet, hjerterom, marketplace
  DEPLOY/repligen.rb  Replicate.com AI image generation CLI (544 LOC)
  DEPLOY/postpro/   Cinematic post-processing via ruby-vips (film stocks, grain, LUTs)
  TODO.md           Operator handoff — intent, constraints, VPS recovery, active checklist
```

## MASTER — commands

```zsh
cd MASTER

# Start CLI (interactive)
bundle exec ruby bin/cli

# On OpenBSD (ruby34 + bundle34)
bundle34 exec ruby bin/cli

# Run tests
bundle exec rake test
bundle exec ruby -Ilib -Itest test/path/to/test_file.rb

# Web face (starts automatically with CLI; Falcon on port 53187)
# After any MASTER/web/ edit: doas rcctl restart master
```

Safe mode is the default (background loops, autofix, watcher disabled). Enable active loops: `MASTER_UNSAFE_PROCESS_DEFAULTS=1`.

## MASTER — architecture

Eleven-stage turn pipeline: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run as `ParallelGroup` with a 30s timeout. The pipeline is a `Result` monad — each stage returns `Result.ok(ctx)` or `Result.err(...)` and short-circuits on error.

Seven modules under `lib/`:

| Module | Responsibility |
|--------|----------------|
| `now/` | Pipeline, CLI, command registry, 11 stage files, routing |
| `judge/` | Scanner, AST fixer (Prism), council, swarm, security, embeddings |
| `loop/` | Fix loop, rule loop, watch loop, convergence architectures |
| `ground/` | Constitution, rules, memory, config, tool contracts, provider registry, axioms |
| `reach/` | All tool implementations: file I/O, git, shell, LLM, web, search, semantic cache |
| `voice/` | Personality, renderer, TTS (Edge TTS), soul drift, expression, Dilla audio |
| `trace/` | Event bus, telemetry, audit log, session, undo, why-explainer |

**Rule system:** Rules defined via `RuleDSL.rule :RULE_ID, severity:, tags:, applies_to: do |src, path:| ... end` in `lib/judge/scan/rules/`. Auto-register in `Rule.registry`. `AstFixer` in `lib/judge/scan/ast_fixer.rb` applies deterministic autofixes before LLM sweep.

**Constitution:** `data/soul.yml` is machine-enforced law. `ABSOLUTE` sections abort the pipeline on violation. `PROTECTED` emit warnings. `data/rules.yml` holds 173 scan rules with thresholds, severities, autofix metadata — single source of truth, never hardcode thresholds.

**Provider routing:** `ground/provider_registry.rb` selects models by capability tier and budget. API keys read from `/etc/master.env` on OpenBSD, environment otherwise. Supported: OpenRouter (primary), Anthropic, OpenAI, Gemini, Mistral, DeepSeek.

**Web face:** Falcon serves `MASTER/web/`. Particle system in `web/public/face.js` / `particle_kernel.js` visualises internal state (council deliberation, pipeline stage, pressure field). Restart required after any `web/` change — no hot-reload.

**Tools:** `MASTER/tools/repligen.rb` and `MASTER/tools/postpro.rb` are thin shims that exec into `DEPLOY/repligen.rb` and `DEPLOY/postpro/postpro.rb`. Heavy logic lives in DEPLOY; MASTER owns the stable entrypoint and tool contracts.

## MASTER — key conventions

`# frozen_string_literal: true` on every `.rb`. Double-quoted strings. No bare `rescue` — always `rescue StandardError => e` or a specific class. No god classes (>300 lines / >10 public methods). No abbreviated identifiers (`configuration` not `cfg`). Guard clauses before main logic. CQS — queries return, commands mutate, never both. Endless methods for single expressions: `def foo = expr`.

File/method size: files warn at 200 lines, hard limit 300. Methods warn at 7 lines, ideal 10. Max 3 positional params; keyword args beyond that. Max 2 nesting levels inside a method.

Comments explain WHY only, one line max. No YARD blocks. No section separator comments.

## repligen.rb — usage

```zsh
cd pub4
ruby DEPLOY/repligen.rb                   # interactive menu
ruby DEPLOY/repligen.rb sync 100          # sync 100 models from Replicate
ruby DEPLOY/repligen.rb search upscale    # search model DB
ruby DEPLOY/repligen.rb stats             # usage summary
```

Config token: `REPLICATE_API_TOKEN` env or `~/.config/repligen/config.json`. DB at `~/.local/share/repligen/repligen.db` (SQLite). Chain templates `masterpiece` and `quick` defined in `CHAIN_TEMPLATES`. Model types auto-classified via regex patterns in `MODEL_TYPES`.

## postpro.rb — usage

```zsh
ruby DEPLOY/postpro/postpro.rb input.jpg --stock kodak_portra --preset social
ruby DEPLOY/postpro/postpro.rb batch *.jpg --preset social --out processed/
ruby DEPLOY/postpro/postpro.rb watch ~/Downloads/ --preset social
```

Requires `ruby-vips` gem and `libvips` system library (`doas pkg_add vips` on OpenBSD). Film stocks defined in `STOCKS` constant: `kodak_portra`, `kodak_vision3`, `fujichrome_velvia`, others. Each stock defines grain sigma, 3×3 colour matrix, and per-channel H-D curves (Dmin/Dmax/pivot/gamma). Camera profiles loaded from `multimedia/camera_profiles/*.json`.

## Rails apps — commands

```zsh
cd DEPLOY/rails/<appname>

bundle install
rails db:migrate
rails server  # or: bundle exec falcon serve

# Tests
bundle exec rails test
bundle exec rails test test/models/post_test.rb
bundle exec rails test:system TEST=test/system/posts_test.rb
```

All apps share: Rails 8.1, SQLite3 (WAL mode), Falcon, Hotwire (Turbo + Stimulus), Importmap, Solid Queue/Cache/Cable, bcrypt auth, Propshaft.

## Rails apps — architecture

**brgen** (`DEPLOY/rails/brgen/`) is the flagship — hyperlocal social network competing with X and Facebook. Subdomain routing per vertical: `tv.`, `dating.`, `playlist.`, `takeaway.`, `markedsplass.`, `maps.`. `acts_as_tenant` scopes all queries to city. Cities: `brgen.no` flagship; others follow `<city>.citynet.no` — wildcard DNS, single wildcard TLS cert, per-city SQLite database at `db/cities/<slug>.sqlite3`.

brgen landing: `#000` OLED-black background, "brgen" in bold Helvetica top-left, hidden nav revealed by swipe-down/tilt/scroll (spring physics: `cubic-bezier(0.32,0.72,0,1)`), horizontal scroll nav "Regular | AI | Marketplace..." with right-edge `mask-image` fade-out. Post composer is Tiptap.js (headless ProseMirror). Anonymous posting: 2 posts per SHA-256 browser fingerprint before signup; MASTER + Groq llama3-8b moderates sync (2s timeout, optimistic approve on timeout). Feed is chronological + distance-weighted — no engagement-bait algorithm.

**amber** — wardrobe intelligence with AI outfit generation via ruby_llm vision.
**bsdports** — OpenBSD ports semantic search with FTS5 + sqlite-vec embeddings.
**baibl** — scripture platform with parallel translations and annotation layers.
**blognet** — semantic publishing with Tiptap editor, newsletter, and paywall.
**hjerterom** — food and resource rescue network for community redistribution.
**marketplace** — local classifieds (Finn.no-style) within brgen's city tenant system.

**Shared patterns:** `Current.user` via `ActiveSupport::CurrentAttributes`. Counter caches on all high-traffic associations. FTS5 virtual tables for full-text search. Active Storage with WebP variants and blurhash placeholders. Turbo Streams over ActionCable for real-time updates. Stimulus controllers for all interactive behaviour — no inline JS. Money in øre (integer), never floats.

**PostproJob:** `app/jobs/postpro_job.rb` in brgen auto-processes uploads; city selects film stock (`brgen.no → kodak_portra`, `losangeles → kodak_vision3`, `amsterdam → fujichrome_velvia`).

## VPS and deployment

vm23 on **server4** (`46.23.89.226`, user `dev`) — full network/hypervisor details in `DEPLOY/openbsd/README.md`. Repo on VPS: `/home/dev/pub4`. Operator keys may also live on `dev@brgen.no` (see operator notes; never commit secrets).

```zsh
# VM (flush pf bruteforce if SSH times out)
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226

# Hypervisor jump when VM SSH is blocked
ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam
vmctl console vm23   # then: doas pfctl -t bruteforce -T flush

# MASTER web face
doas rcctl restart master
curl -fsS http://127.0.0.1:53187/up
curl -fsS https://ai.brgen.no/up

# Full OpenBSD stack (DNS, relayd, TLS, in-place Rails bootstrap)
doas zsh DEPLOY/openbsd/openbsd.sh

# Copy-tree Rails deploy (six apps from master.json)
SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_on_vm_install.sh
# or on workstation → hypervisor → VM:
zsh DEPLOY/sh/vps_run_remote.sh

# Retry failed apps only
SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_retry_failed.sh
```

**Production URLs (after relayd + rcctl are green):**

| Host | Backend |
|------|---------|
| `https://ai.brgen.no` | MASTER web (Falcon :53187) |
| `https://brgen.no` | brgen Rails (:38182) |
| `https://markedsplass.brgen.no`, `dating.`, `takeaway.`, `tv.`, `playlist.`, `maps.`, `messenger.` | brgen subdomain routes (same app) |
| `https://blognet.no` | blognet (:10002) |
| `https://bsdports.org` | bsdports (:47312) |
| `https://baibl.no` | baibl (:10007) |
| `https://hjerterom.no` | hjerterom (:38891) |
| `https://amber.brgen.no` | amber (:61352) |

TLS terminates at relayd; Rails uses `config.assume_ssl = true` only.

**Deploy scripts (`DEPLOY/sh/`):** `vps_install_all.sh` and `vps_on_vm_install.sh` install MASTER + six Rails apps. Per-app `DEPLOY/rails/<app>/<app>.sh` copies the tracked tree to `/home/<app>/app`, copies `pub4-shared` to `/home/<app>/shared`, runs `bundle install` as the app user, ensures `/etc/<app>.env` with `SECRET_KEY_BASE`, overlays shared initializers, migrates DB, installs rc.d. Do not wrap deploy scripts in outer `doas` (nested doas fails). Use `SKIP_MASTER_SCAN=1` until MASTER `/scan DEPLOY` is non-interactive on VPS.

**Predecessor archive:** `DEPLOY/__predecessors/` holds recovered logic from pub/pub2/pub3 (privcam, ai3, multimedia/tts, etc.). Regenerate manifest: `DEPLOY/sh/sync_predecessors.sh`. Archived apps listed in `DEPLOY/rails/apps.yml`.

One tmux session per operation — rapid reconnects trigger pf bruteforce protection. Edit files on VPS, sync back to `DEPLOY/openbsd/` and commit. Pure Ruby for automation — no Python on deploy paths.

**OpenBSD stack:** relayd for reverse proxy (never nginx). httpd serves ACME challenges only. doas not sudo. pledge(2) + unveil(2) on new daemons. rcctl manages all services. relayd, httpd, pf, acme-client are base tools — never `pkg_add` them.

## Git discipline

Stage specific files — never `git add -A`. Commit after every meaningful change. Message: imperative, ≤72 chars. Never force-push main. Never `--no-verify`. Verify e2e (boot + scan + one chat turn) before pushing.

## Workflow

Any file path in input → full scan+fix loop. "Fix"/"clean" → fix loop. "Check"/"review" → scan only. The fix loop is autoiterative — scan → fix → rescan → repeat until zero findings. Never stop after one pass, never ask "should I continue?" between passes.

Scan, lint, and beautify every file you touch — not just changed lines. Re-read all comments on every touch: delete obvious ones, rewrite kept ones S&W-style. Re-read the file from disk before claiming a fix is applied.

## Prohibited in this session

No `sed`, `awk`, `grep` (shell), `wc`, `head`, `tail`, `find`, `sudo`, Python — use Ruby, Glob tool, Grep tool, doas. No column alignment padding. No ASCII decorations (`===`, `---`, `•`, `|`). No new files without checking for existing overlap. No per-step confirmation when prior approval covers the action.
