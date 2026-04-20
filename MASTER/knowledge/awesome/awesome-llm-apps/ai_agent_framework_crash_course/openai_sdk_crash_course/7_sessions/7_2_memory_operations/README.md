pip install openai-agentscp ../env.example .env   # add OpenAI API key
python - <<'PY'
import asyncio
from agent import basic_memory_operations, conversation_corrections

asyncio.run(basic_memory_operations())
asyncio.run(conversation_corrections())
PY
