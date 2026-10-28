# MASTER FaceWorld

FaceWorld is the browser's spatial projection of MASTER's canonical face state.
The CLI, web HUD, 2D fallback, voice timing and 3D renderer share the same
semantic contract. Renderers may simplify geometry for device limits, but may
not invent a second state vocabulary.

## Runtime shape

```
FaceState
  -> FaceWorld
     -> identity
     -> eyes
     -> mouth
     -> cognition
     -> repository
     -> event_field
     -> camera
     -> hud

FaceState
  -> CLI
     -> dmesg
     -> prompt
     -> scrollback

FaceState
  -> Voice
     -> TTS
     -> speech timing
```

The source of truth is `MASTER/data/tokens.yml#tokens.face_interface`.
Ruby reads it through `MASTER/lib/face.rb`. Browser code receives
the same block as `MASTER_FACE_CONTRACT` and keeps dynamic state in
`MASTER_FACE_STATE`.

Face-only grayscale values live in `tokens.face_root.palette`; the universal identity accent and
Brgen/Amber palettes retain their own colours. The CLI uses neutral graphite depth tones, and its
small gaze movements read from the same face contract. The web prompt renders the canonical
`Master::Face::Contract.shell_prompt` at mobile and desktop widths while keeping its visible measure
bounded so the message field and touch controls remain usable.

Micro expressions are semantic blendshape cues; nano-saccades are event-driven eye-field nudges.
Both reuse the existing runtime and remain off under reduced-motion preferences. Web visemes follow
the audio clock at 45 ms sampling intervals; the terminal mouth continues to follow the audio
envelope and phoneme shape.

## Primary material: particle stipple

FaceWorld's material is greyscale particle stipple, named in `tokens.visual_identity.material`
and governed by the law `VISUAL_PARTICLE_STIPPLE_PRIMARY`. The face is not a solid skin. It is a
field of many carriers that resolve into one readable head: out of many, one. A renderer may
simplify geometry for a device's limits; it may not invent a second identity material, such as a
coloured particle skin or a glossy mesh.

What each state means in that material lives beside its dials, in
`tokens.face_interface.stipple_vocabulary`, `stipple_membership`, `stipple_force` and
`stipple_note`, and the browser playground prints the reading for the state it shows. Membership
runs from unturned (still individual) through transitional and turned (admitted into the field)
to locked.

| State | Membership | Force | Reading |
|---|---|---|---|
| idle | transitional | residual | many at rest; individual seeds still visible |
| listening | transitional | ripple | the field opens to incoming signal |
| thinking | turned | gather | parts concentrate toward one locus |
| working | turned | gather | the locus holds while work runs |
| speaking | turned | ripple | signal leaves through the mouth region |
| warning | transitional | residual | binding loosens; individuals reappear |
| error | unturned | fragment | admission fails; the field breaks and may rejoin |
| ready | locked | settle | out of many, one stable form |
| sleeping | unturned | residual | carriers at rest; the field dims but is not erased |

Motion defaults to still. Gather, ripple, fragment and settle run only when a state supplies the
cause, and reduced motion keeps the turned and unturned contrast readable without animation.
Idle keeps its residual, because a field with no individual variation is a fog. The neutral highlight
marks admission and focus only. The point budget and the stipple layer's limits are in the
section on the additive stipple layer below.

## 3D restructuring catalogue

These are implementation directions that all preserve the same state contract.

### Core geometry

1. Floating head-shaped field.
2. Wireframe skull.
3. Volumetric fog skull.
4. Hollow shell with luminous interior.
5. Anatomical cutaway.
6. Tessellated facial surface.
7. Signed-distance facial field.
8. Voxel head.
9. Sparse particle reconstruction.
10. Gaussian-splat reconstruction.
11. Mesh plus splat hybrid.
12. Geometry-free mouth.
13. Recessed eye apertures.
14. Layered anatomical shell.
15. Asymmetric facial topology.
16. Activity-driven geometry density.
17. Confidence-driven shell scale.
18. Risk-driven fracture.
19. Sleep-driven topology collapse.
20. Boot-driven reconstruction.

### Eyes

21. Recessed black apertures.
22. Luminous depth wells.
23. Camera-like optical assemblies.
24. Pointer-tracked gaze.
25. Split stimulus tracking.
26. Attention-driven convergence.
27. Multitask-driven divergence.
28. Attention-driven pupil scale.
29. Cognitive-load iris density.
30. Uncertainty wireframe eyes.
31. Confidence solid eyes.
32. Geometry-derived blinking.
33. Deterministic micro-saccades.
34. Event-directed gaze shifts.
35. Task-directed gaze shifts.
36. Eyes inspect HUD state.
37. Eyes inspect repository nodes.
38. Input/output eye split.
39. Single-aperture deep-think mode.
40. Listening retinal scan.

