streaming-ai-chatbot/
├─ steps/
│  ├─ conversation.stream.ts   # Reactive state for the chat history
│  ├─ chat‑api.step.ts         # Thin wrapper around the LLM HTTP endpoint
│  └─ ai‑response.step.ts      # Parses the streaming response and emits tokens
├─ package.json
├─ .env.example
└─ README.md
