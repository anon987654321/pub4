# frozen_string_literal: true

# Moog DFAM semantics from the RG-69 lo-fi drum machine reference:
# dual-osc FM percussion, 8-step pitch/velocity sequencer, resonant LP decay.
module DfamEngine
  DEFAULT_PATCH = {
    osc1_hz: 80, osc2_hz: 120, fm_pct: 30, noise_pct: 20,
    filter_hz: 2000, res_pct: 40, decay_ms: 200
  }.freeze

  DEFAULT_PATTERN = {
    pitch: [50, 30, 60, 20, 55, 35, 65, 25],
    velocity: [80, 60, 90, 50, 85, 65, 95, 55],
  }.freeze

  STEPS = 8
  STEPS_PER_BAR = 16

  module_function

  def enabled?
    ENV["DFAM"] != "0"
  end

  def resolve_patch
    patch = DEFAULT_PATCH.dup
    patch[:osc1_hz] = env_i("DFAM_OSC1", patch[:osc1_hz])
    patch[:osc2_hz] = env_i("DFAM_OSC2", patch[:osc2_hz])
    patch[:fm_pct] = env_i("DFAM_FM", patch[:fm_pct])
    patch[:noise_pct] = env_i("DFAM_NOISE", patch[:noise_pct])
    patch[:filter_hz] = env_i("DFAM_FILTER", patch[:filter_hz])
    patch[:res_pct] = env_i("DFAM_RES", patch[:res_pct])
    patch[:decay_ms] = env_i("DFAM_DECAY", patch[:decay_ms])
    patch
  end

  def resolve_pattern(seed: nil)
    base = DEFAULT_PATTERN.transform_values(&:dup)
    rng = Random.new(seed || pattern_seed)
    base[:pitch] = base[:pitch].map { |p| (p + rng.rand(-8..8)).clamp(10, 95) }
    base[:velocity] = base[:velocity].map { |v| (v + rng.rand(-10..10)).clamp(35, 100) }
    if (raw = ENV["DFAM_PATTERN"])
      parts = raw.split(",").map(&:strip)
      if parts.length == STEPS * 2
        base[:pitch] = parts.first(STEPS).map { |x| x.to_i.clamp(0, 100) }
        base[:velocity] = parts.drop(STEPS).map { |x| x.to_i.clamp(0, 100) }
      end
    end
    base
  end

  # djb2, not String#hash.
  #
  # Ruby randomises String#hash per process -- SipHash with a key drawn at
  # startup -- so this seeded the pattern from a different number on every run
  # and the eight-step sequence was never the same twice. It reads as
  # deterministic, keyed on the track name, and is not. Twenty-six sites in
  # dilla.rb had the same fault and were corrected; this one is in a lib file
  # and was missed.
  def stable_hash(text)
    text.to_s.each_byte.reduce(5381) { |a, b| ((a * 33) + b) % 4_294_967_296 }
  end

  def pattern_seed
    track = (ENV["TRACK"] || "minor_iv_loop").to_s.downcase.tr("-", "_")
    stable_hash(track) + (@render_seed || 0)
  end

  def mix_events!(left, right, events, chunk_start, chunk_frames, sample_rate: 44_100)
    events.each do |hit|
      t, vel, pitch, _idx, patch = hit.length == 5 ? hit : (hit + [resolve_patch])
      event_frame = (t * sample_rate).round
      dur_frames = [(patch[:decay_ms] / 1000.0 * sample_rate).round, 1].max
      window = overlap_window(event_frame, dur_frames, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      f1 = patch[:osc1_hz] + pitch * 1000.0
      f2 = patch[:osc2_hz] + pitch * 1000.0
      fm_depth = patch[:fm_pct] / 100.0
      noise_amt = (patch[:noise_pct] / 100.0) * vel
      amp = vel * 0.20
      decay = patch[:decay_ms] / 1000.0
      decay_rate = 4.5 / [decay, 0.05].max
      filter_progress = 200.0 / [patch[:filter_hz], 200.0].max
      count.times do |i|
        tt = (source_offset + i).to_f / sample_rate
        env = amp * Math.exp(-tt * decay_rate)
        filter_env = Math.exp(-tt * decay_rate * (1.0 + filter_progress))
        fm = fm_depth * f2 * 0.012 * Math.sin(2 * Math::PI * f1 * tt)
        tri = (2.0 / Math::PI) * Math.asin([[-1.0, Math.sin(2 * Math::PI * f1 * tt)].max, 1.0].min)
        sq = Math.sin(2 * Math::PI * (f2 + fm) * tt).positive? ? 1.0 : -1.0
        noise = deterministic_noise(tt, t, pitch) * noise_amt
        sample = env * filter_env * (0.42 * tri + 0.38 * sq * 0.55 + 0.20 * noise)
        left[local_start + i] += sample * 0.52
        right[local_start + i] += sample * 0.48
      end
    end
  end

  def deterministic_noise(tt, t0, pitch)
    Math.sin(tt * 9_973.7 + t0 * 131.0) * Math.sin(tt * 5_731.2 + pitch * 97.0)
  end

  def overlap_window(event_frame, total_frames, chunk_start, chunk_frames)
    return if total_frames <= 0
    chunk_end = chunk_start + chunk_frames
    event_end = event_frame + total_frames
    return if event_end <= chunk_start || event_frame >= chunk_end
    local_start = [event_frame - chunk_start, 0].max
    source_offset = [chunk_start - event_frame, 0].max
    count = [total_frames - source_offset, chunk_end - (event_frame + source_offset)].min
    count = [count, chunk_frames - local_start].min
    return if count <= 0
    [local_start, source_offset, count]
  end

  def env_i(key, default)
    v = ENV[key]
    return default if v.nil? || v.empty?
    v.to_i
  end
end
