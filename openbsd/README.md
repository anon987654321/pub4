# OpenBSD Rails Infrastructure v337.3.0
Two-phase deployment: 40+ domains, 7 Rails apps, NSD DNS+DNSSEC, TLS, PF firewall, Relayd reverse proxy.

## Architecture
```

Internet → PF (synproxy, rate limit, bruteforce)
        → Relayd (TLS termination, port 443)
        → Falcon (async HTTP server)
        → Rails apps
DNS: NSD with DNSSEC (ECDSAP256SHA256)
```

## Two-Phase Deployment
### Phase 1: Pre-Point (before DNS glue record)

```bash

scp openbsd.sh dev@brgen.no:/home/dev/
ssh dev@brgen.no
doas zsh openbsd.sh --pre-point
```
Sets up:
- Ruby 3.3 + Rails 8.1 + Falcon async HTTP

- PostgreSQL + Redis
- **NSD DNS with DNSSEC** (MUST run before glue registration)
- PF firewall (synproxy, rate limiting, bruteforce detection)
- 7 Rails apps on ports 10001-11006
**CRITICAL**: NSD must be running on port 53 BEFORE registering `ns.brgen.no` glue record at Norid.
### Phase 2: Post-Point (after DNS propagation)

```bash

# After: 1) Norid accepts ns.brgen.no, 2) DNS propagates
doas zsh openbsd.sh --post-point
```
Sets up:
- TLS certificates via acme-client (Let's Encrypt)

- Relayd reverse proxy (port 443 → brgen:11006)
- PTR records (OpenBSD Amsterdam)
- Cron jobs (certificate renewal)
## Apps & Ports
- **brgen:11006** - 40+ city domains (brgen.no, oshlo.no, lndon.uk, etc.)

- **amber:10001** - amberapp.com
- **blognet:10002** - foodielicio.us, stacyspassion.com, etc.
- **bsdports:10003** - bsdports.org
- **hjerterom:10004** - hjerterom.no
- **privcam:10005** - privcam.no
- **pubattorney:10006** - pub.attorney, freehelp.legal
## Requirements
- OpenBSD 7.7+
- Root/doas access
- Public IP: 185.52.176.18
- ~2GB RAM, 10GB disk
## Verify Daemons
```bash

# Check all services
rcctl ls on
# Check individual daemons
rcctl check httpd relayd postgresql redis nsd

# Check Rails apps
rcctl check brgen amber blognet bsdports hjerterom privcam pubattorney

# View logs
tail -f /var/log/messages

tail -f /var/log/rails/unified.log
```
## Security
### PF Firewall

- **Synproxy**: TCP SYN flood protection on ports 22, 80, 443

- **Rate limiting**: Max 50 connections/30s per IP, overload to `<ratelimit>` table
- **Bruteforce protection**: SSH limited to 15 conn/60s, overload to `<bruteforce>` table
- **Scrubbing**: no-df, random-id, max-mss 1440
### Relayd Security Headers (OWASP Secure Headers)
Request headers:

- `X-Forwarded-For: $REMOTE_ADDR`
- `X-Forwarded-Proto: https`
Response headers (added 2025-10-16):
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`

- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: geolocation=(), microphone=(), camera=()`
- `Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'`
### DNSSEC
- Algorithm: ECDSAP256SHA256 (algorithm 13)

- ZSK + KSK per domain
- Zone signing with NSEC3 salt
- DS records at /var/nsd/zones/keys/*.ds (submit to registrar)
## Configuration Files
- `/etc/pf.conf` - Firewall (verified against man.openbsd.org/pf.conf)

- `/etc/relayd.conf` - Reverse proxy (verified against man.openbsd.org/relayd.conf)
- `/etc/httpd.conf` - ACME HTTP-01 challenge server
- `/etc/acme-client.conf` - Let's Encrypt TLS certificates
- `/etc/nsd/nsd.conf` - DNS server with DNSSEC
- `/etc/rc.d/{app}` - Service control scripts
## Verified
- 2025-10-16: All configs verified against official OpenBSD man pages

- VPS: dev@brgen.no (185.52.176.18)
- Version: 337.3.0 (matches master.json)
