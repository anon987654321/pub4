# Corrective RAG Agent

##Features
- Retrieve documents with Qdrant vector store
- Grade relevance using Claude 4.5 sonnet
- Transform queries to improve retrieval- Fall back to web search via Tavily when needed
- Combine OpenAI embeddings with Claude 4.5 for distinct tasks
- Provide UI with Streamlit

## How to Run1. Clone repository  
2. Install dependencies  
3. Add API keys: OpenAI, Anthropic, Tavily, Qdrant  
4. Run `streamlit run corrective_rag.py`  
5. Upload documents or URLs, ask questions, view process, receive answer

## Tech Stack
- LangChain for orchestration  
- LangGraph for workflow management  
- Qdrant for vector storage  
- Claude 4.5 sonnet for analysis  
- OpenAI for embeddings  
- Tavily for web search  - Streamlit for UI