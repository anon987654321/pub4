# DEPLOY → OPERATOR / RAILS / OPENBSD (2026-07)

Canonical layout:

- `RAILS/` — Rails 8 apps + shared engine (was `DEPLOY/rails`)
- `OPENBSD/` — pf, relayd, rc.d, VPS scripts (was `DEPLOY/openbsd`)
- `OPERATOR/` — gates, bin/, data/, operator docs (was `DEPLOY/` minus rails/openbsd)

Compatibility:

- `DEPLOY` → symlink to `OPERATOR`
- `OPERATOR/rails` → symlink to `RAILS`
- `OPERATOR/openbsd` → symlink to `OPENBSD`

Legacy `DEPLOY/rails/...` paths keep working on disk. New code should use `RAILS/`, `OPENBSD/`, `OPERATOR/`.