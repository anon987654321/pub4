# pub4

A map of the four trees after the 2026-09-05 sprawl pass, not a census.
Live counts live in `MASTER/data/sprawl_census.yml`. One-file directories
that remain are priced: OS install paths, Zeitwerk, Rails `test/system`,
ports fixtures, OmniAuth, PWA, and dilla vocal/render takes.

```
pub4/
│
├── CLAUDE.md                 one screen
├── TODO.md                   the backlog
├── TREE.md                   this map
│
├── MASTER/                   the product — a constitutional Ruby runtime
│   ├── bin/master            instruction surface
│   ├── bin/pub4              operator surface
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
│   │   ├── voice/            Osman; Playback speaks a TTY reply
│   │   ├── fix/
│   │   ├── boot/
│   │   └── pub4/
│   ├── spec/                 flattened — isolation, smells, lifecycle sit here
│   ├── test/
│   ├── tools/
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
│   │   └── support/design_metrics_contrast.rb   hoisted from design_metrics/
│   ├── apps.yml              feature truth
│   └── bin/triangle          bring the three up
│
├── OPENBSD/                  deploy pipeline; production is one box, vm23
│   ├── etc/                  relayd, pf, acme — read the man page first
│   ├── bin/vps-deploy
│   ├── RUNBOOK.md
│   └── dotfiles/             sketchybar, skhd — priced OS paths
│
└── STUDIO/                   media tools
    ├── dilla/                beats — renders belong under renders/<seed>/
    ├── postpro/              grade
    ├── repligen/
    ├── lora/
    │   └── _toolkit/toolkit.sh              renamed from lib.sh
    ├── isolation.rb          hoisted from tools/
    └── test/
```

Twenty one-file directories remain, all mandated or priced. Stutter is
zero. Three vague names remain, all Zeitwerk (`lib/io/base.rb` and its
kin). Hoisting a Rails system test out of `test/system/` would run it in
the unit suite and drop it from `rails test:system`; those two stayed.
