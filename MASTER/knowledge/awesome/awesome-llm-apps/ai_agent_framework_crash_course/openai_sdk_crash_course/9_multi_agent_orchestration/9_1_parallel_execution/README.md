pip install openai-agents
cp ../env.example .env   # add your OpenAI API key
python - <<'PY'
import asyncio
from agent import main
asyncio.run(main())
PY
