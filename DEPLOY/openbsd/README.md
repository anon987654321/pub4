# OpenBSD Deploy

Full VPS stack deploy for OpenBSD 7.8 at `46.23.89.226`.

## Run

```zsh
cd ~/pub4/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Resume after interruption:

```zsh
doas zsh openbsd.sh --resume
```

## What it deploys

### Stage 1 — DNS, TLS, packages

- validates OpenBSD interface and disk space
- installs base deploy packages
- configures minimal PF for bootstrap
- configures NSD authoritative DNS
- signs zones with DNSSEC
- configures httpd for ACME challenges
- requests certificates with `acme-client`
- writes TLSA records
- installs certificate-renewal cron

### Stage 2 — application services

- installs Rails app trees from `DEPLOY/rails/*`
- configures app rc.d services
- configures relayd TLS termination
- configures httpd static/ACME serving
- configures smtpd
- loads final PF rules
- verifies service health

## Boundary rules

- Public ingress should be limited to SSH, SMTP, HTTP, and HTTPS.
- Raw Rails/Falcon/internal ports should stay behind relayd or loopback bindings.
- PostgreSQL and Redis are not part of this deploy path unless explicitly reintroduced.
- Secrets must come from environment, local root-owned files, or operator input, never committed docs.
- Certificate renewal must be idempotent and must not append duplicate TLSA records.

## Checks

After deploy:

```zsh
doas rcctl check master
doas pfctl -s rules
curl -sk https://ai.brgen.no/chat/metrics
```

Inspect logs:

```zsh
doas tail -f /var/log/openbsd_setup.log
doas tail -f /var/log/openbsd_transactions.log
doas tail -f /var/log/cert-renewal.log
```

## MASTER sweep notes

`DEPLOY/` is high-risk infrastructure code. Run it through MASTER with deploy policy enabled before changing live systems:

```zsh
bundle exec ruby exe/master /scan DEPLOY
bundle exec ruby exe/master /sweep DEPLOY
```

Reject any change that:

- opens raw app ports publicly
- makes destructive filesystem changes without backup
- weakens PF, relayd, httpd, smtpd, or NSD validation
- stores credentials in repository files
- removes idempotence from cron, DNS, TLS, or rc.d setup
