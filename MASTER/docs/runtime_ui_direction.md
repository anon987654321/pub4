# Runtime UI Direction

MASTER should feel like:

- a control room
- a courtroom
- a terminal
- a scientific instrument

Not:

- a startup dashboard
- a gamified AI toy
- a casino UI
- a neon control panel

## Visual philosophy

Restraint creates authority.

Whitespace is structure.
Typography is architecture.
Motion communicates state.
Observability beats decoration.

## Runtime-derived visuals

Every visual state should derive from runtime events.

Examples:

- entropy
- confidence
- provider health
- workflow pressure
- repair activity
- replay state
- orchestration topology

The UI should not invent operational truth.

## Typography

Use disciplined typography:

- readable line lengths
- visible hierarchy
- restrained contrast
- stable rhythm
- monospace only where semantic

Avoid:

- tiny gray text
- decorative font systems
- excessive uppercase
- compressed spacing
- visual noise

## Motion

Motion should:

- communicate transitions
- expose workflow state
- show repair/retry activity
- reveal orchestration flow
- remain interruptible

Avoid:

- infinite animation
- ornamental transitions
- motion without semantic meaning

## Rails and Hotwire

Favor:

- server rendering
- HTML-first workflows
- Turbo streams
- progressive enhancement
- minimal JS runtime
- DOM-derived interaction

Avoid:

- SPA complexity unless necessary
- duplicated client/server state
- hydration-heavy architectures

## Operational aesthetic

MASTER should visually express:

- determinism
- inspectability
- replayability
- governance
- confidence under pressure

The interface is part of the runtime philosophy.

## Subtle Delight, Snappiness & Grok-like Reactivity

Grounded in the existing particle kernel, SSE master:visual bridge, low-res pixelated canvases, zsh input, streaming chunks + dmesg, enhance flow, topologies emotional/cell grammar, FLAT_UI/CINEMA_PALETTE/step timing, and NNG gaps (control, error recovery, discoverability, help). All ideas are micro, PRESERVE_FIRST, no new files or heavy machinery, beauty-first (kanso, ma, Ando restraint). Many leverage the kernel's 12 semantic fields and the now-cleaner canonical signals post recent defrag.

### Input & Prompt Bar (zsh, photo, enhance)
1. On #zin focus, advance eyePool attention cells +0.07 for 160ms (kernel-driven "attending" micro-expression; decays naturally).
2. Step-ease the #zsh opacity transition to steps(5, end) at 140ms to match primer/cursor timing.
3. Photo button pointerdown spawns 3 fast-decay speech-kind kernel cells at mouth zone with low pressure (tiny "capture" flash).
4. After successful photo upload (state=ready), fade the button background from accent to fg over 420ms steps(4).
5. Enhance confirm [y/n] flow: on keypress, briefly raise mouthPool arousal 0.4 for one frame (viseme-like "decision" pulse).
6. Placeholder text in zin cycles subtly on idle (every 45s, 3-word variants via CSS only or tiny JS) using muted opacity.
7. Long-press (420ms) on photo button (when idle) triggers a low-entropy "preview burst" of 6-8 attention cells in crown zone.
8. Input value length > 180 chars: scale the zsh border-top thickness 1px → 1.5px over 200ms (quiet density signal).
9. On paste into zin, emit a single master:visual "input:paste" with entropy 0.25 so ecology terrain gets a small basin impact.
10. Cursor in zin blinks at 1.1s step-end (already close); sync blink phase to the primer pulse for global rhythm.

