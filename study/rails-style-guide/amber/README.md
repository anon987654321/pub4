          CDN (Cloudflare)
                 │
      Load Balancer (relayd)
                 │
            Falcon (Rails 8)
                 │
   ┌─────────────────────────────┐
   │          Services            │
   ├─────────────────────┬───────┤
   │ PostgreSQL + pgvector│ Redis │
   │   (primary DB)      │ (Action│
   │                     │ Cable)│
   └─────────────────────┴───────┘
