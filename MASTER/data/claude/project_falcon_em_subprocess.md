---
name: Falcon Async + EventMachine = subprocess pattern
description: EM-based gems (rb-edge-tts, em-http) inside Falcon request handlers must shell out to a subprocess; Process.fork and direct EM.run both fail
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---

Falcon uses Async and io-event fibers. `Process.fork` from a request fiber raises `RuntimeError: Closing scheduler with blocked operations!`. `EventMachine.run` conflicts with Falcon's reactor and hangs or closes prematurely. This surfaced in `Master::Speech.synthesize_edge` via rb-edge-tts and applies to any `em-*` gem inside a request handler.

The pattern is an `exe/<name>-worker` script that runs EventMachine work and writes a tempfile; the controller calls `Open3.capture3`. Reference implementation: `MASTER/exe/tts-worker` and `MASTER/lib/master/speech.rb#synthesize_edge`.