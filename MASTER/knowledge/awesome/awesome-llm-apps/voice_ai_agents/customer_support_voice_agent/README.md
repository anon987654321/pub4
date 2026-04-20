#Customer Support Voice Agent

A voice‑enabled support assistant that answers questions about your documentation using OpenAI GPT‑4o and TTS. It crawls documentation sites with Firecrawl, indexes the content in Qdrant, and returns both text and spoken responses.

## Features
- **Knowledge base** – crawls sites, stores embeddings in Qdrant, enables semantic search with FastEmbed.  
- **Agent team** – Documentation Processor generates answers; TTS Agent speaks them; Voice Customization offers alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse.  
- **UI** – Streamlit sidebar configures API keys, selects voice, starts ingestion, and displays results with an audio player and progress indicator.

## Run
```bashgit clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd ai_agent_tutorials/ai_voice_agent_openaisdk
pip install -r requirements.txt
streamlit run ai_voice_agent_docs.py
```

## Setup
1. **API keys** – OpenAI, Qdrant Cloud, Firecrawl.  2. **Configuration** – Enter keys in the sidebar.  
3. **Ingest** – Provide a documentation URL, choose a voice, click *Initialize System*.  
4. **Query** – Ask questions; receive text and voice output.

## Details
- **Ingestion** – Crawls up to five pages, preserves structure and metadata.  
- **Search** – FastEmbed creates embeddings; Qdrant retrieves relevant passages.  
- **Speech** – OpenAI TTS produces natural‑sounding audio with configurable pacing.  

The system is ready for production use; extend it with additional voices or integration points as needed.