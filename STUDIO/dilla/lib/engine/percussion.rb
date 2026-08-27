# frozen_string_literal: true
#
# Synthesised percussion one-shots: rim, clap, tabla, tambourine, woodblock, agogo.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Percussion belongs to the idiom, not to every track alike.
#
# woodblock and agogo fired OUTSIDE the family check, at a flat probability, on
# every step of every track in the catalogue. A Detroit kit, an LA kit and a
# techno kit all got the same woodblock-and-agogo sprinkle laid over them, and
# the operator heard exactly that -- "the redundant drum beat with agogo, not
# the new ones we designed". The feels were driving kicks, snares, hats and
# ghosts correctly; this layer was painting over the difference.
#
# Each feel names its own vocabulary and rate. 0 means the instrument is not
# part of that idiom: techno has no agogo, Detroit has no glitch stab. A feel
# with no entry keeps the old rates, so nothing that already sounded right
# changes.
# The vocabulary is what these producers actually played, and it is short.
#
# A Dilla or Slum Village kit is kick, snare, rimshot, clap, closed and open
# hat, and ghost snares. That is the whole list. Tambourine, agogo, woodblock
# and tabla are general-MIDI world percussion; neither Dilla nor the LA beat
# scene used them, and sprinkling them over a Detroit pattern is what made a
# demo full of new drum designs still sound like the old one.
#
# A first pass removed agogo and woodblock and left tambourine at 0.055, which
# was the same mistake wearing a different instrument. Everything outside the
# list is 0 now.
#
# rim stays because a rimshot is a hiphop sound and Dilla used one constantly.
# glitch stays on the LA and techno feels only, where a stab is idiomatic;
# Detroit gets none.
# Kick, snare/clap, hi-hat, ghost. That is the kit.
#
# Operator direction, and it is what the records are: a Dilla or Slum Village
# bar has a kick, a snare or clap, closed and open hats, and ghost snares
# underneath. Nothing else. Tambourine, agogo, woodblock and tabla are
# general-MIDI world percussion nobody in this lineage played, and rim and
# glitch are the same argument one step quieter -- an ornament arriving on top
# of a groove that should be carrying itself.
#
# Every rate is 0 for these three feels, so the eclectic layer contributes
# nothing and the drums are the drums. Drive and groove come from the kit and
# the microtiming, not from adding instruments. Any feel not listed keeps the
# old rates, so nothing else in the catalogue changes.
PERC_VOCAB = {
  detroit_stumble:   { rim: 0.0, glitch: 0.0, tabla: 0.0, tambourine: 0.0, woodblock: 0.0, agogo: 0.0 },
  la_beat_scene:     { rim: 0.0, glitch: 0.0, tabla: 0.0, tambourine: 0.0, woodblock: 0.0, agogo: 0.0 },
  techno_drive: { rim: 0.0, glitch: 0.0, tabla: 0.0, tambourine: 0.0, woodblock: 0.0, agogo: 0.0 }
}.freeze

# The fallbacks are 0, not the old rates.
#
# Scoping this to the new feels only was too narrow: every other track in the
# catalogue -- which is most of them, since the morph is opt-in -- kept getting
# agogo, woodblock, tambourine and tabla sprinkled over it. The instruction was
# not "use fewer of these on the new patterns", it was that Dilla and the LA beat
# scene never played them. So they are off everywhere, and a feel would have to
# name a rate explicitly in PERC_VOCAB to get one back.

# The morph changes the feel per bar, so the ornaments have to follow it or the
# kit arrives in techno while the percussion is still in Detroit.
def perc_rate(feel, bar, instrument, fallback)
  active = (drum_morph_feel(bar, :perc) || feel)
  table = PERC_VOCAB[active&.to_sym]
  return fallback unless table

  table.fetch(instrument, 0.0)
end

