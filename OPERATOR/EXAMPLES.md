# Examples

## Good OPERATOR Patch

```text
Updated `rails/apps.yml` and `openbsd/etc/relayd.conf` together for a domain change, then ran domain alignment and deploy smoke gates.

Checks:
- ruby RAILS/domain_alignment_gate.rb
- ruby OPENBSD/deploy_smoke_gate.rb
```

## Bad OPERATOR Patch

```text
Changed a port in one app script only.
```

Ports must stay aligned across `rails/apps.yml`, app deploy scripts, relayd, health checks, and docs.

## Good VPS Closeout

```text
Host: vm23.
Commands: git pull --ff-only; zsh OPENBSD/sh/vps_ci.sh brgen; doas rcctl restart brgen; ruby34 OPENBSD/health_check.rb --public --all-ready-apps.
Result: brgen CI passed; public health green.
Skipped: no relayd restart because routes were unchanged.
```

## Bad VPS Closeout

```text
Restarted stuff, should be up.
```

## Good Refusal

```text
I am not running `OPERATOR.sh` from macOS. I can run local gates here; the full installer belongs on vm23 under tmux.
```
