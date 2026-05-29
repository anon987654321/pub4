# pub4

Constitutional AI coding agent and web platform. OpenBSD-first. Ruby-only.

## Layout

```
pub4/
  MASTER/          Constitutional AI agent (~6K LOC Ruby)
  DEPLOY/openbsd/  Two-stage OpenBSD deploy script (openbsd.sh)
  DEPLOY/rails/    Rails 8 sub-apps (brgen, amber, baibl, bsdports, …)
  multimedia/      Audio tools: TTS, Dilla, Postpro, Repligen
  dilla/           Audio mixes and dilla.html canvas
  sh/              Shell scripts
  index.html       Radio Bergen — warp tunnel visualizer
```

## Radio Bergen (`index.html`)

Audio-reactive 3D warp tunnel. Three.js for scene + particle rings; p5.js audio FFT modulates ring radius, particle density, and color gradient; Cannon.js gives particle physics. Mobile parallax via deviceorientation. City carousel cycles brgen domain names. Open in any modern browser, click to start audio.

## MASTER

Self-hosting AI agent that replaces Claude Code CLI on the VPS.

**For LLMs and autonomous agents:** Start here → `MASTER/QUICKSTART.md`

```zsh
cd MASTER && bundle exec ruby bin/cli
```

11-stage pipeline: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render

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
