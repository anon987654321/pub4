corrective‑rag/
├─ lib/                     # Core Master components (already part of the host app)
├─ app/
│  ├─ services/
│  │  ├─ retriever.rb      # Vector‑store abstraction (PGVector, Qdrant, etc.)
│  │  ├─ generator.rb      # Calls the default LLM to produce an initial answer
│  │  └─ corrector.rb      # Detects hallucinations & patches the answer
│  └─ controllers/
│     └─ rag_controller.rb # JSON endpoint: POST /rag
└─ README.md                # ← you are here
