# Decisions

## OpenBSD First

DEPLOY targets OpenBSD vm23. macOS local checks are useful, but OpenBSD behavior wins for package names, service management, relayd, pf, NSD, and Ruby command names.

## relayd Owns TLS

TLS terminates at relayd. Rails apps must use `config.assume_ssl = true` and must not force SSL themselves.

## Loopback App Ports

App ports are internal implementation details. Public ingress is 22, 25, 80, and 443; app ports stay behind relayd.

## `rails/apps.yml` Is Canonical

App status, domains, ports, and deploy scripts live in `DEPLOY/rails/apps.yml`. `DEPLOY/master.json`, relayd, acme, NSD, and docs should agree with it.

## Copy-Tree Deploy

Rails app trees are copied to `/home/<app>/app`; shared code is copied to `/home/<app>/shared`. Do not assume symlinked repo layout on the VPS.

## MASTER Web Assets Must Be Explicit

Falcon does not hot-reload production assets. MASTER web changes require `rails assets:precompile` and `doas rcctl restart master`.
