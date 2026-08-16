# frozen_string_literal: true

# Pocket, humanize, Markov drums, Euclidean/prime grids — hip-hop groove layer.
#
# Pocket DNA (MPC finger-drum craft, Charnas “Dilla Time”, Hein analyses):
#   1. SIMPLICITY — sparse 16-step: few kicks, hard 2&4 snare, rare ghosts
#   2. MICRO-TIMING — independent layers: snare early, kick late, hats later
#   3. SAMPLE CHOICE — alternate kicks, soft ghost snare, closed vs open hat
module DillaGroove
  PRIMES = [3, 5, 7, 11].freeze
  # Tempo/timing should breathe over a multi-bar phrase, not sit dead-locked
  # to the grid — a slow sine LFO, period within the 4-8 bar range documented
  # for this kind of groove-breathing.
  PHRASE_DRIFT_PERIOD_BARS = 6.0
  PHRASE_DRIFT_MAX_MS = 5.0

  # Classic sparse Dilla / Questlove pockets — FEWER kicks, solid 2&4, space.
  # Dense 4-kick bars read as house/techno; soul leaves air for Rhodes.
  POCKET_KICK_PHRASES = [
    [0, 10],
    [0, 6, 10],
    [0, 10, 14],
    [0, 7, 10],
    [0, 6],
    [0, 3, 10],
    [6, 10],
    [0, 11],
  ].freeze
  # Dusty / Madlib — still sparse, occasional four-on-floor half-bar only.
  POCKET_KICK_PHRASES_DUSTY = [
    [0, 10],
    [0, 8, 11],
    [0, 7, 10],
    [0, 4, 10],
    [0, 10, 14],
    [2, 10],
    [0, 6, 10],
    [0, 8],
  ].freeze
  # Neo-soul / D'Angelo live-pocket: often just downbeat + one syncopation.
  # Expanded set rotates across bars so stream/one-shots don't feel looped.
  POCKET_KICK_PHRASES_NEOSOUL = [
    [0, 10],
    [0, 6],
    [0, 10, 13],
    [0],
    [0, 7, 10],
    [0, 11],
    [6, 10],
    [0, 6, 14],
    [0, 9],
    [0, 3, 10],
    [0, 10, 14],
    [0, 5, 10],
    [10],
    [0, 6, 11],
    [0, 8, 14],
    [0, 7],
  ].freeze
  # Sparse shapes for breathing bars.
  POCKET_KICK_SPARSE_PHRASES = [
    [0],
    [0, 10],
    [10],
    [0, 6],
    [],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_DUSTY = [
    [0, 8],
    [0],
    [0, 10],
    [8],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_NEOSOUL = [
    [0],
    [0, 10],
    [],
    [10],
    [0, 6],
    [0, 11],
    [],
    [0, 7],
  ].freeze
  POCKET_SNARE_HARD = [4, 12].freeze
  # Documented Dilla off-kilter device: the backbeat snare occasionally
  # pushed a full 16th early rather than sitting on 4/12 -- a placement
  # choice, distinct from the ms-level micro-timing in role_timing_offset.
  POCKET_SNARE_RUSH = [4, 11].freeze
  POCKET_SNARE_RUSH_DUSTY = [3, 12].freeze
  POCKET_SNARE_RUSH_NEOSOUL = [4, 12].freeze # keep backbeat locked more often
  POCKET_SNARE_GHOST_PHRASES = [
    [],
    [7],
    [10],
    [7, 15],
    [],
    [2],
  ].freeze
  POCKET_SNARE_GHOST_PHRASES_DUSTY = [
    [6],
    [],
    [6, 14],
    [14],
    [],
  ].freeze
  # Live neo-soul ghosts: quiet 16th after 2, rarely both — more phrase variety.
  POCKET_SNARE_GHOST_PHRASES_NEOSOUL = [
    [],
    [5],
    [7],
    [],
    [13],
    [5, 13],
    [6],
    [],
    [15],
    [5, 7],
    [13, 15],
    [],
  ].freeze
  # 8th hats, but NOT every bar identical — leave space (real RH pocket).
  POCKET_HAT_PHRASES = [
    [0, 2, 4, 6, 8, 10, 12, 14],
    [0, 2, 4, 6, 8, 10, 12],
    [0, 4, 6, 8, 10, 12, 14],
    [0, 2, 4, 8, 10, 12, 14],
    [2, 4, 6, 8, 10, 12, 14],
  ].freeze
  # Offbeat-biased dusty hats — thinner than full 16ths.
  POCKET_HAT_PHRASES_DUSTY = [
    [1, 3, 5, 7, 9, 11, 13],
    [1, 3, 5, 7, 9, 11, 15],
    [1, 3, 5, 9, 11, 13],
    [0, 3, 5, 7, 9, 11, 13],
  ].freeze
  # Neo-soul: often quarters or sparse 8ths — never full 16th grid.
  POCKET_HAT_PHRASES_NEOSOUL = [
    [0, 4, 8, 12],
    [0, 2, 4, 8, 12],
    [0, 4, 8, 10, 12],
    [0, 4, 6, 8, 12, 14],
    [2, 4, 8, 12],
    [0, 4, 8],
    [0, 4, 10, 12],
    [0, 2, 8, 12],
    [4, 8, 12],
    [0, 6, 8, 12, 14],
  ].freeze
  # Industrial techno: four-on-floor kick, solid 2+4 snare/clap, 16th hats.
  POCKET_KICK_PHRASES_INDUSTRIAL = [
    [0, 4, 8, 12],
    [0, 4, 8, 12],
    [0, 4, 8, 10, 12],
    [0, 4, 8, 12, 14],
    [0, 4, 6, 8, 12],
    [0, 4, 8, 12],
    [0, 2, 4, 8, 12],
    [0, 4, 8, 11, 12],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_INDUSTRIAL = [
    [0, 4, 8, 12],
    [0, 8],
    [0, 4, 12],
  ].freeze
  POCKET_SNARE_HARD_INDUSTRIAL = [4, 12].freeze
  POCKET_SNARE_RUSH_INDUSTRIAL = [4, 12].freeze
  POCKET_SNARE_GHOST_PHRASES_INDUSTRIAL = [
    [],
    [10],
    [],
    [6],
    [],
  ].freeze
  POCKET_HAT_PHRASES_INDUSTRIAL = [
    (0..15).to_a,
    (0..15).to_a,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [0, 2, 4, 6, 8, 10, 12, 14],
    [0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14],
  ].freeze

  # Freehand nudge ranges in MPC ticks (1/96 beat) — cyclic, not random chaos.
  POCKET_TICKS = {
    kick_anchor: 0..3,
    kick_sync: 2..9,
    snare: -14..-5,
    ghost: -6..4,
    hat_down: -1..4,
    hat_up: 6..16,
    open: 4..12,
    clap: -12..-4,
  }.freeze

  KICK_SAMPLE_CYCLE = %i[kick ind_kick kick kick].freeze
  module_function

  def enabled?
    ENV["GROOVE_ENGINE"] != "0"
  end

  # Gaussian-clustered jitter, not uniform: ~80% of hits land within one
  # sigma of center, a rare (~5%) outlier lands 3-4x further out. Uniform
  # "humanize" jitter reads as robotic — real players cluster tight around
  # a target with occasional misses, not a flat scatter (Box-Muller).
  def gaussian_jitter(rng, half_width)
    u1 = [rng.rand, 1.0e-9].max
    u2 = rng.rand
    z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    sigma = half_width / 3.0
    outlier = rng.rand < 0.05
    (z * sigma * (outlier ? 3.5 : 1.0)).clamp(-half_width * 1.6, half_width * 1.6)
  end

  def pocket_dna?
    ENV.fetch("POCKET_DNA", "1") != "0"
  end

  # dusty | industrial | neo_soul | classic
  def pocket_set
    set = ENV.fetch("POCKET_SET", "neo_soul").to_s.downcase
    return "neo_soul" if set == "soul" || set == "neosoul"
    # An explicit POCKET_SET wins outright -- DRUM_PRESET-based inference below
    # is a fallback for when the caller didn't choose a pocket at all, not a
    # second vote that can overrule one they did (e.g. POCKET_SET=classic with
    # DRUM_PRESET=dilla_slight silently became neo_soul before this guard).
    return set if ENV.key?("POCKET_SET") && !set.empty?

    preset = ENV["DRUM_PRESET"].to_s.downcase
    return "dusty" if preset.include?("madlib")
    return "industrial" if preset.include?("industrial") || preset.include?("boom_808")
    return "neo_soul" if preset.include?("dilla") || preset.include?("mpc")

    set
  end

  def dusty_pocket? = pocket_set == "dusty"
  def industrial_pocket? = pocket_set == "industrial"
  def neosoul_pocket? = pocket_set == "neo_soul" || pocket_set == "soul"

  def kick_phrases
    return POCKET_KICK_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_KICK_PHRASES_DUSTY if dusty_pocket?
    return POCKET_KICK_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_KICK_PHRASES
  end

  def kick_sparse_phrases
    return POCKET_KICK_SPARSE_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_KICK_SPARSE_PHRASES_DUSTY if dusty_pocket?
    return POCKET_KICK_SPARSE_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_KICK_SPARSE_PHRASES
  end

  def snare_rush_steps
    return POCKET_SNARE_RUSH_INDUSTRIAL if industrial_pocket?
    return POCKET_SNARE_RUSH_DUSTY if dusty_pocket?
    return POCKET_SNARE_RUSH_NEOSOUL if neosoul_pocket?

    POCKET_SNARE_RUSH
  end

  def snare_hard_steps
    return POCKET_SNARE_HARD_INDUSTRIAL if industrial_pocket?

    POCKET_SNARE_HARD
  end

  def snare_ghost_phrases
    return POCKET_SNARE_GHOST_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_SNARE_GHOST_PHRASES_DUSTY if dusty_pocket?
    return POCKET_SNARE_GHOST_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_SNARE_GHOST_PHRASES
  end

  def hat_phrases
    return POCKET_HAT_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_HAT_PHRASES_DUSTY if dusty_pocket?
    return POCKET_HAT_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_HAT_PHRASES
  end

  # Bridged from main's @render_seed by pick_render_seed! (dilla.rb) so the
  # phrase-rotation and probabilistic pocket choices below vary by render
  # instead of being a pure function of bar number -- without this, bar N
  # picks the identical kick/hat/ghost-snare shape on every single render
  # of every single track, which read as "the same drums every time".
  def render_seed
    ENV["DILLA_RENDER_SEED"].to_i
  end

  # Structural use of the humanization system: looser (more jitter) where a
  # section should feel open/unlocked, tighter where it should feel nailed
  # down -- not a flat constant across the whole track regardless of what's
  # happening structurally.
  SECTION_JITTER_MUL = {
    breakdown: 1.35, development: 1.2, bridge: 1.2, intro: 1.15,
    e_major_third_rise: 0.6, peak: 0.6, hook: 0.6, recapitulation: 0.7,
  }.freeze

  def swing_jitter_ms(bpm, step, bar, role: nil, section: nil)
    return 0.0 unless enabled?
    return 0.0 if ENV["SWING_JITTER"] == "0"
    beat_ms = 60_000.0 / bpm
    tick_ms = beat_ms / 96.0
    rng = Random.new((bar * 509) + (step * 97) + 8803)
    base_ticks = (ENV["SWING_JITTER_TICKS"] || (pocket_dna? ? 4 : 3)).to_i
    max_ticks = [(base_ticks * SECTION_JITTER_MUL.fetch(section.to_s.to_sym, 1.0)).round, 1].max
    raw = gaussian_jitter(rng, max_ticks * tick_ms / 1000.0)
    # Quantize to a whole tick -- the MPC3000's manual nudge tool (the real
    # mechanism this jitter approximates) can only land on one of 96
    # discrete positions per beat, so a fractional-tick jitter value is one
    # that could never have been produced by hand on the actual hardware.
    quantized_ticks = (raw / (tick_ms / 1000.0)).round
    (quantized_ticks * tick_ms / 1000.0) + phrase_drift_sec(bar, role:)
  end

  # Per-role period multiplier + phase offset so kick/snare/hat drift
  # independently rather than breathing in lockstep -- this is the actual
  # core of Charnas's "Dilla Time" thesis (multiple simultaneous time-feels
  # layered against each other), not one groove with uniform noise added.
  ROLE_DRIFT_PERIOD_MUL = {
    kick: 1.0, kick_anchor: 1.0, kick_sync: 1.0,
    snare: 0.78, clap: 0.78,
    hat: 1.35, hat_down: 1.35, hat_up: 1.35, open: 1.35,
    ghost: 0.6,
  }.freeze
  ROLE_DRIFT_PHASE = {
    kick: 0.0, kick_anchor: 0.0, kick_sync: 0.0,
    snare: Math::PI * 0.6, clap: Math::PI * 0.6,
    hat: Math::PI * 1.3, hat_down: Math::PI * 1.3, hat_up: Math::PI * 1.3, open: Math::PI * 1.3,
    ghost: Math::PI * 0.25,
  }.freeze

  # Slow-oscillating timing drift applied on top of per-hit jitter — the
  # difference between a groove that "breathes" over a phrase and one that's
  # merely noisy hit-to-hit. Deterministic (same bar always drifts the same
  # amount), independent of the per-hit RNG.
  def phrase_drift_sec(bar, role: nil)
    return 0.0 unless enabled?
    return 0.0 if ENV["PHRASE_DRIFT"] == "0"
    role_key = role.to_s.to_sym
    period = (ENV["PHRASE_DRIFT_PERIOD_BARS"] || PHRASE_DRIFT_PERIOD_BARS).to_f * ROLE_DRIFT_PERIOD_MUL.fetch(role_key, 1.0)
    max_ms = (ENV["PHRASE_DRIFT_MAX_MS"] || PHRASE_DRIFT_MAX_MS).to_f
    return 0.0 if period <= 0
    phase = (bar.to_f / period) * 2.0 * Math::PI + ROLE_DRIFT_PHASE.fetch(role_key, 0.0)
    (Math.sin(phase) * max_ms) / 1000.0
  end

  # Multipliers are whole ticks, not arbitrary floats: the MPC3000 runs at
  # 96 PPQ (pulses per quarter note), and its manual time-shift/nudge tool
  # -- the actual mechanism Dilla used instead of quantization -- can only
  # place a hit on one of those 96 discrete positions per beat. A fractional
  # tick offset is a value that could never have existed on the real
  # hardware; whole-tick multipliers keep every offset authentically
  # reachable by the tool this feel is modeled on.
  # Which way each role leans, in whole ticks. Positive drags, negative pushes.
  #
  # The offsets used to be inline and one-directional: snare -3/-4, everything
  # else positive. That is a real feel — a pushed snare against a dragged kit,
  # which the code called "laid-back boom-bap tension" — but it was the only one
  # reachable, and SNARE_EARLY=0 could only switch it off, never reverse it.
  #
  # It is also the inverse of the lurch most people mean by "Dilla". On Donuts
  # and Ruff Draft the snare is the element that drags, against hats that hold
  # steady; Charnas's thesis is that the feels *conflict*, and which layer lags
  # is what distinguishes one groove from another. So the polarity is a profile.
  #
  # Whole ticks throughout, because the MPC3000 runs at 96 PPQ and its nudge tool
  # can only land on those positions — a fractional offset is one the hardware
  # this models could never have produced.
  GROOVE_FEELS = {
    # Unchanged from the inline values, so nothing moves unless asked.
    boom_bap: { snare: -4, snare_plain: -3, clap: -4, kick_anchor: 1, kick: 3,
                hat: 2, hat_up: 3, ghost: 1, bass: 0,
                keys: 0, lead: 0 },

    # Snare behind, hats holding the grid. The hats are the reference the snare
    # is late against — drag them too and the whole bar just sounds slow rather
    # than lurching.
    dilla_drag: { snare: 4, snare_plain: 3, clap: 4, kick_anchor: -1, kick: 0,
                  hat: 0, hat_up: 1, ghost: 2, bass: -2,
                  keys: 5, lead: 7 },

    # Camel: the kick displaced off the grid rather than merely late, hats a
    # touch ahead so the top stutters against a snare that drags further than
    # Dilla's.
    #
    # Not the widest spread — boom_bap is, at 51.5ms against Camel's 44.2 at
    # 85 BPM, because its snare is pushed nearly 30ms while its kick drags 22.
    # What separates Camel is the *direction*: everything below the hats leans
    # late while the hats lean early, so the top and bottom of the kit pull
    # apart. boom_bap splits snare-against-everything; Camel splits
    # hats-against-everything, and that is what reads as broken rather than
    # merely swung.
    camel: { snare: 5, snare_plain: 4, clap: 5, kick_anchor: 2, kick: 4,
             hat: -1, hat_up: 0, ghost: 3, bass: 2,
             keys: 6, lead: 8 },
  }.freeze

  # dilla_drag, not boom_bap.
  #
  # ENV_AND_RENDER.md listed the old default under "a default that surprises",
  # and it was the plainest one there: an engine named for Dilla did not apply
  # the Dilla microtiming unless a knob was set, so every render anyone made
  # without reading that document came out boom-bap — snare four ticks EARLY
  # where the whole point is four ticks late. The table existed, was correct,
  # and was reached by nobody.
  #
  # GROOVE_FEEL still takes boom_bap and camel; what changed is which one you
  # get for free.
  def groove_feel
    key = ENV.fetch("GROOVE_FEEL", "dilla_drag").to_s.downcase.to_sym
    GROOVE_FEELS.fetch(key, GROOVE_FEELS[:dilla_drag])
  end

  def role_timing_offset(role, beat_p, _bar, _step)
    return 0.0 unless enabled?
    tick = beat_p / 96.0
    feel = groove_feel
    case role.to_sym
    when :snare
      return 0.0 if ENV["SNARE_EARLY"] == "0"
      tick * (pocket_dna? ? feel[:snare] : feel[:snare_plain])
    when :clap
      ENV["SNARE_EARLY"] == "0" ? 0.0 : tick * feel[:clap]
    when :kick_anchor, :kick_sync, :kick
      return 0.0 if ENV["KICK_LATE"] == "0"
      # Outside pocket_dna the kick stayed on the grid in every feel; keeping
      # that, so this switch changes the lean and not how much is quantized.
      return 0.0 unless pocket_dna?

      tick * (role.to_sym == :kick_anchor ? feel[:kick_anchor] : feel[:kick])
    when :hat, :hat_down, :hat_up, :open
      return 0.0 if ENV["HATS_LATE"] == "0"
      tick * (role.to_sym == :hat_up ? feel[:hat_up] : feel[:hat])
    when :ghost
      tick * feel[:ghost]
    when :pad, :ep, :keys, :chord
      # The whole harmonic layer was pinned to the grid while the rhythm section
      # leaned around it: at 88 BPM in dilla_drag the snare sat +28.4 ms and the
      # bass -14.2, and pads, EPs and leads all sat at exactly 0.
      #
      # That is backwards for this music. On a Dilla or D'Angelo record the keys
      # are the *latest* thing in the bar — later than the dragged snare — which
      # is most of why the harmony sounds unhurried over a groove that is not.
      # The drums establish the time and the chords refuse to hurry to it.
      return 0.0 if ENV["KEYS_FEEL"] == "0"

      tick * feel.fetch(:keys, 0)
    when :lead, :scale_lead, :xlead
      # Further back still, so the three layers form a hierarchy rather than two
      # positions: bass ahead, drums leaning, keys behind, lead behind the keys.
      return 0.0 if ENV["KEYS_FEEL"] == "0"

      tick * feel.fetch(:lead, 0)
    when :lead_extra
      # The lead is built on top of a pad event and inherits that event's time,
      # so it has already taken the :keys offset by the time it is placed. This
      # returns only the difference, which lets the table above stay absolute
      # (keys 5, lead 7 means the lead lands at 7, not at 12).
      return 0.0 if ENV["KEYS_FEEL"] == "0"

      tick * (feel.fetch(:lead, 0) - feel.fetch(:keys, 0))
    when :bass
      # The bass was the one voice with no entry here, so it fell to the `else`
      # and stayed pinned to the grid in every feel. That made a groove switch a
      # drums-against-a-metronome change rather than a change in how the band
      # sits together.
      #
      # It is the D'Angelo point. On Voodoo the drums drag and the bass does not
      # follow them down — Pino sits fractionally ahead of Questlove, and the
      # pocket is the *distance between them*, not either one's distance from a
      # click. A dragging snare over a locked bass only widens that gap by the
      # snare's own lateness; moving the bass the other way widens it by both.
      #
      # boom_bap stays at 0, which is exactly what the `else` returned, so
      # nothing moves unless the feel is switched.
      return 0.0 if ENV["BASS_FEEL"] == "0"

      tick * feel.fetch(:bass, 0)
    else
      0.0
    end
  end

  def hat_micro_delay_sec(bar, step, beat_p)
    return 0.0 unless enabled?
    return 0.0 if ENV["HAT_MICRO"] == "0"
    rng = Random.new((bar * 313) + (step * 17) + 42)
    # Freehand hats: slightly wider when pocket DNA is on.
    hi = pocket_dna? ? 0.0045 : 0.0022
    raw = rng.rand(0.0004..hi)
    tick_sec = beat_p / 96.0
    return raw if tick_sec <= 0
    [(raw / tick_sec).round, 1].max * tick_sec
  end

  # Real finger-drumming occasionally misses a kick too, not just hats --
  # rare (~3%) and never the downbeat/anchor.
  def kick_should_drop?(bar, step)
    return false unless enabled? && pocket_dna?
    return false if ENV["KICK_DROP"] == "0"
    return false if step.zero?
    Random.new((bar * 971) + (step * 61) + 337 + render_seed).rand < 0.03
  end

  # Documented Dilla technique: kick doubles that sit off the grid -- a
  # quick, quieter second hit close behind the main kick, not a clean
  # quantized repeat. Whole-tick offset (2-4 ticks), same 96-PPQ
  # authenticity as the rest of the timing system.
  def kick_double_offset_ticks(bar, step)
    return unless enabled? && pocket_dna?
    return if ENV["KICK_DOUBLE"] == "0"
    return unless Random.new((bar * 883) + (step * 47) + 521 + render_seed).rand < 0.05
    [2, 3, 4].sample(random: Random.new((bar * 601) + (step * 29) + 71 + render_seed))
  end

  # A ghost note immediately before the backbeat snare -- a quieter
  # pickup hit distinct from the scattered ghost phrase pool, which
  # tends to be a genuine pre-hit ornament rather than mid-bar filler.
  def snare_prehit_ghost?(bar, step)
    return false unless enabled? && pocket_dna?
    return false if ENV["SNARE_PREHIT_GHOST"] == "0"
    Random.new((bar * 449) + (step * 71) + 883 + render_seed).rand < 0.08
  end

  # A finger-drummer occasionally misses a hat, or leaves space on purpose —
  # a pattern that never drops a single 16th over 32 bars reads as sequenced.
  # Rare (~4%), deterministic per bar/step, and never the downbeat.
  def hat_should_drop?(bar, step, section: nil)
    return false unless enabled? && pocket_dna?
    return false if ENV["HAT_DROP"] == "0"
    return false if step.zero?
    prob = 0.04 * SECTION_JITTER_MUL.fetch(section.to_s.to_sym, 1.0)
    Random.new((bar * 787) + (step * 53) + 191 + render_seed).rand < prob
  end

  def freehand_kick_sec(bar, step, beat_p)
    return 0.0 unless pocket_dna? && ENV.fetch("KICK_FREEHAND", "1") != "0"
    # Unquantized kick nudges (time-shift feel) — cyclic by bar/step.
    tick = beat_p / 96.0
    seed = (bar % 4) * 97 + step * 31 + 19
    ticks = POCKET_TICKS[:kick_sync]
    raw = ticks.begin + (seed % (ticks.end - ticks.begin + 1))
    raw * tick * (step.zero? ? 0.35 : 1.0)
  end

  # A flam is a fixed number of MPC ticks, not a fixed ms value -- a fixed-ms
  # constant means the same flam represents a different (and at fast tempos,
  # audibly wrong) fraction of a beat as BPM changes. 2 ticks was the
  # previous ~0.0012s at a typical ~90 BPM (tick ~6.9ms there); express it
  # as 2 ticks directly so it scales correctly with tempo.
  def flam_offset_sec(beat_p = nil)
    return 0.0 unless enabled? && ENV["FLAM"] != "0"
    return 0.0012 unless beat_p&.positive?
    2 * (beat_p / 96.0)
  end

  def kick_snare_swap?
    enabled? && ENV["KICK_SNARE_SWAP"] == "1"
  end

  def groove_lock_melody?
    ENV["GROOVE_LOCK"].to_s.downcase == "kick"
  end

  def melody_time_offset(bar, step, beat_p)
    return 0.0 unless groove_lock_melody?
    step_p = beat_p / 4.0
    rng = Random.new(bar * 71 + step)
    center = step_p * 0.10
    center + gaussian_jitter(rng, step_p * 0.45)
  end

  def trap_morph_hat_density(bar, n_bars, base_steps)
    return base_steps unless enabled? && ENV["TRAP_MORPH"] == "1"
    progress = bar.to_f / [n_bars - 1, 1].max
    extra = (0..15).select { |s| s.odd? && Random.new(bar * 3).rand < (0.15 + progress * 0.55) }
    (base_steps + extra).uniq.sort
  end

  def euclidean(pulses, steps, rotation: 0)
    return [] if steps <= 0 || pulses <= 0
    bucket = 0.0
    out = []
    steps.times do |i|
      bucket += pulses.to_f / steps
      out << ((i + rotation) % steps) if bucket >= 1.0
      bucket -= 1.0 if bucket >= 1.0
    end
    out.uniq.sort
  end

  def prime_poly_steps(_bar)
    return [] unless enabled? && ENV["PRIME_GRID"] == "1"
    PRIMES.flat_map { |p| (0...16).step(p).map { |s| s % 16 } }.uniq.sort
  end

  # A cycle that does not reset at the bar line.
  #
  # Everything else in this file lands inside one 16-step bar and starts over:
  # euclidean(5, 16) is a 16-step figure, prime_poly_steps folds its primes back
  # with `s % 16`, and drum_pattern_pick returns a per-bar list. That is a
  # cross-rhythm INSIDE a bar, which is not the same thing as a polymeter, and
  # the difference is audible -- a figure that resets every bar agrees with the
  # downbeat every bar, however uneven it is within one.
  #
  # This indexes the pattern by the GLOBAL step instead, so an 11-step cycle
  # against a 16-step bar precesses and only comes back round to the downbeat
  # after lcm(11, 16) = 176 steps, or 11 bars.
  #
  # The gap this fills was a claim rather than a feature. producer_dna.rb's
  # flylo_cosmogramma preset says its hats are "a 3-step cycle against a 16-step
  # bar, so they only agree with the downbeat once every three bars" -- but its
  # pool holds one entry, [0, 3, 6, 9, 12, 15], so drum_pattern_pick returns the
  # identical list for every bar and the hats hit the downbeat in all of them.
  # That preset is left alone (nothing moves unless asked); POLYMETER_HATS=3 is
  # what the comment describes.
  #
  # pulses defaults to ONE hit per cycle, not one per position in it. "A 3-step
  # cycle" is a hit every third step -- [0, 3, 6, 9, ...] -- and the first cut of
  # this defaulted to `(0...cycle).to_a`, i.e. every residue, which matches every
  # step and fires continuously. It looked like a working polymeter in the code
  # and was a 16th-note roll in the output.
  #
  # Give pulses to spread more than one hit across the cycle with euclidean, so
  # POLYMETER_HATS=11 POLYMETER_PULSES=7 is the 7-against-11 that IDM uses.
  #
  # Capped at cycle - 1, not at cycle. euclidean(n, n) is every position by
  # definition, so a cycle filled to its own length has no gap in it, precesses
  # against nothing and is audible only as a 16th roll -- the same output as the
  # default bug above, reached by asking for too many pulses instead of too few.
  # One gap is the minimum that makes a cycle a cycle.
  def polymeter_steps(bar, cycle:, pulses: nil, steps_per_bar: 16)
    return [] if cycle.to_i < 2 || steps_per_bar.to_i < 1

    cycle = cycle.to_i
    n = pulses.to_i.clamp(0, cycle - 1)
    hits = n > 1 ? euclidean(n, cycle) : [0]
    return [] if hits.empty?

    base = bar.to_i * steps_per_bar
    (0...steps_per_bar).select { |s| hits.include?((base + s) % cycle) }
  end

  # POLYMETER_HATS=<cycle>, optionally POLYMETER_PULSES=<n>. Off unless set,
  # like every other grid switch here.
  def polymeter_hat_steps(bar)
    return [] unless enabled?

    cycle = ENV["POLYMETER_HATS"].to_i
    return [] unless cycle > 1

    polymeter_steps(bar, cycle:, pulses: ENV["POLYMETER_PULSES"])
  end

  # A lazily-initialized module ivar, not a `NAME = {}` constant -- that
  # constant-literal pattern is exactly what an automated formatting pass
  # kept matching and appending .freeze to (three separate times tonight),
  # each time breaking every render that touches the Markov drum path with
  # FrozenError. This shape isn't a hash-literal-assigned-to-constant, so
  # there's nothing for that kind of blanket rule to catch.
  def markov_cache
    @markov_cache ||= {}
  end

  def markov_steps(bar, role, pool)
    flat = pool.flatten.uniq
    return flat if flat.empty?
    return flat unless enabled? && ENV["MARKOV_DRUMS"] != "0"
    key = [role, flat.hash].join(":")
    matrix = markov_cache[key] ||= build_markov_from_pool(flat)
    rng = Random.new((bar * 1009) + role.hash.abs)
    seed_step = flat[bar % flat.length]
    extra = matrix.dig(seed_step)&.sample(random: rng) || flat[(bar + 1) % flat.length]
    (flat + [seed_step, extra]).uniq.sort
  end

  def build_markov_from_pool(flat)
    transitions = Hash.new { |h, k| h[k] = [] }
    flat.each_with_index do |step, i|
      transitions[step] << flat[(i + 1) % flat.length]
      transitions[step] << flat[(i + 2) % flat.length]
    end
    transitions.transform_values(&:uniq)
  end

  def apply_event_timing!(t, role:, beat_p:, bar:, step:, bpm: 90, section: nil)
    t + role_timing_offset(role, beat_p, bar, step) +
      swing_jitter_ms(bpm, step, bar, role:, section:) +
      (role.to_s.start_with?("hat") ? hat_micro_delay_sec(bar, step, beat_p) : 0.0) +
      (%i[kick kick_anchor kick_sync].include?(role.to_sym) ? freehand_kick_sec(bar, step, beat_p) : 0.0)
  end

  # --- Simplicity: sparse rotating phrases ---

  def pocket_kicks(bar)
    phrases = kick_phrases
    return phrases[0] unless pocket_dna?
    phrase = phrases[(bar + render_seed) % phrases.length]
    # Breathing bar: ~22% chance, seeded per bar+render (reproducible within
    # a render, but not the same every render), drop to a sparser shape
    # drawn from a small pool instead of always the same [0, 10].
    if ENV.fetch("POCKET_SIMPLE", "1") != "0" && Random.new((bar * 733) + 41 + render_seed).rand < 0.22
      # A slice of those breathing bars go all the way to silence -- a real
      # producer choice, not just reduced density every time.
      if ENV["POCKET_KICK_SILENCE"] != "0" && Random.new((bar * 457) + 233 + render_seed).rand < 0.12
        return []
      end
      sparse = kick_sparse_phrases
      return sparse[Random.new((bar * 911) + 17 + render_seed).rand(sparse.length)]
    end
    phrase
  end

  # Rush is a loosening device -- more of it where a section is meant to
  # feel open/unlocked (breakdown, development/bridge), rarer where it
  # should feel locked in (e_major_third_rise/peak/hook/recap).
  SNARE_RUSH_PROB_BY_SECTION = {
    breakdown: 0.20, development: 0.18, bridge: 0.18,
    e_major_third_rise: 0.04, peak: 0.04, hook: 0.04, recapitulation: 0.05
  }.freeze

  def pocket_snares_hard(bar, section: nil)
    hard = snare_hard_steps
    return hard unless pocket_dna?
    return hard if ENV["POCKET_RUSH"] == "0" || industrial_pocket?
    prob = SNARE_RUSH_PROB_BY_SECTION.fetch(section.to_s.to_sym, 0.12)
    Random.new((bar * 619) + 83 + render_seed).rand < prob ? snare_rush_steps : hard
  end

  def pocket_snares_ghost(bar)
    return [] unless pocket_dna?
    return [] if ENV["POCKET_GHOSTS"] == "0"
    ghosts = snare_ghost_phrases
    ghosts[(bar + render_seed) % ghosts.length]
  end

  def pocket_hats(bar)
    phrases = hat_phrases
    phrases[(bar + render_seed) % phrases.length]
  end

  def pocket_open_hat?(bar)
    pocket_dna? && (bar % 8) == 7 && ENV.fetch("POCKET_OPEN_HAT", "1") != "0"
  end

  # --- Sample choice ---

  def kick_sample_key(bar, step)
    return :kick unless pocket_dna?
    # Alternate kicks (different pitch/body) — common MPC finger-drum habit.
    cycle = KICK_SAMPLE_CYCLE
    idx = (bar + (step.zero? ? 0 : 1) + step / 4) % cycle.length
    # Prefer tighter body on downbeat, alternate on offbeats.
    step.zero? ? :kick : cycle[idx]
  end

  def snare_sample_key(ghost:)
    ghost ? :ghost : :snare
  end

  def apply_pocket_place(t, role:, beat_p:, bar:, step:, bpm:, section: nil)
    apply_event_timing!(t, role:, beat_p:, bar:, step:, bpm:, section:)
  end
end
