# frozen_string_literal: true

# Researched chord progressions, BPM, and swing from J Dilla, Flying Lotus,
# and Madlib — source: production DNA reference (Fantastic Vol. 2, Donuts,
# Madvillainy, Los Angeles, Voodoo).
module DillaProducerDNA
  CHORD_TEMPLATES = {
    "maj" => [0, 4, 7],
    "min" => [0, 3, 7],
    "7" => [0, 4, 7, 10],
    "maj7" => [0, 4, 7, 11],
    "m7" => [0, 3, 7, 10],
    "m9" => [0, 3, 7, 10, 2],
    "maj9" => [0, 4, 7, 11, 2],
    "6" => [0, 4, 7, 9],
    "m11" => [0, 3, 7, 10, 5]
  }.freeze

  NOTE_PC = {
    "C" => 0, "B#" => 0, "Db" => 1, "C#" => 1, "D" => 2, "Eb" => 3, "D#" => 3,
    "E" => 4, "Fb" => 4, "F" => 5, "Gb" => 6, "F#" => 6, "G" => 7, "Ab" => 8,
    "G#" => 8, "A" => 9, "Bb" => 10, "A#" => 10, "B" => 11, "Cb" => 11
  }.freeze

  DILLA_TIMING = {
    snare: -22..-10, ghost: -12..10, hat_down: -2..4, hat_up: 12..24,
    kick_anchor: 4..10, kick_sync: 8..18, bass: 24..38, pad: 4..14
  }.freeze

  FLYLO_TIMING = {
    snare: -26..-12, ghost: -8..14, hat_down: 4..10, hat_up: 16..32,
    kick_anchor: 2..8, kick_sync: 6..16, bass: 22..42, pad: 6..18
  }.freeze

  MADLIB_TIMING = {
    snare: -20..-8, ghost: -6..16, hat_down: 0..8, hat_up: 10..22,
    kick_anchor: 3..9, kick_sync: 7..16, bass: 20..36, pad: 2..12
  }.freeze

  # RG-69 Lo-Fi Drum Machine — exact Slum Village voicings + MPC drum grids.
  RG69_CHORDS = {
    "Bbm" => { name: "Bb minor", hz: [233.08, 277.18, 349.23] },
    "Ab" => { name: "Ab major", hz: [207.65, 261.63, 311.13] },
    "Fm7" => { name: "F minor 7", hz: [174.61, 207.65, 261.63, 311.13] },
    "Fm" => { name: "F minor", hz: [174.61, 207.65, 261.63] },
    "Cm" => { name: "C minor", hz: [130.81, 155.56, 196.00] },
    "Gm" => { name: "G minor", hz: [196.00, 233.08, 293.66] },
    "Ebmaj7" => { name: "Eb major 7", hz: [155.56, 196.00, 233.08, 293.66] },
    "Db" => { name: "Db major", hz: [138.59, 174.61, 207.65] },
    "Dbmaj7" => { name: "Db major 7", hz: [138.59, 174.61, 207.65, 261.63] },
    "Cm7" => { name: "C minor 7", hz: [130.81, 155.56, 196.00, 233.08] },
    "Bbm7" => { name: "Bb minor 7", hz: [116.54, 138.59, 174.61, 207.65] },
    "Dm" => { name: "D minor", hz: [146.83, 174.61, 220.00] },
    "Am" => { name: "A minor", hz: [110.00, 130.81, 164.81] }
  }.freeze

  # 16-step grids: [kick, snare, hat, clap, perc] — swing % and MPC humanize ticks.
  RG69_DRUM_PRESETS = {
    dilla_slight: {
      swing: 57, humanize: 2, bpm: 95,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 10], claps: [4, 12], perc: [3, 11]
    },
    dilla_drunk: {
      swing: 62, humanize: 4, bpm: 92,
      kicks: [0, 3, 6, 10, 13], snares: [4, 7, 12], hats: [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15],
      ghosts: [5, 14], claps: [12], perc: [2, 10, 15]
    },
    madlib_dusty: {
      swing: 60, humanize: 3, bpm: 93,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [1, 3, 5, 7, 9, 11, 13, 15],
      ghosts: [6, 14], claps: [4, 12], perc: [6, 14]
    },
    flylo_abstract: {
      swing: 54, humanize: 5, bpm: 84,
      kicks: [0, 5, 8, 13], snares: [2, 6, 10, 15], hats: [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15],
      ghosts: [7, 13], claps: [7, 13], perc: [1, 5, 8, 12]
    },
    mpc3000: {
      swing: 62, humanize: 2, bpm: 90,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 9], claps: [4, 12], perc: [3, 11]
    },
    sp303: {
      swing: 58, humanize: 2, bpm: 96,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [1, 3, 5, 7, 9, 11, 13, 15],
      ghosts: [], claps: [], perc: [6, 14]
    },
    sp1200: {
      swing: 54, humanize: 1, bpm: 90,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 10], claps: [4, 12], perc: []
    }
  }.freeze

  RG69_LOFI = {
    bit_depth: 12, vinyl: 0.40, pad_lowpass_hz: 3200, master_lowpass_hz: 2800,
    pad_attack_ms: 800, pad_release_ms: 2000, filter_cutoff_hz: 12_000
  }.freeze

  # track_id => metadata + chord symbol list (beautiful maj7/m9 voicings)
  PRODUCER_TRACKS = {
    time_donut: {
      producer: :dilla, album: "Donuts", title: "Donut of the Heart (Time)",
      key: "Ab / Fm", bpm: 94, swing: 54, chord_bars: 2, phrase_bars: 8,
      feel: :dilla_slight, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, progression: :time_donut,
      chords: %w[Dbmaj7 Cm7 Fm7 Bbm7],
      timing: DILLA_TIMING
    },
    fall_in_love: {
      producer: :dilla, album: "Fantastic Vol. 2", title: "Fall in Love",
      key: "F minor", bpm: 91, swing: 57, chord_bars: 2, phrase_bars: 8,
      feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, progression: :fall_in_love,
      chords: %w[Bbm Ab Fm7 Fm],
      timing: DILLA_TIMING
    },
    climax: {
      producer: :dilla, album: "Fantastic Vol. 2", title: "Climax",
      key: "E major", bpm: 96, swing: 53, chord_bars: 2, phrase_bars: 8,
      feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, progression: :climax,
      chords: %w[Emaj7 G#m7 G#m7 G#maj7],
      timing: DILLA_TIMING
    },
    get_dis_money: {
      producer: :dilla, album: "Fantastic Vol. 2", title: "Get Dis Money",
      key: "C# minor", bpm: 90, swing: 55, chord_bars: 2, phrase_bars: 8,
      feel: :dilla_slight, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, progression: :get_dis_money,
      chords: %w[C#m9 G#m9 A#7 C#maj9],
      timing: DILLA_TIMING
    },
    thelonious: {
      producer: :dilla, album: "Fantastic Vol. 2", title: "Thelonius",
      key: "Eb minor", bpm: 92, swing: 57, chord_bars: 4, phrase_bars: 8,
      feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk, progression: :thelonious,
      chords: %w[Ebm7 Bbm7],
      timing: DILLA_TIMING
    },
    selfish: {
      producer: :dilla, album: "Fantastic Vol. 2", title: "Selfish",
      key: "G major", bpm: 88, swing: 54, chord_bars: 2, phrase_bars: 8,
      feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, progression: :selfish,
      chords: %w[Cmaj9 Bm7 Am7 D7],
      timing: DILLA_TIMING
    },
    look_of_love: {
      producer: :dilla, album: "Fantastic Vol. 1", title: "Look of Love",
      key: "G major", bpm: 90, swing: 54, chord_bars: 2, phrase_bars: 8,
      feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, progression: :look_of_love,
      chords: %w[Bm7 Bm7 Cmaj9 Em7],
      timing: DILLA_TIMING
    },
    so_far_to_go: {
      producer: :dilla, album: "The Shining", title: "So Far to Go",
      key: "Bb / Dm", bpm: 86, swing: 55, chord_bars: 2, phrase_bars: 8,
      feel: :madlib_dusty, voicing: :spread,
      drum_preset: :madlib_dusty, progression: :so_far_to_go,
      chords: %w[Dm7 Cm7 Fmaj9 Gm7],
      timing: DILLA_TIMING
    },
    flylo_camel: {
      producer: :flylo, album: "Los Angeles", title: "Camel",
      key: "C major", bpm: 84, swing: 54, chord_bars: 2, phrase_bars: 16,
      feel: :flylo_abstract, voicing: :quartal, stereo_pan: true, sidechain: true, intro_bars: 8,
      drum_preset: :flylo_abstract, progression: :flylo_camel,
      chords: %w[Cmaj9 Am9 Fmaj9 G6],
      timing: FLYLO_TIMING
    },
    flylo_roberta: {
      producer: :flylo, album: "Los Angeles", title: "RobertaFlack",
      key: "G major", bpm: 81, swing: 55, chord_bars: 2, phrase_bars: 16,
      feel: :flylo_abstract, voicing: :spread, stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract, progression: :flylo_roberta,
      chords: %w[G6 Em9 Cmaj9 Dmaj9],
      timing: FLYLO_TIMING
    },
    madlib_accordion: {
      producer: :madlib, album: "Madvillainy", title: "Accordion",
      key: "D minor", bpm: 96, swing: 58, chord_bars: 2, phrase_bars: 8,
      feel: :sp303, voicing: :spread,
      drum_preset: :sp303, progression: :madlib_accordion,
      chords: %w[Dm Gm Am],
      timing: MADLIB_TIMING
    },
    neo_soul_pocket: {
      producer: :dilla, album: "Slum Village", title: "Players pocket",
      key: "Dm", bpm: 93, swing: 55, chord_bars: 2, phrase_bars: 16,
      feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, progression: :neo_soul_pocket,
      chords: %w[Dm7 Eb7 Gm7 Am7],
      timing: DILLA_TIMING
    }
  }.freeze

  STREAM_ROTATION = %w[
    time_donut fall_in_love flylo_roberta thelonious selfish
    look_of_love so_far_to_go flylo_camel madlib_accordion
    climax get_dis_money neo_soul_pocket
  ].freeze

  CURATED_PROGRESSIONS = PRODUCER_TRACKS.values.map { |t| t[:progression] }.freeze

  module_function

  def producer_track?(track)
    PRODUCER_TRACKS.key?(track.to_sym)
  end

  def track_entry(track)
    sym = track.to_sym
    sym = :time_donut if sym == :timeless
    PRODUCER_TRACKS[sym]
  end

  def track_preset(track)
    entry = track_entry(track)
    return nil unless entry
    preset = entry.slice(:bpm, :chord_bars, :phrase_bars, :swing, :feel, :voicing, :quintuplet,
                         :stereo_pan, :sidechain, :intro_bars, :half_time_bars, :timing, :drum_preset)
                  .merge(progression: entry[:progression], producer: entry[:producer])
    drum = RG69_DRUM_PRESETS[entry[:drum_preset]]
    preset[:swing] = drum[:swing] if drum && !ENV["SWING"]
    preset[:bpm] = drum[:bpm] if drum && !ENV["BPM"] && entry[:producer] == :dilla
    preset
  end

  def progression_for(track)
    entry = track_entry(track)
    return nil unless entry
    entry[:chords].map { |sym| chord_from_symbol(sym) }
  end

  def drum_pattern_set(preset_key)
    p = RG69_DRUM_PRESETS[preset_key]
    return nil unless p
    {
      kicks: [p[:kicks]],
      snares: [p[:snares]],
      hats: [p[:hats]],
      ghosts: [p[:ghosts]],
      opens: [6, 14],
      claps: [p[:claps]],
      perc: [p[:perc]],
      swing: p[:swing],
      humanize: p[:humanize]
    }
  end

  def humanize_ms(bpm, ticks = 2)
    # MPC3000 PPQN=96: one tick ≈ one 96th of a quarter note.
    beat_ms = 60_000.0 / bpm
    (beat_ms / 96.0 * ticks).round(2)
  end

  def chord_from_symbol(sym)
    sym = sym.to_s.strip
    if (rg = RG69_CHORDS[sym])
      return { name: sym, hz: rg[:hz].dup }
    end
    m = sym.match(/\A([A-G][#b]?)(m9|m7|m11|maj9|maj7|m|7|6)?\z/i)
    raise ArgumentError, "bad chord symbol: #{sym}" unless m
    root_name = m[1][0].upcase + m[1][1..]
    suffix = m[2].to_s.downcase
    quality = case suffix
              when "" then "maj9"
              when "m" then "m9"
              when "maj7" then "maj7"
              when "maj9" then "maj9"
              when "m7" then "m7"
              when "m9" then "m9"
              when "7" then "7"
              when "6" then "6"
              when "m11" then "m11"
              else "maj9"
              end
    root_hz = note_hz(root_name, octave: 3)
    hz = build_voicing(root_hz, quality)
    { name: sym, hz: hz }
  end

  def note_hz(name, octave: 3)
    base = name[0].upcase
    acc = name[1..] || ""
    acc = acc.tr("♯", "#").tr("♭", "b")
    pc = NOTE_PC.fetch("#{base}#{acc}")
    midi = 12 + (octave * 12) + pc
    (440.0 * (2.0**((midi - 69.0) / 12.0))).round(2)
  end

  def build_voicing(root_hz, quality, voices: 4)
    intervals = CHORD_TEMPLATES.fetch(quality) { CHORD_TEMPLATES["maj9"] }
    hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
    extra = intervals.max + 2
    hz << (root_hz * (2**(extra / 12.0))).round(2) while hz.length < voices
    voiced = hz.sort.first(voices)
    # Keep pads in a warm mid register — never sub/bass mud or shrill top.
    midis = voiced.map { |h| 69.0 + 12.0 * Math.log2(h / 440.0) }
    midis = midis.map { |m| m + 12.0 while m < 50.0; m -= 12.0 while m > 76.0; m }
    midis.map { |m| (440.0 * (2.0**((m - 69.0) / 12.0))).round(2) }.uniq.first(voices)
  end

  def mpc_swing_from_sonic_fraction(frac)
    # Inline profiles store 0.16 meaning "Dilla pocket" not 16% swing.
    (50.0 + frac.to_f * 25.0).clamp(52.0, 62.5)
  end

  def humanize_ticks_for(track)
    entry = track_entry(track)
    return 0 unless entry
    key = entry[:drum_preset] || entry[:feel]
    RG69_DRUM_PRESETS.dig(key, :humanize) || 0
  end

  def lofi_sonic_overlay(_track = nil)
    l = RG69_LOFI
    {
      "pad_lowpass_hz" => l[:pad_lowpass_hz],
      "master_lowpass_hz" => l[:master_lowpass_hz],
      "vinyl_noise" => (l[:vinyl] * 0.2).round(3),
      "crush_mix" => ((16 - l[:bit_depth]).to_f / 16.0 * 0.35).round(2),
      "pad_attack_ms" => l[:pad_attack_ms],
      "pad_release_ms" => l[:pad_release_ms]
    }
  end
end