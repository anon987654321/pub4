┌─────────────────────┐   1️⃣ Capture audio chunks
│  STREAMING AUDIO    │   • Read microphone in 20‑ms buffers
│  (VAD + Buffering)  │   • Drop silence with voice‑activity detection
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐   2️⃣ Live transcription
│  OPENAI WHISPER API │   • Send each buffer via HTTP/2 stream
│  (partial results)  │   • Receive incremental transcripts
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐   3️⃣ Parallel agent execution
│  LLM (e.g. DeepSeek)│   • Feed transcript as soon as it arrives
│  (stateless)       │   • Multiple turns can overlap
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐   4️⃣ Stream TTS back to the user
│  OPENAI TTS API     │   • Chunk LLM output into sentences
│  (audio streaming) │   • Play each chunk immediately
└──────────┬──────────┘
           │
           ▼
🔊  Continuous audio output (loop)
