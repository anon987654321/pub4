# Deployment Map

```text
Internet
  -> pf
  -> relayd TLS/SNI
  -> loopback app ports
      -> MASTER Falcon on ai.brgen.no
      -> brgen Rails app and vertical subdomains
      -> amber Rails app
      -> hjerterom Rails app
      -> bsdports Rails app
  -> NSD/acme/httpd for DNS and certificate plumbing
```

## Major Areas

- `openbsd/`: system installer, `/etc` templates, relayd/pf/nsd/acme, VPS scripts, health checks.
- `rails/`: Rails app trees, shared engine, app inventory, production/frontend/domain gates.
- `tools/`: creative tools, security sweep, utility scripts, public tool pages.
- `archive/`: restore notes and historical recovery material.
- `quarantine/`: intentionally isolated historical material.
- `integrity_gate.rb`: local deploy gate chain.
- `master.json`: deploy identity and app/domain metadata.

## Runtime Contract

- TLS terminates at relayd.
- Apps listen on loopback-only ports.
- Rails uses SQLite plus Solid Queue/Cache.
- Secrets live in `/etc/*.env`.
- Source of truth on VPS is `/home/dev/pub4`.
- Long deploys run under tmux.

## Gate Flow

Local:

```text
OPERATOR/bin/check
  -> verify_deploy_identity
  -> rails production/domain/phantom/frontend gates
  -> openbsd deploy smoke
```

Operator:

```text
git pull --ff-only on vm23
  -> vps_ci.sh <app>
  -> OPERATOR.sh or per-app deploy
  -> rcctl restart affected services
  -> health_check --public --all-ready-apps
```
