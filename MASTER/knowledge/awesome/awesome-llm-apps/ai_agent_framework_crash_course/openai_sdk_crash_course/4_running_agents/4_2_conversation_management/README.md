# Conversation Management
Demonstrates manual threading via `result.to_input_list()` and automatic session handling with `SQLiteSession`. Shows conversation state persistence.

## Setup
1. Install SDK: `pip install openai-agents`.
2. Copy `.env.example` to `.env` and add your OpenAI key.
3. Run example:

```python
import asyncio
from agent import manual_conversation_example, session_conversation_example

asyncio.run(manual_conversation_example())
```

## Concepts
- `to_input_list()`: Manage conversation history manually.
- `SQLiteSession`: Persist conversation state.
- Context retention across turns.
- Thread control strategies.

## Related
- Execution methods: `../4_1_execution_methods/README.md`
- Streaming events: `../4_4_streaming_events/README.md`