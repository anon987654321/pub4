data/
  └─ *.pdf / *.txt        # Sample knowledge sources
lib/
  ├─ embedding.rb          # Gemini embedding wrapper (RubyLLM)
  ├─ index.rb              # Simple vector store + cosine similarity
  ├─ agent.rb              # Master‑based agent definition
  └─ pipeline.rb           # Stage definitions and wiring
config.yml                 # Model, cache and similarity settings
README.md                  # ← you are reading it
