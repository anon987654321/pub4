# Clone the awesome‑llm‑apps repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/rag_tutorials/local_rag_agent

# Install dependencies
bundle install

# Optional: pre‑populate the cache with a small corpus
rake rag:seed   # loads docs/*.txt, creates embeddings, stores them
