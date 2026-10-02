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

The source of truth is `MASTER/data/rules.yml#design_system.face_interface`.
Ruby reads it through `MASTER/lib/face/contract.rb`. Browser code receives
the same block as `MASTER_FACE_CONTRACT` and keeps dynamic state in
`MASTER_FACE_STATE`.

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
83. Failing gates as broken links.
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
