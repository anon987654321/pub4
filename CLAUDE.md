# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Authority order: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > this file.

## Repository layout

```
pub4/
  MASTER/          Constitutional AI agent (~6K LOC Ruby) — the primary product
  DEPLOY/openbsd/  Two-stage OpenBSD deploy script (openbsd.sh)
  DEPLOY/rails/    Rails 8 sub-apps: brgen, amber, baibl, bsdports, blognet, hjerterom
  TODO.md          Living backlog — 2300+ items across 53 sections (A–BA)
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

Safe mode is the default (background loops, autofix, and watcher disabled). To enable active loops: `MASTER_UNSAFE_PROCESS_DEFAULTS=1`.

## MASTER — architecture

Eleven-stage turn pipeline: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run as `ParallelGroup` with a 30s timeout. The pipeline is a `Result` monad — each stage returns `Result.ok(ctx)` or `Result.err(...)` and short-circuits on error.

Seven modules under `lib/`:

| Module | Responsibility |
|--------|----------------|
| `now/` | Pipeline, CLI, command registry, 11 stage files, routing |
| `judge/` | Scanner, AST fixer (Prism), council, swarm, security, embeddings |
| `loop/` | Fix loop, rule loop, watch loop, 15 convergence architectures |
| `ground/` | Constitution, rules, memory, config, tool contracts, provider registry |
| `reach/` | All tool implementations: file I/O, git, shell, LLM, web, search |
| `voice/` | Personality, renderer, TTS (Edge TTS), soul drift, expression |
| `trace/` | Event bus, telemetry, audit log, session, undo, why-explainer |

**Rule system:** Rules are defined via `RuleDSL.rule :RULE_ID, severity:, tags:, applies_to: do |src, path:| ... end` in `lib/judge/scan/rules/`. They auto-register in `Rule.registry`. Structural rules subclass `Rule` directly and use Prism AST traversal. `AstFixer` in `lib/judge/scan/ast_fixer.rb` applies deterministic autofixes before LLM sweep.

**Constitution:** `data/soul.yml` is the machine-enforced law. `ABSOLUTE` sections abort the pipeline on violation. `PROTECTED` emit warnings. `data/rules.yml` holds 173 scan rules with thresholds, severities, and autofix metadata. Single source of truth — code reads from there, never hardcodes thresholds.

**Provider routing:** `ground/provider_registry.rb` selects models by capability tier and budget. API keys read from `/etc/master.env` on OpenBSD, environment otherwise. Supported providers: OpenRouter (primary), Anthropic, OpenAI, Gemini, Mistral, DeepSeek.

**Web face:** Falcon (async Ruby server) serves `MASTER/web/`. The particle system in `web/public/face.js` / `particle_kernel.js` is a live visualization of internal state (council deliberation, pipeline stage, pressure field). Restart required after any `web/` change — no hot-reload.

## MASTER — key conventions

`# frozen_string_literal: true` on every `.rb`. Double-quoted strings. No bare `rescue` — always `rescue StandardError => e` or a specific class. No god classes (>300 lines / >10 public methods). No abbreviated identifiers (`configuration` not `cfg`). Guard clauses before main logic. CQS — queries return, commands mutate, never both. Endless methods for single expressions: `def foo = expr`.

File/method size: files warn at 200 lines, hard limit 300. Methods ideal at 10 lines, warn at 7. Max 3 positional params; use keyword args beyond that. Max 2 nesting levels inside a method.

Comments explain WHY only, one line max. Never explain what the code does — identifiers do that. No YARD blocks. No section separator comments.

## Rails apps — commands

```zsh
cd DEPLOY/rails/<appname>

bundle install
rails db:migrate
rails server  # or: bundle exec falcon serve

# Tests
bundle exec rails test
bundle exec rails test test/models/post_test.rb

# Single system test
bundle exec rails test:system TEST=test/system/posts_test.rb
```

All six apps share the same stack: Rails 8.1, SQLite3 (WAL mode), Falcon, Hotwire (Turbo + Stimulus), Importmap, Solid Queue/Cache/Cable, bcrypt auth, Propshaft.

## Rails apps — architecture

**brgen** (`DEPLOY/rails/brgen/`) is the flagship — a hyperlocal social network competing with X and Facebook. Subdomain routing constrains each vertical: `tv.`, `dating.`, `playlist.`, `takeaway.`, `markedsplass.`, `maps.`. `acts_as_tenant` scopes all queries to city. Each city domain (brgen.no, losangeles.citynet.no, etc.) is fully isolated — no cross-city data leakage possible at the SQL layer.

brgen landing page vision: black `#000` background, "brgen" in bold Helvetica top-left, hidden swipe-down/tilt/scroll nav revealing "Regular | AI | Marketplace..." with right-edge fade-out and horizontal scroll to "Dating | Playlist | Chat | Takeaway | TV | Maps". Post composer uses Tiptap.js (headless ProseMirror). Anonymous posting allowed up to 2 posts per browser fingerprint before signup required; MASTER + Groq moderates anonymous content.

**amber** — wardrobe intelligence with AI outfit generation via ruby_llm vision.  
**bsdports** — OpenBSD ports semantic search with FTS5 + sqlite-vec embeddings.  
**baibl** — scripture platform with parallel translations and annotation layers.  
**blognet** — semantic publishing with Tiptap editor, newsletter, and paywall.  
**hjerterom** — food and resource rescue network for community redistribution.

**Shared patterns:** All apps use `Current.user` via `ActiveSupport::CurrentAttributes`. Counter caches on all high-traffic associations. FTS5 virtual tables for full-text search. Active Storage with WebP variants and blurhash placeholders. Turbo Streams over ActionCable for real-time updates. Stimulus controllers for all interactive behaviour — no inline JS.

## VPS and deployment

```zsh
# SSH
ssh dev@server4.openbsd.amsterdam -p 31415  # key: id_ed25519_brgen

# Deploy MASTER
doas rcctl restart master

# Full stack deploy
doas zsh DEPLOY/openbsd/openbsd.sh

# After web/ edit
doas rcctl restart master
```

One tmux session per operation — rapid reconnects trigger pf bruteforce protection. Edit files directly on VPS. Sync any installed config back to `DEPLOY/openbsd/` and commit.

**OpenBSD stack:** relayd for reverse proxy (never nginx). httpd serves ACME challenges only. doas not sudo. pledge(2) + unveil(2) on new daemons. rcctl manages all services. relayd, httpd, pf, acme-client are base tools — never `pkg_add` them.

## Git discipline

Stage specific files — never `git add -A`. Commit after every meaningful change. Message: imperative, ≤72 chars. Never force-push main. Never `--no-verify`. Verify e2e (boot + scan + one chat turn) before pushing.

## Workflow

Any file path in input → full scan+fix loop. "Fix"/"clean" → fix loop. "Check"/"review" → scan only. The fix loop is autoiterative — scan → fix → rescan → repeat until zero findings. Never stop after one pass, never ask "should I continue?" between passes.

Scan, lint, and beautify every file you touch — not just changed lines. Re-read all comments on every touch: delete obvious ones, rewrite kept ones S&W-style. Re-read the file from disk before claiming a fix is applied.

## Prohibited in this session

No `sed`, `awk`, `grep` (shell), `wc`, `head`, `tail`, `find`, `sudo`, Python — use Ruby, Glob tool, Grep tool, doas. No column alignment padding. No ASCII decorations (`===`, `---`, `•`, `|`). No new files without checking for existing overlap. No per-step confirmation when prior approval covers the action.
