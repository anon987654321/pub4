# pub4 - Rails 8 Production Apps on OpenBSD

Seven production Rails 8 applications deployed on OpenBSD 7.6+ with Falcon, governed by master.yml v85.0.

## Projects

### brgen (port 11006)
Reddit-style community platform with X.com design aesthetic. Anonymous posting, voting, nested comments, live search via StimulusReflex, marketplace (markedsplass subdomain), playlists, dating, maps integration. Covers 20+ Nordic/European cities.

**Domains:** brgen.no, oshlo.no, trndheim.no, stvanger.no, trmso.no, reykjavk.is, kobenhvn.dk, stholm.se, gteborg.se, mlmoe.se, hlsinki.fi, lndon.uk, mnchester.uk, brmingham.uk, edinbrgh.uk, glasgw.uk, lverpool.uk, amstrdam.nl, rottrdam.nl, utrcht.nl, brssels.be, zrich.ch, lchtenstein.li, frankfrt.de, mrseille.fr, mlan.it, lsbon.pt

### amber (port 10001)
AI-powered fashion wardrobe assistant. Computer vision for outfit recognition, style recommendations via LangChain, wardrobe management, outfit planning. Norwegian interface with dark theme.

**Domain:** amberapp.com

### blognet (port 10002)
Multi-blog network with engagement scoring, trending feeds, PWA support. Anti-gambling advocacy blogs, food reviews, Norwegian football commentary.

**Domains:** foodielicio.us, stacyspassion.com, antibettingblog.com, anticasinoblog.com, antigamblingblog.com, foball.no

### bsdports (port 10003)
Browser for OpenBSD ports system. Search, browse, view dependencies, installation guides. Minimalist design inspired by man.openbsd.org.

**Domain:** bsdports.org

### hjerterom (port 10004)
Food redistribution platform connecting donors with recipients. Mapbox integration, Vipps payment, analytics dashboard, Norwegian interface.

**Domain:** hjerterom.no

### privcam (port 10005)
Privacy-focused webcam service. No cloud storage, end-to-end encryption, self-hosted, WebRTC streaming.

**Domain:** privcam.no

### pubattorney (port 10006)
Free legal help platform. Q&A system, document templates, Norwegian legal resources, anonymous consultations.

**Domains:** pub.attorney, freehelp.legal

## Stack

Ruby 3.3, Rails 8.0.4, Falcon, Solid Queue/Cache/Cable, Hotwire, StimulusReflex, SQLite3, LangChain, OpenBSD 7.6+ (relayd/httpd/pf/acme-client), Let's Encrypt

## Media Tools

- **postpro.rb** - FFmpeg video post-processing
- **repligen.rb** - Multi-platform video generator
- **dilla.rb** - J Dilla-style audio swing

## CLI

- **cli.rb** - Interactive Rails generator
- **master.yml** v85.0 - Constitutional governance

## Deployment

Local:
```zsh
cd rails/appname
bundle install && rails db:migrate db:seed && rails server
```

Production:
```zsh
doas pkg_add git ruby ruby33-bundler node
git clone https://github.com/anon987654321/pub4.git && cd pub4
doas zsh openbsd/openbsd.sh
doas zsh rails/appname/appname.sh
doas rcctl enable appname && doas rcctl start appname
```

Verify:
```zsh
rcctl check appname && curl http://localhost:1000X && curl -I https://domain.com
```

## master.yml

Self-optimizing constitutional document enforcing:
- Zsh-only (no bash/sed/awk)
- Ruby-only logic
- Preserve-then-improve
- Security-first
- Zero sprawl

v85.0: 5 cycles max, <2% threshold

## Structure

```
pub4/
├── master.yml
├── cli.rb
├── rails/{amber,blognet,brgen,bsdports,hjerterom,privcam,pubattorney}/
├── openbsd/{openbsd.sh,README.md}
├── media/{postpro,repligen,dilla}.rb
└── sh/
```

## Changelog (2025-12-21)

**Rails:** 42 scripts → 7 apps + 12 modules | SQLite3, LangChain, Hotwire, stimulus-components

**OpenBSD:** relayd/pf/acme-client, rc.d services

**Media:** Consolidated, optimized

**master.yml:** v78→85 (Grok/ChatGPT/DeepSeek: structure, security, recovery, Zsh patterns)

**Result:** Zero sprawl, lowercase/underscores, Zsh-native

## Contributing

Pass master.yml principles, use Zsh patterns, preserve behavior, clear commits, self-optimize to <2%.