def schedule_eclectic_percussion!(events, duration, beat_p, bar_p, cfg, n_bars)
  rng = Random.new(stable_hash(cfg[:track].to_s) + 909)
  step_p = beat_p / 4.0
  family = cfg[:style_family]
  feel = cfg[:feel]

  # Polyrhythm 5:4 layer
  poly5 = bar_p / 5.0
  (0...(duration / poly5).floor).each do |i|
    next if family != :wonky && i % 5 != 0
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
  # style families now get the eclectic layer (was Wonky-only, which left
  # :dilla-family tracks — most of STREAM_TRACKS — with almost nothing
  # here beyond sparse woodblock/agogo; real critique was "not intricate
  # or dynamic"). :dilla family gets a calmer rate, not zero.
  (0...(duration / step_p).floor).each do |i|
    bar = (i / 16).floor
    density = section_density(bar, n_bars, chord_phases: @chord_phases, pad_chords: @progression_chords,
                              chord_bars: @render_chord_bars, phrase_bars: @render_phrase_bars)
    t = (i * step_p).round(6)
    r = rng.rand
    if family == :wonky || family == :dilla
      wild = family == :wonky ? 1.0 : 0.6
      events[:rim] ||= []
      events[:rim] << [t, dilla_velocity(0.28, bar, i % 16, spread: 0.1), 0.35] if r < perc_rate(feel, bar, :rim, 0.04) * density * wild
      events[:glitch] ||= []
      events[:glitch] << [t + rng.rand * step_p * 0.5, dilla_velocity(0.35, bar, i, spread: 0.12), :ind_stab] if r < 0.02 * wild
      events[:tabla] ||= []
      events[:tabla] << [t, dilla_velocity(0.32, bar, i, spread: 0.15)] if r < perc_rate(feel, bar, :tabla, 0.0) * density * wild
      events[:tambourine] ||= []
      events[:tambourine] << [t, dilla_velocity(0.22, bar, i, spread: 0.1)] if i.even? && r < perc_rate(feel, bar, :tambourine, 0.0) * density * wild
    end
    events[:woodblock] ||= []
    events[:woodblock] << [t, dilla_velocity(0.2, bar, i, spread: 0.06)] if r < perc_rate(feel, bar, :woodblock, 0.0)
    events[:agogo] ||= []
    events[:agogo] << [t, dilla_velocity(0.18, bar, i, spread: 0.05)] if r < perc_rate(feel, bar, :agogo, 0.0)
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
    events[key] = events[key].reject { |hit| rng.rand < 0.04 } if family == :wonky
  end

  events
end

# Struck objects, built the way struck objects actually behave.
#
# Every voice below used to be white noise or plain sines under one exponential
# decay, and that is audibly not what a drum is. Three things separate a
# synthesised hit from a sampled one, and all three are cheap to fix:
#
#   BAND LIMITING. Raw noise and raw squares carry energy past Nyquist, which
#   folds back down as inharmonic aliasing. It is the single most "cheap
#   digital" artefact there is. Everything here is filtered.
#
#   INHARMONICITY. A struck bar or bell rings at ratios that are NOT integers --
#   a real cowbell is nothing like 1:1.5, and an agogo at exactly 3:2 reads as
#   two oscillators rather than one object. The ratio tables below are
#   stretched deliberately, and higher modes decay faster, which is the physics:
#   short wavelengths lose energy to the mounting first.
#
#   A STRIKE. Every real percussion hit begins with a broadband contact noise
#   before the body speaks. Without it a modal ring sounds like a synth pad
#   with a fast attack, because that is exactly what it is.
#
# Deterministic per voice: the seeds are fixed, so a kit is the same kit twice.

# Two-pole resonant bandpass, transposed direct form II. Used to band-limit
# noise into a formant rather than letting it alias across the whole spectrum.
def perc_bandpass(sig, freq, q)
  w = 2.0 * Math::PI * freq / SAMPLE_RATE
  alpha = Math.sin(w) / (2.0 * q)
  b0 = alpha
  b2 = -alpha
  a0 = 1.0 + alpha
  a1 = -2.0 * Math.cos(w)
  a2 = 1.0 - alpha
  x1 = x2 = y1 = y2 = 0.0
  sig.map do |x|
    y = (b0 / a0) * x + (b2 / a0) * x2 - (a1 / a0) * y1 - (a2 / a0) * y2
    x2 = x1
    x1 = x
    y2 = y1
    y1 = y
    y
  end
end

# A struck body: partials at inharmonic ratios, each with its own decay.
def perc_modes(len, base, ratios, decays, amps)
  out = Array.new(len, 0.0)
  ratios.each_with_index do |r, m|
    f = base * r
    next if f >= SAMPLE_RATE * 0.45          # never place a partial past Nyquist
    d = decays[m]
    a = amps[m]
    len.times do |i|
      t = i.to_f / SAMPLE_RATE
      out[i] += a * Math.exp(-t * d) * Math.sin(2.0 * Math::PI * f * t)
    end
  end
  out
