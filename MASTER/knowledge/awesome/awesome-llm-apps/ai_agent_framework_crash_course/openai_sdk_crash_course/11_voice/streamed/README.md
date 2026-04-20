┌─────────────────────────────────────────────┐
│            STREAMING VOICE WORKFLOW        │├─────────────────────────────────────────────┤
│  🎤 Continuous audio input                 │
│       ▼                                    │
│  ┌───────────────┐ 1. Capture audio chunk   │
│  │ STREAMING     │                        │
│  │   AUDIO       │                        │
│  └───────────────┘                        │
│       │                                  │
│       ▼                                  ││  ┌───────────────┐ 2. Transcribe live       │
│  │ TRANSCRIPTION │    → turn detection        │
│  └───────────────┘                        │
│       │                                  │
│       ▼                                  │
│  ┌───────────────┐ 3. Agent execution       │
│  │  PARALLEL AGENT│   → multiple turns       │
│  └───────────────┘                        │
│       │                                  │
│       ▼                                  ││  ┌───────────────┐ 4. Stream TTS response   ││  │  LIVE TTS     │    → chunked playback        │
│  └───────────────┘                        │
│       │                                  │
│       ▼                                  │
│  🔊 Continuous audio output               │
│       ↺ Loop for multiple turns           │
└─────────────────────────────────────────────┘