### Speech

41. Luminous mouth slit.
42. Volumetric mouth cavity.
43. Speech topology deformation.
44. Abstract lip geometry.
45. Phoneme waves across the face.
46. Amplitude-driven mouth depth.
47. Speech-rate edge vibration.
48. Pause-driven settling.
49. Consonant impulses.
50. Vowel widening.
51. Waveform mouth aperture.
52. Voice wave travelling through the head.
53. Speech-only jaw geometry.
54. Spatial speech trails.
55. Rear-skull waveform wrap.

### Cognition

56. Volumetric neural field.
57. Filament neural graph.
58. Nodes mapped to pipeline stages.
59. Edges mapped to data flow.
60. Risk-driven density.
61. Error-driven disconnection.
62. Completion-driven graph collapse.
63. Parallel tool paths.
64. Ear-to-cortex-to-executor-to-mouth flow.
65. Repository traversal visualization.
66. Directory clusters.
67. File nodes.
68. Dependency fibres.
69. Dead-code dark matter.
70. Successful cleanup as entropy reduction.

### Repository geometry

71. MASTER as head.
72. `lib` as brain.
73. `law` as spine.
74. `tools` as hands.
75. `web` as visual cortex.
76. `RAILS` as external sensory layer.
77. `OPENBSD` as substrate.
78. `STUDIO` as imagination layer.
79. Git branches as spatial strata.
80. Dirty changes as surface perturbations.
81. Dirty files as local topology distortion.
82. Tests as support structure.
83. Failing checks as broken links.
84. Known-good commits as anchors.
85. `/fix` as geometric rehabilitation.

### Camera

86. Head-relative parallax.
87. Face-centred camera.
88. Restrained orbit.
89. Pointer-driven camera tilt.
90. Device-orientation camera.
91. Listening proximity.
92. Speaking recession.
93. Bounded error displacement.
94. Sleeping camera descent.
95. Boot reveal from close range.
96. Resize-preserving semantic scale.
97. Shared CLI/browser camera state.
98. Camera distance from attention.
99. Camera distance from risk.
100. Camera limit from canonical contract.

### Materials

101. One master face material graph.
102. TSL-based shader layer.
103. Cognition-driven topology visibility.
104. Anisotropic curvature reveal.
105. Subsurface-like restrained shading.
106. Transparent thought volumes.
107. Depth-dependent line density.
108. Roughness as calm/activity.
109. Specular response as attention.
110. Speech-driven material density.
111. Monochrome `wscons` mode.
112. Device-budget material reduction.
113. Postprocess reduction before semantic reduction.
114. Stable monochrome fallback.
115. Deterministic noise everywhere.

### Splat and hybrid rendering

116. Canonical neutral splat field.
117. Expression field interpolation.
118. Splat opacity for transient cognition.
119. View-dependent SH detail.
120. Mobile/desktop LOD.
121. Eye-first streaming.
122. Mouth-first streaming.
123. Ghost-face streaming placeholder.
124. Mesh collision hull under splats.
125. Splat-backed thought matter.
126. Fragmentation on error.
127. Reconstruction on recovery.
128. Native GaussianSplat capability detection.
129. Deterministic point fallback.
130. Shared state for mesh/splat projections.

### Terminal-native 3D HUD

131. Monospaced spatial labels.
132. `master0` semantic anchor.
133. `voice0` voice anchor.
134. `web0` web anchor.
135. `root on master0` boot anchor.
136. Repository nodes with dmesg labels.
137. Command execution as spatial dmesg.
138. Errors pinned to their subsystem.
139. Success lines fading after acknowledgement.
140. Current command on the nearest plane.
141. History receding into depth.
142. `you$` / `master$` shared prompt vocabulary.
143. Flat scrollback instead of bubbles.
144. No decorative panel chrome.
145. `/status` widening the terminal plane.
146. `/doctor` widening diagnostic space.
147. `/fix` showing traversal.
148. `/face` exposing the spatial projection of the same command.
149. Text fallback for every visual state.
150. Accessibility tree matching spatial state.

### Physics and runtime

