# 1. Clone the repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/rag_tutorials/rag_database_routing

# 2. Install Ruby dependencies
bundle install

# 3. Load sample data into the in‑memory databases
ruby scripts/load_sample_data.rb

# 4. Start the RAG server (listens on http://localhost:3000)
bundle exec ruby bin/rag_server.rb
