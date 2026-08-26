# 168 ways to get there

Proposals against three stated goals, 2026-08-25:

1. **repligen** composes long chains of radically different models, toward
   visuals unlike anything seen before — new cinematography, new colour.
2. **lora** produces stunning selfies that are actually good photography, on
   FLUX 2 or whatever is current.
3. **postpro** is the house filter on every photo and video, emulates real
   analog, and rescues what can be rescued.

Grounded in `PHOTOGRAPHY.md` (the four layers), the Replicate survey in
`repligen/README.md` and `lora/README.md`, and what the three tools verifiably
do today. Marked **[cheap]** when it is an afternoon, **[deep]** when it is a
project, **[yours]** when it is a decision rather than work.

---

## A. The chain engine — repligen's missing spine (1–24)

Today repligen is single-shot: one model, optionally one `--postpro` handoff.
Everything in §B depends on this existing first.

1. A `Chain` object: an ordered list of stages, each `{model, inputs, inherits}`. **[deep]**
2. Declarative chains as YAML under `repligen/chains/`, so a look is a file, not a shell history. **[deep]**
3. `Stage#inherits` — name what carries forward: `:image`, `:seed`, `:palette`, `:references`, `:mask`, `:depth`.
4. Content-addressed intermediates, so re-running a chain re-uses stages whose inputs did not change. **[deep]**
5. `--from STAGE` to resume a chain at any stage against a cached intermediate. **[cheap]**
6. `--until STAGE` to stop early and look.
7. Per-stage provenance in the sidecar: model, version, input hash, seed, duration, cost.
8. Chain-level cost estimate before running, from each model's published price.
9. A dry-run that validates every stage's `input_keys` against `MODEL_CAPABILITIES` and refuses before spending anything. **[cheap]**
10. Refuse a chain whose stage N+1 needs an input stage N cannot produce — the same refusal discipline the table already has.
11. Fan-out: one stage, N seeds, producing a contact sheet rather than one frame.
12. Fan-in: several intermediates as the multi-reference input to one later stage.
13. Branch and compare: two variants of one stage, both carried forward, diffed at the end.
14. A `--contact-sheet` output that tiles every stage of the chain in order, so you can see *where* a look was won or lost.
15. Retry-with-jitter on a provider 5xx, distinct from a refusal — a timeout is not a rejection.
16. Per-stage timeout, since a 30 s model and a 4 min model in one chain should not share a bound.
17. Cache the provider schema per model+version so a chain does not re-fetch it per stage.
18. Chain linting: warn when two adjacent stages both do global colour, which is usually a mistake.
19. Warn when a chain has no structure-preserving stage — pure generation chains drift (see §B).
20. `repligen chains --list` with a one-line description of each, generated from the YAML.
21. Named chains callable as one word: `--chain nordic_winter`.
22. Chain composition: a chain that includes another chain as a stage. **[deep]**
23. A seed policy per chain — pinned, derived-from-previous, or free — because reproducibility and exploration want different things.
24. Record the exact chain in every output's sidecar, so a good frame can be re-run a year later. **[deep]**

## B. Chains worth trying — the vocabulary (25–46)

The FLUX 2 family is decomposed by *what it preserves*, which is what makes
chaining possible: each stage can change one thing while holding another.

