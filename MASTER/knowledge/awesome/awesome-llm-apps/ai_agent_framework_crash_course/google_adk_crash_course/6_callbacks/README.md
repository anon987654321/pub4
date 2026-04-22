┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│ Agent start          │   │ LLM request          │   │ Tool execution       │
│ callback (agent)    │   │ callback (prompt)    │   │ callback (tool)      │
└─────────────────────┘   └─────────────────────┘   └─────────────────────┘
          │                         │                         │
          ▼                         ▼                         ▼
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│ LLM response         │   │ Tool result          │   │ Agent end            │
│ callback (response) │   │ callback (result)   │   │ callback (final)    │
└─────────────────────┘   └─────────────────────┘   └─────────────────────┘
