   ┌─────────────┐
   │  RECORD     │ → Audio buffer
   └─────┬───────┘
         │
   ┌─────▼───────┐
   │ TRANSCRIBE │ → Text (LLM prompt)
   └─────┬───────┘
         │
   ┌─────▼───────┐
   │ PROCESS    │ → Agent decisions & response
   └─────┬───────┘
         │
   ┌─────▼───────┐
   │ SYNTHESIZE │ → Speech audio (TTS)
   └─────┬───────┘
         │
   ┌─────▼───────┐
   │ PLAY       │ → Audio output to user
   └─────────────┘
