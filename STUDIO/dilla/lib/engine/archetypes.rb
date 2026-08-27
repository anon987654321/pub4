# frozen_string_literal: true
#
# Drum archetypes and ghost-note tiers.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

GHOST_TIERS = {
  whisper: { mul: 0.58, steps_scale: 0.72, fill_mul: 0.35 },
  pocket:  { mul: 1.0,  steps_scale: 1.0,  fill_mul: 1.0 },
  accent:  { mul: 1.28, steps_scale: 1.18, fill_mul: 1.45 },
}.freeze

# Phrase-level compositional archetypes -- each bundle reuses existing,
# already-tested per-bar-read ENV knobs (groove_engine.rb reads SNARE_EARLY/
# KICK_LATE/HATS_LATE/POCKET_KICK_SILENCE/KICK_FREEHAND live at scheduling
# time, not once at setup, so mutating them mid-render genuinely changes the
# next bar's feel) rather than new step-array generation. Named after the
# drum-composition ideas they approximate; "hat disagreement" and "barline
# slip" are real-mechanism approximations (no literal per-role swing bypass
# or cross-bar anticipation exists yet), not literal implementations.
DRUM_ARCHETYPES = {
  # No kick on 1 some bars; bass implies the downbeat instead.
  negative_space:     { "POCKET_KICK_SILENCE" => "1", "SNARE_EARLY" => "0", "KICK_LATE" => "0", "KICK_FREEHAND" => "0", "GHOST_TIER" => "whisper" },
  # Snare lands early, kick answers after it, kit stays default-loose.
  late_answer_kick:    { "POCKET_KICK_SILENCE" => "0", "SNARE_EARLY" => "1", "KICK_LATE" => "1", "KICK_FREEHAND" => "1", "GHOST_TIER" => "pocket" },
  # Ghost notes carry more weight than the backbeat itself.
  ghost_led_backbeat:  { "POCKET_KICK_SILENCE" => "0", "SNARE_EARLY" => "0", "KICK_LATE" => "0", "KICK_FREEHAND" => "0", "GHOST_TIER" => "accent" },
  # Approximation: hats stay on-grid (HATS_LATE=0) while kick/snare keep
  # their own independent early/late push -- not a literal separate swing
  # lane, but reads as "hats disagreeing with the kit" in practice.
  hat_disagreement:    { "POCKET_KICK_SILENCE" => "0", "SNARE_EARLY" => "1", "KICK_LATE" => "0", "HATS_LATE" => "0", "KICK_FREEHAND" => "0", "GHOST_TIER" => "pocket" },
  # Approximation: KICK_FREEHAND's cyclic unquantized nudge is the closest
  # existing mechanism to "anticipates the next bar" without new per-bar
  # lookahead scheduling.
  barline_slip:        { "POCKET_KICK_SILENCE" => "0", "SNARE_EARLY" => "0", "KICK_LATE" => "0", "KICK_FREEHAND" => "1", "GHOST_TIER" => "pocket" },
}.freeze
DRUM_ARCHETYPE_ORDER = DRUM_ARCHETYPES.keys.freeze

def drum_archetype_rotation_enabled?
  # Off by default -- only ever verified as "renders without crashing," never
  # actually listened to. Silently changed already-tuned tracks (pedal_e_descent
  # included) by default; real listening feedback was that it made rhythm
  # feel broken/off-grid, not intentionally loose. Opt in with
  # DRUM_ARCHETYPE_ROTATE=1 once it's been through an actual listening pass.
  ENV.fetch("DRUM_ARCHETYPE_ROTATE", "0") != "0"
end

# concrete_soul: techno's physicality (harder sidechain pump, more headroom
# for kick/bass, no vinyl-warmth coloration) layered onto the untouched
# harmonic/fugue/archetype engine, rather than a separate synthesis path
# (render_techno) reimplementing harmony from scratch. Only touches mix
# character knobs that already exist and are already used elsewhere in this
# file for other tracks -- no new filter chains invented here. Every value
# is a force (this track name is the only thing that should ever set it
# this way, so soft-fill's "don't clobber an explicit override" caution
# doesn't apply).
CONCRETE_SOUL_MIX = {
  "SIDECHAIN_STYLE" => "wonky", # the harder-pump of the two real options
  "ANALOG_CHAIN" => "broadcast", # least-colored chain -- no vinyl warmth
  "SONITEX" => "donuts_soul", "SONITEX_PRESET" => "donuts_soul",
  "VINYL" => "0",
  "GHOST_TIER" => "accent",
  "KICK_GAIN" => "0.85",
  "DRUM_BUS_VOL" => "1.0", "DRUM_BUS_GAIN" => "1.0", "DRUM_MIX_WEIGHT" => "1.0",
  "RIR_ROOM" => "1", # concrete/warehouse ambience -- this is the one place
  # the room-print layer is the point, not a subtle extra.
  # Every other phrase flips the drum pattern vocabulary from concrete_soul's
  # base :syncopated_slash_ninth (Dilla pocket) to :techno_house (straight
  # four-on-the-floor) -- the actual "alternates between J Dilla drums and
  # HATE techno drums" request, not just a mix-character difference.
  "DRUM_STYLE_ALTERNATE" => "1",
}.freeze

