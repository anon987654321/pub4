# MyToonz

AI comic strip generator — ComicStrip model, ReplicateService, GenerateComicStripJob.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Solid Queue · OpenBSD relayd

## Deploy

```zsh
doas zsh DEPLOY/rails/mytoonz/mytoonz.sh
curl -fsS http://127.0.0.1:10008/up
```

Set `REPLICATE_API_TOKEN` in production for AI generation.

## Status

Feature matrix: `apps.yml` → `archived_apps.mytoonz`.