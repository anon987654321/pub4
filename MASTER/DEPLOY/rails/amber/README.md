# amber

Amber social platform. Rails 8. PostgreSQL + pgvector. Redis.

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

## Deploy

```zsh
cd ~/pub4/MASTER/DEPLOY/rails/amber
doas zsh amber.sh
```
