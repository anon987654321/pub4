#!/usr/bin/env ruby
# frozen_string_literal: true

# Small, non-interactive Replicate image entrypoint. Credentials stay in env/user config.
require "optparse"
require "fileutils"
require "json"
require "time"
require "digest"
require "securerandom"
# ../lib/... resolved correctly at MASTER/tools/repligen/ and has resolved to
# STUDIO/lib/ -- which does not exist -- since the move to STUDIO/, so every
# invocation of this file has aborted on line 12 with a LoadError since
# 687c07a43. There is no ../lib/master_paths anywhere in the repo under any
# prefix; the module lives in MASTER/lib/boot/paths.rb.
require_relative "../../MASTER/lib/io/replicate_client"
require_relative "../../MASTER/lib/io/script_dispatch"
require_relative "../../MASTER/lib/io/analog_capabilities"
require_relative "../../MASTER/lib/boot/paths"
# Shellwords.escape is called in maybe_handoff_postpro. Nothing required it, so
# --postpro reached a NameError instead of a handoff -- the one code path in
# this file that had never run even before the LoadError above made all of them
# unreachable.
require "shellwords"

# Structured fields compose onto the free-text --prompt. An unrecognised value
# used to be documented as "a no-op rather than a crash" -- but compile_prompt
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

# Every structured field, in the order compile_prompt emits them. Keeping the
# list here rather than repeating it in compile_prompt, resolve_vocab and the
# option parser is what makes it possible to add a dimension in one place --
# and what makes vocab-check able to check all of them without being told.
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

