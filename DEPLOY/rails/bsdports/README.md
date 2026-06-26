# bsdports

OpenBSD ports search — FTS5 live search, dependencies, advisories, maintainers.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · OpenBSD relayd

## Deploy

```zsh
doas zsh DEPLOY/rails/bsdports/bsdports.sh
curl -fsS http://127.0.0.1:47312/up
```

## Status

Feature matrix: `apps.yml` → `bsdports`.

```zsh
# Sync import from local tree (OpenBSD VPS: /usr/ports)
PLATFORM=openbsd BSDPORTS_TREE_PATH=/usr/ports bin/rails ports:import_now

# Queue nightly-style import
bin/rails ports:import
```