151. Spring-based facial rig.
152. Named animation states only.
153. Deterministic event impulses.
154. Mass and damping for major objects.
155. Input-driven energy.
156. Bounded event accumulation.
157. Predictable energy decay.
158. One animation scheduler.
159. Demand-driven idle rendering.
160. Active 60fps ceiling.
161. Idle low-FPS ceiling.
162. Hidden-tab zero-FPS budget.
163. Mobile point ceiling.
164. Desktop point ceiling.
165. DPR ceiling.
166. Event-pulse cap.
167. Render-loop watchdog.
168. Visibility recovery.
169. GPU failure degradation.
170. No uncontrolled auxiliary RAF loops.

### Non-human identity

171. Geometry-first identity.
172. Motion grammar as personality.
173. Incomplete-form frames.
174. Mathematical membranes.
175. Voice-grown geometry.
176. Silence-collapsed geometry.
177. Non-human optical anatomy.
178. Topological expression.
179. Repository-scale machine mode.
180. Information-dense diagnostic mode.

The numbered catalogue is deliberately additive. Selection is renderer-budget
and device dependent; the semantic contract remains singular.

## ASCII sculpt controls

The terminal and browser render the same perspective-correct, lit triangle mesh as
ASCII, with the contract's character ramps ordered by measured ink density. The
browser keeps the existing single frame loop and offers the same practical controls
as the STL-to-ASCII reference:

- `c`: cycle the contract's sculpt, high-contrast and fine-detail character ramps.
- `m`: reverse or restore the ASCII tone ramp. This does not invert the page or
  recolour the underlying WebGL scene.
- `r`: pause or resume automatic rotation; dragging horizontally on the face
  canvas manually changes the ASCII head's viewing angle.
- `?face_ramp=high_contrast`, `?face_ink=light` and `?face_rotate=0`: set those
  preferences directly; `?face_chars=MASTER` supplies a custom printable-ASCII ramp.

In the terminal, `MASTER_FACE_RAMP=high_contrast`, `MASTER_FACE_CHARS=MASTER`,
`MASTER_FACE_MODE=light` (reverse the tone ramp), `MASTER_FACE_ROTATE=0`, and
`MASTER_REDUCED_MOTION=1` select the equivalent appearance options. Named ramps live in `MASTER/data/tokens.yml`; the browser and
Ruby renderer do not carry separate copies of the ramp definitions. The ordinary
ramp, default ink and pose remain unchanged so the existing golden frames stay valid.

## Sparse gravitational field

The current 3D face uses a sparse, void-first projection layered onto the canonical
FaceState. It intentionally avoids a filled particle carpet: eyes and mouth are
described by rings and broken contours, cheeks have three depth layers, and detached
fragments orbit in the surrounding void.

The field implements the complete interaction vocabulary introduced in the 2026-10-08
design pass: orbit, drift, attract, repel, bloom, collapse, fragment, remember, connect,
breathe and resolve. It adds a super-void state for long silence, three-dimensional depth
reveal from camera distance, deterministic particle memory, and semantic particle gathering.
Thinking gathers high on the forehead; listening blooms the cheek/ear structures; speaking
draws a temporary voice filament around the negative-space mouth; errors fragment; and
reflection/repair recomposes the field.

Human presence is a local gravitational force driven by pointer position and held briefly as
a decaying presence field, so the face continues to acknowledge a person for a moment after
the pointer leaves. Eye and mouth wells remain deliberately empty. Evidence creates temporary
connecting trails; speech creates separate voice traces; Law/canonical events create resonance
rings. Detached particles orbit in the periphery with a small anti-gravity drift, while
stable asymmetry and seeded memory prevent the field from becoming a perfectly mirrored
screen saver. The sparse-field shader uses hard-edged points with distance-aware size
clamped to its four-pixel shader ceiling rather than soft particle glows, keeping negative
space as the dominant visual material. The renderer remains subordinate to the single
FaceState and the existing frame clock.

## Additive stipple layer

The browser stipple layer is a bounded rendering adapter, not a second face-state
system. `RAILS/master/public/face_stipple_system.js` reads the nine profiles from
`MASTER_FACE_CONTRACT.stipple.profiles`, derives its starting point samples
deterministically, and attaches the overlay through the existing face renderer.
It does not own a second animation loop or replace the canonical FaceState,
FaceWorld, ParticleKernel, or sparse gravitational field.

