┌─────────────┐      ┌─────────────────────┐
│  Frontend   │◀───▶│  Master::Bridge     │
│ (React/Vite)│      │  FerrumWebChat      │
└─────┬───────┘      └───────┬─────────────┘
      │                      │
      ▼                      ▼
┌─────────────┐      ┌─────────────────────┐
│  Master::   │◀───▶│  Master::Pipeline    │
│  Controller │      │  (Intake → … → Render)│
└─────┬───────┘      └───────┬─────────────┘
      │                      ▼
      ▼            ┌─────────────────────┐
┌─────────────────────┐│  Master::Semantic   │
│  Master::Tools::    ││  Cache (vector DB) │
│  SearchKnowledge   │└─────────────────────┘
└─────────────────────┘
