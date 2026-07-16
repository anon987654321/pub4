# frozen_string_literal: true

# Pocket, humanize, Markov drums, Euclidean/prime grids — hip-hop groove layer.
module DillaGroove
  PRIMES = [3, 5, 7, 11].freeze
  MARKOV_CACHE = {}

  module_function

  def enabled?
    ENV["GROOVE_ENGINE"] != "0"
  end

  def swing_jitter_ms(bpm, step, bar)
    return 0.0 unless enabled?
    return 0.0 if ENV["SWING_JITTER"] == "0"
    beat_ms = 60_000.0 / bpm
    tick = beat_ms / 96.0
    rng = Random.new((bar * 509) + (step * 97) + 8803)
    max_ticks = (ENV["SWING_JITTER_TICKS"] || 3).to_i
    rng.rand(-max_ticks..max_ticks) * tick / 1000.0
  end

  def role_timing_offset(role, beat_p, bar, step)
    return 0.0 unless enabled?
    case role.to_sym
    when :snare
      ENV["SNARE_EARLY"] == "0" ? 0.0 : -(beat_p / 96.0) * 2.5
    when :hat, :hat_down, :hat_up, :open
      ENV["HATS_LATE"] == "0" ? 0.0 : (beat_p / 96.0) * 1.8
    when :ghost
      0.0
    else
      0.0
    end
  end

  def hat_micro_delay_sec(bar, step, beat_p)
    return 0.0 unless enabled?
    return 0.0 if ENV["HAT_MICRO"] == "0"
    rng = Random.new((bar * 313) + (step * 17) + 42)
    rng.rand(0.0005..0.0022)
  end

  def flam_offset_sec
    enabled? && ENV["FLAM"] != "0" ? 0.001 : 0.0
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
    rng.rand(-step_p * 0.35..step_p * 0.55)
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

  def markov_steps(bar, role, pool)
    flat = pool.flatten.uniq
    return flat if flat.empty?
    return flat unless enabled? && ENV["MARKOV_DRUMS"] != "0"
    key = [role, flat.hash].join(":")
    matrix = MARKOV_CACHE[key] ||= build_markov_from_pool(flat)
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
      swing_jitter_ms(bpm, step, bar) +
      (role.to_s.start_with?("hat") ? hat_micro_delay_sec(bar, step, beat_p) : 0.0)
  end
end