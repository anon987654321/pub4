# Clone the tutorial repo
git clone https://github.com/your-org/local_hybrid_search_rag.git
cd local_hybrid_search_rag

# Install Ruby dependencies in an isolated bundle
bundle config set --local path .bundle
bundle install

# Populate the example corpus (CSV with `id,text` columns)
bin/load_corpus.rb data/example_corpus.csv

# Build indexes (BM25 + embeddings)
bin/build_index.rb
