---
name: Falcon Async + EventMachine = subprocess pattern
description: EM-based gems (rb-edge-tts, em-http) inside Falcon request handlers must shell out to a subprocess; Process.fork and direct EM.run both fail
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Falcon uses Async/io-event fibers. `Process.fork` from a request fiber → `RuntimeError: Closing scheduler with blocked operations!`. `EventMachine.run` conflicts with Falcon's reactor (hang or premature close). Hit in `Master::Speech.synthesize_edge` (rb-edge-tts); same for any `em-*` gem.

**Apply:** `exe/<name>-worker` script does EM work → tempfile; controller calls `Open3.capture3`. Ref: `MASTER/exe/tts-worker`, `MASTER/lib/master/speech.rb#synthesize_edge`.