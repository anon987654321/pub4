# frozen_string_literal: true

# What a photograph can be asked for, in words a diffusion model acts on.
#
# Every vocabulary, pool and composer lives here rather than in preprompt.rb,
# because preprompt.rb reaches into MASTER for its Replicate client and lora
# composes prompts on a rented GPU that has none of that loaded. Nothing in this
# file makes a request, reads a credential or requires a gem.

# Structured fields compose onto the free-text --prompt. The docs called an
# unrecognised value "a no-op rather than a crash" -- but compile_prompt
# looks the key up and .compacts the nil away, so `--stock portra400` produced a
# prompt with no film stock in it, silently, after paying for the generation and
# waiting for it. A no-op is the worst of the three options here: a crash costs
# you nothing and tells you what you meant, and a guess at least renders. See
# resolve_vocab, which normalises spelling and then refuses what it cannot place.
STOCK_VOCAB = {
  # colour negative
  "portra" => "Kodak Portra 400 color negative scan, fine grain, gentle highlight rolloff",
  "portra800" => "Kodak Portra 800 color negative, warmer grain, low-light latitude",
  "gold" => "Kodak Gold 200 warm consumer color, soft contrast",
  "ultramax" => "Kodak UltraMax 400 consumer negative, punchy saturation, everyday snapshot color",
  "ektar" => "Kodak Ektar 100, saturated fine-grain negative, vivid reds",
  "fuji400h" => "Fujifilm Pro 400H, cool pastel palette, gentle greens and soft skin",
  "superia" => "Fujifilm Superia 400, green-leaning consumer color, visible grain",
  "vista" => "Agfa Vista 200, warm mid-contrast consumer negative",
  # colour reversal
  "provia" => "Fujifilm Provia 100F, neutral saturated color, clean shadows",
  "velvia" => "Fujifilm Velvia 50 reversal, extreme saturation, deep contrast, no highlight latitude",
  "ektachrome" => "Kodak Ektachrome E100 slide film, clean neutral color, crisp shadows",
  "kodachrome" => "Kodachrome 64, dense reds, dark saturated shadows, archival slide look",
  # tungsten / cine
  "cinestill" => "CineStill 800T tungsten-balanced, halation around highlights",
  "vision3" => "Kodak Vision3 500T motion picture negative, wide latitude, cinema grade",
  # black and white
  "trix" => "Kodak Tri-X 400 black and white, silver-rich contrast, visible grain",
  "hp5" => "Ilford HP5 Plus 400 black and white, forgiving latitude, classic reportage grain",
  "fp4" => "Ilford FP4 Plus 125 black and white, fine grain, long tonal scale",
  "delta3200" => "Ilford Delta 3200 black and white, coarse grain, low-light available darkness",
  "panf" => "Ilford Pan F Plus 50 black and white, extremely fine grain, glassy midtones",
  # instant / process
  "polaroid" => "Polaroid SX-70 instant film, soft focus falloff, milky highlights, pastel cast",
  "instax" => "Fujifilm Instax instant print, bright flash falloff, small-format softness",
  "crossprocessed" => "cross-processed E-6 in C-41 chemistry, shifted cyan shadows, blown contrast",
  "expired" => "expired film stock, colour crossover, unpredictable magenta shift, fogged shadows",
}.freeze

LENS_VOCAB = {
  "24mm" => "24mm wide lens, strong perspective, foreground close and background deep",
  "28mm" => "28mm reportage lens, environmental context without visible distortion",
  "35mm" => "35mm lens, moderate depth of field, slight environmental context",
  "50mm" => "50mm lens, natural perspective, shallow depth of field",
  "85mm" => "85mm portrait lens, compressed background, creamy bokeh",
  "105mm" => "105mm short telephoto, flattened features, isolated subject",
  "135mm" => "135mm telephoto, heavy compression, background reduced to tone",
  "macro" => "macro lens, extreme close focus, paper-thin depth of field",
  "tilt_shift" => "tilt-shift lens, plane of focus deliberately skewed across the frame",
  "anamorphic" => "anamorphic lens, oval bokeh, horizontal blue flare, 2.39:1 character",
  "petzval" => "Petzval lens, swirling background bokeh, sharp centre falling off hard to the edges",
  "large_format" => "4x5 large-format view camera, immense detail, shallow plane, gentle falloff",
  "medium_format" => "medium-format Hasselblad look, high resolution tonal smoothness",
  "soft_focus" => "soft-focus portrait lens, halated highlights, detail preserved under the glow",
}.freeze

