# Built‑in Tools Agent

Demonstrates OpenAI Agents SDK built‑in tools: WebSearchTool and CodeInterpreterTool.

## 🎯 Demonstrates
- **WebSearchTool** – performs real‑time web searches.
- **CodeInterpreterTool** – executes Python code and calculates values.
- **Built‑in Tool Integration** – uses pre‑configured SDK tools.
- **Tool Combination** – runs multiple tools within a single agent.

## 🚀 Quick Start1. Install the SDK: `pip install openai-agents`.
2. Copy env file and add your API key: `cp ../env.example .env && edit .env`.
3. Run the agent:

```python
from agents import Runner
from agent import root_agent

result = Runner.run_sync(root_agent, "What's the latest news about AI and calculate 15% of 200?")
print(result.final_output)
```

## 💡 Key Concepts
- **WebSearchTool()** – searches the web for current information.
- **CodeInterpreterTool()** – runs Python code and performs calculations.
- **Tool Instantiation** – creates tool instances with default settings.
- **Multi-tool Agents** – combines different tool types in one workflow.

## 🧪 Available Tools
### WebSearchTool
- Retrieves up‑to‑date web results.
- Ideal for factual questions requiring recent data.

### CodeInterpreterTool
- Executes Python code in a secure sandbox.
- Handles mathematical calculations and data analysis.

## 🔗 Next Steps
- [Function Tools](../3_1_function_tools/README.md) – custom function tools.
- [Agents as Tools](../3_3_agents_as_tools/README.md) – advanced orchestration patterns.