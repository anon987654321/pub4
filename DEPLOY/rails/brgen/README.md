# brgen — hyperlocal city platform

One Rails 8 codebase. Every city gets its own local discovery system.

The loop: see what matters nearby → act on it → leave a trust signal → improve the next recommendation.

## Surfaces

- Posts, events, listings, food, music, video — filtered by proximity
- Creator local audience and monetization tools
- Marketplace with city-scoped inventory
- AI recommendations seeded by local signals

## Domains

`brgen.no` plus city aliases (bergen.city, oslo.city, trondheim.city, …)

## Stack

Rails 8 · SQLite · Falcon · Hotwire · OpenBSD · relayd SNI routing

## Deploy

```zsh
doas zsh DEPLOY/rails/brgen/brgen.sh
```
