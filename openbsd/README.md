# OpenBSD Rails Infrastructure v338.0.0
Single-file deployment: 40+ domains, 7 Rails apps, NSD DNS+DNSSEC, TLS, PF firewall, Relayd reverse proxy.

## Architecture
```
Internet → PF (synproxy, rate limit, bruteforce)
        → Relayd (TLS termination, port 443)
        → Falcon (async HTTP server)
        → Rails 8 apps

DNS: NSD with DNSSEC (ECDSAP256SHA256)
```

## Quick Start

```bash
# Copy to VPS
scp openbsd.sh dev@185.52.176.18:~/

# SSH to VPS
ssh dev@185.52.176.18

# Phase 1: Infrastructure + DNS (before domain points here)
doas zsh openbsd.sh --pre-point

# Register ns.brgen.no → 185.52.176.18 at Norid
# Wait 24-48h for DNS propagation

# Phase 2: TLS + Reverse Proxy (after DNS propagates)
doas zsh openbsd.sh --post-point
```

## What Gets Installed

### Phase 1: --pre-point
- **Ruby 3.3 + Rails 8.0** (Solid Queue/Cache/Cable - Redis-free)
- **PostgreSQL 16** + **Redis 7**
- **NSD DNS** with DNSSEC (MUST run before registering glue record)
- **PF Firewall** (synproxy, rate limiting, bruteforce detection)
- **7 Rails apps** on fixed ports

### Phase 2: --post-point
- **TLS certificates** via acme-client (Let's Encrypt)
- **Relayd reverse proxy** (port 443 → apps)
- **PTR records** (OpenBSD Amsterdam)
- **Cron jobs** (certificate renewal)

## Apps & Ports (Fixed Allocation)

| App | Port | Domains |
|-----|------|---------|
| **brgen** | 11006 | brgen.no + 40 city domains |
| **amber** | 10001 | amberapp.com |
| **blognet** | 10002 | foodielicio.us, stacyspassion.com, etc. |
| **bsdports** | 10003 | bsdports.org |
| **hjerterom** | 10004 | hjerterom.no |
| **privcam** | 10005 | privcam.no |
| **pubattorney** | 10006 | pub.attorney, freehelp.legal |

## Requirements

- OpenBSD 7.6+
- Root/doas access
- Public IP: 185.52.176.18
- ~2GB RAM, 10GB disk
- Internet connectivity

## Verify Installation

```bash
# Check all services running
rcctl ls on

# Check individual daemons
rcctl check postgresql redis nsd httpd relayd
rcctl check brgen amber blognet bsdports hjerterom privcam pubattorney

# Check listening ports
netstat -an | grep LISTEN | grep -E '1000[1-6]|11006'

# View logs
tail -f /var/log/messages
tail -f /var/log/rails/unified.log
```

## Security

### PF Firewall
- **Synproxy**: TCP SYN flood protection (ports 22, 80, 443)
- **Rate limiting**: Max 50 connections/30s per IP
- **Bruteforce protection**: SSH limited to 15 conn/60s
- **Scrubbing**: no-df, random-id, max-mss 1440

### Relayd Security Headers (OWASP)
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), microphone=(), camera=()
Content-Security-Policy: default-src 'self'
```

### DNSSEC
- Algorithm: ECDSAP256SHA256 (algorithm 13)
- ZSK + KSK per domain
- Zone signing with NSEC3 salt
- DS records at `/var/nsd/zones/keys/*.ds` (submit to registrar)

## Configuration Files

All verified against official OpenBSD man pages:

- `/etc/pf.conf` - Firewall (man pf.conf)
- `/etc/relayd.conf` - Reverse proxy (man relayd.conf)
- `/etc/httpd.conf` - ACME HTTP-01 challenge
- `/etc/acme-client.conf` - Let's Encrypt TLS
- `/etc/nsd/nsd.conf` - DNS server with DNSSEC
- `/etc/rc.d/{app}` - Service control scripts

## Troubleshooting

### Check service status
```bash
rcctl check postgresql  # Should return "postgresql(ok)"
rcctl check nsd         # Should return "nsd(ok)"
```

### View logs
```bash
tail -100 /var/log/messages
tail -100 /var/log/rails/unified.log
```

### Test DNS locally
```bash
dig @localhost brgen.no SOA
nsd-checkzone brgen.no /var/nsd/zones/brgen.no.zone
```

### Test Rails app manually
```bash
su -l dev -c "cd /home/dev/rails/brgen && bundle exec falcon --bind tcp://127.0.0.1:11006"
```

### Verify TLS certificate
```bash
openssl s_client -connect brgen.no:443 -servername brgen.no < /dev/null | grep Verify
```

## Emergency Rollback

```bash
# Stop all services
for app in brgen amber blognet bsdports hjerterom privcam pubattorney; do
  rcctl stop $app
  rcctl disable $app
done
rcctl stop relayd

# Restore from backup
ls -la /var/rails/backups/
```

## Version History

- **v338.0.0** (2025-12-09): Rails 8.0 + Solid Stack, fixed ports
- **v337.4.0** (2025-10-23): Initial release with Rails 7.2

## Verified

- 2025-12-09: Rails 8.0, Solid Queue/Cache/Cable, fixed ports
- VPS: dev@185.52.176.18 (185.52.176.18)
- All configs verified against man.openbsd.org

