# OpenBSD deploy

Two-stage VPS installer for pub4. Target: OpenBSD 7.8+, vm23 (`46.23.89.226`).

## VM provisioning (OpenBSD Amsterdam)

Provider welcome email from Mischa, 2026-05-17. Operator record — not secrets.

| Field | Value |
|-------|-------|
| VMM host | `server4.openbsd.amsterdam` |
| VM name | `vm23` |
| SSH user | `dev` |
| SSH key | `~/.ssh/id_ed25519_brgen` (same key on VM and hypervisor) |

**IPv4**

| | |
|-|-|
| Address | `46.23.89.226` |
| Subnet | `255.255.255.192` (`/26`) |
| Gateway | `46.23.89.193` |

**IPv6**

| | |
|-|-|
| Address | `2a03:6000:6e64:623::226` |
| Prefix | `/64` |
| Gateway | `2a03:6000:6e64:623::1` |

**Access**

```zsh
# VM (app host) — direct once unbanned
ssh dev@46.23.89.226

# Hypervisor (for pf bruteforce ban, wedged networking, or console)
ssh -p 31415 -i ~/.ssh/id_ed25519_brgen -o VerifyHostKeyDNS=yes dev@server4.openbsd.amsterdam
vmctl status vm23
vmctl console vm23          # inside: login, pfctl -t bruteforce -T flush ; exit with ~.
```

See DEPLOY/openbsd/unban_pf.sh for a one-shot helper that drops you straight into the console with the exact pfctl command.

**Operator docs** (read 2026-06-15)

- [Onboarding](https://openbsd.amsterdam/onboard.html) — console via vmctl/cu(1), ~. to exit, doas setup, syspatch, initial root password from authorized_keys
- [Backup](https://openbsd.amsterdam/backup.html) — wingman1 (s4vm23@wingman1.openbsd.amsterdam, same port/key, openrsync recommended; 10G free)
- [PTR / rDNS](https://openbsd.amsterdam/ptr.html) — set from inside VM only (token + ftp/http to ptr4/ptr6); protect endpoint
- [Upgrade](https://openbsd.amsterdam/upgrade.html) — sysupgrade or manual bsd.rd
- [Known issues](https://openbsd.amsterdam/known.html) — mostly resolved in 7.3+ (use ping cron to gateway only if needed)

**Notes**

- Rapid SSH reconnects trip pf `<bruteforce>` table (see pf.conf + unban_pf.sh). Always use tmux; prefer host console when direct is blocked.
- FDE the VM only if you accept that the provider cannot cold-start it.
- Billing: €71/yr via pay.html (include "server4 vm23" in description).
- Same key works for VM + host + backup wingman.

## Run

```zsh
cd ~/pub4/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

```zsh
doas zsh openbsd.sh --sync-configs    # mirror repo etc/ → /etc, restart services
doas zsh openbsd.sh --resume          # continue interrupted stage run
doas ksh emergency_cpu.sh             # stop crash-looping Rails services (CPU relief)
```

## Stages

**Stage 1** — NSD + DNSSEC, acme-client TLS, httpd ACME, base pf, packages.

**Stage 2** — Rails app trees, relayd SNI, smtpd, final pf, rc.d services, health_check.

## Rules

- Public ingress: SSH, SMTP, 80, 443 only. App ports bind loopback; relayd terminates TLS.
- SQLite + Solid Queue/Cache by default. No PostgreSQL/Redis unless explicitly added.
- Secrets in `/etc/master.env`, `/etc/<app>.env` — never in git. Operator secrets in `~/priv/`.
- Any file installed on VPS must be copied back to `DEPLOY/openbsd/` and committed.

## Post-deploy

```zsh
doas rcctl check master relayd pf
curl -fsS http://127.0.0.1:53187/up
curl -sk https://ai.brgen.no/up
doas tail -f /var/log/openbsd_setup.log
```

## MASTER review

Before changing live infra:

```zsh
cd ~/pub4/MASTER && bundle exec ruby bin/cli
# /scan DEPLOY/openbsd
# /sweep DEPLOY/openbsd
```

Reject changes that open raw app ports, weaken pf/relayd validation, or drop backup/idempotence.