### Streaming, Chunks & Live Feedback (chat-log, cursor, dmesg)
11. On first _chatOnChunk, advance the face colorTarget toward the model tint 15% faster for the opening 800ms (snappier "response starts" feel).
12. New .dmesg-line elements: start at opacity 0.4, step to 1.0 over 180ms (instead of instant).
13. When a sentence chunk ends (period detection in streaming), inject 0.15 pressure into live mouthPool cells (tiny "punctuated" physicality).
14. Cursor removal on _chatOnDone: fade opacity 1→0 over 280ms steps(3) before DOM remove (less abrupt).
15. Scroll-snap in #chat-log: after append, if user is near bottom, use a 1-frame RAF scroll with ease-out steps.
16. Assistant message prompt ("master$ ") appears with 80ms delay after user message for theatrical but quiet rhythm.
17. ERROR: chunks get a 120ms red flash on the current .msg-body (using existing TINT.veto lerp path).
18. Dmesg lines that mention "veto" or "pass": the ecology weather spawns one extra calm burst at low force.
19. Streaming body text: every 4th chunk character, if kernel present, nudge one random live eye cell attention +0.03.
20. After [DONE], the last assistant message gets a 1px left hairline that fades over 1.8s (quiet "settled" marker).

### Particle Face & Ecology Reactivity (kernel, motion, state viz)
21. Idle breath amplitude now also receives a 0.003–0.009 entropy wobble (using the canonical entropy from visual events) for organic micro-variation.
22. On any master:visual with high confidence (>0.85), eyeJitter decay slows 8% for 900ms (calmer, more "focused" passive stare).
23. MouthPool on speech boundary: in addition to arousal/pressure, set 1-2 cells' valence to +0.6 for 220ms (brighter "speaking" micro-glow via existing color lerp).
24. Ecology agent spirits: orbit radius now receives a 0.02–0.06 multiplier from the corresponding kernel cell's attention (already partially wired; make the read authoritative).
25. Terrain line alpha in drawSemanticTerrain: multiply by (0.7 + confidence * 0.3) so high-certainty moments look crisper.
26. Crown zone cells (memory kind): on "memory|retriev" events, spawn one extra slow-decay cell with high valence.
27. Vertex displacement on the icosa: add a 0.3x global scale factor from current mouthDrive average when >0.6 (subtle "full voice" head expansion).
28. When topology switches to codebase via canonical event, edgePoints opacity steps from 0.55 to 0.72 over 300ms (quiet "thinking about code" cue).
29. Reduced-motion profile: still allow 3–4 low-amplitude kernel cell "breaths" per minute at 8% normal motion (never fully static).
30. On device tilt or mouse move, the eyeMask vertices get a 1-frame 0.015 position bias toward the direction (already mouse-driven; add tiny kernel attention boost in that zone).

### Performance & Perceived Snappiness
31. visual_bridge handleRuntimeEvent: batch 2–3 rapid events into one RAF before emitting master:visual (less thrash on busy pipelines).
32. ParticleKernel.step calls: guard with a 8ms min delta (coalesce with existing frame dt) to avoid sub-frame overwork on high refresh.
33. Canvas resize: cache the last internalW/H and only call fitInternalResolution when crossing 50px threshold or profile change.
34. Chat-log appends: use a 1-line micro task queue so 3+ chunks in 50ms render as one DOM write.
35. SSE reconnect backoff: show a single dim dmesg "link quiet" instead of repeated errors; face confidence drops smoothly 0.1.
36. Primer boot sequence: the POST_LINES already beep; add one kernel cell spawn per line (tiny "awakening" particles that decay by "ready").
37. RAF in face/ecology: when document.hidden or battery profile, drop kernel step rate to 1/3 without changing visual governor global cap.
38. Three points count: on coarse pointer or reduced motion, halve the unique edge positions used for edgePoints (cheaper but still reads as dense).
39. Color lerps (faceCurrent → target): use a slightly higher factor (0.06) on high-activity moments detected from recent pulse count.
40. Dmesg fade timeouts: use a shared 3-slot ring so 20+ lines don't create 20 timers.