end

# Contact noise: the moment before the body speaks.
def perc_strike(len, seed, freq, q, decay, gain)
  rng = Random.new(seed)
  raw = Array.new(len) { rng.rand * 2.0 - 1.0 }
  perc_bandpass(raw, freq, q).each_with_index.map do |v, i|
    v * Math.exp(-(i.to_f / SAMPLE_RATE) * decay) * gain
  end
end

def perc_normalize(out, peak)
  m = out.map(&:abs).max || 1.0
  out.map { |s| s / [m, 1.0e-6].max * peak }
end

# Rimshot: stick on the rim, plus the shell speaking underneath it. The old
# version was noise alone, which is the "tss" half without the "tok" half --
# the pitched shell mode is what makes it read as a drum being hit.
def synth_rim_sample
  len = (0.07 * SAMPLE_RATE).round
  shell = perc_modes(len, 430.0, [1.0, 2.61, 4.19], [58.0, 96.0, 150.0], [0.60, 0.26, 0.12])
  stick = perc_strike(len, 42, 2600.0, 1.1, 130.0, 0.75)
  perc_normalize(shell.each_with_index.map { |v, i| v + stick[i] }, 0.78)
end

# Hand clap: several pairs of hands, not one.
#
# The old version fired three noise bursts 3 ms apart, which is inside the ear's
# fusion window -- they arrive as a single transient, so it sounded like a snare
# with no tone rather than a clap. Real claps in a room are 15-30 ms apart,
# unevenly, and the last one is followed by the room. That spacing IS the sound.
# Band-limited around 1.6 kHz because that is where hands live; white noise
# reads as static.
def synth_clap_sample
  len = (0.34 * SAMPLE_RATE).round
  rng = Random.new(17)
  out = Array.new(len, 0.0)
  # four hits, unevenly spaced, each slightly quieter and duller than the last
  [[0.0, 1.0, 1750.0], [0.017, 0.86, 1650.0], [0.036, 0.72, 1520.0], [0.058, 0.55, 1400.0]]
    .each_with_index do |(delay, amp, fc), n|
    off = (delay * SAMPLE_RATE).round
    burst_len = len - off
    next if burst_len <= 0
    raw = Array.new(burst_len) { rng.rand * 2.0 - 1.0 }
    perc_bandpass(raw, fc, 1.5).each_with_index do |v, i|
      out[off + i] += v * Math.exp(-(i.to_f / SAMPLE_RATE) * (68.0 + n * 6.0)) * amp
    end
  end
  # the room the hands are in: a slower, darker tail under all of it
  tail_raw = Array.new(len) { rng.rand * 2.0 - 1.0 }
  perc_bandpass(tail_raw, 1150.0, 0.8).each_with_index do |v, i|
    out[i] += v * Math.exp(-(i.to_f / SAMPLE_RATE) * 13.0) * 0.22
  end
  perc_normalize(out, 0.85)
end

# Tabla. Nearly the only drum with a definite pitch, because the black tuning
# paste loads the centre of the head so its modes fall close to whole-number
# ratios instead of the inharmonic mess an undamped membrane produces. Close,
# not exact -- the slight stretch below is the difference between a tabla and a
# sine with a pitch envelope, which is what this was. The pitch drop stays: that
# is the palm on the head.
def synth_tabla_sample
  len = (0.30 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  ratios = [1.0, 2.01, 3.04, 4.09]
  decays = [13.0, 20.0, 30.0, 44.0]
  amps   = [0.60, 0.30, 0.16, 0.08]
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    bend = 1.0 + 0.55 * Math.exp(-t * 45.0)      # palm pressure releasing
    attack = 1.0 - Math.exp(-t * 160.0)
    ratios.each_with_index do |r, m|
      f = 186.0 * r * bend
      next if f >= SAMPLE_RATE * 0.45
      out[i] += amps[m] * Math.exp(-t * decays[m]) * attack * Math.sin(2.0 * Math::PI * f * t)
    end
  end
  strike = perc_strike(len, 71, 1900.0, 1.3, 190.0, 0.30)
  perc_normalize(out.each_with_index.map { |v, i| v + strike[i] }, 0.72)
end

# No voice below is one exp(-t*k) shape at a different rate. That shape is
# correct that a rim, a woodblock and an agogo bell decay at different
# SPEEDS, and wrong that they decay the same SHAPE. Real struck objects
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
