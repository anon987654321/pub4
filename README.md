# pub4

Constitutional AI coding agent and web platform. OpenBSD-first. Ruby-only.

## Layout

```
pub4/
  MASTER/          Constitutional AI agent (~6K LOC Ruby)
  DEPLOY/openbsd/  Two-stage OpenBSD deploy script (openbsd.sh)
  multimedia/      Audio tools: TTS, Dilla, Postpro, Repligen
  dilla/           Audio mixes and dilla.html canvas
  sh/              Shell scripts
```

## MASTER

Self-hosting AI agent that replaces Claude Code CLI on the VPS.

```zsh
cd MASTER && bundle exec ruby exe/master
```

10-stage pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render

Key features: scan, sweep (self-refactor), autoloop (continuous fix), council (adversarial review), TTS, soul (identity evolution).

## Deploy

```zsh
cd MASTER/DEPLOY/openbsd
doas zsh openbsd.sh
```

Deploys full OpenBSD stack: pf, relayd, httpd, smtpd, nsd, Rails apps, masterweb rc.d service.

## Requirements

- OpenBSD 7.8 (VPS) or proot Ubuntu (Termux)
- Ruby 3.3+, Bundler
- `OPENROUTER_API_KEY`

## License

MIT
