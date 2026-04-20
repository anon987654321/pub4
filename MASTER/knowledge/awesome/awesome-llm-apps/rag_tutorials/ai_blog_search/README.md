# Agentic RAG with LangGraph: AI Blog Search

## Overview
AI Blog Search is an Agentic RAG application that retrieves and analyzes AI blog posts. It uses LangChain, LangGraph, and Gemini to fetch, process, and answer queries.

## LangGraph Workflow
![LangGraph-Workflow](https://github.com/user-attachments/assets/07d8a6b5-f1ef-4b7e-b47a-4f14a192bd8a)

## Demo
https://github.com/user-attachments/assets/cee07380-d3dc-45f4-ad26-7d944ba9c32b

## Features
- Retrieves blog content from Qdrant vector storage.
- Rewrites or answers queries using an AI agent.
- Grades answer relevance with Gemini.
- Refines vague queries for better retrieval.
- Provides a Streamlit UI for URL entry, query input, and responses.
- Executes a state graph with LangGraph for decision flow.

## Technologies
- Language: Python 3.10+
- Framework: LangChain, LangGraph- Database: Qdrant
- Embeddings: Gemini embedding‑001- Chat: Gemini 2.0‑flash
- Loader: LangChain WebBaseLoader- Splitter: RecursiveCharacterTextSplitter
- UI: Streamlit

## Requirements1. Install dependencies: `pip install -r requirements.txt`
2. Run the app: `streamlit run app.py`
3. Use the UI:
   - Enter a Google API key in the sidebar.
   - Paste a blog URL.
   - Submit a query about the blog post.

## Contact
LinkedIn: https://linkedin.com/in/codewithcharan  
Instagram: https://instagram.com/joyboy._.ig  
Twitter: https://twitter.com/Joyboy_x_  

Thanks for visiting! 👋  
Message me on LinkedIn to collaborate.