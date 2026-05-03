# MASTER

Constitutional AI coding agent. OpenBSD-first. Ruby-only. Self-hosting.

Reviews its own code, argues with itself via adversarial council, ships the result.

## Quick start

```zsh
cd ~/pub4/MASTER
bundle install
export OPENROUTER_API_KEY=...
bundle exec ruby exe/master
```

## Architecture

10-stage Result-monadic pipeline:

```
Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
```

Council and Lint run in parallel (30s timeout). Rollback on axiom violation.

## Key commands

```
/scan [deep|quick|critical]   Scan lib/ for violations
/sweep [path]                 Self-refactor loop (convergence-driven)
/autoloop [n]                 Fix violations autonomously, n cycles
/crit <file|text>             Adversarial council review
/soul                         Identity evolution commands
/model [id|list]              Show or switch model
/why <rule>                   Explain a scan rule
```

## Data files

`data/*.yml` is the living spec — replaces the old master.yml monolith:

| File | Purpose |
|---|---|
| `soul.yml` | Golden rule, anti-simulation, protection tiers |
| `rules.yml` | Structural rules, voice, zen principles |
| `ruby_style.yml` | Ruby/zsh/OpenBSD rules, banned commands |
| `workflow.yml` | Scan depths, autoloop config, anti-sprawl |
| `standing_orders.yml` | Current FSM state |
| `models.yml` | Model capability table |
| `council.yml` | Council personas and trigger patterns |

## Web UI

Rails 8 + Falcon on port 10002 (internal). relayd proxies to ai.brgen.no:4430.

Canvas: 2000-particle orb, ambient pad engine, drum sequencer, 17 voice FX.

## Deploy

```zsh
cd DEPLOY/openbsd && doas zsh openbsd.sh
```

## License

MIT
