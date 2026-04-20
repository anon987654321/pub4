# Tutorial 4: Tool‑Using Agent

## What You’ll Learn
- Use Google ADK’s built‑in tools- Create custom function tools
- Integrate third‑party tools
- Connect to MCP servers## Core Concept: Tools
Tools are functions your agent calls to perform tasks. They act as the agent’s hands, enabling:
- Web search and real‑time data retrieval
- Code execution and calculations
- API and service calls
- Database and file‑system access
- Interaction with other AI frameworks

## Tool Types
### Built‑in Tools
Pre‑built Google ADK tools for Gemini models only:
- Search
- Code execution
- RAG
- Cloud integrations

### Function Tools
Custom Python functions you define:
- Math calculations
- Data processing
- API calls
- File operations
- Business logic

### Third‑party Tools
Integrations with LangChain, CrewAI, or other frameworks.

### MCP Tools
Connect to external or custom MCP servers; use SSE or Streamable HTTP.

## Tutorial Structure
Four example directories:
- **4_1_builtin_tools** – built‑in tool usage
- **4_2_function_tools** – custom function tools
- **4_3_thirdparty_tools** – third‑party integrations
- **4_4_mcp_tools** – MCP server integration

Each directory contains a Python file, a README, and a requirements.txt.

## Learning Objectives
- Apply built‑in tools effectively
- Build and integrate custom function tools
- Leverage third‑party ecosystems
- Deploy and create MCP servers
- Choose appropriate tools for tasks
- Follow best practices for tool design

## Pro Tips
- Start with built‑ins; they are optimized.
- Document tools with clear docstrings.
- Handle errors in every tool.
- Use descriptive tool names.
- Test tools independently before composition.

## Real‑World Applications
Tool‑using agents enable:
- Information retrieval
- Data analysis- API integration
- Automation
- Data‑driven decisions

## Important Notes
- Built‑ins work only with Gemini models.
- Do not mix built‑ins and custom tools in one agent.
- Built‑ins are faster; custom tools require validation.