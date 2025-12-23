# Brgen - Bergen Social Platform

**Version:** 8.0.0  
**Stack:** Rails 8 + Solid Stack + Falcon  
**Port:** 37824  
**Domains:** 35+ international city domains

## Overview

Brgen (Bergen) is a comprehensive social platform serving 35+ city-branded domains across Europe and North America. Built with Rails 8 and the Solid Stack, it provides a unified backend for multiple city-specific frontends.

## Features

### Core Platform
- **Multi-tenancy**: Acts as tenant system for city isolation
- **Authentication**: Devise + guest accounts
- **Real-time**: StimulusReflex for reactive UI
- **Background jobs**: Solid Queue
- **Caching**: Solid Cache
- **WebSockets**: Solid Cable
- **Assets**: Propshaft (Rails 8 default)

### Sub-applications
Each runs on the same backend with different branding:

1. **markedsplass** (Marketplace) - Buy/sell/trade locally
2. **playlist** - Music sharing and discovery
3. **dating** - City-based dating platform
4. **tv** - Video streaming and sharing
5. **takeaway** - Food delivery coordination
6. **maps** - City navigation and POIs

## Architecture

```
Internet → PF Firewall → Relayd (TLS) → Falcon → Rails 8
                                                    ↓
                                          Solid Stack (Queue/Cache/Cable)
                                                    ↓
                                                PostgreSQL
```

### Domains Served

**Norway:** brgen.no, oshlo.no, trndheim.no, stvanger.no, trmso.no  
**Nordic:** reykjavk.is, kobenhvn.dk, stholm.se, gteborg.se, mlmoe.se, hlsinki.fi  
**UK:** lndon.uk, mnchester.uk, brmingham.uk, edinbrgh.uk, glasgw.uk, lverpool.uk  
**Europe:** amstrdam.nl, rottrdam.nl, utrcht.nl, brssels.be, zrich.ch, lchtenstein.li  
**Continental:** frankfrt.de, mrseille.fr, mlan.it, lsbon.pt  
**North America:** lsangeles.com, newyrk.us, chcago.us, dtroit.us, houstn.us, dllas.us, austn.us, prtland.com, mnneapolis.com

## Quick Start

```zsh
cd /home/dev/rails
./brgen/brgen.sh
```

The generator will set up everything automatically.

## Documentation

For detailed setup, configuration, deployment, and troubleshooting:
- Installation instructions
- Environment variables
- Service management
- Performance tuning
- Security best practices

See the full documentation at `/docs/brgen/` or visit https://brgen.no/docs

---
**Built with ❤️ in Bergen, Norway**
