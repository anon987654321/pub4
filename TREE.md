# pub4

A map of the three top-level trees after the 2026-09-05 sprawl pass, not a census.
Live counts live in `MASTER/data/sprawl_census.yml`. One-file directories
that remain are priced: OS install paths, Zeitwerk, Rails `test/system`,
ports fixtures, OmniAuth, PWA, and dilla vocal/render takes.

```
pub4/
│
├── CLAUDE.md                 one screen — and AGENTS, GEMINI, .cursorrules,
│                             .github/copilot-instructions, all generated from
│                             MASTER/AGENTS.md by rake docs:agent_contracts
├── TODO.md                   the backlog
├── TREE.md                   this map
│
├── MASTER/                   the product — a constitutional Ruby runtime
│   ├── bin/master            instruction surface
│   ├── bin/operator              operator surface
│   ├── bin/cli               the same runtime, slash commands
│   ├── completions/_master   zsh completion (priced: the name is the command)
│   ├── data/                 law as YAML — soul.yml outranks everything
│   │   ├── soul.yml
│   │   ├── rules.yml
│   │   ├── pub_archive_restore.yml          hoisted from lessons/
│   │   └── radio_bergen_track_dossiers.yml  hoisted from reports/
│   ├── law/                  one domain file per body of law
│   ├── lib/
│   │   ├── core/             fold spine
│   │   ├── cli/
│   │   ├── review/           scanners
│   │   ├── ground/
│   │   ├── io/
│   │   ├── voice/            speech, persona; Playback speaks a TTY reply
│   │   ├── fix/
│   │   ├── boot/
│   │   ├── cognition/        perception, affect, reflection (COGNITION.md)
│   │   ├── operator/         bin/operator and bin/check libraries
│   │   └── trace/            event bus, logs, session, undo
│   ├── test/
│   ├── tools/                canonical tool plane
│   │   ├── dilla/            beats
│   │   ├── postpro/          image grading
│   │   ├── preprompt/        image generation
│   │   ├── bplans/           business-plan source
│   │   ├── lora/             training/media workflows
│   │   ├── isolation.rb      tool isolation runner
│   │   └── test/             tool suites
│   └── web/                  the face
│       └── test/master_auth_config.yml      hoisted from fixtures/
│
├── RAILS/                    three Rails 8 apps
│   ├── brgen/                city social network; verticals are engines
│   │   ├── test/             one-file type dirs hoisted (mailers, tasks, support)
│   │   └── test/system/      stays — rails test:system globs this path
│   ├── amber/
│   │   └── test/             same hoist; public_navigation stays in test/system/
│   ├── bsdports/
│   │   └── test/             makefile parser hoisted one level; ports fixtures stay
│   ├── shared/               engine every app mounts
│   ├── gates/                design and deploy measurements
│   │   ├── gates.yml         one row per gate: class, pass line, preconditions
│   │   └── support/design_metrics/   contrast, contrast_checks, type_checks
│   ├── mobile/               store registry; android/ and ios/ native shells
│   ├── apps.yml              feature truth
│   └── bin/triangle          bring the three up
│
├── OPENBSD/                  deploy pipeline; production is one box, vm23
│   ├── etc/                  relayd, pf, acme — read the man page first
│   ├── bin/vps-deploy
│   ├── bin/vps_console.exp   the one console door; each recovery mode is an argument
│   ├── RUNBOOK.md
│   └── dotfiles/             sketchybar, skhd — priced OS paths
│
```

Nineteen one-file directories remain, all mandated or priced. Stutter is
zero. Two vague names remain, both Zeitwerk (`lib/io/base.rb` and
`lib/boot/data.rb`). Hoisting a Rails system test out of `test/system/`
would run it in the unit suite and drop it from `rails test:system`;
those two stayed. The three counts come from
`MASTER/data/sprawl_census.yml`; `bin/operator measure --why sprawl.lone_dirs`
names the members rather than leaving this paragraph to remember them.

The grammar that keeps this map short. The three governed trees stay at the root and MASTER/tools stays inside MASTER; they are
never nested under an `apps/`. Files move only when their location breaks a
rule, never because a listing would look tidier. `RAILS/shared/` gives nothing
to a `platform/` until a second app consumes it, and brgen's engines are product
domains only. `RAILS/gates/` keeps its name: renaming it `verification/` would
move the runner, `gates.yml` and every ownership row for no reader.
Ownership-free names (`misc/`, `utils/`, `common/`, `old/`) are refused
everywhere a framework does not dictate them; Rails `app/helpers/` is
convention, not a drawer.
