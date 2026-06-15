# OpenBSD deploy

Two-stage VPS installer for pub4. Target: OpenBSD 7.8+, vm23 (`46.23.89.226`).

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