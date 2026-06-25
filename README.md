# pub4

Constitutional AI runtime and OpenBSD-first deploy stack. Ruby.

## Layout

```
pub4/
  MASTER/           AI agent (~6K LOC) + web face
  DEPLOY/
    openbsd/        VPS stack (pf, relayd, nsd, rc.d)
    rails/          Rails 8 apps + shared engine
    dilla/          Audio lab
    bp/             Business-plan HTML sites
    postpro/        Image post-processing
    sh/             Deploy helpers
  index.html        Radio Bergen — warp tunnel visualizer
```

## MASTER

Self-hosting agent on the VPS. Replaces external CLI tooling for repo work.

```zsh
cd MASTER && bundle exec ruby bin/cli
```

Pipeline: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render

Operator docs: `MASTER/QUICKSTART.md`, `MASTER/data/rules.yml`, `MASTER/data/voice.yml`, `MASTER/data/limits.yml`

Web face: Falcon on `:53187`, relayd → `https://ai.brgen.no`

## Deploy

```zsh
doas zsh DEPLOY/openbsd/openbsd.sh          # full two-stage install
doas zsh DEPLOY/openbsd/openbsd.sh --sync-configs   # mirror /etc from repo
```

Rails app matrix: `DEPLOY/rails/apps.yml`

## Fictive Seed Data (Faker + Web Scraping)

Base seeds use ruby-faker for rich, idempotent fictive data across brgen (core + subapps: marketplace, dating, playlist, takeaway, tv, maps, messages) and amber (wardrobe items, outfits, posts).

**Web-augmented mode** (optional, for more "real" fictive data):

- Uses Ferrum (headless Chrome) + vision LLM (OpenRouter) to scrape public Reddit subs / X searches.
- Rake tasks: `rake scrape:reddit_seed`, `rake scrape:x_seed` (brgen verticals), `rake scrape:fashion_seed` (amber).
- In seeds: `SEED_FROM_WEB=1 OPENROUTER_API_KEY=... bin/rails db:seed:replant`
- Scraped content is fictivized, anonymized, and routed to models (e.g. local buzz → Posts + Places/Maps; deals → Marketplace; music → Playlist; fashion → Amber Items/Outfits).
- Service lives in `DEPLOY/rails/shared/app/services/scrape.rb` (shared engine).

**Other LLMs/agents:** This pattern (Ferrum + LLM extraction + model routing + optional in seeds) is the canonical way to bootstrap realistic demo data without real user content. See `DEPLOY/rails/*/db/seeds.rb`, `DEPLOY/rails/brgen/lib/tasks/*.rake`, and `DEPLOY/rails/amber/lib/tasks/fashion.rake`.

## VPS Operations (Optimized, Light)

Target: vm23 on server4.openbsd.amsterdam (brgen.no).

**Access (if direct VM ssh blocked by pf):**
- Host: `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen -o VerifyHostKeyDNS=yes dev@server4.openbsd.amsterdam`
- Then: `vmctl console vm23` → login → `doas pfctl -t bruteforce -T flush` → exit with `~.`.

**Safe, light updates (no CPU/mem spikes):**
```zsh
cd /home/dev/pub4
git pull --ff-only

# Light config sync (enforces MASTER rules scan + health)
doas zsh DEPLOY/openbsd/openbsd.sh --sync-configs

# Or per-app (brgen subapps + amber etc.):
doas zsh DEPLOY/rails/brgen/brgen.sh   # or amber/amber.sh, etc.
# Inside .sh: MASTER /scan DEPLOY gate, bundle (cached), db:seed (optional web), rcctl restart (only if /up != 200)

# Ultra-light: just restart (with sleeps)
for s in brgen amber bsdports blognet hjerterom baibl; do doas rcctl restart $s || true; sleep 5; done
```

Always run from tmux. Use openrsync where possible. Health: curl /up endpoints + `ruby DEPLOY/openbsd/health_check.rb`.

See `DEPLOY/openbsd/README.md` for full provisioning, backup (wingman1 via openrsync), PTR, and docs links.

## Rules & Self-Application

`MASTER/data/rules.yml` is enforced everywhere (self_test on laws, veto patterns, ground_truth_check, evidence_scoring, tier1 priorities, etc.).

Deploys run `MASTER /scan DEPLOY --depth deep` before applying (blocks on violation). No exceptions for "deploy-only" code.

Other LLMs: the system is designed for recursive self-application — scan the tree yourself before proposing changes.

Operator docs: `MASTER/QUICKSTART.md`, `DEPLOY/openbsd/README.md`, `DEPLOY/rails/apps.yml`.

## Requirements

- OpenBSD 7.8+ on VPS; Ruby **3.4** for Rails apps
- `OPENROUTER_API_KEY` (and other keys in `/etc/master.env` on VPS)
- TLS terminates at **relayd** — Rails uses `assume_ssl`, not `force_ssl`

## License

MIT