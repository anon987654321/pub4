# Post-Point Deployment Guide

**Status:** Pre-point completed ✓, DNS glue record updated ✓

## Prerequisites Checklist

- [x] Pre-point deployment completed (`--pre-point`)
- [x] DNS glue record for `ns.brgen.no` points to `185.52.176.18`
- [ ] DNS propagated (verify with `verify_dns.sh`)
- [ ] SSH access to VPS: `ssh dev@185.52.176.18`
- [ ] Latest code on VPS: `cd /home/dev/pub4 && git pull`

## Steps

### 1. Verify DNS Propagation

```zsh
# On local machine or VPS
zsh verify_dns.sh
```

**Expected output:**
```
✓ brgen.no → 185.52.176.18
✓ oshlo.no → 185.52.176.18
✓ trndheim.no → 185.52.176.18
✓ bsdports.org → 185.52.176.18
✓ amberapp.com → 185.52.176.18

Results: 5 passed, 0 failed

✓ DNS fully propagated - ready for: doas zsh openbsd.sh --post-point
```

If any fail, **wait 24-48 hours** after glue record update.

### 2. Connect to VPS

```zsh
ssh dev@185.52.176.18
```

### 3. Update Code

```zsh
cd /home/dev/pub4
git pull origin main
```

### 4. Run Post-Point Deployment

```zsh
doas zsh openbsd/openbsd.sh --post-point
```

**What it does:**
1. Validates environment (root access, OpenBSD version)
2. Configures `httpd` for ACME challenges (port 80)
3. Generates Let's Encrypt TLS certificates for **40+ domains**
4. Configures `relayd` reverse proxy (TLS termination on port 443)
5. Sets PTR records via OpenBSD Amsterdam API
6. Enables certificate auto-renewal cron jobs

**Duration:** 10-20 minutes

### 5. Verify Services

```zsh
# Check all services running
rcctl ls on

# Verify specific daemons
rcctl check httpd relayd nsd postgresql redis

# Check Rails apps
rcctl check brgen amber blognet bsdports hjerterom privcam pubattorney

# View logs
tail -f /var/log/messages
tail -f /var/log/rails/unified.log
```

### 6. Test HTTPS Access

```zsh
# From local machine
curl -I https://brgen.no
curl -I https://bsdports.org
curl -I https://amberapp.com
```

**Expected:** `HTTP/2 200` with valid TLS certificate

### 7. Submit DNSSEC DS Records

```zsh
# On VPS, get DS records
ls -lh /var/nsd/zones/keys/*.ds

# Submit each domain's DS record to its registrar
# Example for brgen.no:
cat /var/nsd/zones/keys/brgen.no.ds
```

## Troubleshooting

### ACME fails: "Domain does not resolve"
- DNS not propagated yet - wait longer
- Verify: `dig brgen.no @8.8.8.8`

### ACME fails: "Connection refused"
- Port 80 blocked by firewall
- Check: `pfctl -sr | grep 80`
- Fix: Already handled in script

### Relayd won't start
- Missing TLS certificates
- Check: `ls -lh /etc/ssl/*.crt`
- Re-run: `acme-client -v brgen.no`

### PTR fails: "Token invalid"
- Not on OpenBSD Amsterdam VM
- Script will skip PTR setup (non-critical)

### Can't resolve *.brgen.no subdomains
- DNSSEC DS records not submitted
- Submit DS records from `/var/nsd/zones/keys/*.ds` to Norid

## Architecture

```
Internet
  ↓
PF Firewall (ports 22, 53, 80, 443)
  ↓
┌────────────┬──────────────┬────────────┐
│            │              │            │
NSD:53      httpd:80    relayd:443    PostgreSQL
(DNS+DNSSEC) (ACME only)  (TLS term)    Redis
                            ↓
                         Falcon
                            ↓
           ┌────────────────┼────────────────┐
           ↓                ↓                ↓
      brgen:11006     amber:10001    blognet:10002
      (40+ domains)   bsdports:10003 hjerterom:10004
                      privcam:10005   pubattorney:10006
```

## OpenBSD Amsterdam PTR API

**Automatic via script:**
- Tokens fetched from `http://ptr4.openbsd.amsterdam/token`
- PTR set for `ns.brgen.no` on both IPv4 and IPv6
- 65-second propagation wait

**Manual verification:**
```zsh
dig -x 185.52.176.18
# Should return: ns.brgen.no
```

## Post-Deployment Checklist

- [ ] All domains resolve to `185.52.176.18`
- [ ] HTTPS works for all domains
- [ ] All Rails apps respond on their ports
- [ ] NSD DNS server responds: `dig @185.52.176.18 brgen.no`
- [ ] PTR record set: `dig -x 185.52.176.18`
- [ ] DNSSEC DS records submitted to registrars
- [ ] Certificate renewal cron jobs active: `crontab -l`

## Next Steps

1. Test each domain in browser
2. Monitor logs for errors
3. Set up monitoring/alerting
4. Document any custom configs
5. Backup `/etc` and `/var/nsd/zones`
