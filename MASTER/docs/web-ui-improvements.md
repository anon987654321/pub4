# MASTER Web UI Improvement Proposals

**Scope**: MASTER/web/ (face rendering, chat interface, dashboard, PWA, SSE/streaming, canvas interactions, CSS, controllers, public/*.js assets).

**Basis**: Code analysis of current implementation (minimalist zen "terminal" aesthetic, face as central visual, chat-log + zsh prompt bar, heavy JS in public/ for particles/3D/dither/phosphor, Rails backend for chat/tts/photo/events, existing TODOs in Q4/Q5/L/O sections).

**Philosophy alignment**: Preserve ultra-minimal, OLED-black, crosshair-cursor, monospace, no-fuss "you$ / master$" feel. Enhance without adding chrome. Favor pixelated/retro where it fits (see recent white phosphor face changes). Performance on low-end (coarsePointer modes). Accessibility, battery, offline. Deep integration with MASTER core (bus events, visual state, voice, models).

**Total ideas**: ~160 (categorized; many build on or expand existing TODOs like Q401-Q510, L01-L08, O5xx; new ones from direct code review of chat.js, face.js, face3d_*, mask.js, particle_kernel.js, controllers, CSS, views).

Ideas are actionable, small-to-medium patches preferred. Prioritize: face/visual (core identity), streaming UX, perf, a11y, features that surface MASTER capabilities.

## 1. Face / Particle / Visualization System (25 ideas)
1. Implement full module split for face.js (Q401): face/particles.js, face/audio.js, face/expressions.js, face/tts.js, face/main.js + index that wires.
2. Add Web Worker for particle physics/simulation updates to offload main thread (esp. with 20k particles).
3. Expose face config UI (sliders for N particles, morph speed, coherence, breathing amp) in a hidden "dev face panel" toggleable by ?debug=1 or alt-click logo.
4. Add "face modes" switch: 3D points (current), raster dither (face3d), hybrid, wireframe, silhouette only.
5. Improve 2D fallback (no WebGL): use ParticleKernel for consistent dithered cell rendering instead of ad-hoc fillRect.
6. Add face "afterimages" / trail effects using offscreen canvas + alpha decay for phosphor persistence visual.
7. Support multiple simultaneous faces (e.g. Osman + Pernille side-by-side or layered for council deliberation).
8. Drive face directly from visual_bridge + face_state more deeply (e.g. entropy -> particle scatter, confidence -> cohesion).
9. Add procedural "damage" / glitch effects on face for veto/error states (scanlines, pixel drop, chromatic aberration via canvas filters).
10. Make particle count dynamic + LOD: lower for battery/coarse, higher for desktop; auto-scale with viewport + FPS.
11. Add face "idle animations" library: breathing, saccades, subtle topology morphs even without input.
12. Integrate cognition_ecology visuals as "background" or "halo" around the face (terrain, trails).
13. Add face export: button to snapshot current state + canvas as PNG/SVG with metadata (model, mood, timestamp).
14. Improve expression transitions with lerp + easing curves (Q410) + audio-reactive (viseme drives jaw/mouth blendshapes in 3D).
15. Wire persona color/motion distinction (Q412) even in white-phosphor mode: use subtle size variation, dither density, or secondary "aura" particles per persona.
16. Add "thinking" face state: slower morph, higher scatter, pulsing highlight on "active" zones.
17. Canvas resize observer + DPR clamping + virtual resolution for consistent pixel look across devices (Q405).
18. Pause rAF + audio analysis on hidden tab + reduced-motion (Q402, Q409); resume gracefully.
19. Add visual "TTS fetching" anticipation indicator (Q413): pre-load expression change + brief particle "inhale".
20. Face as interactive: click zones to trigger /why or specific persona speak; drag to rotate 3D head.
21. Add face "memory" overlay: faint previous topologies or cluster points fading in as "ghosts".
22. Support high-contrast / monochrome forced mode for accessibility (beyond current white).
23. Dither quality modes: low (bayer fast), high (Atkinson + multi-pass), none (for perf).
24. Face state persistence: save/restore last expression + topology across reloads via localStorage or session.
25. Add subtle CRT bezel / scanline overlay (CSS + canvas) toggleable for extra retro 8-bit terminal feel.

## 2. Chat Interface & Streaming (30 ideas)
26. Add chat history sidebar (collapsible, searchable) that loads from /chat/history; click to replay with context.
27. Infinite scroll / pagination for chat-log (virtual list for long sessions).
28. Command palette (cmd+k / ctrl+k): fuzzy search available /commands, recent, face modes, etc. (builds on missing web /grep etc.).
29. Per-message actions: copy, "regenerate with different model", "send to face as expression", "quote in new input".
30. Better streaming UX: word-by-word reveal with cursor, optional "instant" mode, typing sound (subtle, opt-in).
31. Multi-turn editing: click previous user message to edit + branch (like chat UIs); server supports via context.
32. Attachments beyond photo: drag-drop files, paste images, with preview + postpro options.
33. Enhance preview live: as you type, subtle dimmed suggestion below input (Q202 style progressive).
34. Voice input: button for STT (browser or server), auto-send on silence (T728).
35. Threading / branching UI: visual tree or "fork" button for alternative explorations.
36. Search in chat: / or input prefix to filter visible messages + highlight.
37. Markdown / code rendering in assistant responses (syntax highlight via lightweight lib or Prism).
38. Cost / token / model badge per message or session (surfaced from backend).
39. "Thinking" indicators: per-chunk status (enhance, tool call, council) with icons or face sync.
40. Undo / edit last turn: keyboard or button that reverts UI + sends correction.
41. Session save / load / export: buttons for markdown, jsonl, or "shareable replay" link.
42. Input history (arrow up/down) persisted client-side or via /history.
43. Auto-complete for @mentions (files? models? personas) in prompt.
44. Better error recovery: retry button on stream fail, with last message preserved.
45. Collapsible / summary for long assistant blocks (click to expand).
46. Side-by-side diff view when enhance or tool results change output.
47. Chat log "dmesg" as optional overlay or bottom ticker (already partial).
48. Input bar improvements: growing textarea, emoji picker? no — keep minimal; better placeholder with examples.
49. Send on shift+enter? Or configurable.
50. Mobile: better virtual keyboard handling, swipe gestures for history, tap face to focus input.
51. "Quiet mode": hide chat-log, only face + minimal prompt (focus on visual).
52. Multi-user / shared chat? (if auth allows) with user colors.
53. Rate limit UI feedback: show "slow down" when hitting backend throttles.
54. Paste detection + large paste handling (Q107).
55. Command bar integration: type / in input to trigger palette.

## 3. Performance & Rendering (20 ideas)
56. Bundle split / lazy load: face3d only when needed, three.module only on WebGL, etc.
57. OffscreenCanvas for face rendering where supported.
58. Throttle / debounce heavy listeners (mousemove, resize, audio).
59. FPS monitor + auto quality downgrade (particle count, dither, shadows).
60. Memory: clean up old canvases, event listeners, SSE on unmount/navigation.
61. Preload critical assets (manifest, fonts, face shaders) + service worker caching (already partial sw.js).
62. Reduce main thread work in draw loops: use requestIdleCallback for non-visual.
63. Canvas pooling or single canvas for multiple visual systems (face + ecology + codebase).
64. WebGL instancing or points with better shaders for 20k+ particles.
65. CSS containment, will-change, transform for chat-log and overlays.
66. Debounce photo postpro + uploads.
67. Virtual scrolling for very long chat logs + dmesg lines.
68. Worker for audio analysis / FFT.
69. Measure & report render time, particle update time via /metrics or debug panel.
70. Avoid layout thrashing in appendMsg / streaming updates.
71. Image loading lazy for any future icons / previews.
72. Font subsetting or system stack fallback for "Roboto Mono".
73. Reduce re-renders: React-like signals or simple dirty flags for face state.
74. Battery-aware: lower particle N, disable audio viz, slower animations (already partial via data attrs).
75. Profile with devtools; add perf marks around key paths (draw, SSE, enhance).

## 4. Accessibility & Inclusivity (18 ideas)
76. Full ARIA: roles, labels, live regions for streaming text (Q414), face as decorative or described.
77. Keyboard only: full nav of history, input, photo, face interactions (tab, arrows, enter, space).
78. Screen reader: announce new messages, face state changes ("Osman thinking", "expression: curious"), dmesg.
79. High contrast mode: stronger --face-fg, forced outlines, no subtle opacity.
80. Reduced motion: respect everywhere (Q409), provide "static face" option.
81. Color: ensure all states have non-color indicators (icons, patterns, text); our white face helps.
82. Touch targets: min 44px for buttons (photo, primer, etc.).
83. Focus management: visible focus on primer, input, messages; trap in modals if added.
84. Voice / TTS controls: volume, speed, skip visible + keyboard.
85. Alt text / descriptions for any visual outputs (future diagrams, exports).
86. Language: support dir=auto, better i18n if ever.
87. Error announcements: polite live regions for failures.
88. Magnification / zoom friendly (no fixed small fonts without scale).
89. Captioning for any future video/audio in UI.
90. Cognitive: clear affordances, consistent "terminal" metaphors, undo everywhere.
91. Pointer: support coarse (touch) vs fine; larger hit areas.
92. Add "describe face" button that reads current state aloud or to clipboard.
93. WCAG AA/AAA audit pass for contrast (current dark theme mostly good with white on black).
94. Skip links or quick nav for long logs.
95. Announce model / tier / cost changes.

## 5. Theming, Aesthetics & Polish (15 ideas, building on white phosphor)
96. Expand runtime profiles: "zen" (current), "crt" (scanlines + bloom on white pixels), "pixel" (strict low-res no upscale), "neon" (subtle color accents on white).
97. More CSS vars for easy theming: --face-particle-size, --dither-strength, --phosphor-decay.
98. Darker-than-black or true OLED modes with --face-bg: #000000.
99. Subtle background textures (very faint grid or noise) that react to face state.
100. Consistent micro-animations: only steps() or linear for retro; spring for modern opt-in.
101. Logo / branding polish: animated "MASTER" that pulses with face.
102. Error / 4xx / 5xx pages styled in same terminal aesthetic (already partial HTML).
103. Photo upload UI: better preview, progress, postpro choice (stock selector).
104. Enhance confirm: nicer UI than [y/n] text (still keyboard driven).
105. Cursor: custom crosshair already good; variants per state (thinking = hourglass pixels?).
106. Scrollbars: custom thin monospace-style that fit zen.
107. Selection: highlight color matches --face-fg dim.
108. Print / export styles: clean chat transcript.
109. Seasonal / event skins (subtle): e.g. holiday dither patterns.
110. User-select and drag prevention tuned (already mostly).
111. Focus-visible outlines that look pixelated / retro.
112. Toast / flash messages in dmesg style (dim, auto-fade).
113. Loading skeleton for initial face + chat that matches pixel aesthetic.
114. Subtle CRT curvature / vignette via CSS filter or overlay (opt-in).

## 6. Features & New Capabilities (25 ideas)
115. Full offline mode: cache last session, local TTS fallback, offline face sim (Q510).
116. STT everywhere: mic button in prompt, wake-word "master", continuous listening opt-in.
117. Multi-model chat: switch model mid-session with visual indicator (face tint gone, but badge + expression).
118. Tool use visualization: live face + log updates when tools run (already dmesg partial).
119. Council / deliberation view: show multiple personas "speaking" with face switching or split.
120. Code execution sandbox preview in chat (if /run etc.).
121. File browser / @file completion integrated with codebase visual.
122. Session analytics dashboard (separate or overlay): tokens, cost, turns, common commands.
123. "Remember this" : highlight messages to pin to long-term memory.
124. Image gen integration (repligen?) triggered from chat + face reaction.
125. Voice cloning / style training UI (advanced).
126. Collaborative: share session link, multiple cursors (if auth).
127. Export to other formats: PDF transcript, audio podcast of session.
128. Quick actions bar: /scan, /fix, /critique buttons that inject into chat.
129. Face-driven commands: certain expressions trigger suggestions (e.g. "veto" face suggests rollback).
130. History search across sessions (backend + UI).
131. "What would X say?" : switch persona for last response preview.
132. Diff view for any file changes mentioned in response.
133. Calendar / reminder integration from chat (future).
134. Better photo: multi-photo, camera live preview, auto-crop to face.
135. Audio upload / transcription.
136. Diagram / ASCII art rendering from responses.
137. "Continue in background" for long tasks with notification.
138. Bookmarkable states: ?face=neural& mood=curious&log=last10 .
139. Theme editor for advanced users (CSS vars live edit).

## 7. Architecture, Code Quality, Backend (20 ideas)
140. Extract ChatService from chat_controller (O106).
141. Extract ImagePresenter for photo (O107).
142. Add strong params everywhere (O505).
143. Move TTS synthesis to background job + polling (O507).
144. Rate limit all endpoints (O501, Q501).
145. ETag / Cache headers for static responses (Q502).
146. Strict loading, N+1 checks (O508, L07).
147. Better error taxonomy + user-friendly messages.
148. Audit logs for chat commands / photo uploads.
149. Split large JS: move 3D math, dither, kernel to workers or dedicated modules.
150. Add tests for controllers, JS (smoke at least).
151. TypeScript? or JSDoc for public/*.js.
152. CSP review / tightening (already has initializer).
153. Auth tier improvements: finer grained for web vs CLI.
154. Database for chat history / sessions (current in-memory?).
155. Webhook / API for external chat clients.
156. Metrics: expose Prometheus for web requests, face FPS, stream latency.
157. Internationalization hooks (even if English primary).
158. Configuration for face defaults, chat limits per tier.
159. Graceful degradation: if face fails, still full chat.
160. Versioning: UI version in meta, easy rollback.

## 8. PWA, Mobile, Offline, Distribution (12 ideas)
161. Better PWA: install prompt, better icons, splash, shortcuts (chat, face only).
162. Background sync for pending messages.
163. IndexedDB for full chat history + face snapshots.
164. Responsive: dedicated mobile layout (bottom bar, larger targets, no hover).
165. Add to home screen guidance.
166. Share target: accept shared text/images into chat.
167. Offline face: procedural animation without backend.
168. Push notifications for long-running tasks or mentions.
169. Installable "kiosk" mode for always-on face display.
170. Better iOS/Android webapp meta (status bar, safe areas — partial).
171. Service worker update UX (new version toast).
172. Performance budgets + lighthouse CI.

## 9. Dev / Debug / Observability (15 ideas)
173. ?debug=1 or alt+d : overlay with FPS, particle count, state, last events, bus traffic.
174. Visual debugger: click particle to log its zone/state.
175. Live CSS var editor.
176. Record / replay session (face + chat + audio).
177. Export face state JSON for face3d_preview or tests.
178. Console commands exposed (window.MASTERFace.setTopology etc. documented).
179. Network panel simulation (throttle SSE).
180. Error boundary UI that shows stack + "report to /propose".
181. A/B for face algorithms (dither type, particle vs raster).
182. Telemetry opt-in: anonymized usage (face interactions, commands used).
183. Hot reload for public/*.js during dev (bin/dev already?).
184. Screenshot automation for docs / gallery.
185. Accessibility audit button (axe or similar) in debug.

## 10. Integration with Broader MASTER (10 ideas)
186. Deeper visual_bridge: more events (proposal, council vote, self-scan) drive face + dmesg.
187. Codebase visual synced with chat context (highlight files mentioned).
188. Cognition ecology as "peripheral vision" around face.
189. Proactive proposals surfaced in chat UI (R section).
190. Persona system (S1) fully wired to voice + face + prompt prefix.
191. Self-evolution / meta (S2, W) visible in dashboard or "insights" panel.
192. Event bus inspector (live list of recent master:visual etc.).
193. Cost / usage from metrics exposed nicely.
194. Direct link from face click to relevant /why or source.

## 11. Miscellaneous / Wild (10+ ideas)
195. Easter eggs: konami code for old-school face mode or dilla soundtrack.
196. Collaborative face: multiple users affect same particle system (fun demo).
197. Generative face variants: user prompt "make the face look like a cat" -> topology/morph.
198. AR mode: face overlaid on camera (advanced, privacy).
199. Sound design: more procedural audio tied to face (beyond TTS).
200. Localization of the "terminal" metaphor (different prompts per language).

**Next steps recommendation**: Pick high-impact low-effort from face (1-25) and chat (26-55). Many can be done with small targeted edits to public/*.js + CSS + minor controller tweaks. Track them in a new section of this doc. After batch, run full web surface scans (L items) + manual a11y/perf audit.

**Measurement**: Add basic analytics (events for face interaction, message sent, etc.) to validate improvements.

This list is derived from direct code reading + existing backlog. Can be expanded further with user testing or more deep dives (e.g. full face.js 1286 lines analysis).

---

*Generated as part of web UI exploration. Committed to docs for reference. Many ideas align with "zen-minimal" + retro pixel soul of the project.*