CAMERA_HEIGHT_VOCAB = {
  "ground" => "camera on the ground looking up, subject towering",
  "low" => "low camera angle looking slightly up",
  "hip" => "hip-height camera, candid unposed viewpoint",
  "eye" => "eye-level camera height",
  "high" => "elevated camera angle looking slightly down",
  "overhead" => "overhead camera angle",
  "birds_eye" => "bird's-eye view straight down, subject flattened into pattern",
}.freeze

DISTANCE_VOCAB = {
  "macro" => "extreme macro detail, a fragment of the subject filling the frame",
  "closeup" => "tight close-up crop, face fills frame",
  "portrait" => "head-and-shoulders portrait crop",
  "half" => "half-body framing",
  "three_quarter" => "three-quarter body framing, knees up",
  "full" => "full-body framing",
  "wide" => "wide environmental framing, subject small in frame",
  "establishing" => "distant establishing shot, subject a figure in a landscape",
}.freeze

LIGHTING_VOCAB = {
  "soft" => "soft diffused key light, low contrast falloff",
  "hard" => "hard direct key light, defined shadow edges",
  "backlit" => "backlit rim light, subject silhouetted against source",
  "window" => "window light from camera-left, natural falloff",
  "golden_hour" => "warm low-angle golden-hour sunlight",
  "rembrandt" => "Rembrandt key light, triangle of light on the shadow-side cheek",
  "split" => "split lighting, one half of the face lit and the other in shadow",
  "butterfly" => "butterfly light from above the lens, symmetrical shadow under the nose",
  "loop" => "loop lighting, small nose shadow angled down the cheek",
  "rim" => "rim light separating the subject from a dark background",
  "practical" => "lit only by practical lamps inside the scene, mixed colour temperature",
  "neon" => "neon sign lighting, saturated magenta and cyan on skin",
  "candlelight" => "candlelight, very warm, falling off within a metre",
  "firelight" => "firelight from below, flickering warm key, deep shadow above",
  "overcast" => "overcast sky as one enormous softbox, shadowless and even",
  "open_shade" => "open shade, cool ambient fill bounced from the sky",
  "direct_flash" => "direct on-camera flash, hard shadow behind the subject, falloff to black",
  "mixed" => "mixed daylight and tungsten, warm interior against cool window light",
  "projector" => "light thrown by a projector, patterned across the subject",
  "underwater" => "light refracted through water, moving caustics across the subject",
}.freeze

WEATHER_VOCAB = {
  "rain" => "Bergen rain, wet pavement reflections, overcast diffusion",
  "drizzle" => "fine drizzle, everything slightly damp, no visible drops",
  "downpour" => "heavy downpour, rain visible in the air, soaked surfaces",
  "fog" => "coastal fog, desaturated distance, soft contrast",
  "haze" => "atmospheric haze, distance washed pale, contrast falling off with depth",
  "clear" => "clear Nordic sky, crisp daylight",
  "snow" => "winter light off snow, cool color temperature",
  "sleet" => "sleet, half-melted, grey light and wet grey ground",
  "frost" => "hard frost, low sun, long shadows across white ground",
  "wind" => "strong wind, hair and fabric in motion, sharp cold light",
  "storm" => "storm light, dark sky against a lit subject, high contrast",
  "aurora" => "aurora overhead, green light on snow, deep blue ambient",
}.freeze

TIME_OF_DAY_VOCAB = {
  "first_light" => "first light before sunrise, colourless and dim",
  "dawn" => "pale dawn light, low saturation, cool blue shadows",
  "morning" => "clear morning light, long shadows, cool bright air",
  "midday" => "neutral midday light, even exposure",
  "afternoon" => "late afternoon light, warming, shadows lengthening",
  "golden_hour" => "golden-hour warmth, long soft shadows",
  "sunset" => "sunset, the light itself orange, sky brighter than the ground",
  "dusk" => "dusk, sky still bright and the ground already dark",
  "blue_hour" => "blue-hour ambient light, deep shadow tones",
  "night" => "practical night lighting, mixed color temperature",
  "midnight" => "deep night, lit only by what is switched on",
}.freeze