### Error States, Recovery & Control (NNG 3/5/9)
41. On SSE onerror or ERROR chunk: the face shake now also drops 4–6 random mouth cells' confidence by 0.35 (visible "stutter" without alarm).
42. Escape key (already ttsSkip): also emit a master:visual "user:interrupt" so ecology gets one rift impact (clear "I stopped you" feedback).
43. Photo upload failure: the assistant message appears with a 200ms delayed red hairline on the photo-button (state reset happens first).
44. Enhance [y/n] timeout (no key in 12s): auto-accept original with a quiet kernel "settle" pulse (no pressure spike).
45. Long-press anywhere on #chat-shell (outside input): triggers ttsSkip + one ecology weather burst at low force (emergency stop affordance).
46. After veto verdict: the next zin placeholder temporarily reads "try a tighter question" for 9s (subtle recovery hint, no new strings in core logic).
47. Confidence event <0.3: eyeJitter gains a tiny random 1px twitch every 4th frame for 2.5s ("nervous but working" micro).
48. /run natural language commands: on submit, the face pulse starts 40ms earlier than the SSE roundtrip (predictive "heard you").
49. STT (long-press canvas): on recognition start, all live eye cells get +0.25 attention for the duration (visible "listening hard").
50. Network stall >4s: a single very dim centered dmesg "link thinking" appears once; face breath slows 30% (quiet waiting state).

### Discoverability, Help & Recognition (NNG 6/10)
51. First successful message after boot: spawn 5 slow crown memory cells labeled by provider (tiny "you used X" echo that fades in 12s).
52. Hover (or pointer near) the #face canvas edges: raise 2–3 peripheral kernel cells' arousal 0.2 for 300ms (quiet "edge has meaning" affordance).
53. Zsh input empty + 6s idle: one very low-alpha ecology "help" trail appears pointing toward the input (auto-removes on any input).
54. Verdict "pass" events: the chat-log gets a 1px hairline flash under the last message (matches the beep).
55. On model tint change (claude/gemini etc.): the face TINT lerp also nudges one mouth cell valence toward the new hue for 1s.
56. Canvas double-tap (coarse) or double-click: cycles the visual profile (full/battery) with a single kernel cell "confirm" spawn.
57. Dmesg lines mentioning tools: those lines get a persistent 0.6s longer fade and a tiny corresponding ecology flow cell.
58. Primer "ready" speech: at the moment the voice starts, 8–10 new attention cells spawn across eye zones (boot "eyes opening").
59. When topologies switch (face <-> ecology <-> codebase), the document root data attr change is accompanied by a 90ms global canvas filter contrast nudge (0.05) that steps back.
60. Photo button in "ready" state: pointerenter spawns 1–2 memory-kind cells at crown with the image token as a pseudo-label (harmless, decays).

### Micro Personality & Grok-like Delight (tied to existing soul/TTS/kernel)
61. TTS onboundary (already drives arousal): also set a random live eye cell's valence +0.15 (subtle "smiling while speaking" with the viseme mouth).
62. Osman creative styles (dramatic/ethereal etc.): when active via server TTS, the face receives a one-time master:visual with mode=style-name that slightly warps the breath frequency for the duration.
63. High-entropy moments: ecology terrain gets 1–2 extra jagged lines for 1.8s (matches "spray: entropy" cell grammar without extra cost).
64. Council deliberation start (newer bus events): all 7 agent spirits briefly increase radius 8% then settle (visible "thinking together").
65. Successful auto-commit after mutation: one crown cell gets high confidence + slow decay and a green-tinted valence (quiet "saved" joy).
66. Visitor vs dev tier: the zsh .pp color desaturates 15% for visitor (already data-driven; make the face overall saturation follow the same).
67. WakeLock acquired: a single 80ms full-white low-alpha flash on the primer area (then gone) — "eyes open, staying awake".
68. Reduced-motion + coarse pointer: the eyeJitter is replaced by a slower 0.8s sinusoidal "scan" across the two eyes (still expressive, zero random).
69. Every 25th chunk in a long response: if no recent user gesture, the head3 does a 0.8° micro-yaw toward the last mouse position (subtle "checking in").
70. On final [DONE] with high confidence: the last dmesg line (if any) gets a 0.4s brighter moment before its normal fade.

