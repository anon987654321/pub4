# OpenBSD deploy

Two-stage installer for vm23. Operator runbook: `../OPERATOR.md`. SSH detail: `SSH_ACCESS.md`.

## vm23

| | |
|-|-|
| IPv4 | `46.23.89.226` /26, gw `46.23.89.193` |
| IPv6 | `2a03:6000:6e64:623::226` /64 |
| VMM | `server4.openbsd.amsterdam:31415`, `vmctl console vm23` |
| User | `dev`, key `~/.ssh/id_ed25519_brgen` |

```zsh
ssh brgen                              # VM
ssh -p 31415 dev@server4.openbsd.amsterdam   # hypervisor
```

## Run

```zsh
cd ~/pub4/OPENBSD
doas zsh OPERATOR.sh
```

| Command | Purpose |
|---------|---------|
| `doas zsh OPERATOR.sh` | Install etc/usr/var, validate, restart services |
| `doas ksh resource_guard.sh` | Shed optional apps under load |
| `doas ksh start_all_apps.sh` | Full stack |

## Stages

1. NSD, DNSSEC, acme certs, httpd ACME, pf, packages.
2. Rails trees, relayd SNI, smtpd, rc.d, health_check.

## vm23 budget (1 vCPU, ~1 GiB)

Boot core: `master` + `brgen`. Optional apps stopped until started. relayd interval 120 s. `MASTER_SAFE_MODE=1` in rc.d.

```zsh
doas rcctl check master brgen
ruby34 OPENBSD/health_check.rb
```

## Rules

Public ingress: 22, 25, 80, 443. App ports on loopback; relayd terminates TLS. SQLite + Solid Queue/Cache. Secrets in `/etc/*.env`, not git.

VPS source of truth: `/home/dev/pub4`. Commit any `/etc` change back to `OPENBSD/`.

## Post-deploy

```zsh
doas rcctl check master relayd pf
curl -fsS http://127.0.0.1:53187/up
curl -sk https://ai.brgen.no/up
```

Infra edits: `/scan OPENBSD` inside MASTER before applying live.