# frozen_string_literal: true
#
# Synthesised percussion one-shots: rim, clap, tabla, tambourine, woodblock, agogo.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def schedule_eclectic_percussion!(events, duration, beat_p, bar_p, cfg, n_bars)
  rng = Random.new(stable_hash(cfg[:track].to_s) + 909)
  step_p = beat_p / 4.0
  family = cfg[:style_family]

  # Polyrhythm 5:4 layer
  poly5 = bar_p / 5.0
  (0...(duration / poly5).floor).each do |i|
    next if family != :flylo && i % 5 != 0
    t = (i * poly5).round(6)
    events[:poly5] ||= []
    events[:poly5] << [t, (0.12 + 0.06 * Math.sin(i * 0.9)).clamp(0.06, 0.28), :rim]
  end

  # Clap on 2&4 is scheduled in dilla_schedule (snare unison) when BACKBEAT_CLAP=1.
  unless backbeat_clap_enabled?
    (0...(duration / bar_p).floor).each do |bar|
      base = bar * bar_p
      density = section_density(bar, n_bars, chord_phases: @chord_phases, pad_chords: @progression_chords,
                                chord_bars: @render_chord_bars, phrase_bars: @render_phrase_bars)
      next if density < 0.5
      [1, 3].each do |beat|
        t = (base + beat * beat_p).round(6)
        events[:clap] ||= []
        events[:clap] << [t, dilla_velocity(0.42 * density, bar, beat, spread: 0.08), :clap]
      end
    end
  end

  # Rim / brush / woodblock / agogo / glitch / tabla / tambourine — both
  # style families now get the eclectic layer (was FlyLo-only, which left
  # :dilla-family tracks — most of STREAM_TRACKS — with almost nothing
  # here beyond sparse woodblock/agogo; real critique was "not intricate
  # or dynamic"). :dilla family gets a calmer rate, not zero.
  (0...(duration / step_p).floor).each do |i|
    bar = (i / 16).floor
    density = section_density(bar, n_bars, chord_phases: @chord_phases, pad_chords: @progression_chords,
                              chord_bars: @render_chord_bars, phrase_bars: @render_phrase_bars)
    t = (i * step_p).round(6)
    r = rng.rand
    if family == :flylo || family == :dilla
      wild = family == :flylo ? 1.0 : 0.6
      events[:rim] ||= []
      events[:rim] << [t, dilla_velocity(0.28, bar, i % 16, spread: 0.1), 0.35] if r < 0.04 * density * wild
      events[:glitch] ||= []
      events[:glitch] << [t + rng.rand * step_p * 0.5, dilla_velocity(0.35, bar, i, spread: 0.12), :ind_stab] if r < 0.02 * wild
      events[:tabla] ||= []
      events[:tabla] << [t, dilla_velocity(0.32, bar, i, spread: 0.15)] if r < 0.018 * density * wild
      events[:tambourine] ||= []
      events[:tambourine] << [t, dilla_velocity(0.22, bar, i, spread: 0.1)] if i.even? && r < 0.08 * density * wild
    end
    events[:woodblock] ||= []
    events[:woodblock] << [t, dilla_velocity(0.2, bar, i, spread: 0.06)] if r < 0.01
    events[:agogo] ||= []
    events[:agogo] << [t, dilla_velocity(0.18, bar, i, spread: 0.05)] if r < 0.008
  end

  # Wall-of-noise bar every 32
  (0...(duration / bar_p).floor).each do |bar|
    next unless bar.positive? && bar % 32 == 31
    base = bar * bar_p
    16.times do |step|
      t = (base + step * step_p).round(6)
      events[:glitch] ||= []
      events[:glitch] << [t, dilla_velocity(0.55, bar, step, spread: 0.05), :ind_clap]
    end
  end

  # Trigger-finger miss (intentional dropout)
  %i[kick snare hat].each do |key|
    next unless events[key]
    events[key] = events[key].reject { |hit| rng.rand < 0.04 } if family == :flylo
  end

  events
end

def synth_rim_sample
  len = (0.06 * SAMPLE_RATE).round
  rng = Random.new(42)
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 55.0)
    out[i] = env * (rng.rand * 2.0 - 1.0) * 0.7
  end
  out
end

def synth_clap_sample
  len = (0.14 * SAMPLE_RATE).round
  rng = Random.new(17)
  out = Array.new(len, 0.0)
  3.times do |layer|
    offset = (layer * 0.003 * SAMPLE_RATE).round
    len.times do |i|
      next if i < offset
      t = (i - offset).to_f / SAMPLE_RATE
      env = Math.exp(-t * (30.0 + layer * 8))
      out[i] += env * (rng.rand * 2.0 - 1.0) * (0.35 - layer * 0.08)
    end
  end
  peak = out.map(&:abs).max || 1.0
  out.map { |s| s / [peak, 0.01].max * 0.85 }
end

def synth_tabla_sample
  len = (0.22 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 18.0) * (1.0 - Math.exp(-t * 120.0))
    f = 180.0 + 90.0 * Math.exp(-t * 40.0)
    out[i] = env * Math.sin(2 * Math::PI * f * t) * 0.6
  end
  out
end

# Every voice below used to be one exp(-t*k) shape at a different rate —
# correct that a rim, a woodblock and an agogo bell decay at different
# SPEEDS, wrong that they decay the same SHAPE. Real struck objects
# don't share one physical behavior; each gets the envelope its actual
# physical characteristics: a woodblock has ~zero ring (transient click,
# then silence), a tambourine's metal jingles shimmer well after the
# hand-hit decays (two-stage, not one), a bell's higher partials lose
# energy faster than its fundamental (independent per-partial decay).
def synth_tambourine_sample
  len = (0.16 * SAMPLE_RATE).round
  rng = Random.new(88)
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    hit = Math.exp(-t * 60.0)
    shimmer = Math.exp(-t * 9.0) * 0.35
    out[i] = (rng.rand * 2.0 - 1.0) * (hit * 0.5 + shimmer)
  end
  out
end

def synth_woodblock_sample
  len = (0.04 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    click = t < 0.0015 ? 1.0 : 0.0
    body = Math.exp(-t * 140.0) * Math.sin(2 * Math::PI * 1200.0 * t)
    out[i] = click * 0.4 + body * 0.55
  end
  out
end

def synth_agogo_sample
  len = (0.12 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    fundamental = Math.exp(-t * 16.0) * Math.sin(2 * Math::PI * 660.0 * t)
    overtone = Math.exp(-t * 34.0) * Math.sin(2 * Math::PI * 990.0 * t)
    out[i] = (fundamental * 0.5 + overtone * 0.5) * 0.45
  end
  out
end
