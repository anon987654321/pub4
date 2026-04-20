# Agentic RAGwith Reasoning

### Free Step‑by‑Step Tutorial
👉 Follow the complete tutorial at https://www.theunwindai.com/p/build-an-agentic-rag-app-with-reasoning

A step‑by‑step RAG system that demonstrates an AI agent's reasoning using Agno, Gemini, and OpenAI. Users add web sources, ask questions, and observe the agent's reasoning in real time.

## Features
- **Interactive Knowledge Base** – Add URLs dynamically; persistent vector store with LanceDB prevents duplicate loading.
- **Transparent Reasoning** – Display the agent's thought steps alongside the final answer.
- **Advanced RAG** – Vector search with OpenAI embeddings; source attribution with citations.

## Agent Configuration
- Language model: Gemini 2.5 Flash
- Embedding model: OpenAI
- Reasoning tools: step‑by‑step analysis
- Custom instructions: configurable agent behavior
- Default knowledge source: MCP vs A2A Protocol article

## Prerequisites- Google API key
- OpenAI API key

## Run
1. Clone the repository:
   git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
   cd rag_tutorials/agentic_rag_with_reasoning
2. Install dependencies:
   pip install -r requirements.txt
3. Start the app:
   streamlit run rag_reasoning_agent.py
4. Enter API keys in the UI.

## How It Works
- **Knowledge Base Setup** – Load documents from URLs, chunk text, embed with OpenAI, store vectors in LanceDB, retrieve with semantic search.
- **Agent Processing** – Receive a query, run ReasoningTools, retrieve relevant vectors, generate answer with Gemini, stream events for real‑time feedback.
- **UI Flow** – Input API keys, load default article, add URLs, ask questions, view reasoning in the left panel and answer with citations in the right panel.

All events stream for real‑time updates.