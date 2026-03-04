# Brgen - Bergen Social Platform
**Version:** 8.0.0
**Stack:** Rails 8 + Solid Stack + Falcon + PostgreSQL + Redis

**Port:** dynamic (persisted in `/etc/master_app_ports.conf`)

**Domains:** 35+ international city domains

## Overview
Brgen (Bergen) is a comprehensive social platform serving 35+ city-branded domains across Europe and North America. Built with Rails 8 and the Solid Stack, it provides a unified backend for multiple city-specific frontends.

## Architecture
```
          CDN (Cloudflare / Fastly)
                   │
            Load Balancer
              (relayd)
          ┌────────┴────────┐
       Node 1            Node 2
      (brgen)           (brgen)
          │                 │
    PostgreSQL         Read Replica
     (primary)          (standby)
          └────── Redis ─────┘
                 (Action Cable)
```

### Topology
- **Web:** Falcon (async, multi-threaded)
- **Jobs:** Solid Queue (database-backed, no Sidekiq)
- **Cache:** Solid Cache (database-backed, sharded)
- **WS:** Solid Cable + Redis pub/sub
- **DB pool:** PgBouncer (transaction mode, 10k clients)
- **Rate limiting:** Rails 8 built-in `rate_limit`

## Prerequisites
- Ruby 3.4+
- PostgreSQL 16
- Redis 7
- Falcon (`gem install falcon`)

## Environment Variables
| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string via PgBouncer |
| `RAILS_MASTER_KEY` | Rails credentials master key |
| `RAILS_ENV` | Set to `production` on server |

## Features
### Core Platform
- **Multi-tenancy**: Acts as tenant system for city isolation
- **Authentication**: Rails 8 built-in (`bin/rails generate authentication`)
- **Real-time**: Turbo Streams + Action Cable
- **Background jobs**: Solid Queue
- **Caching**: Solid Cache
- **WebSockets**: Solid Cable
- **Rate limiting**: `rate_limit to: 1000, within: 1.minute`

### Sub-applications
1. **markedsplass** (Marketplace) - Buy/sell/trade locally
2. **playlist** - Music sharing and discovery
3. **dating** - City-based dating platform
4. **tv** - Video streaming and sharing
5. **takeaway** - Food delivery coordination
6. **maps** - City navigation and POIs

### Domains Served
**Norway:** brgen.no, oshlo.no, trndheim.no, stvanger.no, trmso.no
**Nordic:** reykjavk.is, kobenhvn.dk, stholm.se, gteborg.se, mlmoe.se, hlsinki.fi
**UK:** lndon.uk, mnchester.uk, brmingham.uk, edinbrgh.uk, glasgw.uk, lverpool.uk
**Europe:** amstrdam.nl, rottrdam.nl, utrcht.nl, brssels.be, zrich.ch, lchtenstein.li
**Continental:** frankfrt.de, mrseille.fr, mlan.it, lsbon.pt
**North America:** lsangeles.com, newyrk.us, chcago.us, dtroit.us, houstn.us, dllas.us, austn.us, prtland.com, mnneapolis.com

## Deploy
```zsh
# First run (Stage 1: DNS + certs)
doas zsh openbsd.sh

# After DNS propagation (Stage 2: services + apps)
doas zsh openbsd.sh --resume
```

## Scaling
Add nodes via relayd — update the table in `/etc/relayd.conf` and reload:
```
rcctl reload relayd
```
Each additional node needs:
1. The app deployed to `/home/brgen/app`
2. An rc.d service enabled
3. PgBouncer pointed at the primary PostgreSQL

## Monitoring
- Rails log: `/home/brgen/app/log/production.log`
- Solid Queue: `bin/rails solid_queue:supervisor` status
- PgBouncer stats: `psql -p 6432 -U pgbouncer pgbouncer -c "SHOW STATS;"`

---
**Built with in Bergen, Norway**
