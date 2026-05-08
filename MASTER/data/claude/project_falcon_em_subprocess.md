---
name: Falcon Async + EventMachine = subprocess pattern
description: EM-based gems (rb-edge-tts, em-http) inside Falcon request handlers must shell out to a subprocess; Process.fork and direct EM.run both fail
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Falcon uses Async/io-event fibers. Calling `Process.fork` from a request fiber raises `RuntimeError: Closing scheduler with blocked operations!`. Calling `EventMachine.run` directly conflicts with Falcon's reactor (silent hang or premature scheduler close).

**Why:** Async's fiber scheduler tracks open fibers across fork boundaries; EM owns its own reactor that can't coexist with Async's in the same process. We hit this twice: in `Master::Speech.synthesize_edge` (rb-edge-tts) and would hit it for any `em-*` gem.

**How to apply:** When wiring an EM-based gem into a Falcon controller, write a small `exe/<name>-worker` Ruby script that does the EM work and writes output to a tempfile. Call it via `Open3.capture3` from the controller path. Reference: `MASTER/exe/tts-worker` + `MASTER/lib/master/speech.rb#synthesize_edge`.