The layer is enabled by default for the web face; `?stipple=0` disables it for
comparison. The additive point-layer ceiling comes from `face_interface.spatial.budget`: 1,200 desktop points and 420 coarse-pointer/mobile points in total across the stipple and FaceWorld proxy. The canonical `point_allocation` gives 75 percent to stipple (900 desktop, 315 constrained-device points) and 25 percent to the FaceWorld proxy (300 desktop, 105 constrained-device points). `FaceState.renderBudget()` resolves the split once, so concurrent adapters do not each claim the full ceiling. The sparse gravitational field separately obeys the shared particle budget, including the 64-particle reduced-motion ceiling. The shared swarm contract in face_interface.swarm applies a lower 240-particle soft ceiling to this stipple overlay, still underneath the 900/315 allocated point shares. The separate sparse_field continues to use its own desktop/mobile and 64-particle reduced-motion budget. Renderers may choose less detail, never more. Missing pressure telemetry
uses the neutral pressure value, so it does not silently alter a mode's canonical
density. Reduced motion freezes time and removes ripple and turbulence while
retaining the still-state profile.

This is a stipple/point-sprite shader, not a Gaussian-splat renderer. The latter
uses anisotropic Gaussian primitives, density control, and visibility-aware
splatting; its costs and visual quality cannot be inferred from this overlay.
The canonical `kinetic_depth` direction still calls for raw WebGL points and
short shaders. Replacing the current Three.js face is a separate renderer migration
and must preserve deferred WebGL boot, the single frame clock, accessible state
and the text/ASCII recovery path. Do not layer a second point engine onto the
page merely to claim the migration is complete.

The focused regression contract is
`node --test RAILS/master/test/face_stipple.test.mjs`. Browser acceptance remains
open until the default face, `?stipple=0`, and `?playground=1` have been captured
at narrow and wide viewports with console output, point/FPS evidence and reduced
motion enabled and disabled. The source test and a mocked shader test are not a
substitute for GPU/browser evidence.

Research references:
- Three.js `Points` and `BufferGeometry` describe the point-cloud primitives
  and GPU-backed attribute buffers:
  https://threejs.org/docs/pages/Points
  https://threejs.org/docs/pages/BufferGeometry
- MDN WebGL best practices cover hardware-dependent point-size limits, resource
  budgets and batching:
  https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices
- Kerbl et al., *3D Gaussian Splatting for Real-Time Radiance Field Rendering*,
  describes anisotropic Gaussian primitives and visibility-aware splatting:
  https://ar5iv.labs.arxiv.org/html/2308.04079
- Design-token exchange and contextual resolution are covered by the Design
  Tokens Community Group's 2025.10 reports; these are Community Group reports,
  not W3C Recommendations:
  https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/
  https://www.w3.org/community/reports/design-tokens/CG-FINAL-resolver-20251028/

## Current landed foundation

- one executable Ruby face contract
- one canonical browser FaceState
- one layered FaceWorld
- one repository topology
- one deterministic splat/point field
- bounded event pulses
- camera/parallax constraints from the contract
- explicit desktop/mobile point budgets
- explicit DPR budget
- browser transcript aligned with terminal scrollback
- monospaced MASTER web typography
- non-empty CLI results preserved when the presenter returns an empty string

## Distant-human morphology

The face uses `MASTER/data/laws.yml#tokens.face_interface.spatial.morphology` as its
single morphology contract. This is deliberately speculative: current evidence supports
long-run trends in Homo toward greater cranial globularity and reduced facial robusticity,
and softer diets are associated with more gracile masticatory architecture, but science
does not provide a reliable blueprint for what humans will look like thousands or
millions of years from now. Spaceflight adds real craniofacial and ocular adaptation
problems, not a settled future phenotype.

The present design projects those measured directions conservatively: a fuller and
higher neurocranial vault, reduced lower-face projection, a more vertical face, a lighter
masticatory architecture, a restrained brow and slightly finer facial projection. The nose
is not treated as a single future-human template: contemporary research links parts of
nasal and mid-facial form to temperature and humidity, so the contract deliberately marks
the profile as climate-neutral rather than inventing a universal climate phenotype. Seeded
asymmetry preserves ordinary human irregularity instead of a polished synthetic mask.

The redesign is informed by the 2026 Hubbe/Harvati study, which finds that Homo shows
long-run cranial expansion and facial reduction but that neutral evolution and stasis
often fit the data better than a simple directional-selection story. Climate studies
likewise show real associations between nasal/mid-facial morphology and temperature and
humidity, without implying a single endpoint for future humans.

References:
- Hubbe & Harvati, “Evolutionary drivers of encephalization and facial reduction in the
  genus Homo”, Nature Communications, 2026-07-06:
  https://doi.org/10.1038/s41467-026-74739-w
