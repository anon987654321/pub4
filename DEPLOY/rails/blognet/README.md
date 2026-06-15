# blognet

Editorial publishing network. Food vertical brand: **foodielicio.us** (recipe-first UX).

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Action Text · OpenBSD relayd

Not PostgreSQL/pgvector in current deploy shape — see `config/database.yml`.

## Deploy

```zsh
doas zsh DEPLOY/rails/blognet/blognet.sh
```

## Direction

Longform posts, categories, comments, feeds, recipe schema, semantic discovery. Full backlog in `apps.yml` → `blognet` (most features still `port` or `missing`).