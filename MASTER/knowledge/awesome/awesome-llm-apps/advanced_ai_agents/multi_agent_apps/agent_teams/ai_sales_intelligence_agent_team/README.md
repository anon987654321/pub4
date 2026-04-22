ai_battle_card_agent/
├─ __init__.py          # Exposes the public API (Agent, Tools, etc.)
├─ agent.py            # Orchestrates the team: creates agents, routes tasks, aggregates results
├─ tools.py            # Shared utilities:
│   ├─ LLM wrappers (OpenRouter, DeepSeek, etc.)
│   ├─ Data adapters (CRM, web scraping)
│   └─ Formatters (JSON, Markdown)
├─ outputs/            # Generated battle cards (one file per prospect)
│   ├─ *.json
│   └─ *.md
├─ requirements.txt    # Exact dependency pins for reproducibility
└─ README.md           # This document
