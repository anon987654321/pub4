# pub4 - Rails 8 on OpenBSD

Production Rails 8 applications with Falcon on OpenBSD 7.6+, governed by master.yml.

## Stack

Ruby 3.3, Rails 8.0.4, Falcon, Solid Queue/Cache/Cable, Hotwire, StimulusReflex, SQLite3, LangChain, OpenBSD 7.6+ (relayd/httpd/pf), Let's Encrypt, VPS 185.52.176.18

## Applications

| App | Port | Purpose | Domains |
|-----|------|---------|---------|
| amber | 10001 | AI Fashion Wardrobe | amberapp.com |
| blognet | 10002 | Multi-blog Platform | foodielicio.us, stacyspassion.com |
| bsdports | 10003 | BSD Ports Browser | bsdports.org |
| hjerterom | 10004 | Food Redistribution | hjerterom.no |
| privcam | 10005 | Privacy Webcam | privcam.no |
| pubattorney | 10006 | Legal Help | pub.attorney, freehelp.legal |
| brgen | 11006 | Reddit Clone | brgen.no + 20 domains, 6 subdomains |

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