### Accessibility, Reduced Motion & Edge Polish
71. All new step transitions respect the existing @media (prefers-reduced-motion) rule (already inherited).
72. Focus-visible on zin and photo-button: add a 1px outline that also raises the nearest eyePool attention cells (keyboard users see the face react).
73. Canvas aria-hidden already present; add role="img" + dynamic aria-label derived from current State.mode + confidence (e.g. "thinking, 0.78").
74. When battery profile active, all particle counts in kernel pools are halved at spawn time (already partially done via limits; make consistent for ecology agents too).
75. Scroll in chat-log: momentum on touch devices already; add a 60ms RAF clamp so it never overscrolls past the last message by >12px.
76. Color contrast: all new micro elements (hairlines, flashes) stay within the existing --face-fg / muted tokens.
77. VoiceOver / SR users: the dmesg lines are already low-volume; ensure they are not announced by wrapping new ones in aria-hidden when they are purely visual echoes.
78. Pointer coarse: increase the long-press timeout from 420ms to 520ms and widen the STT hit area by 8px (easier on phones).
79. Visibilitychange hidden: already pauses some work; also pause new kernel spawns from non-critical events for 800ms after return.
80. Error recovery text (e.g. photo fail): use the exact same mono font and dim color as dmesg so it feels like part of the instrument, not a dialog.

These 80 ideas are all small deltas on existing paths (kernel fields, RAF loops, SSE listeners, CSS custom properties, data attrs, existing TINT/lerp/pulse). Most are 1–4 line changes. Many directly improve the "watch from afar" passive beauty while adding the snappy, alive, grok-like reactivity (instant visual acknowledgment of every user action and every internal state change) without violating restraint or introducing noise.

Implementation order suggestion: group by file (bridge + face first for signal + breath wins, then chat.js + css for input/streaming, then ecology for field harmony). Each can be a separate micro-slice after full re-read of the touched file. All preserve current behavior as fallbacks or additive only.

## Implementation Status (Micro-Slices)

**Batch 1 completed (micro-slices 3-6, covering ~12 ideas + foundations):**
- Bridge classify now prefers registry (ONE_SOURCE signal cleanup for all downstream reactivity).
- Face idle breath: confidence modulation + entropy wobble (ideas 21 + related).
- Face speech boundary: valence boost on mouthPool cells (idea 23).
- Face high-confidence: eyeJitter decay slowed (idea 22).
- Face tint lerp: activity-adaptive faster speed on pulse (snappier model/mood response).
- Chat streaming: cursor removal with step fade (pleasant done state).
- Chat dmesg: quick step fade-in on appearance (snappier live log).

**Batch 2 (micro-slices 7-9, ecology field harmony):**
- cognition_ecology.js: agent orbit radius now subtly tightens with high confidence (calmer, more focused "spirits").
- Terrain line alpha now scales with confidence (crisper field when system is sure).
- High-entropy moments now produce visibly more jagged/chaotic terrain lines (extra "jagged" effect per idea 63) — all using the canonical event signals.

**Batch 3 (micro-slice 10, face personality):**
- face.js: eyeJitter now increases with entropy (nervous/tense eyes on high-entropy moments) while still damped by confidence — nice "alive" personality signal for the watched face.

**Batch 4 (micro-slices 11-16, Ruby runtime events + face reaction):**
- ... (Ruby signals for council:deliberation, user:interrupt, tts:style:active, tribunal:rendered+confidence, input:long, link:quiet — ideas 64/42/62/47/70/17/8/9/48/35/50/167 + NNG control/recovery)
- face.js verdict handler: numeric confidence now drives jitter + brightness.
- face.js: council:deliberation/start now visibly raises mouth pressure + lowers eye confidence (idea 64).
- face.js: input:long/cmd:long now drives jitter + mouth pressure (ideas 8/9/48 density/predictive).

**Remaining backlog** in todo (ms17+). All changes 1-line additive PRESERVE_FIRST after full re-reads. Face now visibly reacts to verdict confidence, council deliberation, and long inputs. Continuing systematic micro-slices.

Run `/sweep` or equivalent after full set for style.

