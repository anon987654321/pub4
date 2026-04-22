ai_medical_imaging_agent/
├─ README.md          # ← you are here
├─ requirements.txt   # Python runtime dependencies
├─ agent.py           # Core orchestration (prompt handling, result parsing)
├─ inference.py       # Thin wrapper around the chosen LLM / vision model
├─ prompts/           # System & few‑shot prompts
│   ├─ system.txt
│   └─ few_shot.jsonl
└─ examples/          # Sample DICOM / PNG images + expected JSON outputs
