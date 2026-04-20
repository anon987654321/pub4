┌─────────────────────────────────────────────────────┐
│          MULTI-AGENT ORCHESTRATION                  │
├─────────────────────────────────────────────────────┤
│  TASK DECOMPOSITION                                 │
│      → ORCHESTRATOR (routes tasks)                  ││      → AGENT (executes)                             │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │            PARALLEL EXECUTION                 │ │
│  │  ├─────────┐  ├─────────┐  ├─────────┐  ├─────────┐ │
│  │            │  │           │  │           │ │ |
│  │   RESEARCH │  │ WRITING │  │ ANALYSIS │  │ REVIEW │ │
│  │            │  │ AGENT   │  │ AGENT    │ │ |
│  └───────────────────────────────────────────────┘ │
│                                                     ││           RESULT SYNTHESIS                          │
│        • Combine outputs                            │
│        • Assess quality                             │
│        • Produce final response                   │
└─────────────────────────────────────────────────────┘
