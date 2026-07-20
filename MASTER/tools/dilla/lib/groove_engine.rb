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

  # Classic sparse pockets (rotate by bar). Not dense machine-gun 16ths.
  POCKET_KICK_PHRASES = [
    [0, 6, 10],
    [0, 10],
    [0, 6, 10, 13],
    [0, 3, 10],
    [0, 6, 11],
    [0, 10, 14],
    [3, 10],
    [0, 6, 9, 10],
  ].freeze
  # Dusty / Madlib-leaning: more four-on-floor anchors + late-bar push.
  POCKET_KICK_PHRASES_DUSTY = [
    [0, 4, 10],
    [0, 8, 11],
    [0, 5, 10, 14],
    [0, 4, 8, 12],
    [0, 7, 10],
    [2, 8, 12],
    [0, 4, 11],
    [0, 6, 8, 12],
  ].freeze
  # Sparse shapes for the occasional breathing bar -- real Dilla pockets
  # loosen up periodically, but never repeat the same two notes on a
  # robotic every-4th-bar wall (that's what made a "sequenced" bar).
  POCKET_KICK_SPARSE_PHRASES = [
    [0, 10],
    [6, 10],
    [0, 6],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_DUSTY = [
    [0, 8],
    [4, 12],
    [0, 4],
  ].freeze
  POCKET_SNARE_HARD = [4, 12].freeze
  # Documented Dilla off-kilter device: the backbeat snare occasionally
  # pushed a full 16th early rather than sitting on 4/12 -- a placement
  # choice, distinct from the ms-level micro-timing in role_timing_offset.
  POCKET_SNARE_RUSH = [4, 11].freeze
  POCKET_SNARE_RUSH_DUSTY = [3, 12].freeze
  POCKET_SNARE_GHOST_PHRASES = [
    [7],
    [2, 10],
    [7, 15],
    [10],
    [],
  ].freeze
  POCKET_SNARE_GHOST_PHRASES_DUSTY = [
    [6],
    [2, 6, 14],
    [6, 14],
    [14],
    [2, 10],
  ].freeze
  POCKET_HAT_PHRASES = [
    [0, 2, 4, 6, 8, 10, 12, 14],
    [0, 2, 4, 6, 8, 10, 13, 14],
    [0, 2, 4, 6, 8, 10, 12, 13, 14],
    [0, 3, 4, 6, 8, 10, 12, 14],
    [0, 2, 4, 7, 8, 10, 12, 14],
  ].freeze
  # Offbeat-biased hats (1,3,5…) — different ride from straight 8ths.
  POCKET_HAT_PHRASES_DUSTY = [
    [1, 3, 5, 7, 9, 11, 13, 15],
    [1, 3, 5, 7, 9, 11, 12, 15],
    [0, 1, 3, 5, 7, 9, 11, 13, 15],
    [1, 3, 4, 7, 9, 11, 13, 15],
    [1, 3, 5, 8, 9, 11, 13, 15],
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

  # dusty | industrial | classic
  def pocket_set
    set = ENV.fetch("POCKET_SET", "classic").to_s.downcase
    preset = ENV["DRUM_PRESET"].to_s.downcase
    return "dusty" if set == "dusty" || preset.include?("madlib")
    return "industrial" if set == "industrial" || preset.include?("industrial") || preset.include?("boom_808")

    set
  end

  def dusty_pocket? = pocket_set == "dusty"
  def industrial_pocket? = pocket_set == "industrial"

  def kick_phrases
    return POCKET_KICK_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_KICK_PHRASES_DUSTY if dusty_pocket?

    POCKET_KICK_PHRASES
  end

  def kick_sparse_phrases
    return POCKET_KICK_SPARSE_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_KICK_SPARSE_PHRASES_DUSTY if dusty_pocket?

    POCKET_KICK_SPARSE_PHRASES
  end

  def snare_rush_steps
    return POCKET_SNARE_RUSH_INDUSTRIAL if industrial_pocket?
    return POCKET_SNARE_RUSH_DUSTY if dusty_pocket?

    POCKET_SNARE_RUSH
  end

  def snare_hard_steps
    return POCKET_SNARE_HARD_INDUSTRIAL if industrial_pocket?

    POCKET_SNARE_HARD
  end

  def snare_ghost_phrases
    return POCKET_SNARE_GHOST_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_SNARE_GHOST_PHRASES_DUSTY if dusty_pocket?

    POCKET_SNARE_GHOST_PHRASES
  end

  def hat_phrases
    return POCKET_HAT_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_HAT_PHRASES_DUSTY if dusty_pocket?

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

  def swing_jitter_ms(bpm, step, bar, role: nil)
    return 0.0 unless enabled?
    return 0.0 if ENV["SWING_JITTER"] == "0"
    beat_ms = 60_000.0 / bpm
    tick_ms = beat_ms / 96.0
    rng = Random.new((bar * 509) + (step * 97) + 8803)
    max_ticks = (ENV["SWING_JITTER_TICKS"] || (pocket_dna? ? 4 : 3)).to_i
    raw = gaussian_jitter(rng, max_ticks * tick_ms / 1000.0)
    # Quantize to a whole tick -- the MPC3000's manual nudge tool (the real
    # mechanism this jitter approximates) can only land on one of 96
    # discrete positions per beat, so a fractional-tick jitter value is one
    # that could never have been produced by hand on the actual hardware.
    quantized_ticks = (raw / (tick_ms / 1000.0)).round
    (quantized_ticks * tick_ms / 1000.0) + phrase_drift_sec(bar, role: role)
  end

  # Per-role period multiplier + phase offset so kick/snare/hat drift
  # independently rather than breathing in lockstep -- this is the actual
  # core of Charnas's "Dilla Time" thesis (multiple simultaneous time-feels
  # layered against each other), not one groove with uniform noise added.
  ROLE_DRIFT_PERIOD_MUL = {
    kick: 1.0, kick_anchor: 1.0, kick_sync: 1.0,
    snare: 0.78, clap: 0.78,
    hat: 1.35, hat_down: 1.35, hat_up: 1.35, open: 1.35,
    ghost: 0.6
  }.freeze
  ROLE_DRIFT_PHASE = {
    kick: 0.0, kick_anchor: 0.0, kick_sync: 0.0,
    snare: Math::PI * 0.6, clap: Math::PI * 0.6,
    hat: Math::PI * 1.3, hat_down: Math::PI * 1.3, hat_up: Math::PI * 1.3, open: Math::PI * 1.3,
    ghost: Math::PI * 0.25
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
  def role_timing_offset(role, beat_p, bar, step)
    return 0.0 unless enabled?
    tick = beat_p / 96.0
    case role.to_sym
    when :snare
      return 0.0 if ENV["SNARE_EARLY"] == "0"
      # Early snare pushes the pocket (classic finger-drum feel).
      mul = pocket_dna? ? 4 : 3
      -(tick * mul)
    when :clap
      ENV["SNARE_EARLY"] == "0" ? 0.0 : -(tick * 4)
    when :kick_anchor, :kick_sync, :kick
      return 0.0 if ENV["KICK_LATE"] == "0"
      # Late kick vs early snare = laid-back boom-bap tension.
      mul = pocket_dna? ? (role.to_sym == :kick_anchor ? 1 : 3) : 0
      tick * mul
    when :hat, :hat_down, :hat_up, :open
      return 0.0 if ENV["HATS_LATE"] == "0"
      mul = pocket_dna? ? (role.to_sym == :hat_up ? 3 : 2) : 2
      tick * mul
    when :ghost
      tick * 1
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
    return nil unless enabled? && pocket_dna?
    return nil if ENV["KICK_DOUBLE"] == "0"
    return nil unless Random.new((bar * 883) + (step * 47) + 521 + render_seed).rand < 0.05
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
  def hat_should_drop?(bar, step)
    return false unless enabled? && pocket_dna?
    return false if ENV["HAT_DROP"] == "0"
    return false if step.zero?
    Random.new((bar * 787) + (step * 53) + 191 + render_seed).rand < 0.04
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
    return 0.0012 unless beat_p && beat_p.positive?
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

  def hat_accel_filter_hz(bar, n_bars, base_hz = 6500)
    return base_hz unless enabled? && ENV["HAT_ACCEL"] == "1"
    progress = bar.to_f / [n_bars - 1, 1].max
    (base_hz + progress * 4000).round
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

  def prime_poly_steps(bar)
    return [] unless enabled? && ENV["PRIME_GRID"] == "1"
    PRIMES.flat_map { |p| (0...16).step(p).map { |s| s % 16 } }.uniq.sort
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

  def apply_event_timing!(t, role:, beat_p:, bar:, step:, bpm: 90)
    t + role_timing_offset(role, beat_p, bar, step) +
      swing_jitter_ms(bpm, step, bar, role: role) +
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
      sparse = kick_sparse_phrases
      return sparse[Random.new((bar * 911) + 17 + render_seed).rand(sparse.length)]
    end
    phrase
  end

  def pocket_snares_hard(bar)
    hard = snare_hard_steps
    return hard unless pocket_dna?
    return hard if ENV["POCKET_RUSH"] == "0" || industrial_pocket?
    Random.new((bar * 619) + 83 + render_seed).rand < 0.12 ? snare_rush_steps : hard
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

  def hat_sample_key(open: false)
    open ? :open_hat : :hat
  end

  def apply_pocket_place(t, role:, beat_p:, bar:, step:, bpm:)
    apply_event_timing!(t, role: role, beat_p: beat_p, bar: bar, step: step, bpm: bpm)
  end
end