# Camera-to-subject distance, which is a different axis from --distance above.
#
# --distance is the CROP: macro through establishing. This is how far away the
# camera stands, and it is the one that decides whether a face is distorted.
# Focal length does not distort a face; distance does. An 85mm lens flatters
# because filling a frame with a head puts the photographer 2-3 m back, where
# the nose is not meaningfully nearer the sensor than the ears. At 40 cm it is,
# and the nose enlarges while the ears recede. See STUDIO/PHOTOGRAPHY.md.
#
# The two were one field, so there was no way to ask for a head-and-shoulders
# crop taken from three metres — which is the ordinary portrait, and was
# unsayable.
SUBJECT_DISTANCE_VOCAB = {
  "selfie" => "camera at arm's length, roughly 45cm from the face, visible " \
              "wide-angle perspective: nose and forehead enlarged, ears falling away",
  "0.5m" => "camera roughly half a metre from the subject, strong near-far perspective",
  "1m" => "camera about a metre from the subject, mild perspective exaggeration",
  "2m" => "camera about two metres back, natural facial proportion",
  "3m" => "camera about three metres back, compressed facial proportion, ears and " \
          "nose rendered at nearly the same scale, the geometry of an 85mm portrait",
  "5m" => "camera about five metres back, strongly compressed, flattened features, " \
          "the geometry of a 135mm portrait",
  "far" => "camera far from the subject, telephoto compression stacking the planes",
}.freeze

# The thing that has never been available in a photograph.
#
# A selfie's framing and gaze come with a selfie's geometry, because arm length
# fixes the distance. A generated image has no camera in it, so the two can be
# separated: the intimacy and eye contact of a selfie with the facial proportion
# of a portrait taken from three metres. Asked for as one word because it is one
# idea, and because spelling it out every time is how it stops being asked for.
SELFIE_GEOMETRY = "held at arm's length in framing and eye contact but with the " \
  "facial proportions of a portrait made from three metres, no wide-angle " \
  "enlargement of the nose or forehead"

# Which side of the face the key light falls on. Independent of the pattern.
#
# Short lighting keys the side turned AWAY from camera and slims; broad keys the
# near side and widens. Most portraiture wants short, and almost nobody asks for
# it by name.
KEY_SIDE_VOCAB = {
  "short" => "short lighting, key on the side of the face turned away from camera, " \
             "the near cheek falling into shadow, slimming",
  "broad" => "broad lighting, key on the side of the face turned toward camera, " \
             "widening the apparent face",
  "even" => "key light square to the face, both sides equally lit",
}.freeze

# The light source reflected in the eye. Its shape states the modifier, which is
# why a portrait reads as lit rather than rendered — and why AI eyes read as
# wrong when the reflection is a perfect featureless dot.
CATCHLIGHT_VOCAB = {
  "softbox" => "rectangular catchlight high in each eye, the shape of a softbox",
  "beauty_dish" => "round catchlight with a darker centre, the shape of a beauty dish",
  "window" => "large soft rectangular catchlight from a window, filling much of the iris",
  "sun" => "small hard bright catchlight, the sun as a point source",
  "ring" => "continuous ring catchlight encircling the pupil",
  "twin" => "two catchlights, a key and a fill, at ten and two o'clock",
  "none" => "no catchlight, eyes unlit and recessive",
}.freeze

# What a retouched training set removed.
#
# Generated skin is too clean and its specular response uniform, because models
# learn from retouched photography and have no account of subsurface scattering:
# real skin is translucent and light returns from below it, warm and soft. These
# are the positive terms; PLASTIC_SKIN_NEGATIVE below is the other half.
SKIN_VOCAB = {
  "real" => "visible pores and fine vellus hair, uneven skin texture across the face, " \
            "subsurface scattering warming the light through the ears and nostrils",
  "oily" => "an oily T-zone catching specular highlights while the cheeks stay matte, " \
            "asymmetric specular response",
  "dry" => "dry matte skin, fine flaking at the nose and lips, light sitting on the surface",
  "weathered" => "weathered skin, sun damage, broken capillaries, deep expression lines",
  "young" => "smooth young skin that still carries pores and down, not airbrushed",
  "sweat" => "a film of sweat catching hard specular highlights across the forehead and nose",
}.freeze