25. **Structure ladder**: generate → `flux-depth-pro` retexture → `flux-canny-pro` restyle. Geometry survives two complete surface changes.
26. **Consistency spine**: every stage after the first takes the previous outputs as multi-reference (8 on `flux-2-max`/`pro`, 10 on `flux-2-flex`), so the chain accumulates instead of wandering. This is the single most important pattern here.
27. **Vector detour**: raster → Recraft V4 SVG → transform the vector mathematically → rasterise → continue. A resolution-independent stage inside a raster chain is genuinely unusual and nothing else on the list produces its artefacts.
28. **Demonstration stage**: Seedream 5 takes an example rather than a prompt — hand it a frame you already love as the instruction.
29. **Cross-vendor deliberately**: one vendor's family shares a look; the unfamiliar output is at the seams between BFL, ByteDance, Google, OpenAI, Krea.
30. **Inpaint-as-composition**: `flux-fill-pro` to extend a frame outward repeatedly, building a scene larger than any single generation.
31. **Depth-locked relight**: hold depth, change only the light description, several times — a lighting contact sheet of one subject.
32. **Palette transplant**: generate the subject in one chain, the palette in another, marry them via multi-reference.
33. **Typography stage**: `flux-2-flex` for any frame carrying text; the others smear it.
34. **Sub-second探索 with `flux-2-klein-4b`**, then re-run the winning prompt through `flux-2-max` — explore cheap, commit expensive.
35. **Grain-aware ordering**: any upscale must come *before* postpro, or the grade's grain gets resampled into mush.
36. **Two-pass colour**: neutral generation, grade in postpro, then a light generative pass to re-integrate — avoids the model's idea of "cinematic teal".
37. **Deliberate degradation stage**: generate clean, destroy on purpose, regenerate from the wreck. Chains that only improve converge on the same look.
38. **Optical-flaw injection between stages** — a real lens' coma, astigmatism, field curvature — so the *next* model sees a photograph rather than a render.
39. **Reference laundering**: run a reference through a heavy style stage before using it as a consistency reference, so identity carries but look does not.
40. **Long chains on purpose**: 8–12 stages, most of them small. The stated goal is unprecedented output, and that lives past the length people normally stop at.
41. **Same chain, different order** — record both. Order is a parameter and almost nobody treats it as one.
42. **A chain that ends in `flux-kontext-max`** for a final text-instructed correction, rather than re-rolling.
43. **Chain a video model in**: FLUX 3 generates audio and video together — a still chain that terminates in motion.
44. **Stills-from-video**: generate motion, extract the best frame, continue the still chain from it. Motion models resolve gesture differently.
45. **Human-in-the-loop stage**: a chain that pauses, shows a contact sheet, and takes a pick before continuing. **[deep]**
46. **A registry of chains that failed**, with why. Same discipline as `MASTER/data/proposals.yml` — this is the thing that stops a year of rediscovering the same dead ends.

## C. Geometry — the selfie inversion (47–58)

`PHOTOGRAPHY.md` §1: distance distorts, not focal length. A selfie is fixed at
the distortion range by arm length. A generated image has no camera, so this is
the one place the physical trade-off can be refused.

47. Prompt the **camera-to-subject distance in metres**, not the focal length. The distance is the cause.
48. Ask for the geometry of 2.5–3.5 m with the framing and gaze of a selfie — never available together before.
49. Build a vocabulary term for it (`selfie_geometry: portrait_distance`) so it is one word, not a paragraph. **[cheap]**
50. Never put the bare word "selfie" in a prompt unqualified — the model reproduces the distortion it learned from millions of real ones.
51. A test set of the same subject at stated 0.4 / 0.8 / 1.5 / 3 / 5 m, to see what the model actually does with distance. **[cheap]**
52. Measure nose-to-ear ratio across that set — a numeric handle on whether the instruction landed.
53. Vocabulary for crop separately from distance: head-and-shoulders, chest-up, half, full.
54. Refuse contradictory pairs (`0.4 m` + `flat facial compression`) the way unsupported params are refused.
55. Frame edge behaviour: a real 85mm at 3 m has a specific falloff and edge rendering; ask for it.
56. Include the arm, or don't, as an explicit choice — the visual grammar of a selfie is partly the arm, and it can be kept while the geometry is not.
57. Test whether multi-reference carries *geometry* or only identity. Nobody documents this and it decides how chains must be ordered.
58. Document the finding either way in `PHOTOGRAPHY.md`. **[cheap]**

## D. Light (59–71)

