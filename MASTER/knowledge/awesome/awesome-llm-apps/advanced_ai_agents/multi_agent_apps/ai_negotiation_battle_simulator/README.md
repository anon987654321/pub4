┌─────────────────────────────────────────────────────┐
│  Next.js + CopilotKit UI                           │
│   ┌─────────────┐    ┌─────────────┐    ┌───────────┐ ││   │ BattleArena │    │ VS Display  │    │ ChatSide  │ ││   │ Timeline    │    │ (BUY/SELL)  │    │ (AG‑UI)   │ │
│   └─────┬───────┘    └─────┬───────┘    └─────┬─────┘ │
└───────┼───────────────────────────────────────┼───────┘
        │  AG‑UI Events                         │
        └─────────────────────┬─────────────────────┘
                              │
                        ┌─────▼─────┐
                        │CopilotKit │
                        │ Runtime   │
                        └─────┬─────┘
                              │ HTTP/SSE
                        ┌─────▼─────┐
                        │FastAPI+ADK│                        │Negotiation│
                        │Agent      │
                        └─────┬─────┘
                              │
                        ┌─────▼─────┐
                        │ Tools     │
                        │ • configure_negotiation │
                        │ • start_negotiation     │
                        │ • buyer_make_offer      │
                        │ • seller_respond        │
                        └─────────────────────────┘
