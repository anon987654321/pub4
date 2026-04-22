# Clone the repository and enter the tutorial directory
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/rag_tutorials/rag-as-a-service

# Install Ruby dependencies
bundle install

# Configure environment variables
export OPENROUTER_API_KEY=your_key_here
export MASTER_MODEL=deepseek-ai/deepseek-v3   # default, can be overridden
export MASTER_VECTOR_DIM=1536                # matches DeepSeek embedding size