59. Name the pattern explicitly: butterfly, loop, Rembrandt, split.
60. Name short vs broad — most people want short, and almost nobody asks.
61. Specify the catchlight **shape**, since it states the modifier: round = beauty dish, rectangle = softbox, small hard dot = bare flash or sun.
62. Specify catchlight position (10 or 2 o'clock).
63. Key-to-fill ratio as a number, not "dramatic".
64. Practical light in frame — a window, a lamp — gives the model an anchor for direction.
65. Motivated light: state where it comes from, so shadow direction stays consistent across a chain.
66. Colour temperature per source, and mixed-temperature setups (tungsten key, daylight fill) which read as real because they usually are.
67. A lighting contact sheet: one subject, all four patterns, both short and broad. **[cheap]**
68. Negative fill as a term — what is *absent* shapes a face as much as what is present.
69. Time-of-day and latitude rather than "golden hour" — Bergen's winter sun is a specific low angle.
70. Depth-locked relighting chain (see 31) so light is a variable and identity is not.
71. Cross-check the rendered pattern against the named one, and log the miss rate. **[deep]**

## E. Expression and moment (72–81)

72. Select dataset sources for genuine expression — a LoRA trained on held smiles generates held smiles.
73. Prompt the moment *after* the laugh, not the laugh — that is where practice says the real expression sits.
74. Micro-expression vocabulary: asymmetric mouth, eye crinkle, a breath held.
75. Ask for the gaze relationship explicitly — at lens, past lens, away, at something in frame.
76. Permit imperfection by name: lines, asymmetry, a scar. Compelling portraits are frequently the least corrected.
77. Avoid "smiling" as a term; it collapses to the same performed shape.
78. Vocabulary for the body: shoulders turned, chin dropped, weight on one foot.
79. Hands, deliberately — the second-hardest thing after eyes and the second most telling.
80. A/B a prompt with and without an expression clause; the gap is the value of the clause. **[cheap]**
81. Keep an "expression that worked" file with the exact wording. **[cheap]**

## F. Defeating the uncanny (82–98)

`PHOTOGRAPHY.md` §4: skin too clean, specular highlights uniform, eye
reflections too perfect — because training data is retouched and the model has
no account of subsurface scattering.

82. Never ask for "flawless skin". It is the failure, named.
83. Ask for pores, vellus hair, uneven texture across the face.
84. Ask for asymmetric specular response — an oily T-zone and matte cheeks.
85. Subsurface warmth explicitly: light through the ear, the nostril, the fingertip.
86. Ask for one unflattering true thing — this is what a retouched training set removed.
87. Postpro grain as the standard antidote to plastic skin (§G).
88. Halation to restore the bleed around a specular highlight that a render lacks.
89. An H&D shoulder so highlights roll rather than clip.
90. Chromatic aberration at frame edges, slightly — renders have none.
91. Vignetting from a real lens, not a symmetric mask.
92. Sensor or film grain that is *chromatic*, not luminance-only.
93. Very slight focus miss — real portraits are rarely perfectly focused on both eyes.
94. Motion at the edges of the frame while the face holds.
95. Dust and a smudge on the front element.
96. Build an **uncanny score**: measure specular uniformity across the face and skin high-frequency energy, and track it per output. **[deep]**
97. Score before and after postpro to prove the grade is doing what §4 claims. **[deep]**
98. Ratchet it — the score may not get worse. This tree already knows how to do that.

## G. Postpro as the house look (99–116)

99. Make it the **default**, not `--postpro` opt-in. This is the stated goal and is currently one flag on one command. **[yours]**
100. A named house preset every surface uses, so output is recognisable as yours. **[yours]**
101. Apply it at the end of every repligen chain automatically, with an opt-out rather than an opt-in.
102. Wire it into the LoRA generation lane, which does not touch it today.
103. Per-subject grade profiles — Ragnhild and Johann do not need the same treatment.
104. Grade *before* any upscale, never after (35).
105. Push/pull processing as a term, since the stack already models push response.
106. Cross-processing and bleach bypass, which are the looks that read as deliberate.
107. Stock-specific halation — cinestill_800t's is the famous one because the remjet is gone.
108. Print stock as a separate stage from negative stock; the pairing is where real film looks live.
109. Expired-film emulation as a first-class preset — shifts, fog, edge effects.
110. A contact-sheet mode: one frame through every stock at once. **[cheap]**
111. Golden-image regression fixtures so a grading change cannot silently alter every past look. **[deep]**
112. Perceptual assertions on those fixtures — ΔE on a skin patch, highlight clipping under 0.5%, mean luminance in range — rather than exact hashes, since some effects contain noise. **[deep]**
113. A `--compare` that writes before/after side by side.
114. Publish the grade's parameters into the output sidecar, so a look is reproducible.
115. LUT export, so the same grade reaches tools outside this tree. **[deep]**
116. A "why did this change" mode that names which effects actually moved pixels — the stack has already found effects that ran and did nothing.

## H. Postpro on video (117–128)

Currently impossible: libvips, and every input glob is `jpg/jpeg/png/webp`.

117. An ffmpeg path beside the vips one — this tree has deep ffmpeg experience in dilla. **[deep]**
118. Reuse dilla's filter-graph knowledge, including the parameter traps already documented there.
119. Per-frame grade with a **temporally stable** grain seed — per-frame random grain boils and is the classic tell. **[deep]**
120. Halation and bloom that are temporally coherent, or highlights crawl.
121. Gate flicker deliberately, as a projector artefact, when it is wanted.
122. Weave and gate-hair as optional period artefacts.
123. Frame-rate and shutter-angle emulation — 180° shutter motion blur is most of what reads as cinema.
124. Telecine and 3:2 pulldown artefacts as an available look.
125. Grade a video by extracting one representative frame, grading it interactively, then applying to all. **[deep]**
126. Performance budget per minute of footage, declared and ratcheted — dilla already learned this lesson.
127. Accept FLUX 3's video output directly as an input, closing the loop with §B.
128. A stills-and-video parity test: the same source frame through both paths must land in the same place. **[deep]**

## I. Rescuing a bad photo — the honest subset (129–140)

From `PHOTOGRAPHY.md`: layer 4 yes, light partly, geometry and expression no.

129. Be explicit in the tool about what it cannot fix. A rescue mode that silently fails at geometry is worse than one that refuses.
130. Auto-detect blown highlights with no data and say so rather than grading around them.
131. Detect and report perspective distortion, so the answer is "reshoot at 3 m" rather than a grade.
132. Recover flat/underexposed digital files — genuinely in reach.
133. Colour-cast removal from mixed lighting — in reach.
134. Add grain to a smooth, noise-reduced phone photo — the single highest-yield rescue, and the same operation as the anti-uncanny fix.
135. Restore roll to highlights that a phone's HDR flattened.
136. Undo over-sharpening halos.
137. Undo phone beauty-mode skin smoothing, by adding texture back.
138. Generative rescue as an explicit *separate* mode — `flux-fill-pro` for a distraction, `flux-2` for a relight — labelled as generated, not graded. **[yours]**
139. A verdict on every rescue: what was fixed, what could not be, what to do differently next time.
140. Never claim a rescue that did not happen — the report is the product.

## J. LoRA on FLUX 2 (141–155)

141. Decide the base generation deliberately: FLUX.1-dev LoRAs are not FLUX 2 adapters. **[yours]**
142. If training, target `black-forest-labs/flux-2-klein-9b-base-lora` — the undistilled base intended for it.
143. Evaluate the reference route first: `flux-2-max` holds a character across a batch from 8 references, with no training at all. **[yours]**
144. The reference route also sidesteps the permanent-public-git problem entirely — references are sent per request and committed nowhere.
145. Use `consistent-character` to bootstrap johann's dataset from 3 images toward 12–18.
146. Curate for the four layers, not for quantity: varied light *pattern*, varied distance, genuine expression.
147. Caption the lighting pattern and the distance, so those become promptable axes rather than baked-in constants.
148. Deliberately include a range of distances, or the LoRA learns one geometry.
149. Hold out a test set and never train on it, so quality is measurable rather than felt.
150. A fixed prompt suite run against every checkpoint, so "better" is comparable. **[cheap]**
151. Score checkpoints with the uncanny metrics from §F.
152. Consent as an executable contract, checked per lane, not a README paragraph. **[yours]**
153. Hashes and a manifest instead of committed images. **[yours]**
154. Secret-leak tests on any generated notebook or config. **[cheap]**
155. Record which base each weight file was trained against — it is not inferable later, and it decides compatibility.

## K. Knowing whether it worked (156–168)

The goal is "unlike anything seen before", which is unmeasurable directly. These
are the proxies that are not.

156. A gallery of everything, with the full chain attached to each frame.
157. Blind A/B against real photographs — the honest test of layer 4. **[cheap]**
158. Track which chains you return to. Revisits are the signal; opinions are not.
159. Novelty proxy: embedding distance from the model's unconditioned output. Far is not automatically good, but near is definitely not new. **[deep]**
160. Palette histograms per chain, to see whether "radically different models" actually produced radically different colour.
161. A wall of failures kept as prominently as successes.
162. Cost per keeper, tracked — it decides how long chains can afford to be.
163. Time-to-first-look, since exploration dies at the wrong latency.
164. A monthly re-survey of the provider catalogue, since today's list is already a generation behind and will be again. `rake repligen:schema_audit` exists for the mechanical half.
165. Version the house look, so past work stays reproducible when it changes.
166. Keep one frame from each era as a reference of where the look has been.
167. Write down what "spectacular" turned out to mean, once there are examples — it will not be what it sounds like now.
168. Decide what is worth showing anyone, which is a different question from all of the above and the only one that finally matters. **[yours]**

---

## Where I would start

Four, in order, because each unblocks the next:

- **§A 1–10**, the chain spine. Nothing in §B is reachable without it, and
  swapping in newer models without it buys a better single shot and no more.
- **§C 47–52**, the selfie inversion. It is cheap, it is testable this
  afternoon, and it is the one advantage in this whole list that exists only
  because the camera is imaginary.
- **§G 99–101**, postpro as default. It is the stated goal, it is a small
  change, and it makes everything downstream consistent.
- **§F 96–98**, the uncanny score. Everything else in §F and §G is an assertion
  until something measures it.

The rest is a menu, not a plan.
