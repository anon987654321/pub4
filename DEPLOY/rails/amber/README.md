# amber

The world's largest social network for fashion. Rails 8 · PostgreSQL + pgvector · Redis · Falcon.

## Features

- **Import your wardrobe** — photograph each item; Amber removes backgrounds, upscales, relights, post-processes for professional shots of you (or AI fashion models) wearing them.
- **Mix & Match Magic** — four counter-rotating Stimulus carousels propose new outfit combinations, weighted by your evolving taste vector.
- **Closet Organization** — cleaning/storage tips drawn from architecture, interior design, and zen minimalism.
- **Wardrobe Analytics** — track usage, cost-per-wear, surface underutilized items.
- **Style Assistant** — daily outfit suggestions tuned to context and weather.
- **Shop Smarter** — surfaces newest/most-popular items from Net-a-porter et al.; supports your own affiliate links.

## Social

User profiles · activity feed · anonymous posting · public chatroom · live webcam streaming.

## Stack

```
CDN (Cloudflare)
       │
Load balancer (relayd)
       │
  Falcon (Rails 8)
       │
  ┌────┴──────────┐
  │               │
PostgreSQL     Redis
+ pgvector  (Action Cable)
```

## Deploy

```zsh
doas zsh DEPLOY/rails/amber/amber.sh
```
