# Clone the Awesome LLM Apps repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/rag_tutorials/hybrid_search_rag

# Install Ruby dependencies
bundle install --without development test

# Configure environment variables
export OPENAI_API_KEY=your_api_key
export ELASTICSEARCH_URL=http://localhost:9200
export EMBEDDING_MODEL=deepseek-ai/deepseek-v3