# Where the plane of focus sits. The eyes lead because they are measured to:
# across 10,000 AVA portraits, four of the five features most correlated with
# rating were sharpness at facial landmarks, the eyes highest
# (ar5iv.labs.arxiv.org/html/1501.07304). A face with soft eyes reads as a
# missed photograph however good the rest is.
FOCUS_VOCAB = {
  "eyes" => "focus on the nearest eye, both eyes critically sharp, background softer than the face",
  "face" => "the face in sharp focus, shallow depth of field",
  "deep" => "deep focus, subject and background both sharp",
  "soft" => "soft overall focus, no plane critically sharp",
}.freeze

# How the frame is arranged, named by what it does for the subject rather than
# by grid. Object emphasis ranks second only to content among rated attributes
# (arxiv.org/pdf/2311.14410), while aesthetic ratings correlate only weakly
# with judged rule-of-thirds placement and not at all with computed placement
# (Amirshahi et al. 2014). So thirds is available and never a default.
COMPOSITION_VOCAB = {
  "isolated" => "subject clearly separated from the background",
  "layered" => "foreground, subject and background in distinct depth layers",
  "clean" => "uncluttered frame edges, nothing competing with the subject",
  "fill_frame" => "subject filling the frame",
  "centered" => "subject centred in the frame",
  "thirds" => "subject placed on a rule-of-thirds line",
}.freeze

# Every structured field, in the order compile_prompt emits them. Keeping the
# list here rather than repeating it in compile_prompt, resolve_vocab and the
# option parser is what makes it possible to add a dimension in one place --
# and what makes vocab-check able to check all of them without being told.
VOCABULARIES = {
  stock: STOCK_VOCAB,
  lens: LENS_VOCAB,
  focus: FOCUS_VOCAB,
  camera_height: CAMERA_HEIGHT_VOCAB,
  distance: DISTANCE_VOCAB,
  composition: COMPOSITION_VOCAB,
  subject_distance: SUBJECT_DISTANCE_VOCAB,
  key_side: KEY_SIDE_VOCAB,
  catchlight: CATCHLIGHT_VOCAB,
  skin: SKIN_VOCAB,
  lighting: LIGHTING_VOCAB,
  weather: WEATHER_VOCAB,
  time_of_day: TIME_OF_DAY_VOCAB,
}.freeze

PLASTIC_SKIN_NEGATIVE = "plastic skin, waxy face, over-smoothed, airbrushed, doll, uncanny, beauty filter, " \
  "heavy makeup, face morph, identity drift, CGI, illustration, anime"
ANTI_BEAUTIFICATION_NEGATIVE = "generic influencer face, overly young face, teenage face, symmetrical idealized " \
  "face, filler lips, filter smoothing"

# Cycled per batch index rather than sampled, so a requested batch fills its
# diversity quota deterministically instead of risking repeats by chance.
#
# It did not fill any such quota. All four pools were read at the same index and
# all four were the same length, so the batch cycled through five tuples and
# nothing else: --batch 20 asked for twenty variations and got each of five
# repeated four times, every time, identically. Five of the six hundred and
# twenty-five combinations these pools describe were reachable at all.
#
# Two changes fix it. The pools are now different lengths -- 7, 6, 8, 9, whose
# least common multiple is 504 -- so the tuple repeats after 504 images rather
# than after 5, twenty-five times past the --batch ceiling; and each pool is
# read at its own stride, coprime with that pool's length, so consecutive
# indices move every field at once instead of marching them in lockstep. A
# batch of 20 now yields 20 distinct combinations. It yielded 5.
EXPRESSION_POOL = [
  "a calm neutral expression", "a slight natural smile", "a direct steady gaze",
  "mid-laugh candid expression", "a thoughtful downward glance",
  "eyes closed, head slightly tilted", "an unguarded expression caught between two others",
].freeze
POSE_POOL = [
  "facing camera directly", "three-quarter turn", "profile turn",
  "looking over one shoulder", "leaning slightly forward", "turning away from the camera",
].freeze
WARDROBE_POOL = [
  "wool coat", "simple knit sweater", "plain white shirt", "denim jacket",
  "dark turtleneck", "oversized raincoat", "linen shirt, sleeves rolled", "heavy fisherman's jumper",
].freeze
BACKGROUND_POOL = [
  "plain studio backdrop", "fjord shoreline", "Bergen street corner", "cafe window",
  "mountain road", "empty car park at night", "wooden dock in rain",
  "stairwell with a single window", "birch woodland",
].freeze
# Coprime with each pool's length, so index * stride visits every entry before
# repeating any. 1 for the first pool: the strides only need to differ from each
# other to break the lockstep, and expression is the field a viewer reads first.
POOL_STRIDES = { expression: 1, pose: 5, wardrobe: 3, background: 4 }.freeze