def apply_concrete_soul_mix!(track)
  return unless track.to_s == "concrete_soul"

  # Called from apply_dilla_style! three lines below the loop that was converted
  # to style_env_write!, and it was still writing ENV directly — so this table
  # reverted operator pins for concrete_soul renders after the neighbouring one
  # had stopped doing it.
  force_env!(CONCRETE_SOUL_MIX, label: "CONCRETE_SOUL_MIX")
end

# FUGUE_CONVERSATION: every new voice answers an existing rhythmic motif,
# scoped to a real, already-available signal rather than new cross-voice
# data plumbing -- arrange_fugue_progression already tags each bar's phase
# (exposition/development/recapitulation/coda) via chord_phase_at, which the
# per-bar loop already computes for every track, fugue-form or not. During
# development/recapitulation, the ghost-snare "countersubject" answers the
# bar's own kick pattern (the "subject") a short beat later, rather than
# drawing from its own independent pattern pool. Exposition/coda are left
# alone -- a fugue states its subject plainly first and lets it go quiet at
# the end; answering everywhere would be a denser kit, not a dialogue.
FUGUE_GHOST_ANSWER_STEPS = 16
FUGUE_GHOST_ANSWER_OFFSET = 3 # dotted-eighth-ish answer, not a flat echo

def fugue_conversation_enabled?
  # Off by default -- same reason as drum_archetype_rotation_enabled? above:
  # verified only as "doesn't crash," never actually listened to. Real
  # feedback was that it added clutter, not a dialogue. Opt in with
  # FUGUE_CONVERSATION=1 once it's been through an actual listening pass.
  ENV.fetch("FUGUE_CONVERSATION", "0") != "0"
end

def fugue_ghost_answer_steps(kick_pattern, phase)
  return [] unless fugue_conversation_enabled?
  return [] unless %i[development recapitulation].include?(phase)

  kick_pattern.map { |step| (step + FUGUE_GHOST_ANSWER_OFFSET) % FUGUE_GHOST_ANSWER_STEPS }
end

# Reassigned once per phrase (not per bar -- these read as a section's
# character, not a bar-to-bar flicker). Deterministic by phrase index, not
# random, so the same render is reproducible.
def apply_drum_archetype!(bar, phrase_bars)
  return unless drum_archetype_rotation_enabled?

  length = phrase_bars.to_i.positive? ? phrase_bars.to_i : 8
  phrase_index = bar / length
  name = DRUM_ARCHETYPE_ORDER[phrase_index % DRUM_ARCHETYPE_ORDER.length]
  bundle = DRUM_ARCHETYPES.fetch(name)
  return if @last_drum_archetype == name

  @last_drum_archetype = name
  # Was a bare ENV loop plus one synthetic provenance key, so print_config_provenance
  # could not show which drum knobs the archetype had moved. force_env! records
  # each one and honours pins.
  force_env!(bundle, label: "apply_drum_archetype![#{name}]")
end

# Alternates the actual drum PATTERN vocabulary (DRUM_PATTERN_SETS[:default
# feel] vs DRUM_PATTERN_SETS[:techno_house]) per phrase, not just the timing/
# velocity knobs apply_drum_archetype! rotates. feel is a plain local in
# dilla_schedule's per-bar loop (dilla_kick_pattern/dilla_snare_steps/etc.
# all take it as a parameter re-read every bar), so reassigning it here
# genuinely swaps which pattern set the next bar draws from -- not a
# separate render pass or crossfade. Off by default (DRUM_STYLE_ALTERNATE=1
# to enable) since it changes a track's core character; concrete_soul turns
# it on via CONCRETE_SOUL_MIX.
#
# The feel it alternates INTO is now a choice rather than a constant. It was
# hard-wired to :techno_house, which was the only dance grid that existed when
# this was written; there are ten now, and "alternate the pattern vocabulary
# every phrase" is a far more interesting instruction when the other vocabulary
# can be two-step, dembow or batucada. DRUM_STYLE_ALTERNATE_FEEL names it; an
# unknown name falls through drum_feel_key to :default rather than erroring, so
# a typo costs a plain grid and not a render.
def alternating_drum_feel(bar, phrase_bars, base_feel)
  return base_feel unless ENV.fetch("DRUM_STYLE_ALTERNATE", "0") != "0"

  length = phrase_bars.to_i.positive? ? phrase_bars.to_i : 8
  return base_feel if (bar / length).even?
  ENV.fetch("DRUM_STYLE_ALTERNATE_FEEL", "techno_house").to_s.downcase.tr("-", "_").to_sym
end
