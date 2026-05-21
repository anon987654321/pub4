# MASTER Web UI

Rails 8 + Falcon server. Internal port 53187; relayd proxies to ai.brgen.no:4430.

## Routes

| Route | Description |
|---|---|
| `GET /` | Chat interface |
| `GET /chat/message` | SSE streaming response |
| `POST /chat/tts` | TTS synthesis |
| `POST /chat/speak` | Speak text |
| `GET /chat/metrics` | Session metrics |
| `GET /chat/dmesg` | Event log |
| `GET /events/stream` | SSE event stream |

## Canvas

- 2000-particle orb visualization
- 50 procedural shapes
- Ambient pad engine
- Drum sequencer
- 17 voice FX chains

## rc.d service

```zsh
doas rcctl enable master
doas rcctl start master
```

Daemon binds to 127.0.0.1:53187. relayd handles TLS termination.