# Look a value up in one vocabulary, or say so and stop.
#
# Spelling is normalised first, because the one thing worse than rejecting
# "golden-hour" is rejecting it when the table plainly contains golden_hour and
# the option parser's own flag is spelled --time-of-day with hyphens. Case,
# hyphens, spaces and surrounding whitespace are all noise here. What is left
# after that either names an entry or is a mistake, and a mistake is worth a
# line of output and an exit rather than an image that quietly lacks the thing
# it was asked for.
def resolve_vocab(field, value)
  return nil if value.nil?

  table = VOCABULARIES.fetch(field)
  key = value.to_s.strip.downcase.tr("- ", "__")
  return table[key] if table.key?(key)

  flag = "--#{field.to_s.tr('_', '-')}"
  abort "warn: unknown #{flag} #{value.inspect}\n       known: #{table.keys.join(', ')}"
end

def compile_prompt(base_prompt, options)
  segments = [base_prompt]
  VOCABULARIES.each_key { |field| segments << resolve_vocab(field, options[field]) }
  segments << SELFIE_GEOMETRY if options[:selfie_geometry]
  segments.compact.join(", ")
end

# The one diversity field a viewer who cannot see the image needs told: where
# the subject is. Expression, pose and wardrobe are describable only by looking.
def batch_background(index, batch_size)
  return nil if batch_size <= 1

  BACKGROUND_POOL[(index * POOL_STRIDES[:background]) % BACKGROUND_POOL.length]
end

def diversify(prompt, index, batch_size)
  return prompt if batch_size <= 1

  parts = [
    EXPRESSION_POOL[(index * POOL_STRIDES[:expression]) % EXPRESSION_POOL.length],
    POSE_POOL[(index * POOL_STRIDES[:pose]) % POSE_POOL.length],
    WARDROBE_POOL[(index * POOL_STRIDES[:wardrobe]) % WARDROBE_POOL.length],
    BACKGROUND_POOL[(index * POOL_STRIDES[:background]) % BACKGROUND_POOL.length],
  ]
  "#{prompt}, #{parts.join(', ')}"
end

# Vocabulary that contradicts itself. Not fatal — a neon sign at midday is a
# real photograph, and so is candlelight in an afternoon interior — but two
# fields describing an incompatible picture is far more often a mistake than an
# intention, and the model resolves it by picking one and ignoring the other
# without saying which.
VOCAB_CONFLICTS = [
  [:lighting, %w[golden_hour], :time_of_day, %w[first_light dawn midday night midnight blue_hour]],
  [:lighting, %w[candlelight firelight neon practical], :time_of_day, %w[morning midday afternoon]],
  [:lighting, %w[overcast open_shade], :weather, %w[clear]],
  [:lighting, %w[hard direct_flash], :weather, %w[fog haze downpour]],
  [:lighting, %w[window golden_hour rembrandt split butterfly loop], :time_of_day, %w[midnight]],
  [:weather, %w[snow frost aurora], :time_of_day, %w[golden_hour]],
  [:focus, %w[eyes face deep], :lens, %w[soft_focus]],
  [:focus, %w[deep], :lens, %w[macro large_format]],
].freeze

