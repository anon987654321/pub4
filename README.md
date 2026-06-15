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

Operator docs: `MASTER/QUICKSTART.md`, `MASTER/data/rules.yml`

Web face: Falcon on `:53187`, relayd → `https://ai.brgen.no`

## Deploy

```zsh
doas zsh DEPLOY/openbsd/openbsd.sh          # full two-stage install
doas zsh DEPLOY/openbsd/openbsd.sh --sync-configs   # mirror /etc from repo
```

Rails app matrix: `DEPLOY/rails/apps.yml`

## Requirements

- OpenBSD 7.8+ on VPS; Ruby **3.4** for Rails apps
- `OPENROUTER_API_KEY` (and other keys in `/etc/master.env` on VPS)
- TLS terminates at **relayd** — Rails uses `assume_ssl`, not `force_ssl`

## License

MIT