- Zaidi et al., “Investigating the case of human nose shape and climate adaptation”,
  PLOS Genetics, 2017:
  https://doi.org/10.1371/journal.pgen.1006616
- García-Martínez et al., “Respiratory adaptation to climate in modern humans and Upper
  Palaeolithic individuals”, Scientific Reports, 2021:
  https://doi.org/10.1038/s41598-021-86830-x

The interface layer remains subordinate to the human morphology so the face reads as a
future person first and a computational being second.

### Stipple point-size hierarchy

The stipple shader now combines the existing canonical sample-bias attribute with camera-space depth attenuation, then bounds the requested point size to 1–1.5 pixels. All sizing values live at `MASTER/data/tokens.yml#tokens.face_interface.stipple.point_size` and arrive in the browser through `MASTER_FACE_CONTRACT`; the shader consumes them as uniforms rather than owning a duplicate tuning table. The five-unit reference depth corresponds approximately to the canonical face camera distance; the GPU may clamp point sizes further. The face identity remains carried by sparse contours and voids, not by simply enlarging every point.

Stipple motion now honors all three existing reduced-motion signals: the semantic face-state bit, the document accessibility projection (`data-reduced-motion="1"`), and the operating-system `prefers-reduced-motion` preference. When any is active, its shader clock is held at zero and ripple/turbulence are disabled while the still-state profile remains. `FaceState.reducedMotion()` is the canonical resolver for the semantic bit, document projection and OS preference; the sparse field, stipple adapter and FaceWorld delegate to it when available and retain a compatibility fallback for older shells.

The shared `FaceState.renderBudget()` also classifies coarse-pointer devices as constrained even when their viewport is wider than the phone breakpoint; the sparse gravitational field uses the same coarse-pointer signal for its own particle ceiling. Its motion update now observes the same face-state, document and OS reduced-motion signals, so the sparse layer no longer continues its background drift when only the document-level preference is active.

Stipple scene discovery follows a container’s point children instead of requiring the parent object to have the exact `type === "Object3D"` label. This admits ordinary Three.js `Group` containers while keeping the overlay attached beside an existing point layer. These are compatibility safeguards, not proof of successful context recovery or a completed raw-WebGL migration.

The primary face loop now routes animation decisions through the same reduced-motion resolver. The OS or page-level preference overrides a manual `full`/`crt` selection with the effective `battery` profile, while the chosen profile remains saved and is restored when the preference clears. Motion checks cover the star accent, shake, awareness, breathing, phosphor decay, adaptive render scaling and the double-tap profile cycle. The extracted particle adapter suppresses audio-driven and emotional particle spawns under reduced motion; phosphor trail capture is skipped; and the micro-interaction module no longer introduces a sinusoidal eye scan or duplicate timed breathing when reduced motion is enabled.

`face.modules.bundle.js` has been refreshed from the current side-effect-only modules in `face_modules_entry.js`, with a source-set SHA-256 that matches those source files. `script/build_face_modules.sh` now prefers pinned esbuild output but has a deterministic source-assembly fallback for offline OpenBSD hosts; that fallback reproduces the committed bundle from the entry’s declared import order. The script itself was not executable from this connected session, so run `rake assets:build_face_modules_bundle` on the target checkout and verify its actual exit status before release.
The renderer adapter now exposes a bounded diagnostic snapshot through `MASTER_FACE_STIPPLE.snapshot()`: enabled/installed/visible state, context state, semantic mode, point count and ceiling, renderer-call count, a rolling 60-sample render-call interval window (mean, median, p95 and approximate calls per second), and relevant shader uniforms. These intervals describe JavaScript render-call cadence, not GPU completion time or a validated FPS measurement. The opt-in `?playground=1` console includes an accessible refresh control for inspecting that snapshot. Its state selector derives from `MASTER_FACE_CONTRACT.state.modes` (with the same nine-state fallback for older shells) and routes changes through `MASTER_FACE_STATE.setMode()` when available, so the developer panel does not introduce a second state vocabulary or mutate the renderer as its primary state authority. Visibility and WebGL context events suppress the additive overlay while unavailable; `uninstall()` restores the wrapped render method when it still owns it, detaches the overlay and disposes its geometry/material.

These source changes do not stop the underlying face renderer, prove WebGL context restoration on a real device, or replace the separately specified raw-WebGL renderer migration. Browser/GPU verification remains required. The regression tests now cover the reduced-motion sources, depth-aware size bound, diagnostics surface and lifecycle contract, but the repository Node runner has not yet been executed.
