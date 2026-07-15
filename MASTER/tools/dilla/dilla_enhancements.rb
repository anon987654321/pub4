# frozen_string_literal: true

# Dilla Lab enhancement layer — sonic profiles, extended harmony, eclectic drums,
# FlyLo sidechain, fugue structure, and per-style mastering. Included into dilla.rb.
module DillaEnhancements
  module_function

  SONIC_YAML = File.expand_path("radio_bergen_sonic.yml", __dir__)

  TRACK_SONIC_MAP = {
    timeless: :dilla_timeless,
    chromatic_minor_descent: :dilla_timeless,
    neo_soul: :slum_players,
    chromatic_mediant: :flylo_camel,
    chromatic_mediant_drift: :flylo_camel,
    sus_add9_ballad: :madlib_eye,
    generated_mediant: :flylo_camel,
    generated_planing: :dilla_timeless,
    generated: :dilla_timeless,
    players: :slum_players,
    fourth_third_sixth_second_turn: :dilla_timeless
  }.freeze

  FLYLO_TRACKS = %i[
    chromatic_mediant chromatic_mediant_drift sus_add9_ballad
    generated_mediant generated_polytonal generated_neapolitan
  ].freeze

  DILLA_TRACKS = %i[
    timeless chromatic_minor_descent neo_soul syncopated_slash_ninth
    chromatic_planing minor_soul_loop generated_planing generated generated_negative
  ].freeze

  MASTER_LUFS_BY_STYLE = {
    dilla: -16.0,
    flylo: -14.0,
    madlib: -15.0,
    neo_soul: -15.5,
    default: -14.0
  }.freeze

  LRA_BY_STYLE = {
    dilla: 11.0,
    flylo: 13.0,
    madlib: 12.0,
    neo_soul: 10.0,
    default: 9.0
  }.freeze

  CHORD_TEMPLATES_EXT = {
    "maj" => [0, 4, 7],
    "min" => [0, 3, 7],
    "7" => [0, 4, 7, 10],
    "maj7" => [0, 4, 7, 11],
    "m7" => [0, 3, 7, 10],
    "m9" => [0, 3, 7, 10, 2],
    "maj9" => [0, 4, 7, 11, 2],
    "sus" => [0, 5, 7],
    "dim" => [0, 3, 6],
    "7alt" => [0, 4, 7, 10, 1],
    "7#11" => [0, 4, 7, 10, 6],
    "m11" => [0, 3, 7, 10, 5],
    "sus4" => [0, 5, 7, 10],
    "aug" => [0, 4, 8],
    "6" => [0, 4, 7, 9]
  }.freeze

  VOICING_STYLES = %i[close spread drop2 drop3 quartal cluster].freeze

  def load_sonic_profiles
    return @sonic_profiles if defined?(@sonic_profiles) && @sonic_profiles
    return @sonic_profiles = {} unless File.exist?(SONIC_YAML)

    require "yaml"
    data = YAML.safe_load_file(SONIC_YAML, permitted_classes: [Symbol], aliases: true) || {}
    @sonic_profiles = (data["profiles"] || {}).transform_keys(&:to_sym)
  rescue StandardError => e
    warn "sonic profile load failed: #{e.message}"
    @sonic_profiles = {}
  end

  def sonic_profile_for(track)
    key = TRACK_SONIC_MAP.fetch(track.to_sym, nil)
    return nil unless key
    load_sonic_profiles[key]
  end

  def style_family(track, feel: nil)
    return :flylo if FLYLO_TRACKS.include?(track.to_sym) || feel == :loose_pocket
    return :dilla if DILLA_TRACKS.include?(track.to_sym) ||
                     %i[timeless organic chromatic_planing syncopated_slash_ninth].include?(feel)
    return :madlib if track.to_s.include?("madlib")
    :default
  end

  def resolve_bpm(preset, track, sonic)
    env_bpm = ENV["BPM"]&.to_f
    return env_bpm if env_bpm&.positive?
    sonic_bpm = sonic&.dig("synth", "bpm")&.to_f
    return sonic_bpm if sonic_bpm&.positive?
    preset.fetch(:bpm, DEFAULT_BPM).to_f
  end

  def resolve_swing(preset, sonic, time_offset)
    return 62.5 if ENV["GOLDEN_SWING"] == "1"
    return ENV["SWING"].to_f if ENV["SWING"]
    sonic_swing = sonic&.dig("synth", "swing")&.to_f
    base = if sonic_swing && sonic_swing < 1.0
             (sonic_swing * 100.0) + time_offset
           else
             preset.fetch(:swing, 58).to_f + time_offset
           end
    base.clamp(0.0, 72.0)
  end

  def enhanced_resolve_config
    track = (ENV["TRACK"] || "timeless").to_s.downcase.tr("-", "_").to_sym
    preset = TRACK_PRESETS.fetch(track, TRACK_PRESETS[:timeless])
    prog = (ENV["PROGRESSION"] || preset.fetch(:progression, track)).to_s.downcase.tr("-", "_").to_sym
    sonic = sonic_profile_for(track)
    feel = preset[:feel] || :default
    family = style_family(track, feel:)
    {
      track: track,
      bpm: resolve_bpm(preset, track, sonic),
      progression: prog,
      chord_bars: preset.fetch(:chord_bars, 4),
      phrase_bars: preset[:phrase_bars],
      swing: resolve_swing(preset, sonic, time_of_day_swing_offset),
      feel: feel,
      stereo_pan: preset[:stereo_pan] || false,
      timing: preset[:timing],
      quintuplet: ENV["QUINTUPLET"] ? ENV["QUINTUPLET"] != "0" : (preset[:quintuplet] || false),
      sonic: sonic,
      style_family: family,
      sidechain: ENV["SIDECHAIN"] != "0" && (family == :flylo || preset[:sidechain] || sonic&.dig("synth", "sidechain_pump")),
      no_quantize: ENV["NO_QUANTIZE"] == "1" || (family == :flylo && ENV["NO_QUANTIZE"] != "0"),
      golden_swing: ENV["GOLDEN_SWING"] == "1",
      voicing: (ENV["VOICING"] || preset[:voicing] || (family == :flylo ? :quartal : :spread)).to_sym,
      engine_progression: sonic&.dig("harmonic", "engine_progression")&.to_sym,
      half_time_bars: preset[:half_time_bars],
      intro_bars: preset.fetch(:intro_bars, family == :flylo ? 8 : 4),
      master_lufs: MASTER_LUFS_BY_STYLE.fetch(family, MASTER_LUFS_BY_STYLE[:default]),
      master_lra: LRA_BY_STYLE.fetch(family, LRA_BY_STYLE[:default])
    }
  end

  def chord_from_quality(root_hz, quality, voices: 5)
    intervals = CHORD_TEMPLATES_EXT.fetch(quality) { CHORD_TEMPLATES.fetch(quality) }
    hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
    extra = intervals.max + 2
    hz << (root_hz * (2**(extra / 12.0))).round(2) while hz.length < voices
    hz.sort.first(voices)
  end

  def apply_voicing(hz, style)
    midis = hz.map { |h| hz_to_midi(h) }.sort
    case style
    when :quartal
      base = midis.first
      [base, base + 5, base + 10, base + 15, base + 17].map { |m| midi_to_hz(m) }
    when :drop2
      return hz if midis.length < 4
      ordered = midis
      drop = ordered.dup
      drop[-2] = ordered[-2] - 12.0 if ordered[-2] > 48
      drop.map { |m| midi_to_hz(m) }
    when :drop3
      return hz if midis.length < 4
      ordered = midis
      drop = ordered.dup
      drop[-3] = ordered[-3] - 12.0 if ordered[-3] > 48
      drop.map { |m| midi_to_hz(m) }
    when :spread
      base = midis.first
      [base, base + 7, base + 11, base + 14, base + 17].map { |m| midi_to_hz(m).clamp(80.0, 1200.0) }
    when :cluster
      base = midis.first
      [base, base + 1, base + 2, base + 6, base + 7].map { |m| midi_to_hz(m) }
    else
      hz
    end.uniq.first(5)
  end

  def decorate_chord(chord, voicing: :spread)
    hz = apply_voicing(chord[:hz], voicing)
    { name: chord[:name], hz: hz }
  end

  def generate_coltrane_changes(root_hz:, length: 8, seed: nil)
    rng = seed ? Random.new(seed) : Random.new
    offsets = [0, 4, 8] # major thirds
    start = offsets.sample(random: rng)
    Array.new(length) do |i|
      semitone = start + offsets[i % 3]
      root = root_hz * (2**(semitone / 12.0))
      q = %w[maj9 m9 7].sample(random: rng)
      { name: "coltrane#{semitone}#{q}", hz: chord_from_quality(root, q) }
    end
  end

  def generate_backdoor_progression(root_hz:, mode: :minor, length: 8, seed: nil)
    rng = seed ? Random.new(seed) : Random.new
    semitones = SCALE_SEMITONES.fetch(mode)
    degree = 1
    transitions = DEGREE_TRANSITIONS.merge(5 => { 1 => 2, 6 => 4, 4 => 1, 3 => 3 })
    quality_for = SCALE_DEGREE_QUALITY.fetch(mode).merge(4 => "7alt", 7 => "7#11")
    Array.new(length) do
      quality = quality_for.fetch(degree, "m9")
      quality = "7alt" if degree == 5 && rng.rand < 0.35
      chord_root = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
      chord = { name: "bk#{degree}#{quality}", hz: chord_from_quality(chord_root, quality) }
      degree = weighted_pick(rng, transitions.fetch(degree, { 1 => 1 }))
      chord
    end
  end

  def generate_slash_progression(root_hz:, mode: :minor, length: 8, seed: nil)
    rng = seed ? Random.new(seed) : Random.new
    pedal = root_hz
    semitones = SCALE_SEMITONES.fetch(mode)
    degree = 0
    Array.new(length) do
      step = semitones[degree % semitones.length] + (degree / semitones.length) * 12
      upper_root = root_hz * (2**(step / 12.0))
      q = rng.rand < 0.5 ? "maj9" : "m9"
      hz = chord_from_quality(upper_root, q, voices: 4)
      hz[0] = pedal
      degree += weighted_pick(rng, PLANING_STEP_WEIGHTS)
      { name: "slash#{step}#{q}", hz: hz.sort }
    end
  end

  def generate_modal_interchange(root_hz:, mode: :minor, length: 8, seed: nil)
    rng = seed ? Random.new(seed) : Random.new
    pool = mode == :minor ? [1, 4, 5, 6, 3, 2, 7, 4, 6] : [1, 2, 3, 4, 5, 6, 7, 6, 4]
    semitones = SCALE_SEMITONES.fetch(mode)
    borrow = { 4 => "maj9", 6 => "maj9", 3 => "aug", 7 => "dim" }
    Array.new(length) do |i|
      degree = pool[i % pool.length]
      q = borrow[degree] || SCALE_DEGREE_QUALITY.fetch(mode).fetch(degree, "m9")
      q = PLANING_QUALITIES.sample(random: rng) if rng.rand < 0.2
      root = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
      { name: "mod#{degree}#{q}", hz: chord_from_quality(root, q) }
    end
  end

  def passing_cluster_between(a, b, rng)
    mid = (a[:hz].first + b[:hz].first) / 2.0
    hz = [mid, mid * 1.059, mid * 1.122, mid * 1.189, mid * 1.335].map { |f| f.round(2) }
    { name: "pass_cluster", hz: hz }
  end

  # A fugue's recapitulation restating the exposition note-for-note in the
  # same voicing reads as static — real recaps land the same material in a
  # different register/spacing so the return feels like arrival, not replay.
  CONTRAST_VOICINGS = {
    quartal: :drop2, drop2: :cluster, cluster: :spread,
    spread: :quartal, drop3: :spread
  }.freeze

  def enrich_progression(pads, cfg, phases: [])
    return pads if pads.empty?
    rng = Random.new((cfg[:track].to_s.hash.abs % 100_000) + pads.length)
    voicing = cfg[:voicing]
    recap_voicing = CONTRAST_VOICINGS.fetch(voicing, :spread)
    out = []
    pads.each_with_index do |chord, i|
      chord_voicing = phases[i] == :recapitulation ? recap_voicing : voicing
      out << decorate_chord(chord, voicing: chord_voicing)
      out << passing_cluster_between(out.last, pads[(i + 1) % pads.length], rng) if rng.rand < 0.12 && i < pads.length - 1
    end
    # Progression mutation on fugue repeats — transpose every 8 chords
    out.map.with_index do |c, i|
      shift = (i / 8) % 2 == 1 ? 2 : 0
      next c if shift.zero?
      { name: "#{c[:name]}_t#{shift}", hz: c[:hz].map { |h| (h * (2**(shift / 12.0))).round(2) } }
    end
  end

  def progression_from_engine(sonic, _fallback_mode)
    chord_names = sonic&.dig("harmonic", "engine_chords")
    if chord_names&.any?
      return chord_names.map do |n|
        PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n }
      end.compact
    end
    name = sonic&.dig("harmonic", "engine_progression")&.to_sym
    return nil unless name && CHORD_PROGRESSIONS.key?(name)
    CHORD_PROGRESSIONS.fetch(name).map do |n|
      PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n }
    end.compact
  end

  def arrange_fugue_progression(pads, needed_chords, cfg)
    return pads if pads.empty?
    hook = pads
    exposition = [(needed_chords * 0.25 / hook.length).ceil, 2].max
    development_len = [(needed_chords * 0.35).round, 2].max
    recapitulation = [(needed_chords * 0.25).round, hook.length].max
    coda = [needed_chords - (exposition * hook.length) - development_len - recapitulation, 0].max

    dev_root = hook.last[:hz].min * (cfg[:style_family] == :flylo ? (2**(3.0 / 12.0)) : 1.0)
    dev_style = case cfg[:progression]
                when :planing then :planing
                when :chromatic_mediant then :chromatic_mediant
                else :functional
                end
    development = case dev_style
                  when :planing
                    generate_planing_progression(root_hz: dev_root, length: development_len, seed: cfg[:track].hash.abs)
                  when :chromatic_mediant
                    generate_chromatic_mediant_progression(root_hz: dev_root, length: development_len, seed: cfg[:track].hash.abs)
                  else
                    generate_progression(root_hz: dev_root, mode: :minor, length: development_len, seed: cfg[:track].hash.abs)
                  end

    intro_hook = Array.new(exposition) { hook }.flatten
    recap = hook.first(recapitulation)
    outro = coda.positive? ? (hook * (coda / hook.length.to_f).ceil).first(coda) : []
    arranged = intro_hook + development + recap + outro

    phases = []
    intro_hook.length.times { phases << :exposition }
    development.length.times { phases << :development }
    recap.length.times { phases << :recapitulation }
    outro.length.times { phases << :coda }

    [arranged.first(needed_chords), phases.first(needed_chords)]
  end

  def log_progression_phases!(track, bpm, pads, phases)
    return if pads.empty?
    lines = pads.each_with_index.map do |chord, i|
      phase = phases&.[](i) || "—"
      notes = chord[:hz].map { |hz| nearest_note(hz) }.join(" ")
      "  [#{phase}] #{chord[:name]}: #{notes}"
    end
    File.open(PROGRESSION_LOG_PATH, "a") do |f|
      f.puts "=== #{Time.now.iso8601} — TRACK=#{track} BPM=#{bpm.round(1)} (fugue) ==="
      f.puts lines
      f.puts
    end
  rescue StandardError => e
    warn "progression log write failed: #{e.message}"
  end

  def cyclic_timing_offset(role, bar_index, step_index, timing, beat_p, cycle: 4)
    range = timing&.fetch(role, nil) || MICROTIMING_MS.fetch(role)
    cyclic_bar = bar_index % cycle
    seed = (cyclic_bar * 97) + (step_index * 31) + role.hash.abs
    raw = range.begin + (seed % (range.end - range.begin + 1))
    return raw unless beat_p
    tick_ms = (beat_p * 1000.0) / 96.0
    quantized = ((raw / tick_ms).round * tick_ms).round(3)
    if ENV["NO_QUANTIZE"] == "1"
      jitter = Random.new(seed).rand(-2.0..2.0)
      return (quantized + jitter).round(3)
    end
    quantized
  end

  def section_density(bar, n_bars)
    sec = dilla_section(bar, n_bars)
    case sec
    when :intro then 0.55
    when :breakdown then 0.45
    when :build then 0.72 + 0.28 * ((bar - (n_bars * 0.82).to_i).to_f / [n_bars * 0.18, 1].max).clamp(0.0, 1.0)
    when :outro then 0.5
    else 1.0
    end
  end

  def schedule_eclectic_percussion!(events, duration, beat_p, bar_p, cfg, n_bars)
    rng = Random.new(cfg[:track].to_s.hash.abs + 909)
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

    # Clap layer 2&4
    (0...(duration / bar_p).floor).each do |bar|
      base = bar * bar_p
      density = section_density(bar, n_bars)
      next if density < 0.5
      [1, 3].each do |beat|
        t = (base + beat * beat_p).round(6)
        events[:clap] ||= []
        events[:clap] << [t, dilla_velocity(0.42 * density, bar, beat, spread: 0.08), :clap]
      end
    end

    # Rim / brush / woodblock / agogo — FlyLo collage
    (0...(duration / step_p).floor).each do |i|
      bar = (i / 16).floor
      density = section_density(bar, n_bars)
      t = (i * step_p).round(6)
      r = rng.rand
      if family == :flylo
        events[:rim] ||= []
        events[:rim] << [t, dilla_velocity(0.28, bar, i % 16, spread: 0.1), 0.35] if r < 0.04 * density
        events[:glitch] ||= []
        events[:glitch] << [t + rng.rand * step_p * 0.5, dilla_velocity(0.35, bar, i, spread: 0.12), :ind_stab] if r < 0.02
        events[:tabla] ||= []
        events[:tabla] << [t, dilla_velocity(0.32, bar, i, spread: 0.15)] if r < 0.018 * density
        events[:tambourine] ||= []
        events[:tambourine] << [t, dilla_velocity(0.22, bar, i, spread: 0.1)] if i.even? && r < 0.08 * density
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

  def extended_drum_kit(base_kit)
    base_kit.merge(
      rim: synth_rim_sample,
      clap: synth_clap_sample,
      tabla: synth_tabla_sample,
      tambourine: synth_tambourine_sample,
      woodblock: synth_woodblock_sample,
      agogo: synth_agogo_sample,
      ind_kick: load_mono_sample(drum_sample_path("ind_kick.wav")),
      ind_clap: load_mono_sample(drum_sample_path("ind_clap.wav")),
      ind_hat: load_mono_sample(drum_sample_path("ind_hat.wav")),
      ind_stab: load_mono_sample(drum_sample_path("ind_stab.wav"))
    )
  rescue StandardError
    base_kit
  end

  def drum_bus_mapping
    {
      kick: :kick, snare: :snare, ghost: :ghost, hat: :hat, open: :open_hat,
      bass: :bass_43, sub_osc: :bass_43, poly: :ghost, shaker: :shaker, cowbell: :cowbell,
      poly5: :rim, clap: :clap, rim: :rim, glitch: :ind_stab, tabla: :tabla,
      tambourine: :tambourine, woodblock: :woodblock, agogo: :agogo
    }
  end

  def sonic_pad_lowpass(sonic)
    sonic&.dig("synth", "pad_lowpass_hz")&.to_i || 2900
  end

  def sonic_vinyl_level(sonic)
    sonic&.dig("synth", "vinyl_noise")&.to_f || 0.18
  end

  def sonic_bass_shelf(sonic)
    sonic&.dig("synth", "bass_shelf_db")&.to_f || 6.0
  end

  def build_harm_bus_filter(idx, duration, _cfg, sonic, harm_fade_start, harm_fade_dur, beat_p, _n_bars)
    lp = sonic_pad_lowpass(sonic)
    shelf = sonic_bass_shelf(sonic)
    build_start = (duration * 0.82).round(2)
    outro_fade = (beat_p * 4.0 * 4).round(2)
    "[#{idx}:a]aformat=channel_layouts=stereo,volume=#{ENV['DEBUG_HARM_WEIGHT'] || '1.0'}," \
      "equalizer=f=95:t=h:w=140:g=-4.5,equalizer=f=1800:t=h:w=1600:g=1.4," \
      "equalizer=f=#{lp}:t=o:w=1.2:g=-1.5," \
      "equalizer=f=80:t=o:w=1:g=#{shelf}," \
      "afade=t=in:st=#{harm_fade_start}:d=#{harm_fade_dur}," \
      "afade=t=out:st=#{(duration - outro_fade).round(2)}:d=#{outro_fade}," \
      "equalizer=f=800:t=h:w=600:g=-4:enable='between(t,#{build_start},#{duration})'[harm]"
  end

  def flylo_sidechain_filters(drum_label: "[drums]", harm_label: "[harm]")
    [
      "#{drum_label}asplit=2[dr_dry][dr_sc]",
      "#{harm_label}[dr_sc]sidechaincompress=threshold=-22dB:ratio=6:attack=0.75:release=14:level_sc=0.9[harm_sc]",
      "[dr_dry][harm_sc]amix=inputs=2:weights=1.0 1.6:duration=first:normalize=0[sc_mix]"
    ]
  end

  def build_drum_bus_filter(cfg, sonic, duration: nil)
    base = cfg[:style_family] == :dilla ? { bits: 11, samples: 1.5, mix: 0.22 } : { bits: 8, samples: 1.2, mix: 0.12 }
    haas = cfg[:style_family] == :flylo ? ",adelay=0|12" : ""
    # Grit as a per-track compositional choice, not a fixed mix-bus setting
    # — cleaner through the exposition, dirtiest through the development
    # section, pulled back as the build lands. A producer varying the dirt
    # on purpose, not one static crush knob for the whole record.
    crush =
      if duration && duration > 20
        third = (duration / 3.0).round(2)
        [
          "acrusher=bits=#{base[:bits] + 2}:samples=#{base[:samples]}:mix=#{(base[:mix] * 0.5).round(2)}:enable='lt(t,#{third})'",
          "acrusher=bits=#{base[:bits]}:samples=#{base[:samples]}:mix=#{(base[:mix] * 1.4).clamp(0.0, 0.6).round(2)}:enable='between(t,#{third},#{(third * 2).round(2)})'",
          "acrusher=bits=#{base[:bits] + 1}:samples=#{base[:samples]}:mix=#{base[:mix]}:enable='gte(t,#{(third * 2).round(2)})'"
        ].join(",") + ","
      else
        "acrusher=bits=#{base[:bits]}:samples=#{base[:samples]}:mix=#{base[:mix]},"
      end
    "[0:a]aformat=channel_layouts=stereo,volume=#{ENV['DEBUG_DRUM_WEIGHT'] || '0.55'}," \
      "equalizer=f=480:t=h:w=420:g=-2.8,#{crush}" \
      "equalizer=f=58:t=o:w=0.8:g=#{cfg[:style_family] == :dilla ? 2.5 : 1.2}#{haas}[drums]"
  end

  def build_up_filter_enhanced(input_tag, duration, out_tag: "built")
    start_t = (duration * 0.82).round(2)
    "[#{input_tag}]" \
      "equalizer=f=4500:t=h:w=5000:g=3.5:enable='gte(t,#{start_t})'," \
      "equalizer=f=220:t=o:w=1.8:g=2.5:enable='gte(t,#{start_t})'[#{out_tag}]"
  end

  def true_peak_guard_for_style(input_tag, cfg, out_tag: "out")
    lufs = cfg[:master_lufs] || MASTER_TARGET_LUFS
    lra = cfg[:master_lra] || MASTER_TARGET_LRA
    if ENV["DEBUG_NO_LOUDNORM"]
      return "[#{input_tag}]alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
    end
    "[#{input_tag}]loudnorm=I=#{lufs}:TP=#{TRUE_PEAK_CEILING_DB}:LRA=#{lra}," \
      "aresample=#{SAMPLE_RATE}," \
      "alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
  end

  def master_bus_filters_enhanced(input_tag, cfg:, duration: nil, ir_input_idx: nil)
    unless sonitex_enabled?
      filt = ["[#{input_tag}]acompressor=threshold=-20dB:ratio=2:attack=25:release=120:makeup=1.5[premaster0]"]
      filt << mix_bass_chord_balance_filter("premaster0", out_tag: "premaster")
      filt << sub_bass_mono_filter("premaster", out_tag: "monobassed")
      filt << analog_drift_filter("monobassed", out_tag: "drifted")
      filt << mood_darken_filter("drifted", out_tag: "darkened")
      reverb_out = "darkened"
      if ir_input_idx
        filt << convolution_reverb_filter("darkened", ir_input_idx, mix: cfg[:style_family] == :flylo ? 0.22 : 0.16, out_tag: "reverbed")
        reverb_out = "reverbed"
      end
      if duration
        filt << build_up_filter_enhanced(reverb_out, duration, out_tag: "built")
        filt << true_peak_guard_for_style("built", cfg)
      else
        filt << true_peak_guard_for_style(reverb_out, cfg)
      end
      return filt
    end
    s = sonitex_config(track: cfg[:track].to_s)
    variant = analog_resolve_variant(track: cfg[:track].to_s)
    filt = []
    filt.concat(sonitex_tape_filters(input_tag, out_tag: "snx_out"))
    filt.concat(analog_emulation_filters("snx_out", variant, out_tag: "ana_out"))
    filt << "[ana_out]alimiter=limit=#{s[:limit]}:level_out=#{s[:level_out]}[premaster0]"
    filt << mix_bass_chord_balance_filter("premaster0", out_tag: "premaster")
    filt << sub_bass_mono_filter("premaster", out_tag: "monobassed")
    filt << analog_drift_filter("monobassed", out_tag: "drifted")
    filt << mood_darken_filter("drifted", out_tag: "darkened")
    reverb_out = "darkened"
    if ir_input_idx
      filt << convolution_reverb_filter("darkened", ir_input_idx, mix: 0.18, out_tag: "reverbed")
      reverb_out = "reverbed"
    end
    if duration
      filt << break_filter(reverb_out, duration, out_tag: "broke")
      filt << build_up_filter_enhanced("broke", duration, out_tag: "built")
      filt << true_peak_guard_for_style("built", cfg)
    else
      filt << true_peak_guard_for_style(reverb_out, cfg)
    end
    filt
  end

  def motif_from_chord(chord)
    return [0, 1, 2, 1] unless chord && chord[:hz]&.any?
    tones = chord[:hz].sort
    [0, 1, 2, tones.length > 3 ? 3 : 1]
  end

  def lead_events_enhanced(pad_events, cfg)
    events = []
    seed_motif = motif_from_chord(pad_events.first&.dig(2))
    pad_events.each_with_index do |(time, velocity, chord, sustain), i|
      next unless chord && chord[:hz]&.any?
      tones = chord[:hz].sort.map { |hz| hz * 2.0 }
      pattern = case i % 4
                when 0 then seed_motif
                when 1 then invert_motif(seed_motif)
                when 2 then seed_motif.reverse
                else seed_motif + seed_motif.reverse
                end
      step_dur = [(sustain || 1.0) / (pattern.length * 2.0), 0.08].max
      # Augmentation at build phases
      step_dur *= 1.5 if i > pad_events.length * 0.82
      pattern.each_with_index do |degree, step|
        hz = tones[degree % tones.length]
        approach = step.zero? && i.positive? ? hz * (2**(1.0 / 12.0)) : hz
        t = time + 0.05 + step * step_dur
        vel = (velocity * (0.9 - step * 0.05)).clamp(0.2, 1.0)
        pan = cfg[:stereo_pan] ? (step.even? ? -0.4 : 0.4) : 0.0
        events << [t, vel, { name: "lead", hz: [approach] }, step_dur * 0.85, pan]
      end
      next unless i.odd? && i.positive?
      answer_offset = pattern.length * step_dur * 0.5
      pattern.each_with_index do |degree, step|
        hz = tones[degree % tones.length] * 0.5
        t = time + 0.05 + answer_offset + step * step_dur
        vel = (velocity * 0.5).clamp(0.15, 0.6)
        pan = cfg[:stereo_pan] ? (step.even? ? 0.5 : -0.5) : 0.0
        events << [t, vel, { name: "lead_answer", hz: [hz] }, step_dur * 0.7, pan]
      end
    end
    events
  end

  def warm_dilla_pad_post_enhanced(path, sonic, cfg)
    return path unless tool_available?("ffmpeg")
    lp = sonic_pad_lowpass(sonic)
    tmp = "#{path}.pad_tmp.wav"
    filt = [
      "aformat=channel_layouts=stereo",
      "lowpass=f=#{lp}:width_type=q:width=0.82",
      "equalizer=f=280:t=o:w=1.1:g=3.2",
      "equalizer=f=1100:t=o:w=0.9:g=-1.6",
      "equalizer=f=4200:t=o:w=1.2:g=-2.4",
      ("tremolo=f=4.5:d=0.12" if cfg[:style_family] == :dilla),
      "aphaser=speed=0.11:decay=0.44",
      "aecho=0.44:0.5:130|210:0.30|0.16",
      "chorus=0.5:0.7:35|45:0.25|0.2:0.3|0.25:1.2|1.6",
      "vibrato=f=0.28:d=0.016",
      "acompressor=threshold=-26dB:ratio=2.1:attack=42:release=200:makeup=2.2",
      "volume=1.28",
      "alimiter=limit=0.97:level_out=0.99"
    ].compact.join(",")
    sh! "ffmpeg", "-y", "-i", path, "-af", filt, "-c:a", "pcm_s16le", tmp
    FileUtils.mv(tmp, path)
    path
  end

  GENERATED_STYLE_ROUTES = {
    coltrane: :generate_coltrane_changes,
    backdoor: :generate_backdoor_progression,
    slash: :generate_slash_progression,
    modal_interchange: :generate_modal_interchange
  }.freeze

  def route_generated_style(style, root_hz:, mode:, length:, seed:)
    meth = GENERATED_STYLE_ROUTES[style]
    return send(meth, root_hz:, mode:, length:, seed:) if meth
    nil
  end
end