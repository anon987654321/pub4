# brgen

Bergen social platform. Rails 8 + Falcon. PostgreSQL + pgvector + Redis.

## Deploy

```zsh
cd ~/pub4/MASTER/DEPLOY/rails/brgen
doas zsh brgen.sh
```

## Stack

```
CDN (Cloudflare)
       │
Load Balancer (relayd)
       │
  Falcon (Rails 8)
       │
  ┌────┴────────┐
  │             │
PostgreSQL   Redis
+ pgvector  (Action Cable)
```

## Subapps

- brgen.no — main social feed
- takeaway — food ordering (see README_takeaway.md)
- tv — video/live streaming (see README_tv.md)