# Words that ask for the opposite of a photograph, or for the failure itself.
#
# The boosters raised aesthetic scores on Stable Diffusion by pulling the
# picture toward concept art: an optimiser searching for better prompts
# appended "artstation" and "8k" (ar5iv.labs.arxiv.org/html/2212.09611), and a
# crowd-driven search settled on "concept art, octane render, trending on
# artstation" (ar5iv.labs.arxiv.org/html/2209.11711). "Flawless" and its kin
# name the retouched skin this vocabulary exists to avoid. Warned rather than
# stripped, because the prompt is the caller's.
BACKFIRING_WORDS = {
  "8k" => "pulls the picture toward rendered concept art",
  "4k" => "pulls the picture toward rendered concept art",
  "masterpiece" => "pulls the picture toward illustration",
  "best quality" => "pulls the picture toward illustration",
  "artstation" => "names a concept-art site, and the picture follows it there",
  "octane render" => "names a 3D renderer, so the picture reads as rendered",
  "unreal engine" => "names a game engine, so the picture reads as rendered",
  "hyperrealistic" => "reads as illustration imitating a photograph",
  "flawless" => "asks for the retouched, poreless skin that marks a generated face",
  "poreless" => "asks for the retouched, poreless skin that marks a generated face",
  "airbrushed" => "asks for the retouched, poreless skin that marks a generated face",
}.freeze

