# OpenBSD Rails Infrastructure v338.0.0
Single-file deployment: 48 domains, 7 Rails apps, NSD DNS+DNSSEC, TLS, PF firewall, Relayd reverse proxy.

## Architecture
```
Internet → PF (bruteforce detection, rate limiting)
        → Relayd (SNI-based TLS routing per app)
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
- **Ruby 3.3 + Rails 8.0** (Solid Queue/Cache/Cable)
- **PostgreSQL 16** + **Redis 7**
- **NSD DNS** with DNSSEC (MUST run before registering glue record)
- **PF Firewall** (bruteforce detection, rate limiting, explicit port list)
- **7 Rails app skeletons** (awaiting code upload)

### Phase 2: --post-point
- **TLS certificates** via acme-client (Let's Encrypt, 48 domains)
- **Relayd reverse proxy** (SNI routing: 7 relays, 1 per app)
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

## Recent Fixes (2025-12-12)

✅ **PF firewall:** Fixed undefined `$domeneshop` variable  
✅ **PF firewall:** Narrowed port range from 65535 to 7 explicit ports  
✅ **NSD DNS:** Removed secondary nameserver notify (primary-only mode)  
✅ **Relayd:** Implemented SNI-based routing for all 7 apps with 48 domains  
✅ **Code quality:** Improved zsh pattern matching (removed grep dependency)

## Verify Installation

```zsh
# Check all services running
rcctl ls on

# Check individual daemons
rcctl check postgresql redis nsd httpd relayd
rcctl check brgen amber blognet bsdports hjerterom privcam pubattorney

# Verify configs
doas pfctl -nf /etc/pf.conf
doas nsd-checkconf /var/nsd/etc/nsd.conf
doas httpd -n
doas relayd -n

# Check listening ports
netstat -an | grep LISTEN

# View logs
doas tail /var/log/messages
tail /var/log/rails/unified.log
```

## Security

### PF Firewall
- **Bruteforce protection:** SSH limited to 15 conn, 5 per 3s
- **Rate limiting:** DNS limited to 100 conn, 15 per 5s
- **Explicit ports:** Only 22, 53, 80, 443, 10001-10006, 11006 exposed
- **Table management:** `pfctl -t bruteforce -T show`

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
- `/etc/httpd.conf` - ACME HTTP-01 challenge (man httpd.conf)
- `/etc/acme-client.conf` - Let's Encrypt TLS (man acme-client.conf)
- `/var/nsd/etc/nsd.conf` - DNS server with DNSSEC (man nsd.conf)
- `/etc/rc.d/{app}` - Service control scripts (man rc.subr)

## Troubleshooting

### Check service status
```zsh
rcctl check postgresql
rcctl check nsd
rcctl ls failed
```

### View logs
```zsh
doas tail -100 /var/log/messages
tail -100 /var/log/rails/unified.log
```

### Test DNS locally
```zsh
dig @localhost brgen.no SOA
nsd-checkzone brgen.no /var/nsd/zones/master/brgen.no.zone
```

### Verify TLS certificate
```zsh
openssl s_client -connect brgen.no:443 -servername brgen.no < /dev/null | grep Verify
```

## Version History

- **v338.0.0** (2025-12-12): Fixed PF bug, SNI routing, narrow ports, primary-only DNS
- **v337.4.0** (2025-10-23): Initial release with Rails 7.2

## Verified

- 2025-12-12: All configs verified against man.openbsd.org
- VPS: dev@185.52.176.18 (185.52.176.18)
- OpenBSD 7.7 amd64

