# Privcam

Private video sharing — Video/Comment models, infinite scroll via VideosInfiniteScrollReflex.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · OpenBSD relayd

## Deploy

```zsh
doas zsh RAILS/privcam/privcam.sh
curl -fsS http://127.0.0.1:47200/up
```

## Status

Feature matrix: `apps.yml` → `archived_apps.privcam`.