def backfiring_words(prompt)
  text = prompt.to_s.downcase
  BACKFIRING_WORDS.select { |word, _| text.match?(/(?<![\w-])#{Regexp.escape(word)}(?![\w-])/) }
end

# CLIP's text encoder takes 77 tokens and discards the rest without saying so.
# On the SD-family lane that loses a long prompt's tail, which is where the film
# stock and the focal length are. FLUX.1 reads CLIP only as a pooled vector and
# carries the whole prompt through T5 at up to 512 tokens
# (black-forest-labs/flux, src/flux/util.py), so there the tail still arrives.
# The ceiling stays 77 because a sitting has to render on either lane.
#
# This is an approximation of BPE, not BPE: roughly one token per word plus one
# per punctuation mark, which runs slightly high on ordinary English. Erring high
# is the right direction for a ceiling. The 12 training prompts measured 39-48
# under it and none were truncated.
TOKEN_LIMIT = 77

def approximate_tokens(prompt)
  prompt.scan(/[\w'-]+|[[:punct:]]/).length + 2 # +2 for CLIP's start and end markers
end

# A sitting — scene, key, distance, lens, stock — as the prompt a subject LoRA
# renders.
#
# The order is deliberate: who, then what they look like, then where they are,
# then how it is lit, then how it was shot. CLIP weights earlier tokens more
# heavily, so identity comes before scenery and scenery before equipment.
def sitting_prompt(sitting, trigger:, descriptor:)
  [trigger,
   descriptor,
   sitting.fetch("scene"),
   "key light #{sitting.fetch('key')}",
   "#{sitting.fetch('distance')} from camera",
   sitting.fetch("lens"),
   sitting["focus"],
   sitting.fetch("stock")].compact.join(", ")
end

# Sittings drawn from the vocabularies rather than written by hand.
#
# lora's shoots.yml is fifty sittings somebody composed, and it stays the record.
# A scenario has the same schema, filled from the pools and tables above, so a
# subject renders in more situations than anyone wrote down and each one still
# names a real light, a lens and a distance.
#
# Numbered, not sampled. Scenario 7 is the same sitting on every run and every
# machine, because a prompt that drifts between runs makes two takes
# incomparable. Each field is read at its own stride, coprime with its pool, as
# diversify reads the batch pools.
#
# Distances start at two metres. Closer than that the nose enlarges and the ears
# fall away, and a likeness is judged on exactly that geometry.
SCENARIO_LENSES = %w[50mm 85mm 105mm 135mm].freeze
# Every drawn sitting asks for sharp eyes, the feature portrait ratings follow
# most closely; see FOCUS_VOCAB. Written sittings keep their own wording.
SCENARIO_FOCUS = "sharp focus on the nearest eye"
SCENARIO_DISTANCES = %w[2m 3m 5m].freeze
SCENARIO_FIELDS = {
  expression: [EXPRESSION_POOL, POOL_STRIDES.fetch(:expression)],
  pose: [POSE_POOL, POOL_STRIDES.fetch(:pose)],
  wardrobe: [WARDROBE_POOL, POOL_STRIDES.fetch(:wardrobe)],
  background: [BACKGROUND_POOL, POOL_STRIDES.fetch(:background)],
  lighting: [LIGHTING_VOCAB.keys, 3],
  distance: [SCENARIO_DISTANCES, 2],
  lens: [SCENARIO_LENSES, 3],
  stock: [STOCK_VOCAB.keys, 5],
}.freeze

# Lights a place cannot have. A car park at night has no sun in it and a dock in
# rain has no hard sunlight on it; asked for both, the model keeps one and drops
# the other without saying which. The light gives way, because the place is the
# half a viewer reads first.
BACKGROUND_LIGHT_CONFLICTS = {
  "empty car park at night" => %w[window golden_hour overcast open_shade backlit underwater],
  "wooden dock in rain" => %w[golden_hour hard backlit projector underwater],
  "stairwell with a single window" => %w[golden_hour overcast open_shade underwater],
  "cafe window" => %w[firelight underwater],
  "plain studio backdrop" => %w[golden_hour overcast open_shade window underwater],
  "mountain road" => %w[candlelight firelight practical neon underwater projector],
  "fjord shoreline" => %w[candlelight practical neon projector],
  "birch woodland" => %w[neon projector underwater],
  "Bergen street corner" => %w[candlelight firelight underwater],
}.freeze

def scenario_pick(field, index)
  pool, stride = SCENARIO_FIELDS.fetch(field)
  pool[(index * stride) % pool.length]
end

# The drawn light, or the nearest one the background can hold. Still a function
# of the number alone, so the sitting stays the same on every run.
#
# A refused light steps by REFUSAL_STRIDE rather than to its neighbour in the
# pool. The next scenario draws three places on, so stepping one at a time
# reaches that light after three refusals and two sittings in a row share it.
# Seven steps lands there only after nine, and no background refuses that many.
REFUSAL_STRIDE = 7

def scenario_light(background, index)
  pool, stride = SCENARIO_FIELDS.fetch(:lighting)
  refused = BACKGROUND_LIGHT_CONFLICTS.fetch(background, [])
  start = index * stride
  steps = (0...pool.length).map { |step| pool[(start + step * REFUSAL_STRIDE) % pool.length] }
  steps.find { |light| !refused.include?(light) }
end

# What vocab-check asks of the scenario tables: every stride reaches its whole
# pool, and every conflict names a background and a light that exist, or the
# conflict never fires.
def scenario_problems(conflicts: BACKGROUND_LIGHT_CONFLICTS)
  problems = SCENARIO_FIELDS.filter_map do |field, (pool, stride)|
    "scenario #{field} stride #{stride} cannot visit all #{pool.length} entries" if stride.gcd(pool.length) != 1
  end
  conflicts.each { |background, lights| problems.concat(conflict_problems(background, lights)) }
  (SCENARIO_LENSES - LENS_VOCAB.keys).each { |lens| problems << "scenario lens #{lens} is not in LENS_VOCAB" }
  (SCENARIO_DISTANCES - SUBJECT_DISTANCE_VOCAB.keys).each do |distance|
    problems << "scenario distance #{distance} is not in SUBJECT_DISTANCE_VOCAB"
  end
  problems
end

def conflict_problems(background, lights)
  problems = (lights - LIGHTING_VOCAB.keys).map { |light| "a conflict names an unknown light #{light.inspect}" }
  problems << "a conflict names an unknown background #{background.inspect}" unless BACKGROUND_POOL.include?(background)
  problems << "#{background.inspect} refuses every light" if (LIGHTING_VOCAB.keys - lights).empty?
  problems
end

# The film stock by its name alone. Each description opens with the name and
# spends the rest on how it looks, which a sitting has no token budget for.
def scenario_sitting(number)
  pick = SCENARIO_FIELDS.keys.to_h { |field| [field, scenario_pick(field, number - 1)] }
  pick[:lighting] = scenario_light(pick.fetch(:background), number - 1)
  {
    "n" => number,
    "side" => "Scenarios",
    "title" => "Scenario #{number}",
    "scene" => pick.values_at(:expression, :pose, :wardrobe, :background).join(", "),
    "key" => pick.fetch(:lighting).tr("_", " "),
    "distance" => pick.fetch(:distance).sub(/m\z/, " m"),
    "lens" => pick.fetch(:lens),
    "focus" => SCENARIO_FOCUS,
    "stock" => STOCK_VOCAB.fetch(pick.fetch(:stock)).split(",").first,
  }
end
