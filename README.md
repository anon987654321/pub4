# pub4 - Modern Rails 8 on OpenBSD

Production-ready Rails 8 applications deployed on OpenBSD 7.6+ with Falcon, using Zsh-native patterns and master.yml governance.

## System Architecture

**Stack:**
- Ruby 3.3 + Rails 8.0.4
- Falcon (async HTTP/2 server)
- Solid Queue/Cache/Cable (Redis-free)
- Hotwire + StimulusReflex + Stimulus Components
- OpenBSD 7.6+ with relayd/httpd/pf
- SQLite3 (development/production)
- LangChain for AI features

**Infrastructure:**
- VPS: 185.52.176.18 (server27.openbsd.amsterdam)
- TLS: Let's Encrypt via acme-client
- Proxy: relayd → httpd → Falcon (ports 10001-10006, 11006)
- Firewall: pf with strict ruleset

## Rails Applications

### Core Apps (ports 10001-10006)
- **amber** (10001) - AI Fashion Wardrobe Assistant - amberapp.com
- **blognet** (10002) - Multi-blog Platform - foodielicio.us, stacyspassion.com
- **bsdports** (10003) - BSD Ports Browser - bsdports.org
- **hjerterom** (10004) - Food Redistribution - hjerterom.no
- **privcam** (10005) - Privacy-First Webcam - privcam.no
- **pubattorney** (10006) - Legal Help Platform - pub.attorney, freehelp.legal

### Flagship App (port 11006)
- **brgen** - Reddit-style Community Platform
  - Main: brgen.no + 20 Nordic/European domains
  - Subdomains: marketplace, playlist, dating, tv, takeaway, maps

## Media Processing Tools

Ruby scripts for video/audio processing:
- **postpro.rb** - FFmpeg video post-processing (metadata, thumbnails)
- **repligen.rb** - Multi-platform video generator (YouTube/TikTok/Instagram)
- **dilla.rb** - Audio beat manipulation (J Dilla-style swing)

## CLI Tools

- **cli.rb** - Interactive Rails generator with Claude Code integration
- **master.yml** - Constitutional governance document (v85.0)

## Deployment

### Local Development
```zsh
cd rails/appname
bundle install
rails db:migrate db:seed
rails server  # Uses Falcon
```

### Production Deployment
```zsh
# On VPS
doas pkg_add git ruby ruby33-bundler node
cd /home/dev && git clone https://github.com/anon987654321/pub4.git
cd pub4/openbsd && doas zsh openbsd.sh  # Setup infrastructure
cd pub4/rails/appname && doas zsh appname.sh  # Deploy app
doas rcctl enable appname && doas rcctl start appname
```

### Verification
```zsh
rcctl check appname  # Should show "appname(ok)"
curl http://localhost:1000X  # Test backend
curl -I https://domain.com  # Test TLS frontend
```

## master.yml Governance

Self-optimizing constitutional document enforcing:
- Zsh-only patterns (no bash/sed/awk/grep)
- Ruby for all logic (no Python)
- Preserve-then-improve doctrine
- Security-first architecture
- Zero file sprawl

**Current Version:** v85.0.0  
**Self-optimization cycles:** 5 max, <2% improvement threshold

## Project Structure

```
pub4/
├── master.yml          # Constitutional governance
├── cli.rb             # Interactive Rails generator
├── rails/             # Rails 8 applications
│   ├── amber/
│   ├── blognet/
│   ├── brgen/
│   ├── bsdports/
│   ├── hjerterom/
│   ├── privcam/
│   ├── pubattorney/
│   └── *.sh           # Shared modules (auth, stack, hotwire, etc.)
├── openbsd/
│   ├── openbsd.sh     # VPS infrastructure setup
│   └── README.md      # OpenBSD deployment guide
├── media/
│   ├── postpro.rb     # Video post-processing
│   ├── repligen.rb    # Multi-platform video generator
│   └── dilla.rb       # Audio beat manipulation
└── sh/                # Utility scripts (tree.sh, clean.sh, etc.)
```

## Session Changelog (2025-12-21)

### Rails Applications
- ✅ Consolidated 42 scripts into 7 app-based folders
- ✅ Extracted shared logic into 12 feature modules (@auth, @stack, @hotwire, etc.)
- ✅ Removed @shared_functions.sh file sprawl
- ✅ Fixed Falcon config syntax (symbols → strings)
- ✅ Integrated LangChain into all apps
- ✅ Added comprehensive views with Rails tag helpers (no divitis)
- ✅ Integrated stimulus-components.com throughout
- ✅ Switched all apps to SQLite3

### OpenBSD Infrastructure
- ✅ Updated relayd.conf with all app backends
- ✅ Configured pf.conf firewall rules
- ✅ Setup acme-client for Let's Encrypt
- ✅ Created rc.d services for all apps
- ✅ Verified man.openbsd.org documentation compliance

### Media Tools
- ✅ Consolidated repligen/ sprawl into single repligen.rb
- ✅ Optimized postpro.rb through master.yml
- ✅ Enhanced dilla.rb with proper error handling

### master.yml Evolution
- v78.0: Added silent_success, tool_permissions wildcards, overrides
- v79.5: Merged Grok's structural improvements
- v80.0: Added immutability boundaries (ChatGPT suggestions)
- v80.2: Fixed DeepSeek-identified gaps (cross-platform paths, secret management)
- v81.0: Added disaster recovery, health checks, backup procedures
- v85.0: Comprehensive Zsh patterns, error recovery, environment detection

### Key Improvements
- Zero file sprawl (reduced from 60+ files to organized structure)
- All shared logic in feature modules
- Consistent naming conventions (lowercase, underscores)
- No ASCII decorations in comments
- Zsh-native patterns throughout
- Security-first secret management

## Contributing

All changes must:
1. Pass through master.yml principles
2. Use Zsh patterns (no forbidden commands)
3. Preserve existing behavior
4. Include clear commit messages
5. Self-optimize until <2% improvement

## License

Private repository - All rights reserved