VOCABULARIES = {
  stock: STOCK_VOCAB,
  lens: LENS_VOCAB,
  camera_height: CAMERA_HEIGHT_VOCAB,
  distance: DISTANCE_VOCAB,
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

# What each Replicate model actually accepts, checked against the live schemas
# rather than remembered.
#
# stable-diffusion-3.5-large was wrong in all three of its interesting fields.
# Its schema is prompt / aspect_ratio / cfg / image / prompt_strength / steps /
# seed / output_format / output_quality — the guidance knob is `cfg`, not
# `cfg_scale`; the step count is `steps`, not `num_inference_steps`; and there
# is NO negative_prompt at all (SD3 had one, 3.5 dropped it). It was the one
# model in this table declared to accept a negative prompt, so it was the one
# model for which negative_prompt_supported? returned true — meaning the
# POSITIVE_SKIN_GUIDANCE fallback was suppressed, a `negative_prompt` key the
# model does not have was sent, and the provenance sidecar recorded
# negative_prompt_sent: true. Precisely the failure the file's own comments say
# was fixed, surviving in the one entry nobody re-read.
#
# guidance_key / steps_key / their ranges are here because build_input had been
# reading options[:guidance], options[:steps] and options[:cfg_scale] for keys
# no flag could ever set. Three declared capabilities with no way to reach them.
MODEL_CAPABILITIES = {
  "black-forest-labs/flux-1.1-pro" => {
    input_keys: %w[prompt aspect_ratio output_format safety_tolerance seed],
    negative_prompt_key: nil,
  },
  # 4 MP. `raw` is the camera-look toggle BFL added for Ultra: less plastic,
  # more candid. Set automatically when --stock or --lens is on, because those
  # flags are how this file asks for a photograph rather than an illustration.
  "black-forest-labs/flux-1.1-pro-ultra" => {
    input_keys: %w[prompt aspect_ratio output_format safety_tolerance seed raw],
    negative_prompt_key: nil,
  },
  # Text-instructed edit of an existing picture. Requires --image; generate
  # without one is a refusal, not a silent text-to-image fallback.
  "black-forest-labs/flux-kontext-pro" => {
    input_keys: %w[prompt aspect_ratio output_format safety_tolerance seed input_image],
    negative_prompt_key: nil,
  },
  "black-forest-labs/flux-dev" => {
    input_keys: %w[prompt aspect_ratio output_format seed guidance num_inference_steps],
    negative_prompt_key: nil,
    guidance_key: "guidance", guidance_range: (0.0..10.0), guidance_default: 3.0,
    steps_key: "num_inference_steps", steps_range: (1..50), steps_default: 28,
  },
  "black-forest-labs/flux-schnell" => {
    input_keys: %w[prompt aspect_ratio output_format seed num_inference_steps],
    negative_prompt_key: nil,
    # schnell is a 1-4 step model. The same --steps 28 that is right for dev is
    # out of range here, which is why the ceiling is per-model and not global.
    steps_key: "num_inference_steps", steps_range: (1..4), steps_default: 4,
  },
  # FLUX 2, the current generation and the default as of 2026-08-25.
  #
  # `input_images`, PLURAL, and that is the whole reason these entries were
  # worth waiting for rather than guessing. FLUX 2 takes up to eight reference
  # images and holds a character across them, where FLUX 1's editors took a
  # single `input_image`. A guessed singular key would have been refused by the
  # chain validator on every FLUX 2 chain — correctly, and for a reason nobody
  # would have found quickly.
  #
  # Read from Replicate's own documentation rather than from the schema
  # endpoint, which needs a token this machine does not have. `rake
  # repligen:schema_audit` is what confirms them against the provider, and
  # should be the first thing run once a token is present.
  #
  # No safety_tolerance: that was a FLUX 1.1 field and nothing in the FLUX 2
  # documentation carries it. Declaring a key the model does not take is the
  # exact failure MODEL_CAPABILITIES exists to prevent, so it is left out until
  # the audit says otherwise.
  "black-forest-labs/flux-2-max" => {
    input_keys: %w[prompt input_images aspect_ratio output_format output_quality seed],
    negative_prompt_key: nil,
  },
  "black-forest-labs/flux-2-pro" => {
    input_keys: %w[prompt input_images aspect_ratio output_format output_quality seed],
    negative_prompt_key: nil,
  },
  # Typography specialist — clean text, captions, complex layouts — and the
  # widest blend surface at ten references.
  "black-forest-labs/flux-2-flex" => {
    input_keys: %w[prompt input_images aspect_ratio output_format output_quality seed],
    negative_prompt_key: nil,
  },
  # Sub-second. The exploration lane: run a prompt here, then commit the winner
  # to flux-2-max.
  "black-forest-labs/flux-2-klein-4b" => {
    input_keys: %w[prompt input_images aspect_ratio output_format output_quality seed],
    negative_prompt_key: nil,
  },
  "black-forest-labs/flux-2-dev" => {
    input_keys: %w[prompt input_images aspect_ratio output_format output_quality seed],
    negative_prompt_key: nil,
  },
  "stability-ai/stable-diffusion-3.5-large" => {
    input_keys: %w[prompt aspect_ratio output_format seed cfg steps],
    negative_prompt_key: nil,
    guidance_key: "cfg", guidance_range: (0.0..20.0), guidance_default: 3.5,
    steps_key: "steps", steps_range: (1..50), steps_default: 35,
  },
}.freeze
DEFAULT_CAPABILITY = { input_keys: %w[prompt aspect_ratio output_format seed], negative_prompt_key: nil }.freeze

# Sub-second, and the current generation. Explore here, commit to FINAL_MODEL.
PREVIEW_MODEL = "black-forest-labs/flux-2-klein-4b"
# What --final asks for. The flag was parsed into options[:final] and nothing
# ever read it, so `--final` did nothing at all: with REPLIGEN_MODEL set to a
# preview model it silently kept previewing.
#
# Ultra, not Pro: 4 MP and a raw mode that matches the stock/lens vocabulary.
# Cheap one-shots stay on flux-1.1-pro (the default); --final is how one
# image leaves preview and also leaves the 1 MP-class model.
FINAL_MODEL = "black-forest-labs/flux-2-max"

def capability_for(model_id)
  MODEL_CAPABILITIES[model_id] || DEFAULT_CAPABILITY
end

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

def compile_negative_prompt(options)
  return options[:negative] if options[:negative]
  return if options[:no_negative]

  parts = [PLASTIC_SKIN_NEGATIVE]
  parts << ANTI_BEAUTIFICATION_NEGATIVE unless options[:allow_beautify]
  parts.join(", ")
end

# --distance is the field that most directly decides the shape of the frame, and
# it was the field this could not see: inference ran on the raw --prompt before
# compile_prompt had folded anything into it, so `--distance closeup` produced a
# 3:2 editorial crop while the word "close-up" typed into the prompt produced
# 4:5. The structured field and the free text disagreed about which one counted.
# The explicit --aspect-ratio still wins over both.
DISTANCE_ASPECT = {
  "macro" => "1:1", "closeup" => "4:5", "portrait" => "4:5", "half" => "4:5",
  "three_quarter" => "2:3", "full" => "2:3", "wide" => "16:9", "establishing" => "16:9",
}.freeze

def infer_aspect_ratio(prompt, explicit, distance = nil)
  return explicit if explicit

  if distance && (ratio = DISTANCE_ASPECT[distance.to_s.strip.downcase.tr("- ", "__")])
    return ratio
  end

  case prompt
  when /\bportrait\b|\bheadshot\b|\bclose[- ]?up\b/i then "4:5"
  when /\blandscape\b|\bwide\b|\bpanoram/i then "16:9"
  when /\bsquare\b|\bavatar\b/i then "1:1"
  else "3:2" # editorial default
  end
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

# The positive half of the same instruction, for models that have no negative
# prompt at all. Every Flux model is one, including the default -- so on the
# default model the entire anti-plastic-skin defence was assembled, threaded
# through four functions, written into the provenance sidecar as if it had been
# applied, and then dropped on the floor by the input_keys filter in build_input
# without a word. The sidecar was the worst part: it recorded a negative prompt
# that was never sent, so the file that exists to make a generation auditable
# was the thing asserting a constraint the generation never had.
#
# You cannot hand Flux a list of things to avoid; naming them in the prompt
# summons them. What you can do is ask for the opposite in the affirmative,
# which is what a photographer would have written in the first place.
POSITIVE_SKIN_GUIDANCE = "natural skin texture with visible pores and fine lines, unretouched, " \
  "documentary realism, real photographic imperfection"

def negative_prompt_supported?(model_id)
  cap = capability_for(model_id)
  !cap[:negative_prompt_key].nil? && cap[:input_keys].include?(cap[:negative_prompt_key])
end

# A number the model will accept, or a refusal that says what the range is.
#
# Silently clamping is the wrong answer here for the same reason a missing film
# stock was: you asked for 28 steps on a model whose ceiling is 4, paid for the
# generation, and got something you did not ask for with nothing in the output
# saying so.
def model_number(cap, kind, value)
  return nil if value.nil?

  key = cap[:"#{kind}_key"]
  abort "warn: --#{kind == :guidance ? 'guidance' : 'steps'} is not a knob on this model" unless key

  range = cap[:"#{kind}_range"]
  unless range.cover?(value)
    abort "warn: #{key} #{value} is outside this model's range #{range.first}..#{range.last}"
  end
  [key.to_sym, value]
end

# Ultra's raw mode is the camera look. Stock or lens in the request means
# the caller asked for a photograph; --no-raw is how they opt out, --raw
# is how they force it on a model that has the key.
def raw_mode?(options)
  return false if options[:no_raw]
  return true if options[:raw]
  !!(options[:stock] || options[:lens])
end

# Up to eight, because that is what flux-2-max and flux-2-pro accept; flex takes
# ten and klein-4b five, and the model's own schema is what refuses the excess
# rather than a number guessed here. Empty becomes nil so .compact drops the key
# entirely — sending an empty list is not the same as not sending one.
def reference_images(options)
  refs = (Array(options[:references]) + [options[:image]]).compact.uniq
  refs.empty? ? nil : refs.first(8)
end

def build_input(prompt, options, seed:, negative_prompt:)

  cap = capability_for(options[:model])
  full = {
    prompt:,
    aspect_ratio: options[:aspect_ratio],
    output_format: "webp",
    safety_tolerance: 2,
    seed:,
    negative_prompt:,
    raw: raw_mode?(options) || nil,
    input_image: options[:image],
    # FLUX 2 takes references as a LIST, up to eight, and holds a character
    # across them. That is the consistency spine a long chain needs: stage N's
    # outputs become stage N+1's references, so the chain accumulates rather
    # than drifting. --reference may be given more than once; --image still
    # works and counts as the first of them.
    input_images: reference_images(options),
    output_quality: 90,
  }.compact

  [model_number(cap, :guidance, options[:guidance]),
   model_number(cap, :steps, options[:steps])].compact.each { |key, value| full[key] = value }
  if cap[:negative_prompt_key] && full.key?(:negative_prompt)
    full[cap[:negative_prompt_key].to_sym] = full.delete(:negative_prompt)
  end
  full.select { |key, _| cap[:input_keys].include?(key.to_s) }
end

# Alt text describes what is in the picture. It is not the prompt.
#
# This was the fully compiled, diversified prompt truncated to 240 characters,
# which meant the accessibility text written into the shared gallery manifest
# opened with "Kodak Portra 400 color negative scan, fine grain, gentle
# highlight rolloff, 85mm portrait lens, compressed background, creamy bokeh"
# and ran out of room before it reached the subject. Someone reading with a
# screen reader got a film-stock datasheet.
#
# Emulsion, glass, weather and hour are how the image was made; a viewer who
# cannot see it needs what it is OF. Subject, then how much of them is in frame,
# then where they are.
ALT_TEXT_FIELDS = %i[distance camera_height].freeze

def alt_text_for(base_prompt, options = {}, background = nil)
  parts = [base_prompt.to_s.strip]
  ALT_TEXT_FIELDS.each { |field| parts << resolve_vocab(field, options[field]) }
  parts << background
  parts.compact.reject(&:empty?).join(", ").gsub(/,\s*/, ", ").strip[0, 240]
end

# Vocabulary that contradicts itself. Not fatal — a neon sign at midday is a
# real photograph, and so is candlelight in an afternoon interior — but two
# fields describing incompatible light is far more often a mistake than an
# intention, and the model resolves it by picking one and ignoring the other
# without saying which.
VOCAB_CONFLICTS = [
  [:lighting, %w[golden_hour], :time_of_day, %w[first_light dawn midday night midnight blue_hour]],
  [:lighting, %w[candlelight firelight neon practical], :time_of_day, %w[morning midday afternoon]],
  [:lighting, %w[overcast open_shade], :weather, %w[clear]],
  [:lighting, %w[hard direct_flash], :weather, %w[fog haze downpour]],
  [:lighting, %w[window golden_hour rembrandt split butterfly loop], :time_of_day, %w[midnight]],
  [:weather, %w[snow frost aurora], :time_of_day, %w[golden_hour]],
].freeze

# A bare "selfie" in the prompt asks for the distortion, and gets it.
#
# The word carries a geometry: arm's length is 40-70cm, which is exactly the
# range where the nose enlarges and the ears fall away, and a model trained on
# millions of real selfies reproduces that faithfully. It is not a style the
# model is applying badly; it is the correct rendering of what was asked for.
#
# Warned rather than refused, because sometimes the distortion is wanted — it
# is what makes a selfie read as a selfie. What must not happen is getting it
# without having chosen it.
def warn_bare_selfie(prompt, options)
  return unless prompt.to_s.match?(/\bselfie\b/i)
  return if options[:selfie_geometry] || options[:subject_distance]

  warn "warn: the prompt says \"selfie\" with no --subject-distance and no " \
       "--selfie-geometry, so the model will render it at arm's length with the " \
       "nose enlarged and the ears falling away — which is what a real selfie is."
  warn "warn: --selfie-geometry keeps the framing and the eye contact and drops " \
       "the distortion; --subject-distance selfie asks for it deliberately."
end

def warn_vocab_conflicts(options)
  warn_bare_selfie(options[:prompt], options)
  VOCAB_CONFLICTS.each do |field_a, values_a, field_b, values_b|
    a = options[field_a]&.to_s&.downcase&.tr("- ", "__")
    b = options[field_b]&.to_s&.downcase&.tr("- ", "__")
    next unless a && b && values_a.include?(a) && values_b.include?(b)

    warn "warn: --#{field_a.to_s.tr('_', '-')} #{a} and --#{field_b.to_s.tr('_', '-')} #{b} describe " \
         "incompatible light; the model will honour one of them and not tell you which"
  end
end

# Content-addressed so repeated downloads of the same output collapse to one
# blob; the sidecar records everything needed to reproduce or audit the call.
def cache_blob(path, cache_dir)
  digest = Master::Io::ReplicateClient.checksum(path)
  FileUtils.mkdir_p(cache_dir)
  blob_path = File.join(cache_dir, "#{digest}#{File.extname(path)}")
  FileUtils.cp(path, blob_path) unless File.exist?(blob_path)
  [digest, blob_path]
end

def write_provenance(output, prompt, compiled_prompt, negative_prompt, options, seed, digest)
  sidecar = { output: }.merge(
    prompt:,
    compiled_prompt:,
    negative_prompt:,
    # Whether the model was actually given it. A sidecar that records a
    # constraint the request never carried is worse than one that records
    # nothing, because it is the file you would consult to find out.
    negative_prompt_sent: !negative_prompt.nil? && negative_prompt_supported?(options[:model]),
    model: options[:model],
    aspect_ratio: options[:aspect_ratio],
    raw: raw_mode?(options) && capability_for(options[:model])[:input_keys].include?("raw"),
    input_image: options[:image],
    seed:,
    sha256: digest,
    generated_at: Time.now.utc.iso8601,
  )
  File.write("#{output}.json", JSON.pretty_generate(sidecar))
  sidecar
end

def append_gallery_manifest(sidecar, alt_text)
  manifest = File.join(MasterPaths.repo, ".master", "media", "gallery.jsonl")
  FileUtils.mkdir_p(File.dirname(manifest))
  File.open(manifest, "a") { |f| f.puts(sidecar.merge(alt_text:).to_json) }
end

# The grade every output gets unless it is turned off.
#
# It was `--postpro PRESET`, opt-in, one flag on one command — so the default
# was no grade at all, and the house look was whatever anyone remembered to
# type. A look that has to be remembered is not a house look.
#
# `portrait` because repligen mostly makes faces and it is the preset built for
# them: kodak_portra with skin_protect, and grain. The grain is not decoration.
# Generated skin is too clean and its specular response uniform, because models
# learn from retouched photography and have no account of subsurface scattering
# — see STUDIO/PHOTOGRAPHY.md §4. Grain is the direct answer to the first half
# of that, and it is the single highest-yield thing that can be done to a
# generated face after the fact.
#
# Changed in one place, here, or per run with --postpro, or per shell with
# REPLIGEN_POSTPRO. --no-postpro turns it off entirely, which is what you want
# when the output is going into another tool that will grade it later.
HOUSE_POSTPRO = ENV.fetch("REPLIGEN_POSTPRO", "portrait")

def maybe_handoff_postpro(output, preset)
  return output unless preset

  result = Master::Io::ScriptDispatch.run(
    root: MasterPaths.root,
    tool: "postpro",
    arg: ["--input", output, "--output", output, "--preset", preset].map { |v| Shellwords.escape(v) }.join(" "),
  )
  result.ok? ? output : (abort "warn: postpro handoff failed: #{result.message}")
end

# Everything below this line is the CLI: it reads ARGV, and the `case` at the
# end runs a command or aborts with usage. Without this guard, *loading* the file
# ran a command — so nothing could ever require it, and STUDIO/gate.rb could
# check it no further than "it parses", which is the check an autofix passes
# while leaving the tool dead.
#
# A top-level `return` rather than wrapping 220 lines in an `if`: it ends the
# file for `load` and `require` exactly as the wrapper would, and re-indenting
# the whole dispatch would have buried the change in a diff nobody could read.
# Running it as a script is unaffected — that is the branch that continues.
# Does everything this file can be asked for actually exist and reach the model?
#
# No API calls, no credentials, no cost. It is here because every failure this
# file had was of the same kind: a value that resolved to nothing and was
# .compacted away, a negative prompt filtered out by the model's own input_keys
# and then recorded in the provenance sidecar as if it had been sent, a
# diversity quota that four same-length pools could not possibly fill. None of
# them raised. You paid Replicate, waited, and got a picture that was missing
# the thing you asked for.
# The keys build_input can fill from something other than a per-model knob.
# Keep in step with the literal hash there.
PRODUCIBLE_INPUT_KEYS = %w[prompt aspect_ratio output_format output_quality safety_tolerance seed raw
                           input_image input_images].freeze

def vocab_problems
  problems = []

  VOCABULARIES.each do |field, table|
    problems << "#{field} vocabulary is empty" if table.empty?
    table.each do |key, description|
      problems << "#{field}.#{key} normalises to #{key.downcase.tr('- ', '__').inspect}, so it can never be matched" \
        if key != key.downcase.tr("- ", "__")
      problems << "#{field}.#{key} has no description" if description.to_s.strip.empty?
    end
    dupes = table.values.tally.select { |_, n| n > 1 }.keys
    dupes.each { |d| problems << "#{field} has two keys with the identical description #{d[0, 40].inspect}" }
  end

  # Every --distance has to have an aspect ratio, or the field silently stops
  # deciding the shape of the frame for that one value.
  (DISTANCE_VOCAB.keys - DISTANCE_ASPECT.keys).each { |k| problems << "distance #{k} has no DISTANCE_ASPECT entry" }
  (DISTANCE_ASPECT.keys - DISTANCE_VOCAB.keys).each { |k| problems << "DISTANCE_ASPECT has #{k}, which is not a --distance value" }

  # A capability whose negative_prompt_key is not in its own input_keys drops
  # the negative prompt in build_input's filter without saying so.
  MODEL_CAPABILITIES.each do |model, cap|
    problems << "#{model} lists no prompt input key" unless cap[:input_keys].include?("prompt")
    key = cap[:negative_prompt_key]
    problems << "#{model} names negative_prompt_key #{key.inspect} but does not list it in input_keys" \
      unless key.nil? || cap[:input_keys].include?(key)

    # An input key nothing can fill is the same defect as a vocabulary entry
    # nothing can select: it reads as a capability and is a comment. This is how
    # guidance/num_inference_steps/cfg_scale were found — declared here, read in
    # build_input, and settable by no flag in the parser.
    %i[guidance steps].each do |kind|
      knob = cap[:"#{kind}_key"]
      next unless knob

      problems << "#{model} names #{kind}_key #{knob.inspect}, which is not in its input_keys" \
        unless cap[:input_keys].include?(knob)
      problems << "#{model} names #{kind}_key #{knob.inspect} with no #{kind}_range to check against" \
        unless cap[:"#{kind}_range"]
    end
    (cap[:input_keys] - PRODUCIBLE_INPUT_KEYS - [cap[:guidance_key], cap[:steps_key], cap[:negative_prompt_key]].compact).each do |orphan|
      problems << "#{model} declares input key #{orphan.inspect}, which build_input has no source for"
    end
  end
  problems << "PREVIEW_MODEL #{PREVIEW_MODEL} has no MODEL_CAPABILITIES entry" unless MODEL_CAPABILITIES.key?(PREVIEW_MODEL)
  problems << "FINAL_MODEL #{FINAL_MODEL} has no MODEL_CAPABILITIES entry" unless MODEL_CAPABILITIES.key?(FINAL_MODEL)

  # The batch diversity claim, checked rather than asserted: --batch tops out at
  # 20, so twenty consecutive indices must produce twenty distinct combinations.
  pools = { expression: EXPRESSION_POOL, pose: POSE_POOL, wardrobe: WARDROBE_POOL, background: BACKGROUND_POOL }
  pools.each do |name, pool|
    stride = POOL_STRIDES.fetch(name)
    problems << "#{name} stride #{stride} shares a factor with its length #{pool.length}, so it cannot visit every entry" \
      if stride.gcd(pool.length) != 1
  end
  tuples = (0...20).map { |i| pools.map { |n, pool| pool[(i * POOL_STRIDES.fetch(n)) % pool.length] } }
  problems << "a batch of 20 produces only #{tuples.uniq.length} distinct combinations" if tuples.uniq.length < 20

  # Conflict rules have to name fields and values that exist, or the warning
  # they exist to raise silently never fires.
  VOCAB_CONFLICTS.each do |field_a, values_a, field_b, values_b|
    [[field_a, values_a], [field_b, values_b]].each do |field, values|
      table = VOCABULARIES[field]
      if table.nil?
        problems << "VOCAB_CONFLICTS names field #{field}, which is not a vocabulary"
        next
      end
      (values - table.keys).each { |v| problems << "VOCAB_CONFLICTS names #{field} #{v.inspect}, which is not in that vocabulary" }
    end
  end

  # Alt text is built from these; a field that is not a vocabulary resolves to
  # nothing and the gallery loses that part of its description.
  (ALT_TEXT_FIELDS - VOCABULARIES.keys).each { |f| problems << "ALT_TEXT_FIELDS names #{f}, which is not a vocabulary" }

  problems
end

return unless __FILE__ == $PROGRAM_NAME

# The reporter. vocab_problems sits above the CLI guard so a test or a gate
# can ask the question without a process exit; this half is the command-line
# face of the same answer.
def vocab_check
  problems = vocab_problems
  problems.each { |line| puts "BROKEN #{line}" }
  counts = VOCABULARIES.map { |f, t| "#{f}=#{t.length}" }.join(" ")
  puts "#{counts}, #{MODEL_CAPABILITIES.length} models — #{problems.length} problem(s)"
  exit(1) if problems.any?
end

cache = File.expand_path(ENV.fetch("REPLIGEN_CATALOG", "~/.cache/repligen/models.json"))
blob_cache_dir = File.expand_path(ENV.fetch("REPLIGEN_BLOB_CACHE", "~/.cache/repligen/blobs"))
options = { model: ENV.fetch("REPLIGEN_MODEL", "black-forest-labs/flux-2-pro"), aspect_ratio: nil, limit: 100, dry_run: false, batch: 1 }
parser = OptionParser.new do |p|
  p.banner = "Usage: repligen.rb generate|search|sync|stats|capabilities|vocab-check [options]"
  p.on("--prompt TEXT") { |v| options[:prompt] = v }
  p.on("--model MODEL") { |v| options[:model] = v; options[:model_explicit] = true }
  p.on("--aspect-ratio RATIO") { |v| options[:aspect_ratio] = v }
  p.on("--output FILE") { |v| options[:output] = File.expand_path(v) }
  p.on("--limit N", Integer) { |v| options[:limit] = v.clamp(1, 1_000) }
  p.on("--dry-run") { options[:dry_run] = true }
  p.on("--until STAGE") { |v| options[:until] = v }
  p.on("--stock NAME") { |v| options[:stock] = v }
  p.on("--lens NAME") { |v| options[:lens] = v }
  p.on("--camera-height NAME") { |v| options[:camera_height] = v }
  p.on("--distance NAME") { |v| options[:distance] = v }
  p.on("--subject-distance NAME") { |v| options[:subject_distance] = v }
  p.on("--key-side NAME") { |v| options[:key_side] = v }
  p.on("--catchlight NAME") { |v| options[:catchlight] = v }
  p.on("--skin NAME") { |v| options[:skin] = v }
  # The framing and gaze of a selfie with the facial proportions of a portrait
  # made from three metres. Not a combination a camera can produce.
  p.on("--selfie-geometry") { options[:selfie_geometry] = true }
  p.on("--lighting NAME") { |v| options[:lighting] = v }
  p.on("--weather NAME") { |v| options[:weather] = v }
  p.on("--time-of-day NAME") { |v| options[:time_of_day] = v }
  p.on("--negative TEXT") { |v| options[:negative] = v }
  p.on("--no-negative") { options[:no_negative] = true }
  p.on("--allow-beautify") { options[:allow_beautify] = true }
  p.on("--batch N", Integer) { |v| options[:batch] = v.clamp(1, 20) }
  p.on("--seed N", Integer) { |v| options[:seed] = v }
  # Both knobs are per-model: --guidance is `guidance` on flux-dev and `cfg` on
  # SD 3.5, --steps is `num_inference_steps` on Flux and `steps` on SD 3.5, and
  # the ranges differ. build_input maps and checks; here they are just numbers.
  p.on("--guidance N", Float) { |v| options[:guidance] = v }
  p.on("--steps N", Integer) { |v| options[:steps] = v }
  p.on("--preview") { options[:preview] = true }
  p.on("--final") { options[:final] = true }
  p.on("--raw") { options[:raw] = true }
  p.on("--no-raw") { options[:no_raw] = true }
  p.on("--image FILE") { |v| options[:image] = File.expand_path(v) }
  # Repeatable. FLUX 2 holds a character across up to eight of these.
  p.on("--reference FILE") { |v| (options[:references] ||= []) << File.expand_path(v) }
  p.on("--postpro PRESET") { |v| options[:postpro] = v }
  # Off entirely. The grade is the default now, so this is the escape hatch.
  p.on("--no-postpro") { options[:postpro] = false }
end
command = ARGV.shift || "help"
parser.parse!(ARGV)
if command == "help"
  puts parser
  exit 0
end

case command
when "capabilities"
  puts Master::Io::AnalogCapabilities.report(:repligen)
when "chains"
  # The chains this tree ships, from the directory rather than a maintained
  # list, so adding one is adding a file.
  require_relative "chain"
  names = Repligen::Chain.available
  if names.empty?
    puts "repligen: no chains in #{Repligen::Chain::DEFAULT_DIR}"
  else
    names.each do |name|
      chain = Repligen::Chain.load(name)
      puts "#{name}  (#{chain[:stages].length} stages)"
      puts "  #{chain[:description].to_s.strip.gsub(/\s+/, ' ')[0, 200]}"
      puts Repligen::Chain.plan(chain)
      puts
    end
  end
when "chain"
  # Validated whole, before anything is spent. A chain that fails at stage 6
  # because stage 2 could not produce what stage 3 assumed has already cost the
  # first five, which is why this refuses on the plan rather than on the wire.
  require_relative "chain"
  name = ARGV.shift.to_s
  abort "usage: repligen chain NAME [--dry-run]" if name.empty?

  chain = begin
    Repligen::Chain.load(name)
  rescue Repligen::Chain::Invalid => e
    abort "repligen: #{e.message}"
  end

  puts "repligen: chain #{name} — #{chain[:stages].length} stages"
  puts Repligen::Chain.plan(chain)

  problems = Repligen::Chain.problems(chain, capability_for: method(:capability_for))
  unless problems.empty?
    warn ""
    problems.each { |problem| warn "repligen: REFUSED — #{problem}" }
    abort "repligen: #{problems.length} problem(s); nothing was requested and nothing was spent"
  end
  puts "repligen: the chain is satisfiable — every stage can take what the one before it produces"

  if options[:dry_run]
    puts "repligen: --dry-run, so nothing was requested"
    exit 0
  end

  # The loop itself lives in Chain.run, which takes this block. It is injected
  # so the carry-forward can be tested without spending anything — see
  # test/tools/test_chain.rb, which hands in a recorder and asserts that stage
  # N+1 really is given stage N's file. That is the one thing a chain must get
  # right and the one thing that fails silently: a model handed no image just
  # generates from the prompt and returns something plausible.
  abort "repligen: chain #{name} needs REPLICATE_API_TOKEN to run; --dry-run validates without it" if
    Master::Io::ReplicateClient.load_token.to_s.strip.empty?

  base = options[:output] || "chain-#{name}.jpg"
  ext = File.extname(base)
  ext = ".jpg" if ext.empty?
  stem = base.sub(/#{Regexp.escape(File.extname(base))}\z/, "")
  client = Master::Io::ReplicateClient.new

  perform = lambda do |stage:, index:, total:, image:, seed:|
    target = "#{stem}-#{format('%02d', index + 1)}-#{stage.name}#{ext}"
    stage_options = options.merge(stage.options).merge(model: stage.model)
    stage_options[:image] = image if image
    prompt = stage.inherits.include?("prompt") ? options[:prompt] : stage.prompt
    compiled = compile_prompt(prompt, stage_options)
    negative = compile_negative_prompt(stage_options)
    stage_seed = seed || options[:seed] || SecureRandom.random_number(2**31)
    input = build_input(compiled, stage_options, seed: stage_seed, negative_prompt: negative)

    puts "repligen: stage #{index + 1}/#{total} #{stage.name} — #{stage.model}"
    urls = Array(client.predict(stage.model, input)).flatten.compact
    abort "repligen: stage #{stage.name} returned no output; earlier stages are kept" if urls.empty?

    FileUtils.mkdir_p(File.dirname(target))
    client.download_url(urls.first, target)
    digest, = cache_blob(target, blob_cache_dir)
    write_provenance(target, prompt, compiled, negative, stage_options, stage_seed, digest)
    puts "repligen: stage #{index + 1} wrote #{target}"
    { path: target, seed: stage_seed }
  end

  produced = Repligen::Chain.run(chain, perform: perform, until_stage: options[:until],
                                        image: options[:image], seed: options[:seed])

  # postpro last, on the final frame only — grading an intermediate would be
  # graded again by every stage after it.
  maybe_handoff_postpro(produced.last, options[:postpro]) if produced.any?
  puts "repligen: chain #{name} produced #{produced.length} frame(s)"
  puts produced
when "vocab-check"
  vocab_check
when "generate"
  abort parser.to_s if options[:prompt].to_s.strip.empty?
  abort "warn: --preview and --final ask for different models" if options[:preview] && options[:final]

  options[:model] = PREVIEW_MODEL if options[:preview] && !ENV.key?("REPLIGEN_MODEL") && !options[:model_explicit]
  # --final overrides REPLIGEN_MODEL, unlike --preview. That is the asymmetry
  # the flag is for: the environment variable is how you leave a session in
  # preview, and --final is how you say "not this one, do it properly".
  options[:model] = FINAL_MODEL if options[:final] && !options[:model_explicit]
  if options[:image]
    abort "warn: --image #{options[:image]} is not a file" unless File.file?(options[:image])
  elsif capability_for(options[:model])[:input_keys].include?("input_image")
    abort "warn: #{options[:model]} is an editor; pass --image PATH"
  end
  options[:aspect_ratio] = infer_aspect_ratio(options[:prompt], options[:aspect_ratio], options[:distance])
  client = options[:dry_run] ? nil : Master::Io::ReplicateClient.new

  options[:postpro] = HOUSE_POSTPRO if options[:postpro].nil?
  warn_vocab_conflicts(options)
  negative_prompt = compile_negative_prompt(options)
  # Say it out loud. The request is about to go out without the constraint the
  # rest of this file spends four functions assembling, and the only reason it
  # ever looked applied is that nobody was told it was not.
  unless negative_prompt.nil? || negative_prompt_supported?(options[:model])
    warn "warn: #{options[:model]} takes no negative prompt; asking for the opposite in the positive instead"
  end

  # Invariant across the batch — every field it reads is the same for all
  # twenty images. Only diversify() varies per index.
  compiled = compile_prompt(options[:prompt], options)
  compiled = "#{compiled}, #{POSITIVE_SKIN_GUIDANCE}" if negative_prompt && !negative_prompt_supported?(options[:model])

  outputs = (0...options[:batch]).map do |index|
    varied = diversify(compiled, index, options[:batch])
    seed = options[:seed] ? options[:seed] + index : SecureRandom.random_number(2**31)
    input = build_input(varied, options, seed:, negative_prompt:)

    if options[:dry_run]
      puts "ok: repligen dry-run model=#{options[:model]} input=#{input.inspect}"
      next nil
    end

    urls = Array(client.predict(options[:model], input)).flatten.compact
    abort "warn: repligen returned no output" if urls.empty?

    target = if options[:output]
               options[:batch] > 1 ? options[:output].sub(/(\.\w+)?\z/) { |ext| "-#{index}#{ext}" } : options[:output]
             end

    unless target
      puts "ok: repligen generated\n#{urls.join("\n")}"
      next nil
    end

    FileUtils.mkdir_p(File.dirname(target))
    client.download_url(urls.first, target)
    digest, = cache_blob(target, blob_cache_dir)
    sidecar = write_provenance(target, options[:prompt], varied, negative_prompt, options, seed, digest)
    append_gallery_manifest(sidecar, alt_text_for(options[:prompt], options, batch_background(index, options[:batch])))
    maybe_handoff_postpro(target, options[:postpro])
    puts "ok: repligen generated #{target}"
    target
  end.compact

  outputs
when "search"
  query = ARGV.join(" ").strip
  abort "usage: repligen.rb search QUERY [--limit N]" if query.empty?
  rows = Master::Io::ReplicateClient.new.models(limit: options[:limit], query:)
  puts rows.map { |row| "#{row['owner']}/#{row['name']}\t#{row['description'].to_s.gsub(/\s+/, ' ')[0, 120]}" }
when "sync"
  rows = Master::Io::ReplicateClient.new.models(limit: options[:limit])
  FileUtils.mkdir_p(File.dirname(cache))
  File.write(cache, JSON.pretty_generate({ synced_at: Time.now.utc.iso8601, models: rows }))
  puts "ok: repligen synced #{rows.length} models to #{cache}"
when "stats"
  data = File.file?(cache) ? JSON.parse(File.read(cache)) : { "models" => [] }
  models = Array(data["models"])
  owners = models.group_by { |row| row["owner"] }.sort_by { |_, rows| -rows.length }.first(10)
  puts "catalog: #{models.length} models (#{data['synced_at'] || 'not synced'})"
  owners.each { |owner, rows| puts "#{owner}: #{rows.length}" }
else
  abort parser.to_s
end
